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

-- -----------------------------------------------------------------------------
-- build_baseline_profile
-- Назначение: строит эталонный профиль на основе исторических данных за период,
--             исключая инцидентные окна.
-- Параметры:
--   p_start          TIMESTAMPTZ – начало периода
--   p_end            TIMESTAMPTZ – конец периода
--   p_baseline_name  TEXT        – имя эталона
--   p_exclude_incident_window_min INT – длительность окна вокруг инцидента (мин)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION build_baseline_profile(
    p_start          TIMESTAMPTZ,
    p_end            TIMESTAMPTZ,
    p_baseline_name  TEXT,
    p_exclude_incident_window_min INT DEFAULT 60
)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    v_exclude_interval INTERVAL := (p_exclude_incident_window_min || ' minutes')::INTERVAL;
    v_metrics RECORD;
    v_hour INT;
    v_dow INT;
    v_total_samples INT := 0;
BEGIN
    DELETE FROM profile_baseline WHERE baseline_name = p_baseline_name;

    FOR v_hour IN 0..23 LOOP
        FOR v_dow IN 0..6 LOOP
            WITH candidate_times AS (
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
            metrics AS (
                SELECT
                    AVG(ph.correlation) AS avg_corr,
                    STDDEV(ph.correlation) AS std_corr,
                    AVG(ph.os_angle) AS avg_os,
                    STDDEV(ph.os_angle) AS std_os,
                    AVG(ph.wait_angle) AS avg_wait,
                    STDDEV(ph.wait_angle) AS std_wait,
                    COUNT(*) AS sample_count
                FROM performance_history ph
                WHERE EXISTS (
                    SELECT 1 FROM candidate_times ct
                    WHERE ph.ts >= ct.hour_ts
                      AND ph.ts < ct.hour_ts + INTERVAL '1 hour'
                )
            ),
            trans_hourly AS (
                SELECT
                    hour_ts,
                    AVG(CASE WHEN from_state = to_state THEN 1.0 ELSE 0.0 END) AS avg_self_loop,
                    AVG(CASE WHEN to_state = ANY(SELECT state_id FROM critical_states) THEN 1.0 ELSE 0.0 END) AS avg_crit,
                    (-SUM(CASE WHEN cnt > 0 THEN cnt * LOG(2, cnt) ELSE 0 END) / NULLIF(SUM(cnt), 0)) AS entropy
                FROM (
                    SELECT
                        date_trunc('hour', tl.ts) AS hour_ts,
                        tl.from_state,
                        tl.to_state,
                        COUNT(*) AS cnt
                    FROM transition_log tl
                    WHERE tl.ts >= p_start AND tl.ts < p_end
                      AND EXTRACT(HOUR FROM tl.ts) = v_hour
                      AND EXTRACT(DOW FROM tl.ts) = v_dow
                      AND NOT EXISTS (
                          SELECT 1
                          FROM performance_incident pi
                          WHERE pi.start_timepoint BETWEEN
                                tl.ts - v_exclude_interval AND tl.ts + v_exclude_interval
                      )
                    GROUP BY date_trunc('hour', tl.ts), tl.from_state, tl.to_state
                ) state_counts
                GROUP BY hour_ts
            ),
            trans_metrics AS (
                SELECT
                    AVG(avg_self_loop) AS avg_self_loop_mean,
                    STDDEV(avg_self_loop) AS avg_self_loop_std,
                    AVG(avg_crit) AS avg_crit_mean,
                    STDDEV(avg_crit) AS avg_crit_std,
                    AVG(entropy) AS entropy_mean,
                    STDDEV(entropy) AS entropy_std,
                    COUNT(*) AS hourly_count
                FROM trans_hourly
            )
            -- Исправленный SELECT:
            SELECT
                m.avg_corr AS avg_correlation_mean,
                m.std_corr AS avg_correlation_std,
                tm.entropy_mean,
                tm.entropy_std,
                tm.avg_crit_mean AS critical_ratio_mean,
                tm.avg_crit_std AS critical_ratio_std,
                m.avg_os AS avg_os_angle_mean,
                m.std_os AS avg_os_angle_std,
                m.avg_wait AS avg_wait_angle_mean,
                m.std_wait AS avg_wait_angle_std,
                tm.avg_self_loop_mean AS self_loop_ratio_mean,
                tm.avg_self_loop_std AS self_loop_ratio_std,
                COALESCE(tm.hourly_count, 0) AS sample_size
            INTO v_metrics
            FROM metrics m
            CROSS JOIN trans_metrics tm;

            IF v_metrics.sample_size > 0 THEN
                INSERT INTO profile_baseline (
                    baseline_name, hour, dow,
                    period_start, period_end,
                    avg_correlation_mean, avg_correlation_std,
                    entropy_mean, entropy_std,
                    critical_ratio_mean, critical_ratio_std,
                    avg_os_angle_mean, avg_os_angle_std,
                    avg_wait_angle_mean, avg_wait_angle_std,
                    self_loop_ratio_mean, self_loop_ratio_std,
                    state_histogram_mean, state_histogram_std,
                    unique_states_count_mean, unique_states_count_std,
                    avg_transition_length_mean, avg_transition_length_std,
                    top_transition_freq_mean, top_transition_freq_std,
                    top_transition_pair
                ) VALUES (
                    p_baseline_name, v_hour, v_dow,
                    p_start, p_end,
                    v_metrics.avg_correlation_mean, v_metrics.avg_correlation_std,
                    v_metrics.entropy_mean, v_metrics.entropy_std,
                    v_metrics.critical_ratio_mean, v_metrics.critical_ratio_std,
                    v_metrics.avg_os_angle_mean, v_metrics.avg_os_angle_std,
                    v_metrics.avg_wait_angle_mean, v_metrics.avg_wait_angle_std,
                    v_metrics.self_loop_ratio_mean, v_metrics.self_loop_ratio_std,
                    '{}'::JSONB, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL
                );
                v_total_samples := v_total_samples + 1;
            END IF;
        END LOOP;
    END LOOP;

    RETURN format('Baseline "%s" built with %s hour/day slots filled.', p_baseline_name, v_total_samples);
END;
$$;

COMMENT ON FUNCTION build_baseline_profile(TIMESTAMPTZ, TIMESTAMPTZ, TEXT, INT) IS
'Строит эталонный профиль на основе исторических данных за период, исключая окна вокруг инцидентов. Сохраняет в profile_baseline с усреднением по часу дня и дню недели.';


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