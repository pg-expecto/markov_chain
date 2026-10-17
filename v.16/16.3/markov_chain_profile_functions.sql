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
-- version 16.3
--------------------------------------------------------------------------------
-- Функции для расчета метрик профиля нагрузки на основе цепи Маркова 
--------------------------------------------------------------------------------
--
-- calculate_profile_metrics
-- Назначение: вычисляет набор профильных метрик для заданного временного окна.
--
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
-- Функция: collect_pre_incident_profiles
-- Назначение: сбор профилей для инцидентов
--
-- Функция: compare_with_pre_incident_profiles
-- Назначение: Функция сравнения текущего профиля с библиотекой
--
-- Функция: find_matching_pre_incident_profile
-- Назначение: Функция поиска совпадающего пред-инцидентного профиля
--
-- Функция: generate_pre_incident_audit_report
-- Назначение: Формирует отчёт о совпадениях текущих профилей с пред-инцидентными шаблонами за указанный период. Возвращает массив строк с деталями каждого совпадения.
--
-- Функция: calculate_signal 
-- Назначение: вычисляет сигнал и статистику для заданного времени
--
-- Функция: generate_incident_forecast_report
-- Назначение: формирует отчёт по прогнозированию инцидентов за заданный период.
--
-- Функция: update_profile_change_indicator
-- Назначение: ежеминутное обновление индикатора.вычисляет текущий сигнал и, если он изменился по сравнению с последним сохранённым, добавляет новую запись в profile_change_indicator.
--
-- Функция: historical_fill_profile_change_indicator
-- Назначение: для исторического заполнения индикатора
--
-- Функция: clean_old_profile_change_indicator
-- Назначение: очистки старых записей из таблицы profile_change_indicator
--
-- Функция: compare_with_fixed_baseline
-- Назначение: Функция сравнения с фиксированным эталоном 
-- 
-- historical_fill_profile_comparison
-- Процедура массового заполнения-
--
-- Функция: compare_profiles_at
-- Назначение: выполняет сравнение эталонного и текущего профилей для заданного
--             момента времени (исторического). Логика полностью соответствует
--             compare_profiles, но вместо now() используется переданное время.
--
-- Функция: fill_profile_comparison_historically
-- Назначение: заполняет таблицу profile_comparison_log за исторический период,
--             используя compare_profiles_at для каждой минуты.
--
-- Функция: generate_profile_comparison_report
-- Назначение: формирует аналитический отчёт по таблице profile_comparison_log
--             за указанный период (по умолчанию – последний месяц).
--
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

-- =============================================================================
-- 2.2. Функции для работы с эталоном
-- =============================================================================


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
    p_exclude_before_min  INT DEFAULT 30,
    p_exclude_after_min   INT DEFAULT 60
)
RETURNS TEXT
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
    v_now          TIMESTAMPTZ := now();
    v_interval     INTERVAL := (p_window_minutes || ' minutes')::INTERVAL;
    v_last_finish  TIMESTAMPTZ;
    v_start_ts     TIMESTAMPTZ;
    v_end_ts       TIMESTAMPTZ;
    v_existing     RECORD;
BEGIN
    -- Проверяем, есть ли уже сохранённое окно
    SELECT window_start, window_end INTO v_existing
    FROM incident_free_window_current
    LIMIT 1;

    -- Получаем время окончания последнего завершённого инцидента
    SELECT MAX(finish_timepoint)
    INTO v_last_finish
    FROM performance_incident
    WHERE finish_timepoint IS NOT NULL;

    -- Если есть существующее окно и оно всё ещё актуально
    IF FOUND AND v_existing.window_start IS NOT NULL THEN
        -- Окно актуально, если:
        -- 1) Его конец < now() (оно в прошлом)
        -- 2) После его окончания не было новых завершённых инцидентов
        -- 3) Оно не пересекается с инцидентами (это уже гарантировано)
        IF v_existing.window_end < v_now AND
           (v_last_finish IS NULL OR v_last_finish <= v_existing.window_start) THEN
            RETURN format('Окно уже существует и актуально: %s – %s',
                          v_existing.window_start, v_existing.window_end);
        END IF;
    END IF;

    -- Если окна нет или оно устарело – ищем новое
    IF v_last_finish IS NULL
       OR v_last_finish + INTERVAL '1 hour' > v_now
       OR v_last_finish + v_interval > v_now
    THEN
        DELETE FROM incident_free_window_current;
        RETURN 'Окно не найдено: последний завершённый инцидент не удовлетворяет условиям доступности.';
    END IF;

    -- Строим окно сразу после последнего завершённого инцидента
    v_start_ts := v_last_finish;
    v_end_ts   := v_last_finish + v_interval;

    -- Проверяем, что окно не пересекается с другими инцидентами (доп. проверка)
    IF EXISTS (
        SELECT 1 FROM performance_incident
        WHERE start_timepoint < v_end_ts
          AND (finish_timepoint IS NULL OR finish_timepoint > v_start_ts)
    ) THEN
        DELETE FROM incident_free_window_current;
        RETURN 'Ошибка: найденное окно пересекается с инцидентом.';
    END IF;

    -- Сохраняем новое окно
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
    -- Получаем текущее безынцидентное окно
    SELECT window_start, window_end INTO v_win_start, v_win_end
    FROM incident_free_window_current
    LIMIT 1;

    IF v_win_start IS NULL OR v_win_end IS NULL THEN
        RETURN 'Ошибка: таблица incident_free_window_current пуста. Сначала выполните find_incident_free_window().';
    END IF;

    -- Проверяем, существует ли уже эталонный профиль с таким же окном
    SELECT window_start, window_end INTO v_last_baseline
    FROM profile_aggregated
    WHERE profile_type = 'baseline'
    ORDER BY ts DESC
    LIMIT 1;

    IF FOUND AND v_last_baseline.window_start = v_win_start AND v_last_baseline.window_end = v_win_end THEN
        RETURN format('Эталонный профиль уже сохранён для окна %s – %s, пропуск.',
                      v_win_start, v_win_end);
    END IF;

    -- Удаляем старый эталонный профиль (если есть)
    DELETE FROM profile_aggregated WHERE profile_type = 'baseline';

    -- Вычисляем метрики для нового окна
    SELECT * INTO v_metrics
    FROM calculate_profile_metrics(v_win_start, v_win_end);

    v_hour := EXTRACT(HOUR FROM now())::SMALLINT;
    v_dow  := EXTRACT(DOW FROM now())::SMALLINT;

    -- Вставляем новый эталонный профиль
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
-- compare_profiles 
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
    p_exclude_before_min  INT DEFAULT 30,
    p_exclude_after_min   INT DEFAULT 60
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
    v_pre_alert     INTEGER;
    v_js_threshold  REAL;
    v_matched_id    BIGINT;
    v_baseline_found BOOLEAN := FALSE;
BEGIN
    -- 1. Проверяем, находится ли текущий момент внутри активного инцидента
    SELECT EXISTS (
        SELECT 1
        FROM performance_incident
        WHERE start_timepoint <= v_now
          AND (finish_timepoint IS NULL OR finish_timepoint >= v_now)
    ) INTO v_inside_incident;

    -- 2. Вычисляем максимальный предсказанный риск за текущее окно
    SELECT MAX(predicted_risk) INTO v_max_pred_risk
    FROM prediction_log
    WHERE prediction_time BETWEEN v_current_start AND v_current_end;

    -- 3. Если внутри инцидента – записываем INCIDENT и выходим
    IF v_inside_incident THEN
        v_status := 'INCIDENT';
        v_report := array_append(v_report, '=== СРАВНЕНИЕ ПРОФИЛЕЙ ===');
        v_report := array_append(v_report, format('Текущий момент: %s', v_now));
        v_report := array_append(v_report, 'Статус: INCIDENT – система находится внутри инцидента, эталонное окно недоступно.');
        v_report := array_append(v_report, '=== КОНЕЦ ОТЧЁТА ===');

        v_pre_alert := 0;
        v_matched_id := NULL;

        INSERT INTO profile_comparison_log (
            current_window_start,
            current_window_end,
            status,
            js_divergence,
            report,
            details,
            max_predicted_risk,
            pre_alert_flag,
            matched_pre_incident_id
        ) VALUES (
            v_current_start,
            v_current_end,
            v_status,
            NULL,
            to_jsonb(v_report),
            jsonb_build_object('reason', 'inside_incident'),
            v_max_pred_risk,
            v_pre_alert,
            v_matched_id
        );
        RETURN v_report;
    END IF;

    -- 4. Пытаемся получить эталонное окно из таблицы incident_free_window_current
    SELECT window_start, window_end INTO v_baseline_start, v_baseline_end
    FROM incident_free_window_current
    LIMIT 1;

    -- Если в incident_free_window_current нет записи, пробуем взять baseline из profile_aggregated
    IF v_baseline_start IS NULL THEN
        SELECT window_start, window_end INTO v_baseline_start, v_baseline_end
        FROM profile_aggregated
        WHERE profile_type = 'baseline'
        ORDER BY ts DESC
        LIMIT 1;
    END IF;

    -- Проверяем, что эталонное окно существует и его конец меньше начала текущего окна
    IF v_baseline_start IS NOT NULL AND v_baseline_end < v_current_start THEN
        v_baseline_found := TRUE;
    ELSE
        v_baseline_found := FALSE;
    END IF;

    IF NOT v_baseline_found THEN
        v_status := 'NO_BASELINE';
        v_report := array_append(v_report, '=== СРАВНЕНИЕ ПРОФИЛЕЙ ===');
        v_report := array_append(v_report, format('Текущий момент: %s', v_now));
        v_report := array_append(v_report, 'Статус: NO_BASELINE – отсутствует актуальный эталонный профиль (окно не найдено или его конец не раньше текущего окна).');
        v_report := array_append(v_report, '=== КОНЕЦ ОТЧЁТА ===');

        v_pre_alert := 0;
        v_matched_id := NULL;

        INSERT INTO profile_comparison_log (
            current_window_start,
            current_window_end,
            status,
            js_divergence,
            report,
            details,
            max_predicted_risk,
            pre_alert_flag,
            matched_pre_incident_id
        ) VALUES (
            v_current_start,
            v_current_end,
            v_status,
            NULL,
            to_jsonb(v_report),
            jsonb_build_object('reason', 'no_baseline'),
            v_max_pred_risk,
            v_pre_alert,
            v_matched_id
        );
        RETURN v_report;
    END IF;

    -- 5. Вычисляем метрики для эталонного и текущего окон
    SELECT * INTO v_baseline_metrics
    FROM calculate_profile_metrics(v_baseline_start, v_baseline_end);

    SELECT * INTO v_current_metrics
    FROM calculate_profile_metrics(v_current_start, v_current_end);

    -- 6. Вычисляем JS-дивергенцию
    v_js := histogram_divergence(
        v_baseline_metrics.state_histogram,
        v_current_metrics.state_histogram
    );

    -- 7. Определяем статус
    v_status := 'NORMAL';
    IF v_js >= 0.05 THEN
        v_status := 'WARNING';
    END IF;
    IF v_js >= 0.2 OR ABS(COALESCE(v_current_metrics.avg_correlation, 0) - COALESCE(v_baseline_metrics.avg_correlation, 0)) > 0.2 THEN
        v_status := 'CRITICAL';
    END IF;

    -- 8. Вычисляем флаг предаварийного состояния
    SELECT COALESCE( (SELECT js_divergence_threshold FROM markov_config ), 0.2 ) INTO v_js_threshold;

    IF v_js IS NOT NULL AND v_js >= v_js_threshold AND v_max_pred_risk IS NOT NULL AND v_max_pred_risk = 1 THEN
        v_pre_alert := 100;
    ELSE
        v_pre_alert := 0;
    END IF;

    -- 9. Поиск совпадающего пред-инцидентного профиля
    v_matched_id := find_matching_pre_incident_profile(
        v_current_metrics.state_histogram,
        0.05,
        100
    );

    -- 10. Формируем отчёт (без изменений, кроме источника эталона)
    -- ... (оставляем существующий код формирования v_report)

    -- 11. Сохраняем результат в profile_comparison_log
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
        'baseline_source', 'incident_free_window_current' -- для отладки
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
        matched_pre_incident_id
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
        v_matched_id
    );

    RETURN v_report;
END;
$$;

COMMENT ON FUNCTION compare_profiles(INT, INT, INT) IS 'Сравнивает текущий профиль нагрузки с эталонным, сохраняет результат в profile_comparison_log, включая максимальный предсказанный риск, флаг предаварийного состояния и идентификатор совпадающего пред-инцидентного профиля.';


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
    p_lookback_days     INT DEFAULT 7,
    p_exclude_before_min INT DEFAULT 0,   -- не используется, оставлен для совместимости
    p_exclude_after_min  INT DEFAULT 0    -- минимальный отступ (в минутах) от p_ts для окончания окна
)
RETURNS TABLE (start_ts TIMESTAMPTZ, end_ts TIMESTAMPTZ)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_interval INTERVAL := (p_window_minutes || ' minutes')::INTERVAL;
    v_exclude_after INTERVAL := (p_exclude_after_min || ' minutes')::INTERVAL;
    v_candidate_start TIMESTAMPTZ;
    v_candidate_end   TIMESTAMPTZ;
    v_has_incident BOOLEAN;
    v_lookback_start TIMESTAMPTZ := p_ts - (p_lookback_days || ' days')::INTERVAL;
BEGIN
    -- Начинаем поиск с окна, которое заканчивается на v_exclude_after раньше p_ts
    v_candidate_start := p_ts - v_interval - v_exclude_after;
    WHILE v_candidate_start >= v_lookback_start LOOP
        v_candidate_end := v_candidate_start + v_interval;
        -- Проверяем, есть ли инцидент, пересекающий это окно
        SELECT EXISTS (
            SELECT 1
            FROM performance_incident
            WHERE start_timepoint < v_candidate_end
              AND (finish_timepoint IS NULL OR finish_timepoint > v_candidate_start)
        ) INTO v_has_incident;
        
        IF NOT v_has_incident THEN
            -- Окно свободно и удовлетворяет отступу
            RETURN QUERY SELECT v_candidate_start, v_candidate_end;
            RETURN;
        END IF;
        
        v_candidate_start := v_candidate_start - INTERVAL '1 minute';
    END LOOP;
    
    -- Если ничего не найдено, возвращаем пустой результат
    RETURN;
