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
-- version 14.9
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
--
-- Функция: compare_profile_windows
-- Назначение: сравнивает метрики профилей нагрузки для двух временных окон
--             (например, час до инцидента и предыдущий час) и возвращает
--             таблицу с абсолютными и относительными изменениями, а также
--             интерпретацией для каждой метрики.
--
-- Функция: refresh_performance_history
-- Назначение: Дополнить таблицу performance_history
--
-- Функция: find_incident_free_window
-- Назначение: найти отрезок времени заданной длины (в минутах), свободный от
--             инцидентов производительности, максимально близкий к текущему
--             моменту (now()).
--
-- Функция: save_baseline_profile
-- Назначение: Сохранение эталонного профиля на основе incident_free_window_current
--
-- Функция: save_current_profile
-- Назначение: Сохранение текущего профиля от текущего времени
--
-- Функция: compare_profiles
-- Назначение: Сравнение эталонного и текущего профилей с анализом аномалий
-- 
-- Функция: histogram_divergence
-- Назначение: Сравнение гистограм эталонного и текущего профилей с анализом аномалий
-- 
-- Функция: clean_profile_comparison_log
-- Назначение: Функция очистки старых записей из profile_comparison_log
--
-- Функция: get_incident_free_window_before
-- Назначение: Получить безынцидентное окно длины p_window_minutes,
-- заканчивающееся не позже p_ts, с максимальным концом.
-- 
-- Процедура: historical_fill_profile_comparison_log
-- Назначение: Процедура исторического заполнения
--
-- Функция: generate_profile_incident_analytics_report
-- Назначение: формирует аналитический отчёт по сводному анализу сравнения
--             профилей производительности и инцидентов на основе данных
--             из profile_comparison_log и performance_incident.
--
-- Функция: generate_comprehensive_analytical_report
-- Назначение: формирует сводный аналитический отчёт по производительности,
--             прогнозированию и профилям нагрузки за указанный период.
--
-- Функция: generate_analytical_report
-- Назначение: формирует аналитический отчёт по заданному временному интервалу,
--             объединяя данные из prediction_log, profile_comparison_log
--             и performance_incident. Возвращает массив строк с интерпретацией
--             и сводными показателями, а не сырыми данными.
--
-- =============================================================================


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
-- ВНИМАНИЕ: Таблицы profile_aggregated, profile_baseline, anomaly_log
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
    p_exclude_before_min        INT         DEFAULT 30,   -- минуты до инцидента
    p_exclude_after_min         INT         DEFAULT 60,   -- минуты после инцидента
    p_min_hours_per_slot        INT         DEFAULT 1
)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    v_before_interval INTERVAL := (p_exclude_before_min || ' minutes')::INTERVAL;
    v_after_interval  INTERVAL := (p_exclude_after_min  || ' minutes')::INTERVAL;
    v_metrics RECORD;
    v_hour INT;
    v_dow INT;
    v_total_slots INT := 0;
    v_processed_slots INT := 0;
    v_total_slots_all CONSTANT INT := 24 * 7;
BEGIN
    DELETE FROM profile_baseline WHERE baseline_name = p_baseline_name;

    RAISE NOTICE 'Начало построения эталона "%s" за период с %s по %s. Буферы: %s мин до, %s мин после.',
                 p_baseline_name, p_start, p_end, p_exclude_before_min, p_exclude_after_min;

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
                            ph.ts - v_before_interval AND ph.ts + v_after_interval
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

        v_processed_slots := v_processed_slots + 7;
        RAISE NOTICE 'Прогресс: % из % слотов обработано (%.1f%%). Заполнено слотов: %',
                     v_processed_slots, v_total_slots_all,
                     (v_processed_slots::numeric / v_total_slots_all * 100),
                     v_total_slots;
    END LOOP;

    RAISE NOTICE 'Построение эталона "%s" завершено. Заполнено %s слотов (минимум %s часов на слот).',
                 p_baseline_name, v_total_slots, p_min_hours_per_slot;

    RETURN format('Baseline "%s" rebuilt with %s slots filled (buffers: %s before, %s after).',
                  p_baseline_name, v_total_slots, p_exclude_before_min, p_exclude_after_min);
END;
$$;

COMMENT ON FUNCTION build_baseline_profile(TIMESTAMPTZ, TIMESTAMPTZ, TEXT, INT, INT, INT) IS
'Строит эталонный профиль с асимметричными буферами до (p_exclude_before_min) и после (p_exclude_after_min) инцидента. По умолчанию: 30 мин до, 60 мин после.';




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


-- =============================================================================
-- Функция: compare_profile_windows (возвращает text[] для отчёта)
-- Назначение: сравнивает метрики профилей нагрузки для двух временных окон,
--             задаваемых строками в формате 'YYYY-MM-DD HH24:MI',
--             и возвращает форматированный отчёт в виде массива строк.
-- Параметры:
--   p_window1_start, p_window1_end – первое окно (базовое)
--   p_window2_start, p_window2_end – второе окно (анализируемое)
-- Возвращает: TEXT[] – строки отчёта с заголовком, описанием окон,
--             строками по каждой метрике и итоговой оценкой.
-- =============================================================================
CREATE OR REPLACE FUNCTION compare_profile_windows(
    p_window1_start TEXT,
    p_window1_end   TEXT,
    p_window2_start TEXT,
    p_window2_end   TEXT
)
RETURNS TEXT[]
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v1_start TIMESTAMPTZ;
    v1_end   TIMESTAMPTZ;
    v2_start TIMESTAMPTZ;
    v2_end   TIMESTAMPTZ;
    w1 RECORD;
    w2 RECORD;
    v_report TEXT[] := '{}';
    v_line TEXT;
    v_delta_abs REAL;
    v_delta_pct REAL;
    v_interp TEXT;
    v_metric_name TEXT;
    v_w1_val TEXT;
    v_w2_val TEXT;
    v_overall_status TEXT := 'НОРМА';
    v_critical_cnt INT := 0;
BEGIN
    -- Преобразование входных строк в TIMESTAMPTZ
    BEGIN
        v1_start := to_timestamp(p_window1_start, 'YYYY-MM-DD HH24:MI');
        v1_end   := to_timestamp(p_window1_end,   'YYYY-MM-DD HH24:MI');
        v2_start := to_timestamp(p_window2_start, 'YYYY-MM-DD HH24:MI');
        v2_end   := to_timestamp(p_window2_end,   'YYYY-MM-DD HH24:MI');
    EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION 'Неверный формат даты/времени. Ожидается "YYYY-MM-DD HH24:MI" (например, "2026-07-01 10:21").';
    END;

    -- Проверка корректности интервалов
    IF v1_start >= v1_end THEN
        RAISE EXCEPTION 'Начало первого окна должно быть раньше конца.';
    END IF;
    IF v2_start >= v2_end THEN
        RAISE EXCEPTION 'Начало второго окна должно быть раньше конца.';
    END IF;

    -- Получаем метрики для обоих окон
    SELECT * INTO w1 FROM calculate_profile_metrics(v1_start, v1_end);
    SELECT * INTO w2 FROM calculate_profile_metrics(v2_start, v2_end);

    -- Заголовок отчёта
    v_report := array_append(v_report, '=== СРАВНИТЕЛЬНЫЙ АНАЛИЗ ПРОФИЛЕЙ НАГРУЗКИ ===');
    v_report := array_append(v_report, '');
    v_report := array_append(v_report, format('Окно 1 (базовое): %s – %s',
        to_char(v1_start, 'YYYY-MM-DD HH24:MI'),
        to_char(v1_end,   'YYYY-MM-DD HH24:MI')));
    v_report := array_append(v_report, format('Окно 2 (анализируемое): %s – %s',
        to_char(v2_start, 'YYYY-MM-DD HH24:MI'),
        to_char(v2_end,   'YYYY-MM-DD HH24:MI')));
    v_report := array_append(v_report, '');
    v_report := array_append(v_report, '--- МЕТРИКИ И ИЗМЕНЕНИЯ ---');

    -- Вспомогательная функция для добавления строки метрики
    -- Объявляем локальную процедуру (используем блок DO, но проще в цикле)

    -- 1. avg_correlation
    v_metric_name := 'Средняя корреляция';
    v_w1_val := COALESCE(w1.avg_correlation::TEXT, 'NULL');
    v_w2_val := COALESCE(w2.avg_correlation::TEXT, 'NULL');
    v_delta_abs := COALESCE(w2.avg_correlation - w1.avg_correlation, 0);
    v_delta_pct := CASE WHEN COALESCE(w1.avg_correlation, 0) <> 0 
                        THEN (v_delta_abs / w1.avg_correlation) * 100 
                        ELSE NULL END;
    v_interp := CASE 
        WHEN v_delta_abs > 0.2 THEN 'Значительный рост связи'
        WHEN v_delta_abs < -0.2 THEN 'Значительное ослабление связи'
        WHEN v_delta_abs > 0.05 THEN 'Умеренный рост связи'
        WHEN v_delta_abs < -0.05 THEN 'Умеренное ослабление связи'
        ELSE 'Без изменений'
    END;
    v_line := format('%s: %s → %s (Δ=%s, %s%%) – %s',
        v_metric_name, v_w1_val, v_w2_val,
        round(v_delta_abs::NUMERIC, 3),
        COALESCE(round(v_delta_pct::NUMERIC, 1)::TEXT, '∞'),
        v_interp);
    v_report := array_append(v_report, v_line);
    IF v_delta_abs > 0.2 OR v_delta_abs < -0.2 THEN v_critical_cnt := v_critical_cnt + 1; END IF;

    -- 2. critical_ratio
    v_metric_name := 'Доля критических состояний';
    v_w1_val := COALESCE(w1.critical_ratio::TEXT, 'NULL');
    v_w2_val := COALESCE(w2.critical_ratio::TEXT, 'NULL');
    v_delta_abs := COALESCE(w2.critical_ratio - w1.critical_ratio, 0);
    v_delta_pct := CASE WHEN COALESCE(w1.critical_ratio, 0) <> 0 
                        THEN (v_delta_abs / w1.critical_ratio) * 100 
                        ELSE NULL END;
    v_interp := CASE 
        WHEN v_delta_abs > 0.05 THEN 'Существенный рост риска'
        WHEN v_delta_abs > 0.02 THEN 'Умеренный рост риска'
        WHEN v_delta_abs < -0.05 THEN 'Значительное снижение риска'
        WHEN v_delta_abs < -0.02 THEN 'Умеренное снижение риска'
        ELSE 'Без изменений'
    END;
    v_line := format('%s: %s → %s (Δ=%s, %s%%) – %s',
        v_metric_name, v_w1_val, v_w2_val,
        round(v_delta_abs::NUMERIC, 3),
        COALESCE(round(v_delta_pct::NUMERIC, 1)::TEXT, '∞'),
        v_interp);
    v_report := array_append(v_report, v_line);
    IF v_delta_abs > 0.05 THEN v_critical_cnt := v_critical_cnt + 2; END IF;

    -- 3. entropy
    v_metric_name := 'Энтропия';
    v_w1_val := COALESCE(w1.entropy::TEXT, 'NULL');
    v_w2_val := COALESCE(w2.entropy::TEXT, 'NULL');
    v_delta_abs := COALESCE(w2.entropy - w1.entropy, 0);
    v_delta_pct := CASE WHEN COALESCE(w1.entropy, 0) <> 0 
                        THEN (v_delta_abs / w1.entropy) * 100 
                        ELSE NULL END;
    v_interp := CASE 
        WHEN v_delta_abs > 0.5 THEN 'Критический рост хаоса'
        WHEN v_delta_abs > 0.2 THEN 'Умеренный рост разнообразия'
        WHEN v_delta_abs < -0.5 THEN 'Резкое снижение разнообразия'
        WHEN v_delta_abs < -0.2 THEN 'Умеренное снижение разнообразия'
        ELSE 'Без изменений'
    END;
    v_line := format('%s: %s → %s (Δ=%s, %s%%) – %s',
        v_metric_name, v_w1_val, v_w2_val,
        round(v_delta_abs::NUMERIC, 3),
        COALESCE(round(v_delta_pct::NUMERIC, 1)::TEXT, '∞'),
        v_interp);
    v_report := array_append(v_report, v_line);
    IF v_delta_abs > 0.5 THEN v_critical_cnt := v_critical_cnt + 2; END IF;

    -- 4. self_loop_ratio
    v_metric_name := 'Доля петель (self-loop)';
    v_w1_val := COALESCE(w1.self_loop_ratio::TEXT, 'NULL');
    v_w2_val := COALESCE(w2.self_loop_ratio::TEXT, 'NULL');
    v_delta_abs := COALESCE(w2.self_loop_ratio - w1.self_loop_ratio, 0);
    v_delta_pct := CASE WHEN COALESCE(w1.self_loop_ratio, 0) <> 0 
                        THEN (v_delta_abs / w1.self_loop_ratio) * 100 
                        ELSE NULL END;
    v_interp := CASE 
        WHEN v_delta_abs > 0.1 THEN 'Сильный рост инерционности'
        WHEN v_delta_abs > 0.05 THEN 'Умеренный рост петель'
        WHEN v_delta_abs < -0.1 THEN 'Сильное снижение петель'
        WHEN v_delta_abs < -0.05 THEN 'Умеренное снижение петель'
        ELSE 'Без изменений'
    END;
    v_line := format('%s: %s → %s (Δ=%s, %s%%) – %s',
        v_metric_name, v_w1_val, v_w2_val,
        round(v_delta_abs::NUMERIC, 3),
        COALESCE(round(v_delta_pct::NUMERIC, 1)::TEXT, '∞'),
        v_interp);
    v_report := array_append(v_report, v_line);
    IF v_delta_abs > 0.1 THEN v_critical_cnt := v_critical_cnt + 1; END IF;

    -- 5. avg_os_angle
    v_metric_name := 'Угол тренда OS (градусы)';
    v_w1_val := COALESCE(w1.avg_os_angle::TEXT, 'NULL');
    v_w2_val := COALESCE(w2.avg_os_angle::TEXT, 'NULL');
    v_delta_abs := COALESCE(w2.avg_os_angle - w1.avg_os_angle, 0);
    v_delta_pct := CASE WHEN COALESCE(w1.avg_os_angle, 0) <> 0 
                        THEN (v_delta_abs / w1.avg_os_angle) * 100 
                        ELSE NULL END;
    v_interp := CASE 
        WHEN v_delta_abs > 10 THEN 'Значительное изменение угла'
        WHEN v_delta_abs > 5 THEN 'Умеренное изменение угла'
        WHEN v_delta_abs < -10 THEN 'Значительное изменение в отрицательную сторону'
        WHEN v_delta_abs < -5 THEN 'Умеренное изменение в отрицательную сторону'
        ELSE 'Без изменений'
    END;
    v_line := format('%s: %s → %s (Δ=%s, %s%%) – %s',
        v_metric_name, v_w1_val, v_w2_val,
        round(v_delta_abs::NUMERIC, 1),
        COALESCE(round(v_delta_pct::NUMERIC, 1)::TEXT, '∞'),
        v_interp);
    v_report := array_append(v_report, v_line);
    IF v_delta_abs > 10 THEN v_critical_cnt := v_critical_cnt + 1; END IF;

    -- 6. avg_wait_angle
    v_metric_name := 'Угол тренда ожиданий (градусы)';
    v_w1_val := COALESCE(w1.avg_wait_angle::TEXT, 'NULL');
    v_w2_val := COALESCE(w2.avg_wait_angle::TEXT, 'NULL');
    v_delta_abs := COALESCE(w2.avg_wait_angle - w1.avg_wait_angle, 0);
    v_delta_pct := CASE WHEN COALESCE(w1.avg_wait_angle, 0) <> 0 
                        THEN (v_delta_abs / w1.avg_wait_angle) * 100 
                        ELSE NULL END;
    v_interp := CASE 
        WHEN v_delta_abs > 10 THEN 'Значительное изменение угла'
        WHEN v_delta_abs > 5 THEN 'Умеренное изменение угла'
        WHEN v_delta_abs < -10 THEN 'Значительное изменение в отрицательную сторону'
        WHEN v_delta_abs < -5 THEN 'Умеренное изменение в отрицательную сторону'
        ELSE 'Без изменений'
    END;
    v_line := format('%s: %s → %s (Δ=%s, %s%%) – %s',
        v_metric_name, v_w1_val, v_w2_val,
        round(v_delta_abs::NUMERIC, 1),
        COALESCE(round(v_delta_pct::NUMERIC, 1)::TEXT, '∞'),
        v_interp);
    v_report := array_append(v_report, v_line);
    IF v_delta_abs > 10 THEN v_critical_cnt := v_critical_cnt + 1; END IF;

    -- 7. unique_states_count
    v_metric_name := 'Количество уникальных состояний';
    v_w1_val := COALESCE(w1.unique_states_count::TEXT, 'NULL');
    v_w2_val := COALESCE(w2.unique_states_count::TEXT, 'NULL');
    v_delta_abs := COALESCE(w2.unique_states_count - w1.unique_states_count, 0);
    v_delta_pct := CASE WHEN COALESCE(w1.unique_states_count, 0) <> 0 
                        THEN (v_delta_abs / w1.unique_states_count) * 100 
                        ELSE NULL END;
    v_interp := CASE 
        WHEN v_delta_abs > 10 THEN 'Резкое расширение набора состояний'
        WHEN v_delta_abs > 5 THEN 'Умеренное расширение'
        WHEN v_delta_abs < -10 THEN 'Резкое сужение набора состояний'
        WHEN v_delta_abs < -5 THEN 'Умеренное сужение'
        ELSE 'Без изменений'
    END;
    v_line := format('%s: %s → %s (Δ=%s, %s%%) – %s',
        v_metric_name, v_w1_val, v_w2_val,
        v_delta_abs::TEXT,
        COALESCE(round(v_delta_pct::NUMERIC, 1)::TEXT, '∞'),
        v_interp);
    v_report := array_append(v_report, v_line);
    IF v_delta_abs > 10 THEN v_critical_cnt := v_critical_cnt + 1; END IF;

    -- 8. avg_transition_length
    v_metric_name := 'Средняя длина перехода';
    v_w1_val := COALESCE(w1.avg_transition_length::TEXT, 'NULL');
    v_w2_val := COALESCE(w2.avg_transition_length::TEXT, 'NULL');
    v_delta_abs := COALESCE(w2.avg_transition_length - w1.avg_transition_length, 0);
    v_delta_pct := CASE WHEN COALESCE(w1.avg_transition_length, 0) <> 0 
                        THEN (v_delta_abs / w1.avg_transition_length) * 100 
                        ELSE NULL END;
    v_interp := CASE 
        WHEN v_delta_abs > 0.5 THEN 'Значительное увеличение (скачки между состояниями)'
        WHEN v_delta_abs > 0.2 THEN 'Умеренное увеличение'
        WHEN v_delta_abs < -0.5 THEN 'Значительное уменьшение (близкие переходы)'
        WHEN v_delta_abs < -0.2 THEN 'Умеренное уменьшение'
        ELSE 'Без изменений'
    END;
    v_line := format('%s: %s → %s (Δ=%s, %s%%) – %s',
        v_metric_name, v_w1_val, v_w2_val,
        round(v_delta_abs::NUMERIC, 3),
        COALESCE(round(v_delta_pct::NUMERIC, 1)::TEXT, '∞'),
        v_interp);
    v_report := array_append(v_report, v_line);
    IF v_delta_abs > 0.5 THEN v_critical_cnt := v_critical_cnt + 1; END IF;

    -- 9. state_histogram (JSON) – только текст
    v_metric_name := 'Гистограмма состояний (JSON)';
    v_w1_val := COALESCE(w1.state_histogram::TEXT, 'NULL');
    v_w2_val := COALESCE(w2.state_histogram::TEXT, 'NULL');
    v_line := format('%s: %s → %s (только для справки)',
        v_metric_name, v_w1_val, v_w2_val);
    v_report := array_append(v_report, v_line);

    -- 10. top_transition (JSON)
    v_metric_name := 'Самый частый переход (JSON)';
    v_w1_val := COALESCE(w1.top_transition::TEXT, 'NULL');
    v_w2_val := COALESCE(w2.top_transition::TEXT, 'NULL');
    v_line := format('%s: %s → %s (только для справки)',
        v_metric_name, v_w1_val, v_w2_val);
    v_report := array_append(v_report, v_line);

    -- Итоговая оценка
    v_report := array_append(v_report, '');
    v_report := array_append(v_report, '--- ИТОГОВАЯ ОЦЕНКА ---');
    IF v_critical_cnt >= 3 THEN
        v_overall_status := 'КРИТИЧЕСКОЕ – обнаружены значительные изменения, требуется немедленный анализ';
    ELSIF v_critical_cnt >= 1 THEN
        v_overall_status := 'НЕСТАБИЛЬНОЕ – выявлены отклонения, рекомендуется мониторинг';
    ELSE
        v_overall_status := 'НОРМА – значимых изменений не обнаружено';
    END IF;
    v_report := array_append(v_report, format('Статус: %s', v_overall_status));
    v_report := array_append(v_report, '');
    v_report := array_append(v_report, '=== КОНЕЦ ОТЧЁТА ===');

    RETURN v_report;
