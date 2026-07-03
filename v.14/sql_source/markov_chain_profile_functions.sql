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
-- markov_chain_profile_functions.sql
-- version 14.1
--------------------------------------------------------------------------------
-- Функции для расчета метрик профиля нагрузки на основе цепи Маркова 
--------------------------------------------------------------------------------
--
-- calculate_profile_metrics
-- Назначение: вычисляет набор профильных метрик для заданного временного окна.
--
-- save_operational_profile
-- Назначение: вычисляет профиль за последние 60 минут и сохраняет его
--
-- save_daily_profile
-- Назначение: сохраненить дневной профиль
--
-- save_weekly_profile
-- Назначение: сохраненить недельный профиль
--
-- build_baseline_profile
-- Назначение: строит эталонный профиль на основе исторических данных за период,
--             исключая инцидентные окна.
--
-- detect_anomaly
-- Назначение: для заданного типа профиля и временного слота вычисляет Z-оценки
--             текущих метрик относительно эталона и возвращает список аномалий.
--
-- get_deviation_report
-- Назначение: возвращает отчёт об отклонениях для последнего профиля указанного
--             типа, сравнивая с эталоном.
--
-- log_anomaly
-- Назначение: Функция логирования аномалий
--
-- check_and_log_anomalies
-- Назначение: Функция проверки и логирования аномалий для последнего профиля
--
-- append_performance_history
-- Назначение: Инкрементально добавляет или обновляет записи в performance_history за указанный период (без TRUNCATE). Использует cluster_stat_median как источник.
--
-- Функция: generate_profile_summary_report
-- Назначение: формирует краткий отчёт по текущему состоянию профилей нагрузки
--             (operational, daily, weekly) на основе данных из profile_aggregated.
--
-- Функция: generate_detailed_profile_report
-- Назначение: формирует расширенный отчёт по профилям нагрузки (operational, daily, weekly)
--             с подробной интерпретацией каждой метрики, анализом аномалий и
--             общей оценкой стабильности системы.



-- -----------------------------------------------------------------------------

-- =============================================================================
-- Примеры использования
-- =============================================================================
/*
-- Сохранение профилей (по cron)
SELECT save_operational_profile();
SELECT save_daily_profile();
SELECT save_weekly_profile();

-- Ручная проверка аномалий для суточного профиля с порогом 2.5
SELECT check_anomalies_manual('daily', 2.5);

-- Просмотр последних аномалий
SELECT * FROM anomaly_log ORDER BY detected_at DESC LIMIT 10;

-- Подтверждение аномалии (ручная обработка)
UPDATE anomaly_log
SET acknowledged = TRUE, acknowledged_by = 'admin', acknowledged_at = now()
WHERE id = 123;
*/
-- =============================================================================


-- =============================================================================
-- 2. Хранимые функции для профилирования производительности
-- =============================================================================
-- ВНИМАНИЕ: Таблицы profile_aggregated, profile_baseline, anomaly_log,
-- excluded_windows должны быть созданы заранее (файл markov_chain_profile_tables.sql).
-- Данный скрипт содержит только определения функций.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- calculate_profile_metrics
-- Назначение: вычисляет набор профильных метрик для заданного временного окна.
-- Параметры:
--   p_start TIMESTAMPTZ – начало окна
--   p_end   TIMESTAMPTZ – конец окна
-- Возвращает:
--   Таблицу с полями, соответствующими структуре profile_aggregated:
--     state_histogram       JSONB
--     avg_correlation       REAL
--     critical_ratio        REAL
--     entropy               REAL
--     avg_os_angle          REAL
--     avg_wait_angle        REAL
--     unique_states_count   INT
--     avg_transition_length REAL
--     self_loop_ratio       REAL
--     top_transition        JSONB
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION calculate_profile_metrics(
    p_start TIMESTAMPTZ,
    p_end   TIMESTAMPTZ
)
RETURNS TABLE (
    state_histogram       JSONB,
    avg_correlation       REAL,
    critical_ratio        REAL,
    entropy               REAL,
    avg_os_angle          REAL,
    avg_wait_angle        REAL,
    unique_states_count   INT,
    avg_transition_length REAL,
    self_loop_ratio       REAL,
    top_transition        JSONB
)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_total_transitions BIGINT;
    v_critical_ids INT[];
    v_histogram JSONB;
    v_entropy REAL;
    v_avg_corr REAL;
    v_crit_ratio REAL;
    v_avg_os REAL;
    v_avg_wait REAL;
    v_unique INT;
    v_avg_len REAL;
    v_self_loop REAL;
    v_top JSONB;
BEGIN
    IF p_start > p_end THEN
        RAISE EXCEPTION 'Начальная дата позже конечной.';
    END IF;

    SELECT array_agg(state_id) INTO v_critical_ids FROM critical_states;
    IF v_critical_ids IS NULL THEN
        v_critical_ids := '{}'::INT[];
    END IF;

    -- 1. Гистограмма
    WITH state_counts AS (
        SELECT to_state, COUNT(*) AS cnt
        FROM transition_log
        WHERE ts >= p_start AND ts < p_end
        GROUP BY to_state
    ),
    total AS (SELECT SUM(cnt) AS total FROM state_counts)
    SELECT jsonb_object_agg(
        to_state::TEXT,
        jsonb_build_object('count', cnt, 'pct', ROUND((cnt::NUMERIC / NULLIF(total, 0)) * 100, 2))
    ) INTO v_histogram
    FROM state_counts, total
    WHERE total > 0;

    -- 2. Средняя корреляция
    SELECT AVG(ph.correlation) INTO v_avg_corr
    FROM performance_history ph
    WHERE ph.ts >= p_start AND ph.ts < p_end;

    -- 3. Доля критических состояний
    SELECT COUNT(*) FILTER (WHERE tl.to_state = ANY(v_critical_ids))::REAL / NULLIF(COUNT(*), 0)
    INTO v_crit_ratio
    FROM transition_log tl
    WHERE tl.ts >= p_start AND tl.ts < p_end;

    -- 4. Энтропия (исправлено)
    WITH probs AS (
        SELECT to_state, COUNT(*)::REAL / SUM(COUNT(*)) OVER () AS p
        FROM transition_log
        WHERE ts >= p_start AND ts < p_end
        GROUP BY to_state
    )
    SELECT -SUM(p * (LN(p) / LN(2))) INTO v_entropy
    FROM probs
    WHERE p > 0;

    -- 5. Средние углы
    SELECT AVG(ph.os_angle), AVG(ph.wait_angle)
    INTO v_avg_os, v_avg_wait
    FROM performance_history ph
    WHERE ph.ts >= p_start AND ph.ts < p_end;

    -- 6. Уникальные состояния
    SELECT COUNT(DISTINCT to_state) INTO v_unique
    FROM transition_log
    WHERE ts >= p_start AND ts < p_end;

    -- 7. Средняя длина перехода
    WITH intervals AS (
        SELECT ts, LAG(ts) OVER (ORDER BY ts) AS prev_ts
        FROM transition_log
        WHERE ts >= p_start AND ts < p_end
    )
    SELECT AVG(EXTRACT(EPOCH FROM (ts - prev_ts)) / 60) INTO v_avg_len
    FROM intervals
    WHERE prev_ts IS NOT NULL;

    -- 8. Доля петель
    SELECT COUNT(*) FILTER (WHERE from_state = to_state)::REAL / NULLIF(COUNT(*), 0)
    INTO v_self_loop
    FROM transition_log
    WHERE ts >= p_start AND ts < p_end;

    -- 9. Наиболее частый переход
    SELECT jsonb_build_object('from_state', from_state, 'to_state', to_state, 'count', cnt)
    INTO v_top
    FROM (
        SELECT from_state, to_state, COUNT(*) AS cnt,
               ROW_NUMBER() OVER (ORDER BY COUNT(*) DESC) AS rn
        FROM transition_log
        WHERE ts >= p_start AND ts < p_end
        GROUP BY from_state, to_state
    ) t
    WHERE rn = 1;

    RETURN QUERY
    SELECT
        COALESCE(v_histogram, '{}'::JSONB),
        COALESCE(v_avg_corr, 0.0)::REAL,
        COALESCE(v_crit_ratio, 0.0)::REAL,
        COALESCE(v_entropy, 0.0)::REAL,
        COALESCE(v_avg_os, 0.0)::REAL,
        COALESCE(v_avg_wait, 0.0)::REAL,
        COALESCE(v_unique, 0)::INT,
        COALESCE(v_avg_len, 0.0)::REAL,
        COALESCE(v_self_loop, 0.0)::REAL,
        COALESCE(v_top, '{}'::JSONB);
END;
$$;
COMMENT ON FUNCTION calculate_profile_metrics IS
'вычисляет набор профильных метрик для заданного временного окна.';


-- -----------------------------------------------------------------------------
-- save_operational_profile
-- Назначение: вычисляет профиль за последние 60 минут и сохраняет его
--             в profile_aggregated с profile_type='operational'.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION save_operational_profile()
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    v_end   TIMESTAMPTZ := now();
    v_start TIMESTAMPTZ := v_end - INTERVAL '60 minutes';
    v_metrics RECORD;
    v_hour SMALLINT := EXTRACT(HOUR FROM v_end)::SMALLINT;
    v_dow  SMALLINT := EXTRACT(DOW FROM v_end)::SMALLINT;
    v_result TEXT;