END;
$$;

COMMENT ON FUNCTION get_incident_free_window_before IS 'Возвращает эталонное окно [finish ; finish + window_minutes] для самого позднего завершённого инцидента,
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

-----------------------------------------------------------------
-- version 15
/* Функция сбора профилей для инцидентов' */
CREATE OR REPLACE FUNCTION collect_pre_incident_profiles(
    p_start             TIMESTAMPTZ,
    p_end               TIMESTAMPTZ,
    p_window_minutes    INT DEFAULT 60
)
RETURNS TEXT
LANGUAGE plpgsql AS $$
DECLARE
    inc RECORD;
    prof RECORD;
    cnt INT := 0;
BEGIN
    FOR inc IN
        SELECT id, start_timepoint
        FROM performance_incident
        WHERE start_timepoint BETWEEN p_start AND p_end
          AND start_timepoint - (p_window_minutes || ' minutes')::INTERVAL >= p_start
    LOOP
        -- Пропускаем, если профиль для этого инцидента уже существует
        IF NOT EXISTS (SELECT 1 FROM pre_incident_profiles WHERE incident_id = inc.id) THEN
            SELECT * INTO prof
            FROM calculate_profile_metrics(
                inc.start_timepoint - (p_window_minutes || ' minutes')::INTERVAL,
                inc.start_timepoint
            );
            INSERT INTO pre_incident_profiles (
                incident_id, window_start, window_end,
                state_histogram, avg_correlation, critical_ratio, entropy,
                avg_os_angle, avg_wait_angle, unique_states_count,
                avg_transition_length, self_loop_ratio, top_transition
            ) VALUES (
                inc.id,
                inc.start_timepoint - (p_window_minutes || ' minutes')::INTERVAL,
                inc.start_timepoint,
                prof.state_histogram, prof.avg_correlation, prof.critical_ratio,
                prof.entropy, prof.avg_os_angle, prof.avg_wait_angle,
                prof.unique_states_count, prof.avg_transition_length,
                prof.self_loop_ratio, prof.top_transition
            );
            cnt := cnt + 1;
        END IF;
    END LOOP;
    RETURN format('Added %s pre-incident profiles.', cnt);
END;
$$;
COMMENT ON FUNCTION collect_pre_incident_profiles IS 'Функция сбора профилей для инцидентов';

/*Функция сравнения текущего профиля с библиотекой*/
CREATE OR REPLACE FUNCTION compare_with_pre_incident_profiles(
    p_threshold     REAL DEFAULT 0.05,
    p_max_profiles  INT  DEFAULT 50,
    p_log_matches   BOOLEAN DEFAULT TRUE
)
RETURNS TABLE (
    matched_id     BIGINT,
    divergence     REAL,
    incident_id    BIGINT,
    incident_time  TIMESTAMPTZ
)
LANGUAGE plpgsql
AS $$
DECLARE
    current_prof RECORD;
    v_start      TIMESTAMPTZ := now() - INTERVAL '60 minutes';
    v_end        TIMESTAMPTZ := now();
    v_rec        RECORD;
BEGIN
    -- Вычисляем текущий профиль за последние 60 минут
    SELECT * INTO current_prof
    FROM calculate_profile_metrics(v_start, v_end);

    -- Проходим по всем шаблонам, у которых JS-дивергенция меньше порога
    FOR v_rec IN
        SELECT
            p.id AS matched_id,
            histogram_divergence(current_prof.state_histogram, p.state_histogram) AS div,
            p.incident_id,
            (SELECT start_timepoint FROM performance_incident WHERE id = p.incident_id) AS incident_time
        FROM pre_incident_profiles p
        WHERE histogram_divergence(current_prof.state_histogram, p.state_histogram) < p_threshold
        ORDER BY p.created_at DESC
        LIMIT p_max_profiles
    LOOP
        -- Возвращаем строку результата
        matched_id    := v_rec.matched_id;
        divergence    := v_rec.div;
        incident_id   := v_rec.incident_id;
        incident_time := v_rec.incident_time;
        RETURN NEXT;

        -- Если включено логирование, сохраняем совпадение в таблицу лога
        IF p_log_matches THEN
            INSERT INTO pre_incident_match_log (
                current_window_start,
                current_window_end,
                matched_pre_incident_id,
                divergence,
                incident_id,
                incident_time,
                threshold_used
            ) VALUES (
                v_start,
                v_end,
                v_rec.matched_id,
                v_rec.div,
                v_rec.incident_id,
                v_rec.incident_time,
                p_threshold
            );
        END IF;
    END LOOP;

    RETURN;
END;
$$;

COMMENT ON FUNCTION compare_with_pre_incident_profiles(REAL, INT, BOOLEAN) IS
'Сравнивает текущий профиль (последние 60 минут) с библиотекой пред-инцидентных профилей.
Возвращает совпадения, у которых JS-дивергенция меньше порога.
При включённом p_log_matches (по умолчанию TRUE) записывает каждое совпадение в таблицу pre_incident_match_log.';


/*Функция поиска совпадающего пред-инцидентного профиля */
CREATE OR REPLACE FUNCTION find_matching_pre_incident_profile(
    p_state_histogram   JSONB,
    p_threshold         REAL DEFAULT 0.05,
    p_max_profiles      INT DEFAULT 100
)
RETURNS BIGINT
LANGUAGE plpgsql STABLE AS $$
DECLARE
    v_id BIGINT;
BEGIN
    SELECT p.id INTO v_id
    FROM pre_incident_profiles p
    WHERE histogram_divergence(p_state_histogram, p.state_histogram) < p_threshold
    ORDER BY p.created_at DESC
    LIMIT 1;
    RETURN v_id;
END;
$$;
COMMENT ON FUNCTION find_matching_pre_incident_profile IS 'Функция сбора профилей для инцидентов';

/*
Формирует отчёт о совпадениях текущих профилей с пред-инцидентными шаблонами за указанный период. Возвращает массив строк с деталями каждого совпадения.
psql -d expecto_db -U expecto_user  -c 'SELECT unnest(generate_pre_incident_audit_report())' > /tmp/generate_pre_incident_audit_report.txt

-- Все совпадения за последние 7 дней
SELECT unnest(generate_pre_incident_audit_report());

-- Только совпадения с JS-дивергенцией <= 0.05
psql -d expecto_db -U expecto_user  -c "SELECT unnest(generate_pre_incident_audit_report(p_start => now() - interval '7 days', p_end   => now(), p_max_js_divergence => 0.05))"
*/
CREATE OR REPLACE FUNCTION generate_pre_incident_audit_report(
    p_start              TIMESTAMPTZ DEFAULT now() - INTERVAL '7 days',
    p_end                TIMESTAMPTZ DEFAULT now(),
    p_max_js_divergence  REAL        DEFAULT NULL
)
RETURNS TEXT[]
LANGUAGE plpgsql STABLE AS $$
DECLARE
    v_report TEXT[] := '{}';
    v_rec RECORD;
    v_sep CONSTANT TEXT := '--------------------------------------------------------------------';
    v_found BOOLEAN := FALSE;
    v_filter_msg TEXT;
    v_incident_count INT;
BEGIN
    -- Сообщение о фильтре
    IF p_max_js_divergence IS NOT NULL THEN
        v_filter_msg := format(' (фильтр по JS-дивергенции: <= %s)', p_max_js_divergence);
    ELSE
        v_filter_msg := ' (без фильтра по JS-дивергенции)';
    END IF;

    v_report := array_append(v_report, '=== ОТЧЁТ АУДИТА СОВПАДЕНИЙ С ПРЕД-ИНЦИДЕНТНЫМИ ПРОФИЛЯМИ ===');
    v_report := array_append(v_report, format('Период: %s – %s%s', date_trunc('minute',p_start)::TEXT, date_trunc('minute',p_end)::TEXT, v_filter_msg));

    -- Список инцидентов за период
    v_report := array_append(v_report, '');
    v_report := array_append(v_report, '--- ИНЦИДЕНТЫ ПРОИЗВОДИТЕЛЬНОСТИ ЗА ПЕРИОД ---');
    SELECT COUNT(*) INTO v_incident_count
    FROM performance_incident
    WHERE start_timepoint BETWEEN p_start AND p_end;
    
    IF v_incident_count > 0 THEN
        v_report := array_append(v_report, format('Всего инцидентов: %s', v_incident_count));
        FOR v_rec IN
            SELECT id, start_timepoint, priority
            FROM performance_incident
            WHERE start_timepoint BETWEEN p_start AND p_end
            ORDER BY start_timepoint
        LOOP
            v_report := array_append(v_report, format('  #%s: %s (приоритет %s)',
                v_rec.id,
                to_char(v_rec.start_timepoint, 'YYYY-MM-DD HH24:MI'),
                COALESCE(v_rec.priority::TEXT, 'N/A')));
        END LOOP;
    ELSE
        v_report := array_append(v_report, '  Инцидентов за период не найдено.');
    END IF;
    v_report := array_append(v_report, '');

    -- Расшифровка полей (без статуса, приоритета и длительности)
    v_report := array_append(v_report, 'Расшифровка полей отчёта:');
    v_report := array_append(v_report, '  - Совпадение текущего и прединцидентного профиля: момент времени, когда был вычислен текущий профиль и выполнено сравнение.');
    v_report := array_append(v_report, '  - JS-дивергенция: численное значение расхождения между текущей гистограммой состояний и гистограммой шаблона (0 – идентичны).');
    v_report := array_append(v_report, '  - Совпавший профиль ID: идентификатор записи в pre_incident_profiles, с которой зафиксировано совпадение.');
    v_report := array_append(v_report, '  - Оригинальный инцидент ID: идентификатор инцидента из performance_incident, к которому относится шаблон.');
    v_report := array_append(v_report, '  - Время оригинального инцидента: время начала этого инцидента.');
    v_report := array_append(v_report, '');

    -- Основной запрос без статуса, приоритета и длительности
    FOR v_rec IN
        SELECT
            pcl.created_at,
            pcl.js_divergence,
            pcl.matched_pre_incident_id,
            pip.incident_id AS original_incident_id,
            pi.start_timepoint AS original_incident_time
        FROM profile_comparison_log pcl
        LEFT JOIN pre_incident_profiles pip ON pcl.matched_pre_incident_id = pip.id
        LEFT JOIN performance_incident pi ON pip.incident_id = pi.id
        WHERE pcl.created_at BETWEEN p_start AND p_end
          AND pcl.matched_pre_incident_id IS NOT NULL
          AND (p_max_js_divergence IS NULL 
               OR (pcl.js_divergence IS NOT NULL AND pcl.js_divergence <= p_max_js_divergence))
        ORDER BY pcl.created_at DESC
    LOOP
        v_found := TRUE;
        v_report := array_append(v_report, format('Совпадение текущего и прединцидентного профиля: %s', date_trunc('minute', v_rec.created_at)));
        v_report := array_append(v_report, format('  JS-дивергенция: %s', COALESCE(round(v_rec.js_divergence::NUMERIC, 4)::TEXT, 'NULL')));
        v_report := array_append(v_report, format('  Совпавший профиль ID: %s', v_rec.matched_pre_incident_id));
        v_report := array_append(v_report, format('  Оригинальный инцидент ID: %s', COALESCE(v_rec.original_incident_id::TEXT, 'неизвестен')));
        IF v_rec.original_incident_time IS NOT NULL THEN
            v_report := array_append(v_report, format('  Время оригинального инцидента: %s', v_rec.original_incident_time));
        ELSE
            v_report := array_append(v_report, '  Оригинальный инцидент не найден (возможно, удалён)');
        END IF;
        v_report := array_append(v_report, v_sep);
    END LOOP;

    IF NOT v_found THEN
        v_report := array_append(v_report, 'Совпадений с пред-инцидентными профилями, удовлетворяющих условиям фильтра, за указанный период не обнаружено.');
    END IF;

    v_report := array_append(v_report, '=== КОНЕЦ ОТЧЁТА ===');
    RETURN v_report;
END;
$$;

COMMENT ON FUNCTION generate_pre_incident_audit_report(TIMESTAMPTZ, TIMESTAMPTZ, REAL) IS
'Формирует отчёт о совпадениях текущих профилей с пред-инцидентными шаблонами за указанный период. 
В заголовок добавлен список инцидентов производительности (ID, время начала, приоритет) за этот период.
Параметр p_max_js_divergence позволяет отфильтровать записи по значению JS-дивергенции (выбираются только те, где js_divergence <= заданного порога). 
Если параметр не указан (NULL), фильтрация не применяется. 
В отчёт не включаются статус сравнения, приоритет и длительность инцидента – только факт совпадения, значение JS-дивергенции, идентификаторы и время оригинального инцидента.';

--------------------------------------------------------------------------------
-- Функция: generate_incident_forecast_report
-- Назначение: формирует отчёт по прогнозированию инцидентов за заданный период.
--------------------------------------------------------------------------------
-- Пример использования:
/*
-- Изменить режим сигнала на OR
UPDATE incident_forecast_config SET signal_mode = 'OR'

-- Отчёт за последние 7 дней
SELECT unnest(generate_incident_forecast_report());

-- Отчёт за конкретный период
SELECT unnest(generate_incident_forecast_report(
    '2026-08-07 00:00'::TIMESTAMPTZ,
    '2026-08-14 00:00'::TIMESTAMPTZ
));

Все настройки управляются через таблицу incident_forecast_config:
-- Изменить режим сигнала на WEIGHTED
UPDATE incident_forecast_config SET signal_mode = 'WEIGHTED', weight_js = 0.4, weight_risk = 0.6;

-- Включить расширенный отчёт
UPDATE incident_forecast_config SET extended_report = TRUE;
*/
-- =============================================================================
-- Модифицированная функция generate_incident_forecast_report
-- =============================================================================
CREATE OR REPLACE FUNCTION generate_incident_forecast_report(
    p_start TIMESTAMPTZ DEFAULT now() - INTERVAL '7 days',
    p_end   TIMESTAMPTZ DEFAULT now()
) RETURNS TEXT[]
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    cfg RECORD;
    v_window_minutes                INT;
    v_js_threshold                  REAL;
    v_risk_threshold                REAL;
    v_include_summary               BOOLEAN;
    v_signal_mode                   TEXT;
    v_min_signal_duration           INT;
    v_use_priority_thresholds       BOOLEAN;
    v_weight_js                     REAL;
    v_weight_risk                   REAL;
    v_auto_threshold                BOOLEAN;
    v_calibration_period_days       INT;
    v_max_js_age_min                INT;
    v_min_data_points               INT;
    v_slope_window_minutes          INT;
    v_extended_report               BOOLEAN;
    v_optimize_thresholds           BOOLEAN;
    v_priority_filter               INT[];
    v_status_filter                 TEXT[];
    v_csv_mode                      BOOLEAN;
    v_include_pre_incident_matches  BOOLEAN;

    v_report TEXT[] := '{}';
    v_header TEXT := '=== ОТЧЁТ ПО ПРОГНОЗИРОВАНИЮ ИНЦИДЕНТОВ ===';
    v_incident RECORD;
    v_signal RECORD;
    v_last_status TEXT;
    v_trend TEXT;
    v_line TEXT;
    v_js_str TEXT;
    v_risk_str TEXT;
    v_marker TEXT;
    v_sep TEXT;
    v_header_line TEXT;
    v_total_incidents INT := 0;
    v_excluded_incidents INT := 0;
    v_incidents_with_signal INT := 0;
    v_avg_minutes_to_incident REAL := 0;
    v_avg_js_avg REAL := 0;
    v_avg_risk_avg REAL := 0;
    v_status_counts JSONB;
    v_pct_text TEXT;
    v_match_pct TEXT;
    v_roc_auc REAL;
    v_brier REAL;
    v_calibration JSONB;
    v_rec RECORD;
    v_legend TEXT;
    v_included_ids BIGINT[] := '{}';
    v_hour_dist JSONB;
    v_dow_dist JSONB;
    v_hour_graph TEXT;
    v_dow_graph TEXT;