END;
$$;

COMMENT ON FUNCTION compare_profile_windows(TEXT, TEXT, TEXT, TEXT) IS
'Сравнивает профили нагрузки для двух окон, задаваемых строками в формате "YYYY-MM-DD HH24:MI". Возвращает форматированный отчёт в виде массива строк с метриками, изменениями, интерпретацией и итоговой оценкой.';

-- =============================================================================
-- Функция: refresh_performance_history
-- Назначение: Дополнить таблицу performance_history
CREATE OR REPLACE FUNCTION refresh_performance_history()
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    last_ts TIMESTAMPTZ;
    start_ts TIMESTAMPTZ;
    end_ts TIMESTAMPTZ := now();
    result TEXT;
BEGIN
    -- Определяем последнюю запись в performance_history
    SELECT MAX(ts) INTO last_ts FROM performance_history;
    
    IF last_ts IS NULL THEN
        -- Если таблица пуста, берём самую раннюю минуту из cluster_stat_median
        SELECT MIN(curr_timestamp) INTO start_ts FROM cluster_stat_median;
        IF start_ts IS NULL THEN
            RETURN 'Нет данных в cluster_stat_median';
        END IF;
    ELSE
        -- Начинаем со следующей минуты
        start_ts := last_ts + INTERVAL '1 minute';
    END IF;
    
    IF start_ts > end_ts THEN
        RETURN 'Новых данных нет';
    END IF;
    
    -- Вызываем инкрементальное добавление
    result := append_performance_history(start_ts, end_ts);
    RETURN result;
END;
$$;


-- =============================================================================
-- Функция: find_incident_free_window (исправленная – оконные функции в WHERE)
-- Назначение: найти отрезок времени заданной длины, свободный от инцидентов,
--             максимально близкий к последнему завершённому инциденту.
--             Результат сохраняется в таблицу incident_free_window_current.
-- Входные параметры:
--   p_window_minutes INT – требуемая длина окна в минутах (по умолчанию 60)
-- Возвращает:
--   TEXT – сообщение о результате
-- =============================================================================
CREATE OR REPLACE FUNCTION find_incident_free_window(
    p_window_minutes      INT DEFAULT 60,
    p_exclude_before_min  INT DEFAULT 30,   -- не используется
    p_exclude_after_min   INT DEFAULT 60    -- не используется
)
RETURNS TEXT
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
    v_now          TIMESTAMPTZ := now();
    v_interval     INTERVAL := (p_window_minutes || ' minutes')::INTERVAL;
    v_last_finish  TIMESTAMPTZ;
	v_test_start_point TIMESTAMPTZ;
    v_start_ts     TIMESTAMPTZ;
    v_end_ts       TIMESTAMPTZ;
BEGIN
    IF p_window_minutes <= 0 THEN
        RAISE EXCEPTION 'Длина окна должна быть положительной, получено %', p_window_minutes;
    END IF;
	
    -- 1. Находим самый поздний завершённый инцидент
    SELECT MAX(finish_timepoint)
    INTO v_last_finish
    FROM performance_incident
    WHERE finish_timepoint IS NOT NULL;

    -- 2. Проверяем условия доступности
    IF v_last_finish IS NULL
       OR v_last_finish + INTERVAL '1 hour' > v_now
       OR v_last_finish + v_interval > v_now
    THEN
        DELETE FROM incident_free_window_current;
        RETURN 'Окно не найдено: последний завершённый инцидент не удовлетворяет условиям доступности (не прошло 1 часа или окно не помещается в прошлое).';
    END IF;

	-- 3. Выбираем точку времени = v_now 
	SELECT now() - interval '2 hour' 
	INTO  v_test_start_point ;

    -- 4. Окно доступно
    v_start_ts := v_test_start_point;
    v_end_ts   := v_test_start_point + v_interval;
	
	DELETE FROM incident_free_window_current;
    INSERT INTO incident_free_window_current (window_start, window_end, updated_at)
    VALUES (v_start_ts, v_end_ts, v_now);
    
    RETURN format('Окно обновлено: %s – %s (длина %s минут)',
                  v_start_ts, v_end_ts, p_window_minutes);
END;
$$;

COMMENT ON FUNCTION find_incident_free_window(INT, INT, INT) IS
'Эталонное окно = [finish ; finish + window_minutes] для самого позднего завершённого инцидента,
доступно только если прошло не менее 1 часа после его окончания и окно целиком в прошлом.
Если условий нет – таблица incident_free_window_current очищается.';

-- =============================================================================
-- Дополнительные функции для профилирования производительности:
-- 1) Сохранение эталонного профиля на основе incident_free_window_current
-- 2) Сохранение текущего профиля от текущего времени
-- 3) Сравнение эталонного и текущего профилей с анализом аномалий

-- =============================================================================
-- Обновлённые функции для профилирования производительности
-- (без использования отдельной таблицы baseline_state)
-- =============================================================================
-- Copyright 2026 Ринат (markov_chain)
-- Лицензия Apache 2.0
-- =============================================================================

--------------------------------------------------------------------------------
-- 2. Функция сохранения эталонного профиля (переработанная)
--    Использует incident_free_window_current как источник актуального окна,
--    а для проверки изменений сравнивает с последним сохранённым профилем
--    в profile_aggregated (profile_type='baseline').
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION save_baseline_profile()
RETURNS TEXT
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
    v_win_start TIMESTAMPTZ;
    v_win_end   TIMESTAMPTZ;
    v_last_baseline RECORD;
    v_metrics   RECORD;
    v_hour      SMALLINT;
    v_dow       SMALLINT;
BEGIN
    -- 1. Получаем текущее безынцидентное окно
    SELECT window_start, window_end INTO v_win_start, v_win_end
    FROM incident_free_window_current
    LIMIT 1;

    IF v_win_start IS NULL OR v_win_end IS NULL THEN
        RETURN 'Ошибка: таблица incident_free_window_current пуста. Сначала выполните find_incident_free_window().';
    END IF;
/*
--14.8
--Эталонное окно - скользящее
    -- 2. Проверяем, совпадает ли текущее окно с последним сохранённым эталонным профилем
    SELECT window_start, window_end INTO v_last_baseline
    FROM profile_aggregated
    WHERE profile_type = 'baseline'
    ORDER BY ts DESC
    LIMIT 1;

    IF FOUND AND v_last_baseline.window_start = v_win_start AND v_last_baseline.window_end = v_win_end THEN
        RETURN format('Эталонный профиль уже сохранён для окна %s – %s, пропуск.',
                      v_win_start, v_win_end);
    END IF;
--Эталонное окно - скользящее	
--14.8	
*/
    -- 3. Удаляем старый эталонный профиль (если есть)
    DELETE FROM profile_aggregated WHERE profile_type = 'baseline';

    -- 4. Вычисляем метрики для нового окна
    SELECT * INTO v_metrics
    FROM calculate_profile_metrics(v_win_start, v_win_end);

    v_hour := EXTRACT(HOUR FROM now())::SMALLINT;
    v_dow  := EXTRACT(DOW FROM now())::SMALLINT;

    -- 5. Вставляем новый эталонный профиль
    INSERT INTO profile_aggregated (
        profile_type, ts, hour, dow, window_start, window_end,
        state_histogram, avg_correlation, critical_ratio, entropy,
        avg_os_angle, avg_wait_angle, unique_states_count,
        avg_transition_length, self_loop_ratio, top_transition
    ) VALUES (
        'baseline', now(), v_hour, v_dow, v_win_start, v_win_end,
        v_metrics.state_histogram, v_metrics.avg_correlation,
        v_metrics.critical_ratio, v_metrics.entropy,
        v_metrics.avg_os_angle, v_metrics.avg_wait_angle,
        v_metrics.unique_states_count,
        v_metrics.avg_transition_length, v_metrics.self_loop_ratio,
        v_metrics.top_transition
    );

    RETURN format('Эталонный профиль сохранён: %s – %s (длина %s мин)',
                  v_win_start, v_win_end,
                  EXTRACT(EPOCH FROM (v_win_end - v_win_start)) / 60);
END;
$$;

COMMENT ON FUNCTION save_baseline_profile() IS
'Сохраняет эталонный профиль на основе текущего окна из incident_free_window_current.
Если окно совпадает с последним сохранённым эталоном – пропускает.
Старый эталон удаляется.';

--------------------------------------------------------------------------------
-- 3. Функция сохранения текущего профиля производительности (без изменений)
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION save_current_profile(
    p_window_minutes INT DEFAULT 60
)
RETURNS TEXT
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
    v_end   TIMESTAMPTZ := now();
    v_start TIMESTAMPTZ := v_end - (p_window_minutes || ' minutes')::INTERVAL;
    v_metrics RECORD;
    v_hour  SMALLINT := EXTRACT(HOUR FROM v_end)::SMALLINT;
    v_dow   SMALLINT := EXTRACT(DOW FROM v_end)::SMALLINT;
