-- Copyright 2026 Ринат (markov_chain)
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
-- 
-- http://www.apache.org/licenses/LICENSE-2.0
-- 
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
--------------------------------------------------------------------------------
-- markov_chain_reports_functions.sql
-- version 26.3
--------------------------------------------------------------------------------
-- Функции для отчетов по цепи Маркова 
--------------------------------------------------------------------------------

-- ============================================================================
-- Функция: build_profile_hourly
-- Назначение: часовое агрегирование профиля производительности.
-- ============================================================================
CREATE OR REPLACE FUNCTION build_profile_hourly(
    p_period_start timestamptz DEFAULT date_trunc('month', now())
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    -- ========================================================================
    -- Шаг 1: базовые метрики из cluster_stat_median
    -- ========================================================================
    INSERT INTO profile_hourly (
        bucket_hour, avg_speed, avg_waitings, avg_correlation,
        avg_slope_speed, avg_slope_waitings
    )
    SELECT
        date_trunc('hour', m.curr_timestamp)                                AS bucket_hour,
        avg(m.curr_op_speed)                                                AS avg_speed,
        avg(m.curr_waitings)                                                AS avg_waitings,
        COALESCE(corr(m.curr_op_speed, m.curr_waitings), 0)                 AS avg_correlation,
        COALESCE(regr_slope(m.curr_op_speed,
                            extract(epoch FROM m.curr_timestamp)), 0)       AS avg_slope_speed,
        COALESCE(regr_slope(m.curr_waitings,
                            extract(epoch FROM m.curr_timestamp)), 0)       AS avg_slope_waitings
    FROM cluster_stat_median m
    WHERE m.curr_timestamp >= p_period_start
    GROUP BY date_trunc('hour', m.curr_timestamp)
    ON CONFLICT (bucket_hour) DO UPDATE SET
        avg_speed          = EXCLUDED.avg_speed,
        avg_waitings       = EXCLUDED.avg_waitings,
        avg_correlation    = EXCLUDED.avg_correlation,
        avg_slope_speed    = EXCLUDED.avg_slope_speed,
        avg_slope_waitings = EXCLUDED.avg_slope_waitings,
        created_at         = now();

    -- ========================================================================
    -- Шаг 2: JS-дивергенция из profile_comparison_log
    -- ========================================================================
    UPDATE profile_hourly p
    SET avg_js_divergence = s.avg_js,
        max_js_divergence = s.max_js,
        created_at        = now()
    FROM (
        SELECT
            date_trunc('hour', pcl.current_window_end) AS hour_ts,
            avg(pcl.js_divergence)                     AS avg_js,
            max(pcl.js_divergence)                     AS max_js
        FROM profile_comparison_log pcl
        WHERE pcl.current_window_end >= p_period_start
          AND pcl.js_divergence IS NOT NULL
        GROUP BY date_trunc('hour', pcl.current_window_end)
    ) s
    WHERE p.bucket_hour = s.hour_ts;

    -- ========================================================================
    -- Шаг 3a (PRIMARY): энтропия и доля критических состояний из profile_aggregated.
    -- Если источника нет — значения остаются NULL, шаг 3b подставит fallback.
    -- ========================================================================
    UPDATE profile_hourly p
    SET avg_entropy          = s.avg_entropy,
        critical_state_share = s.critical_share,
        created_at           = now()
    FROM (
        SELECT
            date_trunc('hour', pa.ts)          AS hour_ts,
            avg(pa.entropy)                    AS avg_entropy,
            avg(pa.critical_ratio)             AS critical_share
        FROM profile_aggregated pa
        WHERE pa.ts >= p_period_start
          AND pa.profile_type = 'operational'
        GROUP BY date_trunc('hour', pa.ts)
    ) s
    WHERE p.bucket_hour = s.hour_ts;

    -- ========================================================================
    -- Шаг 3b (FALLBACK): если profile_aggregated пуст — вычисляем из transition_log.
    -- Работает только для часов, где avg_entropy = NULL после шага 3a.
    -- Dwell-time распределение по to_state внутри каждого часа, без зависимостей
    -- от state_descriptions (state_id берётся напрямую из transition_log).
    -- ========================================================================
    UPDATE profile_hourly p
    SET avg_entropy          = s.entropy,
        critical_state_share = s.critical_ratio,
        created_at           = now()
    FROM (
        WITH dwell AS (
            SELECT
                tl.ts,
                tl.to_state,
                date_trunc('hour', tl.ts)                                        AS hour_ts,
                EXTRACT(epoch FROM (
                    LEAST(
                        LEAD(tl.ts) OVER (ORDER BY tl.ts, tl.id),
                        date_trunc('hour', tl.ts) + interval '1 hour',
                        now()
                    ) - tl.ts
                ))                                                               AS dwell_sec
            FROM transition_log tl
            WHERE tl.ts >= p_period_start - interval '1 hour'
              AND tl.ts <  now()  + interval '1 hour'
        ),
        hourly AS (
            SELECT
                hour_ts AS ts,
                to_state,
                SUM(GREATEST(dwell_sec, 0)) AS sec
            FROM dwell
            WHERE hour_ts >= p_period_start
              AND GREATEST(dwell_sec, 0) > 0
            GROUP BY hour_ts, to_state
        ),
        probs AS (
            SELECT
                ts,
                to_state,
                sec,
                sec / NULLIF(SUM(sec) OVER (PARTITION BY ts), 0) AS pr
            FROM hourly
        )
        SELECT
            ts,
            (-SUM(pr * ln(pr) / ln(2.0)))::real                            AS entropy,
            (SUM(CASE WHEN to_state IN (SELECT state_id FROM critical_states)
                      THEN pr ELSE 0 END))::real                            AS critical_ratio
        FROM probs
        WHERE pr > 0
        GROUP BY ts
    ) s
    WHERE p.bucket_hour = s.ts
      AND p.avg_entropy IS NULL;

    -- ========================================================================
    -- Шаг 4: количество аномалий из anomaly_log
    -- ========================================================================
    UPDATE profile_hourly p
    SET anomaly_count = COALESCE((
            SELECT count(*)::integer
            FROM anomaly_log a
            WHERE date_trunc('hour', a.detected_at) = p.bucket_hour
        ), 0),
        created_at = now()
    WHERE p.bucket_hour >= date_trunc('hour', p_period_start);

    -- ========================================================================
    -- Шаг 5: SICPP активность.
    --   v26.3.1 FIX: интервал активного состояния клиппится по границам часа:
    --      LEAST(COALESCE(next_changed_at, now()), date_trunc('hour', changed_at) + 1h)
    --      − GREATEST(changed_at, date_trunc('hour', changed_at))
    --   Это устраняет значения > 100 % при пересечении сигналом границы часа
    --   и при последней активной строке без next_changed_at (COALESCE → now()).
    -- ========================================================================
    UPDATE profile_hourly p
    SET sicpp_active_share = COALESCE(s.active_share, 0),
        sicpp_activations  = COALESCE(s.activations, 0),
        created_at         = now()
    FROM (
        WITH spans AS (
            SELECT
                changed_at,
                signal_active,
                LEAD(changed_at) OVER (ORDER BY changed_at) AS next_changed_at
            FROM sicpp_history
            WHERE changed_at >= p_period_start
        )
        SELECT
            date_trunc('hour', changed_at) AS hour_ts,
            SUM(
                CASE WHEN signal_active
                     THEN extract(epoch FROM (
                         LEAST(
                             COALESCE(next_changed_at, now()),
                             date_trunc('hour', changed_at) + interval '1 hour'
                         )
                         - GREATEST(changed_at, date_trunc('hour', changed_at))
                     ))
                     ELSE 0
                END
            ) / 3600.0                                                  AS active_share,
            SUM(CASE WHEN signal_active THEN 1 ELSE 0 END)::integer     AS activations
        FROM spans
        GROUP BY date_trunc('hour', changed_at)
    ) s
    WHERE p.bucket_hour = s.hour_ts;

    -- ========================================================================
    -- Шаг 6: C-only активность.
    --   v26.3.1 FIX: аналогично шагу 5 — клиппинг по границам часа.
    -- ========================================================================
    UPDATE profile_hourly p
    SET c_only_active_share = COALESCE(s.active_share, 0),
        c_only_activations  = COALESCE(s.activations, 0),
        created_at          = now()
    FROM (
        WITH spans AS (
            SELECT
                changed_at,
                result_value,
                LEAD(changed_at) OVER (ORDER BY changed_at) AS next_changed_at
            FROM c_only_incident_flag_history
            WHERE changed_at >= p_period_start
        )
        SELECT
            date_trunc('hour', changed_at) AS hour_ts,
            SUM(
                CASE WHEN result_value
                     THEN extract(epoch FROM (
                         LEAST(
                             COALESCE(next_changed_at, now()),
                             date_trunc('hour', changed_at) + interval '1 hour'
                         )
                         - GREATEST(changed_at, date_trunc('hour', changed_at))
                     ))
                     ELSE 0
                END
            ) / 3600.0                                                  AS active_share,
            SUM(CASE WHEN result_value THEN 1 ELSE 0 END)::integer      AS activations
        FROM spans
        GROUP BY date_trunc('hour', changed_at)
    ) s
    WHERE p.bucket_hour = s.hour_ts;

    -- ========================================================================
    -- Шаг 7: sicpp_lead_time_avg (по эпизодам, связанным с инцидентами часа)
    -- ========================================================================
    UPDATE profile_hourly p
    SET sicpp_lead_time_avg = s.avg_lead_time,
        created_at          = now()
    FROM (
        SELECT
            date_trunc('hour', mcpi.start_timepoint) AS hour_ts,
            avg(extract(epoch FROM
                (mcpi.start_timepoint - sifh.episode_started_at)) / 60.0)
                                                     AS avg_lead_time
        FROM markov_chain_performance_incident mcpi
        JOIN sicpp_incident_flag_history sifh
             ON sifh.incident_id = mcpi.id
        WHERE mcpi.start_timepoint >= p_period_start
          AND sifh.reason = 'sicpp_started'
          AND sifh.episode_started_at IS NOT NULL
        GROUP BY date_trunc('hour', mcpi.start_timepoint)
    ) s
    WHERE p.bucket_hour = s.hour_ts;

    -- ========================================================================
    -- Шаг 8: c_only_lead_time_avg
    -- ========================================================================
    UPDATE profile_hourly p
    SET c_only_lead_time_avg = s.avg_lead_time,
        created_at           = now()
    FROM (
        SELECT
            date_trunc('hour', mcpi.start_timepoint) AS hour_ts,
            avg(extract(epoch FROM
                (mcpi.start_timepoint - cih.changed_at)) / 60.0)
                                                     AS avg_lead_time
        FROM markov_chain_performance_incident mcpi
        JOIN c_only_incident_flag_history cih
             ON cih.incident_id = mcpi.id
        WHERE mcpi.start_timepoint >= p_period_start
          AND cih.flag_value = TRUE
        GROUP BY date_trunc('hour', mcpi.start_timepoint)
    ) s
    WHERE p.bucket_hour = s.hour_ts;
END;
$$;

COMMENT ON FUNCTION build_profile_hourly(timestamptz) IS
'v26.3.1. Часовое агрегирование. FIX: (1) sicpp/c_only active_share клиппинг по границам часа → больше нет >100 %; (2) шаг 3b fallback из transition_log, если profile_aggregated пуст; (3) логика остальных шагов без изменений. Идемпотентна.';

-- ============================================================================
-- Функция: build_profile_daily
-- Назначение: суточное агрегирование (метрики качества сигналов за день).
-- ============================================================================
CREATE OR REPLACE FUNCTION build_profile_daily(
    p_period_start timestamptz DEFAULT date_trunc('month', now())
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    -- Шаг 1: базовые метрики из cluster_stat_median
    INSERT INTO profile_daily (
        bucket_day, avg_speed, avg_waitings, avg_correlation,
        avg_slope_speed, avg_slope_waitings
    )
    SELECT
        date_trunc('day', m.curr_timestamp)::date                           AS bucket_day,
        avg(m.curr_op_speed)                                                AS avg_speed,
        avg(m.curr_waitings)                                                AS avg_waitings,
        COALESCE(corr(m.curr_op_speed, m.curr_waitings), 0)                 AS avg_correlation,
        COALESCE(regr_slope(m.curr_op_speed,
                            extract(epoch FROM m.curr_timestamp)), 0)       AS avg_slope_speed,
        COALESCE(regr_slope(m.curr_waitings,
                            extract(epoch FROM m.curr_timestamp)), 0)       AS avg_slope_waitings
    FROM cluster_stat_median m
    WHERE m.curr_timestamp >= p_period_start
    GROUP BY date_trunc('day', m.curr_timestamp)::date
    ON CONFLICT (bucket_day) DO UPDATE SET
        avg_speed          = EXCLUDED.avg_speed,
        avg_waitings       = EXCLUDED.avg_waitings,
        avg_correlation    = EXCLUDED.avg_correlation,
        avg_slope_speed    = EXCLUDED.avg_slope_speed,
        avg_slope_waitings = EXCLUDED.avg_slope_waitings,
        created_at         = now();

    -- Шаг 2: марковские метрики сворачиваем из profile_hourly
    UPDATE profile_daily p
    SET avg_js_divergence    = h.avg_js,
        max_js_divergence    = h.max_js,
        avg_entropy          = h.avg_entropy,
        critical_state_share = h.critical_share,
        anomaly_count        = h.anomaly_count,
        created_at           = now()
    FROM (
        SELECT
            bucket_hour::date                         AS day_ts,
            avg(avg_js_divergence)                    AS avg_js,
            max(max_js_divergence)                    AS max_js,
            avg(avg_entropy)                          AS avg_entropy,
            avg(critical_state_share)                 AS critical_share,
            sum(anomaly_count)::integer               AS anomaly_count
        FROM profile_hourly
        WHERE bucket_hour >= p_period_start
        GROUP BY bucket_hour::date
    ) h
    WHERE p.bucket_day = h.day_ts;

    -- Шаг 3: точность SICPP за день
    UPDATE profile_daily p
    SET sicpp_true_positive_rate = s.tp_rate,
        created_at               = now()
    FROM (
        SELECT
            date_trunc('day', changed_at)::date
                AS day_ts,
            count(*) FILTER (WHERE incident_id IS NOT NULL)::numeric
              / NULLIF(count(*), 0)
                AS tp_rate
        FROM sicpp_incident_flag_history
        WHERE reason = 'sicpp_started'
          AND changed_at >= p_period_start
        GROUP BY date_trunc('day', changed_at)::date
    ) s
    WHERE p.bucket_day = s.day_ts;

    -- Шаг 4: точность C-only за день
    UPDATE profile_daily p
    SET c_only_precision = s.precision,
        created_at       = now()
    FROM (
        SELECT
            date_trunc('day', changed_at)::date
                AS day_ts,
            count(*) FILTER (WHERE incident_id IS NOT NULL)::numeric
              / NULLIF(count(*), 0)
                AS precision
        FROM c_only_incident_flag_history
        WHERE flag_value = TRUE
          AND changed_at >= p_period_start
        GROUP BY date_trunc('day', changed_at)::date
    ) s
    WHERE p.bucket_day = s.day_ts;

    -- Шаг 5: покрытие инцидентов сигналами и ложные эпизоды
    UPDATE profile_daily p
    SET incident_coverage_total      = COALESCE(s.coverage, 0),
        false_positive_episode_count = COALESCE(s.false_positives, 0),
        created_at                   = now()
    FROM (
        WITH incidents AS (
            SELECT mcpi.id, mcpi.start_timepoint
            FROM markov_chain_performance_incident mcpi
            WHERE date_trunc('day', mcpi.start_timepoint)::date >= p_period_start::date
        ),
        per_day AS (
            SELECT
                date_trunc('day', i.start_timepoint)::date
                    AS day_ts,
                count(*)                                  AS total_incidents,
                count(*) FILTER (
                    WHERE EXISTS (
                        SELECT 1 FROM sicpp_history sh
                        WHERE sh.signal_active = TRUE
                          AND sh.changed_at BETWEEN i.start_timepoint - interval '1 hour'
                                                AND i.start_timepoint
                    ) OR EXISTS (
                        SELECT 1 FROM c_only_incident_flag_history cih
                        WHERE cih.result_value = TRUE
                          AND cih.changed_at BETWEEN i.start_timepoint - interval '1 hour'
                                                AND i.start_timepoint
                    )
                )                                         AS covered_incidents
            FROM incidents i
            GROUP BY date_trunc('day', i.start_timepoint)::date
        ),
        false_pos AS (
            SELECT
                date_trunc('day', sifh.changed_at)::date
                    AS day_ts,
                count(*) FILTER (WHERE sifh.incident_id IS NULL)
                    AS cnt
            FROM sicpp_incident_flag_history sifh
            WHERE sifh.reason = 'sicpp_started'
              AND sifh.changed_at >= p_period_start
            GROUP BY date_trunc('day', sifh.changed_at)::date
        )
        SELECT
            pd.day_ts,
            pd.covered_incidents::numeric / NULLIF(pd.total_incidents, 0) AS coverage,
            COALESCE(fp.cnt, 0)::integer                                  AS false_positives
        FROM per_day pd
        LEFT JOIN false_pos fp ON fp.day_ts = pd.day_ts
    ) s
    WHERE p.bucket_day = s.day_ts;
END;
$$;

COMMENT ON FUNCTION build_profile_daily(timestamptz) IS
'Суточное агрегирование. База — cluster_stat_median; марковские метрики — из profile_hourly. sicpp_true_positive_rate — из sicpp_incident_flag_history; c_only_precision — из c_only_incident_flag_history; incident_coverage_total — доля инцидентов, покрытых сигналом за час до начала; false_positive_episode_count — sicpp_started без incident_id. Идемпотентна.';
	
-- ============================================================================
-- Функция: build_profile_weekly
-- Назначение: недельное агрегирование.
-- ============================================================================
CREATE OR REPLACE FUNCTION build_profile_weekly(
    p_period_start timestamptz DEFAULT date_trunc('month', now())
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    -- Шаг 1: базовые метрики
    INSERT INTO profile_weekly (
        week_start, avg_speed, avg_waitings, avg_correlation
    )
    SELECT
        date_trunc('week', m.curr_timestamp)::date                          AS week_start,
        avg(m.curr_op_speed)                                                AS avg_speed,
        avg(m.curr_waitings)                                                AS avg_waitings,
        COALESCE(corr(m.curr_op_speed, m.curr_waitings), 0)                 AS avg_correlation
    FROM cluster_stat_median m
    WHERE m.curr_timestamp >= p_period_start
    GROUP BY date_trunc('week', m.curr_timestamp)::date
    ON CONFLICT (week_start) DO UPDATE SET
        avg_speed       = EXCLUDED.avg_speed,
        avg_waitings    = EXCLUDED.avg_waitings,
        avg_correlation = EXCLUDED.avg_correlation,
        created_at      = now();

    -- Шаг 2: марковские метрики сворачиваем из profile_daily
    UPDATE profile_weekly p
    SET avg_js_divergence    = d.avg_js,
        max_js_divergence    = d.max_js,
        avg_entropy          = d.avg_entropy,
        critical_state_share = d.critical_share,
        anomaly_count        = d.anomaly_count,
        created_at           = now()
    FROM (
        SELECT
            date_trunc('week', bucket_day)::date    AS week_ts,
            avg(avg_js_divergence)                  AS avg_js,
            max(max_js_divergence)                  AS max_js,
            avg(avg_entropy)                        AS avg_entropy,
            avg(critical_state_share)               AS critical_share,
            sum(anomaly_count)::integer             AS anomaly_count
        FROM profile_daily
        WHERE bucket_day >= p_period_start::date
        GROUP BY date_trunc('week', bucket_day)::date
    ) d
    WHERE p.week_start = d.week_ts;

    -- Шаг 3: transition_period_count
    UPDATE profile_weekly p
    SET transition_period_count = s.cnt,
        created_at              = now()
    FROM (
        SELECT
            date_trunc('week', start_time)::date AS week_ts,
            count(*)::integer                     AS cnt
        FROM profile_transition_periods
        WHERE start_time >= p_period_start
        GROUP BY date_trunc('week', start_time)::date
    ) s
    WHERE p.week_start = s.week_ts;

    -- Шаг 4: покрытие SICPP за неделю
    UPDATE profile_weekly p
    SET sicpp_weekly_coverage = s.coverage,
        avg_lead_time_sicpp   = s.avg_lead,
        created_at            = now()
    FROM (
        SELECT
            date_trunc('week', sh.changed_at)::date
                AS week_ts,
            avg(CASE WHEN sh.signal_active THEN 1.0 ELSE 0.0 END)
                AS coverage,
            avg(sh.signal_duration)::numeric
                AS avg_lead
        FROM sicpp_history sh
        WHERE sh.changed_at >= p_period_start
        GROUP BY date_trunc('week', sh.changed_at)::date
    ) s
    WHERE p.week_start = s.week_ts;

    -- Шаг 5: покрытие C-only за неделю
    UPDATE profile_weekly p
    SET c_only_weekly_coverage = s.coverage,
        avg_lead_time_c_only   = s.avg_lead,
        created_at             = now()
    FROM (
        SELECT
            date_trunc('week', cih.changed_at)::date
                AS week_ts,
            avg(CASE WHEN cih.result_value THEN 1.0 ELSE 0.0 END)
                AS coverage,
            NULL::numeric                                      AS avg_lead
        FROM c_only_incident_flag_history cih
        WHERE cih.changed_at >= p_period_start
        GROUP BY date_trunc('week', cih.changed_at)::date
    ) s
    WHERE p.week_start = s.week_ts;
END;
$$;

COMMENT ON FUNCTION build_profile_weekly(timestamptz) IS
'Недельное агрегирование. База — cluster_stat_median; марковские метрики — из profile_daily; покрытие сигналов — из sicpp_history и c_only_incident_flag_history; число переходных периодов — из profile_transition_periods. Идемпотентна.';
	
-- ============================================================================
-- Функция: detect_transition_periods
-- Назначение: обнаружение переходных периодов по часовым агрегатам.
--
-- Критерий перехода (любой из):
--   1) avg_js_divergence >= 0.05
--   2) avg_slope_speed < 0 AND avg_slope_waitings > 0
--
-- Реализация gaps-and-islands:
--   filtered   — часы, удовлетворяющие условию перехода;
--   numbered   — нумерация отфильтрованных строк row_number();
--   grouped    — вычисление ключа группы grp = bucket_hour − rn*1h
--                (для непрерывной последовательности часов ключ постоянен);
--   финальный SELECT агрегирует по grp.
-- ============================================================================
CREATE OR REPLACE FUNCTION detect_transition_periods(
    p_period_start timestamptz DEFAULT date_trunc('month', now())
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    DELETE FROM profile_transition_periods
    WHERE start_time >= p_period_start;

    INSERT INTO profile_transition_periods (
        start_time, end_time, duration_minutes, period_type, status,
        max_js, avg_js, slope_speed, slope_waitings, correlation,
        entropy, critical_state_share
    )
    WITH filtered AS (
        SELECT *
        FROM profile_hourly h
        WHERE h.bucket_hour >= p_period_start
          AND (
                h.avg_js_divergence >= 0.05
             OR (h.avg_slope_speed < 0 AND h.avg_slope_waitings > 0)
          )
    ),
    numbered AS (
        SELECT
            f.*,
            row_number() OVER (ORDER BY f.bucket_hour) AS rn
        FROM filtered f
    ),
    grouped AS (
        SELECT
            n.*,
            n.bucket_hour - (n.rn * interval '1 hour') AS grp
        FROM numbered n
    )
    SELECT
        min(g.bucket_hour)                                     AS start_time,
        max(g.bucket_hour) + interval '1 hour'                 AS end_time,
        extract(epoch FROM (max(g.bucket_hour) - min(g.bucket_hour))) / 60 + 60
                                                               AS duration_minutes,
        CASE
            WHEN avg(g.avg_slope_speed) < 0
                 AND avg(g.avg_slope_waitings) > 0 THEN 'degradation'
            WHEN avg(g.avg_slope_speed) > 0
                 AND avg(g.avg_slope_waitings) < 0 THEN 'recovery'
            ELSE 'instability'
        END                                                    AS period_type,
        CASE
            WHEN max(g.max_js_divergence) >= 0.2 THEN 'CRITICAL'
            ELSE 'WARNING'
        END                                                    AS status,
        max(g.max_js_divergence)                               AS max_js,
        avg(g.avg_js_divergence)                               AS avg_js,
        avg(g.avg_slope_speed)                                 AS slope_speed,
        avg(g.avg_slope_waitings)                              AS slope_waitings,
        avg(g.avg_correlation)                                 AS correlation,
        avg(g.avg_entropy)                                     AS entropy,
        avg(g.critical_state_share)                            AS critical_state_share
    FROM grouped g
    GROUP BY g.grp
    ORDER BY min(g.bucket_hour);
END;
$$;

COMMENT ON FUNCTION detect_transition_periods(timestamptz) IS
'Обнаруживает переходные периоды по профилю часовых агрегатов. Критерий: JS >= 0.05 ИЛИ (slope_speed<0 AND slope_waitings>0). Gaps-and-islands через CTE: row_number() выносится в отдельный шаг, чтобы не использовать оконную функцию в GROUP BY. Идемпотентна (DELETE + INSERT).';	

CREATE OR REPLACE FUNCTION generate_performance_report(
    p_start          timestamptz DEFAULT now() - interval '30 days',   -- NEW: 30 дней назад
    p_end            timestamptz DEFAULT now(),
    p_include_hourly boolean     DEFAULT TRUE
)
RETURNS text[]
LANGUAGE plpgsql
AS $$
DECLARE
    v_result        text[];
    v_row           record;
    v_start         timestamptz;
    v_end           timestamptz;
    v_build_start   timestamptz;      -- старт построения, выровнен по неделе
    v_data_min      timestamptz;
    v_data_max      timestamptz;
    v_warning       text := NULL;
    v_hourly_count  INT;
    v_daily_count   INT;
    v_weekly_count  INT;
BEGIN
    -- ========================================================================
    -- 1. Валидация
    -- ========================================================================
    v_start := COALESCE(p_start, now() - interval '30 days');
    v_end   := COALESCE(p_end,   now());

    IF v_start > v_end THEN
        RETURN ARRAY[
            '=== СВОДНЫЙ ОТЧЁТ О ПРОФИЛЕ ПРОИЗВОДИТЕЛЬНОСТИ ===',
            format('⚠ Ошибка: p_start (%s) > p_end (%s).', v_start, v_end),
            'Период не задан корректно — отчёт не сформирован.'
        ];
    END IF;

    -- ========================================================================
    -- 2. Проверка источника
    -- ========================================================================
    SELECT MIN(curr_timestamp), MAX(curr_timestamp)
    INTO v_data_min, v_data_max
    FROM cluster_stat_median;

    IF v_data_min IS NULL THEN
        RETURN ARRAY[
            '=== СВОДНЫЙ ОТЧЁТ О ПРОФИЛЕ ПРОИЗВОДИТЕЛЬНОСТИ ===',
            '⚠ Нет данных в cluster_stat_median.',
            'Убедитесь, что cluster_stat_median() и performance_metrics() вызываются регулярно.'
        ];
    END IF;

    -- ========================================================================
    -- 3. Нормализация периода
    --    (убрана проверка p_start >= now() — при DEFAULT now()-30d она не нужна,
    --     а при явном будущем p_start пользователь сам отвечает за корректность)
    -- ========================================================================
    IF v_start < v_data_min THEN
        v_warning := COALESCE(v_warning || E'\n', '') ||
                     format('⚠ p_start (%s) < min(curr_timestamp) (%s); заменено на %s.',
                            v_start, v_data_min, v_data_min);
        v_start := v_data_min;
    END IF;

    -- ========================================================================
    -- 4. Старт построения: выровнен по началу недели,
    --    чтобы все пересекающиеся бакеты содержали полные агрегаты.
    -- ========================================================================
    v_build_start := date_trunc('week', v_start);

    -- ========================================================================
    -- 5. Оркестрация агрегатов
    -- ========================================================================
    PERFORM build_profile_hourly(v_build_start);
    PERFORM build_profile_daily(v_build_start);
    PERFORM build_profile_weekly(v_build_start);
    PERFORM detect_transition_periods(v_build_start);

    -- ========================================================================
    -- 6. Заголовок
    -- ========================================================================
    v_result := ARRAY[
        '=== СВОДНЫЙ ОТЧЁТ О ПРОФИЛЕ ПРОИЗВОДИТЕЛЬНОСТИ ===',
        'Период: ' || v_start::text || ' — ' || v_end::text,
        'Длительность: ' ||
            round(extract(epoch FROM (v_end - v_start)) / 86400, 1)::text || ' дней',
        'Данные в источнике: ' || v_data_min::text || ' — ' || v_data_max::text,
        'Старт построения агрегатов: ' || v_build_start::text || ' (выровнен по неделе)',
        'Секции: ' || CASE WHEN p_include_hourly
                           THEN 'почасовая + ежедневная + недельная динамика (за весь период)'
                           ELSE 'ежедневная + недельная динамика (за весь период)' END,
        ''
    ];

    IF v_warning IS NOT NULL THEN
        v_result := array_append(v_result, v_warning);
        v_result := array_append(v_result, ''::text);
    END IF;

    -- ========================================================================
    -- 7. ПОЧАСОВАЯ ДИНАМИКА — все часы, пересекающиеся с [v_start, v_end]
    --    Включает первый (частичный) и последний (частичный) часы.
    -- ========================================================================
    IF p_include_hourly THEN
        SELECT COUNT(*) INTO v_hourly_count
        FROM profile_hourly
        WHERE bucket_hour >= date_trunc('hour', v_start)
          AND bucket_hour <  v_end;

        v_result := v_result || ARRAY[
            format('--- ПОЧАСОВАЯ ДИНАМИКА (%s часов, за весь период) ---', v_hourly_count)
        ];

        IF v_hourly_count = 0 THEN
            v_result := array_append(v_result, '(нет данных за период)');
        ELSE
            v_result := array_append(v_result,
                'Час             | Скорость | Ожидания | Корр  | SlopeS | SlopeW | ' ||
                'JS avg | JS max | Энтр  | Крит% | Аном | ' ||
                'SICPP% | SICPP# | SICPP lead | C%   | C#  | C lead');
            v_result := array_append(v_result,
                '----------------+----------+----------+-------+--------+--------+' ||
                '-------+--------+-------+-------+------+' ||
                '-------+--------+------------+------+-----+-------');

            FOR v_row IN
                SELECT
                    bucket_hour,
                    COALESCE(round(avg_speed, 2), 0)                   AS speed,
                    COALESCE(round(avg_waitings, 2), 0)                AS waitings,
                    COALESCE(round(avg_correlation, 3), 0)             AS corr,
                    COALESCE(round(avg_slope_speed, 3), 0)             AS slope_speed,
                    COALESCE(round(avg_slope_waitings, 3), 0)          AS slope_wait,
                    COALESCE(round(avg_js_divergence, 4), 0)           AS js_avg,
                    COALESCE(round(max_js_divergence, 4), 0)           AS js_max,
                    COALESCE(round(avg_entropy, 3), 0)                 AS entropy,
                    COALESCE(round(critical_state_share * 100, 1), 0)  AS crit_pct,
                    COALESCE(anomaly_count, 0)                         AS anomalies,
                    COALESCE(round(sicpp_active_share * 100, 1), 0)    AS sicpp_share,
                    COALESCE(sicpp_activations, 0)                     AS sicpp_acts,
                    COALESCE(round(sicpp_lead_time_avg, 1), 0)         AS sicpp_lead,
                    COALESCE(round(c_only_active_share * 100, 1), 0)   AS conly_share,
                    COALESCE(c_only_activations, 0)                    AS conly_acts,
                    COALESCE(round(c_only_lead_time_avg, 1), 0)        AS conly_lead
                FROM profile_hourly
                WHERE bucket_hour >= date_trunc('hour', v_start)
                  AND bucket_hour <  v_end
                ORDER BY bucket_hour
            LOOP
                v_result := array_append(v_result, format(
                    '%s | %8s | %8s | %5s | %6s | %6s | %6s | %6s | %5s | %5s | %4s | %5s | %6s | %10s | %4s | %3s | %6s',
                    to_char(v_row.bucket_hour, 'YYYY-MM-DD HH24:00'),
                    v_row.speed, v_row.waitings, v_row.corr,
                    v_row.slope_speed, v_row.slope_wait,
                    v_row.js_avg, v_row.js_max, v_row.entropy, v_row.crit_pct,
                    v_row.anomalies,
                    v_row.sicpp_share, v_row.sicpp_acts, v_row.sicpp_lead,
                    v_row.conly_share, v_row.conly_acts, v_row.conly_lead
                ));
            END LOOP;
        END IF;
    END IF;

    -- ========================================================================
    -- 8. ЕЖЕДНЕВНАЯ ДИНАМИКА — все дни, пересекающиеся с [v_start, v_end]
    --    День B пересекается ⇔ B < v_end AND B + 1d > v_start.
    -- ========================================================================
    SELECT COUNT(*) INTO v_daily_count
    FROM profile_daily
    WHERE bucket_day::timestamptz < v_end
      AND bucket_day::timestamptz + interval '1 day' > v_start;

    v_result := v_result || ARRAY[
        '',
        format('--- ЕЖЕДНЕВНАЯ ДИНАМИКА (%s дней, за весь период) ---', v_daily_count)
    ];

    IF v_daily_count = 0 THEN
        v_result := array_append(v_result, '(нет данных за период)');
    ELSE
        FOR v_row IN
            SELECT
                bucket_day,
                COALESCE(round(avg_speed, 2), 0)                       AS speed,
                COALESCE(round(avg_waitings, 2), 0)                    AS waitings,
                COALESCE(round(avg_correlation, 3), 0)                 AS corr,
                COALESCE(round(avg_slope_speed, 3), 0)                 AS slope_speed,
                COALESCE(round(avg_slope_waitings, 3), 0)              AS slope_wait,
                COALESCE(round(avg_js_divergence, 4), 0)               AS js_avg,
                COALESCE(round(max_js_divergence, 4), 0)               AS js_max,
                COALESCE(round(avg_entropy, 3), 0)                     AS entropy,
                COALESCE(round(critical_state_share * 100, 1), 0)      AS crit_pct,
                COALESCE(anomaly_count, 0)                             AS anomalies,
                COALESCE(round(sicpp_true_positive_rate * 100, 1), 0)  AS sicpp_tp_pct,
                COALESCE(round(c_only_precision * 100, 1), 0)          AS conly_prec_pct,
                COALESCE(round(incident_coverage_total * 100, 1), 0)   AS coverage_pct,
                COALESCE(false_positive_episode_count, 0)              AS fp
            FROM profile_daily
            WHERE bucket_day::timestamptz < v_end
              AND bucket_day::timestamptz + interval '1 day' > v_start
            ORDER BY bucket_day
        LOOP
            v_result := array_append(v_result, format(
                'День: %s | Скорость: %s | Ожидания: %s | Корр: %s | SlopeS: %s | SlopeW: %s | ' ||
                'JS avg: %s | JS max: %s | Энтропия: %s | Крит.: %s%% | Аномалии: %s | ' ||
                'SICPP TP: %s%% | C-only Prec: %s%% | Покрытие: %s%% | FP: %s',
                v_row.bucket_day,
                v_row.speed, v_row.waitings, v_row.corr,
                v_row.slope_speed, v_row.slope_wait,
                v_row.js_avg, v_row.js_max, v_row.entropy, v_row.crit_pct,
                v_row.anomalies,
                v_row.sicpp_tp_pct, v_row.conly_prec_pct,
                v_row.coverage_pct, v_row.fp
            ));
        END LOOP;
    END IF;

    -- ========================================================================
    -- 9. НЕДЕЛЬНАЯ ДИНАМИКА — все недели, пересекающиеся с [v_start, v_end]
    --    Неделя W (week_start = понедельник) пересекается ⇔
    --        W < v_end AND W + 7d > v_start.
    --    Крайние недели могут быть неполными (это нормально):
    --      - первая: только дни после v_start, но с понедельника (частично);
    --      - последняя: только дни до v_end.
    --    Для неполных недель в колонке «Дней» указано число дней с данными.
    -- ========================================================================
    SELECT COUNT(*) INTO v_weekly_count
    FROM profile_weekly
    WHERE week_start::timestamptz < v_end
      AND week_start::timestamptz + interval '7 days' > v_start;

    v_result := v_result || ARRAY[
        '',
        format('--- НЕДЕЛЬНАЯ ДИНАМИКА (%s недель, за весь период, включая неполные) ---', v_weekly_count)
    ];

    IF v_weekly_count = 0 THEN
        v_result := array_append(v_result, '(нет данных за период)');
    ELSE
        FOR v_row IN
            WITH weekly_base AS (
                SELECT
                    week_start,
                    COALESCE(round(avg_speed, 2), 0)                       AS speed,
                    COALESCE(round(avg_waitings, 2), 0)                    AS waitings,
                    COALESCE(round(avg_correlation, 3), 0)                 AS corr,
                    COALESCE(round(avg_js_divergence, 4), 0)               AS js_avg,
                    COALESCE(round(max_js_divergence, 4), 0)               AS js_max,
                    COALESCE(round(avg_entropy, 3), 0)                     AS entropy,
                    COALESCE(round(critical_state_share * 100, 1), 0)      AS crit_pct,
                    COALESCE(anomaly_count, 0)                             AS anomalies,
                    COALESCE(transition_period_count, 0)                   AS tp,
                    COALESCE(round(sicpp_weekly_coverage * 100, 1), 0)     AS sicpp_cov_pct,
                    COALESCE(round(avg_lead_time_sicpp, 1), 0)             AS sicpp_lead,
                    COALESCE(round(c_only_weekly_coverage * 100, 1), 0)    AS conly_cov_pct,
                    COALESCE(round(avg_lead_time_c_only, 1), 0)            AS conly_lead
                FROM profile_weekly
                WHERE week_start::timestamptz < v_end
                  AND week_start::timestamptz + interval '7 days' > v_start
            )
            SELECT
                wb.*,
                -- Число дней внутри [v_start, v_end], попадающих в неделю
                (
                    SELECT count(*)
                    FROM profile_daily pd
                    WHERE pd.bucket_day >= wb.week_start
                      AND pd.bucket_day <  wb.week_start + 7
                      AND pd.bucket_day::timestamptz <  v_end
                      AND pd.bucket_day::timestamptz + interval '1 day' > v_start
                )::int AS days_with_data,
                -- Флаг полноты: 7 полных дней внутри [v_start, v_end]
                (
                    wb.week_start::timestamptz >= date_trunc('day', v_start)
                    AND (wb.week_start + 7)::timestamptz <= v_end
                ) AS is_full_week
            FROM weekly_base wb
            ORDER BY wb.week_start
        LOOP
            v_result := array_append(v_result, format(
                'Неделя с %s [%s, %s дн.] | Скорость: %s | Ожидания: %s | Корр: %s | ' ||
                'JS avg: %s | JS max: %s | Энтропия: %s | Крит.: %s%% | Аномалии: %s | ' ||
                'Переходных: %s | SICPP cov: %s%% (lead %s мин) | C-only cov: %s%% (lead %s мин)',
                v_row.week_start,
                CASE WHEN v_row.is_full_week THEN 'полная' ELSE 'неполная' END,
                v_row.days_with_data,
                v_row.speed, v_row.waitings, v_row.corr,
                v_row.js_avg, v_row.js_max, v_row.entropy, v_row.crit_pct,
                v_row.anomalies, v_row.tp,
                v_row.sicpp_cov_pct, v_row.sicpp_lead,
                v_row.conly_cov_pct, v_row.conly_lead
            ));
        END LOOP;
    END IF;

    -- ========================================================================
    -- 10. ПЕРЕХОДНЫЕ ПЕРИОДЫ (overlap с [v_start, v_end])
    -- ========================================================================
    v_result := v_result || ARRAY['', '--- ПЕРЕХОДНЫЕ ПЕРИОДЫ ---'];
    IF NOT EXISTS (
        SELECT 1 FROM profile_transition_periods
        WHERE start_time <= v_end
          AND end_time   >= v_start
    ) THEN
        v_result := array_append(v_result, 'Переходных периодов не обнаружено.');
    ELSE
        FOR v_row IN
            SELECT start_time, end_time, period_type, status, max_js, duration_minutes
            FROM profile_transition_periods
            WHERE start_time <= v_end
              AND end_time   >= v_start
            ORDER BY start_time
        LOOP
            v_result := array_append(v_result, format(
                '[%s — %s] Тип: %s | Статус: %s | Макс. JS: %s | Длит.: %s мин.',
                v_row.start_time, v_row.end_time, v_row.period_type,
                v_row.status, COALESCE(round(v_row.max_js, 3), 0),
                v_row.duration_minutes
            ));
        END LOOP;
    END IF;

    RETURN v_result;
END;
$$;

COMMENT ON FUNCTION generate_performance_report(timestamptz, timestamptz, boolean) IS
'v26.2.1.5. Сводный отчёт по профилю производительности (text[]).

ИЗМЕНЕНИЯ ОТ v26.2.1.4:
  * DEFAULT p_start = now() - interval ''30 days'' (было date_trunc(''month'', now())).
  * Удалена нормализация p_start >= now() (при DEFAULT она не нужна;
    при явном будущем p_start пользователь сам отвечает за корректность).
  * Секция «НЕДЕЛЬНАЯ ДИНАМИКА» расширена колонками:
      - «полная/неполная» — флаг, является ли неделя полной в [v_start, v_end];
      - «N дн.» — число дней с данными внутри недели (для неполных недель).
  * Секция «ПОЧАСОВАЯ ДИНАМИКА» — все часы, включая крайние частичные.
  * Секция «ЕЖЕДНЕВНАЯ ДИНАМИКА» — все дни, включая крайние частичные.
  * В шапку добавлена строка «Длительность: X дней».

ПОВЕДЕНИЕ:
  * p_start > p_end → отчёт-ошибка.
  * p_start < min(curr_timestamp) → сдвиг на min(curr_timestamp) + предупреждение.
  * Крайние час/день/неделя могут содержать данные вне [p_start, p_end]
    (это нормально для weekly-агрегатов; см. колонку «дн.» в недельной секции).

ПРИМЕРЫ:
  SELECT unnest(generate_performance_report());                        -- 30 дней
  SELECT unnest(generate_performance_report(now() - interval ''90 days''));  -- 90 дней
  SELECT unnest(generate_performance_report(now() - interval ''30 days'', now(), FALSE));
';



-- ============================================================================
-- report_hourly_dynamics
-- Раздел 1. Почасовая динамика — читает profile_hourly.
-- Включает все часы, пересекающиеся с [v_start, v_end] (крайние — частичные).
-- ============================================================================
CREATE OR REPLACE FUNCTION report_hourly_dynamics(
    p_start      timestamptz DEFAULT now() - interval '7 days',
    p_end        timestamptz DEFAULT now(),
    p_skip_build boolean     DEFAULT FALSE
)
RETURNS text[]
LANGUAGE plpgsql
AS $$
DECLARE
    v_result      text[];
    v_row         record;
    v_start       timestamptz;
    v_end         timestamptz;
    v_build_start timestamptz;
    v_data_min    timestamptz;
    v_data_max    timestamptz;
    v_warning     text := NULL;
    v_count       INT;
BEGIN
    -- 1. Валидация
    v_start := COALESCE(p_start, now() - interval '7 days');
    v_end   := COALESCE(p_end,   now());

    IF v_start > v_end THEN
        RETURN ARRAY[
            '=== РАЗДЕЛ 1. ПОЧАСОВАЯ ДИНАМИКА ===',
            format('⚠ Ошибка: p_start (%s) > p_end (%s).', v_start, v_end),
            'Отчёт не сформирован.'
        ];
    END IF;

    -- 2. Проверка источника
    SELECT MIN(curr_timestamp), MAX(curr_timestamp)
    INTO v_data_min, v_data_max
    FROM cluster_stat_median;

    IF v_data_min IS NULL THEN
        RETURN ARRAY[
            '=== РАЗДЕЛ 1. ПОЧАСОВАЯ ДИНАМИКА ===',
            '⚠ Нет данных в cluster_stat_median.',
            'Убедитесь, что cluster_stat_median() и performance_metrics() вызываются регулярно.'
        ];
    END IF;

    -- 3. Нормализация периода
    IF v_start < v_data_min THEN
        v_warning := format(
            '⚠ p_start (%s) < min(curr_timestamp) (%s); заменено на %s.',
            v_start, v_data_min, v_data_min);
        v_start := v_data_min;
    END IF;

    -- 4. Построение (если не пропускаем)
    IF NOT p_skip_build THEN
        v_build_start := date_trunc('week', v_start);
        PERFORM build_profile_hourly(v_build_start);
        PERFORM build_profile_daily(v_build_start);
        PERFORM build_profile_weekly(v_build_start);
        PERFORM detect_transition_periods(v_build_start);
    END IF;

    -- 5. Подсчёт часов
    SELECT COUNT(*) INTO v_count
    FROM profile_hourly
    WHERE bucket_hour >= date_trunc('hour', v_start)
      AND bucket_hour <  v_end;

    -- 6. Заголовок
    v_result := ARRAY[
        '=== РАЗДЕЛ 1. ПОЧАСОВАЯ ДИНАМИКА ===',
        'Период: '  || v_start::text || ' — ' || v_end::text,
        'Часов с данными: ' || v_count::text,
        ''
    ];

    IF v_warning IS NOT NULL THEN
        v_result := array_append(v_result, v_warning);
        v_result := array_append(v_result, ''::text);
    END IF;

    IF v_count = 0 THEN
        v_result := array_append(v_result, '(нет данных за период)');
        RETURN v_result;
    END IF;

    -- 7. Таблица
    v_result := array_append(v_result,
        'Час             | Скорость | Ожидания | Корр  | SlopeS | SlopeW | ' ||
        'JS avg | JS max | Энтр  | Крит% | Аном | ' ||
        'SICPP% | SICPP# | SICPP lead | C%   | C#  | C lead');
    v_result := array_append(v_result,
        '----------------+----------+----------+-------+--------+--------+' ||
        '-------+--------+-------+-------+------+' ||
        '-------+--------+------------+------+-----+-------');

    FOR v_row IN
        SELECT *
        FROM profile_hourly
        WHERE bucket_hour >= date_trunc('hour', v_start)
          AND bucket_hour <  v_end
        ORDER BY bucket_hour
    LOOP
        v_result := array_append(v_result, format(
            '%s | %8s | %8s | %5s | %6s | %6s | %6s | %6s | %5s | %5s | %4s | %5s | %6s | %10s | %4s | %3s | %6s',
            to_char(v_row.bucket_hour, 'YYYY-MM-DD HH24:00'),
            COALESCE(round(v_row.avg_speed, 2), 0),
            COALESCE(round(v_row.avg_waitings, 2), 0),
            COALESCE(round(v_row.avg_correlation, 3), 0),
            COALESCE(round(v_row.avg_slope_speed, 3), 0),
            COALESCE(round(v_row.avg_slope_waitings, 3), 0),
            COALESCE(round(v_row.avg_js_divergence, 4), 0),
            COALESCE(round(v_row.max_js_divergence, 4), 0),
            COALESCE(round(v_row.avg_entropy, 3), 0),
            COALESCE(round(v_row.critical_state_share * 100, 1), 0),
            COALESCE(v_row.anomaly_count, 0),
            COALESCE(round(v_row.sicpp_active_share * 100, 1), 0),
            COALESCE(v_row.sicpp_activations, 0),
            COALESCE(round(v_row.sicpp_lead_time_avg, 1), 0),
            COALESCE(round(v_row.c_only_active_share * 100, 1), 0),
            COALESCE(v_row.c_only_activations, 0),
            COALESCE(round(v_row.c_only_lead_time_avg, 1), 0)
        ));
    END LOOP;

    RETURN v_result;
END;
$$;

COMMENT ON FUNCTION report_hourly_dynamics(timestamptz, timestamptz, boolean) IS
'Раздел 1. Почасовая динамика из profile_hourly. Семантика пересечения: bucket_hour >= date_trunc(hour, v_start) AND bucket_hour < v_end. Возвращает text[] (как generate_performance_report). p_skip_build = TRUE — не пересчитывать агрегаты.';


-- ============================================================================
-- build_all_profile_aggregates
-- Назначение: одноразовое построение всех агрегатов с выравниванием по неделе.
-- Используется bash-скриптом, чтобы 4 подфункции не строили агрегаты заново.
-- Идемпотентна.
-- ============================================================================
CREATE OR REPLACE FUNCTION build_all_profile_aggregates(
    p_start timestamptz DEFAULT now() - interval '7 days',
    p_end   timestamptz DEFAULT now()
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_start       timestamptz;
    v_data_min    timestamptz;
    v_build_start timestamptz;
BEGIN
    v_start := COALESCE(p_start, now() - interval '7 days');

    SELECT MIN(curr_timestamp) INTO v_data_min FROM cluster_stat_median;
    IF v_data_min IS NULL THEN
        RETURN;  -- нечего строить; подфункции сами вернут ⚠-сообщение
    END IF;

    IF v_start < v_data_min THEN
        v_start := v_data_min;
    END IF;

    v_build_start := date_trunc('week', v_start);

    PERFORM build_profile_hourly(v_build_start);
    PERFORM build_profile_daily(v_build_start);
    PERFORM build_profile_weekly(v_build_start);
    PERFORM detect_transition_periods(v_build_start);
END;
$$;

COMMENT ON FUNCTION build_all_profile_aggregates(timestamptz, timestamptz) IS
'Единоразовое построение profile_hourly/profile_daily/profile_weekly/profile_transition_periods
с выравниванием начала по неделе (как в generate_performance_report). Идемпотентна.';


-- ============================================================================
-- report_daily_dynamics
-- Раздел 2. Ежедневная динамика — читает profile_daily.
-- День B пересекается ⇔ B < v_end AND B + 1d > v_start.
-- ============================================================================
CREATE OR REPLACE FUNCTION report_daily_dynamics(
    p_start      timestamptz DEFAULT now() - interval '30 days',
    p_end        timestamptz DEFAULT now(),
    p_skip_build boolean     DEFAULT FALSE
)
RETURNS text[]
LANGUAGE plpgsql
AS $$
DECLARE
    v_result   text[];
    v_row      record;
    v_start    timestamptz;
    v_end      timestamptz;
    v_data_min timestamptz;
    v_data_max timestamptz;
    v_warning  text := NULL;
    v_count    INT;
    v_build_start timestamptz;
BEGIN
    v_start := COALESCE(p_start, now() - interval '30 days');
    v_end   := COALESCE(p_end,   now());

    IF v_start > v_end THEN
        RETURN ARRAY[
            '=== РАЗДЕЛ 2. ЕЖЕДНЕВНАЯ ДИНАМИКА ===',
            format('⚠ Ошибка: p_start (%s) > p_end (%s).', v_start, v_end),
            'Отчёт не сформирован.'
        ];
    END IF;

    SELECT MIN(curr_timestamp), MAX(curr_timestamp)
    INTO v_data_min, v_data_max FROM cluster_stat_median;

    IF v_data_min IS NULL THEN
        RETURN ARRAY[
            '=== РАЗДЕЛ 2. ЕЖЕДНЕВНАЯ ДИНАМИКА ===',
            '⚠ Нет данных в cluster_stat_median.'
        ];
    END IF;

    IF v_start < v_data_min THEN
        v_warning := format('⚠ p_start (%s) < min(curr_timestamp) (%s); заменено на %s.',
                            v_start, v_data_min, v_data_min);
        v_start := v_data_min;
    END IF;

    IF NOT p_skip_build THEN
        v_build_start := date_trunc('week', v_start);
        PERFORM build_profile_hourly(v_build_start);
        PERFORM build_profile_daily(v_build_start);
    END IF;

    SELECT COUNT(*) INTO v_count
    FROM profile_daily
    WHERE bucket_day::timestamptz <  v_end
      AND bucket_day::timestamptz + interval '1 day' > v_start;

    v_result := ARRAY[
        '=== РАЗДЕЛ 2. ЕЖЕДНЕВНАЯ ДИНАМИКА ===',
        'Период: ' || v_start::text || ' — ' || v_end::text,
        'Дней с данными: ' || v_count::text,
        ''
    ];

    IF v_warning IS NOT NULL THEN
        v_result := array_append(v_result, v_warning);
        v_result := array_append(v_result, ''::text);
    END IF;

    IF v_count = 0 THEN
        v_result := array_append(v_result, '(нет данных за период)');
        RETURN v_result;
    END IF;

    -- Заголовки таблицы
    v_result := array_append(v_result,
        'День       | Скорость | Ожидания | Корр  | SlopeS | SlopeW | ' ||
        'JS avg | JS max | Энтр  | Крит% | Аном | ' ||
        'SICPP TP% | C-only Prec% | Покрытие% | FP');
    v_result := array_append(v_result,
        '-----------+----------+----------+-------+--------+--------+' ||
        '-------+--------+-------+-------+------+' ||
        '----------+--------------+-----------+----');

    FOR v_row IN
        SELECT *
        FROM profile_daily
        WHERE bucket_day::timestamptz <  v_end
          AND bucket_day::timestamptz + interval '1 day' > v_start
        ORDER BY bucket_day
    LOOP
        v_result := array_append(v_result, format(
            '%s | %8s | %8s | %5s | %6s | %6s | %6s | %6s | %5s | %5s | %4s | %9s | %12s | %9s | %3s',
            v_row.bucket_day,
            COALESCE(round(v_row.avg_speed, 2), 0),
            COALESCE(round(v_row.avg_waitings, 2), 0),
            COALESCE(round(v_row.avg_correlation, 3), 0),
            COALESCE(round(v_row.avg_slope_speed, 3), 0),
            COALESCE(round(v_row.avg_slope_waitings, 3), 0),
            COALESCE(round(v_row.avg_js_divergence, 4), 0),
            COALESCE(round(v_row.max_js_divergence, 4), 0),
            COALESCE(round(v_row.avg_entropy, 3), 0),
            COALESCE(round(v_row.critical_state_share * 100, 1), 0),
            COALESCE(v_row.anomaly_count, 0),
            COALESCE(round(v_row.sicpp_true_positive_rate * 100, 1), 0),
            COALESCE(round(v_row.c_only_precision * 100, 1), 0),
            COALESCE(round(v_row.incident_coverage_total * 100, 1), 0),
            COALESCE(v_row.false_positive_episode_count, 0)
        ));
    END LOOP;

    RETURN v_result;
END;
$$;

COMMENT ON FUNCTION report_daily_dynamics(timestamptz, timestamptz, boolean) IS
'Раздел 2. Ежедневная динамика из profile_daily. Пересечение: bucket_day::timestamptz < v_end AND bucket_day + 1d > v_start. Возвращает text[].';

-- ============================================================================
-- report_weekly_dynamics
-- Раздел 3. Недельная динамика — читает profile_weekly + profile_daily
-- (число дней с данными и флаг «полная/неполная» неделя).
-- Неделя W пересекается ⇔ W < v_end AND W + 7d > v_start.
-- ============================================================================
CREATE OR REPLACE FUNCTION report_weekly_dynamics(
    p_start      timestamptz DEFAULT now() - interval '90 days',
    p_end        timestamptz DEFAULT now(),
    p_skip_build boolean     DEFAULT FALSE
)
RETURNS text[]
LANGUAGE plpgsql
AS $$
DECLARE
    v_result   text[];
    v_row      record;
    v_start    timestamptz;
    v_end      timestamptz;
    v_data_min timestamptz;
    v_data_max timestamptz;
    v_warning  text := NULL;
    v_count    INT;
    v_build_start timestamptz;
BEGIN
    v_start := COALESCE(p_start, now() - interval '90 days');
    v_end   := COALESCE(p_end,   now());

    IF v_start > v_end THEN
        RETURN ARRAY[
            '=== РАЗДЕЛ 3. НЕДЕЛЬНАЯ ДИНАМИКА ===',
            format('⚠ Ошибка: p_start (%s) > p_end (%s).', v_start, v_end),
            'Отчёт не сформирован.'
        ];
    END IF;

    SELECT MIN(curr_timestamp), MAX(curr_timestamp)
    INTO v_data_min, v_data_max FROM cluster_stat_median;

    IF v_data_min IS NULL THEN
        RETURN ARRAY[
            '=== РАЗДЕЛ 3. НЕДЕЛЬНАЯ ДИНАМИКА ===',
            '⚠ Нет данных в cluster_stat_median.'
        ];
    END IF;

    IF v_start < v_data_min THEN
        v_warning := format('⚠ p_start (%s) < min(curr_timestamp) (%s); заменено на %s.',
                            v_start, v_data_min, v_data_min);
        v_start := v_data_min;
    END IF;

    IF NOT p_skip_build THEN
        v_build_start := date_trunc('week', v_start);
        PERFORM build_profile_hourly(v_build_start);
        PERFORM build_profile_daily(v_build_start);
        PERFORM build_profile_weekly(v_build_start);
    END IF;

    SELECT COUNT(*) INTO v_count
    FROM profile_weekly
    WHERE week_start::timestamptz <  v_end
      AND week_start::timestamptz + interval '7 days' > v_start;

    v_result := ARRAY[
        '=== РАЗДЕЛ 3. НЕДЕЛЬНАЯ ДИНАМИКА ===',
        'Период: ' || v_start::text || ' — ' || v_end::text,
        'Недель с данными: ' || v_count::text || ' (включая неполные)',
        ''
    ];

    IF v_warning IS NOT NULL THEN
        v_result := array_append(v_result, v_warning);
        v_result := array_append(v_result, ''::text);
    END IF;

    IF v_count = 0 THEN
        v_result := array_append(v_result, '(нет данных за период)');
        RETURN v_result;
    END IF;

    -- Заголовки
    v_result := array_append(v_result,
        'Неделя с    | Статус  | Дн. | Скорость | Ожидания | Корр  | ' ||
        'JS avg | JS max | Энтр  | Крит% | Аном | Перех. | ' ||
        'SICPP cov% | lead | C-only cov% | lead');
    v_result := array_append(v_result,
        '------------+---------+-----+----------+----------+-------+' ||
        '-------+--------+-------+-------+------+--------+' ||
        '-----------+------+-------------+------');

    FOR v_row IN
        WITH weekly_base AS (
            SELECT
                week_start,
                COALESCE(round(avg_speed, 2), 0)                    AS speed,
                COALESCE(round(avg_waitings, 2), 0)                 AS waitings,
                COALESCE(round(avg_correlation, 3), 0)              AS corr,
                COALESCE(round(avg_js_divergence, 4), 0)            AS js_avg,
                COALESCE(round(max_js_divergence, 4), 0)            AS js_max,
                COALESCE(round(avg_entropy, 3), 0)                  AS entropy,
                COALESCE(round(critical_state_share * 100, 1), 0)   AS crit_pct,
                COALESCE(anomaly_count, 0)                          AS anomalies,
                COALESCE(transition_period_count, 0)                AS tp,
                COALESCE(round(sicpp_weekly_coverage * 100, 1), 0)  AS sicpp_cov,
                COALESCE(round(avg_lead_time_sicpp, 1), 0)          AS sicpp_lead,
                COALESCE(round(c_only_weekly_coverage * 100, 1), 0) AS conly_cov,
                COALESCE(round(avg_lead_time_c_only, 1), 0)         AS conly_lead
            FROM profile_weekly
            WHERE week_start::timestamptz <  v_end
              AND week_start::timestamptz + interval '7 days' > v_start
        )
        SELECT
            wb.*,
            (
                SELECT count(*)
                FROM profile_daily pd
                WHERE pd.bucket_day >= wb.week_start
                  AND pd.bucket_day <  wb.week_start + 7
                  AND pd.bucket_day::timestamptz <  v_end
                  AND pd.bucket_day::timestamptz + interval '1 day' > v_start
            )::int AS days_with_data,
            (
                wb.week_start::timestamptz >= date_trunc('day', v_start)
                AND (wb.week_start + 7)::timestamptz <= v_end
            ) AS is_full_week
        FROM weekly_base wb
        ORDER BY wb.week_start
    LOOP
        v_result := array_append(v_result, format(
            '%s | %7s | %3s | %8s | %8s | %5s | %6s | %6s | %5s | %5s | %4s | %6s | %9s | %4s | %11s | %4s',
            v_row.week_start,
            CASE WHEN v_row.is_full_week THEN 'полная' ELSE 'неполн.' END,
            v_row.days_with_data,
            v_row.speed, v_row.waitings, v_row.corr,
            v_row.js_avg, v_row.js_max, v_row.entropy, v_row.crit_pct,
            v_row.anomalies, v_row.tp,
            v_row.sicpp_cov, v_row.sicpp_lead,
            v_row.conly_cov, v_row.conly_lead
        ));
    END LOOP;

    RETURN v_result;
END;
$$;

COMMENT ON FUNCTION report_weekly_dynamics(timestamptz, timestamptz, boolean) IS
'Раздел 3. Недельная динамика из profile_weekly (число дней — из profile_daily). Флаг «полная/неполная» неделя. Пересечение: W < v_end AND W + 7d > v_start. Возвращает text[].';

-- ============================================================================
-- report_transition_periods (v2)
-- Раздел 4. Переходные периоды + статистика инцидентов за период.
--
-- Изменения относительно v1:
--   * Для каждого периода добавлена статистика по инцидентам
--     markov_chain_performance_incident (overlap с [start_time, end_time]):
--       - всего / завершено / открыто;
--       - avg/max длительность (мин);
--       - список ID.
--   * В «СВОДКА ПО ТИПАМ» и «СВОДКА ПО СТАТУСАМ» добавлена колонка
--     «инцидентов: N».
--   * Добавлена итоговая строка «Итого инцидентов по периодам
--     (с перекрытиями): N».
--   * Если markov_chain_performance_incident отсутствует — выводится
--     «инциденты: н/д (нет таблицы)», отчёт не падает.
--   * Функция VOLATILE (использует EXECUTE + может вызывать build_*).
-- ============================================================================
CREATE OR REPLACE FUNCTION report_transition_periods(
    p_start      timestamptz DEFAULT now() - interval '30 days',
    p_end        timestamptz DEFAULT now(),
    p_skip_build boolean     DEFAULT FALSE
)
RETURNS text[]
LANGUAGE plpgsql
AS $$
DECLARE
    v_result      text[];
    v_row         record;
    v_start       timestamptz;
    v_end         timestamptz;
    v_data_min    timestamptz;
    v_data_max    timestamptz;
    v_warning     text := NULL;
    v_count       INT;
    v_build_start timestamptz;
    v_inc_exists  boolean;
    v_total_inc   int := 0;
    v_inc_str     text;
    v_inc_json    jsonb;
    v_sql         text;
BEGIN
    -- ========================================================================
    -- 1. Валидация и нормализация периода
    -- ========================================================================
    v_start := COALESCE(p_start, now() - interval '30 days');
    v_end   := COALESCE(p_end,   now());

    IF v_start > v_end THEN
        RETURN ARRAY[
            '=== РАЗДЕЛ 4. ПЕРЕХОДНЫЕ ПЕРИОДЫ ===',
            format('⚠ Ошибка: p_start (%s) > p_end (%s).', v_start, v_end),
            'Отчёт не сформирован.'
        ];
    END IF;

    SELECT MIN(curr_timestamp), MAX(curr_timestamp)
    INTO v_data_min, v_data_max
    FROM cluster_stat_median;

    IF v_data_min IS NULL THEN
        RETURN ARRAY[
            '=== РАЗДЕЛ 4. ПЕРЕХОДНЫЕ ПЕРИОДЫ ===',
            '⚠ Нет данных в cluster_stat_median.'
        ];
    END IF;

    IF v_start < v_data_min THEN
        v_warning := format('⚠ p_start (%s) < min(curr_timestamp) (%s); заменено на %s.',
                            v_start, v_data_min, v_data_min);
        v_start := v_data_min;
    END IF;

    -- ========================================================================
    -- 2. Построение агрегатов (опционально)
    -- ========================================================================
    IF NOT p_skip_build THEN
        v_build_start := date_trunc('week', v_start);
        PERFORM build_profile_hourly(v_build_start);
        PERFORM detect_transition_periods(v_build_start);
    END IF;

    -- ========================================================================
    -- 3. Наличие таблицы инцидентов
    -- ========================================================================
    SELECT EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_name = 'markov_chain_performance_incident'
    ) INTO v_inc_exists;

    -- ========================================================================
    -- 4. Шапка
    -- ========================================================================
    SELECT COUNT(*) INTO v_count
    FROM profile_transition_periods
    WHERE start_time <= v_end
      AND end_time   >= v_start;

    v_result := ARRAY[
        '=== РАЗДЕЛ 4. ПЕРЕХОДНЫЕ ПЕРИОДЫ ===',
        'Период: ' || v_start::text || ' — ' || v_end::text,
        'Переходных периодов: ' || v_count::text,
        CASE WHEN v_inc_exists
             THEN 'Инциденты: markov_chain_performance_incident (overlap с периодом)'
             ELSE 'Инциденты: ⚠ таблица markov_chain_performance_incident не найдена'
        END,
        ''
    ];

    IF v_warning IS NOT NULL THEN
        v_result := array_append(v_result, v_warning);
        v_result := array_append(v_result, ''::text);
    END IF;

    IF v_count = 0 THEN
        v_result := array_append(v_result, 'Переходных периодов не обнаружено.');
        RETURN v_result;
    END IF;

    -- ========================================================================
    -- 4.1. Перечень периодов с инцидентами
    -- ========================================================================
    v_result := array_append(v_result, '--- ПЕРЕЧЕНЬ ПЕРИОДОВ С ИНЦИДЕНТАМИ ---');

    v_sql := format($f$
        SELECT
            p.start_time, p.end_time, p.period_type, p.status,
            p.max_js, p.duration_minutes,
            %s AS inc
        FROM profile_transition_periods p
        WHERE p.start_time <= $1
          AND p.end_time   >= $2
        ORDER BY p.start_time
    $f$,
        CASE WHEN v_inc_exists THEN $sub$
            (SELECT jsonb_build_object(
                'total',     COUNT(*)::int,
                'completed', COUNT(*) FILTER (WHERE finish_timepoint IS NOT NULL)::int,
                'open',      COUNT(*) FILTER (WHERE finish_timepoint IS NULL)::int,
                'avg_dur',   ROUND(AVG(EXTRACT(epoch FROM (finish_timepoint - start_timepoint)) / 60.0)::numeric, 1),
                'max_dur',   ROUND(MAX(EXTRACT(epoch FROM (finish_timepoint - start_timepoint)) / 60.0)::numeric, 1),
                'ids',       string_agg(id::text, ',' ORDER BY id)
            )
             FROM markov_chain_performance_incident
             WHERE start_timepoint < p.end_time
               AND (finish_timepoint IS NULL OR finish_timepoint >= p.start_time))
        $sub$ ELSE 'NULL::jsonb' END
    );

    FOR v_row IN EXECUTE v_sql USING v_end, v_start LOOP
        v_inc_json := v_row.inc;

        IF NOT v_inc_exists THEN
            v_inc_str := 'инциденты: н/д (нет таблицы)';
        ELSIF v_inc_json IS NULL OR (v_inc_json->>'total')::int = 0 THEN
            v_inc_str := 'инцидентов: 0';
        ELSE
            v_total_inc := v_total_inc + (v_inc_json->>'total')::int;
            v_inc_str := format(
                'инцидентов: %s (заверш. %s, откр. %s; avg %s / max %s мин; IDs: %s)',
                v_inc_json->>'total',
                v_inc_json->>'completed',
                v_inc_json->>'open',
                COALESCE(v_inc_json->>'avg_dur', '-'),
                COALESCE(v_inc_json->>'max_dur', '-'),
                COALESCE(v_inc_json->>'ids',     '-')
            );
        END IF;

        v_result := array_append(v_result, format(
            '[%s — %s] Тип: %s | Статус: %s | Макс. JS: %s | Длит.: %s мин | %s',
            to_char(v_row.start_time, 'YYYY-MM-DD HH24:MI'),
            to_char(v_row.end_time,   'YYYY-MM-DD HH24:MI'),
            v_row.period_type,
            v_row.status,
            COALESCE(round(v_row.max_js, 3), 0),
            v_row.duration_minutes,
            v_inc_str
        ));
    END LOOP;

    IF v_inc_exists THEN
        v_result := array_append(v_result, '');
        v_result := array_append(v_result, format(
            'Итого инцидентов по периодам (с перекрытиями): %s', v_total_inc));
    END IF;
    v_result := array_append(v_result, '');

    -- ========================================================================
    -- 4.2. Сводка по типам (с числом инцидентов)
    -- ========================================================================
    v_result := array_append(v_result, '--- СВОДКА ПО ТИПАМ ---');

    v_sql := format($f$
        SELECT
            period_type,
            COUNT(*) AS cnt,
            ROUND(AVG(duration_minutes)::numeric, 1) AS avg_dur,
            COALESCE(SUM(duration_minutes), 0)::numeric AS total_dur,
            ROUND(AVG(max_js)::numeric, 3) AS avg_max_js,
            ROUND(MAX(max_js)::numeric, 3) AS peak_js,
            COALESCE(SUM(inc_cnt), 0)::int AS total_incidents
        FROM (
            SELECT
                p.period_type, p.duration_minutes, p.max_js,
                %s AS inc_cnt
            FROM profile_transition_periods p
            WHERE p.start_time <= $1
              AND p.end_time   >= $2
        ) x
        GROUP BY period_type
        ORDER BY period_type
    $f$,
        CASE WHEN v_inc_exists THEN $sub$
            (SELECT COUNT(*)::int
             FROM markov_chain_performance_incident
             WHERE start_timepoint < p.end_time
               AND (finish_timepoint IS NULL OR finish_timepoint >= p.start_time))
        $sub$ ELSE '0::int' END
    );

    FOR v_row IN EXECUTE v_sql USING v_end, v_start LOOP
        v_result := array_append(v_result, format(
            '  %-12s | периодов: %3s | средн. длит.: %6s мин | суммарно: %8s мин | сред. JS max: %s | пик JS: %s%s',
            v_row.period_type,
            v_row.cnt,
            v_row.avg_dur,
            v_row.total_dur,
            v_row.avg_max_js,
            v_row.peak_js,
            CASE WHEN v_inc_exists
                 THEN format(' | инцидентов: %s', v_row.total_incidents)
                 ELSE '' END
        ));
    END LOOP;

    -- ========================================================================
    -- 4.3. Сводка по статусам (с числом инцидентов)
    -- ========================================================================
    v_result := array_append(v_result, '');
    v_result := array_append(v_result, '--- СВОДКА ПО СТАТУСАМ ---');

    v_sql := format($f$
        SELECT
            status,
            COUNT(*) AS cnt,
            ROUND(AVG(max_js)::numeric, 3) AS avg_max_js,
            COALESCE(SUM(inc_cnt), 0)::int AS total_incidents
        FROM (
            SELECT
                p.status, p.max_js,
                %s AS inc_cnt
            FROM profile_transition_periods p
            WHERE p.start_time <= $1
              AND p.end_time   >= $2
        ) x
        GROUP BY status
        ORDER BY status
    $f$,
        CASE WHEN v_inc_exists THEN $sub$
            (SELECT COUNT(*)::int
             FROM markov_chain_performance_incident
             WHERE start_timepoint < p.end_time
               AND (finish_timepoint IS NULL OR finish_timepoint >= p.start_time))
        $sub$ ELSE '0::int' END
    );

    FOR v_row IN EXECUTE v_sql USING v_end, v_start LOOP
        v_result := array_append(v_result, format(
            '  %-10s | периодов: %3s | сред. JS max: %s%s',
            v_row.status,
            v_row.cnt,
            v_row.avg_max_js,
            CASE WHEN v_inc_exists
                 THEN format(' | инцидентов: %s', v_row.total_incidents)
                 ELSE '' END
        ));
    END LOOP;

    RETURN v_result;
END;
$$;

COMMENT ON FUNCTION report_transition_periods(timestamptz, timestamptz, boolean) IS
'v2. Раздел 4. Переходные периоды из profile_transition_periods.
Пересечение периода с окном отчёта: start_time <= p_end AND end_time >= p_start.

ДОПОЛНЕНИЕ: для каждого периода выводится статистика инцидентов
markov_chain_performance_incident с семантикой пересечения
  start_timepoint < period.end_time
  AND (finish_timepoint IS NULL OR finish_timepoint >= period.start_time).
Строка периода: «… | инцидентов: N (заверш. X, откр. Y; avg A / max B мин; IDs: …)».
В «СВОДКА ПО ТИПАМ» и «СВОДКА ПО СТАТУСАМ» добавлена колонка «инцидентов: N».
Итог: «Итого инцидентов по периодам (с перекрытиями): N».
При отсутствии markov_chain_performance_incident отчёт не падает —
пишет «инциденты: н/д (нет таблицы)».

ВНИМАНИЕ: один инцидент, перекрывающий несколько периодов, учитывается
в каждом из них (учтено в строке «с перекрытиями»).

Функция VOLATILE (использует EXECUTE и может вызывать build_profile_hourly /
detect_transition_periods при p_skip_build = FALSE).';

-- ============================================================================
-- report_incident_statistics
-- Раздел 5. Статистика по инцидентам производительности.
-- Источник: markov_chain_performance_incident (id, start_timepoint, finish_timepoint).
-- Семантика пересечения: start_timepoint < v_end
--                    AND (finish_timepoint IS NULL OR finish_timepoint >= v_start).
-- Не требует агрегатов profile_*; поэтому p_skip_build не нужен.
-- ============================================================================
CREATE OR REPLACE FUNCTION report_incident_statistics(
    p_start timestamptz DEFAULT now() - interval '7 days',
    p_end   timestamptz DEFAULT now()
)
RETURNS text[]
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_result   text[];
    v_row      record;
    v_start    timestamptz;
    v_end      timestamptz;
    v_warning  text := NULL;

    v_total        INT;
    v_completed    INT;
    v_open         INT;
    v_days_with    INT;
    v_avg_dur      numeric;
    v_median_dur   numeric;
    v_p90_dur      numeric;
    v_min_dur      numeric;
    v_max_dur      numeric;

    v_busiest_day  date;
    v_busiest_day_cnt INT;
    v_busiest_hour int;
    v_busiest_hour_cnt INT;

    v_longest_id   bigint;
    v_longest_dur  numeric;
BEGIN
    -- 1. Валидация
    v_start := COALESCE(p_start, now() - interval '7 days');
    v_end   := COALESCE(p_end,   now());

    IF v_start > v_end THEN
        RETURN ARRAY[
            '=== РАЗДЕЛ 5. СТАТИСТИКА ПО ИНЦИДЕНТАМ ===',
            format('⚠ Ошибка: p_start (%s) > p_end (%s).', v_start, v_end),
            'Отчёт не сформирован.'
        ];
    END IF;

    -- 2. Проверка наличия таблицы
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_name = 'markov_chain_performance_incident'
    ) THEN
        RETURN ARRAY[
            '=== РАЗДЕЛ 5. СТАТИСТИКА ПО ИНЦИДЕНТАМ ===',
            '⚠ Таблица markov_chain_performance_incident не найдена.',
            'Убедитесь, что markov_chain_tables.sql применён.'
        ];
    END IF;

    -- 3. Сводные метрики
    SELECT
        COUNT(*),
        COUNT(*) FILTER (WHERE finish_timepoint IS NOT NULL),
        COUNT(*) FILTER (WHERE finish_timepoint IS NULL),
        COUNT(DISTINCT start_timepoint::date),
        ROUND(AVG(EXTRACT(epoch FROM (finish_timepoint - start_timepoint)) / 60.0)::numeric, 1),
        ROUND((percentile_cont(0.5) WITHIN GROUP (
            ORDER BY EXTRACT(epoch FROM (finish_timepoint - start_timepoint)) / 60.0))::numeric, 1),
        ROUND((percentile_cont(0.9) WITHIN GROUP (
            ORDER BY EXTRACT(epoch FROM (finish_timepoint - start_timepoint)) / 60.0))::numeric, 1),
        ROUND(MIN(EXTRACT(epoch FROM (finish_timepoint - start_timepoint)) / 60.0)::numeric, 1),
        ROUND(MAX(EXTRACT(epoch FROM (finish_timepoint - start_timepoint)) / 60.0)::numeric, 1)
    INTO v_total, v_completed, v_open, v_days_with,
         v_avg_dur, v_median_dur, v_p90_dur, v_min_dur, v_max_dur
    FROM markov_chain_performance_incident
    WHERE start_timepoint < v_end
      AND (finish_timepoint IS NULL OR finish_timepoint >= v_start);

    -- 4. Заголовок
    v_result := ARRAY[
        '=== РАЗДЕЛ 5. СТАТИСТИКА ПО ИНЦИДЕНТАМ ===',
        'Период: '  || v_start::text || ' — ' || v_end::text,
        'Источник: markov_chain_performance_incident (пересечение с периодом)',
        ''
    ];

    IF v_total = 0 THEN
        v_result := array_append(v_result, 'Инцидентов за период не зафиксировано.');
        RETURN v_result;
    END IF;

    -- 5. Общая сводка
    v_result := v_result || ARRAY[
        '--- ОБЩАЯ СВОДКА ---',
        format('  Всего инцидентов:        %s', v_total),
        format('  Завершённых:             %s', v_completed),
        format('  Открытых (в процессе):   %s', v_open),
        format('  Дней с инцидентами:      %s', v_days_with),
        ''
    ];

    -- 6. Длительности (только завершённые)
    IF v_completed > 0 THEN
        v_result := v_result || ARRAY[
            '--- ДЛИТЕЛЬНОСТИ (завершённые инциденты, минуты) ---',
            format('  Средняя:    %s', v_avg_dur),
            format('  Медиана:    %s', v_median_dur),
            format('  P90:        %s', v_p90_dur),
            format('  Минимум:    %s', v_min_dur),
            format('  Максимум:   %s', v_max_dur),
            ''
        ];

        -- Самый длинный инцидент
        SELECT id,
               ROUND(EXTRACT(epoch FROM (finish_timepoint - start_timepoint)) / 60.0)::numeric
        INTO v_longest_id, v_longest_dur
        FROM markov_chain_performance_incident
        WHERE start_timepoint < v_end
          AND (finish_timepoint IS NULL OR finish_timepoint >= v_start)
          AND finish_timepoint IS NOT NULL
        ORDER BY (finish_timepoint - start_timepoint) DESC
        LIMIT 1;

        IF v_longest_id IS NOT NULL THEN
            v_result := array_append(v_result,
                format('  Самый длинный: ID=%s, %s мин', v_longest_id, v_longest_dur));
            v_result := array_append(v_result, '');
        END IF;
    END IF;

    -- 7. Пиковые значения (день и час)
    SELECT start_timepoint::date, COUNT(*)::int
    INTO v_busiest_day, v_busiest_day_cnt
    FROM markov_chain_performance_incident
    WHERE start_timepoint < v_end
      AND (finish_timepoint IS NULL OR finish_timepoint >= v_start)
    GROUP BY start_timepoint::date
    ORDER BY COUNT(*) DESC, start_timepoint::date
    LIMIT 1;

    SELECT EXTRACT(hour FROM start_timepoint)::int, COUNT(*)::int
    INTO v_busiest_hour, v_busiest_hour_cnt
    FROM markov_chain_performance_incident
    WHERE start_timepoint < v_end
      AND (finish_timepoint IS NULL OR finish_timepoint >= v_start)
    GROUP BY EXTRACT(hour FROM start_timepoint)
    ORDER BY COUNT(*) DESC, EXTRACT(hour FROM start_timepoint)
    LIMIT 1;

    IF v_busiest_day IS NOT NULL THEN
        v_result := v_result || ARRAY[
            '--- ПИКОВЫЕ ЗНАЧЕНИЯ ---',
            format('  Самый активный день:     %s (%s инцидентов)',
                   v_busiest_day, v_busiest_day_cnt),
            format('  Самый активный час:      %s:00 (%s инцидентов)',
                   v_busiest_hour, v_busiest_hour_cnt),
            ''
        ];
    END IF;

    -- 8. Распределение по дням
    v_result := v_result || ARRAY['--- РАСПРЕДЕЛЕНИЕ ПО ДНЯМ ---'];
    v_result := array_append(v_result,
        'День       | Инцидентов | Заверш. | Открыт. | Ср.длит.,мин | Макс.длит.,мин');
    v_result := array_append(v_result,
        '-----------+------------+---------+---------+--------------+---------------');

    FOR v_row IN
        SELECT
            start_timepoint::date AS day,
            COUNT(*) AS cnt,
            COUNT(*) FILTER (WHERE finish_timepoint IS NOT NULL) AS completed,
            COUNT(*) FILTER (WHERE finish_timepoint IS NULL)     AS open_cnt,
            ROUND(AVG(EXTRACT(epoch FROM (finish_timepoint - start_timepoint)) / 60.0)::numeric, 1) AS avg_dur,
            ROUND(MAX(EXTRACT(epoch FROM (finish_timepoint - start_timepoint)) / 60.0)::numeric, 1) AS max_dur
        FROM markov_chain_performance_incident
        WHERE start_timepoint < v_end
          AND (finish_timepoint IS NULL OR finish_timepoint >= v_start)
        GROUP BY start_timepoint::date
        ORDER BY day
    LOOP
        v_result := array_append(v_result, format(
            '%s | %10s | %7s | %7s | %12s | %13s',
            v_row.day, v_row.cnt, v_row.completed, v_row.open_cnt,
            COALESCE(v_row.avg_dur::text, '-'),
            COALESCE(v_row.max_dur::text, '-')
        ));
    END LOOP;

    v_result := array_append(v_result, '');

    -- 9. Распределение по часам суток
    v_result := v_result || ARRAY['--- РАСПРЕДЕЛЕНИЕ ПО ЧАСАМ СУТОК (start_timepoint) ---'];
    v_result := array_append(v_result, 'Час  | Инцидентов | Гистограмма');
    v_result := array_append(v_result, '-----+------------+------------');

    FOR v_row IN
        SELECT
            EXTRACT(hour FROM start_timepoint)::int AS hr,
            COUNT(*)::int AS cnt
        FROM markov_chain_performance_incident
        WHERE start_timepoint < v_end
          AND (finish_timepoint IS NULL OR finish_timepoint >= v_start)
        GROUP BY EXTRACT(hour FROM start_timepoint)
        ORDER BY hr
    LOOP
        v_result := array_append(v_result, format(
            '%4s | %10s | %s',
            v_row.hr, v_row.cnt, repeat('█', LEAST(v_row.cnt, 40))
        ));
    END LOOP;

    v_result := array_append(v_result, '');

    -- 10. Перечень инцидентов
    v_result := v_result || ARRAY['--- ПЕРЕЧЕНЬ ИНЦИДЕНТОВ ---'];
    v_result := array_append(v_result,
        'ID    | Начало              | Конец               | Длит.,мин | Статус');
    v_result := array_append(v_result,
        '------+---------------------+---------------------+-----------+----------');

    FOR v_row IN
        SELECT
            id,
            start_timepoint,
            finish_timepoint,
            CASE WHEN finish_timepoint IS NOT NULL
                 THEN ROUND(EXTRACT(epoch FROM (finish_timepoint - start_timepoint)) / 60.0)::text
                 ELSE '-' END AS dur_min,
            CASE WHEN finish_timepoint IS NOT NULL THEN 'завершён' ELSE 'ОТКРЫТ' END AS status
        FROM markov_chain_performance_incident
        WHERE start_timepoint < v_end
          AND (finish_timepoint IS NULL OR finish_timepoint >= v_start)
        ORDER BY start_timepoint
    LOOP
        v_result := array_append(v_result, format(
            '%5s | %s | %s | %9s | %s',
            v_row.id,
            to_char(v_row.start_timepoint, 'YYYY-MM-DD HH24:MI'),
            COALESCE(to_char(v_row.finish_timepoint, 'YYYY-MM-DD HH24:MI'), '      (в процессе)'),
            v_row.dur_min,
            v_row.status
        ));
    END LOOP;

    RETURN v_result;
END;
$$;

COMMENT ON FUNCTION report_incident_statistics(timestamptz, timestamptz) IS
'Раздел 5. Статистика по инцидентам производительности из markov_chain_performance_incident.
Семантика пересечения: start_timepoint < p_end AND (finish_timepoint IS NULL OR finish_timepoint >= p_start).
Выводит: общую сводку, длительности (avg/median/P90/min/max), пиковые день/час,
распределение по дням и часам суток, перечень инцидентов. Возвращает text[] (как generate_performance_report).';

-- ---------------------------------------------------------------------------
-- 3.1. Триггерная функция: при вставке нового инцидента линкует сигналы,
--      стартовавшие в окне [start_timepoint − window, start_timepoint].
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_mcpi_link_signals_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_window interval;
BEGIN
    BEGIN
        SELECT (signal_incident_link_window_min || ' minutes')::interval
        INTO v_window
        FROM markov_config
        LIMIT 1;
    EXCEPTION WHEN OTHERS THEN
        v_window := interval '60 minutes';
    END;

    IF v_window IS NULL THEN
        v_window := interval '60 minutes';
    END IF;

    -- Линкуем SICPP «старт эпизода» — предиктивный сигнал.
    UPDATE sicpp_incident_flag_history
       SET incident_id = NEW.id
     WHERE incident_id IS NULL
       AND reason = 'sicpp_started'
       AND changed_at >= NEW.start_timepoint - v_window
       AND changed_at <= NEW.start_timepoint;

    -- Линкуем C-only активные срабатывания.
    UPDATE c_only_incident_flag_history
       SET incident_id = NEW.id
     WHERE incident_id IS NULL
       AND flag_value = TRUE
       AND changed_at >= NEW.start_timepoint - v_window
       AND changed_at <= NEW.start_timepoint;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION trg_mcpi_link_signals_insert() IS
'v26.3.1. AFTER INSERT триггер на markov_chain_performance_incident: проставляет incident_id у ранее нелинкованных сигналов SICPP/C-only, попавших в окно [start − window, start].';

DROP TRIGGER IF EXISTS trg_mcpi_link_signals_ai ON markov_chain_performance_incident;
CREATE TRIGGER trg_mcpi_link_signals_ai
    AFTER INSERT ON markov_chain_performance_incident
    FOR EACH ROW
    EXECUTE FUNCTION trg_mcpi_link_signals_insert();


-- ---------------------------------------------------------------------------
-- 3.2. Бэкфилл для существующих инцидентов (все 129 за 30 дней).
--      Возвращает (linked_sicpp, linked_conly) — сколько записей удалось связать.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION backfill_signal_incident_links(
    p_start timestamptz DEFAULT now() - interval '30 days',
    p_end   timestamptz DEFAULT now()
)
RETURNS TABLE (linked_sicpp bigint, linked_conly bigint)
LANGUAGE plpgsql
AS $$
DECLARE
    v_window    interval;
    v_sicpp     bigint := 0;
    v_conly     bigint := 0;
    v_rowcount  bigint;
    r           record;
BEGIN
    BEGIN
        SELECT (signal_incident_link_window_min || ' minutes')::interval
        INTO v_window
        FROM markov_config
        LIMIT 1;
    EXCEPTION WHEN OTHERS THEN
        v_window := interval '60 minutes';
    END;
    IF v_window IS NULL THEN
        v_window := interval '60 minutes';
    END IF;

    FOR r IN
        SELECT id, start_timepoint
        FROM markov_chain_performance_incident
        WHERE start_timepoint >= p_start
          AND start_timepoint <  p_end
        ORDER BY start_timepoint
    LOOP
        UPDATE sicpp_incident_flag_history
           SET incident_id = r.id
         WHERE incident_id IS NULL
           AND reason = 'sicpp_started'
           AND changed_at >= r.start_timepoint - v_window
           AND changed_at <= r.start_timepoint;
        GET DIAGNOSTICS v_rowcount = ROW_COUNT;
        v_sicpp := v_sicpp + v_rowcount;

        UPDATE c_only_incident_flag_history
           SET incident_id = r.id
         WHERE incident_id IS NULL
           AND flag_value = TRUE
           AND changed_at >= r.start_timepoint - v_window
           AND changed_at <= r.start_timepoint;
        GET DIAGNOSTICS v_rowcount = ROW_COUNT;
        v_conly := v_conly + v_rowcount;
    END LOOP;

    RETURN QUERY SELECT v_sicpp, v_conly;
END;
$$;

COMMENT ON FUNCTION backfill_signal_incident_links(timestamptz, timestamptz) IS
'v26.3.1. Однократный бэкфилл связей сигнал→инцидент за исторические периоды. Идемпотентна: повторный запуск не создаёт дублей, т.к. фильтр incident_id IS NULL.';


CREATE OR REPLACE FUNCTION refresh_outlier_stats(
    p_window interval DEFAULT interval '7 days'
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_speed_k real;
    v_wait_k  real;
BEGIN
    SELECT outlier_speed_sigma, outlier_waitings_sigma
    INTO v_speed_k, v_wait_k
    FROM markov_config
    LIMIT 1;

    INSERT INTO mchain_outlier_stats AS o (
        id, computed_at, window_start, window_end,
        speed_mean, speed_std, speed_k,
        wait_mean,  wait_std,  wait_k
    )
    SELECT
        1,
        now(),
        now() - p_window,
        now(),
        avg(op_speed),   stddev(op_speed),   v_speed_k,
        avg(waitings),   stddev(waitings),   v_wait_k
    FROM performance_history
    WHERE ts >= now() - p_window
    ON CONFLICT (id) DO UPDATE SET
        computed_at  = EXCLUDED.computed_at,
        window_start = EXCLUDED.window_start,
        window_end   = EXCLUDED.window_end,
        speed_mean   = EXCLUDED.speed_mean,
        speed_std    = EXCLUDED.speed_std,
        speed_k      = EXCLUDED.speed_k,
        wait_mean    = EXCLUDED.wait_mean,
        wait_std     = EXCLUDED.wait_std,
        wait_k       = EXCLUDED.wait_k;
END;
$$;

COMMENT ON FUNCTION refresh_outlier_stats(interval) IS
'v26.3.1. Обновляет mchain_outlier_stats (singleton) по performance_history за указанное окно. Вызывать перед mark_outliers() и перед каждым обучением цепи.';

CREATE OR REPLACE FUNCTION mchain_is_outlier(
    p_speed    REAL,
    p_waitings REAL
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_stat mchain_outlier_stats%ROWTYPE;
BEGIN
    SELECT * INTO v_stat FROM mchain_outlier_stats WHERE id = 1;
    IF NOT FOUND OR v_stat.computed_at IS NULL THEN
        RETURN FALSE;
    END IF;

    IF p_speed IS NOT NULL
       AND v_stat.speed_std > 0 AND v_stat.speed_k > 0
       AND abs(p_speed - v_stat.speed_mean) > v_stat.speed_k * v_stat.speed_std THEN
        RETURN TRUE;
    END IF;

    IF p_waitings IS NOT NULL
       AND v_stat.wait_std > 0 AND v_stat.wait_k > 0
       AND abs(p_waitings - v_stat.wait_mean) > v_stat.wait_k * v_stat.wait_std THEN
        RETURN TRUE;
    END IF;

    RETURN FALSE;
END;
$$;

COMMENT ON FUNCTION mchain_is_outlier(real, real) IS
'v26.3.1. |x − μ| > k·σ по speed ИЛИ waitings. Читает кэш mchain_outlier_stats. Возвращает FALSE при отсутствии статистик.';

CREATE OR REPLACE FUNCTION mark_outliers(
    p_start timestamptz DEFAULT now() - interval '30 days',
    p_end   timestamptz DEFAULT now()
)
RETURNS bigint
LANGUAGE plpgsql
AS $$
DECLARE
    v_count bigint;
BEGIN
    PERFORM refresh_outlier_stats();

    UPDATE performance_history
       SET is_outlier = mchain_is_outlier(op_speed, waitings)
     WHERE ts >= p_start
       AND ts <  p_end;

    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN v_count;
END;
$$;

COMMENT ON FUNCTION mark_outliers(timestamptz, timestamptz) IS
'v26.3.1. Размечает performance_history.is_outlier на заданном диапазоне. Возвращает число затронутых строк.';

-- 4.4. «Чистое» представление для обучения цепи.
CREATE OR REPLACE VIEW performance_history_clean AS
SELECT *
FROM performance_history
WHERE NOT COALESCE(is_outlier, FALSE);

COMMENT ON VIEW performance_history_clean IS
'v26.3.1. performance_history без выбросов (is_outlier = FALSE/NULL). Источник для mchain_initial_train_from_history и других функций обучения.';

CREATE OR REPLACE FUNCTION mchain_diagnose_profile_aggregated()
RETURNS TABLE (check_name text, status text, details text)
LANGUAGE plpgsql
AS $$
DECLARE
    v_total_rows bigint;
    v_last_ts    timestamptz;
    v_op_rows    bigint;
    v_last_op_ts timestamptz;
BEGIN
    IF to_regclass('profile_aggregated') IS NULL THEN
        RETURN QUERY SELECT
            'table_exists'::text, 'MISSING'::text,
            'profile_aggregated отсутствует в текущей схеме — build_profile_hourly шаг 3 не сможет заполнить avg_entropy/critical_state_share.'::text;
        RETURN;
    END IF;

    EXECUTE 'SELECT count(*), max(ts) FROM profile_aggregated'
        INTO v_total_rows, v_last_ts;
    RETURN QUERY SELECT
        'total_rows'::text,
        (CASE WHEN v_total_rows > 0 THEN 'OK' ELSE 'EMPTY' END)::text,
        format('count=%s, last_ts=%s', v_total_rows, v_last_ts);

    EXECUTE $sql$
        SELECT count(*), max(ts)
        FROM profile_aggregated
        WHERE profile_type = 'operational'
    $sql$ INTO v_op_rows, v_last_op_ts;
    RETURN QUERY SELECT
        'operational_rows'::text,
        (CASE WHEN v_op_rows > 0 THEN 'OK' ELSE 'EMPTY' END)::text,
        format('count=%s, last_ts=%s', v_op_rows, v_last_op_ts);

    IF v_op_rows = 0 THEN
        RETURN QUERY SELECT
            'diagnosis'::text, 'CRITICAL'::text,
            'Нет operational-строк. Запустите mchain_rebuild_profile_aggregated() или почините writer.'::text;
    ELSIF v_last_op_ts < now() - interval '1 day' THEN
        RETURN QUERY SELECT
            'freshness'::text, 'WARNING'::text,
            format('Последняя строка %s назад — writer, вероятно, сломан.', now() - v_last_op_ts)::text;
    ELSE
        RETURN QUERY SELECT
            'diagnosis'::text, 'OK'::text,
            'Источник свежий, шаг 3a отработает штатно.'::text;
    END IF;
END;
$$;

COMMENT ON FUNCTION mchain_diagnose_profile_aggregated() IS
'v26.3.1. Проверяет наличие/свежесть profile_aggregated. Вызывать перед отчётами.';

CREATE OR REPLACE FUNCTION mchain_rebuild_profile_aggregated(
    p_start timestamptz DEFAULT now() - interval '30 days',
    p_end   timestamptz DEFAULT now()
)
RETURNS TABLE (buckets_written bigint)
LANGUAGE plpgsql
AS $$
DECLARE
    v_count bigint := 0;
BEGIN
    IF to_regclass('profile_aggregated') IS NULL THEN
        RAISE EXCEPTION 'profile_aggregated отсутствует — восстанавливать некуда';
    END IF;

    DELETE FROM profile_aggregated
     WHERE profile_type = 'operational'
       AND ts >= p_start
       AND ts <  p_end;

    INSERT INTO profile_aggregated (ts, profile_type, entropy, critical_ratio)
    WITH dwell AS (
        SELECT
            tl.ts,
            tl.to_state,
            date_trunc('hour', tl.ts)                                    AS hour_ts,
            EXTRACT(epoch FROM (
                LEAST(
                    LEAD(tl.ts) OVER (ORDER BY tl.ts, tl.id),
                    date_trunc('hour', tl.ts) + interval '1 hour',
                    now()
                ) - tl.ts
            ))                                                           AS dwell_sec
        FROM transition_log tl
        WHERE tl.ts >= p_start - interval '1 hour'
          AND tl.ts <  p_end   + interval '1 hour'
    ),
    hourly AS (
        SELECT
            hour_ts AS ts,
            to_state,
            SUM(GREATEST(dwell_sec, 0)) AS sec
        FROM dwell
        WHERE hour_ts >= p_start
          AND hour_ts <  p_end
          AND GREATEST(dwell_sec, 0) > 0
        GROUP BY hour_ts, to_state
    ),
    probs AS (
        SELECT
            ts,
            to_state,
            sec,
            sec / NULLIF(SUM(sec) OVER (PARTITION BY ts), 0) AS pr
        FROM hourly
    ),
    agg AS (
        SELECT
            ts,
            (-SUM(pr * ln(pr) / ln(2.0)))::real                          AS entropy,
            (SUM(CASE WHEN to_state IN (SELECT state_id FROM critical_states)
                      THEN pr ELSE 0 END))::real                          AS critical_ratio
        FROM probs
        WHERE pr > 0
        GROUP BY ts
    )
    SELECT ts, 'operational', entropy, critical_ratio FROM agg;

    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN QUERY SELECT v_count;
END;
$$;

COMMENT ON FUNCTION mchain_rebuild_profile_aggregated(timestamptz, timestamptz) IS
'v26.3.1. Восстанавливает profile_aggregated(profile_type=operational) из transition_log: dwell-time распределение по to_state внутри часа. Используется как замена сломанного writer-а.';