BEGIN
    -- ========================================================================
    -- 1. Чтение конфигурации
    -- ========================================================================
    SELECT * INTO cfg FROM incident_forecast_config LIMIT 1;
    IF NOT FOUND THEN
        INSERT INTO incident_forecast_config DEFAULT VALUES;
        SELECT * INTO cfg FROM incident_forecast_config LIMIT 1;
    END IF;

    v_window_minutes                := cfg.window_minutes;
    v_js_threshold                  := cfg.js_threshold;
    v_risk_threshold                := cfg.risk_threshold;
    v_include_summary               := cfg.include_summary;
    v_signal_mode                   := cfg.signal_mode;
    v_min_signal_duration           := cfg.min_signal_duration;
    v_use_priority_thresholds       := cfg.use_priority_thresholds;
    v_weight_js                     := cfg.weight_js;
    v_weight_risk                   := cfg.weight_risk;
    v_auto_threshold                := cfg.auto_threshold;
    v_calibration_period_days       := cfg.calibration_period_days;
    v_max_js_age_min                := cfg.max_js_age_min;
    v_min_data_points               := cfg.min_data_points;
    v_slope_window_minutes          := cfg.slope_window_minutes;
    v_extended_report               := cfg.extended_report;
    v_optimize_thresholds           := cfg.optimize_thresholds;
    v_priority_filter               := cfg.priority_filter;
    v_status_filter                 := cfg.status_filter;
    v_csv_mode                      := cfg.csv_mode;
    v_include_pre_incident_matches  := cfg.include_pre_incident_matches;

    -- ========================================================================
    -- 2. Обработка режима оптимизации порогов (заглушка)
    -- ========================================================================
    IF v_optimize_thresholds THEN
        RAISE NOTICE 'Оптимизация порогов временно не реализована, используется автонастройка.';
        v_auto_threshold := TRUE;
    END IF;

    -- ========================================================================
    -- 3. Автоматическая настройка порогов (если включена)
    -- ========================================================================
    IF v_auto_threshold THEN
        WITH calibration_data AS (
            SELECT
                pcl.js_divergence,
                pl.predicted_risk
            FROM profile_comparison_log pcl
            JOIN prediction_log pl
                ON date_trunc('minute', pl.prediction_time) = date_trunc('minute', pcl.current_window_end)
            WHERE pcl.current_window_end >= p_start - (v_calibration_period_days || ' days')::INTERVAL
              AND pcl.current_window_end < p_start
              AND pcl.js_divergence IS NOT NULL
              AND pl.predicted_risk IS NOT NULL
        ),
        percentiles AS (
            SELECT
                PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY js_divergence) AS js_p75,
                PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY predicted_risk) AS risk_p75
            FROM calibration_data
        )
        SELECT js_p75, risk_p75 INTO v_js_threshold, v_risk_threshold
        FROM percentiles;

        IF v_js_threshold IS NULL OR v_risk_threshold IS NULL THEN
            v_js_threshold := cfg.js_threshold;
            v_risk_threshold := cfg.risk_threshold;
            RAISE NOTICE 'Автонастройка порогов невозможна (недостаточно данных), используются значения по умолчанию.';
        END IF;
    END IF;

    -- ========================================================================
    -- 4. Формирование заголовка и легенды
    -- ========================================================================
    IF v_csv_mode THEN
        v_sep := ';';
    END IF;

    IF NOT v_csv_mode THEN
        v_report := array_append(v_report, v_header);
        v_report := array_append(v_report, format('Период: %s – %s', to_char(p_start, 'YYYY-MM-DD HH24:MI'), to_char(p_end, 'YYYY-MM-DD HH24:MI')));
        v_report := array_append(v_report, 'Параметры конфигурации:');
        v_report := array_append(v_report, format('  Окно: %s мин', v_window_minutes));
        v_report := array_append(v_report, format('  JS-порог: %s', v_js_threshold));
        v_report := array_append(v_report, format('  Порог риска: %s', v_risk_threshold));
        v_report := array_append(v_report, format('  Режим сигнала: %s', v_signal_mode));
        v_report := array_append(v_report, format('  Мин. длительность сигнала: %s мин', v_min_signal_duration));
        v_report := array_append(v_report, format('  Вес JS: %s', v_weight_js));
        v_report := array_append(v_report, format('  Вес риска: %s', v_weight_risk));
        v_report := array_append(v_report, format('  Автоподбор порогов: %s', CASE WHEN v_auto_threshold THEN 'ВКЛ' ELSE 'ВЫКЛ' END));
        v_report := array_append(v_report, format('  Период калибровки: %s дней', v_calibration_period_days));
        v_report := array_append(v_report, format('  Макс. возраст JS: %s мин', v_max_js_age_min));
        v_report := array_append(v_report, format('  Мин. точек данных: %s', v_min_data_points));
        v_report := array_append(v_report, format('  Окно скорости: %s мин', v_slope_window_minutes));
        v_report := array_append(v_report, format('  Расширенный отчёт: %s', CASE WHEN v_extended_report THEN 'ДА' ELSE 'НЕТ' END));
        v_report := array_append(v_report, format('  Оптимизация порогов: %s', CASE WHEN v_optimize_thresholds THEN 'ВКЛ' ELSE 'ВЫКЛ' END));
        v_report := array_append(v_report, format('  Фильтр приоритетов: %s', COALESCE(array_to_string(v_priority_filter, ','), 'НЕТ')));
        v_report := array_append(v_report, format('  Фильтр статусов: %s', COALESCE(array_to_string(v_status_filter, ','), 'НЕТ')));
        v_report := array_append(v_report, format('  Режим CSV: %s', CASE WHEN v_csv_mode THEN 'ДА' ELSE 'НЕТ' END));
        v_report := array_append(v_report, format('  Включать совпадения с прединцидентными профилями: %s', CASE WHEN v_include_pre_incident_matches THEN 'ДА' ELSE 'НЕТ' END));
        v_report := array_append(v_report, format('Дата формирования: %s', to_char(now(), 'YYYY-MM-DD HH24:MI')));
        v_report := array_append(v_report, '');

        v_legend := 'Расшифровка столбцов:';
        v_legend := v_legend || E'\n- ID – идентификатор инцидента.';
        v_legend := v_legend || E'\n- Время – время начала инцидента.';
        v_legend := v_legend || E'\n- Приор – приоритет инцидента (3 – критический, 4 – высокий).';
        v_legend := v_legend || E'\n- JS(avg [min-max], cnt) – средняя JS-дивергенция за час до инцидента, минимум и максимум, количество точек.';
        v_legend := v_legend || E'\n- Риск(avg [min-max], cnt) – средний предсказанный риск за час, минимум, максимум, количество точек.';
        v_legend := v_legend || E'\n- Тренд – направление изменения риска за час (РОСТ/СНИЖЕНИЕ/СТАБИЛЬНО).';
        v_legend := v_legend || E'\n- Посл.статус – последний статус сравнения профилей перед инцидентом (CRITICAL/WARNING/NORMAL/INCIDENT).';
        v_legend := v_legend || E'\n- Сигнал – сработал ли сигнал (ДА/НЕТ) при заданных порогах.';
        v_legend := v_legend || E'\n- Мин до сигн. – время от первого срабатывания сигнала до начала инцидента (минуты).';
        v_legend := v_legend || E'\n- Длит.сигн.(мин) – длительность непрерывного сигнала (в минутах).';
        v_legend := v_legend || E'\n- Прирост риска – скорость изменения риска за последние N минут (положительное значение – рост).';
        v_legend := v_legend || E'\n- Прирост JS – скорость изменения JS за последние N минут.';
        v_legend := v_legend || E'\n- Данные – достаточность данных для расчёта сигнала: OK – достаточно, LOW_JS – мало данных JS, LOW_RISK – мало данных риска, LOW_BOTH – мало обоих.';
        v_legend := v_legend || E'\n- Уверенность – среднее значение превышения порогов (нормированное) за время сигнала (от 0 до ...).';
        IF v_include_pre_incident_matches THEN
            v_legend := v_legend || E'\n- Шаблон ID – идентификатор совпавшего пред-инцидентного профиля (если есть). NULL – совпадений не найдено.';
            v_legend := v_legend || E'\n- Divergence с шаблоном – значение JS-дивергенции между текущим профилем и совпавшим шаблоном (если есть).';
        END IF;
        IF v_extended_report THEN
            v_legend := v_legend || E'\n- Метка – маркер состояния: [S] – сигнал сработал, [ND] – недостаточно данных.';
            v_legend := v_legend || E'\n- Сила сигн. – значение силы сигнала в момент первого превышения.';
            v_legend := v_legend || E'\n- Макс.сила – максимальное значение силы сигнала за время его действия.';
        END IF;
        v_report := array_append(v_report, v_legend);
        v_report := array_append(v_report, '');
    END IF;

    -- Заголовки таблицы
    IF v_csv_mode THEN
        v_header_line := 'ID;Время;Приор;JS_avg;JS_min;JS_max;JS_cnt;Risk_avg;Risk_min;Risk_max;Risk_cnt;Тренд;Посл.статус;Сигнал;Мин_до_сигн;Длит_сигн;Прирост_риска;Прирост_JS;Данные;Уверенность';
        IF v_include_pre_incident_matches THEN
            v_header_line := v_header_line || ';Шаблон_ID;Divergence_с_шаблоном';
        END IF;
        v_report := array_append(v_report, v_header_line);
    ELSE
        IF v_extended_report THEN
            v_report := array_append(v_report, '--- ДЕТАЛИ ПО ИНЦИДЕНТАМ (исключены продолжения серий) ---');
            v_report := array_append(v_report,
                'Метка | ID | Время | Приор | JS(avg [min-max], cnt) | Риск(avg [min-max], cnt) | Тренд | Посл.статус | Сигнал | Мин до сигн. | Длит.сигн.(мин) | Прирост риска | Прирост JS | Данные | Уверенность | Сила сигн. | Макс.сила'
            );
            IF v_include_pre_incident_matches THEN
                v_report := array_append(v_report,
                    ' | Шаблон ID | Divergence с шаблоном'
                );
            END IF;
            v_report := array_append(v_report,
                '----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------'
            );
        ELSE
            v_report := array_append(v_report, '--- ДЕТАЛИ ПО ИНЦИДЕНТАМ (исключены продолжения серий) ---');
            v_report := array_append(v_report,
                'ID | Время | Приор | JS(avg [min-max], cnt) | Риск(avg [min-max], cnt) | Тренд | Посл.статус | Сигнал | Мин до сигн. | Длит.сигн.(мин) | Прирост риска | Прирост JS | Данные | Уверенность'
            );
            IF v_include_pre_incident_matches THEN
                v_report := array_append(v_report,
                    ' | Шаблон ID | Divergence с шаблоном'
                );
            END IF;
            v_report := array_append(v_report,
                '--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------'
            );
        END IF;
    END IF;

    -- ========================================================================
    -- 5. Основной цикл по инцидентам – теперь с вызовом calculate_signal
    -- ========================================================================
    FOR v_incident IN
        SELECT id, start_timepoint, priority, finish_timepoint
        FROM performance_incident
        WHERE start_timepoint BETWEEN p_start AND p_end
          AND (v_priority_filter IS NULL OR priority = ANY(v_priority_filter))
        ORDER BY start_timepoint
    LOOP
        -- Получение последнего статуса
        SELECT status INTO v_last_status
        FROM profile_comparison_log
        WHERE current_window_end < v_incident.start_timepoint
        ORDER BY current_window_end DESC
        LIMIT 1;

        IF v_status_filter IS NOT NULL AND NOT (v_last_status = ANY(v_status_filter)) THEN
            CONTINUE;
        END IF;

        IF v_last_status = 'INCIDENT' THEN
            v_excluded_incidents := v_excluded_incidents + 1;
            CONTINUE;
        END IF;

        v_included_ids := array_append(v_included_ids, v_incident.id);
        v_total_incidents := v_total_incidents + 1;

        -- Вызов calculate_signal
        SELECT * INTO v_signal
        FROM calculate_signal(
            v_incident.start_timepoint,
            v_window_minutes,
            v_js_threshold,
            v_risk_threshold,
            v_signal_mode,
            v_min_signal_duration,
            v_weight_js,
            v_weight_risk,
            v_max_js_age_min,
            v_min_data_points,
            v_slope_window_minutes
        );

        -- Тренд риска (вычисляем отдельно, если есть данные)
        IF v_signal.risk_cnt >= 2 THEN
            WITH ordered_risks AS (
                SELECT predicted_risk,
                       ROW_NUMBER() OVER (ORDER BY prediction_time) AS rn
                FROM prediction_log
                WHERE prediction_time >= v_incident.start_timepoint - (v_window_minutes || ' minutes')::INTERVAL
                  AND prediction_time < v_incident.start_timepoint
                  AND predicted_risk IS NOT NULL
                ORDER BY prediction_time
            ),
            first_last AS (
                SELECT
                    MAX(CASE WHEN rn = 1 THEN predicted_risk END) AS first_val,
                    MAX(CASE WHEN rn = (SELECT MAX(rn) FROM ordered_risks) THEN predicted_risk END) AS last_val
                FROM ordered_risks
            )
            SELECT
                CASE
                    WHEN last_val > first_val THEN 'РОСТ'
                    WHEN last_val < first_val THEN 'СНИЖЕНИЕ'
                    ELSE 'СТАБИЛЬНО'
                END INTO v_trend
            FROM first_last;
        ELSE
            v_trend := 'НЕДОСТАТОЧНО ДАННЫХ';
        END IF;

        -- Подготовка строковых представлений
        IF v_signal.js_cnt = 0 THEN
            v_js_str := 'NULL [NULL-NULL], n=0';
        ELSIF v_signal.js_cnt = -1 THEN
            v_js_str := COALESCE(round(v_signal.js_avg::NUMERIC, 4)::TEXT, 'NULL') || ' [посл.]';
        ELSE
            v_js_str := COALESCE(round(v_signal.js_avg::NUMERIC, 4)::TEXT, 'NULL') || ' [' ||
                        COALESCE(round(v_signal.js_min::NUMERIC, 4)::TEXT, 'NULL') || '-' ||
                        COALESCE(round(v_signal.js_max::NUMERIC, 4)::TEXT, 'NULL') || '], n=' || v_signal.js_cnt::TEXT;
        END IF;

        IF v_signal.risk_cnt = 0 THEN
            v_risk_str := 'NULL [NULL-NULL], n=0';
        ELSE
            v_risk_str := COALESCE(round(v_signal.risk_avg::NUMERIC, 4)::TEXT, 'NULL') || ' [' ||
                          COALESCE(round(v_signal.risk_min::NUMERIC, 4)::TEXT, 'NULL') || '-' ||
                          COALESCE(round(v_signal.risk_max::NUMERIC, 4)::TEXT, 'NULL') || '], n=' || v_signal.risk_cnt::TEXT;
        END IF;

        -- Маркер
        IF v_signal.data_sufficient IN ('LOW_JS', 'LOW_RISK', 'LOW_BOTH') THEN
            v_marker := '[ND]';
        ELSIF v_signal.signal_triggered THEN
            v_marker := '[S]';
        ELSE
            v_marker := '';
        END IF;

        -- Формирование строки
        IF v_csv_mode THEN
            v_line := format('%s;%s;%s;%s;%s;%s;%s;%s;%s;%s;%s;%s;%s;%s;%s;%s;%s;%s;%s;%s',
                v_incident.id,
                to_char(v_incident.start_timepoint, 'YYYY-MM-DD HH24:MI'),
                COALESCE(v_incident.priority::TEXT, 'N/A'),
                COALESCE(round(v_signal.js_avg::NUMERIC, 4)::TEXT, 'NULL'),
                COALESCE(round(v_signal.js_min::NUMERIC, 4)::TEXT, 'NULL'),
                COALESCE(round(v_signal.js_max::NUMERIC, 4)::TEXT, 'NULL'),
                CASE WHEN v_signal.js_cnt = -1 THEN 'посл.' ELSE v_signal.js_cnt::TEXT END,
                COALESCE(round(v_signal.risk_avg::NUMERIC, 4)::TEXT, 'NULL'),
                COALESCE(round(v_signal.risk_min::NUMERIC, 4)::TEXT, 'NULL'),
                COALESCE(round(v_signal.risk_max::NUMERIC, 4)::TEXT, 'NULL'),
                v_signal.risk_cnt,
                v_trend,
                COALESCE(v_last_status, 'НЕТ ДАННЫХ'),
                CASE WHEN v_signal.signal_triggered THEN 'ДА' ELSE 'НЕТ' END,
                COALESCE(round(EXTRACT(EPOCH FROM (v_incident.start_timepoint - v_signal.first_signal_time)) / 60)::TEXT, 'NULL'),
                COALESCE(v_signal.signal_duration::TEXT, '0'),
                COALESCE(round(v_signal.risk_slope::NUMERIC, 4)::TEXT, 'NULL'),
                COALESCE(round(v_signal.js_slope::NUMERIC, 4)::TEXT, 'NULL'),
                v_signal.data_sufficient,
                COALESCE(round(v_signal.confidence::NUMERIC, 4)::TEXT, 'NULL')
            );
            IF v_include_pre_incident_matches THEN
                v_line := v_line || format(';%s;%s',
                    COALESCE(NULL::TEXT, 'NULL'),  -- Шаблон ID – не вычисляем в этой версии для упрощения
                    COALESCE(NULL::TEXT, 'NULL')   -- Divergence с шаблоном
                );
            END IF;
        ELSIF v_extended_report THEN
            v_line := format(
                '%s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s',
                v_marker,
                v_incident.id,
                to_char(v_incident.start_timepoint, 'YYYY-MM-DD HH24:MI'),
                COALESCE(v_incident.priority::TEXT, 'N/A'),
                v_js_str,
                v_risk_str,
                v_trend,
                COALESCE(v_last_status, 'НЕТ ДАННЫХ'),
                CASE WHEN v_signal.signal_triggered THEN 'ДА' ELSE 'НЕТ' END,
                COALESCE(round(EXTRACT(EPOCH FROM (v_incident.start_timepoint - v_signal.first_signal_time)) / 60)::TEXT, 'NULL'),
                COALESCE(v_signal.signal_duration::TEXT, '0'),
                COALESCE(round(v_signal.risk_slope::NUMERIC, 4)::TEXT, 'NULL'),
                COALESCE(round(v_signal.js_slope::NUMERIC, 4)::TEXT, 'NULL'),
                v_signal.data_sufficient,
                COALESCE(round(v_signal.confidence::NUMERIC, 4)::TEXT, 'NULL'),
                COALESCE(round(v_signal.signal_strength::NUMERIC, 4)::TEXT, 'NULL'),
                COALESCE(round(v_signal.max_signal_strength::NUMERIC, 4)::TEXT, 'NULL')
            );
            IF v_include_pre_incident_matches THEN
                v_line := v_line || format(' | %s | %s',
                    COALESCE(NULL::TEXT, 'NULL'),
                    COALESCE(NULL::TEXT, 'NULL')
                );
            END IF;
        ELSE
            v_line := format(
                '%s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s',
                v_incident.id,
                to_char(v_incident.start_timepoint, 'YYYY-MM-DD HH24:MI'),
                COALESCE(v_incident.priority::TEXT, 'N/A'),
                v_js_str,
                v_risk_str,
                v_trend,
                COALESCE(v_last_status, 'НЕТ ДАННЫХ'),
                CASE WHEN v_signal.signal_triggered THEN 'ДА' ELSE 'НЕТ' END,
                COALESCE(round(EXTRACT(EPOCH FROM (v_incident.start_timepoint - v_signal.first_signal_time)) / 60)::TEXT, 'NULL'),
                COALESCE(v_signal.signal_duration::TEXT, '0'),
                COALESCE(round(v_signal.risk_slope::NUMERIC, 4)::TEXT, 'NULL'),
                COALESCE(round(v_signal.js_slope::NUMERIC, 4)::TEXT, 'NULL'),
                v_signal.data_sufficient,
                COALESCE(round(v_signal.confidence::NUMERIC, 4)::TEXT, 'NULL')
            );
            IF v_include_pre_incident_matches THEN
                v_line := v_line || format(' | %s | %s',
                    COALESCE(NULL::TEXT, 'NULL'),
                    COALESCE(NULL::TEXT, 'NULL')
                );
            END IF;
        END IF;

        v_report := array_append(v_report, v_line);

        -- Накопление статистики для сводки
        IF v_signal.signal_triggered THEN
            v_incidents_with_signal := v_incidents_with_signal + 1;
            v_avg_minutes_to_incident := v_avg_minutes_to_incident +
                EXTRACT(EPOCH FROM (v_incident.start_timepoint - v_signal.first_signal_time)) / 60;
        END IF;
        IF v_signal.js_avg IS NOT NULL THEN
            v_avg_js_avg := v_avg_js_avg + v_signal.js_avg;
        END IF;
        IF v_signal.risk_avg IS NOT NULL THEN
            v_avg_risk_avg := v_avg_risk_avg + v_signal.risk_avg;
        END IF;
    END LOOP;

    -- ========================================================================
    -- 6. Обработка случая отсутствия данных
    -- ========================================================================
    IF v_total_incidents = 0 THEN
        IF NOT v_csv_mode THEN
            v_report := array_append(v_report, format('Инцидентов (не являющихся продолжением серий) за период не найдено. Исключено серийных: %s.', v_excluded_incidents));
            v_report := array_append(v_report, '');
            v_report := array_append(v_report, '=== КОНЕЦ ОТЧЁТА ===');
        ELSE
            v_report := array_append(v_report, 'Нет данных');
        END IF;
        RETURN v_report;
    END IF;

    -- ========================================================================
    -- 7. Итоговая статистика (если включена)
    -- ========================================================================
    IF v_include_summary AND NOT v_csv_mode THEN
        v_avg_minutes_to_incident := v_avg_minutes_to_incident / NULLIF(v_incidents_with_signal, 0);
        v_avg_js_avg := v_avg_js_avg / v_total_incidents;
        v_avg_risk_avg := v_avg_risk_avg / v_total_incidents;

        WITH last_statuses AS (
            SELECT DISTINCT ON (pi.id)
                pi.id,
                pcl.status
            FROM performance_incident pi
            JOIN profile_comparison_log pcl
                ON pcl.current_window_end < pi.start_timepoint
            WHERE pi.id = ANY(v_included_ids)
            ORDER BY pi.id, pcl.current_window_end DESC
        )
        SELECT jsonb_build_object(
            'CRITICAL', COUNT(*) FILTER (WHERE status = 'CRITICAL'),
            'WARNING', COUNT(*) FILTER (WHERE status = 'WARNING'),
            'NORMAL', COUNT(*) FILTER (WHERE status = 'NORMAL'),
            'INCIDENT', COUNT(*) FILTER (WHERE status = 'INCIDENT'),
            'НЕТ ДАННЫХ', COUNT(*) FILTER (WHERE status IS NULL)
        ) INTO v_status_counts
        FROM last_statuses;

        v_pct_text := round(((v_incidents_with_signal::REAL / v_total_incidents) * 100)::NUMERIC, 1)::TEXT || '%';

        -- Распределение по часам и дням
        WITH incident_hours AS (
            SELECT EXTRACT(HOUR FROM start_timepoint)::INT AS h, COUNT(*) AS cnt
            FROM performance_incident
            WHERE id = ANY(v_included_ids)
            GROUP BY h
        ),
        incident_dows AS (
            SELECT EXTRACT(DOW FROM start_timepoint)::INT AS dow, COUNT(*) AS cnt
            FROM performance_incident
            WHERE id = ANY(v_included_ids)
            GROUP BY dow
        )
        SELECT
            (SELECT jsonb_object_agg(h, cnt) FROM incident_hours),
            (SELECT jsonb_object_agg(dow, cnt) FROM incident_dows)
        INTO v_hour_dist, v_dow_dist;

        WITH hour_graph AS (
            SELECT h, cnt, repeat('*', cnt::INT) AS stars
            FROM (SELECT (jsonb_each(v_hour_dist)).key::INT AS h, (jsonb_each(v_hour_dist)).value::INT AS cnt) t
            ORDER BY h
        )
        SELECT string_agg(format('%02s: %s', h, stars), E'\n') INTO v_hour_graph FROM hour_graph;

        WITH dow_graph AS (
            SELECT dow, cnt, repeat('*', cnt::INT) AS stars
            FROM (SELECT (jsonb_each(v_dow_dist)).key::INT AS dow, (jsonb_each(v_dow_dist)).value::INT AS cnt) t
            ORDER BY dow
        )
        SELECT string_agg(format('День %s: %s', dow, stars), E'\n') INTO v_dow_graph FROM dow_graph;

        -- Метрики качества
        WITH quality_metrics AS (
            SELECT
                COUNT(*) FILTER (WHERE actual_outcome = 1) AS pos,
                COUNT(*) FILTER (WHERE actual_outcome = 0) AS neg,
                AVG((predicted_risk - actual_outcome)^2) AS brier,
                (SUM(CASE WHEN actual_outcome = 1 THEN rnk ELSE 0 END) -
                 (COUNT(CASE WHEN actual_outcome = 1 THEN 1 END) *
                  (COUNT(CASE WHEN actual_outcome = 1 THEN 1 END) + 1) / 2.0)
                ) / (COUNT(CASE WHEN actual_outcome = 1 THEN 1 END) *
                     COUNT(CASE WHEN actual_outcome = 0 THEN 1 END)) AS auc
            FROM (
                SELECT
                    predicted_risk,
                    actual_outcome,
                    ROW_NUMBER() OVER (ORDER BY predicted_risk ASC) AS rnk
                FROM prediction_log
                WHERE prediction_time BETWEEN p_start AND p_end
                  AND actual_outcome IS NOT NULL
            ) ranked
            WHERE actual_outcome IN (0,1)
        )
        SELECT brier, auc INTO v_brier, v_roc_auc FROM quality_metrics;

        WITH calibration_bins AS (
            SELECT
                FLOOR(predicted_risk / 0.1) * 0.1 AS bin_low,
                FLOOR(predicted_risk / 0.1) * 0.1 + 0.1 AS bin_high,
                AVG(predicted_risk) AS avg_pred,
                AVG(actual_outcome) AS obs_freq,
                COUNT(*) AS cnt
            FROM prediction_log
            WHERE prediction_time BETWEEN p_start AND p_end
              AND actual_outcome IS NOT NULL
              AND predicted_risk IS NOT NULL
            GROUP BY FLOOR(predicted_risk / 0.1)
            ORDER BY bin_low
        )
        SELECT jsonb_agg(
            jsonb_build_object(
                'bin_low', bin_low,
                'bin_high', bin_high,
                'avg_pred', avg_pred,
                'obs_freq', obs_freq,
                'count', cnt
            )
        ) INTO v_calibration FROM calibration_bins;

        -- Вывод итогов
        v_report := array_append(v_report, '');
        v_report := array_append(v_report, '--- ИТОГОВАЯ СТАТИСТИКА ---');
        v_report := array_append(v_report, format('Всего инцидентов (исключены серийные): %s', v_total_incidents));
        v_report := array_append(v_report, format('  Исключено серийных (последний статус INCIDENT): %s', v_excluded_incidents));
        v_report := array_append(v_report, format('  - с сигналом (режим %s, длительность >= %s мин): %s (%s)',
            v_signal_mode, v_min_signal_duration, v_incidents_with_signal, v_pct_text));
        v_report := array_append(v_report, format('Среднее время от сигнала до инцидента: %s мин', COALESCE(round(v_avg_minutes_to_incident::NUMERIC, 1)::TEXT, 'NULL')));
        v_report := array_append(v_report, format('Средняя JS-дивергенция (за час до инцидента): %s', round(v_avg_js_avg::NUMERIC, 4)));
        v_report := array_append(v_report, format('Средний риск (за час до инцидента): %s', round(v_avg_risk_avg::NUMERIC, 4)));

        IF v_include_pre_incident_matches THEN
            -- Для совпадений с пред-инцидентными профилями – в этой версии не вычисляем, оставляем заглушку
            v_match_pct := '0%';
            v_report := array_append(v_report, format('  - инцидентов с совпадением с пред-инцидентным профилем: %s (%s)',
                0, v_match_pct));
        END IF;

        v_report := array_append(v_report, 'Распределение последних статусов перед инцидентами:');
        v_report := array_append(v_report, format('  CRITICAL: %s', COALESCE((v_status_counts->>'CRITICAL')::TEXT, '0')));
        v_report := array_append(v_report, format('  WARNING: %s', COALESCE((v_status_counts->>'WARNING')::TEXT, '0')));
        v_report := array_append(v_report, format('  NORMAL: %s', COALESCE((v_status_counts->>'NORMAL')::TEXT, '0')));
        v_report := array_append(v_report, format('  INCIDENT: %s', COALESCE((v_status_counts->>'INCIDENT')::TEXT, '0')));
        v_report := array_append(v_report, format('  НЕТ ДАННЫХ: %s', COALESCE((v_status_counts->>'НЕТ ДАННЫХ')::TEXT, '0')));

        IF v_roc_auc IS NOT NULL THEN
            v_report := array_append(v_report, format('ROC-AUC (на основе prediction_log.actual_outcome): %s', round(v_roc_auc::NUMERIC, 4)));
            v_report := array_append(v_report, format('Brier score: %s', round(v_brier::NUMERIC, 6)));
        END IF;

        IF v_calibration IS NOT NULL THEN
            v_report := array_append(v_report, 'Калибровочная кривая (риск vs. фактическая частота):');
            FOR v_rec IN SELECT * FROM jsonb_to_recordset(v_calibration) AS x(bin_low NUMERIC, bin_high NUMERIC, avg_pred NUMERIC, obs_freq NUMERIC, cnt INT)
            LOOP
                v_report := array_append(v_report, format('  [%s-%s]: предсказано %s, фактически %s, n=%s',
                    round(v_rec.bin_low::NUMERIC, 1),
                    round(v_rec.bin_high::NUMERIC, 1),
                    round(v_rec.avg_pred::NUMERIC, 3),
                    round(v_rec.obs_freq::NUMERIC, 3),
                    v_rec.cnt));
            END LOOP;
        END IF;

        v_report := array_append(v_report, 'Распределение инцидентов по часам (0-23):');
        IF v_hour_graph IS NOT NULL THEN
            v_report := array_append(v_report, v_hour_graph);
        ELSE
            v_report := array_append(v_report, 'Нет данных');
        END IF;
        v_report := array_append(v_report, 'Распределение инцидентов по дням недели (0-6, 0=Вс):');
        IF v_dow_graph IS NOT NULL THEN
            v_report := array_append(v_report, v_dow_graph);
        ELSE
            v_report := array_append(v_report, 'Нет данных');
        END IF;
    END IF;

    IF NOT v_csv_mode THEN
        v_report := array_append(v_report, '');
        v_report := array_append(v_report, '=== КОНЕЦ ОТЧЁТА ===');
    END IF;

    RETURN v_report;
