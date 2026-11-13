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
-- version 26.2.1.1
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
    -- Шаг 1: базовые метрики из pg_expecto
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

    -- Шаг 2: JS-дивергенция из profile_comparison_log
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

    -- Шаг 3: энтропия и доля критических состояний из profile_aggregated
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

    -- Шаг 4: количество аномалий из anomaly_log
    UPDATE profile_hourly p
    SET anomaly_count = COALESCE((
            SELECT count(*)::integer
            FROM anomaly_log a
            WHERE date_trunc('hour', a.detected_at) = p.bucket_hour
        ), 0),
        created_at = now()
    WHERE p.bucket_hour >= date_trunc('hour', p_period_start);

    -- Шаг 5: SICPP активность (доля времени и число активаций)
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
            SUM(CASE WHEN signal_active
                     THEN extract(epoch FROM (COALESCE(next_changed_at, now()) - changed_at))
                     ELSE 0 END) / 3600.0                                AS active_share,
            SUM(CASE WHEN signal_active THEN 1 ELSE 0 END)::integer       AS activations
        FROM spans
        GROUP BY date_trunc('hour', changed_at)
    ) s
    WHERE p.bucket_hour = s.hour_ts;

    -- Шаг 6: C-only активность
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
            SUM(CASE WHEN result_value
                     THEN extract(epoch FROM (COALESCE(next_changed_at, now()) - changed_at))
                     ELSE 0 END) / 3600.0                                AS active_share,
            SUM(CASE WHEN result_value THEN 1 ELSE 0 END)::integer        AS activations
        FROM spans
        GROUP BY date_trunc('hour', changed_at)
    ) s
    WHERE p.bucket_hour = s.hour_ts;

    -- Шаг 7: sicpp_lead_time_avg (по эпизодам, связанным с инцидентами часа)
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

    -- Шаг 8: c_only_lead_time_avg
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
'Часовое агрегирование. База — cluster_stat_median (speed/waitings/correlation/slopes). Марковские метрики — из profile_comparison_log (JS), profile_aggregated (энтропия, критические), anomaly_log, sicpp_history, c_only_incident_flag_history, sicpp_incident_flag_history. Идемпотентна (UPSERT + UPDATE).';


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