BEGIN
    SELECT * INTO v_metrics
    FROM calculate_profile_metrics(v_start, v_end);

    INSERT INTO profile_aggregated (
        profile_type, ts, hour, dow, window_start, window_end,
        state_histogram, avg_correlation, critical_ratio, entropy,
        avg_os_angle, avg_wait_angle, unique_states_count,
        avg_transition_length, self_loop_ratio, top_transition
    ) VALUES (
        'operational', v_end, v_hour, v_dow, v_start, v_end,
        v_metrics.state_histogram, v_metrics.avg_correlation,
        v_metrics.critical_ratio, v_metrics.entropy,
        v_metrics.avg_os_angle, v_metrics.avg_wait_angle,
        v_metrics.unique_states_count,
        v_metrics.avg_transition_length, v_metrics.self_loop_ratio,
        v_metrics.top_transition
    );

    -- Проверка аномалий с порогом 2.0 (можно настроить)
    v_result := check_and_log_anomalies('operational', 2.0);

    RETURN format('Operational profile saved at %s. %s', v_end, v_result);
END;
$$;

COMMENT ON FUNCTION save_operational_profile() IS
'Вычисляет профиль за последние 60 минут, сохраняет его и автоматически проверяет аномалии.';


-- -----------------------------------------------------------------------------
-- save_daily_profile
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION save_daily_profile()
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    v_end   TIMESTAMPTZ := now();
    v_start TIMESTAMPTZ := v_end - INTERVAL '24 hours';
    v_metrics RECORD;
    v_hour SMALLINT := EXTRACT(HOUR FROM v_end)::SMALLINT;
    v_dow  SMALLINT := EXTRACT(DOW FROM v_end)::SMALLINT;
    v_result TEXT;
BEGIN
    SELECT * INTO v_metrics
    FROM calculate_profile_metrics(v_start, v_end);

    INSERT INTO profile_aggregated (
        profile_type, ts, hour, dow, window_start, window_end,
        state_histogram, avg_correlation, critical_ratio, entropy,
        avg_os_angle, avg_wait_angle, unique_states_count,
        avg_transition_length, self_loop_ratio, top_transition
    ) VALUES (
        'daily', v_end, v_hour, v_dow, v_start, v_end,
        v_metrics.state_histogram, v_metrics.avg_correlation,
        v_metrics.critical_ratio, v_metrics.entropy,
        v_metrics.avg_os_angle, v_metrics.avg_wait_angle,
        v_metrics.unique_states_count,
        v_metrics.avg_transition_length, v_metrics.self_loop_ratio,
        v_metrics.top_transition
    );

    v_result := check_and_log_anomalies('daily', 2.0);

    RETURN format('Daily profile saved at %s. %s', v_end, v_result);
END;
$$;

COMMENT ON FUNCTION save_daily_profile() IS
'Вычисляет профиль за последние 24 часа, сохраняет его и автоматически проверяет аномалии.';


-- -----------------------------------------------------------------------------
-- save_weekly_profile
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION save_weekly_profile()
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    v_end   TIMESTAMPTZ := now();
    v_start TIMESTAMPTZ := v_end - INTERVAL '7 days';
    v_metrics RECORD;
    v_hour SMALLINT := EXTRACT(HOUR FROM v_end)::SMALLINT;
    v_dow  SMALLINT := EXTRACT(DOW FROM v_end)::SMALLINT;
    v_result TEXT;
BEGIN
    SELECT * INTO v_metrics
    FROM calculate_profile_metrics(v_start, v_end);

    INSERT INTO profile_aggregated (
        profile_type, ts, hour, dow, window_start, window_end,
        state_histogram, avg_correlation, critical_ratio, entropy,
        avg_os_angle, avg_wait_angle, unique_states_count,
        avg_transition_length, self_loop_ratio, top_transition
    ) VALUES (
        'weekly', v_end, v_hour, v_dow, v_start, v_end,
        v_metrics.state_histogram, v_metrics.avg_correlation,
        v_metrics.critical_ratio, v_metrics.entropy,
        v_metrics.avg_os_angle, v_metrics.avg_wait_angle,
        v_metrics.unique_states_count,
        v_metrics.avg_transition_length, v_metrics.self_loop_ratio,
        v_metrics.top_transition
    );

    v_result := check_and_log_anomalies('weekly', 2.0);

    RETURN format('Weekly profile saved at %s. %s', v_end, v_result);
END;
$$;

COMMENT ON FUNCTION save_weekly_profile() IS
'Вычисляет профиль за последние 7 дней, сохраняет его и автоматически проверяет аномалии.';



-- =============================================================================
-- 2.2. Функции для работы с эталоном
-- =============================================================================
-- =============================================================================
-- Функция: build_baseline_profile (исправленная версия, с ограничением периода 30 дней)
-- Назначение: строит эталонный профиль на основе исторических данных за период,
--             исключая инцидентные окна. Заполняет все метрики, исправляет расчёт
--             энтропии, период по умолчанию – 30 дней.
-- Параметры:
--   p_start                     TIMESTAMPTZ – начало периода (по умолч. now() - interval '30 days')
--   p_end                       TIMESTAMPTZ – конец периода (по умолч. now())
--   p_baseline_name             TEXT        – имя эталона (по умолч. 'default')
--   p_exclude_incident_window_min INT       – длительность окна вокруг инцидента (мин) (по умолч. 30)
--   p_min_hours_per_slot        INT         – минимальное число часов в слоте для включения (по умолч. 3)
-- Возвращает: TEXT – отчёт о количестве заполненных слотов.
-- =============================================================================
CREATE OR REPLACE FUNCTION build_baseline_profile(
    p_start                     TIMESTAMPTZ DEFAULT now() - INTERVAL '30 days',
    p_end                       TIMESTAMPTZ DEFAULT now(),
    p_baseline_name             TEXT        DEFAULT 'default',
    p_exclude_incident_window_min INT        DEFAULT 30,
    p_min_hours_per_slot        INT         DEFAULT 1
)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    v_exclude_interval INTERVAL := (p_exclude_incident_window_min || ' minutes')::INTERVAL;
    v_metrics RECORD;
    v_hour INT;
    v_dow INT;
    v_total_slots INT := 0;
    v_processed_slots INT := 0;
    v_total_slots_all CONSTANT INT := 24 * 7;