END;
$$;

COMMENT ON FUNCTION generate_incident_forecast_report(TIMESTAMPTZ, TIMESTAMPTZ) IS 'Расширенный отчёт по прогнозированию инцидентов с исключением серийных инцидентов. Использует calculate_signal для вычисления метрик.';

-- Функция для ежеминутного обновления индикатора
-- вычисляет текущий сигнал и, если он изменился по сравнению с последним сохранённым, добавляет новую запись в profile_change_indicator.
-- =============================================================================
-- Функция: update_profile_change_indicator (обновлённая)
-- Назначение: Ежеминутно вычисляет текущий сигнал с помощью calculate_signal
--             и сохраняет изменения состояния в profile_change_indicator.
-- Возвращает: TEXT – сообщение о результате (инициализация, изменение или неизменность).
-- =============================================================================
CREATE OR REPLACE FUNCTION update_profile_change_indicator()
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    v_current_signal BOOLEAN;
    v_last_signal    BOOLEAN;
    v_signal_rec     RECORD;
BEGIN
    -- 1. Вычисляем текущий сигнал с помощью calculate_signal (использует конфигурацию)
    SELECT signal_triggered INTO v_current_signal
    FROM calculate_signal(now());

    -- 2. Получаем последнее сохранённое значение индикатора
    SELECT indicator_value INTO v_last_signal
    FROM profile_change_indicator
    ORDER BY changed_at DESC
    LIMIT 1;

    -- 3. Если записей ещё нет – создаём первую
    IF v_last_signal IS NULL THEN
        INSERT INTO profile_change_indicator (indicator_value, changed_at)
        VALUES (v_current_signal, now());
        RETURN format('Initial indicator set to %s at %s', v_current_signal, now());
    END IF;

    -- 4. Если сигнал изменился – добавляем новую запись
    IF v_current_signal != v_last_signal THEN
        INSERT INTO profile_change_indicator (indicator_value, changed_at)
        VALUES (v_current_signal, now());
        RETURN format('Indicator changed from %s to %s at %s', v_last_signal, v_current_signal, now());
    ELSE
        RETURN format('Indicator unchanged (%s) at %s', v_current_signal, now());
    END IF;