BEGIN
    IF p_window_minutes <= 0 THEN
        RAISE EXCEPTION 'Размер окна должен быть положительным, получено %', p_window_minutes;
    END IF;

    DELETE FROM profile_aggregated WHERE profile_type = 'current';

    SELECT * INTO v_metrics
    FROM calculate_profile_metrics(v_start, v_end);

    INSERT INTO profile_aggregated (
        profile_type, ts, hour, dow, window_start, window_end,
        state_histogram, avg_correlation, critical_ratio, entropy,
        avg_os_angle, avg_wait_angle, unique_states_count,
        avg_transition_length, self_loop_ratio, top_transition
    ) VALUES (
        'current', v_end, v_hour, v_dow, v_start, v_end,
        v_metrics.state_histogram, v_metrics.avg_correlation,
        v_metrics.critical_ratio, v_metrics.entropy,
        v_metrics.avg_os_angle, v_metrics.avg_wait_angle,
        v_metrics.unique_states_count,
        v_metrics.avg_transition_length, v_metrics.self_loop_ratio,
        v_metrics.top_transition
    );

    RETURN format('Текущий профиль сохранён: %s – %s (длина %s мин)',
                  v_start, v_end, p_window_minutes);
END;
$$;

COMMENT ON FUNCTION save_current_profile(INT) IS
'Сохраняет текущий профиль за последние p_window_minutes минут, удаляя старый.';

--------------------------------------------------------------------------------
-- 4. Вспомогательная функция для расчёта расхождения гистограмм (JS-дивергенция) – без изменений
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION histogram_divergence(
    h1 JSONB,
    h2 JSONB
)
RETURNS REAL
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    v_keys TEXT[];
    v_key TEXT;
    v_p REAL;
    v_q REAL;
    v_m REAL;
    v_kl1 REAL := 0.0;
    v_kl2 REAL := 0.0;
    v_js REAL := 0.0;
    v_epsilon CONSTANT REAL := 1e-12;
BEGIN
    IF h1 IS NULL OR h2 IS NULL THEN
        RETURN NULL;
    END IF;

    SELECT array_agg(DISTINCT key) INTO v_keys
    FROM (
        SELECT key FROM jsonb_each(h1)
        UNION
        SELECT key FROM jsonb_each(h2)
    ) t;

    IF v_keys IS NULL OR array_length(v_keys, 1) = 0 THEN
        RETURN 0.0;
    END IF;

    FOREACH v_key IN ARRAY v_keys
    LOOP
        SELECT (h1->v_key->>'pct')::REAL INTO v_p;
        SELECT (h2->v_key->>'pct')::REAL INTO v_q;
        v_p := COALESCE(v_p, 0.0) / 100.0;
        v_q := COALESCE(v_q, 0.0) / 100.0;
        v_m := (v_p + v_q) / 2.0;

        IF v_p > v_epsilon AND v_m > v_epsilon THEN
            v_kl1 := v_kl1 + v_p * ln(v_p / v_m);
        END IF;
        IF v_q > v_epsilon AND v_m > v_epsilon THEN
            v_kl2 := v_kl2 + v_q * ln(v_q / v_m);
        END IF;
    END LOOP;

    v_js := 0.5 * v_kl1 + 0.5 * v_kl2;
    IF v_js < 0 THEN
        v_js := 0;
    ELSIF v_js > 10 THEN
        v_js := 10;
    END IF;
    RETURN v_js::REAL;
END;
$$;

COMMENT ON FUNCTION histogram_divergence(JSONB, JSONB) IS
'Вычисляет JS-дивергенцию между двумя гистограммами (поля pct в процентах).';

--------------------------------------------------------------------------------
-- compare_profiles (переработанная)
-- Назначение: выполняет сравнение текущего профиля нагрузки с эталонным окном,
--             найденным по стратегии get_incident_free_window_before.
--             Логика полностью соответствует процедуре historical_fill_profile_comparison_log,
--             но работает для одного момента времени (now()).
-- Параметры:
--   p_window_minutes      INT – длина окна в минутах (по умолчанию 60)
--   p_exclude_before_min  INT – не используется (оставлено для совместимости)
--   p_exclude_after_min   INT – не используется
-- Возвращает: TEXT[] – форматированный отчёт о сравнении.
-- Сохраняет результат в таблицу profile_comparison_log.
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION compare_profiles(
    p_window_minutes      INT DEFAULT 60,
    p_exclude_before_min  INT DEFAULT 30,   -- не используется
    p_exclude_after_min   INT DEFAULT 60    -- не используется
)
RETURNS TEXT[]
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
    v_now           TIMESTAMPTZ := now();
    v_interval      INTERVAL := (p_window_minutes || ' minutes')::INTERVAL;
    v_baseline_start TIMESTAMPTZ;
    v_baseline_end  TIMESTAMPTZ;
    v_current_start TIMESTAMPTZ := v_now - v_interval;
    v_current_end   TIMESTAMPTZ := v_now;
    v_baseline_metrics RECORD;
    v_current_metrics  RECORD;
    v_js            REAL;
    v_status        TEXT;
    v_report        TEXT[] := '{}';
    v_details       JSONB;
    v_inside_incident BOOLEAN;
    v_max_pred_risk REAL;
    v_pre_alert     INTEGER;   -- старый флаг (0 или 100)
    v_js_threshold  REAL;      -- порог из конфига
    
    -- Новые переменные для комплексного подхода
    v_high_risk_percentile REAL;    -- 90-й перцентиль
    v_stability_met        BOOLEAN; -- устойчивость 3 из 5
    v_pre_alert_advanced   INTEGER; -- новый флаг
BEGIN
    -- 1. Проверяем, находится ли текущий момент внутри активного инцидента
    SELECT EXISTS (
        SELECT 1
        FROM performance_incident
        WHERE start_timepoint <= v_now
          AND (finish_timepoint IS NULL OR finish_timepoint >= v_now)
    ) INTO v_inside_incident;

    -- 2. Получаем максимальный предсказанный риск за текущее окно (для старого флага и для устойчивости)
    SELECT MAX(predicted_risk) INTO v_max_pred_risk
    FROM prediction_log
    WHERE prediction_time BETWEEN v_current_start AND v_current_end;

    -- 3. Если внутри инцидента – записываем INCIDENT и возвращаем отчёт
    IF v_inside_incident THEN
        v_status := 'INCIDENT';
        v_report := array_append(v_report, '=== СРАВНЕНИЕ ПРОФИЛЕЙ ===');
        v_report := array_append(v_report, format('Текущий момент: %s', v_now));
        v_report := array_append(v_report, 'Статус: INCIDENT – система находится внутри инцидента, эталонное окно недоступно.');
        v_report := array_append(v_report, '=== КОНЕЦ ОТЧЁТА ===');

        v_pre_alert := 0;
        v_pre_alert_advanced := 0;

        INSERT INTO profile_comparison_log (
            current_window_start,
            current_window_end,
            status,
            js_divergence,
            report,
            details,
            max_predicted_risk,
            pre_alert_flag,
            high_risk_percentile,
            js_threshold_used,
            stability_met,
            pre_alert_flag_advanced
        ) VALUES (
            v_current_start,
            v_current_end,
            v_status,
            NULL,
            to_jsonb(v_report),
            jsonb_build_object('reason', 'inside_incident'),
            v_max_pred_risk,
            v_pre_alert,
            NULL,
            NULL,
            NULL,
            v_pre_alert_advanced
        );
        RETURN v_report;
    END IF;

    -- 4. Пытаемся получить эталонное окно (безынцидентное)
    SELECT start_ts, end_ts INTO v_baseline_start, v_baseline_end
    FROM get_incident_free_window_before(v_now, p_window_minutes, p_exclude_before_min, p_exclude_after_min);

    IF v_baseline_start IS NULL THEN
        v_status := 'INCIDENT';
        v_report := array_append(v_report, '=== СРАВНЕНИЕ ПРОФИЛЕЙ ===');
        v_report := array_append(v_report, format('Текущий момент: %s', v_now));
        v_report := array_append(v_report, 'Статус: INCIDENT – эталонное окно недоступно (возможно, ещё не прошло 1 часа после инцидента).');
        v_report := array_append(v_report, '=== КОНЕЦ ОТЧЁТА ===');

        v_pre_alert := 0;
        v_pre_alert_advanced := 0;

        INSERT INTO profile_comparison_log (
            current_window_start,
            current_window_end,
            status,
            js_divergence,
            report,
            details,
            max_predicted_risk,
            pre_alert_flag,
            high_risk_percentile,
            js_threshold_used,
            stability_met,
            pre_alert_flag_advanced
        ) VALUES (
            v_current_start,
            v_current_end,
            v_status,
            NULL,
            to_jsonb(v_report),
            jsonb_build_object('reason', 'no_incident_free_window'),
            v_max_pred_risk,
            v_pre_alert,
            NULL,
            NULL,
            NULL,
            v_pre_alert_advanced
        );
        RETURN v_report;
    END IF;

    -- 5. Эталонное окно найдено – вычисляем метрики для обоих окон
    SELECT * INTO v_baseline_metrics
    FROM calculate_profile_metrics(v_baseline_start, v_baseline_end);

    SELECT * INTO v_current_metrics
    FROM calculate_profile_metrics(v_current_start, v_current_end);

    -- 6. Вычисляем JS-дивергенцию гистограмм
    v_js := histogram_divergence(
        v_baseline_metrics.state_histogram,
        v_current_metrics.state_histogram
    );

    -- 7. Определяем статус по порогам (без изменений)
    v_status := 'NORMAL';
    IF v_js >= 0.05 THEN
        v_status := 'WARNING';
    END IF;
    IF v_js >= 0.2 OR ABS(COALESCE(v_current_metrics.avg_correlation, 0) - COALESCE(v_baseline_metrics.avg_correlation, 0)) > 0.2 THEN
        v_status := 'CRITICAL';
    END IF;

    -- 8. Получаем порог JS из конфигурации (по умолчанию 0.2, но рекомендуется установить 0.3)
    SELECT COALESCE( (SELECT js_divergence_threshold FROM markov_config), 0.2 ) INTO v_js_threshold;

    -- 9. Вычисляем 90-й перцентиль риска за текущее окно (новый подход)
    SELECT PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY predicted_risk) INTO v_high_risk_percentile
    FROM prediction_log
    WHERE prediction_time BETWEEN v_current_start AND v_current_end;

    -- 10. Проверка устойчивости: не менее 3 записей за последние 5 минут,
    --     где JS >= порог И max_predicted_risk >= 0.95
    WITH stability_check AS (
        SELECT COUNT(*) >= 3 AS stable
        FROM profile_comparison_log
        WHERE current_window_end >= v_current_start - INTERVAL '5 minutes'
          AND js_divergence >= v_js_threshold
          AND max_predicted_risk >= 0.95
    )
    SELECT COALESCE(stable, FALSE) INTO v_stability_met FROM stability_check;

    -- 11. Вычисление старого флага (для обратной совместимости)
    IF v_js IS NOT NULL AND v_js >= v_js_threshold AND v_max_pred_risk IS NOT NULL AND v_max_pred_risk = 1 THEN
        v_pre_alert := 100;
    ELSE
        v_pre_alert := 0;
    END IF;

    -- 12. Вычисление нового флага (комплексный критерий)
    IF v_js IS NOT NULL 
       AND v_js >= v_js_threshold 
       AND v_high_risk_percentile >= 0.95 
       AND v_stability_met THEN
        v_pre_alert_advanced := 100;
    ELSE
        v_pre_alert_advanced := 0;
    END IF;

    -- 13. Формируем отчёт (добавляем информацию о новом флаге)
    v_report := array_append(v_report, '=== СРАВНЕНИЕ ЭТАЛОННОГО И ТЕКУЩЕГО ПРОФИЛЕЙ ===');
    v_report := array_append(v_report, format('Текущий момент: %s', v_now));
    v_report := array_append(v_report, format('Эталонное окно: %s – %s',
        to_char(v_baseline_start, 'YYYY-MM-DD HH24:MI'),
        to_char(v_baseline_end, 'YYYY-MM-DD HH24:MI')));
    v_report := array_append(v_report, format('Текущее окно: %s – %s',
        to_char(v_current_start, 'YYYY-MM-DD HH24:MI'),
        to_char(v_current_end, 'YYYY-MM-DD HH24:MI')));
    v_report := array_append(v_report, '');

    v_report := array_append(v_report, '--- МЕТРИКИ ---');
    v_report := array_append(v_report, format('  Средняя корреляция (эталон/текущий): %s / %s',
        COALESCE(round(v_baseline_metrics.avg_correlation::NUMERIC, 3)::TEXT, 'NULL'),
        COALESCE(round(v_current_metrics.avg_correlation::NUMERIC, 3)::TEXT, 'NULL')));
    v_report := array_append(v_report, format('  Доля критических (эталон/текущий): %s / %s',
        COALESCE(round(v_baseline_metrics.critical_ratio::NUMERIC, 3)::TEXT, 'NULL'),
        COALESCE(round(v_current_metrics.critical_ratio::NUMERIC, 3)::TEXT, 'NULL')));
    v_report := array_append(v_report, format('  Энтропия (эталон/текущий): %s / %s',
        COALESCE(round(v_baseline_metrics.entropy::NUMERIC, 3)::TEXT, 'NULL'),
        COALESCE(round(v_current_metrics.entropy::NUMERIC, 3)::TEXT, 'NULL')));
    v_report := array_append(v_report, format('  Доля петель (эталон/текущий): %s / %s',
        COALESCE(round(v_baseline_metrics.self_loop_ratio::NUMERIC, 3)::TEXT, 'NULL'),
        COALESCE(round(v_current_metrics.self_loop_ratio::NUMERIC, 3)::TEXT, 'NULL')));

    IF v_max_pred_risk IS NOT NULL THEN
        v_report := array_append(v_report, format('  Максимальный предсказанный риск в текущем окне: %s',
            round(v_max_pred_risk::NUMERIC, 4)::TEXT));
    ELSE
        v_report := array_append(v_report, '  Максимальный предсказанный риск в текущем окне: нет данных');
    END IF;

    -- Выводим новый флаг и промежуточные значения
    v_report := array_append(v_report, format('  90-й перцентиль риска: %s',
        COALESCE(round(v_high_risk_percentile::NUMERIC, 3)::TEXT, 'NULL')));
    v_report := array_append(v_report, format('  Порог JS (из конфига): %s', round(v_js_threshold::NUMERIC, 2)::TEXT));
    v_report := array_append(v_report, format('  Устойчивость (3 из 5 мин): %s', CASE WHEN v_stability_met THEN 'ДА' ELSE 'НЕТ' END));
    v_report := array_append(v_report, format('  Предаварийный флаг (старый): %s', CASE WHEN v_pre_alert = 100 THEN 'АКТИВИРОВАН (100)' ELSE 'НЕТ (0)' END));
    v_report := array_append(v_report, format('  Индикатор изменения профиля: %s', CASE WHEN v_pre_alert_advanced = 100 THEN 'АКТИВИРОВАН (100)' ELSE 'НЕТ (0)' END));

    v_report := array_append(v_report, '');
    v_report := array_append(v_report, '--- АНАЛИЗ ГИСТОГРАММЫ СОСТОЯНИЙ ---');
    IF v_js IS NOT NULL THEN
        v_report := array_append(v_report, format('  JS-дивергенция: %s', round(v_js::NUMERIC, 4)::TEXT));
        IF v_js < 0.01 THEN
            v_report := array_append(v_report, '  Интерпретация: гистограммы практически идентичны.');
        ELSIF v_js < 0.05 THEN
            v_report := array_append(v_report, '  Интерпретация: незначительные изменения.');
        ELSIF v_js < 0.1 THEN
            v_report := array_append(v_report, '  Интерпретация: заметные изменения – возможна смена характера нагрузки.');
        ELSE
            v_report := array_append(v_report, '  Интерпретация: значительные изменения – система работает в другом режиме.');
        END IF;
    ELSE
        v_report := array_append(v_report, '  Не удалось вычислить JS-дивергенцию (отсутствуют данные гистограмм).');
    END IF;

    v_report := array_append(v_report, '');
    v_report := array_append(v_report, format('--- ИТОГОВАЯ ОЦЕНКА: %s ---', v_status));
    v_report := array_append(v_report, CASE v_status
        WHEN 'NORMAL'   THEN '  Профиль соответствует эталону, отклонений не обнаружено.'
        WHEN 'WARNING'  THEN '  Обнаружены умеренные отклонения, рекомендуется мониторинг.'
        WHEN 'CRITICAL' THEN '  Выявлены значительные отклонения, требуется анализ и возможно вмешательство.'
        ELSE '  Неизвестный статус.'
    END);
    v_report := array_append(v_report, '=== КОНЕЦ ОТЧЁТА ===');

    -- 14. Сохраняем результат в profile_comparison_log (с новыми колонками)
    v_details := jsonb_build_object(
        'baseline_avg_correlation', v_baseline_metrics.avg_correlation,
        'baseline_critical_ratio', v_baseline_metrics.critical_ratio,
        'baseline_entropy', v_baseline_metrics.entropy,
        'baseline_self_loop_ratio', v_baseline_metrics.self_loop_ratio,
        'current_avg_correlation', v_current_metrics.avg_correlation,
        'current_critical_ratio', v_current_metrics.critical_ratio,
        'current_entropy', v_current_metrics.entropy,
        'current_self_loop_ratio', v_current_metrics.self_loop_ratio,
        'js_divergence', v_js,
        'js_threshold_used', v_js_threshold,
        'high_risk_percentile', v_high_risk_percentile,
        'stability_met', v_stability_met
    );

    INSERT INTO profile_comparison_log (
        baseline_window_start,
        baseline_window_end,
        current_window_start,
        current_window_end,
        status,
        js_divergence,
        report,
        details,
        max_predicted_risk,
        pre_alert_flag,
        high_risk_percentile,
        js_threshold_used,
        stability_met,
        pre_alert_flag_advanced
    ) VALUES (
        v_baseline_start,
        v_baseline_end,
        v_current_start,
        v_current_end,
        v_status,
        v_js,
        to_jsonb(v_report),
        v_details,
        v_max_pred_risk,
        v_pre_alert,
        v_high_risk_percentile,
        v_js_threshold,
        v_stability_met,
        v_pre_alert_advanced
    );

    RETURN v_report;