BEGIN
    DELETE FROM profile_baseline WHERE baseline_name = p_baseline_name;

    RAISE NOTICE 'Начало построения эталона "%s" за период с %s по %s. Всего слотов: %s',
                 p_baseline_name, p_start, p_end, v_total_slots_all;

    FOR v_hour IN 0..23 LOOP
        RAISE NOTICE 'Обработка часа %s из 24', v_hour;
        FOR v_dow IN 0..6 LOOP

            WITH candidate_hours AS (
                SELECT DISTINCT
                    date_trunc('hour', ph.ts) AS hour_ts
                FROM performance_history ph
                WHERE ph.ts >= p_start AND ph.ts < p_end
                  AND EXTRACT(HOUR FROM ph.ts) = v_hour
                  AND EXTRACT(DOW FROM ph.ts) = v_dow
                  AND NOT EXISTS (
                      SELECT 1
                      FROM performance_incident pi
                      WHERE pi.start_timepoint BETWEEN
                            ph.ts - v_exclude_interval AND ph.ts + v_exclude_interval
                  )
            ),
            perf_agg AS (
                SELECT
                    date_trunc('hour', ph.ts) AS hour_ts,
                    AVG(ph.correlation) AS avg_corr,
                    STDDEV(ph.correlation) AS std_corr,
                    AVG(ph.os_angle) AS avg_os,
                    STDDEV(ph.os_angle) AS std_os,
                    AVG(ph.wait_angle) AS avg_wait,
                    STDDEV(ph.wait_angle) AS std_wait,
                    COUNT(*) AS sample_count
                FROM performance_history ph
                WHERE EXISTS (
                    SELECT 1 FROM candidate_hours ch
                    WHERE ph.ts >= ch.hour_ts AND ph.ts < ch.hour_ts + INTERVAL '1 hour'
                )
                GROUP BY date_trunc('hour', ph.ts)
            ),
            trans_agg AS (
                SELECT
                    tl.hour_ts,
                    COUNT(*) AS total_trans,
                    AVG(CASE WHEN tl.from_state = tl.to_state THEN 1.0 ELSE 0.0 END) AS self_loop_ratio,
                    AVG(CASE WHEN tl.to_state = ANY(SELECT state_id FROM critical_states) THEN 1.0 ELSE 0.0 END) AS critical_ratio,
                    COUNT(DISTINCT tl.to_state) AS unique_states,
                    AVG(ABS(tl.to_state - tl.from_state)) AS avg_transition_length,
                    top.top_transition,
                    ent.entropy
                FROM (
                    SELECT
                        date_trunc('hour', ts) AS hour_ts,
                        from_state,
                        to_state
                    FROM transition_log
                    WHERE EXISTS (
                        SELECT 1 FROM candidate_hours ch
                        WHERE ts >= ch.hour_ts AND ts < ch.hour_ts + INTERVAL '1 hour'
                    )
                ) tl
                CROSS JOIN LATERAL (
                    SELECT jsonb_build_object('from_state', from_state, 'to_state', to_state, 'cnt', cnt) AS top_transition
                    FROM (
                        SELECT from_state, to_state, COUNT(*) AS cnt,
                               ROW_NUMBER() OVER (ORDER BY COUNT(*) DESC) AS rn
                        FROM transition_log tl2
                        WHERE date_trunc('hour', tl2.ts) = tl.hour_ts
                        GROUP BY from_state, to_state
                    ) t
                    WHERE rn = 1
                ) top
                CROSS JOIN LATERAL (
                    SELECT -SUM(p * ln(p) / ln(2)) AS entropy
                    FROM (
                        SELECT COUNT(*)::REAL / SUM(COUNT(*)) OVER () AS p
                        FROM transition_log tl2
                        WHERE date_trunc('hour', tl2.ts) = tl.hour_ts
                        GROUP BY to_state
                    ) probs
                    WHERE p > 0
                ) ent
                GROUP BY tl.hour_ts, top.top_transition, ent.entropy
            ),
            hour_metrics AS (
                SELECT
                    COALESCE(p.hour_ts, t.hour_ts) AS hour_ts,
                    p.avg_corr,
                    p.std_corr,
                    p.avg_os,
                    p.std_os,
                    p.avg_wait,
                    p.std_wait,
                    p.sample_count AS perf_samples,
                    t.total_trans,
                    t.self_loop_ratio,
                    t.critical_ratio,
                    t.unique_states,
                    t.avg_transition_length,
                    t.top_transition,
                    t.entropy
                FROM perf_agg p
                FULL JOIN trans_agg t ON p.hour_ts = t.hour_ts
            ),
            hourly_distribution AS (
                SELECT
                    to_state AS state_id,
                    date_trunc('hour', ts) AS hour_ts,
                    COUNT(*)::REAL / SUM(COUNT(*)) OVER (PARTITION BY date_trunc('hour', ts)) AS dolya
                FROM transition_log
                WHERE EXISTS (
                    SELECT 1 FROM candidate_hours ch
                    WHERE ts >= ch.hour_ts AND ts < ch.hour_ts + INTERVAL '1 hour'
                )
                GROUP BY date_trunc('hour', ts), to_state
            ),
            slot_agg AS (
                SELECT
                    COUNT(*) AS hour_count,
                    AVG(avg_corr) AS avg_correlation_mean,
                    COALESCE(STDDEV(avg_corr), 0) AS avg_correlation_std,
                    AVG(entropy) AS entropy_mean,
                    COALESCE(STDDEV(entropy), 0) AS entropy_std,
                    AVG(critical_ratio) AS critical_ratio_mean,
                    COALESCE(STDDEV(critical_ratio), 0) AS critical_ratio_std,
                    AVG(avg_os) AS avg_os_angle_mean,
                    COALESCE(STDDEV(avg_os), 0) AS avg_os_angle_std,
                    AVG(avg_wait) AS avg_wait_angle_mean,
                    COALESCE(STDDEV(avg_wait), 0) AS avg_wait_angle_std,
                    AVG(self_loop_ratio) AS self_loop_ratio_mean,
                    COALESCE(STDDEV(self_loop_ratio), 0) AS self_loop_ratio_std,
                    AVG(unique_states) AS unique_states_count_mean,
                    COALESCE(STDDEV(unique_states), 0) AS unique_states_count_std,
                    AVG(avg_transition_length) AS avg_transition_length_mean,
                    COALESCE(STDDEV(avg_transition_length), 0) AS avg_transition_length_std,
                    AVG((top_transition->>'cnt')::REAL) AS top_transition_freq_mean,
                    COALESCE(STDDEV((top_transition->>'cnt')::REAL), 0) AS top_transition_freq_std,
                    (SELECT jsonb_build_object('from_state', from_state, 'to_state', to_state)
                     FROM (
                         SELECT (top_transition->>'from_state')::SMALLINT AS from_state,
                                (top_transition->>'to_state')::SMALLINT AS to_state,
                                COUNT(*) AS freq
                         FROM hour_metrics
                         WHERE top_transition IS NOT NULL
                         GROUP BY from_state, to_state
                         ORDER BY COUNT(*) DESC
                         LIMIT 1
                     ) top_pair) AS top_transition_pair,
                    (SELECT jsonb_object_agg(state_id, avg_dolya)
                     FROM (
                         SELECT state_id, AVG(dolya) AS avg_dolya
                         FROM hourly_distribution
                         GROUP BY state_id
                     ) dist_avg
                    ) AS state_histogram_mean,
                    (SELECT jsonb_object_agg(state_id, stddev_dolya)
                     FROM (
                         SELECT state_id, STDDEV(dolya) AS stddev_dolya
                         FROM hourly_distribution
                         GROUP BY state_id
                     ) dist_std
                    ) AS state_histogram_std
                FROM hour_metrics
                WHERE avg_corr IS NOT NULL OR entropy IS NOT NULL
            )
            SELECT * INTO v_metrics
            FROM slot_agg;

            IF v_metrics.hour_count >= p_min_hours_per_slot THEN
                INSERT INTO profile_baseline (
                    baseline_name, hour, dow,
                    period_start, period_end,
                    avg_correlation_mean, avg_correlation_std,
                    entropy_mean, entropy_std,
                    critical_ratio_mean, critical_ratio_std,
                    avg_os_angle_mean, avg_os_angle_std,
                    avg_wait_angle_mean, avg_wait_angle_std,
                    self_loop_ratio_mean, self_loop_ratio_std,
                    unique_states_count_mean, unique_states_count_std,
                    avg_transition_length_mean, avg_transition_length_std,
                    top_transition_freq_mean, top_transition_freq_std,
                    top_transition_pair,
                    state_histogram_mean, state_histogram_std
                ) VALUES (
                    p_baseline_name, v_hour, v_dow,
                    p_start, p_end,
                    v_metrics.avg_correlation_mean, v_metrics.avg_correlation_std,
                    v_metrics.entropy_mean, v_metrics.entropy_std,
                    v_metrics.critical_ratio_mean, v_metrics.critical_ratio_std,
                    v_metrics.avg_os_angle_mean, v_metrics.avg_os_angle_std,
                    v_metrics.avg_wait_angle_mean, v_metrics.avg_wait_angle_std,
                    v_metrics.self_loop_ratio_mean, v_metrics.self_loop_ratio_std,
                    v_metrics.unique_states_count_mean, v_metrics.unique_states_count_std,
                    v_metrics.avg_transition_length_mean, v_metrics.avg_transition_length_std,
                    v_metrics.top_transition_freq_mean, v_metrics.top_transition_freq_std,
                    v_metrics.top_transition_pair,
                    COALESCE(v_metrics.state_histogram_mean, '{}'::JSONB),
                    COALESCE(v_metrics.state_histogram_std, '{}'::JSONB)
                );
                v_total_slots := v_total_slots + 1;
            END IF;
        END LOOP;

        -- Обновление прогресса после обработки всех дней для текущего часа
        v_processed_slots := v_processed_slots + 7;
        RAISE NOTICE 'Прогресс: % из % слотов обработано (%.1f%%). Заполнено слотов: %',
                     v_processed_slots, v_total_slots_all,
                     (v_processed_slots::numeric / v_total_slots_all * 100),
                     v_total_slots;
    END LOOP;

    RAISE NOTICE 'Построение эталона "%s" завершено. Заполнено %s слотов (минимум %s часов на слот).',
                 p_baseline_name, v_total_slots, p_min_hours_per_slot;

    RETURN format('Baseline "%s" rebuilt with %s slots filled (minimum %s hours per slot).',
                  p_baseline_name, v_total_slots, p_min_hours_per_slot);
END;
$$;

COMMENT ON FUNCTION build_baseline_profile(TIMESTAMPTZ, TIMESTAMPTZ, TEXT, INT, INT) IS
'Строит эталонный профиль с исправленным расчётом энтропии, заполнением всех метрик и периодом по умолчанию 30 дней.';



-- -----------------------------------------------------------------------------
-- detect_anomaly
-- Назначение: для заданного типа профиля и временного слота вычисляет Z-оценки
--             текущих метрик относительно эталона и возвращает список аномалий.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION detect_anomaly(
    p_profile_type TEXT,
    p_hour         INT,
    p_dow          INT,
    p_threshold    REAL DEFAULT 2.0
)
RETURNS TABLE (
    metric_name   TEXT,
    current_value REAL,
    baseline_mean REAL,
    baseline_std  REAL,
    z_score       REAL,
    threshold     REAL
)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_current RECORD;
    v_baseline RECORD;