END;
$$;

COMMENT ON FUNCTION update_profile_change_indicator() IS 'Ежеминутная функция обновления индикатора. Вычисляет текущий сигнал через calculate_signal и добавляет запись в историю только при изменении состояния.';


--Функция для исторического заполнения индикатора
/*
-- Полное перезаполнение индикатора за последние 7 дней
SELECT historical_fill_profile_change_indicator(now() - INTERVAL '7 days', now());

-- Полное перезаполнение от начала доступных данных
SELECT historical_fill_profile_change_indicator();
*/
-- =============================================================================
-- Модифицированная функция historical_fill_profile_change_indicator
-- теперь использует calculate_signal
-- =============================================================================
CREATE OR REPLACE FUNCTION historical_fill_profile_change_indicator(
    p_start TIMESTAMPTZ DEFAULT NULL,
    p_end   TIMESTAMPTZ DEFAULT NULL
)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    v_start TIMESTAMPTZ;
    v_end   TIMESTAMPTZ;
    v_ts    TIMESTAMPTZ;
    v_signal BOOLEAN;
    v_last_signal BOOLEAN := NULL;
    v_counter BIGINT := 0;
    v_total_minutes BIGINT;
    v_last_percent INT := -1;
    v_current_percent INT;
    v_inserted INT := 0;
    v_processed_ts TIMESTAMPTZ;
    v_signal_rec RECORD;
BEGIN
    -- 1. Определение границ
    IF p_start IS NULL THEN
        SELECT MIN(current_window_end) INTO v_start FROM profile_comparison_log;
        IF v_start IS NULL THEN
            RETURN 'Нет данных в profile_comparison_log для определения начала периода.';
        END IF;
    ELSE
        v_start := p_start;
    END IF;

    IF p_end IS NULL THEN
        v_end := now();
    ELSE
        v_end := p_end;
    END IF;

    IF v_start >= v_end THEN
        RETURN 'Начальная дата должна быть раньше конечной.';
    END IF;

    -- 2. Удаление существующих записей за указанный период (перезапись)
    DELETE FROM profile_change_indicator
    WHERE changed_at BETWEEN v_start AND v_end;

    RAISE NOTICE 'Удалены существующие записи за период с % по %', v_start, v_end;

    -- 3. Подготовка к циклу
    v_ts := date_trunc('minute', v_start);
    v_total_minutes := EXTRACT(EPOCH FROM (date_trunc('minute', v_end) - v_ts)) / 60 + 1;
    RAISE NOTICE 'Начало исторического заполнения индикатора с % по % (всего % минут)',
                 v_ts, v_end, v_total_minutes;

    -- 4. Цикл по минутам
    WHILE v_ts <= v_end LOOP
        v_processed_ts := v_ts;

        -- Вычисляем сигнал с помощью calculate_signal
        SELECT signal_triggered INTO v_signal
        FROM calculate_signal(v_ts);

        -- Если сигнал изменился или это первая запись
        IF v_last_signal IS NULL OR v_signal != v_last_signal THEN
            INSERT INTO profile_change_indicator (indicator_value, changed_at)
            VALUES (v_signal, v_ts);
            v_inserted := v_inserted + 1;
            v_last_signal := v_signal;
        END IF;

        v_counter := v_counter + 1;
        v_ts := v_ts + INTERVAL '1 minute';

        -- Вывод прогресса каждые 1%
        v_current_percent := floor((v_counter::NUMERIC / v_total_minutes) * 100);
        IF v_current_percent > v_last_percent THEN
            RAISE NOTICE 'Прогресс: % % (обработано % из % минут, вставлено % записей, последняя минута: %)',
                         v_current_percent, '%', v_counter, v_total_minutes, v_inserted, v_processed_ts;
            v_last_percent := v_current_percent;
        END IF;
    END LOOP;

    RAISE NOTICE 'Заполнение завершено. Обработано % минут, вставлено % записей об изменении состояния.',
                 v_counter, v_inserted;
    RETURN format('Историческое заполнение завершено. Обработано %s минут, вставлено %s записей.',
                  v_counter, v_inserted);
END;
$$;

COMMENT ON FUNCTION historical_fill_profile_change_indicator(TIMESTAMPTZ, TIMESTAMPTZ) IS 'Заполняет таблицу profile_change_indicator за указанный период (по умолчанию от начала данных до now()). Для каждой минуты вычисляет сигнал с помощью calculate_signal и сохраняет только изменения.';

-- Функция очистки старых записей из таблицы profile_change_indicator
CREATE OR REPLACE FUNCTION clean_old_profile_change_indicator(
    p_retention_days INT DEFAULT 30
)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    v_deleted_rows BIGINT;
    v_cutoff TIMESTAMPTZ;
BEGIN
    IF p_retention_days <= 0 THEN
        RETURN 'Ошибка: срок хранения должен быть положительным.';
    END IF;

    v_cutoff := now() - (p_retention_days || ' days')::INTERVAL;

    DELETE FROM profile_change_indicator
    WHERE changed_at < v_cutoff;

    GET DIAGNOSTICS v_deleted_rows = ROW_COUNT;

    RETURN format('Удалено %s записей из profile_change_indicator старше %s дней (до %s).',
                  v_deleted_rows, p_retention_days, v_cutoff);
END;
$$;

COMMENT ON FUNCTION clean_old_profile_change_indicator(INT) IS 'Удаляет записи из profile_change_indicator старше указанного количества дней (по умолчанию 90). Возвращает отчёт о количестве удалённых строк.';

-- =============================================================================
-- Новая функция calculate_signal – вычисляет сигнал и статистику для заданного времени
-- =============================================================================
CREATE OR REPLACE FUNCTION calculate_signal(
    p_time TIMESTAMPTZ,
    p_window_minutes INT DEFAULT NULL,
    p_js_threshold REAL DEFAULT NULL,
    p_risk_threshold REAL DEFAULT NULL,
    p_signal_mode TEXT DEFAULT NULL,
    p_min_signal_duration INT DEFAULT NULL,
    p_weight_js REAL DEFAULT NULL,
    p_weight_risk REAL DEFAULT NULL,
    p_max_js_age_min INT DEFAULT NULL,
    p_min_data_points INT DEFAULT NULL,
    p_slope_window_minutes INT DEFAULT NULL
)
RETURNS TABLE (
    js_avg REAL,
    js_min REAL,
    js_max REAL,
    js_cnt INT,
    risk_avg REAL,
    risk_min REAL,
    risk_max REAL,
    risk_cnt INT,
    signal_triggered BOOLEAN,
    first_signal_time TIMESTAMPTZ,
    signal_duration INT,
    signal_strength REAL,
    max_signal_strength REAL,
    risk_slope REAL,
    js_slope REAL,
    data_sufficient TEXT,
    confidence REAL
)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    cfg RECORD;
    v_window_minutes INT;
    v_js_threshold REAL;
    v_risk_threshold REAL;
    v_signal_mode TEXT;
    v_min_signal_duration INT;
    v_weight_js REAL;
    v_weight_risk REAL;
    v_max_js_age_min INT;
    v_min_data_points INT;
    v_slope_window_minutes INT;

    v_js_stats RECORD;
    v_risk_stats RECORD;
    v_last_js REAL;
    v_last_js_time TIMESTAMPTZ;
    v_last_risk REAL;
    v_last_risk_time TIMESTAMPTZ;

    v_js_min REAL;
    v_js_max REAL;
    v_js_avg REAL;
    v_js_cnt INT;
    v_risk_min REAL;
    v_risk_max REAL;
    v_risk_avg REAL;
    v_risk_cnt INT;
    v_data_sufficient TEXT := 'OK';
    v_insufficient BOOLEAN := FALSE;

    v_first_signal_time TIMESTAMPTZ;
    v_signal_duration INT;
    v_signal_strength REAL;
    v_max_signal_strength REAL;
    v_risk_slope REAL;
    v_js_slope REAL;
    v_confidence REAL;
    v_signal_triggered BOOLEAN := FALSE;

    v_minute_ts TIMESTAMPTZ;
    v_js_value REAL;
    v_risk_value REAL;
    v_is_signal_minute BOOLEAN;
    v_signal_strength_minute REAL;
    v_prev_signal BOOLEAN := FALSE;
    v_current_duration INT := 0;
    v_signal_found BOOLEAN := FALSE;