END;
$$;

COMMENT ON FUNCTION compare_profiles(INT, INT, INT) IS 'Сравнивает текущий профиль нагрузки с эталонным, сохраняет результат в profile_comparison_log, включая максимальный предсказанный риск и два флага предаварийного состояния: старый (pre_alert_flag) и новый (pre_alert_flag_advanced) по комплексному критерию (порог JS, 90-й перцентиль риска, устойчивость 3 из 5 мин).';


--------------------------------------------------------------------------------
-- 6. Пример использования (для справки)
--------------------------------------------------------------------------------
/*
-- Предварительно нужно убедиться, что incident_free_window_current содержит актуальное окно
SELECT find_incident_free_window(60);  -- если ещё не было

-- Сохранение эталонного профиля
SELECT save_baseline_profile();

-- Сохранение текущего профиля (например, за 60 минут)
SELECT save_current_profile(60);

-- Сравнение
SELECT unnest(compare_profiles());
*/


-- =============================================================================
-- 4. Функция очистки старых записей из profile_comparison_log
-- =============================================================================
CREATE OR REPLACE FUNCTION clean_profile_comparison_log()
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    v_retention_days INT;
    v_deleted_rows BIGINT;
BEGIN
    -- Получаем срок хранения из конфигурации
    SELECT COALESCE(profile_comparison_retention_days, 60) INTO v_retention_days
    FROM markov_config LIMIT 1;

    -- Удаляем записи старше указанного числа дней
    DELETE FROM profile_comparison_log
    WHERE created_at < now() - (v_retention_days || ' days')::INTERVAL;

    GET DIAGNOSTICS v_deleted_rows = ROW_COUNT;
    RETURN format('Удалено %s записей из profile_comparison_log (глубина хранения %s дней)',
                  v_deleted_rows, v_retention_days);
END;
$$;

COMMENT ON FUNCTION clean_profile_comparison_log() IS
'Удаляет записи из profile_comparison_log старше profile_comparison_retention_days (из markov_config).';

-- =============================================================================
-- 5. (Опционально) Пример использования и настройка cron
-- =============================================================================
/*
-- Ежедневная очистка (например, в 03:00)
-- 0 3 * * * psql -d expecto_db -U expecto_user -c "SELECT clean_profile_comparison_log();"

-- Ручной вызов
SELECT clean_profile_comparison_log();

-- Просмотр последних сравнений
SELECT id, created_at, status, js_divergence
FROM profile_comparison_log
ORDER BY created_at DESC
LIMIT 10;
*/


-- Функция: получить безынцидентное окно длины p_window_minutes,
-- заканчивающееся не позже p_ts, с максимальным концом.
CREATE OR REPLACE FUNCTION get_incident_free_window_before(
    p_ts                TIMESTAMPTZ,
    p_window_minutes    INT DEFAULT 60,
    p_exclude_before_min INT DEFAULT 30,   -- не используется
    p_exclude_after_min  INT DEFAULT 60    -- не используется
)
RETURNS TABLE (start_ts TIMESTAMPTZ, end_ts TIMESTAMPTZ)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_interval INTERVAL := (p_window_minutes || ' minutes')::INTERVAL;
    v_last_finish TIMESTAMPTZ;
	v_test_start_point TIMESTAMPTZ;	
BEGIN
    -- 1. Находим самый поздний завершённый инцидент
    SELECT MAX(finish_timepoint)
    INTO v_last_finish
    FROM performance_incident
    WHERE finish_timepoint IS NOT NULL;

    -- 2. Проверяем доступность окна (прошло не менее 1 часа и окно помещается до p_ts)
    IF v_last_finish IS NULL
       OR v_last_finish + INTERVAL '1 hour' > p_ts
       OR v_last_finish + v_interval > p_ts
    THEN
        RETURN;
    END IF;
	
	-- 3. ЕСЛИ после инцидента не прошло 2 часа
	-- фиксируем окно
	IF p_ts - v_last_finish <= interval '2 hour' 
	THEN
		-- Окно доступно: [finish, finish + window_minutes]
		RETURN QUERY SELECT v_last_finish AS start_ts, v_last_finish + v_interval AS end_ts;
	END IF;
	
	
	-- 4. Выбираем точку времени 2 часа назад
	SELECT p_ts - interval '2 hour' 
	INTO  v_test_start_point ;

    RETURN QUERY SELECT v_test_start_point AS start_ts, v_test_start_point + v_interval AS end_ts;
	
	
END;
$$;

COMMENT ON FUNCTION get_incident_free_window_before(TIMESTAMPTZ, INT, INT, INT) IS
'Возвращает эталонное окно [finish ; finish + window_minutes] для самого позднего завершённого инцидента,
при условии, что прошло не менее 1 часа после его окончания и окно целиком помещается до p_ts.
Если условие не выполнено – возвращает пустой набор.';




-- =============================================================================
-- Функция: generate_profile_incident_analytics_report
-- Назначение: формирует аналитический отчёт по сводному анализу сравнения
--             профилей производительности и инцидентов на основе данных
--             из profile_comparison_log и performance_incident.
-- Параметры:
--   p_start TIMESTAMPTZ – начало периода (по умолчанию 30 дней назад)
--   p_end   TIMESTAMPTZ – конец периода (по умолчанию now())
-- Возвращает: TEXT[] – массив строк с отформатированным отчётом.
-- =============================================================================
CREATE OR REPLACE FUNCTION generate_profile_incident_analytics_report(
    p_start TIMESTAMPTZ DEFAULT now() - INTERVAL '30 days',
    p_end   TIMESTAMPTZ DEFAULT now()
)
RETURNS TEXT[]
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_report TEXT[] := '{}';
    v_line_sep CONSTANT TEXT := E'\n';
    v_header TEXT := '=== СВОДНЫЙ АНАЛИЗ СРАВНЕНИЯ ПРОФИЛЕЙ И ИНЦИДЕНТОВ ===';
    v_ts TIMESTAMPTZ := now();

    -- Переменные для статистики
    v_total_comparisons BIGINT;
    v_normal_count BIGINT;
    v_warning_count BIGINT;
    v_critical_count BIGINT;
    v_avg_js_normal REAL;
    v_avg_js_warning REAL;
    v_avg_js_critical REAL;
    v_max_js REAL;

    -- Переменные для связи с инцидентами
    v_incidents_total BIGINT;
    v_incidents_with_any BIGINT;
    v_incidents_with_anomaly BIGINT;
    v_incidents_with_warning BIGINT;
    v_incidents_with_critical BIGINT;
    v_avg_time_to_incident_min REAL;
    v_incident_rate_anomaly REAL;
    v_incident_rate_normal REAL;

    -- Переменные для трендов
    v_trend_js TEXT;
    v_trend_status TEXT;

    v_rec RECORD;
    v_line TEXT;