BEGIN
    IF p_profile_type NOT IN ('operational', 'daily', 'weekly') THEN
        RAISE EXCEPTION 'Некорректный тип профиля: %. Допустимые: operational, daily, weekly.', p_profile_type;
    END IF;

    -- Получаем последний профиль указанного типа
    SELECT
        avg_correlation, critical_ratio, entropy,
        avg_os_angle, avg_wait_angle, self_loop_ratio
    INTO v_current
    FROM profile_aggregated
    WHERE profile_type = p_profile_type
    ORDER BY ts DESC
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Нет данных для профиля типа "%".', p_profile_type;
    END IF;

    -- Пытаемся получить эталон для конкретного слота
    SELECT
        avg_correlation_mean, avg_correlation_std,
        entropy_mean, entropy_std,
        critical_ratio_mean, critical_ratio_std,
        avg_os_angle_mean, avg_os_angle_std,
        avg_wait_angle_mean, avg_wait_angle_std,
        self_loop_ratio_mean, self_loop_ratio_std
    INTO v_baseline
    FROM profile_baseline
    WHERE baseline_name = 'default'
      AND hour = p_hour
      AND dow = p_dow
    LIMIT 1;

    IF NOT FOUND THEN
        -- Пробуем эталон без разбивки по времени (если есть запись с NULL hour/dow)
        SELECT
            avg_correlation_mean, avg_correlation_std,
            entropy_mean, entropy_std,
            critical_ratio_mean, critical_ratio_std,
            avg_os_angle_mean, avg_os_angle_std,
            avg_wait_angle_mean, avg_wait_angle_std,
            self_loop_ratio_mean, self_loop_ratio_std
        INTO v_baseline
        FROM profile_baseline
        WHERE baseline_name = 'default'
          AND hour IS NULL
          AND dow IS NULL
        LIMIT 1;

        IF NOT FOUND THEN
            -- Вместо исключения просто выводим предупреждение и возвращаем пустой результат
            RAISE WARNING 'Нет эталонного профиля для имени "default" и слота hour=%, dow=%. Пропускаем проверку аномалий.', p_hour, p_dow;
            RETURN;
        END IF;
    END IF;

    -- Проверка каждой метрики (аналогично исходной функции)
    -- avg_correlation
    IF v_baseline.avg_correlation_std > 0 THEN
        z_score := (v_current.avg_correlation - v_baseline.avg_correlation_mean) / v_baseline.avg_correlation_std;
        IF ABS(z_score) > p_threshold THEN
            metric_name := 'avg_correlation';
            current_value := v_current.avg_correlation;
            baseline_mean := v_baseline.avg_correlation_mean;
            baseline_std := v_baseline.avg_correlation_std;
            threshold := p_threshold;
            RETURN NEXT;
        END IF;
    END IF;

    -- entropy
    IF v_baseline.entropy_std > 0 THEN
        z_score := (v_current.entropy - v_baseline.entropy_mean) / v_baseline.entropy_std;
        IF ABS(z_score) > p_threshold THEN
            metric_name := 'entropy';
            current_value := v_current.entropy;
            baseline_mean := v_baseline.entropy_mean;
            baseline_std := v_baseline.entropy_std;
            threshold := p_threshold;
            RETURN NEXT;
        END IF;
    END IF;

    -- critical_ratio
    IF v_baseline.critical_ratio_std > 0 THEN
        z_score := (v_current.critical_ratio - v_baseline.critical_ratio_mean) / v_baseline.critical_ratio_std;
        IF ABS(z_score) > p_threshold THEN
            metric_name := 'critical_ratio';
            current_value := v_current.critical_ratio;
            baseline_mean := v_baseline.critical_ratio_mean;
            baseline_std := v_baseline.critical_ratio_std;
            threshold := p_threshold;
            RETURN NEXT;
        END IF;
    END IF;

    -- avg_os_angle
    IF v_baseline.avg_os_angle_std > 0 THEN
        z_score := (v_current.avg_os_angle - v_baseline.avg_os_angle_mean) / v_baseline.avg_os_angle_std;
        IF ABS(z_score) > p_threshold THEN
            metric_name := 'avg_os_angle';
            current_value := v_current.avg_os_angle;
            baseline_mean := v_baseline.avg_os_angle_mean;
            baseline_std := v_baseline.avg_os_angle_std;
            threshold := p_threshold;
            RETURN NEXT;
        END IF;
    END IF;

    -- avg_wait_angle
    IF v_baseline.avg_wait_angle_std > 0 THEN
        z_score := (v_current.avg_wait_angle - v_baseline.avg_wait_angle_mean) / v_baseline.avg_wait_angle_std;
        IF ABS(z_score) > p_threshold THEN
            metric_name := 'avg_wait_angle';
            current_value := v_current.avg_wait_angle;
            baseline_mean := v_baseline.avg_wait_angle_mean;
            baseline_std := v_baseline.avg_wait_angle_std;
            threshold := p_threshold;
            RETURN NEXT;
        END IF;
    END IF;

    -- self_loop_ratio
    IF v_baseline.self_loop_ratio_std > 0 THEN
        z_score := (v_current.self_loop_ratio - v_baseline.self_loop_ratio_mean) / v_baseline.self_loop_ratio_std;
        IF ABS(z_score) > p_threshold THEN
            metric_name := 'self_loop_ratio';
            current_value := v_current.self_loop_ratio;
            baseline_mean := v_baseline.self_loop_ratio_mean;
            baseline_std := v_baseline.self_loop_ratio_std;
            threshold := p_threshold;
            RETURN NEXT;
        END IF;
    END IF;
END;
$$;

COMMENT ON FUNCTION detect_anomaly(TEXT, INT, INT, REAL) IS
'Для заданного типа профиля и временного слота вычисляет Z-оценки текущих метрик относительно эталона. Если эталон отсутствует, возвращает пустой результат с предупреждением (вместо ошибки).';

COMMENT ON FUNCTION detect_anomaly(TEXT, INT, INT, REAL) IS
'Для заданного типа профиля и временного слота вычисляет Z-оценки текущих метрик относительно эталона и возвращает список метрик, превысивших порог.';


-- -----------------------------------------------------------------------------
-- get_deviation_report
-- Назначение: возвращает отчёт об отклонениях для последнего профиля указанного
--             типа, сравнивая с эталоном.
-- -----------------------------------------------------------------------------
/*
Пример:
select get_deviation_report('operational');
                         get_deviation_report
----------------------------------------------------------------------
 (entropy,2.6141396,-2.0613759,0.21822204,21.425495,CRITICAL)
 (self_loop_ratio,0.73333335,0.38636363,0.16070609,2.1590328,WARNING)

select get_deviation_report('daily');
                     get_deviation_report
--------------------------------------------------------------
 (entropy,5.4338317,-2.0613759,0.21822204,34.346703,CRITICAL)

select get_deviation_report('weekly');
                        get_deviation_report
---------------------------------------------------------------------
 (entropy,5.729506,-2.0613759,0.21822204,35.70163,CRITICAL)
 (self_loop_ratio,0.7082536,0.38636363,0.16070609,2.0029733,WARNING)
*/
CREATE OR REPLACE FUNCTION get_deviation_report(
    p_profile_type TEXT,
    p_ts           TIMESTAMPTZ DEFAULT now()
)
RETURNS TABLE (
    metric_name   TEXT,
    current_value REAL,
    baseline_mean REAL,
    baseline_std  REAL,
    z_score       REAL,
    severity      TEXT
)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_hour INT := EXTRACT(HOUR FROM p_ts)::INT;
    v_dow  INT := EXTRACT(DOW FROM p_ts)::INT;
    v_anomalies RECORD;
BEGIN
    FOR v_anomalies IN
        SELECT *
        FROM detect_anomaly(p_profile_type, v_hour, v_dow, 2.0)
    LOOP
        metric_name := v_anomalies.metric_name;
        current_value := v_anomalies.current_value;
        baseline_mean := v_anomalies.baseline_mean;
        baseline_std := v_anomalies.baseline_std;
        z_score := v_anomalies.z_score;
        severity := CASE
            WHEN ABS(v_anomalies.z_score) >= 4.0 THEN 'CRITICAL'
            WHEN ABS(v_anomalies.z_score) >= 3.0 THEN 'HIGH'
            WHEN ABS(v_anomalies.z_score) >= 2.0 THEN 'WARNING'
            ELSE 'NORMAL'
        END;
        RETURN NEXT;
    END LOOP;

    -- Если аномалий нет, возвращаем одну строку с информацией
    IF NOT FOUND THEN
        metric_name := 'NO_ANOMALIES';
        current_value := 0.0;
        baseline_mean := 0.0;
        baseline_std := 0.0;
        z_score := 0.0;
        severity := 'NORMAL';
        RETURN NEXT;
    END IF;
END;
$$;

COMMENT ON FUNCTION get_deviation_report(TEXT, TIMESTAMPTZ) IS
'Возвращает отчёт об отклонениях для последнего профиля указанного типа, сравнивая с эталоном. Определяет слот (час и день недели) на основе переданного времени.';

-- -----------------------------------------------------------------------------
-- Функция логирования аномалий
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION log_anomaly(
    p_profile_type    TEXT,
    p_hour            INT,
    p_dow             INT,
    p_anomaly_score   REAL,
    p_affected_metrics JSONB,
    p_threshold       REAL DEFAULT 2.0,
    p_details         TEXT DEFAULT NULL
)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
    v_id BIGINT;
BEGIN
    INSERT INTO anomaly_log (
        profile_type,
        hour,
        dow,
        detected_at,
        anomaly_score,
        affected_metrics,
        threshold_used,
        details
    ) VALUES (
        p_profile_type,
        p_hour,
        p_dow,
        now(),
        p_anomaly_score,
        p_affected_metrics,
        p_threshold,
        p_details
    ) RETURNING id INTO v_id;

    RETURN v_id;
END;
$$;

COMMENT ON FUNCTION log_anomaly(TEXT, INT, INT, REAL, JSONB, REAL, TEXT) IS
'Записывает обнаруженную аномалию в таблицу anomaly_log. Возвращает ID новой записи.';

-- -----------------------------------------------------------------------------
-- Функция проверки и логирования аномалий для последнего профиля
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION check_and_log_anomalies(
    p_profile_type TEXT,
    p_threshold    REAL DEFAULT 2.0
)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    v_last_profile RECORD;
    v_anomalies RECORD;
    v_anomaly_count INT := 0;
    v_affected_metrics JSONB := '[]'::JSONB;
    v_anomaly_score REAL := 0.0;
    v_details TEXT := '';