BEGIN
    -- 1. Чтение конфигурации (если параметры не переданы)
    IF p_window_minutes IS NULL OR p_js_threshold IS NULL OR p_risk_threshold IS NULL OR
       p_signal_mode IS NULL OR p_min_signal_duration IS NULL OR
       p_weight_js IS NULL OR p_weight_risk IS NULL OR
       p_max_js_age_min IS NULL OR p_min_data_points IS NULL OR
       p_slope_window_minutes IS NULL THEN
        SELECT * INTO cfg FROM incident_forecast_config LIMIT 1;
        IF NOT FOUND THEN
            INSERT INTO incident_forecast_config DEFAULT VALUES;
            SELECT * INTO cfg FROM incident_forecast_config LIMIT 1;
        END IF;
        v_window_minutes := COALESCE(p_window_minutes, cfg.window_minutes);
        v_js_threshold := COALESCE(p_js_threshold, cfg.js_threshold);
        v_risk_threshold := COALESCE(p_risk_threshold, cfg.risk_threshold);
        v_signal_mode := COALESCE(p_signal_mode, cfg.signal_mode);
        v_min_signal_duration := COALESCE(p_min_signal_duration, cfg.min_signal_duration);
        v_weight_js := COALESCE(p_weight_js, cfg.weight_js);
        v_weight_risk := COALESCE(p_weight_risk, cfg.weight_risk);
        v_max_js_age_min := COALESCE(p_max_js_age_min, cfg.max_js_age_min);
        v_min_data_points := COALESCE(p_min_data_points, cfg.min_data_points);
        v_slope_window_minutes := COALESCE(p_slope_window_minutes, cfg.slope_window_minutes);
    ELSE
        v_window_minutes := p_window_minutes;
        v_js_threshold := p_js_threshold;
        v_risk_threshold := p_risk_threshold;
        v_signal_mode := p_signal_mode;
        v_min_signal_duration := p_min_signal_duration;
        v_weight_js := p_weight_js;
        v_weight_risk := p_weight_risk;
        v_max_js_age_min := p_max_js_age_min;
        v_min_data_points := p_min_data_points;
        v_slope_window_minutes := p_slope_window_minutes;
    END IF;

    -- 2. Получение последних значений за пределами окна (для подстановки при пропусках)
    SELECT js_divergence, current_window_end
    INTO v_last_js, v_last_js_time
    FROM profile_comparison_log
    WHERE current_window_end < p_time - (v_window_minutes || ' minutes')::INTERVAL
      AND js_divergence IS NOT NULL
    ORDER BY current_window_end DESC
    LIMIT 1;

    SELECT predicted_risk, prediction_time
    INTO v_last_risk, v_last_risk_time
    FROM prediction_log
    WHERE prediction_time < p_time - (v_window_minutes || ' minutes')::INTERVAL
      AND predicted_risk IS NOT NULL
    ORDER BY prediction_time DESC
    LIMIT 1;

    -- 3. Сбор статистики JS за окно (по диапазону)
    SELECT
        MIN(js_divergence) AS min_val,
        MAX(js_divergence) AS max_val,
        AVG(js_divergence) AS avg_val,
        COUNT(*) AS cnt
    INTO v_js_stats
    FROM profile_comparison_log
    WHERE current_window_end >= p_time - (v_window_minutes || ' minutes')::INTERVAL
      AND current_window_end < p_time
      AND js_divergence IS NOT NULL;

    -- Если данных в окне недостаточно, пытаемся использовать последнее значение из-за окна
    IF v_js_stats IS NULL OR v_js_stats.cnt < v_min_data_points THEN
        IF v_last_js IS NOT NULL AND
           EXTRACT(EPOCH FROM (p_time - v_last_js_time)) / 60 <= v_max_js_age_min THEN
            v_js_min := v_last_js;
            v_js_max := v_last_js;
            v_js_avg := v_last_js;
            v_js_cnt := -1;   -- признак "последнее значение"
            v_data_sufficient := 'LOW_JS';
        ELSE
            v_js_min := NULL; v_js_max := NULL; v_js_avg := NULL; v_js_cnt := 0;
            v_insufficient := TRUE;
            v_data_sufficient := 'LOW_JS';
        END IF;
    ELSE
        v_js_min := v_js_stats.min_val;
        v_js_max := v_js_stats.max_val;
        v_js_avg := v_js_stats.avg_val;
        v_js_cnt := v_js_stats.cnt;
    END IF;

    -- 4. Сбор статистики риска за окно (по диапазону)
    SELECT
        MIN(predicted_risk) AS min_val,
        MAX(predicted_risk) AS max_val,
        AVG(predicted_risk) AS avg_val,
        COUNT(*) AS cnt
    INTO v_risk_stats
    FROM prediction_log
    WHERE prediction_time >= p_time - (v_window_minutes || ' minutes')::INTERVAL
      AND prediction_time < p_time
      AND predicted_risk IS NOT NULL;

    IF v_risk_stats IS NULL OR v_risk_stats.cnt < v_min_data_points THEN
        IF v_last_risk IS NOT NULL AND
           EXTRACT(EPOCH FROM (p_time - v_last_risk_time)) / 60 <= v_max_js_age_min THEN
            v_risk_min := v_last_risk;
            v_risk_max := v_last_risk;
            v_risk_avg := v_last_risk;
            v_risk_cnt := -1;
            IF v_data_sufficient = 'OK' OR v_data_sufficient = 'LOW_JS' THEN
                v_data_sufficient := 'LOW_RISK';
            ELSE
                v_data_sufficient := 'LOW_BOTH';
            END IF;
        ELSE
            v_risk_min := NULL; v_risk_max := NULL; v_risk_avg := NULL; v_risk_cnt := 0;
            v_insufficient := TRUE;
            IF v_data_sufficient = 'OK' OR v_data_sufficient = 'LOW_JS' THEN
                v_data_sufficient := 'LOW_RISK';
            ELSE
                v_data_sufficient := 'LOW_BOTH';
            END IF;
        END IF;
    ELSE
        v_risk_min := v_risk_stats.min_val;
        v_risk_max := v_risk_stats.max_val;
        v_risk_avg := v_risk_stats.avg_val;
        v_risk_cnt := v_risk_stats.cnt;
    END IF;

    -- Если данных недостаточно, возвращаем результат без сигнала
    IF v_insufficient THEN
        js_avg := v_js_avg; js_min := v_js_min; js_max := v_js_max; js_cnt := v_js_cnt;
        risk_avg := v_risk_avg; risk_min := v_risk_min; risk_max := v_risk_max; risk_cnt := v_risk_cnt;
        signal_triggered := FALSE;
        first_signal_time := NULL;
        signal_duration := 0;
        signal_strength := NULL;
        max_signal_strength := NULL;
        risk_slope := NULL;
        js_slope := NULL;
        data_sufficient := v_data_sufficient;
        confidence := NULL;
        RETURN NEXT;
        RETURN;
    END IF;

    -- 5. Расчёт сигнала с проверкой длительности (по минутам)
    -- Используем generate_series для каждой минуты в окне
    FOR v_minute_ts IN
        SELECT generate_series(
            date_trunc('minute', p_time - (v_window_minutes || ' minutes')::INTERVAL),
            date_trunc('minute', p_time) - INTERVAL '1 minute',
            INTERVAL '1 minute'
        )
    LOOP
        -- Получаем последнее значение JS на или до текущей минуты
        SELECT js_divergence INTO v_js_value
        FROM profile_comparison_log
        WHERE current_window_end <= v_minute_ts
          AND js_divergence IS NOT NULL
        ORDER BY current_window_end DESC
        LIMIT 1;

        -- Если не найдено, используем v_last_js (последнее известное до окна)
        IF v_js_value IS NULL THEN
            v_js_value := v_last_js;
        ELSE
            v_last_js := v_js_value;  -- обновляем для следующих минут
        END IF;

        -- Аналогично для риска
        SELECT predicted_risk INTO v_risk_value
        FROM prediction_log
        WHERE prediction_time <= v_minute_ts
          AND predicted_risk IS NOT NULL
        ORDER BY prediction_time DESC
        LIMIT 1;

        IF v_risk_value IS NULL THEN
            v_risk_value := v_last_risk;
        ELSE
            v_last_risk := v_risk_value;
        END IF;

        -- Если оба значения не NULL, вычисляем сигнал для этой минуты
        IF v_js_value IS NOT NULL AND v_risk_value IS NOT NULL THEN
            CASE v_signal_mode
                WHEN 'AND' THEN
                    v_is_signal_minute := (v_risk_value > v_risk_threshold AND v_js_value > v_js_threshold);
                    v_signal_strength_minute := (v_risk_value / v_risk_threshold + v_js_value / v_js_threshold) / 2;
                WHEN 'OR' THEN
                    v_is_signal_minute := (v_risk_value > v_risk_threshold OR v_js_value > v_js_threshold);
                    v_signal_strength_minute := (v_risk_value / v_risk_threshold + v_js_value / v_js_threshold) / 2;
                WHEN 'WEIGHTED' THEN
                    v_signal_strength_minute := (v_risk_value / v_risk_threshold) * v_weight_risk +
                                                (v_js_value / v_js_threshold) * v_weight_js;
                    v_is_signal_minute := v_signal_strength_minute > 1.0;
                WHEN 'OR_WITH_DURATION' THEN
                    v_is_signal_minute := (v_risk_value > v_risk_threshold OR v_js_value > v_js_threshold);
                    v_signal_strength_minute := (v_risk_value / v_risk_threshold + v_js_value / v_js_threshold) / 2;
                ELSE
                    v_is_signal_minute := FALSE;
                    v_signal_strength_minute := 0;
            END CASE;
        ELSE
            v_is_signal_minute := FALSE;
            v_signal_strength_minute := 0;
        END IF;

        -- Группировка для проверки длительности
        IF v_is_signal_minute THEN
            IF NOT v_prev_signal THEN
                v_current_duration := 1;
                v_first_signal_time := v_minute_ts;
                v_signal_strength := v_signal_strength_minute;
                v_max_signal_strength := v_signal_strength_minute;
            ELSE
                v_current_duration := v_current_duration + 1;
                IF v_signal_strength_minute > v_max_signal_strength THEN
                    v_max_signal_strength := v_signal_strength_minute;
                END IF;
            END IF;
            v_prev_signal := TRUE;
            v_signal_triggered := (v_current_duration >= v_min_signal_duration);
        ELSE
            v_prev_signal := FALSE;
            v_current_duration := 0;
        END IF;

        -- Если сигнал уже сработал, можно прервать цикл
        IF v_signal_triggered THEN
            EXIT;
        END IF;
    END LOOP;

    -- Если сигнал сработал, фиксируем длительность и уверенность
    IF v_signal_triggered THEN
        v_signal_duration := v_current_duration;
        v_confidence := v_signal_strength;  -- сила в момент первого срабатывания
    ELSE
        v_first_signal_time := NULL;
        v_signal_duration := 0;
        v_signal_strength := NULL;
        v_max_signal_strength := NULL;
        v_confidence := NULL;
    END IF;

    -- 6. Расчёт скорости изменения (slope) за последние slope_window_minutes
    WITH slope_data AS (
        SELECT
            prediction_time,
            predicted_risk,
            LAG(predicted_risk, 1) OVER (ORDER BY prediction_time) AS prev_risk
        FROM prediction_log
        WHERE prediction_time >= p_time - (v_slope_window_minutes || ' minutes')::INTERVAL
          AND prediction_time < p_time
          AND predicted_risk IS NOT NULL
    )
    SELECT
        (MAX(predicted_risk) - MIN(predicted_risk)) /
            NULLIF(EXTRACT(EPOCH FROM (MAX(prediction_time) - MIN(prediction_time))) / 60, 0) AS risk_slope
    INTO v_risk_slope
    FROM slope_data;

    WITH js_slope_data AS (
        SELECT
            current_window_end,
            js_divergence,
            LAG(js_divergence, 1) OVER (ORDER BY current_window_end) AS prev_js
        FROM profile_comparison_log
        WHERE current_window_end >= p_time - (v_slope_window_minutes || ' minutes')::INTERVAL
          AND current_window_end < p_time
          AND js_divergence IS NOT NULL
    )
    SELECT
        (MAX(js_divergence) - MIN(js_divergence)) /
            NULLIF(EXTRACT(EPOCH FROM (MAX(current_window_end) - MIN(current_window_end))) / 60, 0) AS js_slope
    INTO v_js_slope
    FROM js_slope_data;

    -- 7. Возврат результата
    js_avg := v_js_avg;
    js_min := v_js_min;
    js_max := v_js_max;
    js_cnt := v_js_cnt;
    risk_avg := v_risk_avg;
    risk_min := v_risk_min;
    risk_max := v_risk_max;
    risk_cnt := v_risk_cnt;
    signal_triggered := v_signal_triggered;
    first_signal_time := v_first_signal_time;
    signal_duration := v_signal_duration;
    signal_strength := v_signal_strength;
    max_signal_strength := v_max_signal_strength;
    risk_slope := v_risk_slope;
    js_slope := v_js_slope;
    data_sufficient := v_data_sufficient;
    confidence := v_confidence;

    RETURN NEXT;
END;
$$;

COMMENT ON FUNCTION calculate_signal(TIMESTAMPTZ, INT, REAL, REAL, TEXT, INT, REAL, REAL, INT, INT, INT) IS
'Вычисляет статистику JS-дивергенции и риска за окно до заданного времени, а также определяет срабатывание сигнала (с учётом длительности). Возвращает все необходимые метрики.';


-- Функция сравнения с фиксированным эталоном (исправлена — убран лишний столбец created_at)
CREATE OR REPLACE FUNCTION compare_with_fixed_baseline(p_ts TIMESTAMPTZ)
RETURNS TEXT LANGUAGE plpgsql AS $$
DECLARE
    v_baseline RECORD;
    v_current RECORD;
    v_js REAL;
    v_status TEXT;
    v_window_minutes INT := 60;
    v_interval INTERVAL := (v_window_minutes || ' minutes')::INTERVAL;
    v_js_threshold REAL;