BEGIN
    -- Проверка интервала
    IF p_start > p_end THEN
        RETURN ARRAY['Ошибка: начальная дата позже конечной.'];
    END IF;

    -- ========================================================================
    -- 1. Общая статистика по сравнениям (фильтр по current_window_end)
    -- ========================================================================
    SELECT
        COUNT(*) AS total,
        COUNT(*) FILTER (WHERE status = 'NORMAL') AS normal,
        COUNT(*) FILTER (WHERE status = 'WARNING') AS warning,
        COUNT(*) FILTER (WHERE status = 'CRITICAL') AS critical,
        COALESCE(AVG(js_divergence) FILTER (WHERE status = 'NORMAL'), 0) AS avg_js_normal,
        COALESCE(AVG(js_divergence) FILTER (WHERE status = 'WARNING'), 0) AS avg_js_warning,
        COALESCE(AVG(js_divergence) FILTER (WHERE status = 'CRITICAL'), 0) AS avg_js_critical,
        COALESCE(MAX(js_divergence), 0) AS max_js
    INTO
        v_total_comparisons,
        v_normal_count,
        v_warning_count,
        v_critical_count,
        v_avg_js_normal,
        v_avg_js_warning,
        v_avg_js_critical,
        v_max_js
    FROM profile_comparison_log
    WHERE current_window_end BETWEEN p_start AND p_end;   -- <-- исправлено

    -- ========================================================================
    -- 2. Связь с инцидентами
    -- ========================================================================
    -- 2.1. Общее число инцидентов в периоде
    SELECT COUNT(*) INTO v_incidents_total
    FROM performance_incident
    WHERE start_timepoint BETWEEN p_start AND p_end;

    -- 2.2. Инциденты, которым предшествовало сравнение (окно 30 минут до инцидента)
    WITH incident_comparisons AS (
        SELECT
            pi.start_timepoint AS incident_ts,
            pcl.current_window_end AS comp_ts,
            pcl.status,
            pcl.js_divergence
        FROM performance_incident pi
        JOIN profile_comparison_log pcl
            ON pcl.current_window_end BETWEEN pi.start_timepoint - INTERVAL '30 minutes' AND pi.start_timepoint
        WHERE pi.start_timepoint BETWEEN p_start AND p_end
    )
    SELECT
        COUNT(DISTINCT incident_ts) AS inc_with_any,
        COUNT(DISTINCT incident_ts) FILTER (WHERE status IN ('WARNING', 'CRITICAL')) AS inc_with_anomaly,
        COUNT(DISTINCT incident_ts) FILTER (WHERE status = 'WARNING') AS inc_with_warning,
        COUNT(DISTINCT incident_ts) FILTER (WHERE status = 'CRITICAL') AS inc_with_critical,
        AVG(EXTRACT(EPOCH FROM (incident_ts - comp_ts)) / 60) AS avg_time_to_incident
    INTO
        v_incidents_with_any,
        v_incidents_with_anomaly,
        v_incidents_with_warning,
        v_incidents_with_critical,
        v_avg_time_to_incident_min
    FROM incident_comparisons;

    -- 2.3. Доли
    v_incident_rate_anomaly := CASE
        WHEN v_incidents_total > 0 THEN v_incidents_with_anomaly::REAL / v_incidents_total
        ELSE 0
    END;
    v_incident_rate_normal := CASE
        WHEN v_incidents_total > 0 THEN (v_incidents_total - v_incidents_with_anomaly)::REAL / v_incidents_total
        ELSE 0
    END;

    -- ========================================================================
    -- 3. Тренды (по дням, используем current_window_end)
    -- ========================================================================
    WITH daily_stats AS (
        SELECT
            DATE(current_window_end) AS day,
            AVG(js_divergence) AS avg_js,
            MAX(CASE status
                WHEN 'CRITICAL' THEN 3
                WHEN 'WARNING' THEN 2
                WHEN 'NORMAL' THEN 1
                ELSE 0
            END) AS max_status_score
        FROM profile_comparison_log
        WHERE current_window_end BETWEEN p_start AND p_end
        GROUP BY DATE(current_window_end)
        ORDER BY day
    ),
    trend AS (
        SELECT
            CORR(EXTRACT(EPOCH FROM day)::REAL, avg_js) AS corr_js_time,
            CORR(EXTRACT(EPOCH FROM day)::REAL, max_status_score) AS corr_status_time
        FROM daily_stats
    )
    SELECT
        CASE
            WHEN corr_js_time > 0.5 THEN 'РАСТЕТ (ухудшение)'
            WHEN corr_js_time < -0.5 THEN 'УБЫВАЕТ (улучшение)'
            ELSE 'СТАБИЛЬНО'
        END AS trend_js,
        CASE
            WHEN corr_status_time > 0.5 THEN 'РАСТЕТ (ухудшение)'
            WHEN corr_status_time < -0.5 THEN 'УБЫВАЕТ (улучшение)'
            ELSE 'СТАБИЛЬНО'
        END AS trend_status
    INTO v_trend_js, v_trend_status
    FROM trend;

    -- ========================================================================
    -- 4. Формирование отчёта
    -- ========================================================================
    v_report := array_append(v_report, v_header);
    v_report := array_append(v_report, 'Отчёт сформирован: ' || to_char(v_ts, 'YYYY-MM-DD HH24:MI'));
    v_report := array_append(v_report, 'Период анализа: ' || to_char(p_start, 'YYYY-MM-DD HH24:MI') || ' – ' || to_char(p_end, 'YYYY-MM-DD HH24:MI'));
    v_report := array_append(v_report, '');

    v_report := array_append(v_report, '--- СТАТИСТИКА СРАВНЕНИЙ ПРОФИЛЕЙ ---');
    v_report := array_append(v_report, '  Всего сравнений: ' || v_total_comparisons::TEXT);
    IF v_total_comparisons > 0 THEN
        v_report := array_append(v_report, '  NORMAL: ' || v_normal_count::TEXT || ' (' || ROUND((v_normal_count::NUMERIC / v_total_comparisons) * 100, 1)::TEXT || '%)');
        v_report := array_append(v_report, '  WARNING: ' || v_warning_count::TEXT || ' (' || ROUND((v_warning_count::NUMERIC / v_total_comparisons) * 100, 1)::TEXT || '%)');
        v_report := array_append(v_report, '  CRITICAL: ' || v_critical_count::TEXT || ' (' || ROUND((v_critical_count::NUMERIC / v_total_comparisons) * 100, 1)::TEXT || '%)');
    ELSE
        v_report := array_append(v_report, '  Нет данных для расчёта процентного соотношения.');
    END IF;
    v_report := array_append(v_report, '  Средняя JS-дивергенция (NORMAL): ' || ROUND(v_avg_js_normal::NUMERIC, 4)::TEXT);
    v_report := array_append(v_report, '  Средняя JS-дивергенция (WARNING): ' || ROUND(v_avg_js_warning::NUMERIC, 4)::TEXT);
    v_report := array_append(v_report, '  Средняя JS-дивергенция (CRITICAL): ' || ROUND(v_avg_js_critical::NUMERIC, 4)::TEXT);
    v_report := array_append(v_report, '  Максимальная JS-дивергенция: ' || ROUND(v_max_js::NUMERIC, 4)::TEXT);
    v_report := array_append(v_report, '');

    v_report := array_append(v_report, '--- СВЯЗЬ С ИНЦИДЕНТАМИ ---');
    v_report := array_append(v_report, '  Всего инцидентов за период: ' || COALESCE(v_incidents_total::TEXT, '0'));
    v_report := array_append(v_report, '  Инцидентов, которым предшествовало хотя бы одно сравнение (в течение 60 мин): ' || COALESCE(v_incidents_with_any::TEXT, '0'));
    v_report := array_append(v_report, '  Из них с аномалией (WARNING/CRITICAL): ' || COALESCE(v_incidents_with_anomaly::TEXT, '0'));
    v_report := array_append(v_report, '    - WARNING: ' || COALESCE(v_incidents_with_warning::TEXT, '0'));
    v_report := array_append(v_report, '    - CRITICAL: ' || COALESCE(v_incidents_with_critical::TEXT, '0'));
    IF v_incidents_total > 0 THEN
        v_report := array_append(v_report, '  Доля инцидентов с предшествующей аномалией: ' || ROUND((v_incident_rate_anomaly * 100)::numeric, 1)::TEXT || '%');
        v_report := array_append(v_report, '  Доля инцидентов без аномалии: ' || ROUND((v_incident_rate_normal * 100)::numeric, 1)::TEXT || '%');
    END IF;
    IF v_avg_time_to_incident_min IS NOT NULL THEN
        v_report := array_append(v_report, '  Среднее время от сравнения до инцидента (мин): ' || ROUND(v_avg_time_to_incident_min::NUMERIC, 1)::TEXT);
    ELSE
        v_report := array_append(v_report, '  Нет данных о времени до инцидента.');
    END IF;
    v_report := array_append(v_report, '');

    v_report := array_append(v_report, '--- ТРЕНДЫ ---');
    v_report := array_append(v_report, '  Тренд JS-дивергенции (по дням): ' || COALESCE(v_trend_js, 'недоступно'));
    v_report := array_append(v_report, '  Тренд статусов (по дням): ' || COALESCE(v_trend_status, 'недоступно'));
    v_report := array_append(v_report, '');

    v_report := array_append(v_report, '--- РАСПРЕДЕЛЕНИЕ ПО ДНЯМ НЕДЕЛИ (средняя JS) ---');
    FOR v_rec IN
        SELECT
            EXTRACT(DOW FROM current_window_end) AS dow,
            COUNT(*) AS cnt,
            AVG(js_divergence) AS avg_js,
            MAX(CASE status WHEN 'CRITICAL' THEN 1 ELSE 0 END) AS has_critical
        FROM profile_comparison_log
        WHERE current_window_end BETWEEN p_start AND p_end
        GROUP BY EXTRACT(DOW FROM current_window_end)
        ORDER BY dow
    LOOP
        v_line := format('  День %s: сравнений %s, средняя JS %s%s',
            v_rec.dow,
            v_rec.cnt,
            ROUND(v_rec.avg_js::NUMERIC, 4),
            CASE WHEN v_rec.has_critical = 1 THEN ' (есть CRITICAL)' ELSE '' END
        );
        v_report := array_append(v_report, v_line);
    END LOOP;
    IF NOT FOUND THEN
        v_report := array_append(v_report, '  Нет данных для анализа по дням недели.');
    END IF;
    v_report := array_append(v_report, '');

    v_report := array_append(v_report, '=== КОНЕЦ ОТЧЁТА ===');

    RETURN v_report;
END;
$$;

COMMENT ON FUNCTION generate_profile_incident_analytics_report(TIMESTAMPTZ, TIMESTAMPTZ) IS
'Формирует аналитический отчёт по сводному анализу сравнения профилей производительности и инцидентов за указанный период. Возвращает массив строк.';

-- =============================================================================
-- Функция: generate_comprehensive_analytical_report
-- Назначение: формирует сводный аналитический отчёт по производительности,
--             прогнозированию и профилям нагрузки за указанный период.
-- Выполняет многомерный анализ, выявляет связи между метриками,
-- инцидентами, аномалиями профилей и качеством прогнозов.
-- Возвращает: TEXT[] – массив строк с отформатированным отчётом.
-- Параметры:
--   p_start TIMESTAMPTZ – начало периода (по умолчанию 30 дней назад)
--   p_end   TIMESTAMPTZ – конец периода (по умолчанию now())
-- =============================================================================
CREATE OR REPLACE FUNCTION generate_comprehensive_analytical_report(
    p_start TIMESTAMPTZ DEFAULT NULL,
    p_end   TIMESTAMPTZ DEFAULT NULL
)
RETURNS TEXT[]
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_start TIMESTAMPTZ;
    v_end   TIMESTAMPTZ;
    v_report TEXT[] := '{}';
    v_line_sep CONSTANT TEXT := E'\n';
    v_header TEXT := '=== СВОДНЫЙ АНАЛИТИЧЕСКИЙ ОТЧЁТ ===';
    v_ts TIMESTAMPTZ := now();

    -- Общая статистика
    v_total_transitions BIGINT;
    v_total_predictions BIGINT;
    v_total_incidents BIGINT;
    v_total_comparisons BIGINT;

    -- Статистика производительности
    v_avg_correlation REAL;
    v_avg_os_angle REAL;
    v_avg_wait_angle REAL;
    v_std_correlation REAL;
    v_std_os_angle REAL;
    v_std_wait_angle REAL;

    -- Статистика прогнозов
    v_pred_known BIGINT;
    v_pred_incidents BIGINT;
    v_accuracy REAL;
    v_precision REAL;
    v_recall REAL;
    v_brier REAL;
    v_roc_auc REAL;
    v_reliability INT;

    -- Статистика сравнения профилей
    v_js_avg REAL;
    v_js_max REAL;
    v_anomaly_rate REAL;           -- доля сравнений со статусом CRITICAL или WARNING
    v_critical_ratio REAL;

    -- Связи (корреляции)
    v_corr_js_inc REAL;            -- корреляция между JS-дивергенцией и количеством инцидентов (по дням)
    v_corr_acc_stab REAL;          -- корреляция между точностью прогнозов и стабильностью корреляции (CV)

    -- Тренды
    v_trend_js TEXT;
    v_trend_incidents TEXT;
    v_trend_accuracy TEXT;

    -- Вспомогательные
    v_rec RECORD;
    v_line TEXT;