BEGIN
    -- Получить последний профиль указанного типа
    SELECT
        profile_type,
        ts,
        hour,
        dow,
        window_start,
        window_end,
        avg_correlation,
        critical_ratio,
        entropy,
        avg_os_angle,
        avg_wait_angle,
        self_loop_ratio
    INTO v_last_profile
    FROM profile_aggregated
    WHERE profile_type = p_profile_type
    ORDER BY ts DESC
    LIMIT 1;

    IF NOT FOUND THEN
        RETURN format('No profile found for type "%s"', p_profile_type);
    END IF;

    -- Проверяем, существует ли эталон для данного слота
    IF NOT EXISTS (
        SELECT 1 FROM profile_baseline
        WHERE baseline_name = 'default'
          AND hour = v_last_profile.hour
          AND dow = v_last_profile.dow
    ) THEN
        RETURN format('No baseline for slot hour=%s, dow=%s. Anomaly check skipped.', v_last_profile.hour, v_last_profile.dow);
    END IF;

    -- Вызвать detect_anomaly для этого слота
    FOR v_anomalies IN
        SELECT *
        FROM detect_anomaly(
            p_profile_type,
            v_last_profile.hour,
            v_last_profile.dow,
            p_threshold
        )
    LOOP
        v_anomaly_count := v_anomaly_count + 1;

        v_affected_metrics := v_affected_metrics || jsonb_build_object(
            'metric', v_anomalies.metric_name,
            'current_value', v_anomalies.current_value,
            'baseline_mean', v_anomalies.baseline_mean,
            'baseline_std', v_anomalies.baseline_std,
            'z_score', v_anomalies.z_score
        );

        v_anomaly_score := v_anomaly_score + ABS(v_anomalies.z_score);
        -- Исправлено: вместо '%.2f' используем %s и округление
        v_details := v_details || format('Metric %s: Z=%s; ',
                                         v_anomalies.metric_name,
                                         round(v_anomalies.z_score::numeric, 2)::text);
    END LOOP;

    IF v_anomaly_count > 0 THEN
        PERFORM log_anomaly(
            p_profile_type,
            v_last_profile.hour,
            v_last_profile.dow,
            v_anomaly_score,
            v_affected_metrics,
            p_threshold,
            v_details
        );

        -- Исправлено: вместо '%.2f' используем %s и округление
        RETURN format('Logged %s anomaly(ies) for %s profile at %s (score=%s)',
                      v_anomaly_count,
                      p_profile_type,
                      v_last_profile.ts,
                      round(v_anomaly_score::numeric, 2)::text);
    ELSE
        RETURN format('No anomalies detected for %s profile at %s',
                      p_profile_type,
                      v_last_profile.ts);
    END IF;
END;
$$;

COMMENT ON FUNCTION check_and_log_anomalies(TEXT, REAL) IS
'Проверяет последний профиль указанного типа на аномалии, если для данного слота существует эталон. При обнаружении записывает результат в anomaly_log.';

-- -----------------------------------------------------------------------------
-- Дополнительная функция для ручного запуска проверки аномалий
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION check_anomalies_manual(
    p_profile_type TEXT,
    p_threshold    REAL DEFAULT 2.0
)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN check_and_log_anomalies(p_profile_type, p_threshold);
END;
$$;

COMMENT ON FUNCTION check_anomalies_manual(TEXT, REAL) IS
'Ручной вызов проверки аномалий для последнего профиля указанного типа. Результат логируется в anomaly_log.';

-- Инкрементально добавляет или обновляет записи в performance_history за указанный период (без TRUNCATE). Использует cluster_stat_median как источник.
CREATE OR REPLACE FUNCTION append_performance_history(
    p_start TIMESTAMPTZ,
    p_end   TIMESTAMPTZ
)
RETURNS TEXT
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
    v_ts          TIMESTAMPTZ;
    v_window      INTERVAL := INTERVAL '1 hour';
    v_op_speed    REAL;
    v_waitings    REAL;
    v_correlation REAL;
    v_os_angle    REAL;
    v_wait_angle  REAL;
    v_inserted    INT := 0;
    v_total_minutes BIGINT;
    v_processed   BIGINT := 0;
    v_last_percent INT := -1;
    v_current_percent INT;
    v_start_ts    TIMESTAMPTZ;
    v_end_ts      TIMESTAMPTZ;
BEGIN
    -- Проверка корректности диапазона
    IF p_start > p_end THEN
        RETURN 'Ошибка: время начала должно быть меньше или равно времени окончания.';
    END IF;

    -- Округляем до минут для единообразия
    v_start_ts := date_trunc('minute', p_start);
    v_end_ts   := date_trunc('minute', p_end);

    v_total_minutes := EXTRACT(EPOCH FROM (v_end_ts - v_start_ts)) / 60 + 1;

    RAISE NOTICE 'Начало добавления записей в performance_history за период с % по % (всего % минут)',
                 v_start_ts, v_end_ts, v_total_minutes;

    v_ts := v_start_ts;

    WHILE v_ts <= v_end_ts LOOP
        -- 1. Получаем значения скорости и ожиданий в точный момент времени
        SELECT curr_op_speed, curr_waitings
        INTO v_op_speed, v_waitings
        FROM cluster_stat_median
        WHERE curr_timestamp = v_ts;

        IF NOT FOUND THEN
            v_ts := v_ts + INTERVAL '1 minute';
            v_processed := v_processed + 1;
            v_current_percent := floor(v_processed * 100.0 / v_total_minutes);
            IF v_current_percent > v_last_percent THEN
                RAISE NOTICE 'Прогресс: % % (обработано % из % минут)',
                             v_current_percent, '%', v_processed, v_total_minutes;
                v_last_percent := v_current_percent;
            END IF;
            CONTINUE;
        END IF;

        -- 2. Вычисляем корреляцию за окно
        BEGIN
            SELECT COALESCE(corr(curr_op_speed, curr_waitings), 0)
            INTO v_correlation
            FROM cluster_stat_median
            WHERE curr_timestamp BETWEEN v_ts - v_window AND v_ts;
        EXCEPTION
            WHEN OTHERS THEN
                v_correlation := 0.0;
        END;

        -- 3. Вычисляем угол наклона тренда OS
        BEGIN
            WITH window_data AS (
                SELECT curr_op_speed,
                       row_number() OVER (ORDER BY curr_timestamp) AS rn
                FROM cluster_stat_median
                WHERE curr_timestamp BETWEEN v_ts - v_window AND v_ts
            ),
            stats AS (
                SELECT AVG(rn::DOUBLE PRECISION) as avg1,
                       STDDEV(rn::DOUBLE PRECISION) as std1,
                       AVG(curr_op_speed::DOUBLE PRECISION) as avg2,
                       STDDEV(curr_op_speed::DOUBLE PRECISION) as std2
                FROM window_data
            ),
            standardized_data AS (
                SELECT (wd.rn::DOUBLE PRECISION - s.avg1) / NULLIF(s.std1, 0) as x_z,
                       (wd.curr_op_speed::DOUBLE PRECISION - s.avg2) / NULLIF(s.std2, 0) as y_z
                FROM window_data wd, stats s
            )
            SELECT ATAN(REGR_SLOPE(y_z, x_z)) * 180 / PI()
            INTO v_os_angle
            FROM standardized_data;
        EXCEPTION
            WHEN OTHERS THEN
                v_os_angle := 0.0;
        END;

        -- 4. Вычисляем угол наклона тренда ожиданий
        BEGIN
            WITH window_data AS (
                SELECT curr_waitings,
                       row_number() OVER (ORDER BY curr_timestamp) AS rn
                FROM cluster_stat_median
                WHERE curr_timestamp BETWEEN v_ts - v_window AND v_ts
            ),
            stats AS (
                SELECT AVG(rn::DOUBLE PRECISION) as avg1,
                       STDDEV(rn::DOUBLE PRECISION) as std1,
                       AVG(curr_waitings::DOUBLE PRECISION) as avg2,
                       STDDEV(curr_waitings::DOUBLE PRECISION) as std2
                FROM window_data
            ),
            standardized_data AS (
                SELECT (wd.rn::DOUBLE PRECISION - s.avg1) / NULLIF(s.std1, 0) as x_z,
                       (wd.curr_waitings::DOUBLE PRECISION - s.avg2) / NULLIF(s.std2, 0) as y_z
                FROM window_data wd, stats s
            )
            SELECT ATAN(REGR_SLOPE(y_z, x_z)) * 180 / PI()
            INTO v_wait_angle
            FROM standardized_data;
        EXCEPTION
            WHEN OTHERS THEN
                v_wait_angle := 0.0;
        END;

        -- 5. Вставляем или обновляем запись в performance_history
        INSERT INTO performance_history (ts, op_speed, waitings, correlation, os_angle, wait_angle)
        VALUES (v_ts, v_op_speed, v_waitings, v_correlation, v_os_angle, v_wait_angle)
        ON CONFLICT (ts) DO UPDATE SET
            op_speed = EXCLUDED.op_speed,
            waitings = EXCLUDED.waitings,
            correlation = EXCLUDED.correlation,
            os_angle = EXCLUDED.os_angle,
            wait_angle = EXCLUDED.wait_angle;

        v_inserted := v_inserted + 1;

        v_ts := v_ts + INTERVAL '1 minute';
        v_processed := v_processed + 1;

        v_current_percent := floor(v_processed * 100.0 / v_total_minutes);
        IF v_current_percent > v_last_percent THEN
            RAISE NOTICE 'Прогресс: % % (обработано % из % минут)',
                         v_current_percent, '%', v_processed, v_total_minutes;
            v_last_percent := v_current_percent;
        END IF;
    END LOOP;

    RAISE NOTICE 'Добавление завершено. Вставлено/обновлено записей: %.', v_inserted;
    RETURN format('Обработано %s минут. Вставлено/обновлено записей: %s.',
                  v_total_minutes, v_inserted);
END;
$$;

COMMENT ON FUNCTION append_performance_history(TIMESTAMPTZ, TIMESTAMPTZ) IS
'Инкрементально добавляет или обновляет записи в performance_history за указанный период (без TRUNCATE). Использует cluster_stat_median как источник.';

-- Функция: generate_profile_summary_report (исправленная)
-- Назначение: формирует краткий отчёт по текущему состоянию профилей нагрузки
--             (operational, daily, weekly) на основе данных из profile_aggregated.
-- Возвращает: TEXT[] – массив строк с отформатированным отчётом.
-- Использует функцию get_deviation_report для оценки аномалий относительно эталона.
-- Если эталон отсутствует, выводится предупреждение.