BEGIN
    SELECT state_histogram, avg_correlation, critical_ratio, entropy,
           avg_os_angle, avg_wait_angle, self_loop_ratio
    INTO v_baseline
    FROM profile_aggregated
    WHERE profile_type = 'baseline'
    ORDER BY ts DESC LIMIT 1;
    IF NOT FOUND THEN RETURN 'No baseline profile found.'; END IF;

    SELECT * INTO v_current FROM calculate_profile_metrics(p_ts - v_interval, p_ts);
    IF v_current.state_histogram IS NULL THEN RETURN format('No data for %s', p_ts); END IF;

    v_js := histogram_divergence(v_baseline.state_histogram, v_current.state_histogram);
    SELECT COALESCE(js_divergence_threshold,0.2) INTO v_js_threshold FROM markov_config LIMIT 1;

    v_status := 'NORMAL';
    IF v_js >= v_js_threshold THEN v_status := 'WARNING'; END IF;
    IF v_js >= 0.2 OR ABS(COALESCE(v_current.avg_correlation,0) - COALESCE(v_baseline.avg_correlation,0)) > 0.2 THEN
        v_status := 'CRITICAL';
    END IF;

    INSERT INTO profile_comparison_log (
        baseline_window_start, baseline_window_end, current_window_start, current_window_end,
        status, js_divergence, report, details
    ) VALUES (
        NULL, NULL, p_ts - v_interval, p_ts,
        v_status, v_js,
        jsonb_build_array('Fixed baseline comparison'),
        jsonb_build_object(
            'current_avg_correlation', v_current.avg_correlation,
            'current_critical_ratio', v_current.critical_ratio,
            'current_entropy', v_current.entropy,
            'baseline_avg_correlation', v_baseline.avg_correlation,
            'baseline_critical_ratio', v_baseline.critical_ratio,
            'baseline_entropy', v_baseline.entropy
        )
    );
    RETURN format('Inserted at %s: status=%s, js=%s', p_ts, v_status, v_js);
END;
$$;

COMMENT ON FUNCTION compare_with_fixed_baseline IS 'Функция сравнения с фиксированным эталоном';

-- Процедура массового заполнения
CREATE OR REPLACE PROCEDURE historical_fill_profile_comparison(
    p_start TIMESTAMPTZ, p_end TIMESTAMPTZ, p_step_minutes INT DEFAULT 1
) LANGUAGE plpgsql AS $$
DECLARE
    v_ts TIMESTAMPTZ;
    v_counter BIGINT := 0;
    v_total BIGINT;
    v_result TEXT;
BEGIN
    v_ts := date_trunc('minute', p_start);
    v_total := EXTRACT(EPOCH FROM (p_end - v_ts)) / p_step_minutes + 1;
    RAISE NOTICE 'Начало заполнения с % по % (шаг % мин, всего % итераций)', v_ts, p_end, p_step_minutes, v_total;
    WHILE v_ts <= p_end LOOP
        BEGIN
            v_result := compare_with_fixed_baseline(v_ts);
        EXCEPTION WHEN OTHERS THEN
            RAISE WARNING 'Ошибка на %: %', v_ts, SQLERRM;
        END;
        v_counter := v_counter + 1;
        IF v_counter % 100 = 0 THEN
            RAISE NOTICE 'Прогресс: % из % минут', v_counter, v_total;
        END IF;
        v_ts := v_ts + (p_step_minutes || ' minutes')::INTERVAL;
    END LOOP;
    RAISE NOTICE 'Заполнение завершено. Обработано % минут.', v_counter;
END;
$$;

-- =============================================================================
-- Функция: compare_profiles_at
-- Назначение: выполняет сравнение эталонного и текущего профилей для заданного
--             момента времени (исторического). Логика полностью соответствует
--             compare_profiles, но вместо now() используется переданное время.
-- Параметры:
--   p_ts                   TIMESTAMPTZ – момент времени, для которого выполняется сравнение
--   p_window_minutes       INT         – длина окна в минутах (по умолчанию 60)
--   p_exclude_before_min   INT         – не используется (оставлено для совместимости)
--   p_exclude_after_min    INT         – не используется
-- Возвращает: TEXT[] – форматированный отчёт о сравнении.
-- Сохраняет результат в таблицу profile_comparison_log.
-- =============================================================================
CREATE OR REPLACE FUNCTION compare_profiles_at(
    p_ts                   TIMESTAMPTZ,
    p_window_minutes       INT DEFAULT 60,
    p_lookback_days        INT DEFAULT 7,
    p_exclude_before_min   INT DEFAULT 0,
    p_exclude_after_min    INT DEFAULT 0
)
RETURNS TEXT[]
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
    v_now           TIMESTAMPTZ := p_ts;
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
    v_pre_alert     INTEGER;
    v_js_threshold  REAL;
    v_matched_id    BIGINT;
    v_baseline_found BOOLEAN := FALSE;
BEGIN
    -- 1. Проверяем, находится ли заданный момент внутри активного инцидента
    SELECT EXISTS (
        SELECT 1
        FROM performance_incident
        WHERE start_timepoint <= v_now
          AND (finish_timepoint IS NULL OR finish_timepoint >= v_now)
    ) INTO v_inside_incident;

    -- 2. Вычисляем максимальный предсказанный риск за текущее окно
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
        v_matched_id := NULL;

        INSERT INTO profile_comparison_log (
            created_at,
            current_window_start,
            current_window_end,
            status,
            js_divergence,
            report,
            details,
            max_predicted_risk,
            pre_alert_flag,
            matched_pre_incident_id
        ) VALUES (
            v_now,
            v_current_start,
            v_current_end,
            v_status,
            NULL,
            to_jsonb(v_report),
            jsonb_build_object('reason', 'inside_incident'),
            v_max_pred_risk,
            v_pre_alert,
            v_matched_id
        );
        RETURN v_report;
    END IF;

    -- 4. Пытаемся получить эталонное окно из таблицы incident_free_window_current
    SELECT window_start, window_end INTO v_baseline_start, v_baseline_end
    FROM incident_free_window_current
    LIMIT 1;

    -- Если в incident_free_window_current нет записи, пробуем взять baseline из profile_aggregated
    IF v_baseline_start IS NULL THEN
        SELECT window_start, window_end INTO v_baseline_start, v_baseline_end
        FROM profile_aggregated
        WHERE profile_type = 'baseline'
        ORDER BY ts DESC
        LIMIT 1;
    END IF;

    -- Проверяем, что эталонное окно существует и его конец меньше начала текущего окна
    IF v_baseline_start IS NOT NULL AND v_baseline_end < v_current_start THEN
        v_baseline_found := TRUE;
    ELSE
        v_baseline_found := FALSE;
    END IF;

    -- 5. Если эталон не найден или не подходит – статус NO_BASELINE
    IF NOT v_baseline_found THEN
        v_status := 'NO_BASELINE';
        v_report := array_append(v_report, '=== СРАВНЕНИЕ ПРОФИЛЕЙ ===');
        v_report := array_append(v_report, format('Текущий момент: %s', v_now));
        v_report := array_append(v_report, 'Статус: NO_BASELINE – отсутствует актуальный эталонный профиль (окно не найдено или его конец не раньше текущего окна).');
        v_report := array_append(v_report, '=== КОНЕЦ ОТЧЁТА ===');

        v_pre_alert := 0;
        v_matched_id := NULL;

        INSERT INTO profile_comparison_log (
            created_at,
            current_window_start,
            current_window_end,
            status,
            js_divergence,
            report,
            details,
            max_predicted_risk,
            pre_alert_flag,
            matched_pre_incident_id
        ) VALUES (
            v_now,
            v_current_start,
            v_current_end,
            v_status,
            NULL,
            to_jsonb(v_report),
            jsonb_build_object('reason', 'no_baseline'),
            v_max_pred_risk,
            v_pre_alert,
            v_matched_id
        );
        RETURN v_report;
    END IF;

    -- 6. Эталон найдено – вычисляем метрики для обоих окон
    SELECT * INTO v_baseline_metrics
    FROM calculate_profile_metrics(v_baseline_start, v_baseline_end);

    SELECT * INTO v_current_metrics
    FROM calculate_profile_metrics(v_current_start, v_current_end);

    -- 7. Вычисляем JS-дивергенцию гистограмм
    v_js := histogram_divergence(
        v_baseline_metrics.state_histogram,
        v_current_metrics.state_histogram
    );

    -- 8. Определяем статус по порогам
    v_status := 'NORMAL';
    IF v_js >= 0.05 THEN
        v_status := 'WARNING';
    END IF;
    IF v_js >= 0.2 OR ABS(COALESCE(v_current_metrics.avg_correlation, 0) - COALESCE(v_baseline_metrics.avg_correlation, 0)) > 0.2 THEN
        v_status := 'CRITICAL';
    END IF;

    -- 9. Вычисляем флаг предаварийного состояния
    SELECT COALESCE( (SELECT js_divergence_threshold FROM markov_config ), 0.2 ) INTO v_js_threshold;

    IF v_js IS NOT NULL AND v_js >= v_js_threshold AND v_max_pred_risk IS NOT NULL AND v_max_pred_risk = 1 THEN
        v_pre_alert := 100;
    ELSE
        v_pre_alert := 0;
    END IF;

    -- 10. Поиск совпадающего пред-инцидентного профиля
    v_matched_id := find_matching_pre_incident_profile(
        v_current_metrics.state_histogram,
        0.05,
        100
    );

    -- 11. Формируем отчёт
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

    v_report := array_append(v_report, format('  Предаварийный флаг (порог JS=%s): %s',
        round(v_js_threshold::numeric, 2)::text,
        CASE WHEN v_pre_alert = 100 THEN 'АКТИВИРОВАН (100)' ELSE 'НЕТ (0)' END));

    IF v_matched_id IS NOT NULL THEN
        v_report := array_append(v_report, format('  ⚠ Совпадение с пред-инцидентным профилем (ID=%s)', v_matched_id));
    ELSE
        v_report := array_append(v_report, '  Совпадений с пред-инцидентными профилями не найдено.');
    END IF;

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

    -- 12. Сохраняем результат в profile_comparison_log
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
        'js_threshold_used', v_js_threshold
    );

    INSERT INTO profile_comparison_log (
        created_at,
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
        matched_pre_incident_id
    ) VALUES (
        v_now,
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
        v_matched_id
    );

    RETURN v_report;
END;
$$;

COMMENT ON FUNCTION compare_profiles_at IS
'Сравнивает профили для заданного момента времени (исторического) с использованием фиксированного эталонного окна из incident_free_window_current или profile_aggregated (baseline). Если эталон отсутствует или не подходит, возвращает статус NO_BASELINE. Сохраняет результат в profile_comparison_log.';

-- =============================================================================
-- Функция: fill_profile_comparison_historically
-- Назначение: заполняет таблицу profile_comparison_log за исторический период,
--             используя compare_profiles_at для каждой минуты.
-- Параметры:
--   p_start           TIMESTAMPTZ – начало периода (если NULL – берётся training_start_time из markov_config)
--   p_end             TIMESTAMPTZ – конец периода (если NULL – берётся training_end_time из markov_config)
--   p_step_minutes    INT         – шаг в минутах (по умолчанию 1)
--   p_window_minutes  INT         – длина окна для сравнения (по умолчанию 60)
-- Возвращает: TEXT – отчёт о выполненной работе (количество обработанных минут).
-- =============================================================================
CREATE OR REPLACE FUNCTION fill_profile_comparison_historically(
    p_start           TIMESTAMPTZ DEFAULT NULL,
    p_end             TIMESTAMPTZ DEFAULT NULL,
    p_step_minutes    INT         DEFAULT 1,
    p_window_minutes  INT         DEFAULT 60,
    p_lookback_days   INT         DEFAULT 7,
    p_clean           BOOLEAN     DEFAULT TRUE
)
RETURNS TEXT
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
    v_start TIMESTAMPTZ;
    v_end   TIMESTAMPTZ;
    v_ts    TIMESTAMPTZ;
    v_total_minutes BIGINT;
    v_processed     BIGINT := 0;
    v_last_percent  INT := -1;
    v_current_percent INT;
    v_result        TEXT;
    v_step_interval INTERVAL := (p_step_minutes || ' minutes')::INTERVAL;
BEGIN
    -- 1. Определение границ периода
    IF p_start IS NULL THEN
        SELECT training_start_time INTO v_start FROM markov_config LIMIT 1;
        IF v_start IS NULL THEN
            RETURN 'Ошибка: training_start_time не задан в markov_config, и не передан p_start.';
        END IF;
    ELSE
        v_start := p_start;
    END IF;

    IF p_end IS NULL THEN
        SELECT training_end_time INTO v_end FROM markov_config LIMIT 1;
        IF v_end IS NULL THEN
            RETURN 'Ошибка: training_end_time не задан в markov_config, и не передан p_end.';
        END IF;
    ELSE
        v_end := p_end;
    END IF;

    IF v_start > v_end THEN
        RETURN format('Ошибка: начальная дата (%s) позже конечной (%s).', v_start, v_end);
    END IF;

    -- Округление до минут
    v_start := date_trunc('minute', v_start);
    v_end   := date_trunc('minute', v_end);

    -- 2. Очистка старых данных за этот период (если включена)
    IF p_clean THEN
        DELETE FROM profile_comparison_log
        WHERE created_at BETWEEN v_start AND v_end;
        RAISE NOTICE 'Удалены существующие записи за период с % по %', v_start, v_end;
    END IF;

    v_total_minutes := EXTRACT(EPOCH FROM (v_end - v_start)) / 60 + 1;
    RAISE NOTICE 'Начало исторического заполнения profile_comparison_log с % по % (шаг %s мин, всего %s минут)',
                 v_start, v_end, p_step_minutes, v_total_minutes;

    v_ts := v_start;
    WHILE v_ts <= v_end LOOP
        -- Вызов сравнения профилей с передачей lookback_days
        BEGIN
            PERFORM compare_profiles_at(v_ts, p_window_minutes, p_lookback_days);
        EXCEPTION WHEN OTHERS THEN
            RAISE WARNING 'Ошибка на %: %', v_ts, SQLERRM;
        END;

        v_processed := v_processed + 1;
        v_ts := v_ts + v_step_interval;

        -- Логирование прогресса каждые 1%
        v_current_percent := floor((v_processed::NUMERIC / v_total_minutes) * 100);
        IF v_current_percent > v_last_percent THEN
            RAISE NOTICE 'Прогресс: % % (обработано % из % минут)',
                         v_current_percent, '%', v_processed, v_total_minutes;
            v_last_percent := v_current_percent;
        END IF;
    END LOOP;

    RAISE NOTICE 'Заполнение завершено. Обработано % минут.', v_processed;
    RETURN format('Историческое заполнение profile_comparison_log завершено. Обработано %s минут.', v_processed);