BEGIN
    -- ========================================================================
    -- 1. Определение периода
    -- ========================================================================
    v_start := COALESCE(p_start, now() - INTERVAL '30 days');
    v_end   := COALESCE(p_end, now());
    IF v_start > v_end THEN
        RETURN ARRAY['Ошибка: начальная дата позже конечной.'];
    END IF;

    -- ========================================================================
    -- 2. Сбор базовой статистики
    -- ========================================================================
    -- 2.1. Переходы
    SELECT COUNT(*) INTO v_total_transitions
    FROM transition_log
    WHERE ts BETWEEN v_start AND v_end;

    -- 2.2. Прогнозы
    SELECT
        COUNT(*) AS total,
        COUNT(actual_outcome) AS known,
        COUNT(*) FILTER (WHERE actual_outcome = 1) AS incidents
    INTO v_total_predictions, v_pred_known, v_pred_incidents
    FROM prediction_log
    WHERE prediction_time BETWEEN v_start AND v_end;

    -- 2.3. Инциденты производительности
    SELECT COUNT(*) INTO v_total_incidents
    FROM performance_incident
    WHERE start_timepoint BETWEEN v_start AND v_end;

    -- 2.4. Сравнения профилей
    SELECT COUNT(*) INTO v_total_comparisons
    FROM profile_comparison_log
    WHERE created_at BETWEEN v_start AND v_end;

    -- ========================================================================
    -- 3. Метрики производительности (performance_history)
    -- ========================================================================
    SELECT
        AVG(correlation) AS avg_corr,
        AVG(os_angle) AS avg_os,
        AVG(wait_angle) AS avg_wait,
        STDDEV(correlation) AS std_corr,
        STDDEV(os_angle) AS std_os,
        STDDEV(wait_angle) AS std_wait
    INTO
        v_avg_correlation, v_avg_os_angle, v_avg_wait_angle,
        v_std_correlation, v_std_os_angle, v_std_wait_angle
    FROM performance_history
    WHERE ts BETWEEN v_start AND v_end;

    -- ========================================================================
    -- 4. Качество прогнозов
    -- ========================================================================
    IF v_pred_known > 0 THEN
        SELECT
            COUNT(*) FILTER (WHERE (predicted_risk >= 0.5 AND actual_outcome = 1)
                                 OR (predicted_risk < 0.5 AND actual_outcome = 0))::REAL / v_pred_known AS acc,
            COUNT(*) FILTER (WHERE predicted_risk >= 0.5 AND actual_outcome = 1)::REAL /
                NULLIF(COUNT(*) FILTER (WHERE predicted_risk >= 0.5), 0) AS prec,
            COUNT(*) FILTER (WHERE predicted_risk >= 0.5 AND actual_outcome = 1)::REAL /
                NULLIF(v_pred_incidents, 0) AS rec,
            AVG((predicted_risk - actual_outcome)^2) AS brier
        INTO v_accuracy, v_precision, v_recall, v_brier
        FROM prediction_log
        WHERE prediction_time BETWEEN v_start AND v_end
          AND actual_outcome IS NOT NULL;

        -- ROC-AUC (упрощённо через ранговый метод)
        WITH ranked AS (
            SELECT predicted_risk, actual_outcome,
                   ROW_NUMBER() OVER (ORDER BY predicted_risk ASC) AS rank
            FROM prediction_log
            WHERE prediction_time BETWEEN v_start AND v_end
              AND actual_outcome IS NOT NULL
        ),
        auc_calc AS (
            SELECT
                (SUM(CASE WHEN actual_outcome = 1 THEN rank ELSE 0 END) -
                 (COUNT(CASE WHEN actual_outcome = 1 THEN 1 END) *
                  (COUNT(CASE WHEN actual_outcome = 1 THEN 1 END) + 1) / 2.0)
                ) / (COUNT(CASE WHEN actual_outcome = 1 THEN 1 END) *
                     COUNT(CASE WHEN actual_outcome = 0 THEN 1 END)) AS auc
            FROM ranked
            WHERE actual_outcome IN (0,1)
        )
        SELECT COALESCE(auc, 0) INTO v_roc_auc FROM auc_calc;
    ELSE
        v_accuracy := NULL;
        v_precision := NULL;
        v_recall := NULL;
        v_brier := NULL;
        v_roc_auc := NULL;
    END IF;

    -- Рейтинг достоверности
    SELECT mchain_forecast_reliability() INTO v_reliability;

    -- ========================================================================
    -- 5. Статистика сравнения профилей
    -- ========================================================================
    SELECT
        AVG(js_divergence) AS avg_js,
        MAX(js_divergence) AS max_js,
        COUNT(*) FILTER (WHERE status IN ('CRITICAL', 'WARNING'))::REAL / NULLIF(COUNT(*), 0) AS anomaly_rate,
        COUNT(*) FILTER (WHERE status = 'CRITICAL')::REAL / NULLIF(COUNT(*), 0) AS critical_ratio
    INTO v_js_avg, v_js_max, v_anomaly_rate, v_critical_ratio
    FROM profile_comparison_log
    WHERE created_at BETWEEN v_start AND v_end;

    -- ========================================================================
    -- 6. Вычисление корреляций (по дням)
    -- ========================================================================
    -- 6.1. Корреляция между ежедневной средней JS-дивергенцией и количеством инцидентов
    WITH daily_js AS (
        SELECT DATE(created_at) AS day, AVG(js_divergence) AS avg_js
        FROM profile_comparison_log
        WHERE created_at BETWEEN v_start AND v_end
        GROUP BY DATE(created_at)
    ),
    daily_incidents AS (
        SELECT DATE(start_timepoint) AS day, COUNT(*) AS inc_cnt
        FROM performance_incident
        WHERE start_timepoint BETWEEN v_start AND v_end
        GROUP BY DATE(start_timepoint)
    ),
    daily_combined AS (
        SELECT
            COALESCE(j.day, i.day) AS day,
            COALESCE(j.avg_js, 0) AS avg_js,
            COALESCE(i.inc_cnt, 0) AS inc_cnt
        FROM daily_js j
        FULL JOIN daily_incidents i ON j.day = i.day
    )
    SELECT CORR(avg_js, inc_cnt) INTO v_corr_js_inc
    FROM daily_combined
    WHERE inc_cnt > 0;

    -- 6.2. Корреляция между точностью прогнозов и стабильностью корреляции (CV)
    -- Стабильность = STDDEV(correlation)/AVG(correlation) за день
    WITH daily_perf AS (
        SELECT DATE(ts) AS day,
               AVG(correlation) AS avg_corr,
               STDDEV(correlation) AS std_corr
        FROM performance_history
        WHERE ts BETWEEN v_start AND v_end
        GROUP BY DATE(ts)
    ),
    daily_acc AS (
        SELECT DATE(prediction_time) AS day,
               COUNT(*) FILTER (WHERE (predicted_risk >= 0.5 AND actual_outcome = 1)
                                    OR (predicted_risk < 0.5 AND actual_outcome = 0))::REAL /
               NULLIF(COUNT(*), 0) AS accuracy
        FROM prediction_log
        WHERE prediction_time BETWEEN v_start AND v_end
          AND actual_outcome IS NOT NULL
        GROUP BY DATE(prediction_time)
    ),
    combined_acc_stab AS (
        SELECT
            COALESCE(p.day, a.day) AS day,
            COALESCE(p.std_corr / NULLIF(p.avg_corr, 0), 0) AS cv_corr,
            COALESCE(a.accuracy, 0) AS accuracy
        FROM daily_perf p
        FULL JOIN daily_acc a ON p.day = a.day
        WHERE p.avg_corr IS NOT NULL AND a.accuracy IS NOT NULL
    )
    SELECT CORR(cv_corr, accuracy) INTO v_corr_acc_stab
    FROM combined_acc_stab;

    -- ========================================================================
    -- 7. Тренды (по дням)
    -- ========================================================================
    -- Тренд JS-дивергенции
    WITH daily_js_trend AS (
        SELECT DATE(created_at) AS day, AVG(js_divergence) AS avg_js
        FROM profile_comparison_log
        WHERE created_at BETWEEN v_start AND v_end
        GROUP BY DATE(created_at)
        ORDER BY day
    )
    SELECT
        CASE
            WHEN CORR(EXTRACT(EPOCH FROM day)::REAL, avg_js) > 0.3 THEN 'РАСТЕТ (ухудшение)'
            WHEN CORR(EXTRACT(EPOCH FROM day)::REAL, avg_js) < -0.3 THEN 'УБЫВАЕТ (улучшение)'
            ELSE 'СТАБИЛЬНО'
        END INTO v_trend_js
    FROM daily_js_trend;

    -- Тренд количества инцидентов
    WITH daily_inc_trend AS (
        SELECT DATE(start_timepoint) AS day, COUNT(*) AS inc_cnt
        FROM performance_incident
        WHERE start_timepoint BETWEEN v_start AND v_end
        GROUP BY DATE(start_timepoint)
        ORDER BY day
    )
    SELECT
        CASE
            WHEN CORR(EXTRACT(EPOCH FROM day)::REAL, inc_cnt) > 0.3 THEN 'РАСТЕТ'
            WHEN CORR(EXTRACT(EPOCH FROM day)::REAL, inc_cnt) < -0.3 THEN 'УБЫВАЕТ'
            ELSE 'СТАБИЛЬНО'
        END INTO v_trend_incidents
    FROM daily_inc_trend;

    -- Тренд точности прогнозов
    WITH daily_acc_trend AS (
        SELECT DATE(prediction_time) AS day,
               COUNT(*) FILTER (WHERE (predicted_risk >= 0.5 AND actual_outcome = 1)
                                    OR (predicted_risk < 0.5 AND actual_outcome = 0))::REAL /
               NULLIF(COUNT(*), 0) AS accuracy
        FROM prediction_log
        WHERE prediction_time BETWEEN v_start AND v_end
          AND actual_outcome IS NOT NULL
        GROUP BY DATE(prediction_time)
        ORDER BY day
    )
    SELECT
        CASE
            WHEN CORR(EXTRACT(EPOCH FROM day)::REAL, accuracy) > 0.3 THEN 'РАСТЕТ (улучшение)'
            WHEN CORR(EXTRACT(EPOCH FROM day)::REAL, accuracy) < -0.3 THEN 'УБЫВАЕТ (ухудшение)'
            ELSE 'СТАБИЛЬНО'
        END INTO v_trend_accuracy
    FROM daily_acc_trend;

    -- ========================================================================
    -- 8. Формирование отчёта
    -- ========================================================================
    v_report := array_append(v_report, v_header);
    v_report := array_append(v_report, 'Отчёт сформирован: ' || to_char(v_ts, 'YYYY-MM-DD HH24:MI'));
    v_report := array_append(v_report, 'Период анализа: ' || to_char(v_start, 'YYYY-MM-DD HH24:MI') || ' – ' || to_char(v_end, 'YYYY-MM-DD HH24:MI'));
    v_report := array_append(v_report, '');

    -- ------------------------------------------------------------------------
    -- Раздел 1: Общая статистика
    -- ------------------------------------------------------------------------
    v_report := array_append(v_report, '--- 1. ОБЩАЯ СТАТИСТИКА ---');
    v_report := array_append(v_report, '  Всего переходов (transition_log): ' || COALESCE(v_total_transitions::TEXT, '0'));
    v_report := array_append(v_report, '  Всего прогнозов (prediction_log): ' || COALESCE(v_total_predictions::TEXT, '0'));
    v_report := array_append(v_report, '    – с известным исходом: ' || COALESCE(v_pred_known::TEXT, '0'));
    v_report := array_append(v_report, '    – инцидентов по прогнозам: ' || COALESCE(v_pred_incidents::TEXT, '0'));
    v_report := array_append(v_report, '  Инцидентов производительности: ' || COALESCE(v_total_incidents::TEXT, '0'));
    v_report := array_append(v_report, '  Сравнений профилей (profile_comparison_log): ' || COALESCE(v_total_comparisons::TEXT, '0'));
    v_report := array_append(v_report, '');

    -- ------------------------------------------------------------------------
    -- Раздел 2: Метрики производительности
    -- ------------------------------------------------------------------------
    v_report := array_append(v_report, '--- 2. МЕТРИКИ ПРОИЗВОДИТЕЛЬНОСТИ (performance_history) ---');
    IF v_avg_correlation IS NOT NULL THEN
        v_report := array_append(v_report, '  Средняя корреляция: ' || round(v_avg_correlation::NUMERIC, 3)::TEXT);
        v_report := array_append(v_report, '  Стандартное отклонение корреляции: ' || round(v_std_correlation::NUMERIC, 3)::TEXT);
        v_report := array_append(v_report, '  Коэффициент вариации (CV) корреляции: ' || round((v_std_correlation / NULLIF(v_avg_correlation, 0))::NUMERIC, 3)::TEXT);
        v_report := array_append(v_report, '  Средний угол OS: ' || round(v_avg_os_angle::NUMERIC, 1)::TEXT || '°');
        v_report := array_append(v_report, '  Средний угол WAIT: ' || round(v_avg_wait_angle::NUMERIC, 1)::TEXT || '°');
    ELSE
        v_report := array_append(v_report, '  Нет данных в performance_history за период.');
    END IF;
    v_report := array_append(v_report, '');

    -- ------------------------------------------------------------------------
    -- Раздел 3: Качество прогнозов
    -- ------------------------------------------------------------------------
    v_report := array_append(v_report, '--- 3. КАЧЕСТВО ПРОГНОЗОВ ---');
    IF v_pred_known > 0 THEN
        v_report := array_append(v_report, '  Точность (accuracy, порог 0.5): ' || COALESCE(round(v_accuracy::NUMERIC, 4)::TEXT, 'NULL'));
        v_report := array_append(v_report, '  Точность (precision, порог 0.5): ' || COALESCE(round(v_precision::NUMERIC, 4)::TEXT, 'NULL'));
        v_report := array_append(v_report, '  Полнота (recall, порог 0.5): ' || COALESCE(round(v_recall::NUMERIC, 4)::TEXT, 'NULL'));
        v_report := array_append(v_report, '  Brier score: ' || COALESCE(round(v_brier::NUMERIC, 6)::TEXT, 'NULL'));
        v_report := array_append(v_report, '  ROC-AUC: ' || COALESCE(round(v_roc_auc::NUMERIC, 4)::TEXT, 'NULL'));
        v_report := array_append(v_report, '  Рейтинг достоверности (0–5): ' || v_reliability::TEXT);
    ELSE
        v_report := array_append(v_report, '  Нет прогнозов с известным исходом.');
    END IF;
    v_report := array_append(v_report, '');

    -- ------------------------------------------------------------------------
    -- Раздел 4: Сравнение профилей
    -- ------------------------------------------------------------------------
    v_report := array_append(v_report, '--- 4. СРАВНЕНИЕ ПРОФИЛЕЙ (profile_comparison_log) ---');
    IF v_total_comparisons > 0 THEN
        v_report := array_append(v_report, '  Средняя JS-дивергенция: ' || round(v_js_avg::NUMERIC, 4)::TEXT);
        v_report := array_append(v_report, '  Максимальная JS-дивергенция: ' || round(v_js_max::NUMERIC, 4)::TEXT);
        v_report := array_append(v_report, '  Доля сравнений с аномалией (WARNING/CRITICAL): ' || round((v_anomaly_rate * 100)::NUMERIC, 1)::TEXT || '%');
        v_report := array_append(v_report, '  Доля CRITICAL: ' || round((v_critical_ratio * 100)::NUMERIC, 1)::TEXT || '%');
    ELSE
        v_report := array_append(v_report, '  Нет записей в profile_comparison_log за период.');
    END IF;
    v_report := array_append(v_report, '');

    -- ------------------------------------------------------------------------
    -- Раздел 5: Корреляции и связи
    -- ------------------------------------------------------------------------
    v_report := array_append(v_report, '--- 5. КОРРЕЛЯЦИИ И СВЯЗИ ---');
    IF v_corr_js_inc IS NOT NULL THEN
        v_report := array_append(v_report, '  Корреляция (ежедневная JS-дивергенция vs. количество инцидентов): ' || round(v_corr_js_inc::NUMERIC, 3)::TEXT);
        IF v_corr_js_inc > 0.5 THEN
            v_report := array_append(v_report, '    → Сильная положительная связь: рост аномалий профиля сопровождается ростом инцидентов.');
        ELSIF v_corr_js_inc > 0.3 THEN
            v_report := array_append(v_report, '    → Умеренная положительная связь.');
        ELSIF v_corr_js_inc < -0.3 THEN
            v_report := array_append(v_report, '    → Отрицательная связь (неожиданно).');
        ELSE
            v_report := array_append(v_report, '    → Связь слабая или отсутствует.');
        END IF;
    ELSE
        v_report := array_append(v_report, '  Недостаточно данных для расчёта корреляции JS vs. инциденты.');
    END IF;

    IF v_corr_acc_stab IS NOT NULL THEN
        v_report := array_append(v_report, '  Корреляция (ежедневная точность прогнозов vs. стабильность корреляции (CV)): ' || round(v_corr_acc_stab::NUMERIC, 3)::TEXT);
        IF v_corr_acc_stab < -0.5 THEN
            v_report := array_append(v_report, '    → Сильная отрицательная связь: менее стабильная корреляция → хуже точность прогнозов.');
        ELSIF v_corr_acc_stab < -0.3 THEN
            v_report := array_append(v_report, '    → Умеренная отрицательная связь.');
        ELSE
            v_report := array_append(v_report, '    → Связь слабая или отсутствует.');
        END IF;
    ELSE
        v_report := array_append(v_report, '  Недостаточно данных для расчёта корреляции точность vs. стабильность.');
    END IF;
    v_report := array_append(v_report, '');

    -- ------------------------------------------------------------------------
    -- Раздел 6: Тренды
    -- ------------------------------------------------------------------------
    v_report := array_append(v_report, '--- 6. ТРЕНДЫ (по дням) ---');
    v_report := array_append(v_report, '  Тренд JS-дивергенции: ' || COALESCE(v_trend_js, 'недоступно'));
    v_report := array_append(v_report, '  Тренд количества инцидентов: ' || COALESCE(v_trend_incidents, 'недоступно'));
    v_report := array_append(v_report, '  Тренд точности прогнозов: ' || COALESCE(v_trend_accuracy, 'недоступно'));
    v_report := array_append(v_report, '');

    -- ------------------------------------------------------------------------
    -- Раздел 7: Итоговые выводы и рекомендации
    -- ------------------------------------------------------------------------
    v_report := array_append(v_report, '--- 7. ИТОГОВЫЕ ВЫВОДЫ И РЕКОМЕНДАЦИИ ---');
    -- Формируем содержательный итог
    DECLARE
        v_conclusion TEXT := '';
    BEGIN
        -- Оценка стабильности производительности
        IF v_std_correlation IS NOT NULL AND v_avg_correlation IS NOT NULL THEN
            IF v_std_correlation / NULLIF(v_avg_correlation, 0) < 0.1 THEN
                v_conclusion := v_conclusion || '✔ Производительность стабильна (CV корреляции < 0.1).' || E'\n';
            ELSE
                v_conclusion := v_conclusion || '⚠ Производительность нестабильна (CV корреляции >= 0.1). Рекомендуется анализ причин.' || E'\n';
            END IF;
        END IF;

        -- Оценка качества прогнозов
        IF v_accuracy IS NOT NULL THEN
            IF v_accuracy > 0.7 THEN
                v_conclusion := v_conclusion || '✔ Точность прогнозов высокая (> 0.7).' || E'\n';
            ELSIF v_accuracy > 0.5 THEN
                v_conclusion := v_conclusion || '⚠ Точность прогнозов умеренная (0.5–0.7). Возможно, требуется настройка модели.' || E'\n';
            ELSE
                v_conclusion := v_conclusion || '🔴 Точность прогнозов низкая (< 0.5). Требуется пересмотр модели или данных.' || E'\n';
            END IF;
        END IF;

        -- Оценка аномалий профилей
        IF v_anomaly_rate IS NOT NULL THEN
            IF v_anomaly_rate > 0.2 THEN
                v_conclusion := v_conclusion || '🔴 Высокая доля аномалий профилей (> 20%). Система часто отклоняется от эталона.' || E'\n';
            ELSIF v_anomaly_rate > 0.1 THEN
                v_conclusion := v_conclusion || '⚠ Умеренная доля аномалий профилей (10–20%). Рекомендуется мониторинг.' || E'\n';
            ELSE
                v_conclusion := v_conclusion || '✔ Доля аномалий профилей низкая (< 10%). Профили стабильны.' || E'\n';
            END IF;
        END IF;

        -- Связь аномалий и инцидентов
        IF v_corr_js_inc IS NOT NULL THEN
            IF v_corr_js_inc > 0.5 THEN
                v_conclusion := v_conclusion || '🔴 Сильная корреляция между аномалиями профилей и инцидентами. Аномалии профилей являются ранним признаком инцидентов.' || E'\n';
            ELSIF v_corr_js_inc > 0.3 THEN
                v_conclusion := v_conclusion || '⚠ Умеренная корреляция. Аномалии профилей частично предсказывают инциденты.' || E'\n';
            ELSE
                v_conclusion := v_conclusion || '✔ Связь аномалий профилей и инцидентов слабая. Возможно, инциденты вызваны другими факторами.' || E'\n';
            END IF;
        END IF;

        -- Рекомендации
        v_report := array_append(v_report, v_conclusion);
        v_report := array_append(v_report, '  Рекомендации:');
        IF v_reliability < 3 THEN
            v_report := array_append(v_report, '    - Низкая достоверность прогнозов. Накопите больше данных или пересмотрите параметры забывания.');
        END IF;
        IF v_anomaly_rate > 0.15 THEN
            v_report := array_append(v_report, '    - Частые аномалии профилей. Проверьте, не изменился ли характер нагрузки, обновите эталонный профиль.');
        END IF;
        IF v_corr_js_inc > 0.4 AND v_anomaly_rate > 0.1 THEN
            v_report := array_append(v_report, '    - Используйте аномалии профилей как ранний индикатор риска. Настройте пороги для оповещений.');
        END IF;
        IF v_trend_accuracy = 'УБЫВАЕТ (ухудшение)' THEN
            v_report := array_append(v_report, '    - Качество прогнозов ухудшается. Проверьте актуальность модели и параметры забывания.');
        END IF;
        IF v_trend_incidents = 'РАСТЕТ' THEN
            v_report := array_append(v_report, '    - Наблюдается рост инцидентов. Срочно проанализируйте причины.');
        END IF;
        IF array_length(v_report, 1) = 0 THEN
            v_report := array_append(v_report, '    - Все показатели в норме. Продолжайте мониторинг.');
        END IF;
    END;

    v_report := array_append(v_report, '');
    v_report := array_append(v_report, '=== КОНЕЦ ОТЧЁТА ===');

    RETURN v_report;