-- Функция: generate_profile_summary_report (исправленная)
-- Назначение: формирует краткий отчёт по текущему состоянию профилей нагрузки
--             (operational, daily, weekly) на основе данных из profile_aggregated.
-- Возвращает: TEXT[] – массив строк с отформатированным отчётом.
-- Использует функцию get_deviation_report для оценки аномалий относительно эталона.
-- Если эталон отсутствует, выводится предупреждение.

CREATE OR REPLACE FUNCTION generate_profile_summary_report()
RETURNS TEXT[]
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_report TEXT[] := '{}';
    v_line_sep CONSTANT TEXT := E'\n';
    v_header TEXT := '=== СВОДНЫЙ ОТЧЁТ ПО ПРОФИЛЯМ НАГРУЗКИ ===';
    v_ts TIMESTAMPTZ := now();
    v_rec RECORD;
    v_dev RECORD;
    v_anomaly_text TEXT;
    v_profile_types TEXT[] := ARRAY['operational', 'daily', 'weekly'];
    v_type TEXT;
    v_last_profile RECORD;
    v_has_baseline BOOLEAN;
    v_metrics_text TEXT;
    v_line TEXT;
BEGIN
    -- Добавляем заголовок и время формирования
    v_report := array_append(v_report, v_header);
    v_report := array_append(v_report, 'Отчёт сформирован: ' || to_char(v_ts, 'YYYY-MM-DD HH24:MI'));
    v_report := array_append(v_report, '');

    FOREACH v_type IN ARRAY v_profile_types
    LOOP
        -- Получаем последний профиль данного типа
        SELECT
            profile_type,
            ts,
            window_start,
            window_end,
            avg_correlation,
            critical_ratio,
            entropy,
            self_loop_ratio,
            hour,
            dow
        INTO v_last_profile
        FROM profile_aggregated
        WHERE profile_type = v_type
        ORDER BY ts DESC
        LIMIT 1;

        -- Если профиля нет, пропускаем
        IF NOT FOUND THEN
            v_report := array_append(v_report, 'Тип "' || v_type || '": нет данных');
            v_report := array_append(v_report, '');
            CONTINUE;
        END IF;

        -- Заголовок секции
        v_report := array_append(v_report, '--- ' || upper(v_type) || ' ПРОФИЛЬ ---');
        v_report := array_append(v_report, '  Окно: ' ||
            to_char(v_last_profile.window_start, 'YYYY-MM-DD HH24:MI') ||
            ' – ' ||
            to_char(v_last_profile.window_end, 'YYYY-MM-DD HH24:MI'));
        v_report := array_append(v_report, '  Час дня: ' || v_last_profile.hour || ', день недели: ' || v_last_profile.dow);

        -- Основные метрики
        v_report := array_append(v_report, '  Средняя корреляция: ' || COALESCE(round(v_last_profile.avg_correlation::NUMERIC, 3)::TEXT, 'NULL'));
        v_report := array_append(v_report, '  Доля критических: ' || COALESCE(round(v_last_profile.critical_ratio::NUMERIC, 3)::TEXT, 'NULL'));
        v_report := array_append(v_report, '  Энтропия: ' || COALESCE(round(v_last_profile.entropy::NUMERIC, 3)::TEXT, 'NULL'));
        v_report := array_append(v_report, '  Доля петель: ' || COALESCE(round(v_last_profile.self_loop_ratio::NUMERIC, 3)::TEXT, 'NULL'));

        -- Проверка наличия эталона для данного слота
        SELECT EXISTS (
            SELECT 1
            FROM profile_baseline
            WHERE baseline_name = 'default'
              AND hour = v_last_profile.hour
              AND dow = v_last_profile.dow
        ) INTO v_has_baseline;

        IF NOT v_has_baseline THEN
            v_report := array_append(v_report, '  ⚠ Эталон для данного слота отсутствует. Сравнение с эталоном невозможно.');
        ELSE
            -- Получаем отклонения и собираем текст
            v_anomaly_text := '';
            FOR v_dev IN
                SELECT metric_name, current_value, baseline_mean, baseline_std, z_score, severity
                FROM get_deviation_report(v_type, v_last_profile.ts)
            LOOP
                IF v_dev.metric_name = 'NO_ANOMALIES' THEN
                    v_anomaly_text := '  Аномалий не обнаружено.';
                ELSE
                    IF v_anomaly_text = '' THEN
                        v_anomaly_text := '  Обнаружены аномалии:';
                    END IF;
                    -- Формируем строку без использования format с несколькими спецификаторами
                    v_line := '    ' || v_dev.metric_name ||
                              ': Z=' || to_char(v_dev.z_score, '999.99') ||
                              ' (' || v_dev.severity || ')' ||
                              ' [тек. ' || to_char(v_dev.current_value, '999.999') ||
                              ', эталон ' || to_char(v_dev.baseline_mean, '999.999') ||
                              '±' || to_char(v_dev.baseline_std, '999.999') || ']';
                    v_anomaly_text := v_anomaly_text || E'\n' || v_line;
                END IF;
            END LOOP;

            IF v_anomaly_text = '' THEN
                v_anomaly_text := '  Аномалий не обнаружено.';
            END IF;
            v_report := array_append(v_report, v_anomaly_text);
        END IF;

        v_report := array_append(v_report, '');
    END LOOP;

    -- Добавляем информацию о последних аномалиях из лога (кратко)
    v_report := array_append(v_report, '--- ПОСЛЕДНИЕ АНОМАЛИИ В ЛОГЕ ---');
    FOR v_rec IN
        SELECT profile_type, detected_at, anomaly_score
        FROM anomaly_log
        ORDER BY detected_at DESC
        LIMIT 5
    LOOP
        v_report := array_append(v_report,
            '  ' || v_rec.profile_type ||
            ': ' || to_char(v_rec.detected_at, 'YYYY-MM-DD HH24:MI') ||
            ' (score=' || to_char(COALESCE(v_rec.anomaly_score, 0.0), '999.99') || ')'
        );
    END LOOP;
    IF NOT FOUND THEN
        v_report := array_append(v_report, '  Нет зафиксированных аномалий.');
    END IF;

    v_report := array_append(v_report, '');
    v_report := array_append(v_report, '=== КОНЕЦ ОТЧЁТА ===');

    RETURN v_report;
END;
$$;


COMMENT ON FUNCTION generate_profile_summary_report() IS
'Генерирует краткий отчёт по текущим профилям нагрузки (operational, daily, weekly).
Включает основные метрики последних профилей, сравнение с эталоном (если доступен)
и последние записи из anomaly_log. Возвращает массив строк для удобного отображения.';

-- =============================================================================
-- Функция: generate_detailed_profile_report (расширенная версия)
-- Назначение: формирует расширенный отчёт по профилям нагрузки (operational, daily, weekly)
--             с подробной интерпретацией каждой метрики, анализом аномалий,
--             контекстными метриками производительности, связью с инцидентами,
--             динамикой изменений и прогнозными метриками.
-- Возвращает: TEXT[] – массив строк с отформатированным отчётом.
-- =============================================================================
CREATE OR REPLACE FUNCTION generate_detailed_profile_report()
RETURNS TEXT[]
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_report TEXT[] := '{}';
    v_line_sep CONSTANT TEXT := E'\n';
    v_header TEXT := '=== РАСШИРЕННЫЙ АНАЛИТИЧЕСКИЙ ОТЧЁТ ПО ПРОФИЛЯМ НАГРУЗКИ ===';
    v_ts TIMESTAMPTZ := now();
    v_rec RECORD;
    v_dev RECORD;
    v_anomaly_text TEXT;
    v_profile_types TEXT[] := ARRAY['operational', 'daily', 'weekly'];
    v_type TEXT;
    v_last_profile RECORD;
    v_has_baseline BOOLEAN;
    v_metrics_text TEXT;
    v_line TEXT;
    v_interpretation TEXT;
    v_overall_status TEXT := 'СТАБИЛЬНО';
    v_anomaly_count INT := 0;
    v_critical_anomalies INT := 0;
    v_last_anomalies RECORD;

    -- Дополнительные переменные для новых метрик
    v_avg_op_speed REAL;
    v_avg_waitings REAL;
    v_cv_op_speed REAL;
    v_cv_waitings REAL;
    v_incident_count INT;
    v_avg_time_to_incident_min REAL;
    v_prev_profile RECORD;
    v_entropy_change REAL;
    v_critical_ratio_change REAL;
    v_self_loop_change REAL;
    v_risk_30min REAL;
    v_reliability INT;
    v_forecast_reliability_text TEXT;