END;
$$;

COMMENT ON FUNCTION fill_profile_comparison_historically IS
'Заполняет profile_comparison_log за исторический период, используя compare_profiles_at для каждой минуты. Границы периода берутся из markov_config.training_start_time/training_end_time, если не переданы явно.';

-- =============================================================================
-- Пример вызова после обучения:
-- SELECT fill_profile_comparison_historically();
-- или с явным указанием периода:
-- SELECT fill_profile_comparison_historically('2026-08-01 00:00:00', '2026-08-20 00:00:00', 5, 60);
-- =============================================================================


-- =============================================================================
-- Функция: generate_profile_comparison_report
-- Назначение: формирует аналитический отчёт по таблице profile_comparison_log
--             за указанный период (по умолчанию – последний месяц).
-- Параметры:
--   p_start TIMESTAMPTZ – начало периода (по умолч. now() - interval '1 month')
--   p_end   TIMESTAMPTZ – конец периода (по умолч. now())
-- Возвращает: TEXT[] – массив строк с отформатированным отчётом.
-- Используемые таблицы: profile_comparison_log, performance_incident.
-- =============================================================================
-- =============================================================================
-- Функция: generate_profile_comparison_report (исправленная)
-- Назначение: формирует аналитический отчёт по таблице profile_comparison_log
--             за указанный период (по умолчанию – последний месяц).
-- Параметры:
--   p_start TIMESTAMPTZ – начало периода (по умолч. now() - interval '1 month')
--   p_end   TIMESTAMPTZ – конец периода (по умолч. now())
-- Возвращает: TEXT[] – массив строк с отформатированным отчётом.
-- =============================================================================
/*
psql -d expecto_db -U expecto_user -c 'select unnest(generate_profile_comparison_report())' > /tmp/generate_profile_comparison_report.txt
*/
CREATE OR REPLACE FUNCTION generate_profile_comparison_report(
    p_start TIMESTAMPTZ DEFAULT now() - INTERVAL '1 month',
    p_end   TIMESTAMPTZ DEFAULT now()
)
RETURNS TEXT[]
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_report TEXT[] := '{}';
    v_total BIGINT;
    v_status_counts JSONB;
    v_js_stats RECORD;
    v_daily_stats RECORD;
    v_incident_stats RECORD;
    v_top_records RECORD;
    v_line TEXT;
    v_sep CONSTANT TEXT := '--------------------------------------------------------------------';
    v_header TEXT := '=== ОТЧЁТ ПО СРАВНЕНИЮ ПРОФИЛЕЙ (profile_comparison_log) ===';
BEGIN
    -- Проверка корректности интервала
    IF p_start > p_end THEN
        RETURN ARRAY['Ошибка: начальная дата позже конечной.'];
    END IF;

    -- Заголовок отчёта
    v_report := array_append(v_report, v_header);
    v_report := array_append(v_report, format('Период: %s – %s',
        to_char(p_start, 'YYYY-MM-DD HH24:MI'),
        to_char(p_end, 'YYYY-MM-DD HH24:MI')));
    v_report := array_append(v_report, format('Дата формирования: %s',
        to_char(now(), 'YYYY-MM-DD HH24:MI')));
    v_report := array_append(v_report, '');

    -- ========================================================================
    -- 1. Общая статистика и распределение по статусам
    -- ========================================================================
    SELECT COUNT(*) INTO v_total FROM profile_comparison_log
    WHERE created_at BETWEEN p_start AND p_end;

    v_report := array_append(v_report, '--- ОБЩАЯ СТАТИСТИКА ---');
    v_report := array_append(v_report, format('Всего записей: %s', v_total));

    IF v_total = 0 THEN
        v_report := array_append(v_report, 'Нет данных за указанный период.');
        v_report := array_append(v_report, '=== КОНЕЦ ОТЧЁТА ===');
        RETURN v_report;
    END IF;

    -- Распределение по статусам
    SELECT jsonb_object_agg(status, count) INTO v_status_counts
    FROM (
        SELECT COALESCE(status, 'NULL') AS status, COUNT(*) AS count
        FROM profile_comparison_log
        WHERE created_at BETWEEN p_start AND p_end
        GROUP BY status
    ) t;

    v_report := array_append(v_report, 'Распределение по статусам:');
    FOR v_line IN
        SELECT format('  %s: %s (%s%%)',
            key,
            value::TEXT,
            round((value::NUMERIC / v_total * 100)::NUMERIC, 1)::TEXT)
        FROM jsonb_each_text(v_status_counts)
        ORDER BY key
    LOOP
        v_report := array_append(v_report, v_line);
    END LOOP;

    -- ========================================================================
    -- 2. Статистика JS-дивергенции (только не NULL)
    -- ========================================================================
    SELECT
        COUNT(*) AS cnt,
        COALESCE(AVG(js_divergence), 0) AS avg_js,
        COALESCE(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY js_divergence), 0) AS median_js,
        COALESCE(MIN(js_divergence), 0) AS min_js,
        COALESCE(MAX(js_divergence), 0) AS max_js,
        COALESCE(PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY js_divergence), 0) AS p90_js
    INTO v_js_stats
    FROM profile_comparison_log
    WHERE created_at BETWEEN p_start AND p_end
      AND js_divergence IS NOT NULL;

    v_report := array_append(v_report, '');
    v_report := array_append(v_report, '--- СТАТИСТИКА JS-ДИВЕРГЕНЦИИ (по не-NULL значениям) ---');
    v_report := array_append(v_report, format('  Количество записей с JS: %s', v_js_stats.cnt));
    v_report := array_append(v_report, format('  Среднее: %s', round(v_js_stats.avg_js::NUMERIC, 4)::TEXT));
    v_report := array_append(v_report, format('  Медиана: %s', round(v_js_stats.median_js::NUMERIC, 4)::TEXT));
    v_report := array_append(v_report, format('  Минимум: %s', round(v_js_stats.min_js::NUMERIC, 4)::TEXT));
    v_report := array_append(v_report, format('  Максимум: %s', round(v_js_stats.max_js::NUMERIC, 4)::TEXT));
    v_report := array_append(v_report, format('  90-й процентиль: %s', round(v_js_stats.p90_js::NUMERIC, 4)::TEXT));

    -- ========================================================================
    -- 3. Динамика по дням
    -- ========================================================================
    v_report := array_append(v_report, '');
    v_report := array_append(v_report, '--- ДИНАМИКА ПО ДНЯМ ---');
    v_report := array_append(v_report, 'Дата       | Кол-во | Средняя JS | Доля CRITICAL');
    v_report := array_append(v_report, '------------+--------+------------+---------------');
    FOR v_daily_stats IN
        SELECT
            created_at::DATE AS day,
            COUNT(*) AS total,
            COALESCE(AVG(js_divergence), 0) AS avg_js,
            COUNT(*) FILTER (WHERE status = 'CRITICAL')::NUMERIC / NULLIF(COUNT(*), 0) * 100 AS pct_critical
        FROM profile_comparison_log
        WHERE created_at BETWEEN p_start AND p_end
        GROUP BY day
        ORDER BY day
    LOOP
        v_report := array_append(v_report,
            format('%s | %6s | %10s | %6s%%',
                v_daily_stats.day::TEXT,
                v_daily_stats.total::TEXT,
                round(v_daily_stats.avg_js::NUMERIC, 4)::TEXT,
                round(COALESCE(v_daily_stats.pct_critical, 0)::NUMERIC, 1)::TEXT
            )
        );
    END LOOP;

    -- ========================================================================
    -- 4. Связь с инцидентами производительности
    -- ========================================================================
    v_report := array_append(v_report, '');
    v_report := array_append(v_report, '--- СВЯЗЬ С ИНЦИДЕНТАМИ ---');
    WITH incidents AS (
        SELECT id, start_timepoint
        FROM performance_incident
        WHERE start_timepoint BETWEEN p_start AND p_end
    ),
    prior_status AS (
        SELECT
            i.id,
            i.start_timepoint,
            (
                SELECT status
                FROM profile_comparison_log p
                WHERE p.created_at < i.start_timepoint
                  AND p.created_at >= i.start_timepoint - INTERVAL '30 minutes'
                ORDER BY p.created_at DESC
                LIMIT 1
            ) AS last_status
        FROM incidents i
    )
    SELECT
        COUNT(*) AS total_incidents,
        COUNT(*) FILTER (WHERE last_status = 'CRITICAL') AS with_critical,
        COUNT(*) FILTER (WHERE last_status = 'WARNING') AS with_warning,
        COUNT(*) FILTER (WHERE last_status = 'NORMAL') AS with_normal,
        COUNT(*) FILTER (WHERE last_status IS NULL) AS no_status
    INTO v_incident_stats
    FROM prior_status;

    v_report := array_append(v_report, format('Всего инцидентов за период: %s', v_incident_stats.total_incidents));
    v_report := array_append(v_report, format('  Предшествовал статус CRITICAL (в течение 30 мин): %s (%s%%)',
        v_incident_stats.with_critical,
        CASE WHEN v_incident_stats.total_incidents > 0 
             THEN round((v_incident_stats.with_critical::NUMERIC / v_incident_stats.total_incidents * 100)::NUMERIC, 1)::TEXT 
             ELSE '0' END));
    v_report := array_append(v_report, format('  Предшествовал статус WARNING: %s (%s%%)',
        v_incident_stats.with_warning,
        CASE WHEN v_incident_stats.total_incidents > 0 
             THEN round((v_incident_stats.with_warning::NUMERIC / v_incident_stats.total_incidents * 100)::NUMERIC, 1)::TEXT 
             ELSE '0' END));
    v_report := array_append(v_report, format('  Предшествовал статус NORMAL: %s (%s%%)',
        v_incident_stats.with_normal,
        CASE WHEN v_incident_stats.total_incidents > 0 
             THEN round((v_incident_stats.with_normal::NUMERIC / v_incident_stats.total_incidents * 100)::NUMERIC, 1)::TEXT 
             ELSE '0' END));
    v_report := array_append(v_report, format('  Нет предшествующей записи: %s (%s%%)',
        v_incident_stats.no_status,
        CASE WHEN v_incident_stats.total_incidents > 0 
             THEN round((v_incident_stats.no_status::NUMERIC / v_incident_stats.total_incidents * 100)::NUMERIC, 1)::TEXT 
             ELSE '0' END));

    -- ========================================================================
    -- 5. Топ-5 записей с наибольшей JS-дивергенцией
    -- ========================================================================
    v_report := array_append(v_report, '');
    v_report := array_append(v_report, '--- ТОП-5 ЗАПИСЕЙ С НАИБОЛЬШЕЙ JS-ДИВЕРГЕНЦИЕЙ ---');
    v_report := array_append(v_report, 'Время | Статус | JS | Текущее окно');
    FOR v_top_records IN
        SELECT
            created_at,
            status,
            js_divergence,
            current_window_start,
            current_window_end
        FROM profile_comparison_log
        WHERE created_at BETWEEN p_start AND p_end
          AND js_divergence IS NOT NULL
        ORDER BY js_divergence DESC
        LIMIT 5
    LOOP
        v_report := array_append(v_report,
            format('%s | %s | %s | %s – %s',
                to_char(v_top_records.created_at, 'YYYY-MM-DD HH24:MI'),
                COALESCE(v_top_records.status, 'NULL'),
                round(v_top_records.js_divergence::NUMERIC, 4)::TEXT,
                to_char(v_top_records.current_window_start, 'HH24:MI'),
                to_char(v_top_records.current_window_end, 'HH24:MI')
            )
        );
    END LOOP;

    -- ========================================================================
    -- 6. Итоговый вывод и рекомендации
    -- ========================================================================
    v_report := array_append(v_report, '');
    v_report := array_append(v_report, '--- ИТОГОВЫЙ ВЫВОД ---');
    DECLARE
        v_critical_pct NUMERIC;
        v_js_avg NUMERIC;
    BEGIN
        SELECT
            COUNT(*) FILTER (WHERE status = 'CRITICAL')::NUMERIC / NULLIF(COUNT(*), 0) * 100,
            AVG(js_divergence)
        INTO v_critical_pct, v_js_avg
        FROM profile_comparison_log
        WHERE created_at BETWEEN p_start AND p_end;

        IF v_critical_pct > 10 THEN
            v_report := array_append(v_report, '⚠ Высокая доля CRITICAL (>10%) – система часто значительно отклоняется от эталона.');
        ELSIF v_critical_pct > 5 THEN
            v_report := array_append(v_report, '⚠ Умеренная доля CRITICAL (5-10%) – рекомендуется усилить мониторинг.');
        ELSE
            v_report := array_append(v_report, '✔ Доля CRITICAL низкая (<5%) – профили в основном стабильны.');
        END IF;

        IF v_js_avg > 0.2 THEN
            v_report := array_append(v_report, '⚠ Средняя JS-дивергенция >0.2 – заметные отклонения от эталона.');
        ELSIF v_js_avg > 0.1 THEN
            v_report := array_append(v_report, '⚠ Средняя JS-дивергенция 0.1-0.2 – умеренные отклонения.');
        ELSE
            v_report := array_append(v_report, '✔ Средняя JS-дивергенция <0.1 – профили близки к эталону.');
        END IF;

        IF v_incident_stats.total_incidents > 0
           AND (v_incident_stats.with_critical::NUMERIC / v_incident_stats.total_incidents) > 0.3 THEN
            v_report := array_append(v_report, '⚠ Более 30% инцидентов предваряются статусом CRITICAL – сильная связь.');
        END IF;
    END;

    v_report := array_append(v_report, '');
    v_report := array_append(v_report, '=== КОНЕЦ ОТЧЁТА ===');

    RETURN v_report;
END;
$$;

COMMENT ON FUNCTION generate_profile_comparison_report(TIMESTAMPTZ, TIMESTAMPTZ) IS
'Формирует детализированный отчёт по таблице profile_comparison_log за указанный период.
Включает распределение статусов, статистику JS-дивергенции, динамику по дням, связь с инцидентами,
топ-5 аномальных записей и итоговый вывод с рекомендациями.
По умолчанию период – последний месяц.';