END;
$$;

COMMENT ON FUNCTION generate_comprehensive_analytical_report(TIMESTAMPTZ, TIMESTAMPTZ) IS
'Формирует сводный аналитический отчёт, объединяющий данные о производительности,
прогнозах и сравнении профилей. Включает статистику, корреляции, тренды и итоговые
рекомендации. Возвращает массив строк для удобного отображения.';

-- Процедура исторического заполнения
CREATE OR REPLACE PROCEDURE historical_fill_profile_comparison_log(
    p_start                TIMESTAMPTZ,
    p_end                  TIMESTAMPTZ,
    p_window_minutes       INT DEFAULT 60,
    p_step_minutes         INT DEFAULT 1,
    p_overwrite            BOOLEAN DEFAULT TRUE,
    p_exclude_before_min   INT DEFAULT 30,   -- не используется
    p_exclude_after_min    INT DEFAULT 60    -- не используется
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_ts               TIMESTAMPTZ;
    v_baseline_start   TIMESTAMPTZ;
    v_baseline_end     TIMESTAMPTZ;
    v_current_start    TIMESTAMPTZ;
    v_current_end      TIMESTAMPTZ;
    v_baseline_metrics RECORD;
    v_current_metrics  RECORD;
    v_js               REAL;
    v_status           TEXT;
    v_report           TEXT[] := '{}';
    v_details          JSONB;
    v_counter          BIGINT := 0;
    v_total_minutes    BIGINT;
    v_last_notice      TIMESTAMPTZ := NULL;
    v_inside_incident  BOOLEAN;
BEGIN
    IF p_start > p_end THEN
        RAISE EXCEPTION 'p_start (%s) > p_end (%s)', p_start, p_end;
    END IF;

    IF p_overwrite THEN
        DELETE FROM profile_comparison_log
        WHERE current_window_end BETWEEN p_start AND p_end;
        RAISE NOTICE 'Удалено % записей за период [%, %]',
                     (SELECT COUNT(*) FROM profile_comparison_log
                      WHERE current_window_end BETWEEN p_start AND p_end),
                     p_start, p_end;
    END IF;

    v_total_minutes := EXTRACT(EPOCH FROM (p_end - p_start)) / 60 + 1;
    RAISE NOTICE 'Начало исторического заполнения: % → %, окно % мин, шаг % мин, всего % минут',
                 p_start, p_end, p_window_minutes, p_step_minutes, v_total_minutes;

    v_ts := p_start;
    WHILE v_ts <= p_end LOOP
        v_counter := v_counter + 1;

        -- Проверка: находится ли v_ts внутри активного инцидента
        SELECT EXISTS (
            SELECT 1
            FROM performance_incident
            WHERE start_timepoint <= v_ts
              AND (finish_timepoint IS NULL OR finish_timepoint >= v_ts)
        ) INTO v_inside_incident;

        IF v_inside_incident THEN
            -- Случай 1: внутри инцидента – запись INCIDENT
            INSERT INTO profile_comparison_log (
                current_window_start,
                current_window_end,
                status,
                js_divergence,
                report,
                details
            ) VALUES (
                v_ts - (p_window_minutes || ' minutes')::INTERVAL,
                v_ts,
                'INCIDENT',
                NULL,
                NULL,
                NULL
            );
            v_ts := v_ts + (p_step_minutes || ' minutes')::INTERVAL;
            CONTINUE;
        END IF;

        -- Попытка получить эталонное окно (по новой стратегии)
        SELECT start_ts, end_ts INTO v_baseline_start, v_baseline_end
        FROM get_incident_free_window_before(v_ts, p_window_minutes, p_exclude_before_min, p_exclude_after_min);

        IF v_baseline_start IS NULL THEN
            -- Случай 2: после инцидента, но ещё не прошло 1 часа
            -- (эталонное окно недоступно) – запись INCIDENT
            INSERT INTO profile_comparison_log (
                current_window_start,
                current_window_end,
                status,
                js_divergence,
                report,
                details
            ) VALUES (
                v_ts - (p_window_minutes || ' minutes')::INTERVAL,
                v_ts,
                'INCIDENT',
                NULL,
                NULL,
                NULL
            );
            v_ts := v_ts + (p_step_minutes || ' minutes')::INTERVAL;
            CONTINUE;
        END IF;

        -- Эталонное окно доступно – выполняем нормальный расчёт
        v_current_start := v_ts - (p_window_minutes || ' minutes')::INTERVAL;
        v_current_end   := v_ts;

        SELECT * INTO v_baseline_metrics
        FROM calculate_profile_metrics(v_baseline_start, v_baseline_end);

        SELECT * INTO v_current_metrics
        FROM calculate_profile_metrics(v_current_start, v_current_end);

        v_js := histogram_divergence(
            v_baseline_metrics.state_histogram,
            v_current_metrics.state_histogram
        );

        v_status := 'NORMAL';
        IF v_js >= 0.05 THEN
            v_status := 'WARNING';
        END IF;
        IF v_js >= 0.2 OR ABS(COALESCE(v_current_metrics.avg_correlation, 0) - COALESCE(v_baseline_metrics.avg_correlation, 0)) > 0.2 THEN
            v_status := 'CRITICAL';
        END IF;

        v_details := jsonb_build_object(
            'baseline_avg_correlation', v_baseline_metrics.avg_correlation,
            'baseline_critical_ratio', v_baseline_metrics.critical_ratio,
            'baseline_entropy', v_baseline_metrics.entropy,
            'baseline_self_loop_ratio', v_baseline_metrics.self_loop_ratio,
            'current_avg_correlation', v_current_metrics.avg_correlation,
            'current_critical_ratio', v_current_metrics.critical_ratio,
            'current_entropy', v_current_metrics.entropy,
            'current_self_loop_ratio', v_current_metrics.self_loop_ratio,
            'js_divergence', v_js
        );

        v_report := ARRAY[
            'Сравнение на ' || v_ts,
            'Эталон: ' || v_baseline_start || ' – ' || v_baseline_end,
            'Текущий: ' || v_current_start || ' – ' || v_current_end,
            'JS-дивергенция: ' || COALESCE(ROUND(v_js::NUMERIC, 4)::TEXT, 'NULL'),
            'Статус: ' || v_status
        ];

        INSERT INTO profile_comparison_log (
            baseline_window_start,
            baseline_window_end,
            current_window_start,
            current_window_end,
            status,
            js_divergence,
            report,
            details
        ) VALUES (
            v_baseline_start,
            v_baseline_end,
            v_current_start,
            v_current_end,
            v_status,
            v_js,
            to_jsonb(v_report),
            v_details
        );

        IF v_counter % 100 = 0 OR (v_last_notice IS NULL OR v_ts - v_last_notice > INTERVAL '5 minutes') THEN
            RAISE NOTICE 'Прогресс: % из % минут (%.1f%%), последний ts = %',
                         v_counter, v_total_minutes,
                         (v_counter::NUMERIC / v_total_minutes * 100),
                         v_ts;
            v_last_notice := v_ts;
        END IF;

        v_ts := v_ts + (p_step_minutes || ' minutes')::INTERVAL;
    END LOOP;

    RAISE NOTICE 'Заполнение завершено. Вставлено записей: %', v_counter;
END;
$$;

COMMENT ON PROCEDURE historical_fill_profile_comparison_log IS
'Заполняет profile_comparison_log для каждой минуты диапазона.
Использует новую стратегию выбора эталонного окна (доступно только после finish + 1 час).
Если v_ts внутри инцидента или эталон недоступен – вставляется запись со статусом INCIDENT и NULL-полями.';

-- =============================================================================
-- Функция: generate_analytical_report (модифицированная)
-- Назначение: формирует аналитический отчёт по заданному периоду, исключая
--             из расчётов статус 'INCIDENT' из profile_comparison_log.
--             Показатели: качество прогнозов, доли статусов перед инцидентами,
--             время от CRITICAL до инцидента, тренды, выводы.
-- Параметры:
--   p_start TEXT – начало периода в формате 'YYYY-MM-DD HH24:MI'
--   p_end   TEXT – конец периода в формате 'YYYY-MM-DD HH24:MI'
-- Возвращает: TEXT[] – массив строк отчёта.
-- =============================================================================

CREATE OR REPLACE FUNCTION generate_analytical_report(
    p_start TEXT,
    p_end   TEXT
)
RETURNS TEXT[]
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_start TIMESTAMPTZ;
    v_end   TIMESTAMPTZ;
    v_report TEXT[] := '{}';

    -- Агрегаты из объединённого запроса (без INCIDENT)
    v_total_records BIGINT;
    v_avg_risk REAL;
    v_status_counts JSONB;
    v_avg_js_normal REAL;
    v_avg_js_warning REAL;
    v_avg_js_critical REAL;
    v_incidents_total BIGINT;
    v_accuracy REAL;
    v_precision REAL;
    v_recall REAL;
    v_known_outcomes BIGINT;

    -- Статистика по дням для тренда
    v_trend_js TEXT;
    v_trend_risk TEXT;
    v_days_diff INT;

    -- Время от CRITICAL до инцидента
    v_min_diff REAL;
    v_max_diff REAL;
    v_avg_diff REAL;
    v_median_diff REAL;

    -- Статусы перед инцидентами (исключая INCIDENT)
    v_inc_with_critical BIGINT;
    v_inc_with_warning BIGINT;
    v_inc_with_normal BIGINT;
    v_inc_without_status BIGINT;

BEGIN
    -- Преобразование входных параметров
    BEGIN
        v_start := to_timestamp(p_start, 'YYYY-MM-DD HH24:MI');
        v_end   := to_timestamp(p_end,   'YYYY-MM-DD HH24:MI');
    EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION 'Неверный формат даты/времени. Ожидается "YYYY-MM-DD HH24:MI" (например, "2026-07-10 00:00").';
    END;

    IF v_start > v_end THEN
        RAISE EXCEPTION 'Начальная дата должна быть раньше конечной.';
    END IF;

    -- ========================================================================
    -- 1. Основные агрегаты (прогнозы + сравнения профилей) – исключаем INCIDENT
    -- ========================================================================
    WITH combined AS (
        SELECT
            date_trunc('minute', pl.prediction_time) AS pred_minute,
            pl.predicted_risk,
            pl.actual_outcome,
            pcl.status,
            pcl.js_divergence,
            pcl.current_window_end
        FROM prediction_log pl
        JOIN profile_comparison_log pcl
            ON date_trunc('minute', pl.prediction_time) = date_trunc('minute', pcl.current_window_end)
        WHERE pl.prediction_time BETWEEN v_start AND v_end
          AND pcl.current_window_end BETWEEN v_start AND v_end
          AND pcl.status != 'INCIDENT'           -- Исключаем INCIDENT
    ),
    aggregated AS (
        SELECT
            COUNT(*) AS total_records,
            AVG(predicted_risk) AS avg_risk,
            COUNT(actual_outcome) AS known_outcomes,
            AVG(CASE WHEN actual_outcome IS NOT NULL THEN (CASE WHEN predicted_risk >= 0.5 AND actual_outcome = 1 THEN 1.0
                                                                WHEN predicted_risk < 0.5 AND actual_outcome = 0 THEN 1.0
                                                                ELSE 0.0 END) END) AS accuracy,
            AVG(CASE WHEN predicted_risk >= 0.5 AND actual_outcome = 1 THEN 1.0
                     WHEN predicted_risk >= 0.5 AND actual_outcome = 0 THEN 0.0
                     ELSE NULL END) AS precision,
            AVG(CASE WHEN actual_outcome = 1 AND predicted_risk >= 0.5 THEN 1.0
                     WHEN actual_outcome = 1 AND predicted_risk < 0.5 THEN 0.0
                     ELSE NULL END) AS recall,
            jsonb_build_object(
                'NORMAL', COUNT(*) FILTER (WHERE status = 'NORMAL'),
                'WARNING', COUNT(*) FILTER (WHERE status = 'WARNING'),
                'CRITICAL', COUNT(*) FILTER (WHERE status = 'CRITICAL')
            ) AS status_counts,
            AVG(js_divergence) FILTER (WHERE status = 'NORMAL') AS avg_js_normal,
            AVG(js_divergence) FILTER (WHERE status = 'WARNING') AS avg_js_warning,
            AVG(js_divergence) FILTER (WHERE status = 'CRITICAL') AS avg_js_critical
        FROM combined
    )
    SELECT
        total_records,
        avg_risk,
        known_outcomes,
        accuracy,
        precision,
        recall,
        status_counts,
        avg_js_normal,
        avg_js_warning,
        avg_js_critical
    INTO
        v_total_records,
        v_avg_risk,
        v_known_outcomes,
        v_accuracy,
        v_precision,
        v_recall,
        v_status_counts,
        v_avg_js_normal,
        v_avg_js_warning,
        v_avg_js_critical
    FROM aggregated;

    -- Если данных нет
    IF v_total_records IS NULL OR v_total_records = 0 THEN
        v_report := array_append(v_report, '=== АНАЛИТИЧЕСКИЙ ОТЧЁТ ===');
        v_report := array_append(v_report, 'Период: ' || to_char(v_start, 'YYYY-MM-DD HH24:MI') || ' – ' || to_char(v_end, 'YYYY-MM-DD HH24:MI'));
        v_report := array_append(v_report, 'Нет данных для анализа за указанный период (после исключения INCIDENT).');
        RETURN v_report;
    END IF;

    -- ========================================================================
    -- 2. Общее количество инцидентов за период
    -- ========================================================================
    SELECT COUNT(*) INTO v_incidents_total
    FROM performance_incident
    WHERE start_timepoint BETWEEN v_start AND v_end;

    -- ========================================================================
    -- 3. Время от статуса CRITICAL до ближайшего инцидента
    --    (используем только CRITICAL, INCIDENT не влияет)
    -- ========================================================================
    WITH critical_times AS (
        SELECT current_window_end
        FROM profile_comparison_log
        WHERE status = 'CRITICAL'
          AND current_window_end BETWEEN v_start AND v_end
    ),
    incident_times AS (
        SELECT start_timepoint
        FROM performance_incident
        WHERE start_timepoint BETWEEN v_start AND v_end
    ),
    time_diffs AS (
        SELECT
            EXTRACT(EPOCH FROM (i.start_timepoint - c.current_window_end)) / 60 AS diff_min
        FROM critical_times c
        CROSS JOIN LATERAL (
            SELECT start_timepoint
            FROM incident_times
            WHERE start_timepoint > c.current_window_end
            ORDER BY start_timepoint
            LIMIT 1
        ) i
    )
    SELECT
        MIN(diff_min) AS min_diff,
        MAX(diff_min) AS max_diff,
        AVG(diff_min) AS avg_diff,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY diff_min) AS median_diff
    INTO v_min_diff, v_max_diff, v_avg_diff, v_median_diff
    FROM time_diffs;

    -- ========================================================================
    -- 4. Статусы перед инцидентами (последний статус перед каждым инцидентом,
    --    исключая INCIDENT)
    -- ========================================================================
    WITH incident_prior_status AS (
        SELECT
            pi.start_timepoint,
            (
                SELECT pcl.status
                FROM profile_comparison_log pcl
                WHERE pcl.current_window_end < pi.start_timepoint
                  AND pcl.current_window_end BETWEEN v_start AND v_end
                  AND pcl.status != 'INCIDENT'      -- Исключаем INCIDENT
                ORDER BY pcl.current_window_end DESC
                LIMIT 1
            ) AS prior_status
        FROM performance_incident pi
        WHERE pi.start_timepoint BETWEEN v_start AND v_end
    )
    SELECT
        COUNT(*) FILTER (WHERE prior_status = 'CRITICAL') AS critical_cnt,
        COUNT(*) FILTER (WHERE prior_status = 'WARNING') AS warning_cnt,
        COUNT(*) FILTER (WHERE prior_status = 'NORMAL') AS normal_cnt,
        COUNT(*) FILTER (WHERE prior_status IS NULL) AS without_cnt
    INTO
        v_inc_with_critical,
        v_inc_with_warning,
        v_inc_with_normal,
        v_inc_without_status
    FROM incident_prior_status;

    -- ========================================================================
    -- 5. Тренды (если период > 1 дня) – также исключаем INCIDENT
    -- ========================================================================
    v_days_diff := EXTRACT(DAY FROM (v_end - v_start))::INT;
    IF v_days_diff >= 1 THEN
        WITH daily_stats AS (
            SELECT
                DATE(pcl.current_window_end) AS day,
                AVG(pcl.js_divergence) AS avg_js,
                AVG(pl.predicted_risk) AS avg_risk
            FROM profile_comparison_log pcl
            JOIN prediction_log pl
                ON date_trunc('minute', pl.prediction_time) = date_trunc('minute', pcl.current_window_end)
            WHERE pcl.current_window_end BETWEEN v_start AND v_end
              AND pl.prediction_time BETWEEN v_start AND v_end
              AND pcl.status != 'INCIDENT'
            GROUP BY DATE(pcl.current_window_end)
            ORDER BY day
        )
        SELECT
            CASE
                WHEN CORR(EXTRACT(EPOCH FROM day)::REAL, avg_js) > 0.3 THEN 'РАСТЕТ (ухудшение)'
                WHEN CORR(EXTRACT(EPOCH FROM day)::REAL, avg_js) < -0.3 THEN 'УБЫВАЕТ (улучшение)'
                ELSE 'СТАБИЛЬНО'
            END AS trend_js,
            CASE
                WHEN CORR(EXTRACT(EPOCH FROM day)::REAL, avg_risk) > 0.3 THEN 'РАСТЕТ'
                WHEN CORR(EXTRACT(EPOCH FROM day)::REAL, avg_risk) < -0.3 THEN 'УБЫВАЕТ'
                ELSE 'СТАБИЛЬНО'
            END AS trend_risk
        INTO v_trend_js, v_trend_risk
        FROM daily_stats;
    ELSE
        v_trend_js := 'недостаточно данных (период ≤ 1 дня)';
        v_trend_risk := 'недостаточно данных (период ≤ 1 дня)';
    END IF;

    -- ========================================================================
    -- 6. Формирование отчёта
    -- ========================================================================
    v_report := array_append(v_report, '=== АНАЛИТИЧЕСКИЙ ОТЧЁТ ===');
    v_report := array_append(v_report, 'Период: ' || to_char(v_start, 'YYYY-MM-DD HH24:MI') || ' – ' || to_char(v_end, 'YYYY-MM-DD HH24:MI'));
    v_report := array_append(v_report, '');

    -- Общая статистика
    v_report := array_append(v_report, '--- ОБЩАЯ СТАТИСТИКА ---');
    v_report := array_append(v_report, '  Количество записей (прогноз + сравнение профиля, без INCIDENT): ' || v_total_records::TEXT);
    v_report := array_append(v_report, '  Средний предсказанный риск: ' || round(v_avg_risk::NUMERIC, 4)::TEXT);

    -- Качество прогнозов с интерпретацией
    IF v_known_outcomes > 0 THEN
        v_report := array_append(v_report, '  Прогнозов с известным исходом: ' || v_known_outcomes::TEXT);
        v_report := array_append(v_report, '  Точность (accuracy, порог 0.5): ' || round(COALESCE(v_accuracy, 0)::NUMERIC, 4)::TEXT);
        v_report := array_append(v_report, '  Точность (precision, порог 0.5): ' || round(COALESCE(v_precision, 0)::NUMERIC, 4)::TEXT);
        v_report := array_append(v_report, '  Полнота (recall, порог 0.5): ' || round(COALESCE(v_recall, 0)::NUMERIC, 4)::TEXT);

        DECLARE
            analysis TEXT := '';
        BEGIN
            IF COALESCE(v_accuracy, 0) >= 0.8 THEN
                analysis := analysis || 'Accuracy высокая (>0.8), ';
            ELSIF COALESCE(v_accuracy, 0) >= 0.6 THEN
                analysis := analysis || 'Accuracy умеренная (0.6-0.8), ';
            ELSE
                analysis := analysis || 'Accuracy низкая (<0.6), ';
            END IF;

            IF COALESCE(v_precision, 0) >= 0.8 THEN
                analysis := analysis || 'Precision высокая (>0.8), ';
            ELSIF COALESCE(v_precision, 0) >= 0.6 THEN
                analysis := analysis || 'Precision умеренная (0.6-0.8), ';
            ELSE
                analysis := analysis || 'Precision низкая (<0.6), ';
            END IF;

            IF COALESCE(v_recall, 0) >= 0.8 THEN
                analysis := analysis || 'Recall высокий (>0.8).';
            ELSIF COALESCE(v_recall, 0) >= 0.6 THEN
                analysis := analysis || 'Recall умеренный (0.6-0.8).';
            ELSE
                analysis := analysis || 'Recall низкий (<0.6).';
            END IF;

            v_report := array_append(v_report, '  Интерпретация: ' || analysis);
        END;
    ELSE
        v_report := array_append(v_report, '  Нет данных о фактических исходах (actual_outcome отсутствует).');
    END IF;

    v_report := array_append(v_report, '');

    -- Сравнение профилей (только NORMAL, WARNING, CRITICAL, без INCIDENT)
    v_report := array_append(v_report, '--- СРАВНЕНИЕ ПРОФИЛЕЙ ---');
    v_report := array_append(v_report, '  Распределение статусов (без INCIDENT):');
    v_report := array_append(v_report, '    NORMAL: ' || COALESCE((v_status_counts->>'NORMAL')::TEXT, '0') || ' (' || round((COALESCE((v_status_counts->>'NORMAL')::NUMERIC, 0) / v_total_records * 100)::NUMERIC, 1) || '%)');
    v_report := array_append(v_report, '    WARNING: ' || COALESCE((v_status_counts->>'WARNING')::TEXT, '0') || ' (' || round((COALESCE((v_status_counts->>'WARNING')::NUMERIC, 0) / v_total_records * 100)::NUMERIC, 1) || '%)');
    v_report := array_append(v_report, '    CRITICAL: ' || COALESCE((v_status_counts->>'CRITICAL')::TEXT, '0') || ' (' || round((COALESCE((v_status_counts->>'CRITICAL')::NUMERIC, 0) / v_total_records * 100)::NUMERIC, 1) || '%)');
    IF v_avg_js_normal IS NOT NULL THEN
        v_report := array_append(v_report, '  Средняя JS-дивергенция (NORMAL): ' || round(v_avg_js_normal::NUMERIC, 4)::TEXT);
    END IF;
    IF v_avg_js_warning IS NOT NULL THEN
        v_report := array_append(v_report, '  Средняя JS-дивергенция (WARNING): ' || round(v_avg_js_warning::NUMERIC, 4)::TEXT);
    END IF;
    IF v_avg_js_critical IS NOT NULL THEN
        v_report := array_append(v_report, '  Средняя JS-дивергенция (CRITICAL): ' || round(v_avg_js_critical::NUMERIC, 4)::TEXT);
    END IF;

    -- Связь с инцидентами
    v_report := array_append(v_report, '');
    v_report := array_append(v_report, '--- СВЯЗЬ С ИНЦИДЕНТАМИ ---');
    v_report := array_append(v_report, '  Всего инцидентов за период: ' || v_incidents_total::TEXT);

    -- Вывод долей статусов перед инцидентами (исключая INCIDENT в предшествующих статусах)
    DECLARE
        total_with_status BIGINT;
        pct_critical TEXT;
        pct_warning TEXT;
        pct_normal TEXT;
        pct_without TEXT;
    BEGIN
        total_with_status := v_inc_with_critical + v_inc_with_warning + v_inc_with_normal;
        IF v_incidents_total > 0 THEN
            pct_critical := round((v_inc_with_critical::NUMERIC / v_incidents_total * 100)::NUMERIC, 1) || '%';
            pct_warning  := round((v_inc_with_warning::NUMERIC  / v_incidents_total * 100)::NUMERIC, 1) || '%';
            pct_normal   := round((v_inc_with_normal::NUMERIC   / v_incidents_total * 100)::NUMERIC, 1) || '%';
            pct_without  := round((v_inc_without_status::NUMERIC / v_incidents_total * 100)::NUMERIC, 1) || '%';
        ELSE
            pct_critical := '0%';
            pct_warning  := '0%';
            pct_normal   := '0%';
            pct_without  := '100%';
        END IF;

        v_report := array_append(v_report, '  Доля состояний CRITICAL до инцидента: ' || v_inc_with_critical::TEXT || ' (' || pct_critical || ')');
        v_report := array_append(v_report, '  Доля состояний WARNING до инцидента: ' || v_inc_with_warning::TEXT || ' (' || pct_warning || ')');
        v_report := array_append(v_report, '  Доля инцидентов сразу после состояния NORMAL: ' || v_inc_with_normal::TEXT || ' (' || pct_normal || ')');
        IF v_inc_without_status > 0 THEN
            v_report := array_append(v_report, '  Инцидентов без предшествующего статуса (или только INCIDENT): ' || v_inc_without_status::TEXT || ' (' || pct_without || ')');
        END IF;
    END;

    -- Время от CRITICAL до инцидента
    IF v_min_diff IS NOT NULL THEN
        v_report := array_append(v_report, '  Время от статуса CRITICAL до следующего инцидента (минут):');
        v_report := array_append(v_report, '    минимальное: ' || round(v_min_diff::NUMERIC, 1)::TEXT);
        v_report := array_append(v_report, '    максимальное: ' || round(v_max_diff::NUMERIC, 1)::TEXT);
        v_report := array_append(v_report, '    среднее: ' || round(v_avg_diff::NUMERIC, 1)::TEXT);
        v_report := array_append(v_report, '    медиана: ' || round(v_median_diff::NUMERIC, 1)::TEXT);
    ELSE
        v_report := array_append(v_report, '  Нет данных о времени от CRITICAL до инцидента (возможно, нет CRITICAL или инцидентов).');
    END IF;

    -- Тренды
    v_report := array_append(v_report, '');
    v_report := array_append(v_report, '--- ТРЕНДЫ (по дням) ---');
    v_report := array_append(v_report, '  Тренд JS-дивергенции: ' || v_trend_js);
    v_report := array_append(v_report, '  Тренд среднего риска: ' || v_trend_risk);

    -- Итоговые выводы (без рекомендаций)
    v_report := array_append(v_report, '');
    v_report := array_append(v_report, '--- ВЫВОДЫ ---');
    DECLARE
        v_conclusion TEXT := '';
    BEGIN
        IF v_incidents_total > 0 THEN
            v_conclusion := v_conclusion || '  - Зафиксировано ' || v_incidents_total || ' инцидентов. ';
        END IF;
        IF v_total_records > 0 THEN
            DECLARE
                anomaly_rate NUMERIC;
            BEGIN
                anomaly_rate := (COALESCE((v_status_counts->>'WARNING')::NUMERIC, 0) + COALESCE((v_status_counts->>'CRITICAL')::NUMERIC, 0)) / v_total_records;
                IF anomaly_rate > 0.2 THEN
                    v_conclusion := v_conclusion || 'Высокая доля аномалий (>20%) – система часто отклоняется от эталона. ';
                ELSIF anomaly_rate > 0.1 THEN
                    v_conclusion := v_conclusion || 'Умеренная доля аномалий (10-20%) – рекомендуется мониторинг. ';
                ELSE
                    v_conclusion := v_conclusion || 'Низкая доля аномалий (<10%) – профили стабильны. ';
                END IF;
            END;
        END IF;
        IF v_known_outcomes > 0 AND v_accuracy IS NOT NULL THEN
            IF v_accuracy > 0.7 THEN
                v_conclusion := v_conclusion || 'Точность прогнозов высокая (>0.7). ';
            ELSIF v_accuracy > 0.5 THEN
                v_conclusion := v_conclusion || 'Точность прогнозов умеренная (0.5-0.7). ';
            ELSE
                v_conclusion := v_conclusion || 'Точность прогнозов низкая (<0.5) – требуется пересмотр модели. ';
            END IF;
        END IF;
        IF v_median_diff IS NOT NULL THEN
            v_conclusion := v_conclusion || 'Медианное время от CRITICAL до инцидента: ' || round(v_median_diff::NUMERIC, 1) || ' мин. ';
        END IF;
        IF v_conclusion = '' THEN
            v_conclusion := '  Все показатели в норме. Продолжайте мониторинг.';
        END IF;
        v_report := array_append(v_report, v_conclusion);
    END;

    v_report := array_append(v_report, '');
    v_report := array_append(v_report, '=== КОНЕЦ ОТЧЁТА ===');

    RETURN v_report;
END;
$$;

COMMENT ON FUNCTION generate_analytical_report(TEXT, TEXT) IS
'Формирует аналитический отчёт по заданному периоду, исключая статус INCIDENT.
Включает качество прогнозов, доли статусов перед инцидентами, время от CRITICAL до инцидента, тренды и выводы.';