BEGIN
    -- Заголовок
    v_report := array_append(v_report, v_header);
    v_report := array_append(v_report, 'Отчёт сформирован: ' || to_char(v_ts, 'YYYY-MM-DD HH24:MI'));
    v_report := array_append(v_report, '');

    -- Обработка каждого типа профиля
    FOREACH v_type IN ARRAY v_profile_types
    LOOP
        -- Получаем последний профиль данного типа
        SELECT
            profile_type,
            ts,
            window_start,
            window_end,
            avg_correlation,
            critical_ratio,
            entropy,
            self_loop_ratio,
            hour,
            dow,
            avg_os_angle,
            avg_wait_angle,
            unique_states_count,
            avg_transition_length
        INTO v_last_profile
        FROM profile_aggregated
        WHERE profile_type = v_type
        ORDER BY ts DESC
        LIMIT 1;

        IF NOT FOUND THEN
            v_report := array_append(v_report, 'Тип "' || v_type || '": нет данных');
            v_report := array_append(v_report, '');
            CONTINUE;
        END IF;

        -- ====================================================================
        -- 1. Контекстные метрики производительности (пункт 5)
        -- ====================================================================
        SELECT
            AVG(ph.op_speed) AS avg_op_speed,
            AVG(ph.waitings) AS avg_waitings,
            STDDEV(ph.op_speed) / NULLIF(AVG(ph.op_speed), 0) AS cv_op_speed,
            STDDEV(ph.waitings) / NULLIF(AVG(ph.waitings), 0) AS cv_waitings
        INTO
            v_avg_op_speed, v_avg_waitings, v_cv_op_speed, v_cv_waitings
        FROM performance_history ph
        WHERE ph.ts >= v_last_profile.window_start
          AND ph.ts < v_last_profile.window_end;

        -- ====================================================================
        -- 2. Связь с инцидентами (пункт 6)
        -- ====================================================================
        -- Количество инцидентов в окне
        SELECT COUNT(*) INTO v_incident_count
        FROM performance_incident pi
        WHERE pi.start_timepoint >= v_last_profile.window_start
          AND pi.start_timepoint < v_last_profile.window_end;

        -- Среднее время до инцидента после попадания в критическое состояние
        WITH critical_transitions AS (
            SELECT tl.ts AS trans_ts
            FROM transition_log tl
            WHERE tl.to_state IN (SELECT state_id FROM critical_states)
              AND tl.ts >= v_last_profile.window_start
              AND tl.ts < v_last_profile.window_end
        ),
        incident_times AS (
            SELECT pi.start_timepoint AS inc_ts
            FROM performance_incident pi
            WHERE pi.start_timepoint >= v_last_profile.window_start
              AND pi.start_timepoint < v_last_profile.window_end
        ),
        time_diffs AS (
            SELECT EXTRACT(EPOCH FROM (MIN(i.inc_ts) - ct.trans_ts)) / 60 AS diff_min
            FROM critical_transitions ct
            CROSS JOIN LATERAL (
                SELECT inc_ts
                FROM incident_times
                WHERE inc_ts > ct.trans_ts
                ORDER BY inc_ts
                LIMIT 1
            ) i
            GROUP BY ct.trans_ts
        )
        SELECT AVG(diff_min) INTO v_avg_time_to_incident_min
        FROM time_diffs
        WHERE diff_min IS NOT NULL;

        -- ====================================================================
        -- 3. Сравнение с предыдущим периодом (пункт 7)
        -- ====================================================================
        -- Для каждого типа профиля выбираем предыдущий профиль того же типа
        -- (для operational – предыдущий час, для daily – предыдущий день, для weekly – предыдущая неделя)
        -- Упрощённо: берём предыдущую запись по времени того же типа
        SELECT
            entropy,
            critical_ratio,
            self_loop_ratio
        INTO v_prev_profile
        FROM profile_aggregated
        WHERE profile_type = v_type
          AND ts < v_last_profile.ts
        ORDER BY ts DESC
        LIMIT 1;

        IF FOUND THEN
            v_entropy_change := COALESCE(v_last_profile.entropy - v_prev_profile.entropy, 0);
            v_critical_ratio_change := COALESCE(v_last_profile.critical_ratio - v_prev_profile.critical_ratio, 0);
            v_self_loop_change := COALESCE(v_last_profile.self_loop_ratio - v_prev_profile.self_loop_ratio, 0);
        ELSE
            v_entropy_change := NULL;
            v_critical_ratio_change := NULL;
            v_self_loop_change := NULL;
        END IF;

        -- ====================================================================
        -- Формирование секции отчёта для данного типа профиля
        -- ====================================================================
        v_report := array_append(v_report, '--- ' || upper(v_type) || ' ПРОФИЛЬ ---');
        v_report := array_append(v_report, '  Окно: ' ||
            to_char(v_last_profile.window_start, 'YYYY-MM-DD HH24:MI') ||
            ' – ' ||
            to_char(v_last_profile.window_end, 'YYYY-MM-DD HH24:MI'));
        v_report := array_append(v_report, '  Час дня: ' || v_last_profile.hour || ', день недели: ' || v_last_profile.dow);

        -- Основные метрики цепи Маркова
        v_report := array_append(v_report, '  Метрики цепи Маркова:');
        v_report := array_append(v_report, '    - Средняя корреляция: ' || COALESCE(round(v_last_profile.avg_correlation::NUMERIC, 3)::TEXT, 'NULL'));
        v_report := array_append(v_report, '    - Доля критических состояний: ' || COALESCE(round(v_last_profile.critical_ratio::NUMERIC, 3)::TEXT, 'NULL'));
        v_report := array_append(v_report, '    - Энтропия распределения: ' || COALESCE(round(v_last_profile.entropy::NUMERIC, 3)::TEXT, 'NULL'));
        v_report := array_append(v_report, '    - Доля петель (self-loop): ' || COALESCE(round(v_last_profile.self_loop_ratio::NUMERIC, 3)::TEXT, 'NULL'));
        v_report := array_append(v_report, '    - Угол тренда OS: ' || COALESCE(round(v_last_profile.avg_os_angle::NUMERIC, 3)::TEXT, 'NULL'));
        v_report := array_append(v_report, '    - Угол тренда ожиданий: ' || COALESCE(round(v_last_profile.avg_wait_angle::NUMERIC, 3)::TEXT, 'NULL'));
        v_report := array_append(v_report, '    - Уникальных состояний: ' || COALESCE(v_last_profile.unique_states_count::TEXT, 'NULL'));
        v_report := array_append(v_report, '    - Средняя длина перехода: ' || COALESCE(round(v_last_profile.avg_transition_length::NUMERIC, 3)::TEXT, 'NULL'));

        -- Контекстные метрики производительности (пункт 5)
        v_report := array_append(v_report, '  Контекстные метрики производительности:');
        IF v_avg_op_speed IS NOT NULL THEN
            v_report := array_append(v_report, '    - Средняя операционная скорость: ' || round(v_avg_op_speed::NUMERIC, 2)::TEXT);
            v_report := array_append(v_report, '    - Коэффициент вариации операционной скорости: ' || COALESCE(round(v_cv_op_speed::NUMERIC, 3)::TEXT, 'NULL'));
        ELSE
            v_report := array_append(v_report, '    - Нет данных о производительности в окне.');
        END IF;
        IF v_avg_waitings IS NOT NULL THEN
            v_report := array_append(v_report, '    - Среднее время ожиданий: ' || round(v_avg_waitings::NUMERIC, 2)::TEXT);
            v_report := array_append(v_report, '    - Коэффициент вариации времени ожиданий: ' || COALESCE(round(v_cv_waitings::NUMERIC, 3)::TEXT, 'NULL'));
        END IF;

        -- Связь с инцидентами (пункт 6)
        v_report := array_append(v_report, '  Связь с инцидентами:');
        v_report := array_append(v_report, '    - Количество инцидентов в окне: ' || COALESCE(v_incident_count::TEXT, '0'));
        IF v_avg_time_to_incident_min IS NOT NULL THEN
            v_report := array_append(v_report, '    - Среднее время до инцидента после критического перехода: ' || round(v_avg_time_to_incident_min::NUMERIC, 1)::TEXT || ' мин');
        ELSE
            v_report := array_append(v_report, '    - Нет данных о времени до инцидента (нет критических переходов или инцидентов).');
        END IF;

        -- Сравнение с предыдущим периодом (пункт 7)
        v_report := array_append(v_report, '  Изменение по сравнению с предыдущим периодом:');
        IF v_entropy_change IS NOT NULL THEN
            v_report := array_append(v_report, '    - Энтропия: ' || round(v_entropy_change::NUMERIC, 3)::TEXT || ' (Δ)');
            v_report := array_append(v_report, '    - Доля критических: ' || round(v_critical_ratio_change::NUMERIC, 3)::TEXT || ' (Δ)');
            v_report := array_append(v_report, '    - Доля петель: ' || round(v_self_loop_change::NUMERIC, 3)::TEXT || ' (Δ)');
        ELSE
            v_report := array_append(v_report, '    - Нет предыдущего периода для сравнения.');
        END IF;

        -- Интерпретация метрик (существующая логика)
        v_report := array_append(v_report, '  Интерпретация:');
        -- Корреляция
        IF v_last_profile.avg_correlation IS NOT NULL THEN
            IF v_last_profile.avg_correlation > 0.5 THEN
                v_interpretation := 'Сильная положительная связь между скоростью и ожиданиями – система чувствительна к нагрузке.';
            ELSIF v_last_profile.avg_correlation > 0.3 THEN
                v_interpretation := 'Умеренная положительная связь – возможна зависимость производительности от нагрузки.';
            ELSIF v_last_profile.avg_correlation > -0.3 THEN
                v_interpretation := 'Слабая или отсутствующая связь – производительность слабо зависит от нагрузки.';
            ELSIF v_last_profile.avg_correlation > -0.5 THEN
                v_interpretation := 'Умеренная отрицательная связь – рост нагрузки сопровождается снижением скорости.';
            ELSE
                v_interpretation := 'Сильная отрицательная связь – критическая зависимость, требуется анализ.';
            END IF;
            v_report := array_append(v_report, '    - Корреляция: ' || v_interpretation);
        END IF;

        -- Доля критических
        IF v_last_profile.critical_ratio IS NOT NULL THEN
            IF v_last_profile.critical_ratio > 0.2 THEN
                v_interpretation := 'Высокая доля критических состояний (>20%) – система часто находится в рискованных режимах.';
            ELSIF v_last_profile.critical_ratio > 0.1 THEN
                v_interpretation := 'Умеренная доля критических состояний (10-20%) – периодические риски.';
            ELSE
                v_interpretation := 'Низкая доля критических состояний (<10%) – система в основном стабильна.';
            END IF;
            v_report := array_append(v_report, '    - Критическая доля: ' || v_interpretation);
        END IF;

        -- Энтропия
        IF v_last_profile.entropy IS NOT NULL THEN
            IF v_last_profile.entropy > 5.0 THEN
                v_interpretation := 'Высокая энтропия (>5) – большое разнообразие состояний, система динамична, возможна нестабильность.';
            ELSIF v_last_profile.entropy > 2.0 THEN
                v_interpretation := 'Средняя энтропия (2-5) – умеренное разнообразие, типично для нормальной работы.';
            ELSE
                v_interpretation := 'Низкая энтропия (<2) – система зациклена в небольшом наборе состояний, возможна стагнация или перегрузка.';
            END IF;
            v_report := array_append(v_report, '    - Энтропия: ' || v_interpretation);
        END IF;

        -- Self-loop
        IF v_last_profile.self_loop_ratio IS NOT NULL THEN
            IF v_last_profile.self_loop_ratio > 0.6 THEN
                v_interpretation := 'Очень высокая доля петель (>60%) – система склонна "застревать" в состояниях, малая изменчивость.';
            ELSIF v_last_profile.self_loop_ratio > 0.4 THEN
                v_interpretation := 'Умеренная доля петель (40-60%) – смешанное поведение.';
            ELSE
                v_interpretation := 'Низкая доля петель (<40%) – система активно переключается между состояниями.';
            END IF;
            v_report := array_append(v_report, '    - Петли: ' || v_interpretation);
        END IF;

        -- Проверка эталона и аномалий (существующая логика)
        SELECT EXISTS (
            SELECT 1
            FROM profile_baseline
            WHERE baseline_name = 'default'
              AND hour = v_last_profile.hour
              AND dow = v_last_profile.dow
        ) INTO v_has_baseline;

        IF NOT v_has_baseline THEN
            v_report := array_append(v_report, '  ⚠ Эталон для данного слота отсутствует. Сравнение с эталоном невозможно.');
        ELSE
            v_anomaly_text := '';
            FOR v_dev IN
                SELECT metric_name, current_value, baseline_mean, baseline_std, z_score, severity
                FROM get_deviation_report(v_type, v_last_profile.ts)
            LOOP
                IF v_dev.metric_name = 'NO_ANOMALIES' THEN
                    v_anomaly_text := '  Аномалий не обнаружено.';
                ELSE
                    IF v_anomaly_text = '' THEN
                        v_anomaly_text := '  Обнаружены отклонения от эталона:';
                    END IF;
                    v_line := '    ' || v_dev.metric_name ||
                              ': Z=' || to_char(v_dev.z_score, '999.99') ||
                              ' (' || v_dev.severity || ')' ||
                              ' [тек. ' || to_char(v_dev.current_value, '999.999') ||
                              ', эталон ' || to_char(v_dev.baseline_mean, '999.999') ||
                              '±' || to_char(v_dev.baseline_std, '999.999') || ']';
                    v_anomaly_text := v_anomaly_text || E'\n' || v_line;

                    -- Дополнительная интерпретация отклонения
                    IF v_dev.metric_name = 'avg_correlation' THEN
                        IF v_dev.z_score > 2 THEN
                            v_anomaly_text := v_anomaly_text || E'\n      → Корреляция значительно выше эталона – усиление связи, возможно увеличение нагрузки.';
                        ELSIF v_dev.z_score < -2 THEN
                            v_anomaly_text := v_anomaly_text || E'\n      → Корреляция значительно ниже эталона – ослабление связи, возможно изменение характера нагрузки.';
                        END IF;
                    ELSIF v_dev.metric_name = 'entropy' THEN
                        IF v_dev.z_score > 2 THEN
                            v_anomaly_text := v_anomaly_text || E'\n      → Энтропия выше нормы – система стала более хаотичной, возможна нестабильность.';
                        ELSIF v_dev.z_score < -2 THEN
                            v_anomaly_text := v_anomaly_text || E'\n      → Энтропия ниже нормы – система стала более предсказуемой, но возможно застревание.';
                        END IF;
                    ELSIF v_dev.metric_name = 'critical_ratio' THEN
                        IF v_dev.z_score > 2 THEN
                            v_anomaly_text := v_anomaly_text || E'\n      → Доля критических состояний выше нормы – повышенный риск инцидентов.';
                        END IF;
                    ELSIF v_dev.metric_name = 'self_loop_ratio' THEN
                        IF v_dev.z_score > 2 THEN
                            v_anomaly_text := v_anomaly_text || E'\n      → Доля петель выше нормы – система менее динамична, возможен застой.';
                        END IF;
                    END IF;

                    v_anomaly_count := v_anomaly_count + 1;
                    IF v_dev.severity IN ('CRITICAL', 'HIGH') THEN
                        v_critical_anomalies := v_critical_anomalies + 1;
                    END IF;
                END IF;
            END LOOP;

            IF v_anomaly_text = '' THEN
                v_anomaly_text := '  Аномалий не обнаружено.';
            END IF;
            v_report := array_append(v_report, v_anomaly_text);
        END IF;

        v_report := array_append(v_report, '');
    END LOOP;

    -- ====================================================================
    -- 8. Прогнозные метрики (пункт 8) – глобальные для всей системы
    -- ====================================================================
    v_report := array_append(v_report, '--- ПРОГНОЗНЫЕ МЕТРИКИ ---');

    -- Риск на 30 минут
    BEGIN
        v_risk_30min := mchain_predict_risk_current_horizon();
        IF v_risk_30min IS NOT NULL THEN
            v_report := array_append(v_report, '  Прогноз риска на 30 минут: ' || round(v_risk_30min::NUMERIC, 4)::TEXT);
        ELSE
            v_report := array_append(v_report, '  Прогноз риска на 30 минут: недоступен (нет текущего состояния)');
        END IF;
    EXCEPTION WHEN OTHERS THEN
        v_report := array_append(v_report, '  Прогноз риска на 30 минут: ошибка (' || SQLERRM || ')');
    END;

    -- Достоверность прогноза
    BEGIN
        v_reliability := mchain_forecast_reliability();
        v_report := array_append(v_report, '  Рейтинг достоверности прогнозов (0-5): ' || v_reliability::TEXT);
        v_forecast_reliability_text := CASE
            WHEN v_reliability = 0 THEN 'Модель не обучена (нет данных)'
            WHEN v_reliability = 1 THEN 'Крайне низкая достоверность'
            WHEN v_reliability = 2 THEN 'Низкая достоверность'
            WHEN v_reliability = 3 THEN 'Минимально достаточная'
            WHEN v_reliability = 4 THEN 'Хорошая достоверность'
            WHEN v_reliability = 5 THEN 'Отличная достоверность'
            ELSE 'Неизвестно'
        END;
        v_report := array_append(v_report, '  Интерпретация: ' || v_forecast_reliability_text);
    EXCEPTION WHEN OTHERS THEN
        v_report := array_append(v_report, '  Достоверность прогнозов: ошибка (' || SQLERRM || ')');
    END;

    v_report := array_append(v_report, '');

    -- Общая оценка состояния системы
    v_report := array_append(v_report, '--- ОБЩАЯ ОЦЕНКА СОСТОЯНИЯ СИСТЕМЫ ---');
    IF v_critical_anomalies > 0 THEN
        v_overall_status := 'КРИТИЧЕСКОЕ – обнаружены сильные аномалии, требуется немедленное вмешательство.';
    ELSIF v_anomaly_count > 0 THEN
        v_overall_status := 'НЕСТАБИЛЬНОЕ – выявлены отклонения, рекомендуется анализ и мониторинг.';
    ELSE
        v_overall_status := 'СТАБИЛЬНОЕ – все профили в пределах нормы, система работает штатно.';
    END IF;
    v_report := array_append(v_report, '  Статус: ' || v_overall_status);
    v_report := array_append(v_report, '');

    -- Последние зафиксированные аномалии из лога (кратко)
    v_report := array_append(v_report, '--- ПОСЛЕДНИЕ АНОМАЛИИ В ЛОГЕ ---');
    FOR v_last_anomalies IN
        SELECT profile_type, detected_at, anomaly_score, affected_metrics
        FROM anomaly_log
        ORDER BY detected_at DESC
        LIMIT 5
    LOOP
        v_report := array_append(v_report,
            '  ' || v_last_anomalies.profile_type ||
            ': ' || to_char(v_last_anomalies.detected_at, 'YYYY-MM-DD HH24:MI') ||
            ' (score=' || to_char(COALESCE(v_last_anomalies.anomaly_score, 0.0), '999.99') || ')'
        );
    END LOOP;
    IF NOT FOUND THEN
        v_report := array_append(v_report, '  Нет зафиксированных аномалий.');
    END IF;

    v_report := array_append(v_report, '');
    v_report := array_append(v_report, '=== КОНЕЦ ОТЧЁТА ===');

    RETURN v_report;
END;
$$;

COMMENT ON FUNCTION generate_detailed_profile_report() IS
'Формирует расширенный аналитический отчёт по профилям нагрузки с добавлением:
- контекстных метрик производительности (средние и CV op_speed, waitings),
- связи с инцидентами (количество в окне, среднее время до инцидента после критического перехода),
- сравнения с предыдущим периодом (изменение энтропии, критической доли, петель),
- прогнозных метрик (риск на 30 минут и достоверность прогнозов).';
