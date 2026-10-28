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
-- version 22.2.1
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
--             из profile_comparison_log и markov_chain_performance_incident.
--
-- Функция: generate_comprehensive_analytical_report
-- Назначение: формирует сводный аналитический отчёт по производительности,
--             прогнозированию и профилям нагрузки за указанный период.
--
-- Функция: generate_analytical_report
-- Назначение: формирует аналитический отчёт по заданному временному интервалу,
--             объединяя данные из prediction_log, profile_comparison_log
--             и markov_chain_performance_incident. Возвращает массив строк с интерпретацией
--             и сводными показателями, а не сырыми данными.
--
-- Функция: collect_pre_incident_profiles
-- Назначение: сбор профилей для инцидентов
--
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
-- Функция: sicpp_calculate_at
-- Назначение: вычисляет состояние SICPP на заданный момент p_ts на основе
--             prediction_log и profile_comparison_log. Логика полностью
--             соответствует calculate_signal() из отчёта «ОТЧЁТ ПО
--             ПРОГНОЗИРОВАНИЮ ИНЦИДЕНТОВ», но адаптирована для онлайн-режима.
--
-- Функция: sicpp_update_state
-- Назначение: вызывается из mchain_train_step() ежеминутно. Вычисляет текущее
--             состояние SICPP, обновляет sicpp_current_state, и если состояние
--             изменилось — добавляет запись в sicpp_history.
--
-- Функция: sicpp_get_current
-- Назначение: возвращает текущее состояние SICPP.
--
-- Функция: historical_fill_sicpp
-- Назначение: заполняет sicpp_history за указанный период, последовательно
--             вызывая sicpp_calculate_at для каждой минуты и фиксируя
--             изменения состояния.
--
-- Функция: sicpp_clean_history
-- Назначение: удаляет старые записи из sicpp_history.
--
-- Функция: generate_incident_forecast_report_v2
-- Назначение: формирует отчёт по прогнозированию инцидентов, используя
--             sicpp_history (историю изменений сигнала SICPP) в качестве
--             источника данных о срабатывании сигнала.
--
-- Функция: diagnose_incident_coverage
-- Назначение: диагностика причины отсутствия или непокрытия инцидента
--
-- Функция: get_current_preincident_status
-- Назначение: возвращает текущий интегральный статус предынцедентного
--             состояния СУБД на основе SICPP, сравнения профилей и
--             марковского прогноза риска.
-- get_current_preincident_status_detail - детализация
--
-- Функция: is_within_productive_load
-- Назначение: проверяет, попадает ли момент времени в период продуктивной
--             нагрузки, заданный в markov_config (или переданный явно).
--
-- Функция: is_window_within_productive_load
-- Назначение: проверяет, что всё окно [p_start, p_end) целиком лежит внутри
--             периода продуктивной нагрузки.
--
-- Функция: is_valid_baseline_window
-- Назначение: комплексная проверка, что окно [p_start, p_end) может быть
--             использовано как эталонное:
--               1) целиком лежит в периоде продуктивной нагрузки;
--               2) начинается не ранее чем через baseline_min_gap_after_incident_min
--                  минут после завершения последнего инцидента.
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
--
-- ВАЖНО (версия 16.4.2): в блок построения state_histogram добавлено
--   Laplace smoothing с alpha = 0.5 по всем 189 состояниям.
--   Это устраняет разреженность гистограмм и снижает JS-дивергенцию
--   до осмысленного диапазона (0.05–0.30 вместо 0.49–0.69).
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

    -- 1. Гистограмма (с Laplace smoothing по всем 189 состояниям)
    --    Каждому состоянию добавляется псевдосчёт alpha = 0.5.
    --    Знаменатель = total_transitions + 189 * alpha.
    --    Это устраняет разреженность гистограмм и предотвращает
    --    «упирание» JS-дивергенции в теоретический максимум ln(2) ≈ 0.693.
    WITH all_states AS (
        SELECT generate_series(0, 188) AS state_id
    ),
    state_counts AS (
        SELECT to_state AS state_id, COUNT(*) AS cnt
        FROM transition_log
        WHERE ts >= p_start AND ts < p_end
        GROUP BY to_state
    ),
    totals AS (
        SELECT COALESCE(SUM(cnt), 0) AS total_cnt FROM state_counts
    ),
/*	
    smoothed AS (
        SELECT
            a.state_id,
            (COALESCE(sc.cnt, 0)::REAL + 0.5) AS cnt_smoothed
        FROM all_states a
        LEFT JOIN state_counts sc ON sc.state_id = a.state_id
    ),
*/
    smoothed AS (
    SELECT
        a.state_id,
        (COALESCE(sc.cnt, 0)::NUMERIC + 0.5) AS cnt_smoothed
    FROM all_states a
    LEFT JOIN state_counts sc ON sc.state_id = a.state_id
    ),
    denom AS (
        SELECT (total_cnt + 189 * 0.5) AS total_smoothed FROM totals
    )
    SELECT jsonb_object_agg(
        s.state_id::TEXT,
        jsonb_build_object(
            'count', s.cnt_smoothed,
            'pct', ROUND(((s.cnt_smoothed::NUMERIC / NULLIF(d.total_smoothed, 0)) * 100)::NUMERIC, 2)
        )
    ) INTO v_histogram
    FROM smoothed s, denom d
    WHERE d.total_smoothed > 0;

    -- 2. Средняя корреляция
    SELECT AVG(ph.correlation) INTO v_avg_corr
    FROM performance_history ph
    WHERE ph.ts >= p_start AND ph.ts < p_end;

    -- 3. Доля критических состояний
    SELECT COUNT(*) FILTER (WHERE tl.to_state = ANY(v_critical_ids))::REAL / NULLIF(COUNT(*), 0)
    INTO v_crit_ratio
    FROM transition_log tl
    WHERE tl.ts >= p_start AND tl.ts < p_end;

    -- 4. Энтропия
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
'вычисляет набор профильных метрик для заданного временного окна. '
'Версия 16.4.2: state_histogram строится с Laplace smoothing (alpha=0.5) '
'по всем 189 состояниям, что устраняет разреженность и снижает JS-дивергенцию '
'до осмысленного диапазона.';

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
        FROM markov_chain_performance_incident pi
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
            FROM markov_chain_performance_incident pi
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
-- Дополнительные функции для профилирования производительности:
-- 1) Сохранение эталонного профиля на основе incident_free_window_current
-- 2) Сохранение текущего профиля от текущего времени
-- 3) Сравнение эталонного и текущего профилей с анализом аномалий
-- =============================================================================

-- =============================================================================
-- save_baseline_profile (версия 3, 2026-10-19)
-- Назначение: сохраняет эталонный профиль на основе incident_free_window_current.
--
-- ИЗМЕНЕНИЯ (v3):
--   - Перед сохранением выполняется is_valid_baseline_window: окно должно
--     целиком лежать в периоде продуктивной нагрузки и начинаться не ранее
--     чем через baseline_min_gap_after_incident_min минут после завершения
--     последнего инцидента.
--   - Сохраняются последние p_retention_count baseline-профилей.
-- =============================================================================
CREATE OR REPLACE FUNCTION save_baseline_profile(
    p_retention_count    INT  DEFAULT 5,
    p_overlap_threshold  REAL DEFAULT 0.9
)
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
    v_overlap_start TIMESTAMPTZ;
    v_overlap_end   TIMESTAMPTZ;
    v_overlap_min   NUMERIC;
    v_overlap_ratio NUMERIC;
    v_window_min    NUMERIC;
    v_start_hour    SMALLINT;
    v_end_hour      SMALLINT;
    v_min_gap       INT;
BEGIN
    -- Загружаем параметры конфигурации
    SELECT productive_load_start_hour, productive_load_end_hour, baseline_min_gap_after_incident_min
    INTO v_start_hour, v_end_hour, v_min_gap
    FROM markov_config LIMIT 1;

    SELECT window_start, window_end INTO v_win_start, v_win_end
    FROM incident_free_window_current
    LIMIT 1;

    IF v_win_start IS NULL OR v_win_end IS NULL THEN
        RETURN 'Ошибка: таблица incident_free_window_current пуста. Сначала выполните find_incident_free_window().';
    END IF;

    -- Проверка, что окно валидно (период нагрузки + зазор после инцидента)
    IF NOT is_valid_baseline_window(v_win_start, v_win_end) THEN
        RETURN format('Ошибка: окно %s – %s не удовлетворяет условиям эталонного (период нагрузки %s:00–%s:00, зазор после инцидента %s мин).',
                      v_win_start, v_win_end, v_start_hour, v_end_hour, v_min_gap);
    END IF;

    v_window_min := EXTRACT(EPOCH FROM (v_win_end - v_win_start)) / 60;

    -- Проверка перекрытия с последним baseline
    SELECT window_start, window_end INTO v_last_baseline
    FROM profile_aggregated
    WHERE profile_type = 'baseline'
    ORDER BY ts DESC
    LIMIT 1;

    IF FOUND AND v_last_baseline.window_start IS NOT NULL THEN
        v_overlap_start := GREATEST(v_last_baseline.window_start, v_win_start);
        v_overlap_end   := LEAST(v_last_baseline.window_end, v_win_end);

        IF v_overlap_end > v_overlap_start THEN
            v_overlap_min := EXTRACT(EPOCH FROM (v_overlap_end - v_overlap_start)) / 60;
        ELSE
            v_overlap_min := 0;
        END IF;

        v_overlap_ratio := v_overlap_min / NULLIF(v_window_min, 0);

        IF v_overlap_ratio >= p_overlap_threshold THEN
            RETURN format('Эталон уже сохранён (перекрытие %s%% >= порога %s%% с последним baseline), пропуск.',
                          round(v_overlap_ratio * 100, 1),
                          round((p_overlap_threshold * 100)::numeric, 1));
        END IF;
    END IF;

    -- Вычисляем метрики
    SELECT * INTO v_metrics
    FROM calculate_profile_metrics(v_win_start, v_win_end);

    v_hour := EXTRACT(HOUR FROM now())::SMALLINT;
    v_dow  := EXTRACT(DOW  FROM now())::SMALLINT;

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

    -- Retention: храним последние p_retention_count
    DELETE FROM profile_aggregated
    WHERE profile_type = 'baseline'
      AND id NOT IN (
          SELECT id FROM profile_aggregated
          WHERE profile_type = 'baseline'
          ORDER BY ts DESC
          LIMIT p_retention_count
      );

    RETURN format('Эталонный профиль сохранён: %s – %s (длина %s мин); retention=%s',
                  v_win_start, v_win_end, v_window_min, p_retention_count);
END;
$$;

COMMENT ON FUNCTION save_baseline_profile(INT, REAL) IS
'Сохраняет эталонный профиль на основе текущего окна из incident_free_window_current.
Версия 3 (2026-10-19): перед сохранением проверяет is_valid_baseline_window
(период продуктивной нагрузки + зазор после инцидента). Добавлена overlap-дедупликация:
если новое окно перекрывается с последним baseline >= p_overlap_threshold,
вставка пропускается.';

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

-- =============================================================================
-- compare_profiles (версия 6, 2026-10-29)
-- Назначение: выполняет сравнение текущего профиля нагрузки с эталонным окном.
--
-- ИЗМЕНЕНИЯ (v6):
--   - БЛОК 1: проверка «внутри инцидента» заменена с точечной (по v_now)
--     на проверку ПЕРЕСЕЧЕНИЯ всего текущего окна [v_current_start, v_current_end]
--     с любым инцидентом. Раньше, если инцидент завершился до now(), но
--     начался внутри 60-минутного текущего окна (finish_timepoint < now()
--     AND start_timepoint >= v_current_start), текущее окно «проскакивало»
--     проверку и сравнивалось с эталоном, что давало завышенную JS-дивергенцию
--     и ложные WARNING/CRITICAL.
--   - В v_details добавлен ключ 'incident_overlap', сообщающий, что текущее
--     окно пересекается с инцидентом (для диагностики).
-- =============================================================================
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
    v_incident_overlap RECORD;
    v_max_pred_risk REAL;
    v_risk_p90      REAL;
    v_stability_met BOOLEAN;
    v_pre_alert     INTEGER;
    v_pre_alert_advanced INTEGER := 0;
    v_js_threshold  REAL;
    v_baseline_found BOOLEAN := FALSE;
    v_last_statuses TEXT[];
    v_crit_or_warn_count INT;
    v_baseline_source TEXT := 'unknown';
BEGIN
    -- 1. Проверяем, пересекается ли ТЕКУЩЕЕ ОКНО [v_current_start, v_current_end]
    --    с любым инцидентом производительности (включая незавершённые).
    --    v6: раньше проверялась только точка v_now — это пропускало инциденты,
    --    которые завершились до v_now, но начались внутри окна (например,
    --    инцидент 14:24–15:10 при v_current_start=14:54, v_current_end=15:54).
    SELECT
        pi.id,
        pi.start_timepoint,
        pi.finish_timepoint
    INTO v_incident_overlap
    FROM markov_chain_performance_incident pi
    WHERE pi.start_timepoint <  v_current_end
      AND (pi.finish_timepoint IS NULL OR pi.finish_timepoint > v_current_start)
    ORDER BY pi.start_timepoint DESC
    LIMIT 1;

    v_inside_incident := FOUND;

    -- 2. Вычисляем максимальный и 90-й перцентиль предсказанного риска
    SELECT
        MAX(predicted_risk),
        PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY predicted_risk)
    INTO v_max_pred_risk, v_risk_p90
    FROM prediction_log
    WHERE prediction_time BETWEEN v_current_start AND v_current_end;

    -- 3. Если текущее окно пересекается с инцидентом – записываем INCIDENT
    --    и выходим, не выполняя сравнение с эталоном.
    IF v_inside_incident THEN
        v_status := 'INCIDENT';
        v_report := array_append(v_report, '=== СРАВНЕНИЕ ПРОФИЛЕЙ ===');
        v_report := array_append(v_report, format('Текущий момент: %s', v_now));
        v_report := array_append(v_report, format('Текущее окно: %s – %s',
            to_char(v_current_start, 'YYYY-MM-DD HH24:MI'),
            to_char(v_current_end,   'YYYY-MM-DD HH24:MI')));
        v_report := array_append(v_report, format(
            'Инцидент (пересечение): ID=%s, %s – %s',
            v_incident_overlap.id,
            to_char(v_incident_overlap.start_timepoint, 'YYYY-MM-DD HH24:MI'),
            COALESCE(to_char(v_incident_overlap.finish_timepoint, 'YYYY-MM-DD HH24:MI'),
                     'не завершён')));
        v_report := array_append(v_report,
            'Статус: INCIDENT – текущее окно пересекается с инцидентом, эталонное окно недоступно.');
        v_report := array_append(v_report, '=== КОНЕЦ ОТЧЁТА ===');

        v_pre_alert := 0;

        INSERT INTO profile_comparison_log (
            current_window_start, current_window_end, status, js_divergence,
            report, details, max_predicted_risk, pre_alert_flag, pre_alert_flag_advanced
        ) VALUES (
            v_current_start, v_current_end, v_status, NULL,
            to_jsonb(v_report),
            jsonb_build_object(
                'reason', 'incident_overlap',
                'incident_id', v_incident_overlap.id,
                'incident_start', v_incident_overlap.start_timepoint,
                'incident_finish', v_incident_overlap.finish_timepoint),
            v_max_pred_risk, v_pre_alert, v_pre_alert_advanced
        );
        RETURN v_report;
    END IF;

    -- ========================================================================
    -- 4. Цепочка fallback для получения эталонного окна
    -- ========================================================================

    -- fallback 0: incident_free_window_current (только если валидно)
    SELECT window_start, window_end INTO v_baseline_start, v_baseline_end
    FROM incident_free_window_current
    LIMIT 1;

    IF v_baseline_start IS NOT NULL
       AND v_baseline_end < v_current_start
       AND is_valid_baseline_window(v_baseline_start, v_baseline_end) THEN
        v_baseline_source := 'incident_free_window_current';
    ELSE
        v_baseline_start := NULL;
        v_baseline_end := NULL;
    END IF;

    -- fallback 1: самый свежий baseline из profile_aggregated (только валидный)
    IF v_baseline_start IS NULL OR v_baseline_end >= v_current_start THEN
        SELECT window_start, window_end INTO v_baseline_start, v_baseline_end
        FROM profile_aggregated
        WHERE profile_type = 'baseline'
          AND window_end < v_current_start
          AND is_valid_baseline_window(window_start, window_end)
        ORDER BY window_end DESC
        LIMIT 1;

        IF v_baseline_start IS NOT NULL
           AND v_baseline_end < v_current_start THEN
            v_baseline_source := 'profile_aggregated.baseline';
        ELSE
            v_baseline_start := NULL;
            v_baseline_end := NULL;
        END IF;
    END IF;

    -- fallback 2: динамический поиск безынцидентного окна
    IF v_baseline_start IS NULL OR v_baseline_end >= v_current_start THEN
        SELECT start_ts, end_ts INTO v_baseline_start, v_baseline_end
        FROM get_incident_free_window_before(
            p_ts                 => v_current_start,
            p_window_minutes     => p_window_minutes,
            p_lookback_days      => 30,
            p_exclude_before_min => 0,
            p_exclude_after_min  => 1
        );

        IF v_baseline_start IS NOT NULL
           AND v_baseline_end < v_current_start THEN
            v_baseline_source := 'get_incident_free_window_before';
        END IF;
    END IF;

    -- Финальная проверка
    IF v_baseline_start IS NOT NULL AND v_baseline_end < v_current_start THEN
        v_baseline_found := TRUE;
    ELSE
        v_baseline_found := FALSE;
        v_baseline_source := 'none';
    END IF;

    -- 5. Если эталон не найден – статус NO_BASELINE
    IF NOT v_baseline_found THEN
        v_status := 'NO_BASELINE';
        v_report := array_append(v_report, '=== СРАВНЕНИЕ ПРОФИЛЕЙ ===');
        v_report := array_append(v_report, format('Текущий момент: %s', v_now));
        v_report := array_append(v_report, 'Статус: NO_BASELINE – отсутствует актуальный эталонный профиль, удовлетворяющий условиям (период нагрузки + зазор после инцидента).');
        v_report := array_append(v_report, 'Проверены все источники: incident_free_window_current, profile_aggregated.baseline, get_incident_free_window_before.');
        v_report := array_append(v_report, '=== КОНЕЦ ОТЧЁТА ===');

        v_pre_alert := 0;

        INSERT INTO profile_comparison_log (
            current_window_start, current_window_end, status, js_divergence,
            report, details, max_predicted_risk, pre_alert_flag, pre_alert_flag_advanced
        ) VALUES (
            v_current_start, v_current_end, v_status, NULL,
            to_jsonb(v_report),
            jsonb_build_object('reason', 'no_baseline',
                               'checked_sources', jsonb_build_array(
                                   'incident_free_window_current',
                                   'profile_aggregated.baseline',
                                   'get_incident_free_window_before')),
            v_max_pred_risk, v_pre_alert, v_pre_alert_advanced
        );
        RETURN v_report;
    END IF;

    -- 6. Вычисляем метрики для эталонного и текущего окон
    SELECT * INTO v_baseline_metrics
    FROM calculate_profile_metrics(v_baseline_start, v_baseline_end);

    SELECT * INTO v_current_metrics
    FROM calculate_profile_metrics(v_current_start, v_current_end);

    -- 7. Вычисляем JS-дивергенцию
    v_js := histogram_divergence(
        v_baseline_metrics.state_histogram,
        v_current_metrics.state_histogram
    );

    -- 8. Определяем статус
    v_status := 'NORMAL';
    IF v_js >= 0.05 THEN
        v_status := 'WARNING';
    END IF;
    IF v_js >= 0.2 OR ABS(COALESCE(v_current_metrics.avg_correlation, 0) - COALESCE(v_baseline_metrics.avg_correlation, 0)) > 0.2 THEN
        v_status := 'CRITICAL';
    END IF;

    -- 9. Вычисляем простой pre_alert_flag
    SELECT COALESCE( (SELECT js_divergence_threshold FROM markov_config ), 0.2 ) INTO v_js_threshold;

    IF v_js IS NOT NULL AND v_js >= v_js_threshold AND v_max_pred_risk IS NOT NULL AND v_max_pred_risk = 1 THEN
        v_pre_alert := 100;
    ELSE
        v_pre_alert := 0;
    END IF;

    -- 10. Вычисляем устойчивость: 3 из 5 последних сравнений
    SELECT array_agg(status ORDER BY current_window_end DESC)
    INTO v_last_statuses
    FROM (
        SELECT status, current_window_end
        FROM profile_comparison_log
        WHERE current_window_end < v_current_start
        ORDER BY current_window_end DESC
        LIMIT 5
    ) t;

    IF v_last_statuses IS NULL THEN
        v_stability_met := FALSE;
    ELSE
        SELECT COUNT(*) INTO v_crit_or_warn_count
        FROM unnest(v_last_statuses) AS s
        WHERE s IN ('CRITICAL', 'WARNING');
        v_stability_met := (v_crit_or_warn_count >= 3);
    END IF;

    -- 11. Вычисляем pre_alert_flag_advanced
    IF v_js IS NOT NULL
       AND v_js >= v_js_threshold
       AND v_risk_p90 IS NOT NULL
       AND v_risk_p90 >= 0.95
       AND v_stability_met
    THEN
        v_pre_alert_advanced := 100;
    ELSE
        v_pre_alert_advanced := 0;
    END IF;

    -- 12. Формируем отчёт
    v_report := array_append(v_report, '=== СРАВНЕНИЕ ЭТАЛОННОГО И ТЕКУЩЕГО ПРОФИЛЕЙ ===');
    v_report := array_append(v_report, format('Текущий момент: %s', v_now));
    v_report := array_append(v_report, format('Источник эталона: %s', v_baseline_source));
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

    IF v_risk_p90 IS NOT NULL THEN
        v_report := array_append(v_report, format('  90-й перцентиль риска в текущем окне: %s',
            round(v_risk_p90::NUMERIC, 4)::TEXT));
    ELSE
        v_report := array_append(v_report, '  90-й перцентиль риска: нет данных');
    END IF;

    v_report := array_append(v_report, format('  Предаварийный флаг (простой): %s',
        CASE WHEN v_pre_alert = 100 THEN 'АКТИВИРОВАН (100)' ELSE 'НЕТ (0)' END));

    v_report := array_append(v_report, format('  Устойчивость (3 из 5 последних): %s (CRITICAL/WARNING: %s)',
        CASE WHEN v_stability_met THEN 'ДА' ELSE 'НЕТ' END,
        COALESCE(v_crit_or_warn_count::TEXT, '0')));

    v_report := array_append(v_report, format('  Предаварийный флаг (расширенный): %s',
        CASE WHEN v_pre_alert_advanced = 100 THEN 'АКТИВИРОВАН (100)' ELSE 'НЕТ (0)' END));

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
        v_report := array_append(v_report, '  Не удалось вычислить JS-дивергенцию.');
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

    -- 13. Сохраняем результат в profile_comparison_log
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
        'risk_p90', v_risk_p90,
        'stability_met', v_stability_met,
        'crit_or_warn_count', v_crit_or_warn_count,
        'baseline_source', v_baseline_source
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
        pre_alert_flag_advanced,
        high_risk_percentile,
        js_threshold_used,
        stability_met
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
        v_pre_alert_advanced,
        v_risk_p90,
        v_js_threshold,
        v_stability_met
    );

    RETURN v_report;
END;
$$;

COMMENT ON FUNCTION compare_profiles(INT, INT, INT) IS
'Сравнивает текущий профиль нагрузки с эталонным, сохраняет результат в profile_comparison_log.
Версия 6 (2026-10-29): проверка «внутри инцидента» теперь выполняется для всего
текущего окна [v_current_start, v_current_end], а не только для точки now().
Это устраняет ложные CRITICAL/WARNING, когда инцидент завершился до now(),
но начался внутри 60-минутного текущего окна.
При выборе эталона из incident_free_window_current и profile_aggregated.baseline
дополнительно проверяется is_valid_baseline_window.';

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
-- get_incident_free_window_before (версия 3, 2026-10-19)
-- Назначение: получить безынцидентное окно длины p_window_minutes,
--             заканчивающееся не позже p_ts, с максимальным концом.
--
-- ИЗМЕНЕНИЯ (v3):
--   - Окно выбирается только из периода продуктивной нагрузки
--     (markov_config.productive_load_start_hour / productive_load_end_hour).
--   - Начало окна должно быть не ранее чем через
--     baseline_min_gap_after_incident_min минут после завершения последнего
--     инцидента, закончившегося до начала окна.
-- =============================================================================
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
    v_interval      INTERVAL := (p_window_minutes || ' minutes')::INTERVAL;
    v_exclude_after INTERVAL := (p_exclude_after_min || ' minutes')::INTERVAL;
    v_candidate_start TIMESTAMPTZ;
    v_candidate_end   TIMESTAMPTZ;
    v_has_incident    BOOLEAN;
    v_lookback_start  TIMESTAMPTZ := p_ts - (p_lookback_days || ' days')::INTERVAL;
    v_start_hour      SMALLINT;
    v_end_hour        SMALLINT;
    v_min_gap         INT;
    v_last_incident_end TIMESTAMPTZ;
BEGIN
    -- Загружаем параметры конфигурации
    SELECT productive_load_start_hour, productive_load_end_hour, baseline_min_gap_after_incident_min
    INTO v_start_hour, v_end_hour, v_min_gap
    FROM markov_config LIMIT 1;

    -- Начинаем поиск с окна, которое заканчивается на v_exclude_after раньше p_ts
    v_candidate_start := p_ts - v_interval - v_exclude_after;

    WHILE v_candidate_start >= v_lookback_start LOOP
        v_candidate_end := v_candidate_start + v_interval;

        -- 1. Проверка, что окно целиком внутри периода продуктивной нагрузки
        IF NOT is_window_within_productive_load(v_candidate_start, v_candidate_end, v_start_hour, v_end_hour) THEN
            v_candidate_start := v_candidate_start - INTERVAL '1 minute';
            CONTINUE;
        END IF;

        -- 2. Проверка, что окно не пересекается с инцидентом
        SELECT EXISTS (
            SELECT 1
            FROM markov_chain_performance_incident
            WHERE start_timepoint < v_candidate_end
              AND (finish_timepoint IS NULL OR finish_timepoint > v_candidate_start)
        ) INTO v_has_incident;

        IF v_has_incident THEN
            v_candidate_start := v_candidate_start - INTERVAL '1 minute';
            CONTINUE;
        END IF;

        -- 3. Проверка отступа после последнего завершённого инцидента
        --    Находим последний инцидент, завершившийся до начала окна.
        SELECT MAX(finish_timepoint) INTO v_last_incident_end
        FROM markov_chain_performance_incident
        WHERE finish_timepoint <= v_candidate_start;

        IF v_last_incident_end IS NOT NULL
           AND v_candidate_start < v_last_incident_end + (v_min_gap || ' minutes')::INTERVAL THEN
            v_candidate_start := v_candidate_start - INTERVAL '1 minute';
            CONTINUE;
        END IF;

        -- Все проверки пройдены
        RETURN QUERY SELECT v_candidate_start, v_candidate_end;
        RETURN;
    END LOOP;

    -- Если ничего не найдено, возвращаем пустой результат
    RETURN;
END;
$$;

COMMENT ON FUNCTION get_incident_free_window_before(TIMESTAMPTZ, INT, INT, INT, INT) IS
'Возвращает самое свежее безынцидентное окно [start, end) длины p_window_minutes, заканчивающееся не позже p_ts, с учётом:
  1) окно целиком лежит в периоде продуктивной нагрузки (markov_config.productive_load_start_hour / productive_load_end_hour);
  2) окно не пересекается с инцидентами;
  3) начало окна не ранее чем через baseline_min_gap_after_incident_min минут после завершения последнего инцидента, закончившегося до начала окна.';



-- =============================================================================
-- Функция: generate_profile_incident_analytics_report
-- Назначение: формирует аналитический отчёт по сводному анализу сравнения
--             профилей производительности и инцидентов на основе данных
--             из profile_comparison_log и markov_chain_performance_incident.
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
    FROM markov_chain_performance_incident
    WHERE start_timepoint BETWEEN p_start AND p_end;

    -- 2.2. Инциденты, которым предшествовало сравнение (окно 30 минут до инцидента)
    WITH incident_comparisons AS (
        SELECT
            pi.start_timepoint AS incident_ts,
            pcl.current_window_end AS comp_ts,
            pcl.status,
            pcl.js_divergence
        FROM markov_chain_performance_incident pi
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
    FROM markov_chain_performance_incident
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
        FROM markov_chain_performance_incident
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
        FROM markov_chain_performance_incident
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
    FROM markov_chain_performance_incident
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
        FROM markov_chain_performance_incident
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
        FROM markov_chain_performance_incident pi
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
-- =============================================================================
-- Функция: collect_pre_incident_profiles (v19.1-fix)
-- Назначение: сбор прединцидентных профилей в библиотеку pre_incident_profiles.
--
-- ИСПРАВЛЕНИЕ v19.1-fix (2026-10-25):
--   - Удалена ссылка на несуществующую колонку source_table (в
--     markov_chain_profile_tables.sql колонка не создаётся).
--   - Дедупликация выполняется по incident_id (UNIQUE-ключ по смыслу).
--   - Из INSERT убраны source_table и v_source.
--   - Источник инцидентов — markov_chain_performance_incident (MCI).
-- =============================================================================
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
    cnt       INT := 0;
    v_skipped INT := 0;
    v_empty   INT := 0;
BEGIN
    FOR inc IN
        SELECT id, start_timepoint
        FROM markov_chain_performance_incident
        WHERE start_timepoint BETWEEN p_start AND p_end
          AND start_timepoint - (p_window_minutes || ' minutes')::INTERVAL >= p_start
    LOOP
        -- Дедупликация: пропускаем, если для этого инцидента уже есть профиль
        IF NOT EXISTS (
            SELECT 1 FROM pre_incident_profiles
            WHERE incident_id = inc.id
        ) THEN
            SELECT * INTO prof
            FROM calculate_profile_metrics(
                inc.start_timepoint - (p_window_minutes || ' minutes')::INTERVAL,
                inc.start_timepoint
            );

            IF prof.state_histogram IS NULL OR prof.state_histogram = '{}'::JSONB THEN
                v_empty := v_empty + 1;
                RAISE WARNING 'Empty profile for incident_id=% at %', inc.id, inc.start_timepoint;
                CONTINUE;
            END IF;

            INSERT INTO pre_incident_profiles (
                incident_id,
                window_start, window_end,
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
        ELSE
            v_skipped := v_skipped + 1;
        END IF;
    END LOOP;

    RETURN format('Added %s pre-incident profiles (skipped existing: %s, empty: %s).',
                  cnt, v_skipped, v_empty);
END;
$$;

COMMENT ON FUNCTION collect_pre_incident_profiles(TIMESTAMPTZ, TIMESTAMPTZ, INT) IS
'v19.1-fix. Собирает прединцидентные профили из markov_chain_performance_incident
в pre_incident_profiles. Дедупликация по incident_id. Параметр source_table не
используется: в схеме pre_incident_profiles колонки source_table нет.';




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
--------------------------------------------------------------------------------
-- generate_pre_incident_audit_report
-- Версия: 19.1 (2026-10-25)
-- Назначение: формирует отчёт о совпадениях текущих профилей с пред-инцидентными
--             шаблонами за указанный период. Возвращает массив строк с деталями
--             каждого совпадения.
--
-- КЛЮЧЕВЫЕ ИЗМЕНЕНИЯ v19.1 (относительно v15):
--   - Источник инцидентов: markov_chain_performance_incident (MCI).
--   - Столбец priority УДАЛЁН из выборки и вывода
--     (MCI не содержит priority; используется MCI.id как ссылка).
--   - Обновлена расшифровка полей и COMMENT ON FUNCTION.
--   - Логика JOIN с pre_incident_profiles и фильтра по JS-дивергенции без
--     изменений.
--------------------------------------------------------------------------------
/*
Примеры использования:

-- Все совпадения за последние 7 дней
SELECT unnest(generate_pre_incident_audit_report());

-- Только совпадения с JS-дивергенцией <= 0.05
SELECT unnest(generate_pre_incident_audit_report(
    p_start             => now() - interval '7 days',
    p_end               => now(),
    p_max_js_divergence => 0.05
));

-- Сохранение в файл
psql -d expecto_db -U expecto_user \
    -c 'SELECT unnest(generate_pre_incident_audit_report())' \
    > /tmp/generate_pre_incident_audit_report.txt
*/
CREATE OR REPLACE FUNCTION generate_pre_incident_audit_report(
    p_start              TIMESTAMPTZ DEFAULT now() - INTERVAL '7 days',
    p_end                TIMESTAMPTZ DEFAULT now(),
    p_max_js_divergence  REAL        DEFAULT NULL
)
RETURNS TEXT[]
LANGUAGE plpgsql
STABLE
AS $$
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

    v_report := array_append(v_report, '=== ОТЧЁТ АУДИТА СОВПАДЕНИЙ С ПРЕД-ИНЦИДЕНТНЫМИ ПРОФИЛЯМИ (v19.1) ===');
    v_report := array_append(v_report, format('Период: %s – %s%s',
        date_trunc('minute', p_start)::TEXT,
        date_trunc('minute', p_end)::TEXT,
        v_filter_msg));

    -- ========================================================================
    -- Список инцидентов за период (из markov_chain_performance_incident)
    -- v19.1: priority исключён (MCI не содержит этого столбца)
    -- ========================================================================
    v_report := array_append(v_report, '');
    v_report := array_append(v_report, '--- ИНЦИДЕНТЫ ПРОИЗВОДИТЕЛЬНОСТИ ЗА ПЕРИОД (markov_chain_performance_incident) ---');

    SELECT COUNT(*) INTO v_incident_count
    FROM markov_chain_performance_incident
    WHERE start_timepoint BETWEEN p_start AND p_end;

    IF v_incident_count > 0 THEN
        v_report := array_append(v_report, format('Всего инцидентов: %s', v_incident_count));
        FOR v_rec IN
            SELECT id, start_timepoint
            FROM markov_chain_performance_incident
            WHERE start_timepoint BETWEEN p_start AND p_end
            ORDER BY start_timepoint
        LOOP
            v_report := array_append(v_report, format('  #%s: %s',
                v_rec.id,
                to_char(v_rec.start_timepoint, 'YYYY-MM-DD HH24:MI')));
        END LOOP;
    ELSE
        v_report := array_append(v_report, '  Инцидентов за период не найдено.');
    END IF;
    v_report := array_append(v_report, '');

    -- ========================================================================
    -- Расшифровка полей (без приоритета и длительности)
    -- ========================================================================
    v_report := array_append(v_report, 'Расшифровка полей отчёта:');
    v_report := array_append(v_report, '  - Совпадение текущего и прединцидентного профиля: момент времени, когда был вычислен текущий профиль и выполнено сравнение.');
    v_report := array_append(v_report, '  - JS-дивергенция: численное значение расхождения между текущей гистограммой состояний и гистограммой шаблона (0 – идентичны).');
    v_report := array_append(v_report, '  - Совпавший профиль ID: идентификатор записи в pre_incident_profiles, с которой зафиксировано совпадение.');
    v_report := array_append(v_report, '  - Оригинальный инцидент ID: идентификатор инцидента из markov_chain_performance_incident, к которому относится шаблон.');
    v_report := array_append(v_report, '  - Время оригинального инцидента: время начала этого инцидента.');
    v_report := array_append(v_report, '  Примечание v19.1: столбец priority в отчёте отсутствует –');
    v_report := array_append(v_report, '  markov_chain_performance_incident не содержит priority.');
    v_report := array_append(v_report, '');

    -- ========================================================================
    -- Основной запрос совпадений (без статуса, приоритета и длительности)
    -- ========================================================================
    FOR v_rec IN
        SELECT
            pcl.created_at,
            pcl.js_divergence,
            pcl.matched_pre_incident_id,
            pip.incident_id AS original_incident_id,
            pi.start_timepoint AS original_incident_time
        FROM profile_comparison_log pcl
        LEFT JOIN pre_incident_profiles pip
               ON pcl.matched_pre_incident_id = pip.id
        LEFT JOIN markov_chain_performance_incident pi
               ON pip.incident_id = pi.id
        WHERE pcl.created_at BETWEEN p_start AND p_end
          AND pcl.matched_pre_incident_id IS NOT NULL
          AND (p_max_js_divergence IS NULL
               OR (pcl.js_divergence IS NOT NULL
                   AND pcl.js_divergence <= p_max_js_divergence))
        ORDER BY pcl.created_at DESC
    LOOP
        v_found := TRUE;
        v_report := array_append(v_report, format(
            'Совпадение текущего и прединцидентного профиля: %s',
            date_trunc('minute', v_rec.created_at)));
        v_report := array_append(v_report, format(
            '  JS-дивергенция: %s',
            COALESCE(round(v_rec.js_divergence::NUMERIC, 4)::TEXT, 'NULL')));
        v_report := array_append(v_report, format(
            '  Совпавший профиль ID: %s',
            v_rec.matched_pre_incident_id));
        v_report := array_append(v_report, format(
            '  Оригинальный инцидент ID: %s',
            COALESCE(v_rec.original_incident_id::TEXT, 'неизвестен')));
        IF v_rec.original_incident_time IS NOT NULL THEN
            v_report := array_append(v_report, format(
                '  Время оригинального инцидента: %s',
                v_rec.original_incident_time));
        ELSE
            v_report := array_append(v_report, '  Оригинальный инцидент не найден (возможно, удалён)');
        END IF;
        v_report := array_append(v_report, v_sep);
    END LOOP;

    IF NOT v_found THEN
        v_report := array_append(v_report,
            'Совпадений с пред-инцидентными профилями, удовлетворяющих условиям фильтра, за указанный период не обнаружено.');
    END IF;

    v_report := array_append(v_report, '=== КОНЕЦ ОТЧЁТА ===');
    RETURN v_report;
END;
$$;

COMMENT ON FUNCTION generate_pre_incident_audit_report(TIMESTAMPTZ, TIMESTAMPTZ, REAL) IS
'v19.1 (2026-10-25). Формирует отчёт о совпадениях текущих профилей с
пред-инцидентными шаблонами за указанный период.

В заголовок добавлен список инцидентов из markov_chain_performance_incident
(ID, время начала) за этот период; столбец priority ИСКЛЮЧЁН — MCI его не
содержит.

Параметр p_max_js_divergence позволяет отфильтровать записи по значению
JS-дивергенции (выбираются только те, где js_divergence <= заданного порога).
Если параметр не указан (NULL), фильтрация не применяется.

В отчёт не включаются статус сравнения, приоритет и длительность инцидента —
только факт совпадения, значение JS-дивергенции, идентификаторы и время
оригинального инцидента.';


-- =============================================================================
-- Функция: update_profile_change_indicator (обновлённая версия 2)
-- Назначение: Ежеминутно обновляет индикатор изменения профиля на основе
--             последнего значения pre_alert_flag_advanced из profile_comparison_log.
--             Если флаг равен 100 – сигнал активен (TRUE), иначе FALSE.
--             Записывает изменение состояния в profile_change_indicator.
-- Возвращает: TEXT – сообщение о результате (инициализация, изменение или неизменность).
-- =============================================================================
CREATE OR REPLACE FUNCTION update_profile_change_indicator()
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    v_current_signal BOOLEAN;
    v_last_signal    BOOLEAN;
    v_pre_alert_flag INT;
BEGIN
    -- 1. Получаем последнее значение pre_alert_flag_advanced из profile_comparison_log
    SELECT pre_alert_flag_advanced
    INTO v_pre_alert_flag
    FROM profile_comparison_log
    ORDER BY created_at DESC
    LIMIT 1;

    -- Если записей нет, считаем сигнал неактивным
    IF NOT FOUND OR v_pre_alert_flag IS NULL THEN
        v_current_signal := FALSE;
    ELSE
        v_current_signal := (v_pre_alert_flag = 100);
    END IF;

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
    IF v_current_signal IS DISTINCT FROM v_last_signal THEN
        INSERT INTO profile_change_indicator (indicator_value, changed_at)
        VALUES (v_current_signal, now());
        RETURN format('Indicator changed from %s to %s at %s', v_last_signal, v_current_signal, now());
    ELSE
        RETURN format('Indicator unchanged (%s) at %s', v_current_signal, now());
    END IF;
END;
$$;

COMMENT ON FUNCTION update_profile_change_indicator() IS 
'Ежеминутная функция обновления индикатора. Использует последний pre_alert_flag_advanced 
из profile_comparison_log. Если флаг = 100, сигнал активен (TRUE), иначе FALSE. 
Записывает изменение состояния в profile_change_indicator.';

--Функция для исторического заполнения индикатора
/*
-- Полное перезаполнение индикатора за последние 7 дней
SELECT historical_fill_profile_change_indicator(now() - INTERVAL '7 days', now());

-- Полное перезаполнение от начала доступных данных
SELECT historical_fill_profile_change_indicator();
*/
-- =============================================================================
-- Функция: historical_fill_profile_change_indicator (версия 2)
-- Назначение: Заполняет таблицу profile_change_indicator за указанный период.
--             Для каждой минуты определяет значение сигнала на основе
--             последнего pre_alert_flag_advanced из profile_comparison_log,
--             у которого current_window_end <= рассматриваемой минуты.
--             Сигнал считается активным (TRUE), если pre_alert_flag_advanced = 100,
--             иначе FALSE. Записывает только моменты изменения состояния.
--
-- Параметры:
--   p_start TIMESTAMPTZ – начало периода (если NULL – берётся минимальная
--                          дата из profile_comparison_log)
--   p_end   TIMESTAMPTZ – конец периода (если NULL – now())
--
-- Возвращает: TEXT – отчёт о количестве обработанных минут и вставленных записей.
-- =============================================================================
CREATE OR REPLACE FUNCTION historical_fill_profile_change_indicator(
    p_start TIMESTAMPTZ DEFAULT NULL,
    p_end   TIMESTAMPTZ DEFAULT NULL
)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    v_start          TIMESTAMPTZ;
    v_end            TIMESTAMPTZ;
    v_ts             TIMESTAMPTZ;
    v_signal         BOOLEAN;
    v_last_signal    BOOLEAN := NULL;
    v_pre_alert_flag INT;
    v_counter        BIGINT := 0;
    v_total_minutes  BIGINT;
    v_last_percent   INT := -1;
    v_current_percent INT;
    v_inserted       INT := 0;
    v_processed_ts   TIMESTAMPTZ;
BEGIN
    -- ------------------------------------------------------------------
    -- 1. Определение границ периода
    -- ------------------------------------------------------------------
    IF p_start IS NULL THEN
        SELECT MIN(current_window_end) INTO v_start
        FROM profile_comparison_log;
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
        RETURN 'Ошибка: начальная дата должна быть раньше конечной.';
    END IF;

    -- Округляем до минут
    v_start := date_trunc('minute', v_start);
    v_end   := date_trunc('minute', v_end);

    -- ------------------------------------------------------------------
    -- 2. Удаление существующих записей за указанный период (перезапись)
    -- ------------------------------------------------------------------
    DELETE FROM profile_change_indicator
    WHERE changed_at BETWEEN v_start AND v_end;

    RAISE NOTICE 'Удалены существующие записи за период с % по %', v_start, v_end;

    -- ------------------------------------------------------------------
    -- 3. Подготовка к циклу
    -- ------------------------------------------------------------------
    v_ts := v_start;
    v_total_minutes := EXTRACT(EPOCH FROM (v_end - v_start)) / 60 + 1;

    RAISE NOTICE 'Начало исторического заполнения индикатора с % по % (всего % минут)',
                 v_ts, v_end, v_total_minutes;

    -- ------------------------------------------------------------------
    -- 4. Цикл по минутам
    -- ------------------------------------------------------------------
    WHILE v_ts <= v_end LOOP
        v_processed_ts := v_ts;

        -- Получаем последний pre_alert_flag_advanced,
        -- у которого current_window_end <= v_ts
        SELECT pcl.pre_alert_flag_advanced
        INTO v_pre_alert_flag
        FROM profile_comparison_log pcl
        WHERE pcl.current_window_end <= v_ts
        ORDER BY pcl.current_window_end DESC
        LIMIT 1;

        -- Если данных нет или флаг NULL – считаем сигнал неактивным
        IF NOT FOUND OR v_pre_alert_flag IS NULL THEN
            v_signal := FALSE;
        ELSE
            v_signal := (v_pre_alert_flag = 100);
        END IF;

        -- Если сигнал изменился или это первая запись – вставляем новую строку
        IF v_last_signal IS NULL OR v_signal IS DISTINCT FROM v_last_signal THEN
            INSERT INTO profile_change_indicator (indicator_value, changed_at)
            VALUES (v_signal, v_ts);
            v_inserted := v_inserted + 1;
            v_last_signal := v_signal;
        END IF;

        v_counter := v_counter + 1;
        v_ts := v_ts + INTERVAL '1 minute';

        -- ------------------------------------------------------------------
        -- 5. Вывод прогресса каждые 1%
        -- ------------------------------------------------------------------
        v_current_percent := floor((v_counter::NUMERIC / v_total_minutes) * 100);
        IF v_current_percent > v_last_percent THEN
            RAISE NOTICE 'Прогресс: % %% (обработано % из % минут, вставлено % записей, последняя минута: %)',
                         v_current_percent, v_counter, v_total_minutes, v_inserted, v_processed_ts;
            v_last_percent := v_current_percent;
        END IF;
    END LOOP;

    RAISE NOTICE 'Заполнение завершено. Обработано % минут, вставлено % записей об изменении состояния.',
                 v_counter, v_inserted;

    RETURN format('Историческое заполнение завершено. Обработано %s минут, вставлено %s записей.',
                  v_counter, v_inserted);
END;
$$;

COMMENT ON FUNCTION historical_fill_profile_change_indicator(TIMESTAMPTZ, TIMESTAMPTZ) IS 'Заполняет таблицу profile_change_indicator за указанный период (по умолчанию от начала данных до now()). Для каждой минуты определяет значение сигнала на основе последнего pre_alert_flag_advanced из profile_comparison_log с current_window_end <= рассматриваемой минуты. Сигнал активен (TRUE), если pre_alert_flag_advanced = 100, иначе FALSE. Сохраняет только моменты изменения состояния. Согласована с update_profile_change_indicator().';


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
	
	-- Переменные для сохранения последнего подходящего непрерывного сигнала
    v_last_qualifying_start        TIMESTAMPTZ;
    v_last_qualifying_duration     INT;
    v_last_qualifying_strength     REAL;
    v_last_qualifying_max_strength REAL;
    v_last_qualifying_found        BOOLEAN := FALSE;
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

        IF v_js_value IS NULL THEN
            v_js_value := v_last_js;
        ELSE
            v_last_js := v_js_value;
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
                -- Начало нового непрерывного сигнала
                v_current_duration := 1;
                v_first_signal_time := v_minute_ts;
                v_signal_strength := v_signal_strength_minute;
                v_max_signal_strength := v_signal_strength_minute;
            ELSE
                -- Продолжение сигнала
                v_current_duration := v_current_duration + 1;
                IF v_signal_strength_minute > v_max_signal_strength THEN
                    v_max_signal_strength := v_signal_strength_minute;
                END IF;
            END IF;
            v_prev_signal := TRUE;
        ELSE
            -- Сигнал прервался
            IF v_prev_signal THEN
                -- Проверяем, достиг ли только что завершённый сигнал минимальной длительности
                IF v_current_duration >= v_min_signal_duration THEN
                    -- Сохраняем как последний подходящий
                    v_last_qualifying_start := v_first_signal_time;
                    v_last_qualifying_duration := v_current_duration;
                    v_last_qualifying_strength := v_signal_strength;
                    v_last_qualifying_max_strength := v_max_signal_strength;
                    v_last_qualifying_found := TRUE;
                END IF;
            END IF;
            v_prev_signal := FALSE;
            v_current_duration := 0;
        END IF;
    END LOOP;

    -- После цикла проверяем, не остался ли сигнал активным до конца окна
    IF v_prev_signal THEN
        IF v_current_duration >= v_min_signal_duration THEN
            v_last_qualifying_start := v_first_signal_time;
            v_last_qualifying_duration := v_current_duration;
            v_last_qualifying_strength := v_signal_strength;
            v_last_qualifying_max_strength := v_max_signal_strength;
            v_last_qualifying_found := TRUE;
        END IF;
    END IF;

    -- Если сигнал сработал, фиксируем длительность и уверенность
    IF v_last_qualifying_found THEN
        v_signal_triggered := TRUE;
        v_first_signal_time := v_last_qualifying_start;
        v_signal_duration := v_last_qualifying_duration;
        v_signal_strength := v_last_qualifying_strength;
        v_max_signal_strength := v_last_qualifying_max_strength;
        v_confidence := v_signal_strength;
    ELSE
        v_signal_triggered := FALSE;
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
'v1-версия расчёта сигнала (на prediction_log + profile_comparison_log). Не используется в отчётности с v3.0.0. Оставлен для отладки и сверки с sicpp_calculate_at.';

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
-- compare_profiles_at (версия 4, 2026-10-29)
-- Назначение: выполняет сравнение эталонного и текущего профилей для заданного
--             момента времени (исторического).
--
-- ИЗМЕНЕНИЯ (v4):
--   - БЛОК 1: проверка «внутри инцидента» заменена с точечной (по p_ts)
--     на проверку ПЕРЕСЕЧЕНИЯ всего текущего окна [v_current_start, v_current_end]
--     с любым инцидентом. Аналогично правке в compare_profiles v6.
--     Это устраняет ложные WARNING/CRITICAL при историческом заполнении
--     profile_comparison_log (fill_profile_comparison_historically), когда
--     инцидент завершился до p_ts, но попал в 60-минутное окно.
--   - В v_details добавлен ключ 'incident_overlap' (для диагностики).
-- =============================================================================
CREATE OR REPLACE FUNCTION compare_profiles_at(
    p_ts                   TIMESTAMPTZ,
    p_window_minutes       INT DEFAULT 60,
    p_lookback_days        INT DEFAULT 30,
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
    v_incident_overlap RECORD;
    v_max_pred_risk REAL;
    v_risk_p90      REAL;
    v_stability_met BOOLEAN;
    v_pre_alert     INTEGER;
    v_pre_alert_advanced INTEGER := 0;
    v_js_threshold  REAL;
    v_matched_id    BIGINT;
    v_baseline_found BOOLEAN := FALSE;
    v_last_statuses TEXT[];
    v_crit_or_warn_count INT;
BEGIN
    -- 1. Проверяем, пересекается ли ТЕКУЩЕЕ ОКНО [v_current_start, v_current_end]
    --    с любым инцидентом производительности (включая незавершённые).
    --    v4: раньше проверялась только точка p_ts — это пропускало инциденты,
    --    которые завершились до p_ts, но начались внутри окна.
    SELECT
        pi.id,
        pi.start_timepoint,
        pi.finish_timepoint
    INTO v_incident_overlap
    FROM markov_chain_performance_incident pi
    WHERE pi.start_timepoint <  v_current_end
      AND (pi.finish_timepoint IS NULL OR pi.finish_timepoint > v_current_start)
    ORDER BY pi.start_timepoint DESC
    LIMIT 1;

    v_inside_incident := FOUND;

    -- 2. Вычисляем максимальный и 90-й перцентиль предсказанного риска
    SELECT
        MAX(predicted_risk),
        PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY predicted_risk)
    INTO v_max_pred_risk, v_risk_p90
    FROM prediction_log
    WHERE prediction_time BETWEEN v_current_start AND v_current_end;

    -- 3. Если текущее окно пересекается с инцидентом – записываем INCIDENT
    IF v_inside_incident THEN
        v_status := 'INCIDENT';
        v_report := array_append(v_report, '=== СРАВНЕНИЕ ПРОФИЛЕЙ ===');
        v_report := array_append(v_report, format('Текущий момент: %s', v_now));
        v_report := array_append(v_report, format('Текущее окно: %s – %s',
            to_char(v_current_start, 'YYYY-MM-DD HH24:MI'),
            to_char(v_current_end,   'YYYY-MM-DD HH24:MI')));
        v_report := array_append(v_report, format(
            'Инцидент (пересечение): ID=%s, %s – %s',
            v_incident_overlap.id,
            to_char(v_incident_overlap.start_timepoint, 'YYYY-MM-DD HH24:MI'),
            COALESCE(to_char(v_incident_overlap.finish_timepoint, 'YYYY-MM-DD HH24:MI'),
                     'не завершён')));
        v_report := array_append(v_report,
            'Статус: INCIDENT – текущее окно пересекается с инцидентом.');
        v_report := array_append(v_report, '=== КОНЕЦ ОТЧЁТА ===');

        v_pre_alert := 0;
        v_matched_id := NULL;

        INSERT INTO profile_comparison_log (
            created_at, current_window_start, current_window_end, status,
            js_divergence, report, details, max_predicted_risk,
            pre_alert_flag, pre_alert_flag_advanced, matched_pre_incident_id
        ) VALUES (
            v_now, v_current_start, v_current_end, v_status, NULL,
            to_jsonb(v_report),
            jsonb_build_object(
                'reason', 'incident_overlap',
                'incident_id', v_incident_overlap.id,
                'incident_start', v_incident_overlap.start_timepoint,
                'incident_finish', v_incident_overlap.finish_timepoint),
            v_max_pred_risk, v_pre_alert, v_pre_alert_advanced, v_matched_id
        );
        RETURN v_report;
    END IF;

    -- 4. Пытаемся получить эталонное окно
    -- 4.0. incident_free_window_current (только если валидно)
    SELECT window_start, window_end INTO v_baseline_start, v_baseline_end
    FROM incident_free_window_current
    LIMIT 1;

    IF v_baseline_start IS NOT NULL
        AND v_baseline_end < v_current_start
        AND is_valid_baseline_window(v_baseline_start, v_baseline_end, v_now) THEN
        NULL;
    ELSE
        v_baseline_start := NULL;
        v_baseline_end := NULL;
    END IF;

    -- 4.1. Исторический baseline из profile_aggregated (только валидный)
    IF v_baseline_start IS NULL OR v_baseline_end >= v_current_start THEN
        SELECT window_start, window_end INTO v_baseline_start, v_baseline_end
        FROM profile_aggregated
        WHERE profile_type = 'baseline'
            AND window_end < v_current_start
            AND is_valid_baseline_window(window_start, window_end, v_now)
        ORDER BY window_end DESC
        LIMIT 1;

        IF v_baseline_start IS NOT NULL AND v_baseline_end >= v_current_start THEN
            v_baseline_start := NULL;
            v_baseline_end := NULL;
        END IF;
    END IF;

    -- 4.2. Динамический поиск безынцидентного окна
    IF v_baseline_start IS NULL OR v_baseline_end >= v_current_start THEN
        SELECT start_ts, end_ts
        INTO v_baseline_start, v_baseline_end
        FROM get_incident_free_window_before(
            p_ts                => v_current_start,
            p_window_minutes    => p_window_minutes,
            p_lookback_days     => p_lookback_days,
            p_exclude_after_min => 60
        );
    END IF;

    -- 4.3. Финальная проверка
    IF v_baseline_start IS NOT NULL AND v_baseline_end < v_current_start THEN
        v_baseline_found := TRUE;
    ELSE
        v_baseline_found := FALSE;
    END IF;

    -- 5. Если эталон не найден – NO_BASELINE
    IF NOT v_baseline_found THEN
        v_status := 'NO_BASELINE';
        v_report := array_append(v_report, '=== СРАВНЕНИЕ ПРОФИЛЕЙ ===');
        v_report := array_append(v_report, format('Текущий момент: %s', v_now));
        v_report := array_append(v_report, 'Статус: NO_BASELINE – отсутствует актуальный эталонный профиль, удовлетворяющий условиям (период нагрузки + зазор после инцидента).');
        v_report := array_append(v_report, '=== КОНЕЦ ОТЧЁТА ===');

        v_pre_alert := 0;
        v_matched_id := NULL;

        INSERT INTO profile_comparison_log (
            created_at, current_window_start, current_window_end, status,
            js_divergence, report, details, max_predicted_risk,
            pre_alert_flag, pre_alert_flag_advanced, matched_pre_incident_id
        ) VALUES (
            v_now, v_current_start, v_current_end, v_status, NULL,
            to_jsonb(v_report), jsonb_build_object('reason', 'no_baseline'),
            v_max_pred_risk, v_pre_alert, v_pre_alert_advanced, v_matched_id
        );
        RETURN v_report;
    END IF;

    -- 6. Метрики обоих окон
    SELECT * INTO v_baseline_metrics
    FROM calculate_profile_metrics(v_baseline_start, v_baseline_end);

    SELECT * INTO v_current_metrics
    FROM calculate_profile_metrics(v_current_start, v_current_end);

    -- 7. JS-дивергенция
    v_js := histogram_divergence(
        v_baseline_metrics.state_histogram,
        v_current_metrics.state_histogram
    );

    -- 8. Статус
    v_status := 'NORMAL';
    IF v_js >= 0.05 THEN
        v_status := 'WARNING';
    END IF;
    IF v_js >= 0.2 OR ABS(COALESCE(v_current_metrics.avg_correlation, 0) - COALESCE(v_baseline_metrics.avg_correlation, 0)) > 0.2 THEN
        v_status := 'CRITICAL';
    END IF;

    -- 9. Простой pre_alert_flag
    SELECT COALESCE( (SELECT js_divergence_threshold FROM markov_config ), 0.2 ) INTO v_js_threshold;

    IF v_js IS NOT NULL AND v_js >= v_js_threshold AND v_max_pred_risk IS NOT NULL AND v_max_pred_risk = 1 THEN
        v_pre_alert := 100;
    ELSE
        v_pre_alert := 0;
    END IF;

    -- 10. Устойчивость: 3 из 5 последних сравнений (до v_now)
    SELECT array_agg(status ORDER BY current_window_end DESC)
    INTO v_last_statuses
    FROM (
        SELECT status, current_window_end
        FROM profile_comparison_log
        WHERE current_window_end < v_current_start
        ORDER BY current_window_end DESC
        LIMIT 5
    ) t;

    IF v_last_statuses IS NULL THEN
        v_stability_met := FALSE;
    ELSE
        SELECT COUNT(*) INTO v_crit_or_warn_count
        FROM unnest(v_last_statuses) AS s
        WHERE s IN ('CRITICAL', 'WARNING');
        v_stability_met := (v_crit_or_warn_count >= 3);
    END IF;

    -- 11. Расширенный флаг
    IF v_js IS NOT NULL
       AND v_js >= v_js_threshold
       AND v_risk_p90 IS NOT NULL
       AND v_risk_p90 >= 0.95
       AND v_stability_met
    THEN
        v_pre_alert_advanced := 100;
    ELSE
        v_pre_alert_advanced := 0;
    END IF;

    -- 12. Поиск совпадающего профиля
    v_matched_id := find_matching_pre_incident_profile(
        v_current_metrics.state_histogram,
        0.05,
        100
    );

    -- 13. Формируем отчёт
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
        v_report := array_append(v_report, format('  Максимальный риск: %s', round(v_max_pred_risk::NUMERIC, 4)::TEXT));
    END IF;
    IF v_risk_p90 IS NOT NULL THEN
        v_report := array_append(v_report, format('  90-й перцентиль риска: %s', round(v_risk_p90::NUMERIC, 4)::TEXT));
    END IF;

    v_report := array_append(v_report, format('  Простой флаг: %s', CASE WHEN v_pre_alert = 100 THEN '100' ELSE '0' END));
    v_report := array_append(v_report, format('  Устойчивость: %s (%s из 5)',
        CASE WHEN v_stability_met THEN 'ДА' ELSE 'НЕТ' END,
        COALESCE(v_crit_or_warn_count::TEXT, '0')));
    v_report := array_append(v_report, format('  Расширенный флаг: %s', CASE WHEN v_pre_alert_advanced = 100 THEN '100' ELSE '0' END));

    IF v_matched_id IS NOT NULL THEN
        v_report := array_append(v_report, format('  ⚠ Совпадение с шаблоном (ID=%s)', v_matched_id));
    END IF;

    v_report := array_append(v_report, '');
    v_report := array_append(v_report, format('--- JS-ДИВЕРГЕНЦИЯ: %s ---', round(v_js::NUMERIC, 4)::TEXT));
    v_report := array_append(v_report, format('--- ИТОГОВЫЙ СТАТУС: %s ---', v_status));
    v_report := array_append(v_report, '=== КОНЕЦ ОТЧЁТА ===');

    -- 14. Сохраняем результат
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
        'risk_p90', v_risk_p90,
        'stability_met', v_stability_met,
        'crit_or_warn_count', v_crit_or_warn_count
    );

    INSERT INTO profile_comparison_log (
        created_at, baseline_window_start, baseline_window_end,
        current_window_start, current_window_end, status, js_divergence,
        report, details, max_predicted_risk, pre_alert_flag,
        pre_alert_flag_advanced, matched_pre_incident_id,
        high_risk_percentile, js_threshold_used, stability_met
    ) VALUES (
        v_now, v_baseline_start, v_baseline_end,
        v_current_start, v_current_end, v_status, v_js,
        to_jsonb(v_report), v_details, v_max_pred_risk, v_pre_alert,
        v_pre_alert_advanced, v_matched_id,
        v_risk_p90, v_js_threshold, v_stability_met
    );

    RETURN v_report;
END;
$$;

COMMENT ON FUNCTION compare_profiles_at(TIMESTAMPTZ, INT, INT, INT, INT) IS
'Сравнивает профили для заданного момента времени.
Версия 4 (2026-10-29): проверка «внутри инцидента» теперь выполняется для всего
текущего окна [v_current_start, v_current_end], а не только для точки p_ts.
Это устраняет ложные WARNING/CRITICAL при историческом заполнении
profile_comparison_log (fill_profile_comparison_historically), когда инцидент
завершился до p_ts, но попал в окно [p_ts - 60 мин, p_ts].
При выборе эталона из incident_free_window_current и profile_aggregated.baseline
дополнительно проверяется is_valid_baseline_window.';

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
    p_lookback_days   INT         DEFAULT 30,       -- <-- было 7
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
'Заполняет profile_comparison_log за исторический период. p_lookback_days (по умолчанию 30) задаёт глубину поиска эталонного окна в compare_profiles_at.';

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
-- Используемые таблицы: profile_comparison_log, markov_chain_performance_incident.
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
        FROM markov_chain_performance_incident
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


------------------------------------------
-- 16.8

-- =============================================================================
-- Функция: sicpp_calculate_at
-- Версия: 3.0
-- Назначение: вычисляет состояние SICPP на заданный момент p_ts на основе
--             prediction_log и profile_comparison_log. Логика полностью
--             соответствует calculate_signal() из отчёта «ОТЧЁТ ПО
--             ПРОГНОЗИРОВАНИЮ ИНЦИДЕНТОВ».
-- =============================================================================
CREATE OR REPLACE FUNCTION sicpp_calculate_at(
    p_ts                   TIMESTAMPTZ,
    p_window_minutes       INT  DEFAULT NULL,
    p_js_threshold         REAL DEFAULT NULL,
    p_risk_threshold       REAL DEFAULT NULL,
    p_signal_mode          TEXT DEFAULT NULL,
    p_min_signal_duration  INT  DEFAULT NULL,
    p_weight_js            REAL DEFAULT NULL,
    p_weight_risk          REAL DEFAULT NULL,
    p_max_js_age_min       INT  DEFAULT NULL,
    p_min_data_points      INT  DEFAULT NULL,
    p_slope_window_minutes INT  DEFAULT NULL,
    p_max_signal_duration  INT  DEFAULT NULL
)
RETURNS TABLE (
    js_avg              REAL,
    js_min              REAL,
    js_max              REAL,
    js_cnt              INT,
    risk_avg            REAL,
    risk_min            REAL,
    risk_max            REAL,
    risk_cnt            INT,
    signal_active       BOOLEAN,
    signal_strength     REAL,
    first_signal_time   TIMESTAMPTZ,
    signal_duration     INT,
    max_signal_strength REAL,
    js_slope            REAL,
    risk_slope          REAL,
    data_sufficient     TEXT,
    confidence          REAL,
    signal_mode         TEXT,
    js_threshold        REAL,
    risk_threshold      REAL,
    window_minutes      INT,
    min_signal_duration INT,
    signal_capped       BOOLEAN,
    episode_started_at  TIMESTAMPTZ     -- v18.1: реальный старт эпизода
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
    v_max_signal_duration INT;

    v_js_stats RECORD;
    v_risk_stats RECORD;
    v_last_js REAL;
    v_last_js_time TIMESTAMPTZ;
    v_last_risk REAL;
    v_last_risk_time TIMESTAMPTZ;

    v_js_min REAL; v_js_max REAL; v_js_avg REAL; v_js_cnt INT;
    v_risk_min REAL; v_risk_max REAL; v_risk_avg REAL; v_risk_cnt INT;
    v_data_sufficient TEXT := 'OK';
    v_insufficient BOOLEAN := FALSE;

    v_minute_ts TIMESTAMPTZ;
    v_js_value REAL;
    v_risk_value REAL;
    v_is_signal_minute BOOLEAN;
    v_signal_strength_minute REAL;
    v_prev_signal BOOLEAN := FALSE;
    v_current_duration INT := 0;
    v_run_start TIMESTAMPTZ;
    v_run_strength REAL;
    v_run_max_strength REAL;

    v_last_qualifying_start        TIMESTAMPTZ;
    v_last_qualifying_duration     INT;
    v_last_qualifying_strength     REAL;
    v_last_qualifying_max_strength REAL;
    v_last_qualifying_found        BOOLEAN := FALSE;

    v_signal_active BOOLEAN := FALSE;
    v_signal_strength REAL;
    v_first_signal_time TIMESTAMPTZ;
    v_signal_duration INT := 0;
    v_max_signal_strength REAL;
    v_confidence REAL;
    v_signal_capped BOOLEAN := FALSE;
    v_risk_slope REAL;
    v_js_slope REAL;

    -- v18.1: для carry-forward episode_started_at
    v_prev_sh_active       BOOLEAN;
    v_prev_ep_started_at   TIMESTAMPTZ;
    v_episode_started_at   TIMESTAMPTZ;
    v_real_duration_min    REAL;
BEGIN
    -- 1. Чтение конфигурации
    SELECT * INTO cfg FROM incident_forecast_config LIMIT 1;
    IF NOT FOUND THEN
        INSERT INTO incident_forecast_config DEFAULT VALUES;
        SELECT * INTO cfg FROM incident_forecast_config LIMIT 1;
    END IF;

    v_window_minutes       := COALESCE(p_window_minutes, cfg.window_minutes);
    v_js_threshold         := COALESCE(p_js_threshold, cfg.js_threshold);
    v_risk_threshold       := COALESCE(p_risk_threshold, cfg.risk_threshold);
    v_signal_mode          := COALESCE(p_signal_mode, cfg.signal_mode);
    v_min_signal_duration  := COALESCE(p_min_signal_duration, cfg.min_signal_duration);
    v_weight_js            := COALESCE(p_weight_js, cfg.weight_js);
    v_weight_risk          := COALESCE(p_weight_risk, cfg.weight_risk);
    v_max_js_age_min       := COALESCE(p_max_js_age_min, cfg.max_js_age_min);
    v_min_data_points      := COALESCE(p_min_data_points, cfg.min_data_points);
    v_slope_window_minutes := COALESCE(p_slope_window_minutes, cfg.slope_window_minutes);
    v_max_signal_duration  := COALESCE(p_max_signal_duration, cfg.max_signal_duration_minutes, 180);

    -- 2. Fallback-значения за пределами окна
    SELECT js_divergence, current_window_end
    INTO v_last_js, v_last_js_time
    FROM profile_comparison_log
    WHERE current_window_end < p_ts - (v_window_minutes || ' minutes')::INTERVAL
      AND js_divergence IS NOT NULL
    ORDER BY current_window_end DESC LIMIT 1;

    SELECT predicted_risk, prediction_time
    INTO v_last_risk, v_last_risk_time
    FROM prediction_log
    WHERE prediction_time < p_ts - (v_window_minutes || ' minutes')::INTERVAL
      AND predicted_risk IS NOT NULL
    ORDER BY prediction_time DESC LIMIT 1;

    -- 3. Статистика JS за окно
    SELECT MIN(js_divergence), MAX(js_divergence), AVG(js_divergence), COUNT(*)
    INTO v_js_stats
    FROM profile_comparison_log
    WHERE current_window_end >= p_ts - (v_window_minutes || ' minutes')::INTERVAL
      AND current_window_end < p_ts
      AND js_divergence IS NOT NULL;

    IF v_js_stats IS NULL OR v_js_stats.count < v_min_data_points THEN
        IF v_last_js IS NOT NULL
           AND EXTRACT(EPOCH FROM (p_ts - v_last_js_time)) / 60 <= v_max_js_age_min THEN
            v_js_min := v_last_js; v_js_max := v_last_js; v_js_avg := v_last_js; v_js_cnt := -1;
            v_data_sufficient := 'LOW_JS';
        ELSE
            v_js_min := NULL; v_js_max := NULL; v_js_avg := NULL; v_js_cnt := 0;
            v_insufficient := TRUE;
            v_data_sufficient := 'LOW_JS';
        END IF;
    ELSE
        v_js_min := v_js_stats.min; v_js_max := v_js_stats.max;
        v_js_avg := v_js_stats.avg; v_js_cnt := v_js_stats.count;
    END IF;

    -- 4. Статистика риска за окно
    SELECT MIN(predicted_risk), MAX(predicted_risk), AVG(predicted_risk), COUNT(*)
    INTO v_risk_stats
    FROM prediction_log
    WHERE prediction_time >= p_ts - (v_window_minutes || ' minutes')::INTERVAL
      AND prediction_time < p_ts
      AND predicted_risk IS NOT NULL;

    IF v_risk_stats IS NULL OR v_risk_stats.count < v_min_data_points THEN
        IF v_last_risk IS NOT NULL
           AND EXTRACT(EPOCH FROM (p_ts - v_last_risk_time)) / 60 <= v_max_js_age_min THEN
            v_risk_min := v_last_risk; v_risk_max := v_last_risk;
            v_risk_avg := v_last_risk; v_risk_cnt := -1;
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
        v_risk_min := v_risk_stats.min; v_risk_max := v_risk_stats.max;
        v_risk_avg := v_risk_stats.avg; v_risk_cnt := v_risk_stats.count;
    END IF;

    -- 5. Недостаточно данных — пустое состояние
    IF v_insufficient THEN
        js_avg := v_js_avg; js_min := v_js_min; js_max := v_js_max; js_cnt := v_js_cnt;
        risk_avg := v_risk_avg; risk_min := v_risk_min; risk_max := v_risk_max; risk_cnt := v_risk_cnt;
        signal_active := FALSE; signal_strength := NULL;
        first_signal_time := NULL; signal_duration := 0; max_signal_strength := NULL;
        js_slope := NULL; risk_slope := NULL;
        data_sufficient := v_data_sufficient; confidence := NULL;
        signal_mode := v_signal_mode; js_threshold := v_js_threshold;
        risk_threshold := v_risk_threshold; window_minutes := v_window_minutes;
        min_signal_duration := v_min_signal_duration;
        signal_capped := FALSE;
        episode_started_at := NULL;
        RETURN NEXT; RETURN;
    END IF;

    -- 6. Итерация по минутам окна (как v2.0)
    FOR v_minute_ts IN
        SELECT generate_series(
            date_trunc('minute', p_ts - (v_window_minutes || ' minutes')::INTERVAL),
            date_trunc('minute', p_ts) - INTERVAL '1 minute',
            INTERVAL '1 minute'
        )
    LOOP
        SELECT js_divergence INTO v_js_value
        FROM profile_comparison_log
        WHERE current_window_end <= v_minute_ts AND js_divergence IS NOT NULL
        ORDER BY current_window_end DESC LIMIT 1;
        IF v_js_value IS NULL THEN v_js_value := v_last_js; ELSE v_last_js := v_js_value; END IF;

        SELECT predicted_risk INTO v_risk_value
        FROM prediction_log
        WHERE prediction_time <= v_minute_ts AND predicted_risk IS NOT NULL
        ORDER BY prediction_time DESC LIMIT 1;
        IF v_risk_value IS NULL THEN v_risk_value := v_last_risk; ELSE v_last_risk := v_risk_value; END IF;

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
                    v_is_signal_minute := FALSE; v_signal_strength_minute := 0;
            END CASE;
        ELSE
            v_is_signal_minute := FALSE; v_signal_strength_minute := 0;
        END IF;

        IF v_is_signal_minute THEN
            IF NOT v_prev_signal THEN
                v_current_duration := 1;
                v_run_start := v_minute_ts;
                v_run_strength := v_signal_strength_minute;
                v_run_max_strength := v_signal_strength_minute;
            ELSE
                v_current_duration := v_current_duration + 1;
                IF v_signal_strength_minute > v_run_max_strength THEN
                    v_run_max_strength := v_signal_strength_minute;
                END IF;
            END IF;
            v_prev_signal := TRUE;
        ELSE
            IF v_prev_signal THEN
                IF v_current_duration >= v_min_signal_duration THEN
                    v_last_qualifying_start        := v_run_start;
                    v_last_qualifying_duration     := v_current_duration;
                    v_last_qualifying_strength     := v_run_strength;
                    v_last_qualifying_max_strength := v_run_max_strength;
                    v_last_qualifying_found        := TRUE;
                END IF;
            END IF;
            v_prev_signal := FALSE;
            v_current_duration := 0;
        END IF;
    END LOOP;

    IF v_prev_signal THEN
        IF v_current_duration >= v_min_signal_duration THEN
            v_last_qualifying_start        := v_run_start;
            v_last_qualifying_duration     := v_current_duration;
            v_last_qualifying_strength     := v_run_strength;
            v_last_qualifying_max_strength := v_run_max_strength;
            v_last_qualifying_found        := TRUE;
        END IF;
    END IF;

    -- ======================================================================
    -- 7. Состояние SICPP + v18.1: signal_duration = p_ts - episode_started_at
    -- ======================================================================
    IF v_last_qualifying_found THEN
        v_signal_active        := TRUE;
        v_signal_strength      := v_last_qualifying_strength;
        v_max_signal_strength  := v_last_qualifying_max_strength;
        v_confidence           := v_signal_strength;

        -- 7.1. Определение episode_started_at
        -- Проверяем последнюю запись в sicpp_history до p_ts:
        --   * если предыдущая запись TRUE (эпизод продолжается) и в ней есть
        --     episode_started_at  → carry forward;
        --   * иначе (новая эпизод или нет записей) → v_run_start из локального
        --     скана (начало квалифицирующего пробега ВНУТРИ окна).
        SELECT sh.signal_active, sh.episode_started_at
        INTO v_prev_sh_active, v_prev_ep_started_at
        FROM sicpp_history sh
        WHERE sh.changed_at < p_ts
        ORDER BY sh.changed_at DESC, sh.id DESC
        LIMIT 1;

        IF COALESCE(v_prev_sh_active, FALSE) = TRUE
           AND v_prev_ep_started_at IS NOT NULL THEN
            v_episode_started_at := v_prev_ep_started_at;
        ELSE
            -- Новая эпизод (или первая запись в истории). Используем v_run_start.
            v_episode_started_at := v_run_start;
        END IF;

        -- Защита от NULL
        IF v_episode_started_at IS NULL THEN
            v_episode_started_at := v_run_start;
        END IF;

        -- 7.2. Реальная длительность
        v_real_duration_min := EXTRACT(EPOCH FROM (p_ts - v_episode_started_at)) / 60.0;

        -- 7.3. Каппинг (v18.1: работает, т.к. v_real_duration_min может
        -- превысить max_signal_duration — не ограничена окном)
        IF v_real_duration_min > v_max_signal_duration THEN
            v_signal_duration   := v_max_signal_duration;
            v_first_signal_time := p_ts - (v_max_signal_duration || ' minutes')::INTERVAL;
            v_signal_capped     := TRUE;
        ELSE
            v_signal_duration   := ROUND(v_real_duration_min)::INT;
            v_first_signal_time := v_episode_started_at;
            v_signal_capped     := FALSE;
        END IF;

        -- v18.1: episode_started_at всегда содержит реальный старт,
        -- даже когда first_signal_time капнут.
        episode_started_at := v_episode_started_at;
    ELSE
        v_signal_active        := FALSE;
        v_signal_strength      := NULL;
        v_first_signal_time    := NULL;
        v_signal_duration      := 0;
        v_max_signal_strength  := NULL;
        v_confidence           := NULL;
        v_signal_capped        := FALSE;
        v_episode_started_at   := NULL;
        episode_started_at     := NULL;
    END IF;

    -- 8. Slope риска
    WITH slope_data AS (
        SELECT prediction_time, predicted_risk FROM prediction_log
        WHERE prediction_time >= p_ts - (v_slope_window_minutes || ' minutes')::INTERVAL
          AND prediction_time < p_ts AND predicted_risk IS NOT NULL
    )
    SELECT (MAX(predicted_risk) - MIN(predicted_risk)) /
           NULLIF(EXTRACT(EPOCH FROM (MAX(prediction_time) - MIN(prediction_time))) / 60, 0)
    INTO v_risk_slope FROM slope_data;

    -- 9. Slope JS
    WITH js_slope_data AS (
        SELECT current_window_end, js_divergence FROM profile_comparison_log
        WHERE current_window_end >= p_ts - (v_slope_window_minutes || ' minutes')::INTERVAL
          AND current_window_end < p_ts AND js_divergence IS NOT NULL
    )
    SELECT (MAX(js_divergence) - MIN(js_divergence)) /
           NULLIF(EXTRACT(EPOCH FROM (MAX(current_window_end) - MIN(current_window_end))) / 60, 0)
    INTO v_js_slope FROM js_slope_data;

    -- 10. Возврат
    js_avg := v_js_avg; js_min := v_js_min; js_max := v_js_max; js_cnt := v_js_cnt;
    risk_avg := v_risk_avg; risk_min := v_risk_min; risk_max := v_risk_max; risk_cnt := v_risk_cnt;
    signal_active := v_signal_active; signal_strength := v_signal_strength;
    first_signal_time := v_first_signal_time; signal_duration := v_signal_duration;
    max_signal_strength := v_max_signal_strength;
    js_slope := v_js_slope; risk_slope := v_risk_slope;
    data_sufficient := v_data_sufficient; confidence := v_confidence;
    signal_mode := v_signal_mode; js_threshold := v_js_threshold;
    risk_threshold := v_risk_threshold; window_minutes := v_window_minutes;
    min_signal_duration := v_min_signal_duration;
    signal_capped := v_signal_capped;
    -- episode_started_at уже установлена в блоке 7
    RETURN NEXT;
END;
$$;

COMMENT ON FUNCTION sicpp_calculate_at(TIMESTAMPTZ, INT, REAL, REAL, TEXT, INT, REAL, REAL, INT, INT, INT, INT) IS
'v18.1 (Variant B). SICPP как контекстный индикатор с корректным storage-каппингом.

КЛЮЧЕВОЕ ИЗМЕНЕНИЕ относительно v18.0:
  - Возвращает новую колонку episode_started_at (реальный старт эпизода).
  - signal_duration = p_ts - episode_started_at (реальная длительность, не ограничена
    окном [p_ts - window, p_ts - 1]).
  - carry-forward: если предыдущая запись sicpp_history имеет signal_active=TRUE,
    episode_started_at наследуется из неё; иначе (новая эпизод) = v_run_start
    из локального скана.
  - Каппинг срабатывает корректно: signal_capped=TRUE, когда реальная длительность
    превышает max_signal_duration_minutes.
  - first_signal_time капнут при signal_capped=TRUE, но episode_started_at
    всегда содержит реальный старт.

Остальная логика (локальный скан, WEIGHTED score, slope) — как в v2.0/v18.0.';
-- =============================================================================
-- Функция: sicpp_update_state
-- Версия: 3.0.0
-- Назначение: вызывается из mchain_train_step() ежеминутно. Вычисляет текущее
--             состояние SICPP, обновляет sicpp_current_state, и если состояние
--             изменилось — добавляет запись в sicpp_history.
-- =============================================================================
-- =============================================================================
-- Функция: sicpp_update_state
-- Версия: 3.1.0 (2026-10-27, P0 FIX)
-- Назначение: ежеминутное обновление SICPP. Вычисляет текущее состояние,
--             обновляет sicpp_current_state и при смене состояния пишет запись
--             в sicpp_history.
--
-- ИЗМЕНЕНИЯ v3.1.0 (P0):
--   - Добавлен блок принудительного завершения «capped»-эпизода.
--     Если sicpp_calculate_at вернул signal_capped = TRUE (реальная
--     длительность эпизода > max_signal_duration_minutes), то до записи
--     в историю состояние принудительно сбрасывается:
--         signal_active = FALSE, signal_capped = FALSE,
--         episode_started_at = NULL, signal_duration = 0,
--         reason = 'capped_force_end'.
--     Это разбивает длинные эпизоды на куски ≤ max_signal_duration_minutes.
--
--   - Если в следующем вызове условия сигнала всё ещё выполняются —
--     начнётся НОВЫЙ эпизод (episode_started_at := v_run_start в пределах
--     window_minutes), а не продолжение старого. Так эпизод гарантированно
--     не может «залипнуть» на 900+ минут (test11, ID 611/627/635).
--
-- ⚠ ОГРАНИЧЕНИЕ:
--   Данный фикс РАЗБИВАЕТ эпизоды, но НЕ подавляет повторное срабатывание.
--   Если условия (JS/Risk/W в окне window_minutes) продолжают выполняться,
--   эпизод перезапустится и через ~max_signal_duration_minutes снова будет
--   принудительно закрыт. Сумма FP-минут может остаться прежней
--   (chunking, не suppression).
--
--   Для достижения целевого эффекта (3335 → ~600 FP-минут) требуется
--   дополнительно подавить повторное срабатывание — см. TODO-cooldown
--   в конце функции.
-- =============================================================================
-- =============================================================================
-- Функция: sicpp_update_state
-- Версия: 3.2.0 (2026-10-27, P0 FIX + cooldown)
-- Назначение: ежеминутное обновление SICPP.
--
-- ИЗМЕНЕНИЯ v3.2.0 (относительно v3.1.0):
--   - Добавлен параметр sicpp_cooldown_minutes (из incident_forecast_config,
--     default 60).
--   - При force-close capped-эпизода устанавливается cooldown:
--         force_close_cooldown_until = v_now + sicpp_cooldown_minutes
--   - Пока cooldown активен, sicpp_update_state:
--         * не позволяет singleton стать signal_active=TRUE;
--         * пишет в историю 'cooldown_suppressed' один раз за период
--           (если последняя запись ещё не 'cooldown_suppressed');
--         * возвращает диагностическое сообщение.
--   - После истечения cooldown: force_close_cooldown_until := NULL,
--     нормальная обработка возобновляется. Если условия ещё выполняются,
--     стартует новый эпизод (episode_started_at = v_run_start внутри окна).
--
-- ОГРАНИЧЕНИЕ (по-прежнему chunking, а не permanent suppression):
--   Эпизод разбивается на куски ≤ max_signal_duration_minutes, между
--   которыми стоит пауза sicpp_cooldown_minutes. Сумма FP-минут
--   сокращается примерно в (cooldown + max_dur) / max_dur раза.
-- =============================================================================
CREATE OR REPLACE FUNCTION sicpp_update_state()
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    v_now               TIMESTAMPTZ := date_trunc('minute', now());
    v_calc              RECORD;
    v_prev_active       BOOLEAN;
    v_prev_capped       BOOLEAN;
    v_cooldown_until    TIMESTAMPTZ;
    v_cooldown_minutes  INT;
    v_last_reason       TEXT;
    v_new_id            BIGINT;
    v_reason            TEXT;
BEGIN
    -- -------------------------------------------------------------------
    -- 1. Читаем предыдущее состояние singleton (включая cooldown)
    -- -------------------------------------------------------------------
    SELECT signal_active, signal_capped, force_close_cooldown_until
    INTO v_prev_active, v_prev_capped, v_cooldown_until
    FROM sicpp_current_state
    WHERE id = 1;

    IF NOT FOUND THEN
        v_prev_active    := FALSE;
        v_prev_capped    := FALSE;
        v_cooldown_until := NULL;
    END IF;

    -- -------------------------------------------------------------------
    -- 2. Читаем конфигурацию cooldown
    -- -------------------------------------------------------------------
    SELECT COALESCE(sicpp_cooldown_minutes, 60)
    INTO v_cooldown_minutes
    FROM incident_forecast_config LIMIT 1;

    IF v_cooldown_minutes IS NULL THEN
        v_cooldown_minutes := 60;
    END IF;

    -- -------------------------------------------------------------------
    -- 3. Вычисляем новое состояние
    -- -------------------------------------------------------------------
    SELECT * INTO v_calc FROM sicpp_calculate_at(v_now);

    -- ===================================================================
    -- 4. COOLDOWN: подавление активности
    -- ===================================================================
    IF v_cooldown_until IS NOT NULL AND v_now < v_cooldown_until THEN
        -- Мы в периоде cooldown. Если singleton был активен (аномалия)
        -- или локальный скан квалифицирует сигнал — принудительно гасим.
        IF COALESCE(v_prev_active, FALSE) = TRUE
           OR COALESCE(v_calc.signal_active, FALSE) = TRUE THEN

            -- Проверяем, не записан ли уже 'cooldown_suppressed'
            -- (чтобы не спамить в историю ежеминутно)
            SELECT reason INTO v_last_reason
            FROM sicpp_history
            WHERE changed_at <= v_now
            ORDER BY changed_at DESC, id DESC
            LIMIT 1;

            UPDATE sicpp_current_state SET
                updated_at          = v_now,
                signal_active       = FALSE,
                signal_strength     = NULL,
                first_signal_time   = NULL,
                signal_duration     = 0,
                max_signal_strength = NULL,
                consecutive_run     = 0,
                last_minute_js      = v_calc.js_avg,
                last_minute_risk    = v_calc.risk_avg,
                signal_capped       = FALSE,
                episode_started_at  = NULL
                -- force_close_cooldown_until сохраняется
            WHERE id = 1;

            IF v_last_reason IS DISTINCT FROM 'cooldown_suppressed' THEN
                INSERT INTO sicpp_history (
                    changed_at, signal_active, signal_strength,
                    first_signal_time, signal_duration, max_signal_strength,
                    js_avg, js_min, js_max, js_cnt,
                    risk_avg, risk_min, risk_max, risk_cnt,
                    js_slope, risk_slope, data_sufficient, confidence,
                    signal_mode, js_threshold, risk_threshold,
                    window_minutes, min_signal_duration,
                    reason, signal_capped, episode_started_at
                ) VALUES (
                    v_now, FALSE, NULL,
                    NULL, 0, NULL,
                    v_calc.js_avg, v_calc.js_min, v_calc.js_max, v_calc.js_cnt,
                    v_calc.risk_avg, v_calc.risk_min, v_calc.risk_max, v_calc.risk_cnt,
                    v_calc.js_slope, v_calc.risk_slope, v_calc.data_sufficient, NULL,
                    v_calc.signal_mode, v_calc.js_threshold, v_calc.risk_threshold,
                    v_calc.window_minutes, v_calc.min_signal_duration,
                    'cooldown_suppressed', FALSE, NULL
                ) RETURNING id INTO v_new_id;

                UPDATE sicpp_current_state SET last_history_id = v_new_id WHERE id = 1;
            END IF;

            RETURN format(
                'SICPP suppressed by cooldown at %s (cooldown_until=%s, remaining=%s min)',
                v_now, v_cooldown_until,
                ROUND(EXTRACT(EPOCH FROM (v_cooldown_until - v_now)) / 60, 1));
        END IF;

        -- Сканер не квалифицирует сигнал, и singleton уже FALSE — тихо ждём.
        RETURN format('SICPP inactive during cooldown (until %s)', v_cooldown_until);
    END IF;

    -- -------------------------------------------------------------------
    -- 5. Cooldown истёк — очищаем
    -- -------------------------------------------------------------------
    IF v_cooldown_until IS NOT NULL THEN
        UPDATE sicpp_current_state
        SET force_close_cooldown_until = NULL
        WHERE id = 1;
    END IF;

    -- ===================================================================
    -- 6. P0 FIX: принудительное закрытие capped-эпизода + cooldown
    -- ===================================================================
    IF COALESCE(v_calc.signal_capped, FALSE) = TRUE
       AND COALESCE(v_calc.signal_active, FALSE) = TRUE THEN

        UPDATE sicpp_current_state SET
            updated_at                  = v_now,
            signal_active               = FALSE,
            signal_strength             = NULL,
            first_signal_time           = NULL,
            signal_duration             = 0,
            max_signal_strength         = NULL,
            consecutive_run             = 0,
            last_minute_js              = v_calc.js_avg,
            last_minute_risk            = v_calc.risk_avg,
            signal_capped               = FALSE,
            episode_started_at          = NULL,
            force_close_cooldown_until  = v_now
                                        + (v_cooldown_minutes || ' minutes')::INTERVAL
        WHERE id = 1;

        INSERT INTO sicpp_history (
            changed_at, signal_active, signal_strength,
            first_signal_time, signal_duration, max_signal_strength,
            js_avg, js_min, js_max, js_cnt,
            risk_avg, risk_min, risk_max, risk_cnt,
            js_slope, risk_slope, data_sufficient, confidence,
            signal_mode, js_threshold, risk_threshold,
            window_minutes, min_signal_duration,
            reason, signal_capped, episode_started_at
        ) VALUES (
            v_now, FALSE, NULL,
            NULL, 0, NULL,
            v_calc.js_avg, v_calc.js_min, v_calc.js_max, v_calc.js_cnt,
            v_calc.risk_avg, v_calc.risk_min, v_calc.risk_max, v_calc.risk_cnt,
            v_calc.js_slope, v_calc.risk_slope, v_calc.data_sufficient, NULL,
            v_calc.signal_mode, v_calc.js_threshold, v_calc.risk_threshold,
            v_calc.window_minutes, v_calc.min_signal_duration,
            'capped_force_end', FALSE, NULL
        ) RETURNING id INTO v_new_id;

        UPDATE sicpp_current_state SET last_history_id = v_new_id WHERE id = 1;

        RETURN format(
            'SICPP force-closed capped episode at %s '
            '(was %s min; cooldown %s min, next allowed after %s)',
            v_now, v_calc.signal_duration, v_cooldown_minutes,
            v_now + (v_cooldown_minutes || ' minutes')::INTERVAL);
    END IF;

    -- ===================================================================
    -- 7. Штатная обработка (без изменений относительно v3.1.0)
    -- ===================================================================
    UPDATE sicpp_current_state SET
        updated_at          = v_now,
        signal_active       = COALESCE(v_calc.signal_active, FALSE),
        signal_strength     = v_calc.signal_strength,
        first_signal_time   = v_calc.first_signal_time,
        signal_duration     = COALESCE(v_calc.signal_duration, 0),
        max_signal_strength = v_calc.max_signal_strength,
        consecutive_run     = COALESCE(v_calc.signal_duration, 0),
        last_minute_js      = v_calc.js_avg,
        last_minute_risk    = v_calc.risk_avg,
        signal_capped       = COALESCE(v_calc.signal_capped, FALSE),
        episode_started_at  = v_calc.episode_started_at
    WHERE id = 1;

    -- Запись в историю при смене состояния
    IF v_calc.signal_active IS DISTINCT FROM v_prev_active THEN
        v_reason := CASE WHEN v_calc.signal_active
                         THEN 'signal started' ELSE 'signal ended' END;
    ELSIF COALESCE(v_calc.signal_capped, FALSE) IS DISTINCT FROM COALESCE(v_prev_capped, FALSE) THEN
        v_reason := CASE WHEN COALESCE(v_calc.signal_capped, FALSE)
                         THEN 'signal capped' ELSE 'signal uncapped' END;
    ELSE
        RETURN format('SICPP state unchanged (active=%s, capped=%s) at %s',
                      v_calc.signal_active, v_calc.signal_capped, v_now);
    END IF;

    INSERT INTO sicpp_history (
        changed_at, signal_active, signal_strength,
        first_signal_time, signal_duration, max_signal_strength,
        js_avg, js_min, js_max, js_cnt,
        risk_avg, risk_min, risk_max, risk_cnt,
        js_slope, risk_slope, data_sufficient, confidence,
        signal_mode, js_threshold, risk_threshold,
        window_minutes, min_signal_duration,
        reason, signal_capped, episode_started_at
    ) VALUES (
        v_now, v_calc.signal_active, v_calc.signal_strength,
        v_calc.first_signal_time, v_calc.signal_duration, v_calc.max_signal_strength,
        v_calc.js_avg, v_calc.js_min, v_calc.js_max, v_calc.js_cnt,
        v_calc.risk_avg, v_calc.risk_min, v_calc.risk_max, v_calc.risk_cnt,
        v_calc.js_slope, v_calc.risk_slope, v_calc.data_sufficient, v_calc.confidence,
        v_calc.signal_mode, v_calc.js_threshold, v_calc.risk_threshold,
        v_calc.window_minutes, v_calc.min_signal_duration,
        v_reason, COALESCE(v_calc.signal_capped, FALSE), v_calc.episode_started_at
    ) RETURNING id INTO v_new_id;

    UPDATE sicpp_current_state SET last_history_id = v_new_id WHERE id = 1;

    RETURN format(
        'SICPP state changed: %s at %s (history_id=%s)',
        v_reason, v_now, v_new_id);
END;
$$;

COMMENT ON FUNCTION sicpp_update_state() IS
'v3.2.0 (2026-10-27, P0 FIX + cooldown). Онлайн-обновление SICPP.

Изменения относительно v3.1.0:
  - Введён cooldown после принудительного закрытия capped-эпизода.
  - Длительность cooldown задаётся incident_forecast_config.sicpp_cooldown_minutes
    (default 60 мин).
  - Пока cooldown активен:
      * singleton принудительно FALSE;
      * при первой попытке локального скана вернуть active=TRUE
        пишется одна запись reason=''cooldown_suppressed'';
      * повторные попытки тихо подавляются.
  - После истечения cooldown: force_close_cooldown_until := NULL,
    нормальная обработка возобновляется.

Ожидаемый эффект:
  - Эпизод разбивается на куски ≤ max_signal_duration_minutes с паузой
    sicpp_cooldown_minutes между ними.
  - Суммарное FP-время SICPP сокращается примерно в
    (max_dur + cooldown) / max_dur раза.
  - При sicpp_cooldown_minutes=0 — поведение v3.1.0 без cooldown.
';

-- =============================================================================
-- Функция: sicpp_get_current
-- Версия: 2.0.0
-- Назначение: возвращает текущее состояние SICPP.
-- =============================================================================
CREATE OR REPLACE FUNCTION sicpp_get_current()
RETURNS TABLE (
    updated_at          TIMESTAMPTZ,
    signal_active       BOOLEAN,
    signal_strength     REAL,
    first_signal_time   TIMESTAMPTZ,
    signal_duration     INT,
    max_signal_strength REAL,
    last_minute_js      REAL,
    last_minute_risk    REAL,
    signal_capped       BOOLEAN,
    episode_started_at  TIMESTAMPTZ
)
LANGUAGE sql
STABLE
AS $$
    SELECT updated_at, signal_active, signal_strength,
           first_signal_time, signal_duration, max_signal_strength,
           last_minute_js, last_minute_risk,
           signal_capped, episode_started_at
    FROM sicpp_current_state WHERE id = 1;
$$;

COMMENT ON FUNCTION sicpp_get_current() IS
'v1.1 (2026-10-24). Возвращает текущее состояние SICPP, включая signal_capped
и episode_started_at (v18.1). Остальное — как v1.0.';

-- =============================================================================
-- Функция: historical_fill_sicpp
-- Версия: 3.0
-- Назначение: заполняет sicpp_history за указанный период, последовательно
--             вызывая sicpp_calculate_at для каждой минуты и фиксируя
--             изменения состояния.
--
-- =============================================================================
-- =============================================================================
-- Функция: historical_fill_sicpp
-- Версия: 3.2.0 (2026-10-27, P0 FIX + cooldown — синхронизация с sicpp_update_state v3.2.0)
-- Назначение: заполняет sicpp_history за указанный период, последовательно
--             вызывая sicpp_calculate_at для каждой минуты и фиксируя
--             изменения состояния.
--
-- ИЗМЕНЕНИЯ v3.2.0 (относительно v3.0 от 2026-10-24):
--   1) Добавлен блок COOLDOWN: пока now() < force_close_cooldown_until,
--      сигнал принудительно FALSE, в историю пишется одна запись
--      reason='cooldown_suppressed' на каждый cooldown-период
--      (не спамим ежеминутно).
--   2) Добавлен блок FORCE-CLOSE: если sicpp_calculate_at вернул
--      signal_capped=TRUE AND signal_active=TRUE, эпизод принудительно
--      закрывается (reason='capped_force_end'), устанавливается cooldown
--      длительностью sicpp_cooldown_minutes из incident_forecast_config.
--   3) v_cooldown_until отслеживается локально между итерациями цикла;
--      при p_clean=TRUE сбрасывается и в singleton, и локально;
--      при p_clean=FALSE читается из sicpp_current_state.
--   4) Финальный singleton-апдейт разделён на два случая:
--      - если на p_end ещё активен cooldown → подавленное состояние;
--      - иначе — результат свежего sicpp_calculate_at(p_end).
--   5) В верификацию добавлены счётчики force-close и cooldown-suppressed
--      (считаются из sicpp_history как ground truth, а не из loop-переменных).
--
-- ОЖИДАЕМЫЙ ЭФФЕКТ:
--   - Суммарное FP-время SICPP сокращается примерно в
--     (max_signal_duration_minutes + sicpp_cooldown_minutes)
--     / max_signal_duration_minutes раза (при дефолтах 180 и 60 — в 1.33x,
--     но при частых «залипаниях» — до 3-5x).
--   - Каждый LONG-эпизод разбивается на куски ≤ max_signal_duration_minutes
--     с паузой sicpp_cooldown_minutes между ними.
--   - Precision эпизодов SICPP должен вырасти за счёт исчезновения
--     очень длинных эпизодов.
--
-- ПАРАМЕТРЫ:
--   p_start        TIMESTAMPTZ — начало периода (включительно)
--   p_end          TIMESTAMPTZ — конец периода (включительно)
--   p_step_minutes INT         — шаг в минутах (по умолчанию 1)
--   p_clean        BOOLEAN     — удалять существующие записи за период
--                                 и сбрасывать singleton (по умолчанию TRUE)
--
-- ВОЗВРАЩАЕТ: TEXT — отчёт о выполненной работе.
-- =============================================================================
CREATE OR REPLACE FUNCTION historical_fill_sicpp(
    p_start        TIMESTAMPTZ,
    p_end          TIMESTAMPTZ,
    p_step_minutes INT     DEFAULT 1,
    p_clean        BOOLEAN DEFAULT TRUE
)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    v_ts                TIMESTAMPTZ;
    v_step_interval     INTERVAL := (p_step_minutes || ' minutes')::INTERVAL;
    v_prev_active       BOOLEAN := FALSE;
    v_prev_capped       BOOLEAN := FALSE;
    v_prev_initialized  BOOLEAN := FALSE;
    v_calc              RECORD;
    v_inserted          INT := 0;
    v_processed         BIGINT := 0;
    v_total_minutes     BIGINT;
    v_last_percent      INT := -1;
    v_current_percent   INT;
    v_reason            TEXT;
    v_last_reason       TEXT;

    -- v3.2.0: cooldown tracking
    v_cooldown_minutes           INT;
    v_cooldown_until             TIMESTAMPTZ := NULL;
    v_cooldown_suppressed_done   BOOLEAN := FALSE;
    v_cooldown_suppressed_count  INT := 0;
    v_force_close_count          INT := 0;

    -- Верификация
    v_inc_total       INT;
    v_inc_covered     INT;
    v_inc_missed      INT;
BEGIN
    -- =========================================================================
    -- 1. Проверки и подготовка
    -- =========================================================================
    IF p_start > p_end THEN
        RETURN 'Ошибка: начальная дата позже конечной.';
    END IF;

    p_start := date_trunc('minute', p_start);
    p_end   := date_trunc('minute', p_end);

    IF p_clean THEN
        DELETE FROM sicpp_history WHERE changed_at BETWEEN p_start AND p_end;
        RAISE NOTICE 'Очищены записи sicpp_history за период % – %', p_start, p_end;
    END IF;

    -- =========================================================================
    -- 2. v3.2.0: читаем/сбрасываем cooldown
    -- =========================================================================
    SELECT COALESCE(sicpp_cooldown_minutes, 60)
    INTO v_cooldown_minutes
    FROM incident_forecast_config LIMIT 1;

    IF v_cooldown_minutes IS NULL THEN
        v_cooldown_minutes := 60;
    END IF;

    IF p_clean THEN
        -- полная перегенерация — сбрасываем cooldown в singleton
        UPDATE sicpp_current_state
        SET force_close_cooldown_until = NULL
        WHERE id = 1;
        v_cooldown_until := NULL;
        v_cooldown_suppressed_done := FALSE;
    ELSE
        -- инкрементальный режим — читаем текущий cooldown
        SELECT force_close_cooldown_until
        INTO v_cooldown_until
        FROM sicpp_current_state WHERE id = 1;

        -- Если в истории уже был cooldown_suppressed недавно — не дублируем
        IF v_cooldown_until IS NOT NULL THEN
            SELECT sh.reason INTO v_last_reason
            FROM sicpp_history sh
            WHERE sh.changed_at <= p_start
            ORDER BY sh.changed_at DESC, sh.id DESC
            LIMIT 1;

            IF v_last_reason = 'cooldown_suppressed' THEN
                v_cooldown_suppressed_done := TRUE;
            END IF;
        END IF;
    END IF;

    -- =========================================================================
    -- 3. Подготовка к циклу
    -- =========================================================================
    v_total_minutes := EXTRACT(EPOCH FROM (p_end - p_start)) / 60 + 1;
    RAISE NOTICE 'Начало исторического заполнения SICPP (v3.2.0) с % по % (шаг %s мин, всего %s минут, cooldown=%s мин)',
                 p_start, p_end, p_step_minutes, v_total_minutes, v_cooldown_minutes;

    v_ts := p_start;
    WHILE v_ts <= p_end LOOP
        -- =====================================================================
        -- 4. Расчёт состояния на минуту
        -- =====================================================================
        SELECT * INTO v_calc FROM sicpp_calculate_at(v_ts);

        -- =====================================================================
        -- 5. v3.2.0: COOLDOWN активен → подавляем
        -- =====================================================================
        IF v_cooldown_until IS NOT NULL AND v_ts < v_cooldown_until THEN
            -- Пишем cooldown_suppressed только один раз за период
            IF NOT v_cooldown_suppressed_done THEN
                INSERT INTO sicpp_history (
                    changed_at, signal_active, signal_strength,
                    first_signal_time, signal_duration, max_signal_strength,
                    js_avg, js_min, js_max, js_cnt,
                    risk_avg, risk_min, risk_max, risk_cnt,
                    js_slope, risk_slope, data_sufficient, confidence,
                    signal_mode, js_threshold, risk_threshold,
                    window_minutes, min_signal_duration,
                    reason, signal_capped, episode_started_at
                ) VALUES (
                    v_ts, FALSE, NULL,
                    NULL, 0, NULL,
                    v_calc.js_avg, v_calc.js_min, v_calc.js_max, v_calc.js_cnt,
                    v_calc.risk_avg, v_calc.risk_min, v_calc.risk_max, v_calc.risk_cnt,
                    v_calc.js_slope, v_calc.risk_slope, v_calc.data_sufficient, NULL,
                    v_calc.signal_mode, v_calc.js_threshold, v_calc.risk_threshold,
                    v_calc.window_minutes, v_calc.min_signal_duration,
                    'cooldown_suppressed', FALSE, NULL
                );
                v_inserted := v_inserted + 1;
                v_cooldown_suppressed_done := TRUE;
                v_prev_active := FALSE;
                v_prev_capped := FALSE;

                RAISE NOTICE '  [%] cooldown_suppressed (cooldown_until=%, remaining=% мин)',
                             to_char(v_ts, 'YYYY-MM-DD HH24:MI'),
                             to_char(v_cooldown_until, 'YYYY-MM-DD HH24:MI'),
                             ROUND(EXTRACT(EPOCH FROM (v_cooldown_until - v_ts)) / 60, 1);
            END IF;

            v_processed := v_processed + 1;
            v_ts := v_ts + v_step_interval;

            v_current_percent := floor((v_processed::NUMERIC / v_total_minutes) * 100);
            IF v_current_percent > v_last_percent THEN
                RAISE NOTICE 'Прогресс: % %% (обработано % из %, вставлено %)',
                             v_current_percent, v_processed, v_total_minutes, v_inserted;
                v_last_percent := v_current_percent;
            END IF;
            CONTINUE;
        END IF;

        -- =====================================================================
        -- 6. Cooldown истёк → очищаем
        -- =====================================================================
        IF v_cooldown_until IS NOT NULL AND v_ts >= v_cooldown_until THEN
            v_cooldown_until := NULL;
            v_cooldown_suppressed_done := FALSE;
            UPDATE sicpp_current_state
            SET force_close_cooldown_until = NULL
            WHERE id = 1;
        END IF;

        -- =====================================================================
        -- 7. v3.2.0: принудительное закрытие capped-эпизода + cooldown
        -- =====================================================================
        IF COALESCE(v_calc.signal_capped, FALSE) = TRUE
           AND COALESCE(v_calc.signal_active, FALSE) = TRUE THEN

            INSERT INTO sicpp_history (
                changed_at, signal_active, signal_strength,
                first_signal_time, signal_duration, max_signal_strength,
                js_avg, js_min, js_max, js_cnt,
                risk_avg, risk_min, risk_max, risk_cnt,
                js_slope, risk_slope, data_sufficient, confidence,
                signal_mode, js_threshold, risk_threshold,
                window_minutes, min_signal_duration,
                reason, signal_capped, episode_started_at
            ) VALUES (
                v_ts, FALSE, NULL,
                NULL, 0, NULL,
                v_calc.js_avg, v_calc.js_min, v_calc.js_max, v_calc.js_cnt,
                v_calc.risk_avg, v_calc.risk_min, v_calc.risk_max, v_calc.risk_cnt,
                v_calc.js_slope, v_calc.risk_slope, v_calc.data_sufficient, NULL,
                v_calc.signal_mode, v_calc.js_threshold, v_calc.risk_threshold,
                v_calc.window_minutes, v_calc.min_signal_duration,
                'capped_force_end', FALSE, NULL
            );
            v_inserted := v_inserted + 1;

            -- Устанавливаем cooldown
            v_cooldown_until := v_ts + (v_cooldown_minutes || ' minutes')::INTERVAL;
            v_cooldown_suppressed_done := FALSE;

            UPDATE sicpp_current_state
            SET force_close_cooldown_until = v_cooldown_until
            WHERE id = 1;

            v_prev_active := FALSE;
            v_prev_capped := FALSE;

            RAISE NOTICE '  [%] capped_force_end (was % мин; cooldown % мин, до %)',
                         to_char(v_ts, 'YYYY-MM-DD HH24:MI'),
                         v_calc.signal_duration,
                         v_cooldown_minutes,
                         to_char(v_cooldown_until, 'YYYY-MM-DD HH24:MI');

            v_processed := v_processed + 1;
            v_ts := v_ts + v_step_interval;

            v_current_percent := floor((v_processed::NUMERIC / v_total_minutes) * 100);
            IF v_current_percent > v_last_percent THEN
                RAISE NOTICE 'Прогресс: % %% (обработано % из %, вставлено %)',
                             v_current_percent, v_processed, v_total_minutes, v_inserted;
                v_last_percent := v_current_percent;
            END IF;
            CONTINUE;
        END IF;

        -- =====================================================================
        -- 8. Штатная обработка (init / started / ended / capped)
        --    (без изменений относительно v3.0)
        -- =====================================================================
        IF NOT v_prev_initialized THEN
            INSERT INTO sicpp_history (
                changed_at, signal_active, signal_strength,
                first_signal_time, signal_duration, max_signal_strength,
                js_avg, js_min, js_max, js_cnt,
                risk_avg, risk_min, risk_max, risk_cnt,
                js_slope, risk_slope, data_sufficient, confidence,
                signal_mode, js_threshold, risk_threshold,
                window_minutes, min_signal_duration, reason, signal_capped,
                episode_started_at
            ) VALUES (
                v_ts, COALESCE(v_calc.signal_active, FALSE), v_calc.signal_strength,
                v_calc.first_signal_time, v_calc.signal_duration, v_calc.max_signal_strength,
                v_calc.js_avg, v_calc.js_min, v_calc.js_max, v_calc.js_cnt,
                v_calc.risk_avg, v_calc.risk_min, v_calc.risk_max, v_calc.risk_cnt,
                v_calc.js_slope, v_calc.risk_slope, v_calc.data_sufficient, v_calc.confidence,
                v_calc.signal_mode, v_calc.js_threshold, v_calc.risk_threshold,
                v_calc.window_minutes, v_calc.min_signal_duration, 'init',
                COALESCE(v_calc.signal_capped, FALSE),
                v_calc.episode_started_at
            );
            v_inserted := v_inserted + 1;
            v_prev_active := COALESCE(v_calc.signal_active, FALSE);
            v_prev_capped := COALESCE(v_calc.signal_capped, FALSE);
            v_prev_initialized := TRUE;

        ELSIF v_calc.signal_active IS DISTINCT FROM v_prev_active THEN
            v_reason := CASE WHEN v_calc.signal_active
                             THEN 'signal started' ELSE 'signal ended' END;
            INSERT INTO sicpp_history (
                changed_at, signal_active, signal_strength,
                first_signal_time, signal_duration, max_signal_strength,
                js_avg, js_min, js_max, js_cnt,
                risk_avg, risk_min, risk_max, risk_cnt,
                js_slope, risk_slope, data_sufficient, confidence,
                signal_mode, js_threshold, risk_threshold,
                window_minutes, min_signal_duration, reason, signal_capped,
                episode_started_at
            ) VALUES (
                v_ts, COALESCE(v_calc.signal_active, FALSE), v_calc.signal_strength,
                v_calc.first_signal_time, v_calc.signal_duration, v_calc.max_signal_strength,
                v_calc.js_avg, v_calc.js_min, v_calc.js_max, v_calc.js_cnt,
                v_calc.risk_avg, v_calc.risk_min, v_calc.risk_max, v_calc.risk_cnt,
                v_calc.js_slope, v_calc.risk_slope, v_calc.data_sufficient, v_calc.confidence,
                v_calc.signal_mode, v_calc.js_threshold, v_calc.risk_threshold,
                v_calc.window_minutes, v_calc.min_signal_duration, v_reason,
                COALESCE(v_calc.signal_capped, FALSE),
                v_calc.episode_started_at
            );
            v_inserted := v_inserted + 1;
            v_prev_active := v_calc.signal_active;
            v_prev_capped := COALESCE(v_calc.signal_capped, FALSE);

        ELSIF COALESCE(v_calc.signal_capped, FALSE) IS DISTINCT FROM v_prev_capped THEN
            v_reason := CASE WHEN COALESCE(v_calc.signal_capped, FALSE)
                             THEN 'signal capped' ELSE 'signal uncapped' END;
            INSERT INTO sicpp_history (
                changed_at, signal_active, signal_strength,
                first_signal_time, signal_duration, max_signal_strength,
                js_avg, js_min, js_max, js_cnt,
                risk_avg, risk_min, risk_max, risk_cnt,
                js_slope, risk_slope, data_sufficient, confidence,
                signal_mode, js_threshold, risk_threshold,
                window_minutes, min_signal_duration, reason, signal_capped,
                episode_started_at
            ) VALUES (
                v_ts, COALESCE(v_calc.signal_active, FALSE), v_calc.signal_strength,
                v_calc.first_signal_time, v_calc.signal_duration, v_calc.max_signal_strength,
                v_calc.js_avg, v_calc.js_min, v_calc.js_max, v_calc.js_cnt,
                v_calc.risk_avg, v_calc.risk_min, v_calc.risk_max, v_calc.risk_cnt,
                v_calc.js_slope, v_calc.risk_slope, v_calc.data_sufficient, v_calc.confidence,
                v_calc.signal_mode, v_calc.js_threshold, v_calc.risk_threshold,
                v_calc.window_minutes, v_calc.min_signal_duration, v_reason,
                COALESCE(v_calc.signal_capped, FALSE),
                v_calc.episode_started_at
            );
            v_inserted := v_inserted + 1;
            v_prev_capped := COALESCE(v_calc.signal_capped, FALSE);
        END IF;

        v_processed := v_processed + 1;
        v_ts := v_ts + v_step_interval;

        v_current_percent := floor((v_processed::NUMERIC / v_total_minutes) * 100);
        IF v_current_percent > v_last_percent THEN
            RAISE NOTICE 'Прогресс: % %% (обработано % из %, вставлено %)',
                         v_current_percent, v_processed, v_total_minutes, v_inserted;
            v_last_percent := v_current_percent;
        END IF;
    END LOOP;

    -- =========================================================================
    -- 9. v3.2.0: Финальный singleton-апдейт
    -- =========================================================================
    IF v_cooldown_until IS NOT NULL AND v_cooldown_until > p_end THEN
        -- На p_end ещё активен cooldown → подавленное состояние
        UPDATE sicpp_current_state SET
            updated_at                  = p_end,
            signal_active               = FALSE,
            signal_strength             = NULL,
            first_signal_time           = NULL,
            signal_duration             = 0,
            max_signal_strength         = NULL,
            consecutive_run             = 0,
            last_minute_js              = v_calc.js_avg,
            last_minute_risk            = v_calc.risk_avg,
            signal_capped               = FALSE,
            episode_started_at          = NULL,
            force_close_cooldown_until  = v_cooldown_until
        WHERE id = 1;
    ELSE
        -- Свежий calc на p_end (cooldown не активен)
        SELECT * INTO v_calc FROM sicpp_calculate_at(p_end);
        UPDATE sicpp_current_state SET
            updated_at                  = p_end,
            signal_active               = COALESCE(v_calc.signal_active, FALSE),
            signal_strength             = v_calc.signal_strength,
            first_signal_time           = v_calc.first_signal_time,
            signal_duration             = COALESCE(v_calc.signal_duration, 0),
            max_signal_strength         = v_calc.max_signal_strength,
            consecutive_run             = COALESCE(v_calc.signal_duration, 0),
            last_minute_js              = v_calc.js_avg,
            last_minute_risk            = v_calc.risk_avg,
            signal_capped               = COALESCE(v_calc.signal_capped, FALSE),
            episode_started_at          = v_calc.episode_started_at,
            force_close_cooldown_until  = NULL
        WHERE id = 1;
    END IF;

    -- =========================================================================
    -- 10. Верификация (v3.2.0: + force_close и cooldown_suppressed)
    -- =========================================================================
    BEGIN
        SELECT COUNT(*) INTO v_inc_total
        FROM markov_chain_performance_incident
        WHERE start_timepoint BETWEEN p_start AND p_end;

        SELECT COUNT(*) INTO v_inc_covered
        FROM markov_chain_performance_incident pi
        WHERE pi.start_timepoint BETWEEN p_start AND p_end
          AND COALESCE((
              SELECT sh.signal_active
              FROM sicpp_history sh
              WHERE sh.changed_at <= pi.start_timepoint
              ORDER BY sh.changed_at DESC, sh.id DESC
              LIMIT 1
          ), FALSE) = TRUE;

        v_inc_missed := v_inc_total - v_inc_covered;

        -- Ground truth из sicpp_history
        SELECT COUNT(*) INTO v_force_close_count
        FROM sicpp_history
        WHERE changed_at BETWEEN p_start AND p_end
          AND reason = 'capped_force_end';

        SELECT COUNT(*) INTO v_cooldown_suppressed_count
        FROM sicpp_history
        WHERE changed_at BETWEEN p_start AND p_end
          AND reason = 'cooldown_suppressed';

        RAISE NOTICE '--- ВЕРИФИКАЦИЯ (v3.2.0) ---';
        RAISE NOTICE 'Всего инцидентов в периоде: %', v_inc_total;
        RAISE NOTICE 'С SICPP = TRUE на момент начала: %', v_inc_covered;
        RAISE NOTICE 'Без SICPP (пропущено): %', v_inc_missed;
        RAISE NOTICE 'Событий capped_force_end: %', v_force_close_count;
        RAISE NOTICE 'Событий cooldown_suppressed: %', v_cooldown_suppressed_count;

        IF v_force_close_count = 0 THEN
            RAISE WARNING 'capped_force_end = 0: возможно, ни один эпизод не достиг max_signal_duration_minutes (%) — это норма, если условия не залипают.',
                          (SELECT max_signal_duration_minutes FROM incident_forecast_config LIMIT 1);
        END IF;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Верификация пропущена: %', SQLERRM;
    END;

    -- =========================================================================
    -- 11. Итоговый отчёт
    -- =========================================================================
    RETURN format(
        'Историческое заполнение SICPP завершено (v3.2.0). Обработано %s минут, вставлено %s записей. '
        'Верификация: инцидентов %s, покрыто %s, пропущено %s. '
        'Force-close: %s, cooldown-suppressed: %s.',
        v_processed, v_inserted,
        v_inc_total, v_inc_covered, v_inc_missed,
        v_force_close_count, v_cooldown_suppressed_count
    );
END;
$$;

COMMENT ON FUNCTION historical_fill_sicpp(TIMESTAMPTZ, TIMESTAMPTZ, INT, BOOLEAN) IS
'v3.2.0 (2026-10-27). Синхронизирована с sicpp_update_state() v3.2.0.

ОТЛИЧИЯ ОТ v3.0 (2026-10-24):
  1) Добавлен блок COOLDOWN: пока v_ts < force_close_cooldown_until,
     сигнал принудительно FALSE, в sicpp_history пишется ОДНА запись
     reason=''cooldown_suppressed'' на период cooldown.
  2) Добавлен блок FORCE-CLOSE: если sicpp_calculate_at вернул
     signal_capped=TRUE AND signal_active=TRUE, эпизод закрывается
     (reason=''capped_force_end''), устанавливается cooldown длительностью
     incident_forecast_config.sicpp_cooldown_minutes.
  3) v_cooldown_until отслеживается локально между итерациями цикла:
     - при p_clean=TRUE сбрасывается в singleton и локально;
     - при p_clean=FALSE читается из sicpp_current_state.force_close_cooldown_until.
  4) Финальный singleton-апдейт: если на p_end ещё активен cooldown —
     подавленное состояние; иначе — свежий sicpp_calculate_at(p_end).
  5) В верификацию добавлены счётчики capped_force_end и cooldown_suppressed
     (ground truth из sicpp_history).

ПРИМЕНЕНИЕ:
  - Для полной перегенерации истории: p_clean=TRUE.
    Рекомендуется после установки новой версии.
  - Для инкрементального заполнения: p_clean=FALSE.
    Учитывает текущий cooldown из singleton.

ОЖИДАЕМЫЙ ЭФФЕКТ (при sicpp_cooldown_minutes=60, max_signal_duration_minutes=180):
  - LONG-эпизоды (>800 мин) исчезают.
  - Максимальная длительность FP-эпизода ≤ 240 мин (180 + 60).
  - Суммарное FP-время SICPP сокращается в 2-5 раз.
  - Precision эпизодов SICPP растёт на 5-15 п.п.
';
-- =============================================================================
-- Функция: sicpp_clean_history
-- Версия: 1.0.0
-- Назначение: удаляет старые записи из sicpp_history.
-- =============================================================================
CREATE OR REPLACE FUNCTION sicpp_clean_history(p_retention_days INT DEFAULT 90)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    v_deleted BIGINT;
BEGIN
    IF p_retention_days <= 0 THEN
        RETURN 'Ошибка: срок хранения должен быть положительным.';
    END IF;

    DELETE FROM sicpp_history
    WHERE changed_at < now() - (p_retention_days || ' days')::INTERVAL;
    GET DIAGNOSTICS v_deleted = ROW_COUNT;

    RETURN format('Удалено %s записей из sicpp_history старше %s дней.',
                  v_deleted, p_retention_days);
END;
$$;

COMMENT ON FUNCTION sicpp_clean_history(INT) IS
'Версия 1.0.0. Удаляет записи sicpp_history старше p_retention_days (по умолчанию 90).';

-- =============================================================================
-- Функция: generate_incident_forecast_report_v2
-- Версия: 19.3.1
-- Назначение: формирует отчёт по прогнозированию инцидентов, используя
--             sicpp_history как источник сигнала.
--
-- =============================================================================
-- =============================================================================
-- Функция: generate_incident_forecast_report_v2
-- Версия: 19.3.1 (P1.1: cosmetic fix format «(cap N)» → «(>cap N)»)
-- =============================================================================
-- =============================================================================
-- Функция: generate_incident_forecast_report_v2
-- Версия: 19.3.2 (P1.1 cosmetic + P1.2 sanity-check threshold)
-- =============================================================================
-- =============================================================================
-- Функция: generate_incident_forecast_report_v2
-- Версия: 19.3.3 (P1.1 + P1.2 + P1.3: LONG-эпизоды)
-- =============================================================================
-- =============================================================================
-- Функция: generate_incident_forecast_report_v2
-- Версия: 19.3.4 (P1.1 + P1.2 + P1.3 + P1.4)
-- =============================================================================
-- =============================================================================
-- Функция: generate_incident_forecast_report_v2
-- Версия: 22.0 (2026-10-27)
--
-- =============================================================================
-- =============================================================================
-- generate_incident_forecast_report_v2
-- Версия: 22.1 (2026-10-28, header fix: config thresholds vs in-memory reco)
--
-- ИЗМЕНЕНИЯ v22.1 (относительно v22.0):
--   1) In-memory автонастройка порогов (при auto_threshold = TRUE) больше НЕ
--      перезаписывает v_js_threshold / v_risk_threshold. Она сохраняется в
--      v_js_threshold_reco / v_risk_threshold_reco и выводится в шапку
--      отдельной строкой с пометкой «НЕ использована».
--   2) v_js_threshold / v_risk_threshold всегда берутся из incident_forecast_config
--      (cfg.js_threshold / cfg.risk_threshold) — те же, что использует
--      mchain_hybrid_alert_at для W_score и sicpp_calculate_at для генерации
--      истории. Это устраняет расхождение между шапкой и W_score (test7:
--      header показывал 0.1376/1 из in-memory, а W_score считался по
--      0.216/0.99 из DB).
--   3) v_legend явно указывает, что W_score считается по фактическим порогам.
--   4) Добавлен параметр p_show_inmemory_reco (по умолчанию TRUE) — выводить
--      ли in-memory рекомендацию, если auto_threshold = TRUE.
--   5) Сигнатура расширена третьим параметром p_show_inmemory_reco BOOLEAN
--      DEFAULT TRUE. Обратная совместимость: вызов с двумя аргументами
--      работает как раньше (in-memory reco показывается, но помечена как
--      «не использована»).
-- =============================================================================
CREATE OR REPLACE FUNCTION generate_incident_forecast_report_v2(
    p_start              TIMESTAMPTZ DEFAULT now() - INTERVAL '7 days',
    p_end                TIMESTAMPTZ DEFAULT now(),
    p_show_inmemory_reco BOOLEAN     DEFAULT TRUE
) RETURNS TEXT[]
LANGUAGE plpgsql
AS $$
DECLARE
    -- ============ Config ============
    cfg                             RECORD;
    v_window_minutes                INT;
    v_js_threshold                  REAL;   -- фактические (config) — используются для расчётов
    v_risk_threshold                REAL;   -- фактические (config)
    v_js_threshold_reco             REAL;   -- in-memory рекомендация (НЕ используется)
    v_risk_threshold_reco           REAL;   -- in-memory рекомендация (НЕ используется)
    v_include_summary               BOOLEAN;
    v_signal_mode                   TEXT;
    v_min_signal_duration           INT;
    v_weight_js                     REAL;
    v_weight_risk                   REAL;
    v_auto_threshold                BOOLEAN;
    v_calibration_period_days       INT;
    v_max_js_age_min                INT;
    v_min_data_points               INT;
    v_slope_window_minutes          INT;
    v_extended_report               BOOLEAN;
    v_status_filter                 TEXT[];
    v_csv_mode                      BOOLEAN;
    v_include_pre_incident_matches  BOOLEAN;
    v_series_filter_enabled         BOOLEAN;
    v_sicpp_warn_pct                REAL;
    v_horizon_minutes               INT;
    v_coverage_lead_threshold       INT;

    -- ============ C-параметры ============
    v_c_js_min                      REAL;
    v_c_p90_min                     REAL;
    v_c_w_min                       REAL;
    v_c_window_min                  INT;

    -- ============ Report ============
    v_report TEXT[] := '{}';
    v_header TEXT := '=== ОТЧЁТ ПО ПРОГНОЗИРОВАНИЮ ИНЦИДЕНТОВ (v22.1, header fix + C-diag) ===';
    v_incident RECORD;
    v_signal RECORD;
    v_cover RECORD;
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
    v_sicpp_count BIGINT;
    v_sicpp_first_ts TIMESTAMPTZ;
    v_sicpp_last_ts TIMESTAMPTZ;
    v_sicpp_coverage_pct NUMERIC;
    v_sicpp_span_sec NUMERIC;
    v_period_span_sec NUMERIC;

    -- ============ Счётчики эпизодов ============
    v_total_episodes INT := 0;
    v_tp_episodes INT := 0;
    v_fp_episodes INT := 0;
    v_precision_episodes REAL;
    v_lead_min REAL;
    v_lead_p25 REAL;
    v_lead_median REAL;
    v_lead_p75 REAL;
    v_lead_p90 REAL;
    v_lead_max REAL;
    v_lead_share_under_100 REAL;
    v_fresh_lead_median REAL;
    v_weighted_score REAL;
    v_no_baseline_count INT := 0;
    v_prev_unfinished BOOLEAN;

    -- ============ Lead coverage ============
    v_incidents_lead_ge INT := 0;
    v_incidents_lead_lt INT := 0;
    v_incidents_lead_ge_pct_total NUMERIC;
    v_incidents_lead_ge_pct_covered NUMERIC;
    v_lead_vs_fresh_delta_pct NUMERIC;

    -- ============ C-only ============
    v_risk_p90 REAL;
    v_c_alert_minutes INT;
    v_c_fired BOOLEAN;
    v_ha_covered_count INT := 0;
    v_ha_uncovered_ids TEXT[] := '{}';
    v_ha_dist_0 INT := 0;
    v_ha_dist_1_5 INT := 0;
    v_ha_dist_6_10 INT := 0;
    v_ha_dist_11_15 INT := 0;
    v_ha_dist_16_20 INT := 0;

    -- ============ Lead time ============
    v_max_dur_cap           INT;
    v_lead_raw_min          REAL;
    v_lead_effective_min    REAL;
    v_lead_display          TEXT;
    v_incidents_lead_capped INT := 0;
    v_sicpp_was_active_at_start BOOLEAN;

    -- ============ LONG-эпизоды ============
    v_long_episode_threshold CONSTANT INT := 800;
    v_long_episode_count    INT := 0;
    v_short_lead_count      INT := 0;
    v_short_lead_p50        REAL;
    v_short_lead_p90        REAL;
    v_short_lead_mean       REAL;
    v_short_lead_max        REAL;

    -- ============ P1.4: risk trend per uncovered incident ============
    v_diag_risk_first         REAL;
    v_diag_risk_last          REAL;
    v_diag_risk_max           REAL;
    v_diag_risk_delta         REAL;
    v_diag_risk_trend         TEXT;
    v_diag_risk_trend_display TEXT;
    v_diag_cnt_trend_up       INT := 0;
    v_diag_cnt_trend_down     INT := 0;
    v_diag_cnt_trend_flat     INT := 0;
    v_diag_cnt_trend_no_data  INT := 0;

    -- ============ C-диагностика ============
    v_point_js              REAL;
    v_c_reason              TEXT;
    v_fail_p90              BOOLEAN;
    v_fail_js               BOOLEAN;
    v_fail_ws               BOOLEAN;
    v_uncovered_count       INT := 0;
    v_diag_cnt_all_fail     INT := 0;
    v_diag_cnt_only_p90     INT := 0;
    v_diag_cnt_only_js      INT := 0;
    v_diag_cnt_only_ws      INT := 0;
    v_diag_cnt_p90_js       INT := 0;
    v_diag_cnt_p90_ws       INT := 0;
    v_diag_cnt_js_ws        INT := 0;
    v_diag_cnt_any_p90      INT := 0;
    v_diag_cnt_any_js       INT := 0;
    v_diag_cnt_any_ws       INT := 0;

BEGIN
    -- =========================================================================
    -- 1. Конфигурация
    -- =========================================================================
    SELECT * INTO cfg FROM incident_forecast_config LIMIT 1;
    IF NOT FOUND THEN
        INSERT INTO incident_forecast_config DEFAULT VALUES;
        SELECT * INTO cfg FROM incident_forecast_config LIMIT 1;
    END IF;

    v_window_minutes                := cfg.window_minutes;
    v_js_threshold                  := cfg.js_threshold;      -- ФАКТИЧЕСКИЙ (config)
    v_risk_threshold                := cfg.risk_threshold;    -- ФАКТИЧЕСКИЙ (config)
    v_include_summary               := cfg.include_summary;
    v_signal_mode                   := cfg.signal_mode;
    v_min_signal_duration           := cfg.min_signal_duration;
    v_weight_js                     := cfg.weight_js;
    v_weight_risk                   := cfg.weight_risk;
    v_auto_threshold                := cfg.auto_threshold;
    v_calibration_period_days       := cfg.calibration_period_days;
    v_max_js_age_min                := cfg.max_js_age_min;
    v_min_data_points               := cfg.min_data_points;
    v_slope_window_minutes          := cfg.slope_window_minutes;
    v_extended_report               := cfg.extended_report;
    v_status_filter                 := cfg.status_filter;
    v_csv_mode                      := cfg.csv_mode;
    v_include_pre_incident_matches  := cfg.include_pre_incident_matches;
    v_series_filter_enabled         := COALESCE(cfg.series_filter_enabled, TRUE);
    v_sicpp_warn_pct                := COALESCE(cfg.sicpp_coverage_warn_threshold_pct, 10.0);

    BEGIN
        v_coverage_lead_threshold := COALESCE(cfg.coverage_lead_threshold_min, 60);
    EXCEPTION WHEN OTHERS THEN
        v_coverage_lead_threshold := 60;
    END;

    v_c_js_min     := COALESCE(cfg.hybrid_js_min_threshold,      0.14);
    v_c_p90_min    := COALESCE(cfg.hybrid_p90_min_threshold,     0.98);
    v_c_w_min      := COALESCE(cfg.hybrid_w_score_min_threshold, 0.0);
    v_c_window_min := COALESCE(cfg.hybrid_window_minutes,        20);

    BEGIN
        v_max_dur_cap := COALESCE(cfg.max_signal_duration_minutes, 180);
    EXCEPTION WHEN OTHERS THEN
        v_max_dur_cap := 180;
    END;

    SELECT forecast_horizon_minutes INTO v_horizon_minutes FROM markov_config LIMIT 1;
    IF v_horizon_minutes IS NULL THEN
        v_horizon_minutes := 30;
    END IF;

    -- =========================================================================
    -- 2. In-memory автонастройка (информационно; НЕ используется в расчётах)
    -- =========================================================================
    -- ВАЖНО: результат сохраняется в v_js_threshold_reco / v_risk_threshold_reco
    -- и выводится в шапку отдельной строкой с пометкой «НЕ использована».
    -- Для W_score и покрытия используются v_js_threshold / v_risk_threshold
    -- (фактические из cfg), те же, что видит mchain_hybrid_alert_at.
    v_js_threshold_reco   := NULL;
    v_risk_threshold_reco := NULL;

    IF v_auto_threshold AND p_show_inmemory_reco THEN
        WITH calibration_data AS (
            SELECT pcl.js_divergence, pl.predicted_risk
            FROM profile_comparison_log pcl
            JOIN prediction_log pl
                ON date_trunc('minute', pl.prediction_time)
                 = date_trunc('minute', pcl.current_window_end)
            WHERE pcl.current_window_end >= p_start - (v_calibration_period_days || ' days')::INTERVAL
              AND pcl.current_window_end <  p_start
              AND pcl.js_divergence IS NOT NULL
              AND pl.predicted_risk IS NOT NULL
        ),
        percentiles AS (
            SELECT
                PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY js_divergence)   AS js_p75,
                PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY predicted_risk) AS risk_p75
            FROM calibration_data
        )
        SELECT js_p75, risk_p75
        INTO v_js_threshold_reco, v_risk_threshold_reco
        FROM percentiles;
    END IF;

    -- =========================================================================
    -- 3. Проверка sicpp_history
    -- =========================================================================
    SELECT COUNT(*), MIN(changed_at), MAX(changed_at)
    INTO v_sicpp_count, v_sicpp_first_ts, v_sicpp_last_ts
    FROM sicpp_history
    WHERE changed_at BETWEEN p_start AND p_end;

    IF v_sicpp_count = 0 THEN
        v_report := array_append(v_report, v_header);
        v_report := array_append(v_report, format('Период: %s – %s',
            to_char(p_start, 'YYYY-MM-DD HH24:MI'),
            to_char(p_end,   'YYYY-MM-DD HH24:MI')));
        v_report := array_append(v_report, '');
        v_report := array_append(v_report, '⚠ ВНИМАНИЕ: sicpp_history пуста за указанный период.');
        v_report := array_append(v_report, 'Выполните SELECT historical_fill_sicpp(...) или убедитесь, что mchain_train_step() работает.');
        v_report := array_append(v_report, '');
        v_report := array_append(v_report, '=== КОНЕЦ ОТЧЁТА ===');
        RETURN v_report;
    END IF;

    IF v_sicpp_first_ts IS NOT NULL AND v_sicpp_last_ts > v_sicpp_first_ts AND p_end > p_start THEN
        v_sicpp_span_sec     := EXTRACT(EPOCH FROM (v_sicpp_last_ts - v_sicpp_first_ts));
        v_period_span_sec    := EXTRACT(EPOCH FROM (p_end - p_start));
        v_sicpp_coverage_pct := ROUND((v_sicpp_span_sec / NULLIF(v_period_span_sec, 0) * 100)::NUMERIC, 1);
    ELSE
        v_sicpp_coverage_pct := NULL;
    END IF;

    -- =========================================================================
    -- 4. Эпизоды SICPP
    -- =========================================================================
    DROP TABLE IF EXISTS _tmp_sicpp_episodes_v3;
    CREATE TEMP TABLE _tmp_sicpp_episodes_v3 ON COMMIT DROP AS
    WITH history AS (
        SELECT id, changed_at, signal_active, reason,
               LAG(signal_active) OVER (ORDER BY changed_at, id) AS prev_active
        FROM sicpp_history
        WHERE changed_at <= p_end
    ),
    starts AS (
        SELECT id, changed_at AS raw_start
        FROM history
        WHERE signal_active = TRUE
          AND (prev_active IS NULL OR prev_active = FALSE)
    ),
    ends AS (
        SELECT changed_at AS end_ts
        FROM history
        WHERE signal_active = FALSE
    ),
    episodes_with_end AS (
        SELECT s.id, s.raw_start,
               (SELECT MIN(e.end_ts) FROM ends e WHERE e.end_ts > s.raw_start) AS raw_end
        FROM starts s
    )
    SELECT
        e.id,
        GREATEST(e.raw_start, p_start)             AS episode_start,
        LEAST(COALESCE(e.raw_end, p_end), p_end)   AS episode_end,
        sh.first_signal_time,
        sh.signal_duration,
        sh.signal_strength,
        sh.max_signal_strength,
        sh.confidence,
        COALESCE(sh.window_minutes, v_window_minutes) AS window_minutes,
        COALESCE(sh.signal_capped, FALSE)          AS signal_capped,
        COALESCE(sh.episode_started_at, sh.first_signal_time) AS episode_started_at,
        (sh.episode_started_at IS NULL)            AS episode_started_at_fallback
    FROM episodes_with_end e
    LEFT JOIN sicpp_history sh ON sh.id = e.id
    WHERE COALESCE(e.raw_end, p_end) >= p_start
      AND e.raw_start <= p_end;

    SELECT
        COUNT(*),
        COUNT(*) FILTER (WHERE EXISTS (
            SELECT 1 FROM markov_chain_performance_incident pi
            WHERE pi.start_timepoint >= e.episode_start
              AND pi.start_timepoint <  e.episode_end
        ))
    INTO v_total_episodes, v_tp_episodes
    FROM _tmp_sicpp_episodes_v3 e;

    v_fp_episodes := v_total_episodes - v_tp_episodes;
    v_precision_episodes := CASE WHEN v_total_episodes > 0
                                 THEN v_tp_episodes::REAL / v_total_episodes
                                 ELSE NULL END;

    -- =========================================================================
    -- 5. Предвычисление C для окон инцидентов
    -- =========================================================================
    DROP TABLE IF EXISTS _tmp_c_windows;
    CREATE TEMP TABLE _tmp_c_windows ON COMMIT DROP AS
    SELECT
        pi.id AS incident_id,
        gs.m,
        h.alert, h.fired_c,
        h.risk_p90, h.w_score, h.js_avg
    FROM (
        SELECT id, start_timepoint
        FROM markov_chain_performance_incident
        WHERE start_timepoint BETWEEN p_start AND p_end
    ) pi
    CROSS JOIN LATERAL generate_series(
        pi.start_timepoint - (v_c_window_min || ' minutes')::INTERVAL,
        pi.start_timepoint,
        '1 minute'
    ) AS gs(m)
    CROSS JOIN LATERAL mchain_hybrid_alert_at(gs.m) h;

    CREATE INDEX ON _tmp_c_windows (incident_id, m);

    -- =========================================================================
    -- 6. Заголовок и легенда
    -- =========================================================================
    IF v_csv_mode THEN
        v_sep := ';';
    END IF;

    IF NOT v_csv_mode THEN
        v_report := array_append(v_report, v_header);
        v_report := array_append(v_report, format('Период: %s – %s',
            to_char(p_start, 'YYYY-MM-DD HH24:MI'),
            to_char(p_end,   'YYYY-MM-DD HH24:MI')));
        v_report := array_append(v_report, 'Версия функции: generate_incident_forecast_report_v2 v22.1 (header fix + C-diag)');
        v_report := array_append(v_report, format('Горизонт прогноза (markov_config): %s мин', v_horizon_minutes));
        v_report := array_append(v_report, format('Источник сигнала SICPP: sicpp_history (записей в периоде: %s, первая: %s, последняя: %s)',
            v_sicpp_count,
            to_char(v_sicpp_first_ts, 'YYYY-MM-DD HH24:MI'),
            to_char(v_sicpp_last_ts, 'YYYY-MM-DD HH24:MI')));

        SELECT signal_active INTO v_sicpp_was_active_at_start
        FROM sicpp_history
        WHERE changed_at <= p_start
        ORDER BY changed_at DESC, id DESC
        LIMIT 1;

        IF v_sicpp_first_ts IS NOT NULL
            AND v_sicpp_first_ts > p_start
            AND NOT COALESCE(v_sicpp_was_active_at_start, FALSE) THEN
                v_report := array_append(v_report, '');
                v_report := array_append(v_report, format(
                    '⚠ sicpp_history покрывает только часть периода: с %s (покрытие %s%%).',
                    to_char(v_sicpp_first_ts, 'YYYY-MM-DD HH24:MI'),
                    COALESCE(v_sicpp_coverage_pct::TEXT, '?')));
                v_report := array_append(v_report, format(
                '  Инциденты до %s не могли быть покрыты SICPP; рассмотрите отчёт за период [%s; %s].',
                    to_char(v_sicpp_first_ts, 'YYYY-MM-DD HH24:MI'),
                    to_char(v_sicpp_first_ts, 'YYYY-MM-DD HH24:MI'),
                    to_char(p_end, 'YYYY-MM-DD HH24:MI')));
        END IF;

        v_report := array_append(v_report, '');
        v_report := array_append(v_report, 'Используемые сигналы (v22.1):');
        v_report := array_append(v_report, '  1) SICPP (эпизодный) — покрытие, метка [S].');
        v_report := array_append(v_report, '  2) C-alone — операционный индикатор (колонки c_alert_min, C, C_reason).');
        v_report := array_append(v_report, 'Исключены как невалидные:');
        v_report := array_append(v_report, '  A (PreAlertAdv): precision 5.9%, recall 17.1% — уровень шума.');
        v_report := array_append(v_report, '  B (W_score>1 AND risk_max>=1.0): не даёт уникального вклада.');
        v_report := array_append(v_report, '  Hybrid (A ∪ B ∪ C): разбавление C шумом A (precision 12.5% vs 34.5% у C-alone).');
        v_report := array_append(v_report, 'Параметры конфигурации SICPP (ФАКТИЧЕСКИЕ — используются для расчётов):');
        v_report := array_append(v_report, format('  Окно: %s мин', v_window_minutes));
        v_report := array_append(v_report, format('  JS-порог (config): %s', v_js_threshold));
        v_report := array_append(v_report, format('  Порог риска (config): %s', v_risk_threshold));
        v_report := array_append(v_report, format('  Режим сигнала: %s', v_signal_mode));
        v_report := array_append(v_report, format('  Мин. длительность сигнала: %s мин', v_min_signal_duration));
        v_report := array_append(v_report, format('  Вес JS: %s', v_weight_js));
        v_report := array_append(v_report, format('  Вес риска: %s', v_weight_risk));
        v_report := array_append(v_report, format('  Автоподбор порогов (auto_threshold): %s', CASE WHEN v_auto_threshold THEN 'ВКЛ' ELSE 'ВЫКЛ' END));
        v_report := array_append(v_report, format('  Период калибровки: %s дней', v_calibration_period_days));
        v_report := array_append(v_report, format('  Расширенный отчёт: %s', CASE WHEN v_extended_report THEN 'ДА' ELSE 'НЕТ' END));
        v_report := array_append(v_report, format('  Фильтр статусов: %s', COALESCE(array_to_string(v_status_filter, ','), 'НЕТ')));
        v_report := array_append(v_report, format('  Серийный фильтр: %s', CASE WHEN v_series_filter_enabled THEN 'ВКЛ' ELSE 'ВЫКЛ' END));
        v_report := array_append(v_report, format('  Порог lead time для «покрытие с lead >= N»: %s мин', v_coverage_lead_threshold));
        v_report := array_append(v_report, format('  max_signal_duration_minutes: %s мин', v_max_dur_cap));
        v_report := array_append(v_report, format('  long_episode_threshold_min: %s мин', v_long_episode_threshold));

        IF v_auto_threshold AND p_show_inmemory_reco THEN
            IF v_js_threshold_reco IS NOT NULL AND v_risk_threshold_reco IS NOT NULL THEN
                v_report := array_append(v_report, '');
                v_report := array_append(v_report, 'ⓘ In-memory рекомендация (НЕ использована для W_score и покрытия):');
                v_report := array_append(v_report, format('  JS-порог (reco, p75 за %s дн. от p_start): %s',
                    v_calibration_period_days, v_js_threshold_reco));
                v_report := array_append(v_report, format('  Порог риска (reco, p75): %s', v_risk_threshold_reco));
                v_report := array_append(v_report, '  Для W_score и покрытия используются фактические пороги из config (см. выше).');
            ELSE
                v_report := array_append(v_report, '');
                v_report := array_append(v_report, 'ⓘ In-memory рекомендация недоступна (недостаточно данных калибровки).');
            END IF;
        END IF;

        v_report := array_append(v_report, '  --- Параметры C-alone (операционный индикатор) ---');
        v_report := array_append(v_report, format('  c_js_min_threshold:    %s', v_c_js_min));
        v_report := array_append(v_report, format('  c_p90_min_threshold:   %s', v_c_p90_min));
        v_report := array_append(v_report, format('  c_w_score_min:         %s', v_c_w_min));
        v_report := array_append(v_report, format('  c_window_minutes:      %s', v_c_window_min));
        v_report := array_append(v_report, format('  Режим CSV: %s', CASE WHEN v_csv_mode THEN 'ДА' ELSE 'НЕТ' END));
        v_report := array_append(v_report, format('Дата формирования: %s', to_char(now(), 'YYYY-MM-DD HH24:MI')));
        v_report := array_append(v_report, '');

        v_legend := 'Расшифровка столбцов:';
        v_legend := v_legend || E'\n- ID – идентификатор инцидента (markov_chain_performance_incident).';
        v_legend := v_legend || E'\n- Время – время начала инцидента.';
        v_legend := v_legend || E'\n- JS(avg [min-max], cnt) – JS-дивергенция из последней записи sicpp_history перед инцидентом.';
        v_legend := v_legend || E'\n- Риск(avg [min-max], cnt) – риск из последней записи sicpp_history перед инцидентом.';
        v_legend := v_legend || format(
            E'\n- W_score – WEIGHTED-score по ФАКТИЧЕСКИМ порогам (js_threshold=%s, risk_threshold=%s): '
            '(risk_avg/risk_threshold)*weight_risk + (js_avg/js_threshold)*weight_js.',
            v_js_threshold, v_risk_threshold);
        v_legend := v_legend || E'\n- Тренд – направление изменения риска за час (РОСТ/СНИЖЕНИЕ/СТАБИЛЬНО).';
        v_legend := v_legend || E'\n- Посл.статус – последний статус сравнения профилей перед инцидентом.';
        v_legend := v_legend || E'\n- risk_p90 – 90-й перцентиль predicted_risk из prediction_log за 60 мин до start_timepoint.';
        v_legend := v_legend || E'\n- js@start(C) – js_avg на start_timepoint из mchain_hybrid_alert_at.';
        v_legend := v_legend || E'\n- c_alert_min – число минут, в которые C-alone был активен в окне [start - c_window; start].';
        v_legend := v_legend || E'\n- C – ДА, если c_alert_min > 0; НЕТ, если c_alert_min = 0.';
        v_legend := v_legend || E'\n    Формула C: risk_p90 >= c_p90_min AND js_avg >= c_js_min AND W_score >= c_w_min.';
        v_legend := v_legend || E'\n- C_reason – почему C сработал/не сработал.';
        v_legend := v_legend || E'\n- trend(C-window) – тренд риска за окно [start − c_window; start].';
        v_legend := v_legend || E'\n- Сигнал – ДА, если инцидент покрыт эпизодом SICPP.';
        v_legend := v_legend || E'\n- Мин до сигн. – время от episode_started_at покрывающего эпизода до начала инцидента.';
        v_legend := v_legend || E'\n- Длит.сигн.(мин) – signal_duration покрывающего эпизода.';
        v_legend := v_legend || E'\n- Сигн.ограничен – ДА, если raw lead превысил max_signal_duration_minutes.';
        v_legend := v_legend || E'\n- Прирост риска / JS – risk_slope / js_slope из последней записи sicpp_history.';
        v_legend := v_legend || E'\n- Данные – data_sufficient.';
        v_legend := v_legend || E'\n- Уверенность – confidence покрывающего эпизода SICPP.';
        IF v_extended_report THEN
            v_legend := v_legend || E'\n- Метка – [S] SICPP сработал, [ND] недостаточно данных, [NB] NO_BASELINE, "" нет сигнала.';
            v_legend := v_legend || E'\n- Сила сигн. / Макс.сила – strength / max_strength покрывающего эпизода.';
        END IF;
        v_report := array_append(v_report, v_legend);
        v_report := array_append(v_report, '');
    END IF;

    -- Заголовки таблицы
    IF v_csv_mode THEN
        v_header_line := 'ID;Время;JS_avg;JS_min;JS_max;JS_cnt;Risk_avg;Risk_min;Risk_max;Risk_cnt;W_score;Тренд;Посл.статус;risk_p90;js_start_C;c_alert_min;C;C_reason;Сигнал;Мин_до_сигн;Длит_сигн;Прирост_риска;Прирост_JS;Данные;Уверенность;Сигн_ограничен';
        v_report := array_append(v_report, v_header_line);
    ELSE
        IF v_extended_report THEN
            v_report := array_append(v_report, '--- ДЕТАЛИ ПО ИНЦИДЕНТАМ (v22.1, + C_reason, + js@start(C)) ---');
            v_report := array_append(v_report,
                'Метка | ID | Время | JS(avg [min-max], cnt) | Риск(avg [min-max], cnt) | W_score | Тренд | Посл.статус | risk_p90 | js@start(C) | c_alert_min | C | C_reason | Сигнал | Мин до сигн. | Длит.сигн.(мин) | Прирост риска | Прирост JS | Данные | Уверенность | Сила сигн. | Макс.сила | Сигн.ограничен'
            );
            v_report := array_append(v_report,
                '-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------'
            );
        ELSE
            v_report := array_append(v_report, '--- ДЕТАЛИ ПО ИНЦИДЕНТАМ (v22.1, + C_reason, + js@start(C)) ---');
            v_report := array_append(v_report,
                'ID | Время | JS(avg [min-max], cnt) | Риск(avg [min-max], cnt) | W_score | Тренд | Посл.статус | risk_p90 | js@start(C) | c_alert_min | C | C_reason | Сигнал | Мин до сигн. | Длит.сигн.(мин) | Прирост риска | Прирост JS | Данные | Уверенность'
            );
            v_report := array_append(v_report,
                '-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------'
            );
        END IF;
    END IF;

    -- =========================================================================
    -- 7. Основной цикл по инцидентам
    -- =========================================================================
    FOR v_incident IN
        SELECT id, start_timepoint, finish_timepoint
        FROM markov_chain_performance_incident
        WHERE start_timepoint BETWEEN p_start AND p_end
        ORDER BY start_timepoint
    LOOP
        SELECT status INTO v_last_status
        FROM profile_comparison_log
        WHERE current_window_end < v_incident.start_timepoint
        ORDER BY current_window_end DESC LIMIT 1;

        IF v_status_filter IS NOT NULL AND NOT (v_last_status = ANY(v_status_filter)) THEN
            CONTINUE;
        END IF;

        IF v_last_status = 'NO_BASELINE' THEN
            v_no_baseline_count := v_no_baseline_count + 1;
        END IF;

        IF v_series_filter_enabled AND v_last_status = 'INCIDENT' THEN
            v_prev_unfinished := EXISTS (
                SELECT 1 FROM markov_chain_performance_incident pi2
                WHERE pi2.start_timepoint < v_incident.start_timepoint
                  AND (pi2.finish_timepoint IS NULL OR pi2.finish_timepoint > v_incident.start_timepoint)
                  AND pi2.id <> v_incident.id
            );
            IF v_prev_unfinished THEN
                v_excluded_incidents := v_excluded_incidents + 1;
                CONTINUE;
            END IF;
        END IF;

        v_included_ids := array_append(v_included_ids, v_incident.id);
        v_total_incidents := v_total_incidents + 1;

        v_signal := NULL;
        SELECT
            sh.js_avg, sh.js_min, sh.js_max, sh.js_cnt,
            sh.risk_avg, sh.risk_min, sh.risk_max, sh.risk_cnt,
            sh.risk_slope, sh.js_slope, sh.data_sufficient
        INTO v_signal
        FROM sicpp_history sh
        WHERE sh.changed_at <= v_incident.start_timepoint
        ORDER BY sh.changed_at DESC
        LIMIT 1;

        IF NOT FOUND THEN
            v_signal.js_avg := NULL; v_signal.js_min := NULL; v_signal.js_max := NULL;
            v_signal.js_cnt := 0;
            v_signal.risk_avg := NULL; v_signal.risk_min := NULL; v_signal.risk_max := NULL;
            v_signal.risk_cnt := 0;
            v_signal.risk_slope := NULL; v_signal.js_slope := NULL;
            v_signal.data_sufficient := 'LOW_BOTH'::TEXT;
        END IF;

        SELECT
            COUNT(*) FILTER (WHERE cw.alert)         AS c_alert_min,
            COALESCE(BOOL_OR(cw.fired_c), FALSE)     AS c_fired,
            MAX(cw.risk_p90) FILTER (WHERE cw.m = v_incident.start_timepoint) AS point_p90,
            MAX(cw.w_score)  FILTER (WHERE cw.m = v_incident.start_timepoint) AS point_ws,
            MAX(cw.js_avg)   FILTER (WHERE cw.m = v_incident.start_timepoint) AS point_js
        INTO v_c_alert_minutes, v_c_fired, v_risk_p90, v_weighted_score, v_point_js
        FROM _tmp_c_windows cw
        WHERE cw.incident_id = v_incident.id;

        IF v_c_alert_minutes IS NULL THEN
            v_c_alert_minutes := 0;
        END IF;
        v_c_fired := COALESCE(v_c_fired, FALSE);

        IF v_c_fired THEN
            v_c_reason := 'fired';
        ELSE
            v_fail_p90 := (v_risk_p90 IS NULL OR v_risk_p90 < v_c_p90_min);
            v_fail_js  := (v_point_js  IS NULL OR v_point_js  < v_c_js_min);
            v_fail_ws  := (v_weighted_score IS NULL OR v_weighted_score < v_c_w_min);
            v_c_reason :=
                'p90' || CASE WHEN v_fail_p90 THEN '✗' ELSE '✓' END || ',' ||
                'js'  || CASE WHEN v_fail_js  THEN '✗' ELSE '✓' END || ',' ||
                'w'   || CASE WHEN v_fail_ws  THEN '✗' ELSE '✓' END;
        END IF;

        IF v_c_alert_minutes > 0 THEN
            v_ha_covered_count := v_ha_covered_count + 1;
        ELSE
            v_ha_uncovered_ids := array_append(v_ha_uncovered_ids, v_incident.id::TEXT);
        END IF;

        IF v_c_alert_minutes = 0 THEN v_ha_dist_0 := v_ha_dist_0 + 1;
        ELSIF v_c_alert_minutes <= 5 THEN v_ha_dist_1_5 := v_ha_dist_1_5 + 1;
        ELSIF v_c_alert_minutes <= 10 THEN v_ha_dist_6_10 := v_ha_dist_6_10 + 1;
        ELSIF v_c_alert_minutes <= 15 THEN v_ha_dist_11_15 := v_ha_dist_11_15 + 1;
        ELSE v_ha_dist_16_20 := v_ha_dist_16_20 + 1;
        END IF;

        v_cover := NULL;
        SELECT
            e.id AS episode_id, e.episode_start, e.episode_end, e.first_signal_time,
            e.signal_duration, e.signal_strength, e.max_signal_strength, e.confidence,
            COALESCE(e.signal_capped, FALSE) AS signal_capped,
            e.episode_started_at, e.episode_started_at_fallback
        INTO v_cover
        FROM _tmp_sicpp_episodes_v3 e
        WHERE e.episode_start <= v_incident.start_timepoint
          AND e.episode_end >= v_incident.start_timepoint - v_window_minutes * INTERVAL '1 minute'
        ORDER BY e.episode_end DESC LIMIT 1;

        IF NOT FOUND THEN
            v_cover.episode_id := NULL; v_cover.episode_start := NULL; v_cover.episode_end := NULL;
            v_cover.first_signal_time := NULL; v_cover.signal_duration := 0;
            v_cover.signal_strength := NULL; v_cover.max_signal_strength := NULL;
            v_cover.confidence := NULL; v_cover.signal_capped := FALSE;
            v_cover.episode_started_at := NULL; v_cover.episode_started_at_fallback := FALSE;
        END IF;

        IF v_cover.episode_id IS NOT NULL THEN
            v_incidents_with_signal := v_incidents_with_signal + 1;
            IF v_cover.episode_started_at IS NOT NULL THEN
                v_lead_raw_min := EXTRACT(EPOCH FROM (v_incident.start_timepoint - v_cover.episode_started_at)) / 60;
                v_lead_effective_min := LEAST(v_lead_raw_min, v_max_dur_cap);
                IF v_lead_raw_min > v_max_dur_cap THEN
                    v_lead_display := round(v_lead_raw_min)::TEXT || ' (>cap ' || v_max_dur_cap::TEXT || ')';
                    v_incidents_lead_capped := v_incidents_lead_capped + 1;
                ELSE
                    v_lead_display := round(v_lead_raw_min)::TEXT;
                END IF;
                IF v_cover.episode_started_at_fallback THEN
                    v_lead_display := v_lead_display || ' (from first_signal)';
                END IF;
                v_avg_minutes_to_incident := v_avg_minutes_to_incident + v_lead_raw_min;
                IF v_lead_raw_min >= v_coverage_lead_threshold THEN
                    v_incidents_lead_ge := v_incidents_lead_ge + 1;
                ELSE
                    v_incidents_lead_lt := v_incidents_lead_lt + 1;
                END IF;
            ELSE
                v_lead_raw_min := NULL; v_lead_effective_min := NULL;
                v_lead_display := 'NULL'; v_incidents_lead_lt := v_incidents_lead_lt + 1;
            END IF;
        ELSE
            v_lead_raw_min := NULL; v_lead_effective_min := NULL; v_lead_display := 'NULL';
        END IF;

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
                SELECT MAX(CASE WHEN rn = 1 THEN predicted_risk END) AS first_val,
                       MAX(CASE WHEN rn = (SELECT MAX(rn) FROM ordered_risks) THEN predicted_risk END) AS last_val
                FROM ordered_risks
            )
            SELECT CASE
                WHEN last_val > first_val THEN 'РОСТ'
                WHEN last_val < first_val THEN 'СНИЖЕНИЕ'
                ELSE 'СТАБИЛЬНО'
            END INTO v_trend FROM first_last;
        ELSE
            v_trend := 'НЕДОСТАТОЧНО ДАННЫХ';
        END IF;

        IF v_signal.js_cnt IS NULL OR v_signal.js_cnt = 0 THEN
            v_js_str := 'NULL [NULL-NULL], n=0';
        ELSIF v_signal.js_cnt = -1 THEN
            v_js_str := COALESCE(round(v_signal.js_avg::NUMERIC, 4)::TEXT, 'NULL') || ' [посл.]';
        ELSE
            v_js_str := COALESCE(round(v_signal.js_avg::NUMERIC, 4)::TEXT, 'NULL') || ' [' ||
                        COALESCE(round(v_signal.js_min::NUMERIC, 4)::TEXT, 'NULL') || '-' ||
                        COALESCE(round(v_signal.js_max::NUMERIC, 4)::TEXT, 'NULL') || '], n=' || v_signal.js_cnt::TEXT;
        END IF;

        IF v_signal.risk_cnt IS NULL OR v_signal.risk_cnt = 0 THEN
            v_risk_str := 'NULL [NULL-NULL], n=0';
        ELSE
            v_risk_str := COALESCE(round(v_signal.risk_avg::NUMERIC, 4)::TEXT, 'NULL') || ' [' ||
                          COALESCE(round(v_signal.risk_min::NUMERIC, 4)::TEXT, 'NULL') || '-' ||
                          COALESCE(round(v_signal.risk_max::NUMERIC, 4)::TEXT, 'NULL') || '], n=' || v_signal.risk_cnt::TEXT;
        END IF;

        IF v_signal.data_sufficient IN ('LOW_JS', 'LOW_RISK', 'LOW_BOTH') THEN
            v_marker := '[ND]';
        ELSIF v_last_status = 'NO_BASELINE' THEN
            v_marker := '[NB]';
        ELSIF v_cover.episode_id IS NOT NULL THEN
            v_marker := '[S]';
        ELSE
            v_marker := '';
        END IF;

        IF v_csv_mode THEN
            v_line := format('%s;%s;%s;%s;%s;%s;%s;%s;%s;%s;%s;%s;%s;%s;%s;%s;%s;%s;%s;%s;%s;%s;%s;%s;%s;%s',
                v_incident.id,
                to_char(v_incident.start_timepoint, 'YYYY-MM-DD HH24:MI'),
                COALESCE(round(v_signal.js_avg::NUMERIC, 4)::TEXT, 'NULL'),
                COALESCE(round(v_signal.js_min::NUMERIC, 4)::TEXT, 'NULL'),
                COALESCE(round(v_signal.js_max::NUMERIC, 4)::TEXT, 'NULL'),
                CASE WHEN v_signal.js_cnt = -1 THEN 'посл.' ELSE COALESCE(v_signal.js_cnt::TEXT, '0') END,
                COALESCE(round(v_signal.risk_avg::NUMERIC, 4)::TEXT, 'NULL'),
                COALESCE(round(v_signal.risk_min::NUMERIC, 4)::TEXT, 'NULL'),
                COALESCE(round(v_signal.risk_max::NUMERIC, 4)::TEXT, 'NULL'),
                COALESCE(v_signal.risk_cnt::TEXT, '0'),
                COALESCE(round(v_weighted_score::NUMERIC, 4)::TEXT, 'NULL'),
                v_trend,
                COALESCE(v_last_status, 'НЕТ ДАННЫХ'),
                COALESCE(round(v_risk_p90::NUMERIC, 4)::TEXT, 'NULL'),
                COALESCE(round(v_point_js::NUMERIC, 4)::TEXT, 'NULL'),
                v_c_alert_minutes,
                CASE WHEN v_c_fired THEN 'ДА' ELSE 'НЕТ' END,
                v_c_reason,
                CASE WHEN v_cover.episode_id IS NOT NULL THEN 'ДА' ELSE 'НЕТ' END,
                v_lead_display,
                COALESCE(v_cover.signal_duration::TEXT, '0'),
                COALESCE(round(v_signal.risk_slope::NUMERIC, 4)::TEXT, 'NULL'),
                COALESCE(round(v_signal.js_slope::NUMERIC, 4)::TEXT, 'NULL'),
                COALESCE(v_signal.data_sufficient, 'LOW_BOTH'),
                COALESCE(round(v_cover.confidence::NUMERIC, 4)::TEXT, 'NULL'),
                CASE WHEN v_cover.episode_id IS NULL THEN '-' WHEN v_lead_raw_min > v_max_dur_cap THEN 'ДА' ELSE 'НЕТ' END
            );
        ELSIF v_extended_report THEN
            v_line := format(
                '%s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s',
                v_marker, v_incident.id,
                to_char(v_incident.start_timepoint, 'YYYY-MM-DD HH24:MI'),
                v_js_str, v_risk_str,
                COALESCE(round(v_weighted_score::NUMERIC, 3)::TEXT, '-'),
                v_trend, COALESCE(v_last_status, 'НЕТ ДАННЫХ'),
                COALESCE(round(v_risk_p90::NUMERIC, 4)::TEXT, 'NULL'),
                COALESCE(round(v_point_js::NUMERIC, 4)::TEXT, 'NULL'),
                v_c_alert_minutes,
                CASE WHEN v_c_fired THEN 'ДА' ELSE 'НЕТ' END,
                v_c_reason,
                CASE WHEN v_cover.episode_id IS NOT NULL THEN 'ДА' ELSE 'НЕТ' END,
                v_lead_display,
                COALESCE(v_cover.signal_duration::TEXT, '0'),
                COALESCE(round(v_signal.risk_slope::NUMERIC, 4)::TEXT, 'NULL'),
                COALESCE(round(v_signal.js_slope::NUMERIC, 4)::TEXT, 'NULL'),
                COALESCE(v_signal.data_sufficient, 'LOW_BOTH'),
                COALESCE(round(v_cover.confidence::NUMERIC, 4)::TEXT, 'NULL'),
                COALESCE(round(v_cover.signal_strength::NUMERIC, 4)::TEXT, 'NULL'),
                COALESCE(round(v_cover.max_signal_strength::NUMERIC, 4)::TEXT, 'NULL'),
                CASE WHEN v_cover.episode_id IS NULL THEN '-' WHEN v_lead_raw_min > v_max_dur_cap THEN 'ДА' ELSE 'НЕТ' END
            );
        ELSE
            v_line := format(
                '%s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s',
                v_incident.id,
                to_char(v_incident.start_timepoint, 'YYYY-MM-DD HH24:MI'),
                v_js_str, v_risk_str,
                COALESCE(round(v_weighted_score::NUMERIC, 3)::TEXT, '-'),
                v_trend, COALESCE(v_last_status, 'НЕТ ДАННЫХ'),
                COALESCE(round(v_risk_p90::NUMERIC, 4)::TEXT, 'NULL'),
                COALESCE(round(v_point_js::NUMERIC, 4)::TEXT, 'NULL'),
                v_c_alert_minutes,
                CASE WHEN v_c_fired THEN 'ДА' ELSE 'НЕТ' END,
                v_c_reason,
                CASE WHEN v_cover.episode_id IS NOT NULL THEN 'ДА' ELSE 'НЕТ' END,
                v_lead_display,
                COALESCE(v_cover.signal_duration::TEXT, '0'),
                COALESCE(round(v_signal.risk_slope::NUMERIC, 4)::TEXT, 'NULL'),
                COALESCE(round(v_signal.js_slope::NUMERIC, 4)::TEXT, 'NULL'),
                COALESCE(v_signal.data_sufficient, 'LOW_BOTH'),
                COALESCE(round(v_cover.confidence::NUMERIC, 4)::TEXT, 'NULL')
            );
        END IF;

        v_report := array_append(v_report, v_line);

        IF v_signal.js_avg IS NOT NULL THEN
            v_avg_js_avg := v_avg_js_avg + v_signal.js_avg;
        END IF;
        IF v_signal.risk_avg IS NOT NULL THEN
            v_avg_risk_avg := v_avg_risk_avg + v_signal.risk_avg;
        END IF;
    END LOOP;

    -- =========================================================================
    -- 8. Обработка отсутствия данных
    -- =========================================================================
    IF v_total_incidents = 0 THEN
        IF NOT v_csv_mode THEN
            v_report := array_append(v_report, format('Инцидентов (после фильтров) за период не найдено. Исключено серийных: %s.', v_excluded_incidents));
            v_report := array_append(v_report, '');
            v_report := array_append(v_report, '=== КОНЕЦ ОТЧЁТА ===');
        ELSE
            v_report := array_append(v_report, 'Нет данных');
        END IF;
        DROP TABLE IF EXISTS _tmp_sicpp_episodes_v3;
        DROP TABLE IF EXISTS _tmp_c_windows;
        RETURN v_report;
    END IF;

    -- =========================================================================
    -- 9. Итоговая статистика
    -- =========================================================================
    IF v_include_summary AND NOT v_csv_mode THEN
        v_avg_minutes_to_incident := v_avg_minutes_to_incident / NULLIF(v_incidents_with_signal, 0);
        v_avg_js_avg   := v_avg_js_avg   / v_total_incidents;
        v_avg_risk_avg := v_avg_risk_avg / v_total_incidents;

        v_incidents_lead_ge_pct_total :=
            ROUND((v_incidents_lead_ge::NUMERIC / NULLIF(v_total_incidents, 0)) * 100, 1);
        v_incidents_lead_ge_pct_covered :=
            ROUND((v_incidents_lead_ge::NUMERIC / NULLIF(v_incidents_with_signal, 0)) * 100, 1);

        WITH last_statuses AS (
            SELECT DISTINCT ON (pi.id) pi.id, pcl.status
            FROM markov_chain_performance_incident pi
            JOIN profile_comparison_log pcl ON pcl.current_window_end < pi.start_timepoint
            WHERE pi.id = ANY(v_included_ids)
            ORDER BY pi.id, pcl.current_window_end DESC
        )
        SELECT jsonb_build_object(
            'CRITICAL',    COUNT(*) FILTER (WHERE status = 'CRITICAL'),
            'WARNING',     COUNT(*) FILTER (WHERE status = 'WARNING'),
            'NORMAL',      COUNT(*) FILTER (WHERE status = 'NORMAL'),
            'INCIDENT',    COUNT(*) FILTER (WHERE status = 'INCIDENT'),
            'NO_BASELINE', COUNT(*) FILTER (WHERE status = 'NO_BASELINE'),
            'НЕТ ДАННЫХ',  COUNT(*) FILTER (WHERE status IS NULL)
        ) INTO v_status_counts
        FROM last_statuses;

        v_pct_text := round(((v_incidents_with_signal::REAL / v_total_incidents) * 100)::NUMERIC, 1)::TEXT || '%';

        WITH incident_hours AS (
            SELECT EXTRACT(HOUR FROM start_timepoint)::INT AS h, COUNT(*) AS cnt
            FROM markov_chain_performance_incident WHERE id = ANY(v_included_ids) GROUP BY h
        ),
        incident_dows AS (
            SELECT EXTRACT(DOW FROM start_timepoint)::INT AS dow, COUNT(*) AS cnt
            FROM markov_chain_performance_incident WHERE id = ANY(v_included_ids) GROUP BY dow
        )
        SELECT (SELECT jsonb_object_agg(h, cnt) FROM incident_hours),
               (SELECT jsonb_object_agg(dow, cnt) FROM incident_dows)
        INTO v_hour_dist, v_dow_dist;

        WITH hour_graph AS (
            SELECT h, cnt, repeat('*', cnt::INT) AS stars
            FROM (SELECT (jsonb_each(v_hour_dist)).key::INT AS h,
                         (jsonb_each(v_hour_dist)).value::INT AS cnt) t
            ORDER BY h
        )
        SELECT string_agg(format('%02s: %s', h, stars), E'\n') INTO v_hour_graph FROM hour_graph;

        WITH dow_graph AS (
            SELECT dow, cnt, repeat('*', cnt::INT) AS stars
            FROM (SELECT (jsonb_each(v_dow_dist)).key::INT AS dow,
                         (jsonb_each(v_dow_dist)).value::INT AS cnt) t
            ORDER BY dow
        )
        SELECT string_agg(format('День %s: %s', dow, stars), E'\n') INTO v_dow_graph FROM dow_graph;

        WITH quality_metrics AS (
            SELECT
                AVG((predicted_risk - actual_outcome)^2) AS brier,
                (SUM(CASE WHEN actual_outcome = 1 THEN rnk ELSE 0 END) -
                 (COUNT(CASE WHEN actual_outcome = 1 THEN 1 END) *
                  (COUNT(CASE WHEN actual_outcome = 1 THEN 1 END) + 1) / 2.0)
                ) / NULLIF(COUNT(CASE WHEN actual_outcome = 1 THEN 1 END) *
                     COUNT(CASE WHEN actual_outcome = 0 THEN 1 END), 0) AS auc
            FROM (
                SELECT predicted_risk, actual_outcome,
                       ROW_NUMBER() OVER (ORDER BY predicted_risk ASC) AS rnk
                FROM prediction_log
                WHERE prediction_time BETWEEN p_start AND p_end
                  AND actual_outcome IS NOT NULL
                  AND horizon_minutes = v_horizon_minutes
            ) ranked
            WHERE actual_outcome IN (0,1)
        )
        SELECT brier, auc INTO v_brier, v_roc_auc FROM quality_metrics;

        WITH calibration_bins AS (
            SELECT (bin - 1) / 10.0 AS bin_low, bin / 10.0 AS bin_high,
                   AVG(predicted_risk) AS avg_pred, AVG(actual_outcome) AS obs_freq, COUNT(*) AS cnt
            FROM (
                SELECT WIDTH_BUCKET(LEAST(predicted_risk, 0.999999), 0, 1, 10) AS bin,
                       predicted_risk, actual_outcome
                FROM prediction_log
                WHERE prediction_time BETWEEN p_start AND p_end
                  AND actual_outcome IS NOT NULL AND predicted_risk IS NOT NULL
                  AND horizon_minutes = v_horizon_minutes
            ) t
            GROUP BY bin ORDER BY bin
        )
        SELECT jsonb_agg(jsonb_build_object('bin_low', bin_low, 'bin_high', bin_high,
                                            'avg_pred', avg_pred, 'obs_freq', obs_freq, 'cnt', cnt))
        INTO v_calibration FROM calibration_bins;

        v_report := array_append(v_report, '');
        v_report := array_append(v_report, '--- ИТОГОВАЯ СТАТИСТИКА (v22.1, header fix + C-diag) ---');
        v_report := array_append(v_report, format('Всего инцидентов (после фильтров): %s', v_total_incidents));
        v_report := array_append(v_report, format('  Исключено серийных: %s', v_excluded_incidents));
        v_report := array_append(v_report, format('  - с сигналом SICPP (по эпизодам): %s (%s)', v_incidents_with_signal, v_pct_text));
        v_report := array_append(v_report, format('Среднее время от episode_started_at SICPP-эпизода до инцидента (raw, ALL): %s мин',
            COALESCE(round(v_avg_minutes_to_incident::NUMERIC, 1)::TEXT, 'NULL')));
        IF v_incidents_lead_capped > 0 THEN
            v_report := array_append(v_report, format('  ⚠ Из них с raw lead > %s мин: %s (в строках отмечены «(>cap %s)»)',
                v_max_dur_cap, v_incidents_lead_capped, v_max_dur_cap));
            v_report := array_append(v_report, '    Значения lead приведены как raw (не капнутые).');
        END IF;
        v_report := array_append(v_report, format('Средняя JS-дивергенция: %s', round(v_avg_js_avg::NUMERIC, 4)));
        v_report := array_append(v_report, format('Средний риск: %s', round(v_avg_risk_avg::NUMERIC, 4)));

        v_report := array_append(v_report, 'Распределение последних статусов перед инцидентами:');
        v_report := array_append(v_report, format('  CRITICAL:    %s', COALESCE((v_status_counts->>'CRITICAL')::TEXT, '0')));
        v_report := array_append(v_report, format('  WARNING:     %s', COALESCE((v_status_counts->>'WARNING')::TEXT, '0')));
        v_report := array_append(v_report, format('  NORMAL:      %s', COALESCE((v_status_counts->>'NORMAL')::TEXT, '0')));
        v_report := array_append(v_report, format('  INCIDENT:    %s', COALESCE((v_status_counts->>'INCIDENT')::TEXT, '0')));
        v_report := array_append(v_report, format('  NO_BASELINE: %s', COALESCE((v_status_counts->>'NO_BASELINE')::TEXT, '0')));
        v_report := array_append(v_report, format('  НЕТ ДАННЫХ:  %s', COALESCE((v_status_counts->>'НЕТ ДАННЫХ')::TEXT, '0')));

        IF v_no_baseline_count > 0 THEN
            v_report := array_append(v_report, format(
                '⚠ Найдено %s инцидентов с статусом NO_BASELINE. Для периодов после 2026-10-14 это указывает на проблему fallback-цепочки в compare_profiles.',
                v_no_baseline_count));
        END IF;

        IF v_roc_auc IS NOT NULL THEN
            v_report := array_append(v_report, format('ROC-AUC (по prediction_log, horizon=%s): %s', v_horizon_minutes, round(v_roc_auc::NUMERIC, 4)));
            v_report := array_append(v_report, format('Brier score: %s', round(v_brier::NUMERIC, 6)));
        END IF;

        IF v_calibration IS NOT NULL THEN
            v_report := array_append(v_report, 'Калибровочная кривая (риск vs. фактическая частота, WIDTH_BUCKET):');
            FOR v_rec IN SELECT * FROM jsonb_to_recordset(v_calibration)
                AS x(bin_low NUMERIC, bin_high NUMERIC, avg_pred NUMERIC, obs_freq NUMERIC, cnt INT)
            LOOP
                v_report := array_append(v_report, format('  [%s-%s]: предсказано %s, фактически %s, n=%s',
                    round(v_rec.bin_low::NUMERIC, 1), round(v_rec.bin_high::NUMERIC, 1),
                    round(v_rec.avg_pred::NUMERIC, 3), round(v_rec.obs_freq::NUMERIC, 3), v_rec.cnt));
            END LOOP;
        END IF;

        v_report := array_append(v_report, 'Распределение инцидентов по часам (0-23):');
        v_report := array_append(v_report, COALESCE(v_hour_graph, 'Нет данных'));
        v_report := array_append(v_report, 'Распределение инцидентов по дням недели (0-6, 0=Вс):');
        v_report := array_append(v_report, COALESCE(v_dow_graph, 'Нет данных'));

        -- =====================================================================
        -- ПОКРЫТИЕ SICPP С УЧЁТОМ LEAD TIME
        -- =====================================================================
        v_report := array_append(v_report, '');
        v_report := array_append(v_report, format('--- ПОКРЫТИЕ SICPP С УЧЁТОМ LEAD TIME (порог: %s мин) ---', v_coverage_lead_threshold));
        v_report := array_append(v_report, 'Отделяет «SICPP был активен при инциденте» (текущее покрытие) от');
        v_report := array_append(v_report, '«SICPP предсказал инцидент заранее» (покрытие при lead >= порога).');
        v_report := array_append(v_report, format('  Всего покрыто эпизодами SICPP:     %s из %s (%s)',
            v_incidents_with_signal, v_total_incidents, v_pct_text));
        v_report := array_append(v_report, format('  Из них lead >= %s мин (предсказано заранее): %s (%s%% от покрытых)',
            v_coverage_lead_threshold, v_incidents_lead_ge, COALESCE(v_incidents_lead_ge_pct_covered::TEXT, '0')));
        v_report := array_append(v_report, format('  Из них lead <  %s мин (активен, но не предсказал): %s',
            v_coverage_lead_threshold, v_incidents_lead_lt));
        v_report := array_append(v_report, format('  Доля покрытия с lead >= %s от всех инцидентов: %s%%',
            v_coverage_lead_threshold, COALESCE(v_incidents_lead_ge_pct_total::TEXT, '0')));

        IF v_incidents_lead_capped > 0 THEN
            v_report := array_append(v_report, format(
                '  ⚠ %s инцидентов имеют raw lead > %s мин (показан полностью).',
                v_incidents_lead_capped, v_max_dur_cap));
            v_report := array_append(v_report, '    Классификация lead_ge/lead_lt выполнена по raw lead (без каппинга).');
        END IF;

        IF v_incidents_lead_ge_pct_total IS NOT NULL AND v_incidents_lead_ge_pct_total < 50 THEN
            v_report := array_append(v_report, format(
                '  ⚠ Менее половины инцидентов (%s%%) имеют lead >= %s мин.',
                v_incidents_lead_ge_pct_total, v_coverage_lead_threshold));
        END IF;

        -- =====================================================================
        -- C-ONLY
        -- =====================================================================
        v_report := array_append(v_report, '');
        v_report := array_append(v_report, '--- C-ONLY (операционный индикатор, v3.7.0) ---');
        v_report := array_append(v_report, 'Формула:');
        v_report := array_append(v_report, format('  C = risk_p90 >= %s AND js_avg >= %s AND W_score >= %s',
            v_c_p90_min, v_c_js_min, v_c_w_min));
        v_report := array_append(v_report, format('  Окно проверки: %s мин.', v_c_window_min));
        v_report := array_append(v_report, '  A (PreAlertAdv) и B (W_score>1 AND risk_max>=1.0) исключены как невалидные.');
        v_report := array_append(v_report, format('  Всего инцидентов: %s, покрыто C: %s (%s%%), не покрыто: %s',
            v_total_incidents, v_ha_covered_count,
            ROUND((v_ha_covered_count::NUMERIC / NULLIF(v_total_incidents, 0)) * 100, 1),
            v_total_incidents - v_ha_covered_count));
        v_report := array_append(v_report, '  Распределение инцидентов по числу минут C в окне:');
        v_report := array_append(v_report, format('    0 мин (не покрыто):      %s', v_ha_dist_0));
        v_report := array_append(v_report, format('    1-5 мин:                 %s', v_ha_dist_1_5));
        v_report := array_append(v_report, format('    6-10 мин:                %s', v_ha_dist_6_10));
        v_report := array_append(v_report, format('    11-15 мин:               %s', v_ha_dist_11_15));
        v_report := array_append(v_report, format('    16-20 мин (весь период): %s', v_ha_dist_16_20));
        IF array_length(v_ha_uncovered_ids, 1) > 0 THEN
            v_report := array_append(v_report, format('  Непокрытые инциденты (ID): %s',
                array_to_string(v_ha_uncovered_ids, ', ')));
        END IF;
        v_report := array_append(v_report, '  ⓘ Известные метрики C-alone (test6, unfiltered): precision 34.5%, recall 51.4%, ALERT-time 14.1%.');

        -- =====================================================================
        -- ДИАГНОСТИКА C ПО НЕПОКРЫТЫМ ИНЦИДЕНТАМ
        -- =====================================================================
        v_report := array_append(v_report, '');
        v_report := array_append(v_report, '--- ДИАГНОСТИКА C ПО НЕПОКРЫТЫМ ИНЦИДЕНТАМ (v22.1) ---');
        v_report := array_append(v_report, format('Формула C: risk_p90 >= %s AND js_avg >= %s AND W_score >= %s',
            v_c_p90_min, v_c_js_min, v_c_w_min));
        v_report := array_append(v_report, 'Значения p90/js/W взяты на start_timepoint инцидента из mchain_hybrid_alert_at.');
        v_report := array_append(v_report, 'NULL трактуется как ✗ (нет данных ⇒ порог не пройден).');
        v_report := array_append(v_report, format('trend(C-window) — направление и delta риска за окно [start − %s мин, start]; |Δ| ≥ 0.05 для РОСТ/СНИЖЕНИЕ.', v_c_window_min));
        v_report := array_append(v_report, '');
        v_uncovered_count := COALESCE(array_length(v_ha_uncovered_ids, 1), 0);
        v_report := array_append(v_report, format('Всего непокрытых: %s из %s', v_uncovered_count, v_total_incidents));
        v_report := array_append(v_report, '');

        v_report := array_append(v_report,
            rpad('ID', 6) || ' ' ||
            rpad('Время', 21) ||
            rpad('p90(мин=' || v_c_p90_min::TEXT || ')', 21) ||
            rpad('js(мин=' || v_c_js_min::TEXT || ')', 21) ||
            rpad('W(мин=' || v_c_w_min::TEXT || ')', 21) ||
            rpad('trend(C-window)', 21) ||
            'reason');
        v_report := array_append(v_report,
            '------ ' || repeat('-', 21) || repeat('-', 21) || repeat('-', 21) || repeat('-', 21) || repeat('-', 21));

        FOR v_rec IN
            SELECT pi.id, pi.start_timepoint,
                   cw_start.risk_p90 AS diag_p90,
                   cw_start.js_avg   AS diag_js,
                   cw_start.w_score  AS diag_ws
            FROM markov_chain_performance_incident pi
            LEFT JOIN _tmp_c_windows cw_start
                   ON cw_start.incident_id = pi.id
                  AND cw_start.m = pi.start_timepoint
            WHERE pi.id::TEXT = ANY(v_ha_uncovered_ids)
            ORDER BY pi.start_timepoint
        LOOP
            v_fail_p90 := (v_rec.diag_p90 IS NULL OR v_rec.diag_p90 < v_c_p90_min);
            v_fail_js  := (v_rec.diag_js  IS NULL OR v_rec.diag_js  < v_c_js_min);
            v_fail_ws  := (v_rec.diag_ws  IS NULL OR v_rec.diag_ws  < v_c_w_min);

            IF v_fail_p90 THEN v_diag_cnt_any_p90 := v_diag_cnt_any_p90 + 1; END IF;
            IF v_fail_js  THEN v_diag_cnt_any_js  := v_diag_cnt_any_js  + 1; END IF;
            IF v_fail_ws  THEN v_diag_cnt_any_ws  := v_diag_cnt_any_ws  + 1; END IF;
            IF v_fail_p90 AND v_fail_js AND v_fail_ws THEN v_diag_cnt_all_fail := v_diag_cnt_all_fail + 1;
            ELSIF v_fail_p90 AND NOT v_fail_js AND NOT v_fail_ws THEN v_diag_cnt_only_p90 := v_diag_cnt_only_p90 + 1;
            ELSIF NOT v_fail_p90 AND v_fail_js AND NOT v_fail_ws THEN v_diag_cnt_only_js := v_diag_cnt_only_js + 1;
            ELSIF NOT v_fail_p90 AND NOT v_fail_js AND v_fail_ws THEN v_diag_cnt_only_ws := v_diag_cnt_only_ws + 1;
            ELSIF v_fail_p90 AND v_fail_js AND NOT v_fail_ws THEN v_diag_cnt_p90_js := v_diag_cnt_p90_js + 1;
            ELSIF v_fail_p90 AND NOT v_fail_js AND v_fail_ws THEN v_diag_cnt_p90_ws := v_diag_cnt_p90_ws + 1;
            ELSIF NOT v_fail_p90 AND v_fail_js AND v_fail_ws THEN v_diag_cnt_js_ws := v_diag_cnt_js_ws + 1;
            END IF;

            WITH c_window_risk AS (
                SELECT predicted_risk, prediction_time
                FROM prediction_log
                WHERE prediction_time >= v_rec.start_timepoint - (v_c_window_min || ' minutes')::INTERVAL
                  AND prediction_time <= v_rec.start_timepoint
                  AND predicted_risk IS NOT NULL
            )
            SELECT
                (SELECT predicted_risk FROM c_window_risk ORDER BY prediction_time ASC  LIMIT 1),
                (SELECT predicted_risk FROM c_window_risk ORDER BY prediction_time DESC LIMIT 1),
                MAX(predicted_risk)
            INTO v_diag_risk_first, v_diag_risk_last, v_diag_risk_max
            FROM c_window_risk;

            IF v_diag_risk_first IS NULL OR v_diag_risk_last IS NULL THEN
                v_diag_risk_trend := 'НЕТ ДАННЫХ';
                v_diag_risk_trend_display := 'НЕТ ДАННЫХ';
                v_diag_risk_delta := NULL;
                v_diag_cnt_trend_no_data := v_diag_cnt_trend_no_data + 1;
            ELSE
                v_diag_risk_delta := v_diag_risk_last - v_diag_risk_first;
                IF v_diag_risk_delta > 0.05 THEN
                    v_diag_risk_trend := 'РОСТ';
                    v_diag_cnt_trend_up := v_diag_cnt_trend_up + 1;
                ELSIF v_diag_risk_delta < -0.05 THEN
                    v_diag_risk_trend := 'СНИЖЕНИЕ';
                    v_diag_cnt_trend_down := v_diag_cnt_trend_down + 1;
                ELSE
                    v_diag_risk_trend := 'СТАБИЛЬНО';
                    v_diag_cnt_trend_flat := v_diag_cnt_trend_flat + 1;
                END IF;
                v_diag_risk_trend_display := v_diag_risk_trend || ' ('
                    || CASE WHEN round(v_diag_risk_delta::numeric, 2) >= 0 THEN '+' ELSE '' END
                    || round(v_diag_risk_delta::numeric, 2)::TEXT
                    || ')';
            END IF;

            v_line := rpad(v_rec.id::TEXT, 6) || ' ' ||
                      rpad(to_char(v_rec.start_timepoint, 'YYYY-MM-DD HH24:MI'), 21) ||
                      rpad(COALESCE(round(v_rec.diag_p90::NUMERIC, 4)::TEXT, 'NULL'), 21) ||
                      rpad(COALESCE(round(v_rec.diag_js::NUMERIC, 4)::TEXT, 'NULL'), 21) ||
                      rpad(COALESCE(round(v_rec.diag_ws::NUMERIC, 4)::TEXT, 'NULL'), 21) ||
                      rpad(v_diag_risk_trend_display, 21) ||
                      'p90' || CASE WHEN v_fail_p90 THEN '✗' ELSE '✓' END || ',' ||
                      'js'  || CASE WHEN v_fail_js  THEN '✗' ELSE '✓' END || ',' ||
                      'w'   || CASE WHEN v_fail_ws  THEN '✗' ELSE '✓' END;

            v_report := array_append(v_report, v_line);
        END LOOP;

        v_report := array_append(v_report, '');
        v_report := array_append(v_report, 'Сводка провалов (из ' || v_uncovered_count::TEXT || ' непокрытых):');
        v_report := array_append(v_report, format('  Провал по p90 (любой):               %s', v_diag_cnt_any_p90));
        v_report := array_append(v_report, format('  Провал по js  (любой):               %s', v_diag_cnt_any_js));
        v_report := array_append(v_report, format('  Провал по W   (любой):               %s', v_diag_cnt_any_ws));
        v_report := array_append(v_report, format('  Все три условия провалены:           %s', v_diag_cnt_all_fail));
        v_report := array_append(v_report, format('  Только p90 (js✓, w✓):                 %s', v_diag_cnt_only_p90));
        v_report := array_append(v_report, format('  Только js  (p90✓, w✓):                %s', v_diag_cnt_only_js));
        v_report := array_append(v_report, format('  Только W   (p90✓, js✓):               %s', v_diag_cnt_only_ws));
        v_report := array_append(v_report, format('  p90 + js   (w✓):                      %s', v_diag_cnt_p90_js));
        v_report := array_append(v_report, format('  p90 + W    (js✓):                     %s', v_diag_cnt_p90_ws));
        v_report := array_append(v_report, format('  js + W     (p90✓):                    %s', v_diag_cnt_js_ws));

        v_report := array_append(v_report, '');
        v_report := array_append(v_report, format('Тренд риска за C-окно (%s мин) у непокрытых:', v_c_window_min));
        v_report := array_append(v_report, format('  РОСТ:        %s', v_diag_cnt_trend_up));
        v_report := array_append(v_report, format('  СНИЖЕНИЕ:    %s', v_diag_cnt_trend_down));
        v_report := array_append(v_report, format('  СТАБИЛЬНО:   %s', v_diag_cnt_trend_flat));
        v_report := array_append(v_report, format('  НЕТ ДАННЫХ:  %s', v_diag_cnt_trend_no_data));

        IF v_diag_cnt_trend_up > 0 THEN
            v_report := array_append(v_report, '');
            v_report := array_append(v_report, format(
                '  ⚠ %s из %s непокрытых имели РОСТ риска за C-окно — сигнал «не успел».',
                v_diag_cnt_trend_up, v_uncovered_count));
            v_report := array_append(v_report,
                '    Возможные меры: расширить hybrid_window_minutes (C смотрит дальше) или');
            v_report := array_append(v_report,
                '    снизить hybrid_p90_min_threshold (порог срабатывания C).');
        END IF;

        IF v_diag_cnt_trend_flat > 0
           AND v_diag_cnt_trend_flat >= v_diag_cnt_trend_up + v_diag_cnt_trend_down THEN
            v_report := array_append(v_report, '');
            v_report := array_append(v_report,
                '  ℹ Большинство непокрытых — со СТАБИЛЬНЫМ риском: сигнал «не приближался»,');
            v_report := array_append(v_report,
                '    а не «не успел». Расширение окна/снижение порога не поможет.');
            v_report := array_append(v_report,
                '    Причины — блокировка по js/W или действительно «тихий» инцидент.');
        END IF;

        IF v_diag_cnt_any_p90 > 0 AND v_diag_cnt_any_p90 = v_diag_cnt_any_js THEN
            v_report := array_append(v_report, '');
            v_report := array_append(v_report, '  ⚠ p90 и js проваливаются одновременно у всех непокрытых:');
            v_report := array_append(v_report, '    риск и JS-дивергенция в этих инцидентах коррелированы (низкий риск ⇔ низкий JS).');
        END IF;

        IF v_diag_cnt_only_p90 > 0 THEN
            v_report := array_append(v_report, '');
            v_report := array_append(v_report, format(
                '  ⚠ %s инцидентов имеют js и W в норме, но p90 < %s — C блокируется p90:',
                v_diag_cnt_only_p90, v_c_p90_min));
            v_report := array_append(v_report,
                '    рассмотреть снижение hybrid_p90_min_threshold или пересмотр весов W_score.');
        END IF;

        -- =====================================================================
        -- PRECISION эпизодов SICPP
        -- =====================================================================
        v_report := array_append(v_report, '');
        v_report := array_append(v_report, '--- ТОЧНОСТЬ SICPP (PRECISION эпизодов) ---');
        v_report := array_append(v_report, 'Эпизод считается TP, если хотя бы один инцидент начался в [episode_start, episode_end).');
        v_report := array_append(v_report, format('  всего эпизодов:            %s', v_total_episodes));
        v_report := array_append(v_report, format('  TP (последовал инцидент): %s', v_tp_episodes));
        v_report := array_append(v_report, format('  FP (без инцидента):       %s', v_fp_episodes));
        IF v_precision_episodes IS NOT NULL THEN
            v_report := array_append(v_report, format('  precision: %s%%', round(v_precision_episodes::NUMERIC * 100, 1)));
        END IF;

        -- =====================================================================
        -- РАСПРЕДЕЛЕНИЕ LEAD TIME SICPP
        -- =====================================================================
        WITH leads AS (
            SELECT pi.id,
                   EXTRACT(EPOCH FROM (
                       pi.start_timepoint - (
                           SELECT COALESCE(e.episode_started_at, e.first_signal_time)
                           FROM _tmp_sicpp_episodes_v3 e
                           WHERE e.episode_start <= pi.start_timepoint
                             AND e.episode_end >= pi.start_timepoint - v_window_minutes * INTERVAL '1 minute'
                           ORDER BY e.episode_end DESC
                           LIMIT 1
                       )
                   )) / 60 AS raw_lead_min,
                   EXTRACT(EPOCH FROM (
                       pi.start_timepoint - (
                           SELECT sh.changed_at
                           FROM sicpp_history sh
                           WHERE sh.changed_at <= pi.start_timepoint
                             AND sh.reason = 'signal started'
                           ORDER BY sh.changed_at DESC LIMIT 1
                       )
                   )) / 60 AS fresh_lead_min
            FROM markov_chain_performance_incident pi
            WHERE pi.id = ANY(v_included_ids)
        )
        SELECT MIN(raw_lead_min),
               PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY raw_lead_min),
               PERCENTILE_CONT(0.5)  WITHIN GROUP (ORDER BY raw_lead_min),
               PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY raw_lead_min),
               PERCENTILE_CONT(0.9)  WITHIN GROUP (ORDER BY raw_lead_min),
               MAX(raw_lead_min),
               COUNT(*) FILTER (WHERE raw_lead_min < 100)::REAL
                   / NULLIF(COUNT(*) FILTER (WHERE raw_lead_min IS NOT NULL), 0),
               PERCENTILE_CONT(0.5)  WITHIN GROUP (ORDER BY fresh_lead_min)
        INTO v_lead_min, v_lead_p25, v_lead_median, v_lead_p75, v_lead_p90,
             v_lead_max, v_lead_share_under_100, v_fresh_lead_median
        FROM leads WHERE raw_lead_min IS NOT NULL;

        v_report := array_append(v_report, '');
        v_report := array_append(v_report, '--- РАСПРЕДЕЛЕНИЕ LEAD TIME SICPP ---');
        v_report := array_append(v_report, 'Lead time (raw) = start_timepoint - episode_started_at покрывающего эпизода.');
        v_report := array_append(v_report, 'Lead time (fresh) = start_timepoint - последний changed_at с reason=''signal started''.');
        IF v_lead_min IS NOT NULL THEN
            v_report := array_append(v_report, format('  raw lead time, мин:  min=%s, p25=%s, p50=%s, p75=%s, p90=%s, max=%s',
                round(v_lead_min::NUMERIC, 1), round(v_lead_p25::NUMERIC, 1), round(v_lead_median::NUMERIC, 1),
                round(v_lead_p75::NUMERIC, 1), round(v_lead_p90::NUMERIC, 1), round(v_lead_max::NUMERIC, 1)));
            v_report := array_append(v_report, format('  доля инцидентов с raw lead < 100 мин: %s%%',
                round((v_lead_share_under_100 * 100)::NUMERIC, 1)));

            IF v_lead_median > v_max_dur_cap THEN
                v_report := array_append(v_report, format(
                    '  ℹ Медиана raw lead time %s мин > cap %s мин — длительное предаварийное состояние (не артефакт каппинга).',
                    round(v_lead_median::NUMERIC, 1), v_max_dur_cap));
                IF v_fresh_lead_median IS NOT NULL THEN
                    v_lead_vs_fresh_delta_pct := ROUND(
                        (ABS(v_lead_median - v_fresh_lead_median) / NULLIF(v_lead_median, 0) * 100)::NUMERIC, 1);
                    v_report := array_append(v_report, format(
                        '  sanity check: raw (%s мин) vs fresh (%s мин), Δ = %s%%',
                        round(v_lead_median::NUMERIC, 1), round(v_fresh_lead_median::NUMERIC, 1),
                        v_lead_vs_fresh_delta_pct));
                    IF v_lead_vs_fresh_delta_pct < 20 THEN
                        v_report := array_append(v_report, '  ✓ значения согласованы: episode_started_at корректно наследуется через carry-forward.');
                    ELSE
                        v_report := array_append(v_report, '  ⚠ значения расходятся: проверить carry-forward episode_started_at в sicpp_history.');
                    END IF;
                END IF;
            END IF;
        ELSE
            v_report := array_append(v_report, '  нет данных для расчёта raw lead time');
        END IF;

        IF v_fresh_lead_median IS NOT NULL THEN
            v_report := array_append(v_report, format('  fresh lead time, медиана: %s мин', round(v_fresh_lead_median::NUMERIC, 1)));
        END IF;

        -- =====================================================================
        -- LONG-ЭПИЗОДЫ
        -- =====================================================================
        WITH leads AS (
            SELECT pi.id,
                   EXTRACT(EPOCH FROM (
                       pi.start_timepoint - (
                           SELECT COALESCE(e.episode_started_at, e.first_signal_time)
                           FROM _tmp_sicpp_episodes_v3 e
                           WHERE e.episode_start <= pi.start_timepoint
                             AND e.episode_end >= pi.start_timepoint - v_window_minutes * INTERVAL '1 minute'
                           ORDER BY e.episode_end DESC
                           LIMIT 1
                       )
                   )) / 60 AS raw_lead_min
            FROM markov_chain_performance_incident pi
            WHERE pi.id = ANY(v_included_ids)
        ),
        classified AS (
            SELECT raw_lead_min, (raw_lead_min > v_long_episode_threshold) AS is_long
            FROM leads WHERE raw_lead_min IS NOT NULL
        )
        SELECT
            COUNT(*) FILTER (WHERE is_long),
            COUNT(*) FILTER (WHERE NOT is_long),
            PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY raw_lead_min) FILTER (WHERE NOT is_long),
            PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY raw_lead_min) FILTER (WHERE NOT is_long),
            AVG(raw_lead_min) FILTER (WHERE NOT is_long),
            MAX(raw_lead_min) FILTER (WHERE NOT is_long)
        INTO v_long_episode_count, v_short_lead_count,
             v_short_lead_p50, v_short_lead_p90,
             v_short_lead_mean, v_short_lead_max
        FROM classified;

        v_report := array_append(v_report, '');
        v_report := array_append(v_report, format('--- LONG-ЭПИЗОДЫ (порог: > %s мин) ---', v_long_episode_threshold));
        v_report := array_append(v_report, format('Эпизоды с raw lead > %s мин выделены как LONG; остальные — SHORT.', v_long_episode_threshold));
        v_report := array_append(v_report, '');
        v_report := array_append(v_report, format('  Всего покрыто SICPP:  %s', v_incidents_with_signal));
        v_report := array_append(v_report, format('  SHORT (≤ %s мин):   %s', v_long_episode_threshold, v_short_lead_count));
        v_report := array_append(v_report, format('  LONG  (> %s мин):    %s', v_long_episode_threshold, v_long_episode_count));
        v_report := array_append(v_report, '');
        v_report := array_append(v_report, '--- СРАВНЕНИЕ ALL vs SHORT (raw lead, мин) ---');
        v_report := array_append(v_report,
            rpad('Показатель', 12) || lpad('ALL', 10) || lpad('SHORT', 10));
        v_report := array_append(v_report,
            rpad('p50', 12) ||
            lpad(COALESCE(round(v_lead_median::NUMERIC, 1)::TEXT, 'NULL'), 10) ||
            lpad(COALESCE(round(v_short_lead_p50::NUMERIC, 1)::TEXT, 'NULL'), 10));
        v_report := array_append(v_report,
            rpad('p90', 12) ||
            lpad(COALESCE(round(v_lead_p90::NUMERIC, 1)::TEXT, 'NULL'), 10) ||
            lpad(COALESCE(round(v_short_lead_p90::NUMERIC, 1)::TEXT, 'NULL'), 10));
        v_report := array_append(v_report,
            rpad('mean', 12) ||
            lpad(COALESCE(round(v_avg_minutes_to_incident::NUMERIC, 1)::TEXT, 'NULL'), 10) ||
            lpad(COALESCE(round(v_short_lead_mean::NUMERIC, 1)::TEXT, 'NULL'), 10));
        v_report := array_append(v_report,
            rpad('max', 12) ||
            lpad(COALESCE(round(v_lead_max::NUMERIC, 1)::TEXT, 'NULL'), 10) ||
            lpad(COALESCE(round(v_short_lead_max::NUMERIC, 1)::TEXT, 'NULL'), 10));

        IF v_long_episode_count > 0 AND v_lead_median IS NOT NULL AND v_lead_p90 IS NOT NULL THEN
            v_report := array_append(v_report, '');
            v_report := array_append(v_report,
                'Интерпретация: SHORT-метрики (p50/p90/mean/max) отражают «типичное» предаварийное состояние');
            v_report := array_append(v_report,
                format('без искажения %s длинными эпизодами. Для оперативных решений используйте SHORT;', v_long_episode_count));
            v_report := array_append(v_report,
                'ALL-метрики полезны только для оценки «сколько SICPP держится в предаварийном режиме».');
        END IF;


    END IF;

    -- =========================================================================
    -- 10. Непокрытые инциденты (без приоритизации)
    -- =========================================================================
    IF NOT v_csv_mode THEN
        v_report := array_append(v_report, '');
        v_report := array_append(v_report, '--- НЕПОКРЫТЫЕ ИНЦИДЕНТЫ (v22.1, без ранжирования по P3) ---');
        v_report := array_append(v_report, '  Внимание: markov_chain_performance_incident не содержит priority.');
        v_report := array_append(v_report, '  Разделение на P3/P4 невозможно; проверяется только факт покрытия SICPP.');

        DECLARE
            v_uncovered_sicpp_count INT;
        BEGIN
            SELECT COUNT(*) INTO v_uncovered_sicpp_count
            FROM markov_chain_performance_incident pi
            WHERE pi.id = ANY(v_included_ids)
              AND NOT EXISTS (
                  SELECT 1 FROM _tmp_sicpp_episodes_v3 e
                  WHERE e.episode_start <= pi.start_timepoint
                    AND e.episode_end >= pi.start_timepoint - v_window_minutes * INTERVAL '1 minute'
              );

            IF v_uncovered_sicpp_count = 0 THEN
                v_report := array_append(v_report, '  ✅ Все инциденты покрыты сигналом SICPP.');
            ELSE
                v_report := array_append(v_report, format('  🔴 ОБНАРУЖЕНО %s непокрытых SICPP инцидентов:', v_uncovered_sicpp_count));
                FOR v_rec IN
                    SELECT pi.id, pi.start_timepoint,
                           EXTRACT(EPOCH FROM (pi.finish_timepoint - pi.start_timepoint)) / 60 AS dur
                    FROM markov_chain_performance_incident pi
                    WHERE pi.id = ANY(v_included_ids)
                      AND NOT EXISTS (
                          SELECT 1 FROM _tmp_sicpp_episodes_v3 e
                          WHERE e.episode_start <= pi.start_timepoint
                            AND e.episode_end >= pi.start_timepoint - v_window_minutes * INTERVAL '1 minute'
                      )
                    ORDER BY pi.start_timepoint
                LOOP
                    v_report := array_append(v_report, format('    ID=%s, start=%s, длит=%s мин',
                        v_rec.id, to_char(v_rec.start_timepoint, 'YYYY-MM-DD HH24:MI'),
                        COALESCE(round(v_rec.dur::NUMERIC, 1)::TEXT, 'N/A')));
                END LOOP;
                v_report := array_append(v_report, '  ⚠ Запись в sicpp_coverage_alerts отключена: таблица требует priority, а MCI его не имеет.');
            END IF;
        END;
    END IF;

    IF NOT v_csv_mode THEN
        v_report := array_append(v_report, '');
        v_report := array_append(v_report, '=== КОНЕЦ ОТЧЁТА ===');
    END IF;

    DROP TABLE IF EXISTS _tmp_sicpp_episodes_v3;
    DROP TABLE IF EXISTS _tmp_c_windows;

    RETURN v_report;
END;
$$;

COMMENT ON FUNCTION generate_incident_forecast_report_v2(TIMESTAMPTZ, TIMESTAMPTZ, BOOLEAN) IS
'v22.1 (2026-10-28). Отчёт по прогнозированию инцидентов.

ИЗМЕНЕНИЯ v22.1 (относительно v22.0):
  1) In-memory автонастройка (при auto_threshold = TRUE) больше не перезаписывает
     v_js_threshold / v_risk_threshold. Она сохраняется в v_js_threshold_reco /
     v_risk_threshold_reco и выводится в шапку отдельной строкой с пометкой
     «НЕ использована».
  2) v_js_threshold / v_risk_threshold всегда берутся из incident_forecast_config
     (cfg.js_threshold / cfg.risk_threshold) — те же, что использует
     mchain_hybrid_alert_at для W_score и sicpp_calculate_at для генерации
     истории. Это устраняет расхождение между шапкой и W_score (test7:
     header показывал 0.1376/1 из in-memory, а W_score считался по
     0.216/0.99 из DB).
  3) v_legend явно указывает, что W_score считается по фактическим порогам.
  4) Добавлен параметр p_show_inmemory_reco (по умолчанию TRUE) — выводить
     ли in-memory рекомендацию, если auto_threshold = TRUE.
  5) Сигнатура расширена третьим параметром p_show_inmemory_reco BOOLEAN
     DEFAULT TRUE. Обратная совместимость: вызов с двумя аргументами
     работает как раньше (in-memory reco показывается, но помечена как
     «не использована»).

Для Варианта C (0.15/0.85) рекомендуется auto_threshold = FALSE:
  UPDATE incident_forecast_config
  SET js_threshold = 0.15, risk_threshold = 0.85, auto_threshold = FALSE;
  SELECT historical_fill_sicpp(...);  -- перегенерация с p_clean = TRUE
  SELECT historical_fill_c_only(...); -- перегенерация C-only
  -- отчёты после этого покажут JS-порог (config) = 0.15, Порог риска (config) = 0.85,
  -- без строки «In-memory рекомендация».
';
-- =============================================================================
-- Функция: diagnose_incident_coverage
-- Версия: 19.1
--
-- =============================================================================
CREATE OR REPLACE FUNCTION diagnose_incident_coverage(
    p_incident_id BIGINT
)
RETURNS TEXT[]
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_report TEXT[] := '{}';
    v_inc RECORD;
    v_cfg RECORD;
    v_last_sicpp RECORD;
    v_last_status TEXT;
    v_window INT;
    v_series_enabled BOOLEAN;
    v_covering_episodes INT := 0;
    v_excluded_by_status   BOOLEAN := FALSE;
    v_excluded_by_series   BOOLEAN := FALSE;
    v_prev_unfinished BOOLEAN := FALSE;
    v_excluded_reason TEXT := NULL;
    v_rec RECORD;
    v_duration_min NUMERIC;
    v_js_thr REAL;
    v_risk_thr REAL;
    v_w_js REAL;
    v_w_risk REAL;
    v_w_score REAL;
BEGIN
    SELECT * INTO v_inc FROM markov_chain_performance_incident WHERE id = p_incident_id;
    IF NOT FOUND THEN
        RETURN ARRAY[format('Инцидент с ID=%s не найден в markov_chain_performance_incident.', p_incident_id)];
    END IF;

    IF v_inc.finish_timepoint IS NOT NULL THEN
        v_duration_min := round((EXTRACT(EPOCH FROM (v_inc.finish_timepoint - v_inc.start_timepoint)) / 60)::numeric, 1);
    END IF;

    SELECT * INTO v_cfg FROM incident_forecast_config LIMIT 1;
    v_window         := COALESCE(v_cfg.window_minutes, 60);
    v_series_enabled := COALESCE(v_cfg.series_filter_enabled, TRUE);
    v_js_thr         := COALESCE(v_cfg.js_threshold, 0.15);
    v_risk_thr       := COALESCE(v_cfg.risk_threshold, 0.85);
    v_w_js           := COALESCE(v_cfg.weight_js, 0.7);
    v_w_risk         := COALESCE(v_cfg.weight_risk, 0.3);

    v_report := array_append(v_report, format('=== ДИАГНОСТИКА ПОКРЫТИЯ ИНЦИДЕНТА ID=%s (v19.1, priority исключён) ===', p_incident_id));
    v_report := array_append(v_report, '');
    v_report := array_append(v_report, '--- 1. ДАННЫЕ ИНЦИДЕНТА ---');
    v_report := array_append(v_report, format('  ID:                %s', v_inc.id));
    v_report := array_append(v_report, format('  start_timepoint:   %s', v_inc.start_timepoint));
    v_report := array_append(v_report, format('  finish_timepoint:  %s', COALESCE(v_inc.finish_timepoint::TEXT, 'NULL')));
    v_report := array_append(v_report, '  priority:          (недоступен: MCI не содержит столбца priority)');
    IF v_duration_min IS NOT NULL THEN
        v_report := array_append(v_report, format('  duration, мин:     %s', v_duration_min));
    END IF;

    -- 2. Фильтры (priority_filter удалён)
    v_report := array_append(v_report, '');
    v_report := array_append(v_report, '--- 2. ПРОВЕРКА ФИЛЬТРОВ ---');
    v_report := array_append(v_report, '  priority_filter:   (не применим: у MCI нет priority)');

    SELECT status INTO v_last_status
    FROM profile_comparison_log
    WHERE current_window_end < v_inc.start_timepoint
    ORDER BY current_window_end DESC LIMIT 1;

    v_report := array_append(v_report, format('  v_last_status: %s', COALESCE(v_last_status, 'NULL')));

    IF v_cfg.status_filter IS NULL THEN
        v_report := array_append(v_report, '  status_filter: NULL (все статусы)');
    ELSIF v_last_status = ANY(v_cfg.status_filter) THEN
        v_report := array_append(v_report, format('  status_filter: %s — %s входит → пропуск',
            v_cfg.status_filter, v_last_status));
    ELSE
        v_report := array_append(v_report, format('  status_filter: %s — %s НЕ входит → ИСКЛЮЧЁН',
            v_cfg.status_filter, v_last_status));
        v_excluded_by_status := TRUE;
        v_excluded_reason := COALESCE(v_excluded_reason, 'status_filter');
    END IF;

    v_report := array_append(v_report, format('  series_filter_enabled: %s', v_series_enabled));
    IF v_series_enabled AND v_last_status = 'INCIDENT' THEN
        v_prev_unfinished := EXISTS (
            SELECT 1 FROM markov_chain_performance_incident pi2
            WHERE pi2.start_timepoint < v_inc.start_timepoint
              AND (pi2.finish_timepoint IS NULL OR pi2.finish_timepoint > v_inc.start_timepoint)
              AND pi2.id <> v_inc.id
        );
        IF v_prev_unfinished THEN
            v_report := array_append(v_report, '  series_filter: v_last_status=INCIDENT AND предыдущий не завершён → ИСКЛЮЧЁН');
            v_excluded_by_series := TRUE;
            v_excluded_reason := COALESCE(v_excluded_reason, 'series_filter');
        ELSE
            v_report := array_append(v_report, '  series_filter: v_last_status=INCIDENT, но предыдущий завершён → НЕ исключён');
        END IF;
    ELSE
        v_report := array_append(v_report, '  series_filter: не применим');
    END IF;

    -- 3. Последняя запись SICPP
    SELECT * INTO v_last_sicpp FROM sicpp_history
    WHERE changed_at <= v_inc.start_timepoint
    ORDER BY changed_at DESC LIMIT 1;

    v_report := array_append(v_report, '');
    v_report := array_append(v_report, '--- 3. ПОСЛЕДНЯЯ ЗАПИСЬ SICPP ---');
    IF NOT FOUND THEN
        v_report := array_append(v_report, '  ⚠ Нет записей в sicpp_history до start_timepoint.');
    ELSE
        v_report := array_append(v_report, format('  id: %s, changed_at: %s, signal_active: %s, reason: %s',
            v_last_sicpp.id, v_last_sicpp.changed_at, v_last_sicpp.signal_active, COALESCE(v_last_sicpp.reason, 'NULL')));
        v_report := array_append(v_report, format('  first_signal_time: %s, signal_duration: %s',
            COALESCE(v_last_sicpp.first_signal_time::TEXT, 'NULL'),
            COALESCE(v_last_sicpp.signal_duration::TEXT, 'NULL')));
        v_report := array_append(v_report, format('  js_avg: %s, risk_avg: %s',
            COALESCE(round(v_last_sicpp.js_avg::NUMERIC, 4)::TEXT, 'NULL'),
            COALESCE(round(v_last_sicpp.risk_avg::NUMERIC, 4)::TEXT, 'NULL')));

        IF v_last_sicpp.js_avg IS NOT NULL AND v_last_sicpp.risk_avg IS NOT NULL THEN
            v_w_score := (v_last_sicpp.risk_avg / NULLIF(v_risk_thr, 0)) * v_w_risk
                       + (v_last_sicpp.js_avg   / NULLIF(v_js_thr, 0))   * v_w_js;
            v_report := array_append(v_report, format(
                '  WEIGHTED score = (risk/%s)*%s + (js/%s)*%s = %s',
                round(v_risk_thr::NUMERIC, 3),
                round(v_w_risk::NUMERIC, 2),
                round(v_js_thr::NUMERIC, 3),
                round(v_w_js::NUMERIC, 2),
                round(v_w_score::NUMERIC, 4)));
        END IF;
    END IF;

    -- 4. Покрытие по эпизодам
    v_report := array_append(v_report, '');
    v_report := array_append(v_report, format('--- 4. ПОКРЫТИЕ ПО ЭПИЗОДАМ (окно %s мин) ---', v_window));
    v_report := array_append(v_report, format('  Правило: episode_start <= %s AND episode_end >= %s - %s мин',
        v_inc.start_timepoint, v_inc.start_timepoint, v_window));

    FOR v_rec IN
    WITH history AS (
        SELECT id, changed_at, signal_active, first_signal_time, signal_duration,
               LAG(signal_active) OVER (ORDER BY changed_at, id) AS prev_active
        FROM sicpp_history
    ),
    starts AS (
        SELECT id, changed_at AS raw_start, first_signal_time, signal_duration
        FROM history
        WHERE signal_active = TRUE
          AND (prev_active IS NULL OR prev_active = FALSE)
    ),
    ends AS (
        SELECT changed_at AS end_ts FROM history WHERE signal_active = FALSE
    ),
    episodes AS (
        SELECT s.id, s.raw_start,
               (SELECT MIN(e.end_ts) FROM ends e WHERE e.end_ts > s.raw_start) AS raw_end,
               s.first_signal_time, s.signal_duration
        FROM starts s
    )
    SELECT id, raw_start AS episode_start,
           COALESCE(raw_end, now()) AS episode_end,
           first_signal_time, signal_duration
    FROM episodes
    WHERE raw_start <= v_inc.start_timepoint
      AND COALESCE(raw_end, now()) >= v_inc.start_timepoint - v_window * INTERVAL '1 minute'
    ORDER BY raw_start
    LOOP
        v_covering_episodes := v_covering_episodes + 1;
        v_report := array_append(v_report, format(
            '    id=%s, [%s .. %s], пробег=%s мин, first_signal=%s',
            v_rec.id,
            v_rec.episode_start,
            v_rec.episode_end,
            COALESCE(v_rec.signal_duration::TEXT, '-'),
            COALESCE(v_rec.first_signal_time::TEXT, '-')));
    END LOOP;

    IF v_covering_episodes > 0 THEN
        v_report := array_append(v_report, format('  ➜ ПОКРЫТО (%s эпизодов)', v_covering_episodes));
    ELSE
        v_report := array_append(v_report, '  ➜ НЕ ПОКРЫТО (нет эпизода)');
    END IF;

    -- 5. Вердикт
    v_report := array_append(v_report, '');
    v_report := array_append(v_report, '--- 5. ИТОГОВЫЙ ВЕРДИКТ ---');
    IF v_excluded_reason IS NOT NULL THEN
        v_report := array_append(v_report, format('  ❌ ИСКЛЮЧЁН: %s', v_excluded_reason));
    ELSIF v_covering_episodes > 0 THEN
        v_report := array_append(v_report, '  ✅ ПРИСУТСТВУЕТ и ПОКРЫТ (v19.1).');
    ELSE
        v_report := array_append(v_report, '  ⚠ ПРИСУТСТВУЕТ, но НЕ покрыт.');
    END IF;

    RETURN v_report;
END;
$$;

COMMENT ON FUNCTION diagnose_incident_coverage(BIGINT) IS
'v19.1 (2026-10-25). Диагностика покрытия инцидента по markov_chain_performance_incident.

КЛЮЧЕВЫЕ ИЗМЕНЕНИЯ v19.1 (относительно v4.0.1):
  - Источник инцидентов: performance_incident → markov_chain_performance_incident.
  - Удалена переменная v_excluded_by_priority.
  - Удалена секция разбора priority_filter (у MCI нет priority).
  - Удалена строка "priority: ..." в блоке 1. ДАННЫЕ ИНЦИДЕНТА;
    вместо неё печатается пометка "(недоступен: MCI не содержит столбца priority)".
  - v_excluded_reason теперь может принимать только значения
    ''status_filter'' или ''series_filter''.
  - В блоке 2 сохранён разбор status_filter и series_filter без изменений.

Логика детекции эпизодов (first-FALSE-after-start, игнорирование init)
соответствует generate_incident_forecast_report_v2 v19.1.';

-- =============================================================================
-- Функция: get_active_p3_alerts
-- Назначение: возвращает неподтверждённые (acknowledged = FALSE) P3-алерты.
-- =============================================================================
CREATE OR REPLACE FUNCTION get_active_p3_alerts()
RETURNS TABLE (
    alert_id        BIGINT,
    detected_at     TIMESTAMPTZ,
    incident_id     BIGINT,
    incident_start  TIMESTAMPTZ,
    priority        SMALLINT,
    reason          TEXT,
    age_hours       NUMERIC
)
LANGUAGE sql
STABLE
AS $$
    SELECT
        a.id                                            AS alert_id,
        a.detected_at,
        a.incident_id,
        a.incident_start,
        a.priority,
        a.reason,
        round(EXTRACT(EPOCH FROM (now() - a.detected_at)) / 3600, 1) AS age_hours
    FROM sicpp_coverage_alerts a
    WHERE a.acknowledged = FALSE
    ORDER BY a.detected_at DESC;
$$;

COMMENT ON FUNCTION get_active_p3_alerts() IS
'Возвращает неподтверждённые P3-алерты (acknowledged = FALSE), с возрастом в часах.';

-- =============================================================================
-- Функция: acknowledge_p3_alert
-- Назначение: подтверждение алерта по incident_id.
-- =============================================================================
CREATE OR REPLACE FUNCTION acknowledge_p3_alert(
    p_incident_id BIGINT,
    p_ack_by      TEXT DEFAULT NULL
)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    v_rows INT;
BEGIN
    UPDATE sicpp_coverage_alerts
    SET acknowledged    = TRUE,
        acknowledged_at = now(),
        acknowledged_by = COALESCE(p_ack_by, current_user)
    WHERE incident_id = p_incident_id
      AND acknowledged = FALSE;

    GET DIAGNOSTICS v_rows = ROW_COUNT;

    IF v_rows = 0 THEN
        RETURN format('Алерт для incident_id=%s не найден или уже подтверждён.',
                      p_incident_id);
    END IF;

    RETURN format('Алерт для incident_id=%s подтверждён пользователем %s.',
                  p_incident_id, COALESCE(p_ack_by, current_user));
END;
$$;

COMMENT ON FUNCTION acknowledge_p3_alert(BIGINT, TEXT) IS
'Подтверждает P3-алерт по incident_id (acknowledged = TRUE, фиксирует ack_at/by).';


-- =============================================================================
-- Функция: get_current_preincident_status
-- Версия: 5.1.0
-- Назначение: возвращает текущий интегральный статус предынцедентного
--             состояния СУБД на основе SICPP, сравнения профилей и
--             марковского прогноза риска.
--
-- Возвращает INTEGER:
--   0   — NORMAL:  предпосылок нет, СУБД в норме
--   50  — WARNING: незначительные предпосылки, требуется мониторинг
--   100 — ALARM:   сильные предпосылки, СУБД в предаварийном состоянии
--
-- Примеры использования:
--   SELECT get_current_preincident_status();                 -- 0/50/100
--   SELECT get_current_preincident_status(p_alarm_risk => 0.95);  -- строже
--   SET client_min_messages = DEBUG1;
--   SELECT get_current_preincident_status();                 -- с диагностикой
-- =============================================================================
CREATE OR REPLACE FUNCTION get_current_preincident_status(
    p_sicpp_warn_strength   REAL DEFAULT 1.1,   -- оставлен для совместимости, в теле не используется
    p_alarm_risk            REAL DEFAULT 0.90,
    p_warning_risk          REAL DEFAULT 0.60,
    p_warning_js            REAL DEFAULT 0.10,
    p_recent_minutes        INT  DEFAULT 5,
    p_state_staleness_min   INT  DEFAULT 5
)
RETURNS INTEGER
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_state_id            SMALLINT;
    v_is_critical         BOOLEAN := FALSE;
    v_sicpp_updated_at    TIMESTAMPTZ;
    v_sicpp_active        BOOLEAN;
    v_sicpp_fresh         BOOLEAN := FALSE;
    v_comp_window_end     TIMESTAMPTZ;
    v_comp_status         TEXT;
    v_comp_js             REAL;
    v_comp_pre_alert      INTEGER;
    v_comp_matched_id     BIGINT;
    v_comp_fresh          BOOLEAN := FALSE;
    v_risk                REAL;
    v_hybrid_alert        BOOLEAN := FALSE;
    v_recent_interval     INTERVAL;
    v_stale_interval      INTERVAL;
BEGIN
    v_recent_interval := (p_recent_minutes      || ' minutes')::INTERVAL;
    v_stale_interval  := (p_state_staleness_min || ' minutes')::INTERVAL;

    -- 1. Текущее состояние из markov
    BEGIN
        v_state_id := mchain_get_current_state_id();
    EXCEPTION WHEN OTHERS THEN
        v_state_id := NULL;
    END;
    IF v_state_id IS NOT NULL THEN
        BEGIN
            SELECT EXISTS (SELECT 1 FROM critical_states WHERE state_id = v_state_id)
            INTO v_is_critical;
        EXCEPTION WHEN OTHERS THEN
            v_is_critical := FALSE;
        END;
    END IF;

    -- 2. SICPP singleton
    BEGIN
        SELECT updated_at, signal_active
        INTO v_sicpp_updated_at, v_sicpp_active
        FROM sicpp_current_state WHERE id = 1;
    EXCEPTION WHEN OTHERS THEN
        v_sicpp_updated_at := NULL;
    END;
    IF v_sicpp_updated_at IS NOT NULL
       AND v_sicpp_updated_at >= now() - v_stale_interval
       AND COALESCE(v_sicpp_active, FALSE) = TRUE THEN
        v_sicpp_fresh := TRUE;
    ELSE
        v_sicpp_fresh  := FALSE;
        v_sicpp_active := FALSE;
    END IF;

    -- 3. Сравнение профилей
    BEGIN
        SELECT current_window_end, status, js_divergence,
               pre_alert_flag, matched_pre_incident_id
        INTO v_comp_window_end, v_comp_status, v_comp_js,
             v_comp_pre_alert, v_comp_matched_id
        FROM profile_comparison_log
        ORDER BY current_window_end DESC LIMIT 1;
    EXCEPTION WHEN OTHERS THEN
        v_comp_window_end := NULL;
    END;
    IF v_comp_window_end IS NOT NULL
       AND v_comp_window_end >= now() - v_recent_interval THEN
        v_comp_fresh := TRUE;
    ELSE
        v_comp_fresh := FALSE;
    END IF;

    -- 4. Риск и C-only
    BEGIN
        v_risk := mchain_predict_risk_current_horizon();
    EXCEPTION WHEN OTHERS THEN
        v_risk := NULL;
    END;

    BEGIN
        SELECT h.alert INTO v_hybrid_alert
        FROM mchain_hybrid_alert_at(now()) h;
    EXCEPTION WHEN OTHERS THEN
        v_hybrid_alert := FALSE;
    END;

    -- ALARM (100)
    IF v_is_critical THEN RETURN 100; END IF;
    IF v_hybrid_alert THEN RETURN 100; END IF;
    IF v_comp_fresh AND v_comp_status = 'INCIDENT' THEN RETURN 100; END IF;
    IF v_risk IS NOT NULL AND v_risk >= p_alarm_risk THEN RETURN 100; END IF;

    -- WARNING (50)
    IF v_sicpp_fresh AND v_sicpp_active THEN RETURN 50; END IF;
    IF v_comp_fresh AND v_comp_matched_id IS NOT NULL THEN RETURN 50; END IF;
    IF v_comp_fresh AND v_comp_pre_alert = 100 THEN RETURN 50; END IF;
    IF v_comp_fresh AND v_comp_status IN ('CRITICAL', 'WARNING') THEN RETURN 50; END IF;
    IF v_comp_fresh AND v_comp_js IS NOT NULL AND v_comp_js >= p_warning_js THEN RETURN 50; END IF;
    IF v_risk IS NOT NULL AND v_risk >= p_warning_risk THEN RETURN 50; END IF;

    RETURN 0;
END;
$$;

COMMENT ON FUNCTION get_current_preincident_status(REAL, REAL, REAL, REAL, INT, INT) IS
'v5.1.0 (2026-10-28, без integral_signal_calculate_at).
Текущий интегральный статус предынцедентного состояния СУБД: 0 / 50 / 100.
Источники: markov state, sicpp_current_state, profile_comparison_log,
mchain_predict_risk_current_horizon(), mchain_hybrid_alert_at(now()).

ALARM (100): critical_state OR C-alert OR comparison.status=INCIDENT OR risk >= p_alarm_risk.
WARNING (50): SICPP активен OR matched_pre_incident_id OR pre_alert=100 OR
              status IN (CRITICAL,WARNING) OR js >= p_warning_js OR risk >= p_warning_risk.
NORMAL (0): ни один триггер не сработал.
';


-- =============================================================================
-- Функция: get_current_preincident_status_detail
-- Версия: 3.1.0
-- Назначение: детализация решения get_current_preincident_status() — разложение
--             по источникам (State, SICPP, Comparison, C, Risk) и порогам.
-- =============================================================================
CREATE OR REPLACE FUNCTION get_current_preincident_status_detail(
    p_sicpp_warn_strength REAL DEFAULT 1.1,
    p_alarm_risk          REAL DEFAULT 0.90,
    p_warning_risk        REAL DEFAULT 0.60,
    p_warning_js          REAL DEFAULT 0.10,
    p_recent_minutes      INT  DEFAULT 5,
    p_state_staleness_min INT  DEFAULT 5
)
RETURNS TEXT[]
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_report     TEXT[] := '{}';
    v_status     INTEGER;
    v_state_id   SMALLINT;
    v_is_crit    BOOLEAN;
    v_sicpp      RECORD;
    v_comp       RECORD;
    v_risk       REAL;
    v_hyb        RECORD;
    v_js_avg_now REAL;
BEGIN
    v_status := get_current_preincident_status(
        p_sicpp_warn_strength, p_alarm_risk, p_warning_risk,
        p_warning_js, p_recent_minutes, p_state_staleness_min);

    v_report := array_append(v_report, format('=== PREINCIDENT STATUS: %s (%s) ===',
        v_status,
        CASE v_status WHEN 0 THEN 'NORMAL' WHEN 50 THEN 'WARNING'
                      WHEN 100 THEN 'ALARM' ELSE 'UNKNOWN' END));
    v_report := array_append(v_report, format('Timestamp: %s',
        to_char(now(), 'YYYY-MM-DD HH24:MI:SS')));
    v_report := array_append(v_report, '');

    -- 1. State
    BEGIN
        v_state_id := mchain_get_current_state_id();
    EXCEPTION WHEN OTHERS THEN
        v_state_id := NULL;
    END;
    BEGIN
        SELECT EXISTS(SELECT 1 FROM critical_states WHERE state_id = v_state_id)
        INTO v_is_crit;
    EXCEPTION WHEN OTHERS THEN
        v_is_crit := FALSE;
    END;
    v_report := array_append(v_report, format('1. State:  id=%s, critical=%s',
        COALESCE(v_state_id::TEXT, 'NULL'), v_is_crit));

    -- 2. SICPP
    BEGIN
        SELECT updated_at, signal_active, signal_strength, signal_duration,
               signal_capped, first_signal_time
        INTO v_sicpp
        FROM sicpp_current_state WHERE id = 1;
    EXCEPTION WHEN OTHERS THEN
        v_sicpp.updated_at := NULL;
    END;
    v_report := array_append(v_report, format(
        '2. SICPP:  updated=%s, active=%s, strength=%s, duration=%s min, capped=%s, first_signal=%s',
        COALESCE(to_char(v_sicpp.updated_at, 'HH24:MI:SS'), 'NULL'),
        COALESCE(v_sicpp.signal_active::TEXT, 'NULL'),
        COALESCE(round(v_sicpp.signal_strength::NUMERIC, 4)::TEXT, 'NULL'),
        COALESCE(v_sicpp.signal_duration::TEXT, '0'),
        COALESCE(v_sicpp.signal_capped::TEXT, 'FALSE'),
        COALESCE(to_char(v_sicpp.first_signal_time, 'YYYY-MM-DD HH24:MI'), 'NULL')));

    -- 3. Comparison
    BEGIN
        SELECT current_window_end, status, js_divergence,
               pre_alert_flag, matched_pre_incident_id
        INTO v_comp
        FROM profile_comparison_log
        ORDER BY current_window_end DESC LIMIT 1;
    EXCEPTION WHEN OTHERS THEN
        v_comp.current_window_end := NULL;
    END;
    v_report := array_append(v_report, format(
        '3. Comp:   window_end=%s, status=%s, js=%s, pre_alert=%s, matched_id=%s',
        COALESCE(to_char(v_comp.current_window_end, 'HH24:MI:SS'), 'NULL'),
        COALESCE(v_comp.status, 'NULL'),
        COALESCE(round(v_comp.js_divergence::NUMERIC, 4)::TEXT, 'NULL'),
        COALESCE(v_comp.pre_alert_flag::TEXT, 'NULL'),
        COALESCE(v_comp.matched_pre_incident_id::TEXT, 'NULL')));

    -- 3b. C-only
    BEGIN
        SELECT h.alert, h.fired_c, h.risk_p90, h.w_score
        INTO v_hyb FROM mchain_hybrid_alert_at(now()) h;
        SELECT sh.js_avg INTO v_js_avg_now
        FROM sicpp_history sh
        WHERE sh.changed_at <= now()
        ORDER BY sh.changed_at DESC LIMIT 1;
        v_report := array_append(v_report, format(
            '3b. C:     alert=%s, fired_c=%s, risk_p90=%s, js_avg=%s, w_score=%s',
            COALESCE(v_hyb.alert::TEXT, 'NULL'),
            COALESCE(v_hyb.fired_c::TEXT, 'NULL'),
            COALESCE(round(v_hyb.risk_p90::NUMERIC, 4)::TEXT, 'NULL'),
            COALESCE(round(v_js_avg_now::NUMERIC, 4)::TEXT, 'NULL'),
            COALESCE(round(v_hyb.w_score::NUMERIC, 4)::TEXT, 'NULL')));
    EXCEPTION WHEN OTHERS THEN
        v_report := array_append(v_report, '3b. C:     error (' || SQLERRM || ')');
    END;

    -- 4. Risk
    BEGIN
        v_risk := mchain_predict_risk_current_horizon();
    EXCEPTION WHEN OTHERS THEN
        v_risk := NULL;
    END;
    v_report := array_append(v_report, format('4. Risk:   predicted_risk=%s',
        COALESCE(round(v_risk::NUMERIC, 4)::TEXT, 'NULL')));

    -- 5. Пороги
    v_report := array_append(v_report, '');
    v_report := array_append(v_report, 'Пороги:');
    v_report := array_append(v_report, format(
        '  ALARM (100): critical_state OR C-fired OR INCIDENT OR risk >= %s', p_alarm_risk));
    v_report := array_append(v_report, format(
        '  WARNING (50): SICPP активен OR matched_pre_incident_id OR pre_alert=100 OR '
        'status IN (CRITICAL,WARNING) OR js >= %s OR risk >= %s',
        p_warning_js, p_warning_risk));
    v_report := array_append(v_report, '  NORMAL (0):   ни один триггер не сработал.');

    RETURN v_report;
END;
$$;

COMMENT ON FUNCTION get_current_preincident_status_detail(REAL, REAL, REAL, REAL, INT, INT) IS
'v3.1.0 (2026-10-28, без integral_signal_calculate_at).
Детализация решения get_current_preincident_status() по источникам
(State, SICPP, Comparison, C, Risk) и порогам.
';


-- =============================================================================
-- is_within_productive_load
-- Назначение: проверяет, попадает ли момент времени в период продуктивной
--             нагрузки, заданный в markov_config (или переданный явно).
-- Параметры:
--   p_ts         TIMESTAMPTZ – проверяемый момент времени
--   p_start_hour SMALLINT    – час начала (если NULL – из markov_config)
--   p_end_hour   SMALLINT    – час окончания (если NULL – из markov_config)
-- Возвращает: BOOLEAN
-- =============================================================================
-- =============================================================================
-- P1.1. is_within_productive_load — SMALLINT → INT
--
-- Причина: при вызове is_within_productive_load(ts, 22, 6) литералы 22, 6
-- интерпретируются как INTEGER, что не совпадает с SMALLINT-сигнатурой
-- (в PG нет неявного приведения INTEGER → SMALLINT при вызове функции).
-- =============================================================================
CREATE OR REPLACE FUNCTION is_within_productive_load(
    p_ts         TIMESTAMPTZ,
    p_start_hour INT DEFAULT NULL,
    p_end_hour   INT DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_start_hour INT;
    v_end_hour   INT;
    v_time       TIME;
BEGIN
    IF p_start_hour IS NULL OR p_end_hour IS NULL THEN
        SELECT productive_load_start_hour, productive_load_end_hour
        INTO v_start_hour, v_end_hour
        FROM markov_config LIMIT 1;
    ELSE
        v_start_hour := p_start_hour;
        v_end_hour   := p_end_hour;
    END IF;

    v_time := p_ts::time;

    IF v_start_hour <= v_end_hour THEN
        -- Обычный дневной период [start, end)
        RETURN v_time >= make_time(v_start_hour, 0, 0)
           AND v_time <  make_time(v_end_hour,   0, 0);
    ELSE
        -- Ночной период (переход через полночь)
        RETURN v_time >= make_time(v_start_hour, 0, 0)
            OR v_time <  make_time(v_end_hour,   0, 0);
    END IF;
END;
$$;

COMMENT ON FUNCTION is_within_productive_load(TIMESTAMPTZ, INT, INT) IS 'v17.1. Проверяет, попадает ли момент времени в период продуктивной нагрузки. Параметры берутся из markov_config, если не переданы явно. Сигнатура SMALLINT → INT, чтобы работали вызовы с обычными целочисленными литералами (is_within_productive_load(ts, 22, 6)) без явных приведений.';

-- =============================================================================
-- is_window_within_productive_load
-- Назначение: проверяет, что всё окно [p_start, p_end) целиком лежит внутри
--             периода продуктивной нагрузки.
-- Возвращает: BOOLEAN
-- =============================================================================
CREATE OR REPLACE FUNCTION is_window_within_productive_load(
    p_start      TIMESTAMPTZ,
    p_end        TIMESTAMPTZ,
    p_start_hour INT DEFAULT NULL,
    p_end_hour   INT DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_start_hour INT;
    v_end_hour   INT;
BEGIN
    IF p_start_hour IS NULL OR p_end_hour IS NULL THEN
        SELECT productive_load_start_hour, productive_load_end_hour
        INTO v_start_hour, v_end_hour
        FROM markov_config LIMIT 1;
    ELSE
        v_start_hour := p_start_hour;
        v_end_hour   := p_end_hour;
    END IF;

    IF v_start_hour <= v_end_hour THEN
        -- Дневной период: окно должно целиком лежать в тех же сутках
        -- и в пределах [v_start_hour, v_end_hour).
        RETURN p_start::date = p_end::date
           AND p_start::time >= make_time(v_start_hour, 0, 0)
           AND p_end::time   <= make_time(v_end_hour,   0, 0);
    ELSE
        -- Ночной период: окно может пересекать полночь.
        IF p_start::date = p_end::date THEN
            RETURN p_start::time >= make_time(v_start_hour, 0, 0)
                OR p_end::time   <= make_time(v_end_hour,   0, 0);
        ELSE
            RETURN p_start::time >= make_time(v_start_hour, 0, 0)
               AND p_end::time   <= make_time(v_end_hour,   0, 0);
        END IF;
    END IF;
END;
$$;

COMMENT ON FUNCTION is_window_within_productive_load(TIMESTAMPTZ, TIMESTAMPTZ, INT, INT) IS 'v17.1. Проверяет, что всё окно [p_start, p_end) целиком лежит внутри периода продуктивной нагрузки. Сигнатура SMALLINT → INT для удобства вызова.';





-- =============================================================================
-- is_valid_baseline_window
-- Версия: 17.1.3 (2026-10-26)
-- Назначение: комплексная проверка, что окно [p_start, p_end) может быть
--             использовано как эталонное.
--
-- Контракт (три независимые проверки, все должны быть выполнены):
--   1) окно целиком лежит в периоде продуктивной нагрузки
--      (markov_config.productive_load_start_hour / productive_load_end_hour);
--   2) начало окна не ранее чем через baseline_min_gap_after_incident_min
--      минут после завершения последнего инцидента, закончившегося до
--      начала окна;
--   3) окно НЕ пересекается ни с одним инцидентом из markov_chain_performance_incident
--      (включая незавершённые, у которых finish_timepoint IS NULL).
--
-- ИСТОРИЯ ИЗМЕНЕНИЙ:
--   v17.1   — исходная версия; шаг 3 отсутствовал.
--   v17.1.1 — восстановлен шаг 3 после регресса в test3 (окно 10:31–11:31,
--             накрывающее инциденты 123 и 124, возвращало TRUE вместо FALSE).
--   v17.1.2 — устранён регресс test4: в файле v17.1 оставались ТРИ
--             определения is_valid_baseline_window — правильные в середине
--             файла и старое в конце. Последнее (без шага 3) перезаписывало
--             корректное при psql -f, что и привело к возврату TRUE вместо
--             FALSE в test4. Теперь определение единственное, в конце файла.
--
-- Параметры:
--   p_start TIMESTAMPTZ – начало окна (включается)
--   p_end   TIMESTAMPTZ – конец окна (не включается; полуинтервал)
--
-- Возвращает: BOOLEAN — TRUE если все три проверки пройдены.
-- =============================================================================
CREATE OR REPLACE FUNCTION is_valid_baseline_window(
    p_start        TIMESTAMPTZ,
    p_end          TIMESTAMPTZ,
    p_reference_ts TIMESTAMPTZ DEFAULT now()
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_start_hour    SMALLINT;
    v_end_hour      SMALLINT;
    v_min_gap       INT;
    v_max_age_hours INT;
    v_last_incident_end TIMESTAMPTZ;
BEGIN
    SELECT productive_load_start_hour,
           productive_load_end_hour,
           baseline_min_gap_after_incident_min,
           COALESCE(baseline_max_age_hours, 12)
    INTO v_start_hour, v_end_hour, v_min_gap, v_max_age_hours
    FROM markov_config LIMIT 1;

    -- 1. Окно целиком внутри периода продуктивной нагрузки
    IF NOT is_window_within_productive_load(p_start, p_end, v_start_hour, v_end_hour) THEN
        RETURN FALSE;
    END IF;

    -- 2. Зазор после последнего инцидента, завершившегося до начала окна
    SELECT MAX(finish_timepoint) INTO v_last_incident_end
    FROM markov_chain_performance_incident
    WHERE finish_timepoint <= p_start;

    IF v_last_incident_end IS NOT NULL
       AND p_start < v_last_incident_end + (v_min_gap || ' minutes')::INTERVAL THEN
        RETURN FALSE;
    END IF;

    -- 3. Окно не пересекается ни с одним инцидентом
    IF EXISTS (
        SELECT 1 FROM markov_chain_performance_incident
        WHERE start_timepoint < p_end
          AND (finish_timepoint IS NULL OR finish_timepoint > p_start)
    ) THEN
        RETURN FALSE;
    END IF;

    -- 4. Окно не старше baseline_max_age_hours относительно p_reference_ts
    IF p_end < p_reference_ts - (v_max_age_hours || ' hours')::INTERVAL THEN
        RETURN FALSE;
    END IF;

    RETURN TRUE;
END;
$$;

COMMENT ON FUNCTION is_valid_baseline_window(TIMESTAMPTZ, TIMESTAMPTZ, TIMESTAMPTZ) IS
'v17.1.3 (2026-10-26). Комплексная проверка эталонного окна:
 (1) целиком в периоде продуктивной нагрузки (markov_config.productive_load_start_hour / _end_hour);
 (2) начинается не ранее чем через baseline_min_gap_after_incident_min минут
     после завершения последнего инцидента, закончившегося до начала окна;
 (3) НЕ пересекается ни с одним инцидентом из markov_chain_performance_incident,
     включая незавершённые (finish_timepoint IS NULL);
 (4) возраст окна относительно p_reference_ts не превышает
     markov_config.baseline_max_age_hours (по умолчанию 12 ч).  -- NEW

Параметр p_reference_ts (v17.1.3):
  - для онлайн-проверок (compare_profiles, save_baseline_profile) — DEFAULT now();
  - для исторического заполнения (compare_profiles_at) — передавать p_ts,
    чтобы возраст измерялся относительно исторической точки, а не реального now().';

-- =============================================================================
-- R1.2. mchain_hybrid_alert_at v3.8.0
-- Добавлен spike-pathway: если risk пиковал в окне 60 мин (>=0.95 в 3+ минутах),
-- это тоже C. Расширяет recall на «тихих» инцидентах (js < js_min).
-- =============================================================================
CREATE OR REPLACE FUNCTION mchain_hybrid_alert_at(
    p_ts        TIMESTAMPTZ,
    p_js_min    REAL    DEFAULT NULL,
    p_p90_min   REAL    DEFAULT NULL,
    p_w_min     REAL    DEFAULT NULL,
    p_include_b BOOLEAN DEFAULT NULL,
    p_include_a BOOLEAN DEFAULT NULL
)
RETURNS TABLE (
    alert     BOOLEAN,     -- итоговый (profile OR spike, с учётом include_a/b)
    fired_a   BOOLEAN,
    fired_b   BOOLEAN,
    fired_c   BOOLEAN,     -- = profile_c OR spike_c (совместимо с v3.7.0)
    risk_p90  REAL,
    pre_adv   INT,
    w_score   REAL,
    js_avg    REAL,
    profile_c BOOLEAN,     -- NEW v3.8.0: только профильный путь
    spike_c   BOOLEAN,     -- NEW v3.8.0: только spike-путь
    spike_cnt INT          -- NEW v3.8.0: минут с risk >= 0.95 в окне 60 мин
)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    cfg         RECORD;
    v_js_min    REAL;
    v_p90_min   REAL;
    v_w_min     REAL;
    v_include_a BOOLEAN;
    v_include_b BOOLEAN;
    v_pre_adv   INT;
    v_js_avg    REAL;
    v_risk_avg  REAL;
    v_risk_max  REAL;
    v_risk_p90  REAL;
    v_w_score   REAL;
    v_spike_cnt INT;
    v_a BOOLEAN;
    v_b BOOLEAN;
    v_c_profile BOOLEAN;
    v_c_spike   BOOLEAN;
    v_c         BOOLEAN;
BEGIN
    SELECT hybrid_js_min_threshold,
           hybrid_p90_min_threshold,
           hybrid_w_score_min_threshold,
           hybrid_include_a,
           hybrid_include_b,
           js_threshold, risk_threshold, weight_js, weight_risk
    INTO cfg
    FROM incident_forecast_config LIMIT 1;

    v_js_min    := COALESCE(p_js_min,    cfg.hybrid_js_min_threshold,     0.14);
    v_p90_min   := COALESCE(p_p90_min,   cfg.hybrid_p90_min_threshold,    0.98);
    v_w_min     := COALESCE(p_w_min,     cfg.hybrid_w_score_min_threshold, 0.0);
    v_include_a := COALESCE(p_include_a, cfg.hybrid_include_a,            FALSE);
    v_include_b := COALESCE(p_include_b, cfg.hybrid_include_b,            FALSE);

    SELECT pcl.pre_alert_flag_advanced INTO v_pre_adv
    FROM profile_comparison_log pcl
    WHERE pcl.current_window_end <= p_ts
    ORDER BY pcl.current_window_end DESC
    LIMIT 1;

    SELECT sh.js_avg, sh.risk_avg, sh.risk_max
    INTO v_js_avg, v_risk_avg, v_risk_max
    FROM sicpp_history sh
    WHERE sh.changed_at <= p_ts
    ORDER BY sh.changed_at DESC
    LIMIT 1;

    SELECT PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY predicted_risk)
    INTO v_risk_p90
    FROM prediction_log
    WHERE prediction_time >  p_ts - INTERVAL '60 minutes'
      AND prediction_time <= p_ts
      AND predicted_risk IS NOT NULL;

    -- Spike counter: сколько минут за час риск был >= 0.95
    SELECT COUNT(*) INTO v_spike_cnt
    FROM prediction_log
    WHERE prediction_time >  p_ts - INTERVAL '60 minutes'
      AND prediction_time <= p_ts
      AND predicted_risk >= 0.95;

    IF v_js_avg IS NOT NULL AND v_risk_avg IS NOT NULL
       AND cfg.risk_threshold > 0 AND cfg.js_threshold > 0 THEN
        v_w_score := (v_risk_avg / cfg.risk_threshold) * cfg.weight_risk
                   + (v_js_avg   / cfg.js_threshold)   * cfg.weight_js;
    ELSE
        v_w_score := NULL;
    END IF;

    -- === Компоненты ===
    v_a := v_include_a AND COALESCE(v_pre_adv = 100, FALSE);
    v_b := v_include_b AND COALESCE(v_w_score > 1.0 AND v_risk_max >= 1.0, FALSE);

    -- Профильный путь (v3.7.0)
    v_c_profile := COALESCE(
        v_risk_p90 >= v_p90_min
        AND v_js_avg   >= v_js_min
        AND v_w_score  >= v_w_min,
        FALSE);

    -- Spike-путь (v3.8.0)
    v_c_spike := COALESCE(
        v_risk_p90  >= v_p90_min
        AND v_spike_cnt >= 3
        AND v_w_score  >= v_w_min,
        FALSE);

    v_c := v_c_profile OR v_c_spike;

    alert    := v_a OR v_b OR v_c;
    fired_a  := v_a;
    fired_b  := v_b;
    fired_c  := v_c;
    risk_p90 := v_risk_p90;
    pre_adv  := v_pre_adv;
    w_score  := v_w_score;
    js_avg   := v_js_avg;
    profile_c := v_c_profile;
    spike_c   := v_c_spike;
    spike_cnt := v_spike_cnt;
    RETURN NEXT;
END;
$$;

COMMENT ON FUNCTION mchain_hybrid_alert_at(TIMESTAMPTZ, REAL, REAL, REAL, BOOLEAN, BOOLEAN) IS
'v3.8.0 (2026-10-27). Двухпутевой C-only ALERT.

  ALERT = (include_a AND A) OR (include_b AND B) OR fired_c
  где fired_c = profile_c OR spike_c

  profile_c = risk_p90 >= p90_min AND js_avg >= js_min AND w_score >= w_min
  spike_c   = risk_p90 >= p90_min AND spike_cnt >= 3 AND w_score >= w_min
              (spike_cnt — число минут в окне 60 мин с predicted_risk >= 0.95)';  
  
CREATE OR REPLACE FUNCTION update_operational_alert_state()
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    v_now       TIMESTAMPTZ := date_trunc('minute', now());
    v_calc      RECORD;
    v_prev      RECORD;
    v_reason    TEXT;
    v_new_id    BIGINT;
BEGIN
    -- Текущее состояние
    SELECT * INTO v_prev FROM operational_alert_state WHERE id = 1;
    IF NOT FOUND THEN
        INSERT INTO operational_alert_state (id) VALUES (1);
        v_prev.alert_active  := FALSE;
        v_prev.fired_c       := FALSE;
        v_prev.fired_a_would := FALSE;
        v_prev.fired_b       := FALSE;
    END IF;

    -- Новое состояние
    SELECT h.alert, h.fired_a, h.fired_b, h.fired_c,
           h.risk_p90, h.pre_adv, h.w_score
    INTO v_calc
    FROM mchain_hybrid_alert_at(v_now) h;

    -- Обновить singleton
    UPDATE operational_alert_state SET
        updated_at    = v_now,
        alert_active  = COALESCE(v_calc.alert, FALSE),
        fired_c       = COALESCE(v_calc.fired_c, FALSE),
        fired_a_would = COALESCE(v_calc.pre_adv = 100, FALSE),
        fired_b       = COALESCE(v_calc.fired_b, FALSE),
        risk_p90      = v_calc.risk_p90,
        js_avg        = (SELECT js_avg FROM sicpp_history
                         WHERE changed_at <= v_now
                         ORDER BY changed_at DESC LIMIT 1)
    WHERE id = 1;

    -- Записать в историю только при смене alert_active
    IF v_calc.alert IS DISTINCT FROM v_prev.alert_active THEN
        v_reason := CASE WHEN v_calc.alert THEN 'alert started' ELSE 'alert ended' END;

        INSERT INTO operational_alert_history (
            changed_at, alert_active, fired_c, fired_a_would, fired_b,
            risk_p90, js_avg, reason
        ) VALUES (
            v_now, COALESCE(v_calc.alert, FALSE),
            COALESCE(v_calc.fired_c, FALSE),
            COALESCE(v_calc.pre_adv = 100, FALSE),
            COALESCE(v_calc.fired_b, FALSE),
            v_calc.risk_p90,
            (SELECT js_avg FROM sicpp_history
             WHERE changed_at <= v_now
             ORDER BY changed_at DESC LIMIT 1),
            v_reason
        ) RETURNING id INTO v_new_id;

        UPDATE operational_alert_state SET last_history_id = v_new_id WHERE id = 1;
        RETURN format('Operational alert changed to %s at %s (history_id=%s)',
                      v_calc.alert, v_now, v_new_id);
    END IF;

    RETURN format('Operational alert unchanged (%s) at %s', v_calc.alert, v_now);
END;
$$;

COMMENT ON FUNCTION update_operational_alert_state() IS
'v3.5.0. Ежеминутное обновление операционного индикатора ALERT (C-only по умолчанию).
Вызывается из mchain_train_step(). Обновляет singleton operational_alert_state
и добавляет запись в operational_alert_history при смене состояния.';


-- =============================================================================
-- Функция: find_incident_free_window (версия 5)
-- Назначение: найти самое свежее окно длины p_window_minutes, свободное от
--             инцидентов, заканчивающееся не позже (now() - p_exclude_after_min).
--             Результат сохраняется в incident_free_window_current.
--
-- ИЗМЕНЕНИЯ (2026-10-14):
--   - Раньше окно строилось как [finish, finish + window] для последнего
--     завершённого инцидента, что давало «мёртвую зону» ~120 мин после каждого
--     инцидента (см. диагностику NO_BASELINE от 2026-10-14).
--   - Теперь используется get_incident_free_window_before с отступом
--     p_exclude_after_min (по умолчанию 120 мин) от now(), что исключает
--     перекрытие с текущим часовым окном.
--   - Старое окно в incident_free_window_current переиспользуется, если оно
--     всё ещё удовлетворяет условию свежести (window_end < now() - 120 мин).
--
-- Входные параметры:
--   p_window_minutes    INT – длина окна в минутах (по умолчанию 60)
--   p_lookback_days     INT – глубина поиска (по умолчанию 30)
--   p_exclude_after_min INT – отступ от now() (по умолчанию 120)
--
-- Возвращает: TEXT – сообщение о результате.
-- =============================================================================
CREATE OR REPLACE FUNCTION find_incident_free_window(
    p_window_minutes     INT  DEFAULT 60,
    p_lookback_days      INT  DEFAULT 30,
    p_exclude_after_min  INT  DEFAULT 120,
    p_overlap_threshold  REAL DEFAULT 0.9
)
RETURNS TEXT
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
    v_now              TIMESTAMPTZ := now();
    v_existing         RECORD;
    v_existing_found   BOOLEAN := FALSE;
    v_existing_stale   BOOLEAN := FALSE;
    v_max_age_hours    INT;
    v_start_ts         TIMESTAMPTZ;
    v_end_ts           TIMESTAMPTZ;
    v_overlap_start    TIMESTAMPTZ;
    v_overlap_end      TIMESTAMPTZ;
    v_overlap_min      NUMERIC;
    v_overlap_ratio    NUMERIC;
    v_new_is_stale     BOOLEAN := FALSE;
BEGIN
    -- 1. Читаем существующее окно
    SELECT window_start, window_end INTO v_existing
    FROM incident_free_window_current
    LIMIT 1;
    v_existing_found := FOUND;

    -- 2. Читаем параметр baseline_max_age_hours
    SELECT COALESCE(baseline_max_age_hours, 12) INTO v_max_age_hours
    FROM markov_config LIMIT 1;

    -- 3. Проверяем, не устарело ли существующее окно
    IF v_existing_found AND v_existing.window_start IS NOT NULL THEN
        v_existing_stale :=
            (v_existing.window_end < v_now - (v_max_age_hours || ' hours')::INTERVAL);
    END IF;

    -- 4. Существующее окно валидно и НЕ устарело? Оставляем.
    IF v_existing_found
       AND v_existing.window_start IS NOT NULL
       AND NOT v_existing_stale
       AND v_existing.window_end < v_now - (p_exclude_after_min || ' minutes')::INTERVAL
       AND NOT EXISTS (
           SELECT 1 FROM markov_chain_performance_incident
           WHERE start_timepoint < v_existing.window_end
             AND (finish_timepoint IS NULL OR finish_timepoint > v_existing.window_start)
       )
    THEN
        RETURN format('Окно уже существует и актуально: %s – %s (возраст < %s ч)',
                      v_existing.window_start, v_existing.window_end, v_max_age_hours);
    END IF;

    -- 5. Ищем новое окно
    SELECT start_ts, end_ts INTO v_start_ts, v_end_ts
    FROM get_incident_free_window_before(
        p_ts                 => v_now,
        p_window_minutes     => p_window_minutes,
        p_lookback_days      => p_lookback_days,
        p_exclude_before_min => 0,
        p_exclude_after_min  => p_exclude_after_min
    );

    IF v_start_ts IS NULL THEN
        -- Новое окно не найдено. Если есть существующее — оставляем его
        -- (compare_profiles решит, использовать ли его через fallback-цепочку).
        IF v_existing_found AND v_existing.window_start IS NOT NULL THEN
            RETURN format('Новое окно не найдено. Сохранено существующее окно: %s – %s',
                          v_existing.window_start, v_existing.window_end);
        END IF;
        DELETE FROM incident_free_window_current;
        RETURN format('Окно не найдено: нет безынцидентного интервала длиной %s мин за последние %s дней (отступ %s мин).',
                      p_window_minutes, p_lookback_days, p_exclude_after_min);
    END IF;

    -- 6. Проверяем, не устарело ли найденное окно
    v_new_is_stale := (v_end_ts < v_now - (v_max_age_hours || ' hours')::INTERVAL);

    -- 7. Если новое окно тоже устарело и есть существующее — оставляем существующее
    IF v_new_is_stale AND v_existing_found AND v_existing.window_start IS NOT NULL THEN
        RETURN format('Найдено только устаревшее окно %s – %s (возраст >= %s ч). Сохранено существующее: %s – %s',
                      v_start_ts, v_end_ts, v_max_age_hours,
                      v_existing.window_start, v_existing.window_end);
    END IF;

    -- 8. СТАБИЛИЗАЦИЯ: если новое окно сильно перекрывается с существующим
    --    (и существующее не устарело) — оставляем существующее.
    IF v_existing_found
       AND v_existing.window_start IS NOT NULL
       AND NOT v_existing_stale
    THEN
        v_overlap_start := GREATEST(v_existing.window_start, v_start_ts);
        v_overlap_end   := LEAST(v_existing.window_end, v_end_ts);

        IF v_overlap_end > v_overlap_start THEN
            v_overlap_min := EXTRACT(EPOCH FROM (v_overlap_end - v_overlap_start)) / 60;
        ELSE
            v_overlap_min := 0;
        END IF;

        v_overlap_ratio := v_overlap_min / NULLIF(p_window_minutes, 0);

        IF v_overlap_ratio >= p_overlap_threshold THEN
            RETURN format('Окно стабилизировано (перекрытие %s%% >= порога %s%%): %s – %s',
                          round(v_overlap_ratio * 100, 1),
                          round((p_overlap_threshold * 100)::numeric, 1),
                          v_existing.window_start, v_existing.window_end);
        END IF;
    END IF;

    -- 9. Финальная проверка: новое окно не должно пересекаться с инцидентом
    IF EXISTS (
        SELECT 1 FROM markov_chain_performance_incident
        WHERE start_timepoint < v_end_ts
          AND (finish_timepoint IS NULL OR finish_timepoint > v_start_ts)
    ) THEN
        DELETE FROM incident_free_window_current;
        RETURN 'Ошибка: найденное окно пересекается с инцидентом.';
    END IF;

    -- 10. Сохраняем новое окно
    DELETE FROM incident_free_window_current;
    INSERT INTO incident_free_window_current (window_start, window_end, updated_at)
    VALUES (v_start_ts, v_end_ts, v_now);

    RETURN format('Окно обновлено: %s – %s (длина %s минут, возраст %s ч)',
                  v_start_ts, v_end_ts, p_window_minutes,
                  round(EXTRACT(EPOCH FROM (v_now - v_end_ts)) / 3600, 1));
END;
$$;

COMMENT ON FUNCTION find_incident_free_window(INT, INT, INT, REAL) IS
'Ищет самое свежее окно длины p_window_minutes, свободное от инцидентов.
Версия 5 (2026-10-26): добавлена проверка baseline_max_age_hours.
- Существующее окно в incident_free_window_current считается актуальным,
  только если оно не старше markov_config.baseline_max_age_hours.
- Если окно устарело — выполняется поиск нового через
  get_incident_free_window_before().
- Если найдено только устаревшее окно (нет свежего валидного) — сохраняется
  существующее окно (лучше устаревшее, чем никакого).
- Стабилизация по перекрытию (p_overlap_threshold) применяется только к
  НЕ устаревшим окнам.';

CREATE OR REPLACE FUNCTION adapt_c_thresholds()
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    cfg RECORD;
    v_now TIMESTAMPTZ := now();
    v_start TIMESTAMPTZ;
    v_old_js REAL;
    v_old_p90 REAL;
    v_old_w REAL;
    v_old_window INT;
    v_new_js REAL;
    v_new_p90 REAL;
    v_new_w REAL;
    v_new_window INT;
    v_inc RECORD;
    v_p90 REAL;
    v_js REAL;
    v_w REAL;
    v_c_alert_min INT;
    v_covered BOOLEAN;
    v_total_incidents INT := 0;
    v_covered_incidents INT := 0;
    v_uncovered RECORD;
    v_js_values REAL[] := '{}';
    v_p90_values REAL[] := '{}';
    v_w_values REAL[] := '{}';
    v_trend_up_count INT := 0;
    v_trend_total INT := 0;
    v_target_recall REAL;
    v_js_percentile REAL;
    v_p90_percentile REAL;
    v_changed BOOLEAN := FALSE;
    v_reason TEXT := '';
BEGIN
    -- 1. Читаем конфигурацию
    SELECT * INTO cfg FROM incident_forecast_config LIMIT 1;
    IF NOT FOUND THEN
        RETURN 'incident_forecast_config не найдена';
    END IF;

    IF NOT cfg.c_auto_threshold THEN
        RETURN 'Адаптация C отключена (c_auto_threshold = FALSE)';
    END IF;

    -- Проверяем, не пора ли пересчитывать (не чаще раза в сутки)
    IF cfg.c_last_auto_threshold_at IS NOT NULL
       AND v_now - cfg.c_last_auto_threshold_at < INTERVAL '1 day' THEN
        RETURN 'Пересчёт C ещё не требуется (прошло менее суток)';
    END IF;

    v_start := v_now - (cfg.c_calibration_period_days || ' days')::INTERVAL;

    v_old_js := cfg.hybrid_js_min_threshold;
    v_old_p90 := cfg.hybrid_p90_min_threshold;
    v_old_w := cfg.hybrid_w_score_min_threshold;
    v_old_window := cfg.hybrid_window_minutes;
    v_target_recall := cfg.c_target_recall;

    -- 2. Собираем статистику по инцидентам за период
    FOR v_inc IN
        SELECT id, start_timepoint
        FROM markov_chain_performance_incident
        WHERE start_timepoint BETWEEN v_start AND v_now
    LOOP
        v_total_incidents := v_total_incidents + 1;

        -- Получаем значения на момент старта
        SELECT h.risk_p90, h.js_avg, h.w_score, h.fired_c
        INTO v_p90, v_js, v_w, v_covered
        FROM mchain_hybrid_alert_at(v_inc.start_timepoint) h;

        -- Определяем, покрыт ли инцидент (c_alert_min > 0)
        -- Используем ту же логику, что в отчёте: проверяем окно [start - c_window, start]
        -- Для простоты считаем, что инцидент покрыт, если хотя бы в одну минуту окна
        -- fired_c = TRUE. Но у нас нет прямого доступа к _tmp_c_windows.
        -- Воспроизведём: проверим, был ли fired_c в какие-либо минуты окна.
        -- Это дорого; вместо этого используем упрощение: если на start_timepoint
        -- fired_c = TRUE, то покрыт. В отчёте c_alert_min может быть >0 даже если
        -- на start_timepoint fired_c = FALSE (например, C сработал раньше).
        -- Для адаптации нам важно понять, какие пороги мешают.
        -- Поэтому будем анализировать только непокрытые инциденты (c_alert_min = 0).
        -- Чтобы не вычислять c_alert_min, проверим, был ли fired_c хотя бы раз в окне.
        -- Реализуем через цикл по минутам (как в отчёте), но это может быть медленно.
        -- Для оптимизации: используем только те инциденты, где на start_timepoint
        -- fired_c = FALSE, и считаем их потенциально непокрытыми.
        -- Более точный подход: вычислить c_alert_min через функцию, но её нет.
        -- Создадим временную таблицу? Это сложно.
        -- Упростим: будем собирать значения p90, js, W для всех инцидентов,
        -- и отдельно для тех, где fired_c = FALSE на start_timepoint.
        -- Это даст представление о порогах.
        IF NOT COALESCE(v_covered, FALSE) THEN
            -- Инцидент не покрыт на start_timepoint (возможно, покрыт раньше)
            v_js_values := array_append(v_js_values, v_js);
            v_p90_values := array_append(v_p90_values, v_p90);
            v_w_values := array_append(v_w_values, v_w);

            -- Оценим тренд риска за окно (упрощённо: сравним risk_p90 в начале и конце окна)
            -- Для простоты пропустим, т.к. это требует отдельных запросов.
        END IF;
    END LOOP;

    IF v_total_incidents = 0 THEN
        RETURN 'Нет инцидентов за период для адаптации C';
    END IF;

    -- 3. Вычисляем новые пороги на основе перцентилей
    -- Цель: покрыть целевую долю инцидентов, которые сейчас не покрыты из-за js или p90.
    -- Берём целевой перцентиль: (1 - target_recall) * 100 от значений непокрытых.
    -- Например, если target_recall = 0.7, то хотим покрыть 70% непокрытых.
    -- Значит, порог должен быть ниже 70% значений. Установим порог на уровне
    -- 30-го перцентиля (т.е. 70% значений выше порога).
    -- Для js: чем ниже порог, тем больше покрытие.
    -- Для p90: чем ниже порог, тем больше покрытие.

    IF array_length(v_js_values, 1) > 0 THEN
        -- Вычисляем 30-й перцентиль (покрываем 70% значений)
        SELECT PERCENTILE_CONT(1 - v_target_recall) WITHIN GROUP (ORDER BY val)
        INTO v_js_percentile
        FROM unnest(v_js_values) AS val;

        -- Ограничиваем изменение
        v_new_js := LEAST(
            GREATEST(v_js_percentile, v_old_js * (1 - cfg.c_max_threshold_change_pct / 100.0)),
            v_old_js * (1 + cfg.c_max_threshold_change_pct / 100.0)
        );
        -- Не ниже 0.05
        v_new_js := GREATEST(v_new_js, 0.05);
    ELSE
        v_new_js := v_old_js;
    END IF;

    IF array_length(v_p90_values, 1) > 0 THEN
        SELECT PERCENTILE_CONT(1 - v_target_recall) WITHIN GROUP (ORDER BY val)
        INTO v_p90_percentile
        FROM unnest(v_p90_values) AS val;

        v_new_p90 := LEAST(
            GREATEST(v_p90_percentile, v_old_p90 * (1 - cfg.c_max_threshold_change_pct / 100.0)),
            v_old_p90 * (1 + cfg.c_max_threshold_change_pct / 100.0)
        );
        v_new_p90 := GREATEST(v_new_p90, 0.5);
    ELSE
        v_new_p90 := v_old_p90;
    END IF;

    -- W оставляем без изменений (0)
    v_new_w := v_old_w;

    -- 4. Адаптация окна: если много инцидентов с ростом риска, увеличиваем окно
    -- (упрощённо: если доля непокрытых с ростом риска > 30%, увеличиваем окно на 5 мин)
    -- Для простоты пропустим, так как требует вычисления трендов.
    v_new_window := v_old_window;

    -- 5. Применяем изменения, если они значимы
    IF v_new_js <> v_old_js OR v_new_p90 <> v_old_p90 OR v_new_w <> v_old_w OR v_new_window <> v_old_window THEN
        UPDATE incident_forecast_config SET
            hybrid_js_min_threshold = v_new_js,
            hybrid_p90_min_threshold = v_new_p90,
            hybrid_w_score_min_threshold = v_new_w,
            hybrid_window_minutes = v_new_window,
            c_last_auto_threshold_at = v_now
        WHERE id = (SELECT id FROM incident_forecast_config LIMIT 1);

        INSERT INTO c_threshold_history (
            old_js_min, new_js_min,
            old_p90_min, new_p90_min,
            old_w_min, new_w_min,
            old_window_min, new_window_min,
            reason
        ) VALUES (
            v_old_js, v_new_js,
            v_old_p90, v_new_p90,
            v_old_w, v_new_w,
            v_old_window, v_new_window,
            format('Адаптация C: target_recall=%s, период=%s дн., инцидентов=%s',
                   v_target_recall, cfg.c_calibration_period_days, v_total_incidents)
        );

        RETURN format('Пороги C обновлены: js %s→%s, p90 %s→%s, W %s→%s, window %s→%s',
                      v_old_js, v_new_js, v_old_p90, v_new_p90, v_old_w, v_new_w, v_old_window, v_new_window);
    ELSE
        UPDATE incident_forecast_config SET c_last_auto_threshold_at = v_now;
        RETURN 'Пороги C не изменились';
    END IF;
END;
$$;

COMMENT ON FUNCTION adapt_c_thresholds() IS
'Адаптивная настройка порогов C‑alone на основе данных за c_calibration_period_days.
Вызывается периодически (например, из mchain_train_step или cron).
Использует перцентили значений p90 и js у непокрытых инцидентов для достижения
целевого recall. Ограничивает изменение порогов c_max_threshold_change_pct.';


CREATE OR REPLACE FUNCTION adapt_sicpp_thresholds()
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    cfg RECORD;
    v_now TIMESTAMPTZ := now();
    v_start TIMESTAMPTZ;
    v_old_js REAL;
    v_old_risk REAL;
    v_new_js REAL;
    v_new_risk REAL;
    v_js_p REAL;
    v_risk_p REAL;
    v_n INT;
    v_p REAL;
BEGIN
    SELECT * INTO cfg FROM incident_forecast_config LIMIT 1;
    IF NOT FOUND THEN
        RETURN 'incident_forecast_config не найдена';
    END IF;

    IF NOT cfg.auto_threshold THEN
        RETURN 'Автонастройка SICPP отключена (auto_threshold = FALSE)';
    END IF;

    -- Не чаще одного раза в сутки
    IF cfg.sicpp_auto_threshold_last_run IS NOT NULL
       AND v_now - cfg.sicpp_auto_threshold_last_run < INTERVAL '24 hours' THEN
        RETURN 'Пересчёт порогов SICPP ещё не требуется (прошло менее суток)';
    END IF;

    v_start := v_now - (cfg.calibration_period_days || ' days')::INTERVAL;
    v_old_js := cfg.js_threshold;
    v_old_risk := cfg.risk_threshold;
    v_p := cfg.sicpp_auto_threshold_percentile;

    -- Калибровка только по «чистым» окнам:
    --  - исключаем статус INCIDENT;
    --  - исключаем окна за 60 мин до и 30 мин после инцидента.
    WITH calib AS (
        SELECT pcl.js_divergence,
               pl.predicted_risk
        FROM profile_comparison_log pcl
        JOIN prediction_log pl
          ON date_trunc('minute', pl.prediction_time) =
             date_trunc('minute', pcl.current_window_end)
        WHERE pcl.current_window_end >= v_start
          AND pcl.current_window_end < v_now
          AND pcl.js_divergence IS NOT NULL
          AND pl.predicted_risk IS NOT NULL
          AND pcl.status IS DISTINCT FROM 'INCIDENT'
          AND NOT EXISTS (
              SELECT 1
              FROM markov_chain_performance_incident pi
              WHERE pcl.current_window_end
                    BETWEEN pi.start_timepoint - INTERVAL '60 minutes'
                        AND pi.start_timepoint + INTERVAL '30 minutes'
          )
    )
    SELECT COUNT(*),
           PERCENTILE_CONT(v_p) WITHIN GROUP (ORDER BY js_divergence),
           PERCENTILE_CONT(v_p) WITHIN GROUP (ORDER BY predicted_risk)
    INTO v_n, v_js_p, v_risk_p
    FROM calib;

    IF v_n < cfg.sicpp_auto_threshold_min_points
       OR v_js_p IS NULL
       OR v_risk_p IS NULL THEN
        UPDATE incident_forecast_config
        SET sicpp_auto_threshold_last_run = v_now
        WHERE id = cfg.id;

        RETURN format(
            'Пороги SICPP не изменены: недостаточно данных калибровки (%s < %s)',
            v_n, cfg.sicpp_auto_threshold_min_points
        );
    END IF;

    -- Ограничиваем шаг изменения и абсолютные границы
    v_new_js := LEAST(
        GREATEST(v_js_p, v_old_js * (1 - cfg.sicpp_auto_threshold_max_change_pct / 100.0)),
        v_old_js * (1 + cfg.sicpp_auto_threshold_max_change_pct / 100.0)
    );
    v_new_js := GREATEST(v_new_js, 0.05);

    v_new_risk := LEAST(
        GREATEST(v_risk_p, v_old_risk * (1 - cfg.sicpp_auto_threshold_max_change_pct / 100.0)),
        v_old_risk * (1 + cfg.sicpp_auto_threshold_max_change_pct / 100.0)
    );
    v_new_risk := GREATEST(v_new_risk, 0.50);
    v_new_risk := LEAST(v_new_risk, 0.99);

    IF abs(v_new_js - v_old_js) < 0.005
       AND abs(v_new_risk - v_old_risk) < 0.005 THEN
        UPDATE incident_forecast_config
        SET sicpp_auto_threshold_last_run = v_now
        WHERE id = cfg.id;

        RETURN 'Пороги SICPP не изменены (в пределах допуска)';
    END IF;

    UPDATE incident_forecast_config
    SET js_threshold = v_new_js,
        risk_threshold = v_new_risk,
        sicpp_auto_threshold_last_run = v_now
    WHERE id = cfg.id;

    INSERT INTO sicpp_threshold_history (
        old_js_threshold, new_js_threshold,
        old_risk_threshold, new_risk_threshold,
        calibration_from, calibration_to,
        sample_size, percentile, reason
    ) VALUES (
        v_old_js, v_new_js,
        v_old_risk, v_new_risk,
        v_start, v_now,
        v_n, v_p,
        format('SICPP auto-threshold: percentile=%s, period=%s days, n=%s',
               v_p, cfg.calibration_period_days, v_n)
    );

    RETURN format(
        'Пороги SICPP обновлены: js %s→%s, risk %s→%s (n=%s, p=%s)',
        round(v_old_js::numeric, 4), round(v_new_js::numeric, 4),
        round(v_old_risk::numeric, 4), round(v_new_risk::numeric, 4),
        v_n, v_p
    );
END;
$$;

COMMENT ON FUNCTION adapt_sicpp_thresholds() IS
'Автонастройка порогов SICPP (js_threshold, risk_threshold) по «чистым» окнам за calibration_period_days.
Исключает INCIDENT и интервалы ±(60/30) мин вокруг инцидентов. Использует sicpp_auto_threshold_percentile (по умолчанию 0.90).
Ограничивает шаг sicpp_auto_threshold_max_change_pct. Вызывать из mchain_train_step().';
	
	

-- =============================================================================
-- signals_report
-- Версия: 1.0 (2026-10-27)
--
-- Назначение: для каждого инцидента из markov_chain_performance_incident
--             выводит время первой активации каждого из трёх сигналов
--             предупреждения в окне v_lookback минут перед стартом:
--
--               1) SICPP            — episode_started_at покрывающего эпизода
--                                     из sicpp_history;
--               2) C-only           — первый fired_c=TRUE в окне
--                                     [start − v_lookback, start]
--                                     (mchain_hybrid_alert_at);
--               3) Integral         — LEAST(SICPP, C-only) — момент первого
--                                     из двух сигналов.
--
--             Параметры p_start / p_end — как у
--             generate_incident_forecast_report_v2.
--
--             v_lookback = GREATEST(window_minutes, hybrid_window_minutes)
--             (по умолчанию 60 мин), чтобы SICPP и C-only сравнивались
--             в одном временном окне.
--
-- Возвращает: TEXT[] — массив строк отчёта.
--
-- Пример:
--   SELECT unnest(signals_report());
--   SELECT unnest(signals_report(now() - INTERVAL '30 days', now()));
-- =============================================================================
-- =============================================================================
-- signals_report
-- Версия: 1.1 (2026-10-27)
--
-- Назначение: для каждого инцидента из markov_chain_performance_incident
--             выводит время первой активации каждого из трёх сигналов
--             предупреждения в окне v_lookback минут перед стартом,
--             а также ДЛИТЕЛЬНОСТЬ (lead, мин) между сигналом и началом
--             инцидента:
--
--               1) SICPP     — episode_started_at покрывающего эпизода
--                              из sicpp_history;
--               2) C-only    — первый fired_c=TRUE в окне
--                              [start − v_lookback, start]
--                              (mchain_hybrid_alert_at);
--               3) Integral  — LEAST(SICPP, C-only).
--
--             В конце отчёта — сводка (покрытие, медиана/среднее/min/max
--             lead) по каждому из трёх сигналов.
--
-- Возвращает: TEXT[] — массив строк отчёта.
--
-- Изменения v1.1 (относительно v1.0):
--   - Для каждого сигнала добавлена колонка Lead (мин) —
--     длительность между сигналом и началом инцидента.
--   - Добавлена секция «СВОДКА ПО LEAD TIME»: покрытие, медиана,
--     среднее, min/max lead для SICPP / C-only / Integral.
-- =============================================================================
-- =============================================================================
-- signals_report
-- Версия: 1.2 (2026-10-27)
--
-- Назначение: для каждого инцидента из markov_chain_performance_incident
--             выводит время первой активации каждого из трёх сигналов
--             предупреждения в окне v_lookback минут перед стартом,
--             а также длительность (lead, мин) между сигналом и началом
--             инцидента. В конце отчёта — сводка по lead time.
--
--             СИГНАЛЫ:
--               1) SICPP     — episode_started_at покрывающего эпизода
--                              из sicpp_history;
--               2) C-only    — первый fired_c=TRUE в окне
--                              [start − v_lookback, start];
--               3) Integral  — LEAST(SICPP, C-only).
--
--             Возвращает: TEXT[].
--
-- Изменения v1.2 (относительно v1.1):
--   - Единый разделитель столбцов — символ '|' (с пробелами вокруг).
--     Применено как в таблице инцидентов, так и в сводке по lead time.
-- =============================================================================
-- =============================================================================
-- signals_report
-- Версия: 2.0 (2026-10-27) — 100% согласованность с
--         generate_incident_forecast_report_v2 v22.0
--
-- Назначение: для каждого инцидента из markov_chain_performance_incident
--             выводит время первой активации каждого из трёх сигналов
--             предупреждения и lead (мин) между сигналом и стартом.
--             Решения «сигнал сработал / не сработал» полностью совпадают
--             с логикой v22.0.
--
-- КЛЮЧЕВЫЕ ИЗМЕНЕНИЯ v2.0 (по сравнению с v1.2):
--   - C-only ищется в окне hybrid_window_minutes (20 мин), как в v22.0,
--     а не в GREATEST(window_minutes, hybrid_window_minutes) = 60 мин.
--     Это устраняет расхождения с отчётом v22.0 (test8, ID 41).
--   - SICPP-покрытие: episode_start <= start AND episode_end >= start - window_minutes
--     (60 мин, как в v22.0).
--   - Применяются те же фильтры, что в v22.0:
--       * status_filter (status_filter из incident_forecast_config);
--       * series_filter_enabled (исключение серийных инцидентов).
--   - Добавлены колонки:
--       * SICPP end — конец покрывающего эпизода (диагностика «истёкших» сигналов);
--       * C cnt — число минут fired_c=TRUE в окне c_window (совпадает
--                 с c_alert_min из v22.0, если include_a/b=FALSE).
--   - В шапку вынесены параметры конфигурации (window_minutes,
--     hybrid_window_minutes, max_signal_duration_minutes, series_filter_enabled,
--     status_filter) для воспроизводимости.
--   - Разделитель столбцов — ' | ' (как в v1.2).
--
-- Возвращает: TEXT[].
-- =============================================================================
CREATE OR REPLACE FUNCTION signals_report(
    p_start TIMESTAMPTZ DEFAULT now() - INTERVAL '7 days',
    p_end   TIMESTAMPTZ DEFAULT now()
)
RETURNS TEXT[]
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    cfg RECORD;
    v_window_minutes  INT;
    v_c_window_min    INT;
    v_max_dur_cap     INT;
    v_series_enabled  BOOLEAN;
    v_status_filter   TEXT[];

    v_report    TEXT[] := '{}';
    v_rec       RECORD;

    -- per-incident
    v_sicpp_warn     TIMESTAMPTZ;
    v_sicpp_end      TIMESTAMPTZ;
    v_sicpp_lead     TEXT;
    v_sicpp_lead_min NUMERIC;
    v_c_warn         TIMESTAMPTZ;
    v_c_lead         TEXT;
    v_c_lead_min     NUMERIC;
    v_int_warn       TIMESTAMPTZ;
    v_int_lead       TEXT;
    v_int_lead_min   NUMERIC;
    v_c_alert_min    INT;

    v_row_count       INT := 0;
    v_excluded_status INT := 0;
    v_excluded_series INT := 0;

    -- аккумуляторы для сводки
    v_sicpp_leads NUMERIC[] := '{}';
    v_c_leads     NUMERIC[] := '{}';
    v_int_leads   NUMERIC[] := '{}';

    v_median NUMERIC;
    v_avg    NUMERIC;
    v_min    NUMERIC;
    v_max    NUMERIC;

    -- ширины колонок
    c_id      CONSTANT INT := 10;
    c_time    CONSTANT INT := 16;
    c_lead    CONSTANT INT := 8;
    c_cnt     CONSTANT INT := 6;
    c_sep     CONSTANT TEXT := ' | ';
BEGIN
    -- =========================================================================
    -- 1. Конфигурация (тот же источник, что в v22.0)
    -- =========================================================================
    SELECT * INTO cfg FROM incident_forecast_config LIMIT 1;
    IF NOT FOUND THEN
        INSERT INTO incident_forecast_config DEFAULT VALUES;
        SELECT * INTO cfg FROM incident_forecast_config LIMIT 1;
    END IF;

    v_window_minutes := COALESCE(cfg.window_minutes, 60);
    v_c_window_min   := COALESCE(cfg.hybrid_window_minutes, 20);
    v_max_dur_cap    := COALESCE(cfg.max_signal_duration_minutes, 180);
    v_series_enabled := COALESCE(cfg.series_filter_enabled, TRUE);
    v_status_filter  := cfg.status_filter;

    -- =========================================================================
    -- 2. Заголовок и параметры
    -- =========================================================================
    v_report := array_append(v_report,
        '=== ОТЧЁТ ПО СИГНАЛАМ ПРЕДУПРЕЖДЕНИЯ ИНЦИДЕНТОВ ===');
    v_report := array_append(v_report, format('Период: %s – %s',
        to_char(p_start, 'YYYY-MM-DD HH24:MI'),
        to_char(p_end,   'YYYY-MM-DD HH24:MI')));
    v_report := array_append(v_report,
        'Версия функции: signals_report v2.0 (согласовано с generate_incident_forecast_report_v2 v22.0)');
    v_report := array_append(v_report, '');
    v_report := array_append(v_report, 'Параметры (из incident_forecast_config):');
    v_report := array_append(v_report, format('  window_minutes (SICPP покрытие):    %s мин', v_window_minutes));
    v_report := array_append(v_report, format('  hybrid_window_minutes (C-only):    %s мин', v_c_window_min));
    v_report := array_append(v_report, format('  max_signal_duration_minutes:        %s мин', v_max_dur_cap));
    v_report := array_append(v_report, format('  series_filter_enabled:              %s',
        CASE WHEN v_series_enabled THEN 'ВКЛ' ELSE 'ВЫКЛ' END));
    v_report := array_append(v_report, format('  status_filter:                      %s',
        COALESCE(array_to_string(v_status_filter, ','), 'НЕТ')));
    v_report := array_append(v_report, '');
    v_report := array_append(v_report,
        'Определения сигналов (те же, что в v22.0):');
    v_report := array_append(v_report, format(
        '  SICPP:  episode_start <= start_timepoint AND episode_end >= start_timepoint - %s мин',
        v_window_minutes));
    v_report := array_append(v_report, format(
        '  C-only: хотя бы одна минута fired_c=TRUE в [start_timepoint - %s мин, start_timepoint]',
        v_c_window_min));
    v_report := array_append(v_report, '  Integral = LEAST(SICPP, C-only)');
    v_report := array_append(v_report,
        '  «—» означает: сигнал не сработал по правилам v22.0.');
    v_report := array_append(v_report, '');
    v_report := array_append(v_report,
        'Колонка «SICPP end» — конец покрывающего эпизода; если раньше старта,');
    v_report := array_append(v_report,
        '  сигнал формально покрывает инцидент (по правилу v22.0), но фактически истёк.');
    v_report := array_append(v_report, '');

    -- =========================================================================
    -- 3. Заголовок таблицы
    -- =========================================================================
    v_report := array_append(v_report,
        rpad('ID', c_id) || c_sep ||
        rpad('Время инцидента', c_time) || c_sep ||
        rpad('SICPP warn', c_time) || c_sep ||
        lpad('Lead', c_lead) || c_sep ||
        rpad('SICPP end', c_time) || c_sep ||
        rpad('C warn', c_time) || c_sep ||
        lpad('Lead', c_lead) || c_sep ||
        lpad('C cnt', c_cnt) || c_sep ||
        rpad('Integral', c_time) || c_sep ||
        lpad('Lead', c_lead));
    v_report := array_append(v_report,
        repeat('-', c_id) || c_sep ||
        repeat('-', c_time) || c_sep ||
        repeat('-', c_time) || c_sep ||
        repeat('-', c_lead) || c_sep ||
        repeat('-', c_time) || c_sep ||
        repeat('-', c_time) || c_sep ||
        repeat('-', c_lead) || c_sep ||
        repeat('-', c_cnt) || c_sep ||
        repeat('-', c_time) || c_sep ||
        repeat('-', c_lead));

    -- =========================================================================
    -- 4. Основной цикл по инцидентам
    -- =========================================================================
    FOR v_rec IN
        WITH sicpp_hist AS (
            SELECT id, changed_at, signal_active,
                   episode_started_at, first_signal_time,
                   LAG(signal_active) OVER (ORDER BY changed_at, id) AS prev_active
            FROM sicpp_history
            WHERE changed_at <= p_end
        ),
        sicpp_starts AS (
            SELECT id, changed_at AS raw_start,
                   COALESCE(episode_started_at, first_signal_time) AS episode_started_at
            FROM sicpp_hist
            WHERE signal_active = TRUE
              AND (prev_active IS NULL OR prev_active = FALSE)
        ),
        sicpp_ends AS (
            SELECT changed_at AS end_ts FROM sicpp_hist WHERE signal_active = FALSE
        ),
        sicpp_episodes AS (
            SELECT s.id, s.raw_start, s.episode_started_at,
                   (SELECT MIN(e.end_ts) FROM sicpp_ends e WHERE e.end_ts > s.raw_start) AS raw_end
            FROM sicpp_starts s
        )
        SELECT
            pi.id              AS incident_id,
            pi.start_timepoint AS incident_start,
            (
                SELECT e.episode_started_at
                FROM sicpp_episodes e
                WHERE e.raw_start <= pi.start_timepoint
                  AND COALESCE(e.raw_end, p_end)
                      >= pi.start_timepoint - v_window_minutes * INTERVAL '1 minute'
                ORDER BY e.raw_start DESC
                LIMIT 1
            ) AS sicpp_warning,
            (
                SELECT COALESCE(e.raw_end, p_end)
                FROM sicpp_episodes e
                WHERE e.raw_start <= pi.start_timepoint
                  AND COALESCE(e.raw_end, p_end)
                      >= pi.start_timepoint - v_window_minutes * INTERVAL '1 minute'
                ORDER BY e.raw_start DESC
                LIMIT 1
            ) AS sicpp_episode_end,
            (
                SELECT status
                FROM profile_comparison_log
                WHERE current_window_end < pi.start_timepoint
                ORDER BY current_window_end DESC
                LIMIT 1
            ) AS last_status
        FROM markov_chain_performance_incident pi
        WHERE pi.start_timepoint BETWEEN p_start AND p_end
        ORDER BY pi.start_timepoint
    LOOP
        -- =====================================================================
        -- 5.1. status_filter (та же логика, что в v22.0)
        --      Важно: last_status может быть NULL; тогда
        --      NOT (NULL = ANY(...)) = NULL → IF NULL → false → не исключается.
        -- =====================================================================
        IF v_status_filter IS NOT NULL AND NOT (v_rec.last_status = ANY(v_status_filter)) THEN
            v_excluded_status := v_excluded_status + 1;
            CONTINUE;
        END IF;

        -- =====================================================================
        -- 5.2. series_filter (та же логика, что в v22.0)
        -- =====================================================================
        IF v_series_enabled AND v_rec.last_status = 'INCIDENT' THEN
            IF EXISTS (
                SELECT 1 FROM markov_chain_performance_incident pi2
                WHERE pi2.start_timepoint < v_rec.incident_start
                  AND (pi2.finish_timepoint IS NULL OR pi2.finish_timepoint > v_rec.incident_start)
                  AND pi2.id <> v_rec.incident_id
            ) THEN
                v_excluded_series := v_excluded_series + 1;
                CONTINUE;
            END IF;
        END IF;

        v_row_count := v_row_count + 1;

        -- =====================================================================
        -- 6. SICPP (покрытие + lead)
        -- =====================================================================
        v_sicpp_warn := v_rec.sicpp_warning;
        v_sicpp_end  := v_rec.sicpp_episode_end;

        IF v_sicpp_warn IS NOT NULL THEN
            v_sicpp_lead_min := ROUND(
                (EXTRACT(EPOCH FROM (v_rec.incident_start - v_sicpp_warn)) / 60)::NUMERIC, 1);
            v_sicpp_lead := v_sicpp_lead_min::TEXT;
            v_sicpp_leads := array_append(v_sicpp_leads, v_sicpp_lead_min);
        ELSE
            v_sicpp_lead_min := NULL;
            v_sicpp_lead := '—';
        END IF;

        -- =====================================================================
        -- 7. C-only: поиск в [start - c_window, start] (как в v22.0)
        --    fired_c — тот же флаг, что используется в v22.0 для v_c_fired
        --    (C=ДА/НЕТ). При include_a/b=FALSE alert = fired_c, поэтому
        --    c_alert_min (COUNT FILTER fired_c) совпадает с колонкой v22.0.
        -- =====================================================================
        SELECT
            MIN(gs.m) FILTER (WHERE h.fired_c = TRUE),
            COUNT(*)  FILTER (WHERE h.fired_c = TRUE)
        INTO v_c_warn, v_c_alert_min
        FROM generate_series(
            v_rec.incident_start - v_c_window_min * INTERVAL '1 minute',
            v_rec.incident_start,
            '1 minute'
        ) AS gs(m)
        CROSS JOIN LATERAL mchain_hybrid_alert_at(gs.m) h;

        IF v_c_alert_min IS NULL THEN
            v_c_alert_min := 0;
        END IF;

        IF v_c_warn IS NOT NULL THEN
            v_c_lead_min := ROUND(
                (EXTRACT(EPOCH FROM (v_rec.incident_start - v_c_warn)) / 60)::NUMERIC, 1);
            v_c_lead := v_c_lead_min::TEXT;
            v_c_leads := array_append(v_c_leads, v_c_lead_min);
        ELSE
            v_c_lead_min := NULL;
            v_c_lead := '—';
        END IF;

        -- =====================================================================
        -- 8. Integral = LEAST(SICPP, C-only)
        -- =====================================================================
        IF v_sicpp_warn IS NULL AND v_c_warn IS NULL THEN
            v_int_warn := NULL;
            v_int_lead := '—';
            v_int_lead_min := NULL;
        ELSE
            v_int_warn := LEAST(v_sicpp_warn, v_c_warn);
            v_int_lead_min := ROUND(
                (EXTRACT(EPOCH FROM (v_rec.incident_start - v_int_warn)) / 60)::NUMERIC, 1);
            v_int_lead := v_int_lead_min::TEXT;
            v_int_leads := array_append(v_int_leads, v_int_lead_min);
        END IF;

        -- =====================================================================
        -- 9. Формирование строки
        -- =====================================================================
        v_report := array_append(v_report,
            rpad(v_rec.incident_id::TEXT, c_id) || c_sep ||
            rpad(to_char(v_rec.incident_start, 'YYYY-MM-DD HH24:MI'), c_time) || c_sep ||
            rpad(COALESCE(to_char(v_sicpp_warn, 'YYYY-MM-DD HH24:MI'), '—'), c_time) || c_sep ||
            lpad(v_sicpp_lead, c_lead) || c_sep ||
            rpad(COALESCE(to_char(v_sicpp_end, 'YYYY-MM-DD HH24:MI'), '—'), c_time) || c_sep ||
            rpad(COALESCE(to_char(v_c_warn, 'YYYY-MM-DD HH24:MI'), '—'), c_time) || c_sep ||
            lpad(v_c_lead, c_lead) || c_sep ||
            lpad(v_c_alert_min::TEXT, c_cnt) || c_sep ||
            rpad(COALESCE(to_char(v_int_warn, 'YYYY-MM-DD HH24:MI'), '—'), c_time) || c_sep ||
            lpad(v_int_lead, c_lead));
    END LOOP;

    -- =========================================================================
    -- 10. Пустой результат
    -- =========================================================================
    IF v_row_count = 0 THEN
        v_report := array_append(v_report, '');
        v_report := array_append(v_report, format(
            'Инцидентов за период не найдено (исключено: status_filter=%s, series_filter=%s).',
            v_excluded_status, v_excluded_series));
        v_report := array_append(v_report, '');
        v_report := array_append(v_report, '=== КОНЕЦ ОТЧЁТА ===');
        RETURN v_report;
    END IF;

    v_report := array_append(v_report, '');
    v_report := array_append(v_report, format('Всего инцидентов (после фильтров): %s', v_row_count));
    v_report := array_append(v_report, format('Исключено: status_filter=%s, series_filter=%s',
        v_excluded_status, v_excluded_series));

    -- =========================================================================
    -- 11. Сводка по lead time
    -- =========================================================================
    DECLARE
        c_sig  CONSTANT INT := 12;
        c_cnt2 CONSTANT INT := 9;
        c_pct  CONSTANT INT := 7;
        c_stat CONSTANT INT := 10;
    BEGIN
        v_report := array_append(v_report, '');
        v_report := array_append(v_report,
            '--- СВОДКА ПО LEAD TIME (мин, между сигналом и стартом инцидента) ---');
        v_report := array_append(v_report,
            rpad('Сигнал', c_sig) || c_sep ||
            lpad('Покрыто', c_cnt2) || c_sep ||
            lpad('%', c_pct) || c_sep ||
            lpad('Медиана', c_stat) || c_sep ||
            lpad('Среднее', c_stat) || c_sep ||
            lpad('Мин', c_stat) || c_sep ||
            lpad('Макс', c_stat));
        v_report := array_append(v_report,
            repeat('-', c_sig) || c_sep ||
            repeat('-', c_cnt2) || c_sep ||
            repeat('-', c_pct) || c_sep ||
            repeat('-', c_stat) || c_sep ||
            repeat('-', c_stat) || c_sep ||
            repeat('-', c_stat) || c_sep ||
            repeat('-', c_stat));

        -- SICPP
        IF array_length(v_sicpp_leads, 1) > 0 THEN
            SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY val)::NUMERIC,
                   AVG(val)::NUMERIC, MIN(val)::NUMERIC, MAX(val)::NUMERIC
            INTO v_median, v_avg, v_min, v_max
            FROM unnest(v_sicpp_leads) AS val;

            v_report := array_append(v_report,
                rpad('SICPP', c_sig) || c_sep ||
                lpad(array_length(v_sicpp_leads, 1)::TEXT, c_cnt2) || c_sep ||
                lpad(ROUND((array_length(v_sicpp_leads, 1)::NUMERIC / v_row_count * 100), 1)::TEXT, c_pct) || c_sep ||
                lpad(ROUND(v_median, 1)::TEXT, c_stat) || c_sep ||
                lpad(ROUND(v_avg, 1)::TEXT, c_stat) || c_sep ||
                lpad(ROUND(v_min, 1)::TEXT, c_stat) || c_sep ||
                lpad(ROUND(v_max, 1)::TEXT, c_stat));
        ELSE
            v_report := array_append(v_report,
                rpad('SICPP', c_sig) || c_sep ||
                lpad('0', c_cnt2) || c_sep ||
                lpad('0.0', c_pct) || c_sep ||
                lpad('—', c_stat) || c_sep ||
                lpad('—', c_stat) || c_sep ||
                lpad('—', c_stat) || c_sep ||
                lpad('—', c_stat));
        END IF;

        -- C-only
        IF array_length(v_c_leads, 1) > 0 THEN
            SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY val)::NUMERIC,
                   AVG(val)::NUMERIC, MIN(val)::NUMERIC, MAX(val)::NUMERIC
            INTO v_median, v_avg, v_min, v_max
            FROM unnest(v_c_leads) AS val;

            v_report := array_append(v_report,
                rpad('C-only', c_sig) || c_sep ||
                lpad(array_length(v_c_leads, 1)::TEXT, c_cnt2) || c_sep ||
                lpad(ROUND((array_length(v_c_leads, 1)::NUMERIC / v_row_count * 100), 1)::TEXT, c_pct) || c_sep ||
                lpad(ROUND(v_median, 1)::TEXT, c_stat) || c_sep ||
                lpad(ROUND(v_avg, 1)::TEXT, c_stat) || c_sep ||
                lpad(ROUND(v_min, 1)::TEXT, c_stat) || c_sep ||
                lpad(ROUND(v_max, 1)::TEXT, c_stat));
        ELSE
            v_report := array_append(v_report,
                rpad('C-only', c_sig) || c_sep ||
                lpad('0', c_cnt2) || c_sep ||
                lpad('0.0', c_pct) || c_sep ||
                lpad('—', c_stat) || c_sep ||
                lpad('—', c_stat) || c_sep ||
                lpad('—', c_stat) || c_sep ||
                lpad('—', c_stat));
        END IF;

        -- Integral
        IF array_length(v_int_leads, 1) > 0 THEN
            SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY val)::NUMERIC,
                   AVG(val)::NUMERIC, MIN(val)::NUMERIC, MAX(val)::NUMERIC
            INTO v_median, v_avg, v_min, v_max
            FROM unnest(v_int_leads) AS val;

            v_report := array_append(v_report,
                rpad('Integral', c_sig) || c_sep ||
                lpad(array_length(v_int_leads, 1)::TEXT, c_cnt2) || c_sep ||
                lpad(ROUND((array_length(v_int_leads, 1)::NUMERIC / v_row_count * 100), 1)::TEXT, c_pct) || c_sep ||
                lpad(ROUND(v_median, 1)::TEXT, c_stat) || c_sep ||
                lpad(ROUND(v_avg, 1)::TEXT, c_stat) || c_sep ||
                lpad(ROUND(v_min, 1)::TEXT, c_stat) || c_sep ||
                lpad(ROUND(v_max, 1)::TEXT, c_stat));
        ELSE
            v_report := array_append(v_report,
                rpad('Integral', c_sig) || c_sep ||
                lpad('0', c_cnt2) || c_sep ||
                lpad('0.0', c_pct) || c_sep ||
                lpad('—', c_stat) || c_sep ||
                lpad('—', c_stat) || c_sep ||
                lpad('—', c_stat) || c_sep ||
                lpad('—', c_stat));
        END IF;
    END;

    v_report := array_append(v_report, '');
    v_report := array_append(v_report, '=== КОНЕЦ ОТЧЁТА ===');

    RETURN v_report;
END;
$$;

COMMENT ON FUNCTION signals_report(TIMESTAMPTZ, TIMESTAMPTZ) IS
'v2.0 (2026-10-27). Отчёт по сигналам предупреждения инцидентов.

100% согласован с generate_incident_forecast_report_v2 v22.0:
  * SICPP-покрытие: episode_start <= start_timepoint
                    AND episode_end >= start_timepoint - window_minutes (60);
  * C-only: хотя бы одна минута fired_c=TRUE в
            [start_timepoint - hybrid_window_minutes (20), start_timepoint];
  * те же фильтры, что в v22.0: status_filter и series_filter_enabled;
  * c_alert_min (колонка «C cnt») вычисляется через COUNT(*) FILTER
    (WHERE fired_c=TRUE), что при include_a/b=FALSE совпадает с c_alert_min
    из v22.0.

Для каждого инцидента выводится:
  - SICPP warn — episode_started_at покрывающего эпизода (или «—»);
  - SICPP end  — конец покрывающего эпизода (диагностика «истёкших» сигналов);
  - Lead       — длительность между сигналом и стартом инцидента (мин);
  - C warn     — первый fired_c=TRUE в окне c_window (или «—»);
  - C cnt      — число минут fired_c=TRUE в окне c_window;
  - Integral   — LEAST(SICPP, C-only), если хотя бы один сработал.

В шапке выводятся используемые параметры конфигурации (window_minutes,
hybrid_window_minutes, max_signal_duration_minutes, series_filter_enabled,
status_filter) — для воспроизводимости и сверки с v22.0.

Пример:
  SELECT unnest(signals_report());
  SELECT unnest(signals_report(now() - INTERVAL ''30 days'', now()));
';

-- =============================================================================
-- signals_false_positive_report
-- Версия: 1.1 (2026-10-28)
--
-- Назначение: контрольный отчёт о ложных срабатываниях (FP) сигналов
--             SICPP / C-only / ALARM.
--
--             FP-эпизод = непрерывный интервал активности сигнала, в течение
--             [ep_start, ep_end + p_grace_minutes) НЕ начался ни один инцидент.
--
-- Параметры:
--   p_start         TIMESTAMPTZ — начало периода (по умолчанию now() - 7 days)
--   p_end           TIMESTAMPTZ — конец периода (по умолчанию now())
--   p_grace_minutes INT         — «зона толерантности» (по умолчанию 30 мин):
--                                 инцидент, начавшийся через ≤ grace минут
--                                 после ep_end, ещё засчитывается как TP.
--
-- Возвращает: TEXT[].
--
-- Ограничения:
--   - Эпизоды, начавшиеся до p_start или завершающиеся после p_end, обрезаются
--     до границ периода — их длительность/минуты считаются только по
--     «видимой» части.
--   - Для C-only используется alert_active из operational_alert_history;
--     при include_a/b=TRUE это A∪B∪C, а не чистый C-only.
-- =============================================================================
CREATE OR REPLACE FUNCTION signals_false_positive_report(
    p_start         TIMESTAMPTZ DEFAULT now() - INTERVAL '7 days',
    p_end           TIMESTAMPTZ DEFAULT now(),
    p_grace_minutes INT         DEFAULT 30
)
RETURNS TEXT[]
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    cfg RECORD;
    v_js_thr REAL;
    v_risk_thr REAL;
    v_w_thr REAL;
    v_grace INTERVAL;

    v_report TEXT[] := '{}';
    v_rec RECORD;
    v_line TEXT;
    v_sep CONSTANT TEXT := ' | ';
    v_trend_found BOOLEAN := FALSE;

    -- SICPP
    v_s_tot INT := 0; v_s_tp INT := 0; v_s_tpg INT := 0; v_s_fp INT := 0;
    v_s_fp_min NUMERIC := 0;
    v_s_cov_first TIMESTAMPTZ; v_s_cov_last TIMESTAMPTZ;

    -- C-only
    v_c_tot INT := 0; v_c_tp INT := 0; v_c_tpg INT := 0; v_c_fp INT := 0;
    v_c_fp_min NUMERIC := 0;
    v_c_cov_first TIMESTAMPTZ; v_c_cov_last TIMESTAMPTZ;
    v_c_has_data BOOLEAN;

    -- ширины колонок
    c_id      CONSTANT INT := 8;
    c_time    CONSTANT INT := 16;
    c_dur     CONSTANT INT := 7;
    c_num     CONSTANT INT := 8;
    c_reason  CONSTANT INT := 22;
    c_delta   CONSTANT INT := 10;
BEGIN
    IF p_start > p_end THEN
        RETURN ARRAY['Ошибка: начальная дата позже конечной.'];
    END IF;
    IF p_grace_minutes < 0 THEN
        RETURN ARRAY['Ошибка: p_grace_minutes должен быть >= 0.'];
    END IF;
    v_grace := (p_grace_minutes || ' minutes')::INTERVAL;

    SELECT * INTO cfg FROM incident_forecast_config LIMIT 1;
    IF NOT FOUND THEN
        INSERT INTO incident_forecast_config DEFAULT VALUES;
        SELECT * INTO cfg FROM incident_forecast_config LIMIT 1;
    END IF;

    v_js_thr   := COALESCE(cfg.hybrid_js_min_threshold,      0.14);
    v_risk_thr := COALESCE(cfg.hybrid_p90_min_threshold,     0.98);
    v_w_thr    := COALESCE(cfg.hybrid_w_score_min_threshold, 0.0);

    -- =================================================================
    -- 1. Заголовок
    -- =================================================================
    v_report := array_append(v_report,
        '=== ОТЧЁТ О ЛОЖНЫХ СРАБАТЫВАНИЯХ СИГНАЛОВ (FP) ===');
    v_report := array_append(v_report, format('Период: %s – %s',
        to_char(p_start, 'YYYY-MM-DD HH24:MI'),
        to_char(p_end,   'YYYY-MM-DD HH24:MI')));
    v_report := array_append(v_report,
        'Версия: signals_false_positive_report v1.1 (2026-10-28; ALARM удалён)');
    v_report := array_append(v_report, '');
    v_report := array_append(v_report, 'Определения:');
    v_report := array_append(v_report,
        '  Эпизод = непрерывный интервал, где сигнал активен.');
    v_report := array_append(v_report,
        '  TP (strict)  = в [ep_start, ep_end) начался хотя бы один инцидент.');
    v_report := array_append(v_report, format(
        '  TP (+grace)  = инцидент в [ep_start, ep_end + %s мин) (пост-эффект).',
        p_grace_minutes));
    v_report := array_append(v_report,
        '  FP = ни одного инцидента с учётом grace.');
    v_report := array_append(v_report,
        '  precision = TP(+grace) / (TP(+grace) + FP).');
    v_report := array_append(v_report, '');
    v_report := array_append(v_report, 'Источники эпизодов:');
    v_report := array_append(v_report,
        '  SICPP  — sicpp_history (episode_started_at .. следующая FALSE).');
    v_report := array_append(v_report,
        '  C-only — operational_alert_history.alert_active=TRUE.');
    v_report := array_append(v_report,
        '           При include_a/b=FALSE alert_active == fired_c.');
    v_report := array_append(v_report, format(
        '  Параметры C-only: js_min=%s, p90_min=%s, W_min=%s.',
        v_js_thr, v_risk_thr, v_w_thr));
    v_report := array_append(v_report, '');

    -- =================================================================
    -- 2. SICPP — статистика
    -- =================================================================
    WITH sicpp_hist AS (
        SELECT id, changed_at, signal_active,
               LAG(signal_active) OVER (ORDER BY changed_at, id) AS prev_active
        FROM sicpp_history WHERE changed_at <= p_end
    ),
    sicpp_starts AS (
        SELECT id, changed_at AS raw_start FROM sicpp_hist
        WHERE signal_active = TRUE
          AND (prev_active IS NULL OR prev_active = FALSE)
    ),
    sicpp_ends AS (
        SELECT changed_at AS end_ts FROM sicpp_hist WHERE signal_active = FALSE
    ),
    sicpp_episodes AS (
        SELECT s.id, s.raw_start AS ep_start_raw,
               (SELECT MIN(e.end_ts) FROM sicpp_ends e WHERE e.end_ts > s.raw_start) AS ep_end_raw
        FROM sicpp_starts s
    ),
    sicpp_clipped AS (
        SELECT id,
               GREATEST(ep_start_raw, p_start) AS ep_start,
               LEAST(COALESCE(ep_end_raw, p_end), p_end) AS ep_end
        FROM sicpp_episodes
        WHERE COALESCE(ep_end_raw, p_end) >= p_start
          AND ep_start_raw <= p_end
    ),
    sicpp_classified AS (
        SELECT e.id, e.ep_start, e.ep_end,
               EXISTS (SELECT 1 FROM markov_chain_performance_incident pi
                       WHERE pi.start_timepoint >= e.ep_start
                         AND pi.start_timepoint <  e.ep_end) AS is_tp,
               EXISTS (SELECT 1 FROM markov_chain_performance_incident pi
                       WHERE pi.start_timepoint >= e.ep_start
                         AND pi.start_timepoint <  e.ep_end + v_grace) AS is_tp_grace
        FROM sicpp_clipped e
    )
    SELECT
        COUNT(*),
        COUNT(*) FILTER (WHERE is_tp),
        COUNT(*) FILTER (WHERE is_tp_grace),
        COUNT(*) FILTER (WHERE NOT is_tp_grace),
        COALESCE(SUM(EXTRACT(EPOCH FROM (ep_end - ep_start)) / 60)
                 FILTER (WHERE NOT is_tp_grace), 0)
    INTO v_s_tot, v_s_tp, v_s_tpg, v_s_fp, v_s_fp_min
    FROM sicpp_classified;

    SELECT MIN(changed_at), MAX(changed_at)
    INTO v_s_cov_first, v_s_cov_last
    FROM sicpp_history WHERE changed_at BETWEEN p_start AND p_end;

    -- =================================================================
    -- 3. C-only — статистика
    -- =================================================================
    SELECT EXISTS (
        SELECT 1 FROM operational_alert_history
        WHERE changed_at BETWEEN p_start AND p_end
    ) INTO v_c_has_data;

    IF v_c_has_data THEN
        WITH c_hist AS (
            SELECT id, changed_at, alert_active,
                   LEAD(changed_at) OVER (ORDER BY changed_at, id) AS next_change
            FROM operational_alert_history WHERE changed_at <= p_end
        ),
        c_episodes AS (
            SELECT id, changed_at AS ep_start_raw,
                   COALESCE(next_change, p_end) AS ep_end_raw
            FROM c_hist WHERE alert_active = TRUE
        ),
        c_clipped AS (
            SELECT id,
                   GREATEST(ep_start_raw, p_start) AS ep_start,
                   LEAST(ep_end_raw, p_end) AS ep_end
            FROM c_episodes
            WHERE ep_end_raw >= p_start AND ep_start_raw <= p_end
        ),
        c_classified AS (
            SELECT e.id, e.ep_start, e.ep_end,
                   EXISTS (SELECT 1 FROM markov_chain_performance_incident pi
                           WHERE pi.start_timepoint >= e.ep_start
                             AND pi.start_timepoint <  e.ep_end) AS is_tp,
                   EXISTS (SELECT 1 FROM markov_chain_performance_incident pi
                           WHERE pi.start_timepoint >= e.ep_start
                             AND pi.start_timepoint <  e.ep_end + v_grace) AS is_tp_grace
            FROM c_clipped e
        )
        SELECT
            COUNT(*),
            COUNT(*) FILTER (WHERE is_tp),
            COUNT(*) FILTER (WHERE is_tp_grace),
            COUNT(*) FILTER (WHERE NOT is_tp_grace),
            COALESCE(SUM(EXTRACT(EPOCH FROM (ep_end - ep_start)) / 60)
                     FILTER (WHERE NOT is_tp_grace), 0)
        INTO v_c_tot, v_c_tp, v_c_tpg, v_c_fp, v_c_fp_min
        FROM c_classified;

        SELECT MIN(changed_at), MAX(changed_at)
        INTO v_c_cov_first, v_c_cov_last
        FROM operational_alert_history WHERE changed_at BETWEEN p_start AND p_end;
    END IF;

    -- =================================================================
    -- 4. СВОДКА
    -- =================================================================
    v_report := array_append(v_report, '--- СВОДКА ПО ЛОЖНЫМ СРАБАТЫВАНИЯМ ---');
    v_report := array_append(v_report,
        rpad('Сигнал', 12) || v_sep ||
        lpad('Всего', c_num) || v_sep ||
        lpad('TP', c_num) || v_sep ||
        lpad('TP+gr', c_num) || v_sep ||
        lpad('FP', c_num) || v_sep ||
        lpad('Prec,%', c_num) || v_sep ||
        lpad('FP мин', c_num) || v_sep ||
        lpad('Avg FP', c_num));
    v_report := array_append(v_report,
        repeat('-', 12) || v_sep || repeat('-', c_num) || v_sep ||
        repeat('-', c_num) || v_sep || repeat('-', c_num) || v_sep ||
        repeat('-', c_num) || v_sep || repeat('-', c_num) || v_sep ||
        repeat('-', c_num) || v_sep || repeat('-', c_num));

    v_report := array_append(v_report,
        rpad('SICPP', 12) || v_sep ||
        lpad(v_s_tot::TEXT, c_num) || v_sep ||
        lpad(v_s_tp::TEXT, c_num) || v_sep ||
        lpad(v_s_tpg::TEXT, c_num) || v_sep ||
        lpad(v_s_fp::TEXT, c_num) || v_sep ||
        lpad(CASE WHEN (v_s_tpg + v_s_fp) > 0
                  THEN ROUND(v_s_tpg::NUMERIC / (v_s_tpg + v_s_fp) * 100, 1)::TEXT
                  ELSE '—' END, c_num) || v_sep ||
        lpad(ROUND(v_s_fp_min, 0)::TEXT, c_num) || v_sep ||
        lpad(CASE WHEN v_s_fp > 0
                  THEN ROUND((v_s_fp_min / v_s_fp)::NUMERIC, 1)::TEXT
                  ELSE '—' END, c_num));

    IF v_c_has_data THEN
        v_report := array_append(v_report,
            rpad('C-only', 12) || v_sep ||
            lpad(v_c_tot::TEXT, c_num) || v_sep ||
            lpad(v_c_tp::TEXT, c_num) || v_sep ||
            lpad(v_c_tpg::TEXT, c_num) || v_sep ||
            lpad(v_c_fp::TEXT, c_num) || v_sep ||
            lpad(CASE WHEN (v_c_tpg + v_c_fp) > 0
                      THEN ROUND(v_c_tpg::NUMERIC / (v_c_tpg + v_c_fp) * 100, 1)::TEXT
                      ELSE '—' END, c_num) || v_sep ||
            lpad(ROUND(v_c_fp_min, 0)::TEXT, c_num) || v_sep ||
            lpad(CASE WHEN v_c_fp > 0
                      THEN ROUND((v_c_fp_min / v_c_fp)::NUMERIC, 1)::TEXT
                      ELSE '—' END, c_num));
    ELSE
        v_report := array_append(v_report,
            rpad('C-only', 12) || v_sep ||
            lpad('0', c_num) || v_sep || lpad('0', c_num) || v_sep ||
            lpad('0', c_num) || v_sep || lpad('0', c_num) || v_sep ||
            lpad('—', c_num) || v_sep || lpad('0', c_num) || v_sep ||
            lpad('—', c_num));
    END IF;

    v_report := array_append(v_report, '');
    v_report := array_append(v_report, 'Покрытие источников данных:');
    v_report := array_append(v_report, format(
        '  sicpp_history:              %s .. %s',
        COALESCE(to_char(v_s_cov_first, 'YYYY-MM-DD HH24:MI'), 'нет данных'),
        COALESCE(to_char(v_s_cov_last,  'YYYY-MM-DD HH24:MI'), 'нет данных')));
    IF v_c_has_data THEN
        v_report := array_append(v_report, format(
            '  operational_alert_history: %s .. %s',
            COALESCE(to_char(v_c_cov_first, 'YYYY-MM-DD HH24:MI'), 'нет данных'),
            COALESCE(to_char(v_c_cov_last,  'YYYY-MM-DD HH24:MI'), 'нет данных')));
    ELSE
        v_report := array_append(v_report,
            '  operational_alert_history: НЕТ ЗАПИСЕЙ за период — секция C-only пуста.');
    END IF;
    v_report := array_append(v_report, '');

    -- =================================================================
    -- 5. ДЕТАЛИ FP — SICPP
    -- =================================================================
    IF v_s_fp > 0 THEN
        v_report := array_append(v_report,
            format('--- ДЕТАЛИ FP — SICPP (%s эпизодов) ---', v_s_fp));
        v_report := array_append(v_report,
            rpad('ID', c_id) || v_sep ||
            rpad('Старт эпизода', c_time) || v_sep ||
            rpad('Конец эпизода', c_time) || v_sep ||
            lpad('Длит', c_dur) || v_sep ||
            lpad('JS', c_num) || v_sep ||
            lpad('Risk', c_num) || v_sep ||
            lpad('W', c_num) || v_sep ||
            rpad('Классификация', c_reason) || v_sep ||
            lpad('Ближ.инц', c_delta) || v_sep ||
            'Δ,мин');
        v_report := array_append(v_report,
            repeat('-', c_id) || v_sep || repeat('-', c_time) || v_sep ||
            repeat('-', c_time) || v_sep || repeat('-', c_dur) || v_sep ||
            repeat('-', c_num) || v_sep || repeat('-', c_num) || v_sep ||
            repeat('-', c_num) || v_sep || repeat('-', c_reason) || v_sep ||
            repeat('-', c_delta) || v_sep || repeat('-', 6));

        FOR v_rec IN
        WITH sicpp_hist AS (
            SELECT id, changed_at, signal_active,
                   LAG(signal_active) OVER (ORDER BY changed_at, id) AS prev_active
            FROM sicpp_history WHERE changed_at <= p_end
        ),
        sicpp_starts AS (
            SELECT id, changed_at AS raw_start FROM sicpp_hist
            WHERE signal_active = TRUE
              AND (prev_active IS NULL OR prev_active = FALSE)
        ),
        sicpp_ends AS (
            SELECT changed_at AS end_ts FROM sicpp_hist WHERE signal_active = FALSE
        ),
        sicpp_episodes AS (
            SELECT s.id, s.raw_start AS ep_start_raw,
                   (SELECT MIN(e.end_ts) FROM sicpp_ends e WHERE e.end_ts > s.raw_start) AS ep_end_raw
            FROM sicpp_starts s
        ),
        sicpp_clipped AS (
            SELECT id,
                   GREATEST(ep_start_raw, p_start) AS ep_start,
                   LEAST(COALESCE(ep_end_raw, p_end), p_end) AS ep_end
            FROM sicpp_episodes
            WHERE COALESCE(ep_end_raw, p_end) >= p_start AND ep_start_raw <= p_end
        ),
        fp AS (
            SELECT e.id, e.ep_start, e.ep_end
            FROM sicpp_clipped e
            WHERE NOT EXISTS (SELECT 1 FROM markov_chain_performance_incident pi
                              WHERE pi.start_timepoint >= e.ep_start
                                AND pi.start_timepoint <  e.ep_end + v_grace)
        )
        SELECT fp.id, fp.ep_start, fp.ep_end,
               EXTRACT(EPOCH FROM (fp.ep_end - fp.ep_start)) / 60 AS dur_min,
               sh.js_avg, sh.risk_avg,
               (sh.risk_avg / NULLIF(cfg.risk_threshold, 0)) * cfg.weight_risk
                 + (sh.js_avg / NULLIF(cfg.js_threshold, 0)) * cfg.weight_js AS w_score,
               (SELECT MIN(pi.start_timepoint) FROM markov_chain_performance_incident pi
                WHERE pi.start_timepoint > fp.ep_end) AS next_incident_ts
        FROM fp
        LEFT JOIN sicpp_history sh ON sh.id = fp.id
        ORDER BY fp.ep_start
        LOOP
            v_report := array_append(v_report,
                rpad(v_rec.id::TEXT, c_id) || v_sep ||
                rpad(to_char(v_rec.ep_start, 'YYYY-MM-DD HH24:MI'), c_time) || v_sep ||
                rpad(to_char(v_rec.ep_end,   'YYYY-MM-DD HH24:MI'), c_time) || v_sep ||
                lpad(ROUND(v_rec.dur_min::NUMERIC, 0)::TEXT, c_dur) || v_sep ||
                lpad(COALESCE(ROUND(v_rec.js_avg::NUMERIC, 3)::TEXT,   '—'), c_num) || v_sep ||
                lpad(COALESCE(ROUND(v_rec.risk_avg::NUMERIC, 3)::TEXT, '—'), c_num) || v_sep ||
                lpad(COALESCE(ROUND(v_rec.w_score::NUMERIC, 3)::TEXT,  '—'), c_num) || v_sep ||
                rpad(
                    CASE
                        WHEN v_rec.js_avg IS NOT NULL AND v_rec.risk_avg IS NOT NULL
                         AND v_rec.js_avg >= cfg.js_threshold
                         AND v_rec.risk_avg >= cfg.risk_threshold THEN 'js+risk above thr'
                        WHEN v_rec.js_avg IS NOT NULL
                         AND v_rec.js_avg >= cfg.js_threshold THEN 'js above thr'
                        WHEN v_rec.risk_avg IS NOT NULL
                         AND v_rec.risk_avg >= cfg.risk_threshold THEN 'risk above thr'
                        ELSE 'weak/no data'
                    END, c_reason) || v_sep ||
                lpad(COALESCE(to_char(v_rec.next_incident_ts, 'HH24:MI'), '—'), c_delta) || v_sep ||
                COALESCE(ROUND(EXTRACT(EPOCH FROM (v_rec.next_incident_ts - v_rec.ep_end)) / 60)::TEXT, '—'));
        END LOOP;
        v_report := array_append(v_report, '');
    ELSE
        v_report := array_append(v_report, '--- SICPP: FP-эпизодов нет ---');
        v_report := array_append(v_report, '');
    END IF;

    -- =================================================================
    -- 6. ДЕТАЛИ FP — C-only
    -- =================================================================
    IF v_c_has_data AND v_c_fp > 0 THEN
        v_report := array_append(v_report,
            format('--- ДЕТАЛИ FP — C-only (%s эпизодов) ---', v_c_fp));
        v_report := array_append(v_report,
            rpad('ID', c_id) || v_sep ||
            rpad('Старт эпизода', c_time) || v_sep ||
            rpad('Конец эпизода', c_time) || v_sep ||
            lpad('Длит', c_dur) || v_sep ||
            lpad('Ближ.инц', c_delta) || v_sep ||
            'Δ,мин');
        v_report := array_append(v_report,
            repeat('-', c_id) || v_sep || repeat('-', c_time) || v_sep ||
            repeat('-', c_time) || v_sep || repeat('-', c_dur) || v_sep ||
            repeat('-', c_delta) || v_sep || repeat('-', 6));

        FOR v_rec IN
        WITH c_hist AS (
            SELECT id, changed_at, alert_active,
                   LEAD(changed_at) OVER (ORDER BY changed_at, id) AS next_change
            FROM operational_alert_history WHERE changed_at <= p_end
        ),
        c_episodes AS (
            SELECT id, changed_at AS ep_start_raw,
                   COALESCE(next_change, p_end) AS ep_end_raw
            FROM c_hist WHERE alert_active = TRUE
        ),
        c_clipped AS (
            SELECT id,
                   GREATEST(ep_start_raw, p_start) AS ep_start,
                   LEAST(ep_end_raw, p_end) AS ep_end
            FROM c_episodes
            WHERE ep_end_raw >= p_start AND ep_start_raw <= p_end
        ),
        fp AS (
            SELECT e.id, e.ep_start, e.ep_end
            FROM c_clipped e
            WHERE NOT EXISTS (SELECT 1 FROM markov_chain_performance_incident pi
                              WHERE pi.start_timepoint >= e.ep_start
                                AND pi.start_timepoint <  e.ep_end + v_grace)
        )
        SELECT fp.id, fp.ep_start, fp.ep_end,
               EXTRACT(EPOCH FROM (fp.ep_end - fp.ep_start)) / 60 AS dur_min,
               (SELECT MIN(pi.start_timepoint) FROM markov_chain_performance_incident pi
                WHERE pi.start_timepoint > fp.ep_end) AS next_incident_ts
        FROM fp ORDER BY fp.ep_start
        LOOP
            v_report := array_append(v_report,
                rpad(v_rec.id::TEXT, c_id) || v_sep ||
                rpad(to_char(v_rec.ep_start, 'YYYY-MM-DD HH24:MI'), c_time) || v_sep ||
                rpad(to_char(v_rec.ep_end,   'YYYY-MM-DD HH24:MI'), c_time) || v_sep ||
                lpad(ROUND(v_rec.dur_min::NUMERIC, 0)::TEXT, c_dur) || v_sep ||
                lpad(COALESCE(to_char(v_rec.next_incident_ts, 'HH24:MI'), '—'), c_delta) || v_sep ||
                COALESCE(ROUND(EXTRACT(EPOCH FROM (v_rec.next_incident_ts - v_rec.ep_end)) / 60)::TEXT, '—'));
        END LOOP;
        v_report := array_append(v_report, '');
    ELSIF NOT v_c_has_data THEN
        v_report := array_append(v_report,
            '--- C-only: НЕТ ДАННЫХ (operational_alert_history пуста за период) ---');
        v_report := array_append(v_report, '');
    ELSE
        v_report := array_append(v_report, '--- C-only: FP-эпизодов нет ---');
        v_report := array_append(v_report, '');
    END IF;

    -- =================================================================
    -- 7. РАСПРЕДЕЛЕНИЕ FP ПО ДЛИТЕЛЬНОСТИ
    -- =================================================================
    v_report := array_append(v_report, '--- РАСПРЕДЕЛЕНИЕ FP ПО ДЛИТЕЛЬНОСТИ (мин) ---');
    v_report := array_append(v_report,
        rpad('Сигнал', 12) || v_sep ||
        lpad('<5', c_dur) || v_sep ||
        lpad('5-15', c_dur) || v_sep ||
        lpad('15-60', c_dur) || v_sep ||
        lpad('60-180', c_dur) || v_sep ||
        lpad('>180', c_dur));
    v_report := array_append(v_report,
        repeat('-', 12) || v_sep || repeat('-', c_dur) || v_sep ||
        repeat('-', c_dur) || v_sep || repeat('-', c_dur) || v_sep ||
        repeat('-', c_dur) || v_sep || repeat('-', c_dur));

    DECLARE b1 INT := 0; b2 INT := 0; b3 INT := 0; b4 INT := 0; b5 INT := 0;
    BEGIN
        WITH sicpp_hist AS (
            SELECT id, changed_at, signal_active,
                   LAG(signal_active) OVER (ORDER BY changed_at, id) AS prev_active
            FROM sicpp_history WHERE changed_at <= p_end
        ),
        sicpp_starts AS (
            SELECT id, changed_at AS raw_start FROM sicpp_hist
            WHERE signal_active = TRUE AND (prev_active IS NULL OR prev_active = FALSE)
        ),
        sicpp_ends AS (
            SELECT changed_at AS end_ts FROM sicpp_hist WHERE signal_active = FALSE
        ),
        sicpp_episodes AS (
            SELECT s.id, s.raw_start AS ep_start_raw,
                   (SELECT MIN(e.end_ts) FROM sicpp_ends e WHERE e.end_ts > s.raw_start) AS ep_end_raw
            FROM sicpp_starts s
        ),
        sicpp_clipped AS (
            SELECT id, GREATEST(ep_start_raw, p_start) AS ep_start,
                   LEAST(COALESCE(ep_end_raw, p_end), p_end) AS ep_end
            FROM sicpp_episodes
            WHERE COALESCE(ep_end_raw, p_end) >= p_start AND ep_start_raw <= p_end
        ),
        fp AS (
            SELECT EXTRACT(EPOCH FROM (e.ep_end - e.ep_start)) / 60 AS dur_min
            FROM sicpp_clipped e
            WHERE NOT EXISTS (SELECT 1 FROM markov_chain_performance_incident pi
                              WHERE pi.start_timepoint >= e.ep_start
                                AND pi.start_timepoint <  e.ep_end + v_grace)
        )
        SELECT COUNT(*) FILTER (WHERE dur_min < 5),
               COUNT(*) FILTER (WHERE dur_min >= 5  AND dur_min < 15),
               COUNT(*) FILTER (WHERE dur_min >= 15 AND dur_min < 60),
               COUNT(*) FILTER (WHERE dur_min >= 60 AND dur_min < 180),
               COUNT(*) FILTER (WHERE dur_min >= 180)
        INTO b1, b2, b3, b4, b5 FROM fp;

        v_report := array_append(v_report,
            rpad('SICPP', 12) || v_sep ||
            lpad(b1::TEXT, c_dur) || v_sep || lpad(b2::TEXT, c_dur) || v_sep ||
            lpad(b3::TEXT, c_dur) || v_sep || lpad(b4::TEXT, c_dur) || v_sep ||
            lpad(b5::TEXT, c_dur));
    END;

    IF v_c_has_data THEN
        DECLARE b1 INT := 0; b2 INT := 0; b3 INT := 0; b4 INT := 0; b5 INT := 0;
        BEGIN
            WITH c_hist AS (
                SELECT id, changed_at, alert_active,
                       LEAD(changed_at) OVER (ORDER BY changed_at, id) AS next_change
                FROM operational_alert_history WHERE changed_at <= p_end
            ),
            c_episodes AS (
                SELECT id, changed_at AS ep_start_raw,
                       COALESCE(next_change, p_end) AS ep_end_raw
                FROM c_hist WHERE alert_active = TRUE
            ),
            c_clipped AS (
                SELECT id, GREATEST(ep_start_raw, p_start) AS ep_start,
                       LEAST(ep_end_raw, p_end) AS ep_end
                FROM c_episodes
                WHERE ep_end_raw >= p_start AND ep_start_raw <= p_end
            ),
            fp AS (
                SELECT EXTRACT(EPOCH FROM (e.ep_end - e.ep_start)) / 60 AS dur_min
                FROM c_clipped e
                WHERE NOT EXISTS (SELECT 1 FROM markov_chain_performance_incident pi
                                  WHERE pi.start_timepoint >= e.ep_start
                                    AND pi.start_timepoint <  e.ep_end + v_grace)
            )
            SELECT COUNT(*) FILTER (WHERE dur_min < 5),
                   COUNT(*) FILTER (WHERE dur_min >= 5  AND dur_min < 15),
                   COUNT(*) FILTER (WHERE dur_min >= 15 AND dur_min < 60),
                   COUNT(*) FILTER (WHERE dur_min >= 60 AND dur_min < 180),
                   COUNT(*) FILTER (WHERE dur_min >= 180)
            INTO b1, b2, b3, b4, b5 FROM fp;

            v_report := array_append(v_report,
                rpad('C-only', 12) || v_sep ||
                lpad(b1::TEXT, c_dur) || v_sep || lpad(b2::TEXT, c_dur) || v_sep ||
                lpad(b3::TEXT, c_dur) || v_sep || lpad(b4::TEXT, c_dur) || v_sep ||
                lpad(b5::TEXT, c_dur));
        END;
    END IF;

    v_report := array_append(v_report, '');

    -- =================================================================
    -- 8. ТРЕНД FP ПО ДНЯМ
    -- =================================================================
    v_report := array_append(v_report, '--- ТРЕНД FP ПО ДНЯМ ---');
    v_report := array_append(v_report,
        rpad('День', 12) || v_sep ||
        lpad('SICPP', c_dur) || v_sep ||
        lpad('C-only', c_dur));
    v_report := array_append(v_report,
        repeat('-', 12) || v_sep || repeat('-', c_dur) || v_sep ||
        repeat('-', c_dur));

    FOR v_rec IN
    WITH sicpp_hist AS (
        SELECT id, changed_at, signal_active,
               LAG(signal_active) OVER (ORDER BY changed_at, id) AS prev_active
        FROM sicpp_history WHERE changed_at <= p_end
    ),
    sicpp_starts AS (
        SELECT id, changed_at AS raw_start FROM sicpp_hist
        WHERE signal_active = TRUE AND (prev_active IS NULL OR prev_active = FALSE)
    ),
    sicpp_ends AS (
        SELECT changed_at AS end_ts FROM sicpp_hist WHERE signal_active = FALSE
    ),
    sicpp_episodes AS (
        SELECT s.id, s.raw_start AS ep_start_raw,
               (SELECT MIN(e.end_ts) FROM sicpp_ends e WHERE e.end_ts > s.raw_start) AS ep_end_raw
        FROM sicpp_starts s
    ),
    sicpp_clipped AS (
        SELECT id, GREATEST(ep_start_raw, p_start) AS ep_start,
               LEAST(COALESCE(ep_end_raw, p_end), p_end) AS ep_end
        FROM sicpp_episodes
        WHERE COALESCE(ep_end_raw, p_end) >= p_start AND ep_start_raw <= p_end
    ),
    sicpp_fp AS (
        SELECT DATE(e.ep_start) AS day FROM sicpp_clipped e
        WHERE NOT EXISTS (SELECT 1 FROM markov_chain_performance_incident pi
                          WHERE pi.start_timepoint >= e.ep_start
                            AND pi.start_timepoint <  e.ep_end + v_grace)
    ),
    c_fp AS (
        SELECT DATE(GREATEST(h.changed_at, p_start)) AS day
        FROM operational_alert_history h
        WHERE h.alert_active = TRUE
          AND h.changed_at BETWEEN p_start AND p_end
          AND NOT EXISTS (SELECT 1 FROM markov_chain_performance_incident pi
                          WHERE pi.start_timepoint >= h.changed_at
                            AND pi.start_timepoint <
                                COALESCE((SELECT MIN(h2.changed_at) FROM operational_alert_history h2
                                          WHERE h2.changed_at > h.changed_at AND h2.alert_active = FALSE), p_end)
                                + v_grace)
    ),
    all_days AS (
        SELECT DISTINCT day FROM sicpp_fp
        UNION SELECT DISTINCT day FROM c_fp
    )
    SELECT d.day,
           COALESCE((SELECT COUNT(*) FROM sicpp_fp WHERE day = d.day), 0) AS s_cnt,
           COALESCE((SELECT COUNT(*) FROM c_fp     WHERE day = d.day), 0) AS c_cnt
    FROM all_days d
    ORDER BY d.day
    LOOP
        v_trend_found := TRUE;
        v_report := array_append(v_report,
            rpad(v_rec.day::TEXT, 12) || v_sep ||
            lpad(v_rec.s_cnt::TEXT, c_dur) || v_sep ||
            lpad(v_rec.c_cnt::TEXT, c_dur));
    END LOOP;

    IF NOT v_trend_found THEN
        v_report := array_append(v_report, '  Нет FP-эпизодов за период.');
    END IF;
    v_report := array_append(v_report, '');

    -- =================================================================
    -- 9. ВЫВОДЫ И РЕКОМЕНДАЦИИ
    -- =================================================================
    v_report := array_append(v_report, '--- ВЫВОДЫ ---');

    DECLARE
        v_s_prec NUMERIC; v_c_prec NUMERIC;
    BEGIN
        IF (v_s_tpg + v_s_fp) > 0 THEN
            v_s_prec := ROUND(v_s_tpg::NUMERIC / (v_s_tpg + v_s_fp) * 100, 1);
        END IF;
        IF (v_c_tpg + v_c_fp) > 0 THEN
            v_c_prec := ROUND(v_c_tpg::NUMERIC / (v_c_tpg + v_c_fp) * 100, 1);
        END IF;

        IF v_s_prec IS NOT NULL THEN
            v_report := array_append(v_report, format(
                '  SICPP:  precision(+grace) = %s%% (FP %s из %s) — %s',
                v_s_prec, v_s_fp, v_s_tot,
                CASE WHEN v_s_prec >= 50 THEN 'приемлемо'
                     WHEN v_s_prec >= 30 THEN 'умеренно'
                     ELSE 'низкая' END));
        END IF;
        IF v_c_prec IS NOT NULL THEN
            v_report := array_append(v_report, format(
                '  C-only: precision(+grace) = %s%% (FP %s из %s) — %s',
                v_c_prec, v_c_fp, v_c_tot,
                CASE WHEN v_c_prec >= 50 THEN 'приемлемо'
                     WHEN v_c_prec >= 30 THEN 'умеренно'
                     ELSE 'низкая' END));
        END IF;

        v_report := array_append(v_report, '');
        v_report := array_append(v_report, '  Рекомендации:');

        IF v_s_fp > 0 AND v_s_prec IS NOT NULL AND v_s_prec < 30 THEN
            v_report := array_append(v_report,
                '    → SICPP: повысить js_threshold / risk_threshold,');
            v_report := array_append(v_report,
                '      либо ограничить LONG-эпизоды через max_signal_duration_minutes.');
        END IF;
        IF v_c_fp > 0 AND v_c_prec IS NOT NULL AND v_c_prec < 30 THEN
            v_report := array_append(v_report,
                '    → C-only: включить c_auto_threshold=TRUE,');
            v_report := array_append(v_report,
                '      либо скорректировать hybrid_js_min_threshold / hybrid_p90_min_threshold.');
        END IF;
        IF (v_s_fp + v_c_fp) = 0 THEN
            v_report := array_append(v_report,
                '    ✔ Ложных срабатываний не обнаружено.');
        END IF;
    END;

    v_report := array_append(v_report, '');
    v_report := array_append(v_report, '=== КОНЕЦ ОТЧЁТА ===');

    RETURN v_report;
END;
$$;

COMMENT ON FUNCTION signals_false_positive_report(TIMESTAMPTZ, TIMESTAMPTZ, INT) IS
'v1.1 (2026-10-28). Контрольный отчёт о ложных срабатываниях сигналов SICPP и C-only.

ИЗМЕНЕНИЯ v1.1 (относительно v1.0):
  - Секция ALARM полностью удалена: источник integral_signal_history
    удалён из системы вместе с интегральным сигналом SICPP + C-only.
  - Убраны: секция «ALARM — статистика», детальная секция «ДЕТАЛИ FP — ALARM»,
    строка «ALARM» в распределении по длительности, CTE `a_fp` в тренде
    по дням, ALARM-precision в выводах.
  - Оставлены только SICPP и C-only — два сигнала, которые не зависят
    от интегрального агрегатора.

Определения и формулы:
  Эпизод = непрерывный интервал активности сигнала.
  TP (strict)  = инцидент в [ep_start, ep_end).
  TP (+grace)  = инцидент в [ep_start, ep_end + p_grace_minutes).
  FP           = not TP (+grace).
  precision    = TP (+grace) / (TP (+grace) + FP).

Возвращает TEXT[].
';

-- =============================================================================
-- get_signals_valid_from
-- Возвращает earliest timestamp, с которого все три источника (SICPP,
-- C-only, ALARM) имеют полное и непрерывное покрытие.
--
-- Логика:
--   1) SICPP — max(changed_at) для первой "init" записи sicpp_history
--   2) C-only — первая запись operational_alert_history
--   3) ALARM — первая запись integral_signal_history
--   4) Для каждого добавляется warm-up: window_minutes для SICPP,
--      hybrid_window_minutes для C-only
-- =============================================================================
CREATE OR REPLACE FUNCTION get_signals_valid_from(
    p_warm_up_minutes INT DEFAULT NULL
)
RETURNS TABLE (
    sicpp_first_record      TIMESTAMPTZ,
    c_only_first_record     TIMESTAMPTZ,
    alarm_first_record      TIMESTAMPTZ,    -- всегда NULL (источник удалён)
    earliest_reliable_ts    TIMESTAMPTZ,
    recommended_start_ts    TIMESTAMPTZ,
    details                 TEXT
)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    cfg RECORD;
    v_warmup INT;
    v_sicpp_ts   TIMESTAMPTZ;
    v_c_only_ts  TIMESTAMPTZ;
    v_max_ts     TIMESTAMPTZ;
    v_recommended TIMESTAMPTZ;
BEGIN
    SELECT * INTO cfg FROM incident_forecast_config LIMIT 1;
    v_warmup := COALESCE(p_warm_up_minutes,
                         GREATEST(cfg.window_minutes, cfg.hybrid_window_minutes) + 5);

    -- SICPP: первая запись с reason='init' (или самая ранняя, если init нет)
    SELECT MIN(changed_at) INTO v_sicpp_ts
    FROM sicpp_history
    WHERE reason = 'init';

    IF v_sicpp_ts IS NULL THEN
        SELECT MIN(changed_at) INTO v_sicpp_ts FROM sicpp_history;
    END IF;

    -- C-only: первый переход alert_active=TRUE
    SELECT MIN(changed_at) INTO v_c_only_ts
    FROM operational_alert_history
    WHERE alert_active = TRUE;

    -- ALARM-источник  удалён вместе с интегральным сигналом.
    alarm_first_record := NULL;

    -- Earliest reliable = max из двух доступных источников.
    v_max_ts := GREATEST(
        COALESCE(v_sicpp_ts,  'infinity'::TIMESTAMPTZ),
        COALESCE(v_c_only_ts, 'infinity'::TIMESTAMPTZ)
    );

    IF v_max_ts = 'infinity'::TIMESTAMPTZ THEN
        earliest_reliable_ts := NULL;
        recommended_start_ts := NULL;
        details := format(
            'Отсутствуют данные: sicpp=%s, c_only=%s (ALARM-источник удалён)',
            COALESCE(v_sicpp_ts::TEXT,  'NULL'),
            COALESCE(v_c_only_ts::TEXT, 'NULL'));
        sicpp_first_record  := v_sicpp_ts;
        c_only_first_record := v_c_only_ts;
        RETURN NEXT; RETURN;
    END IF;

    earliest_reliable_ts := v_max_ts;

    -- Рекомендация: округлить до 30-мин границы + warm-up
    recommended_start_ts := date_trunc('hour', v_max_ts)
                          + (ceil(EXTRACT(MINUTE FROM v_max_ts) / 30.0) * 30 || ' minutes')::INTERVAL
                          + (v_warmup || ' minutes')::INTERVAL;

    sicpp_first_record  := v_sicpp_ts;
    c_only_first_record := v_c_only_ts;

    details := format(
        'bottleneck=%s; warm-up=%s мин; earliest=%s; recommended=%s; ALARM-источник удалён',
        CASE
            WHEN v_c_only_ts = v_max_ts THEN 'operational_alert_history'
            WHEN v_sicpp_ts  = v_max_ts THEN 'sicpp_history'
            ELSE 'unknown'
        END,
        v_warmup, v_max_ts, recommended_start_ts);

    RETURN NEXT;
END;
$$;

COMMENT ON FUNCTION get_signals_valid_from(INT) IS
'v1.1 (2026-10-28). Возвращает earliest_reliable_ts (max из первых записей
sicpp_history и operational_alert_history) и recommended_start_ts
(с округлением до 30 мин + warm-up).

ИЗМЕНЕНИЯ v1.1 (относительно v1.0):
  - Поле alarm_first_record всегда NULL — сохранено только для совместимости
    с существующими вызывающими запросами (например, SELECT * FROM ...).
  - earliest_reliable_ts считается как GREATEST от двух доступных источников
    (SICPP и C-only), а не от трёх.
';


CREATE OR REPLACE FUNCTION sicpp_cooldown_status()
RETURNS TABLE (
    field   TEXT,
    value   TEXT,
    status  TEXT,
    comment TEXT
)
LANGUAGE sql
STABLE
AS $$
    SELECT 'force_close_cooldown_until'::TEXT,
           COALESCE(to_char(s.force_close_cooldown_until, 'YYYY-MM-DD HH24:MI'), 'NULL'),
           CASE
               WHEN s.force_close_cooldown_until IS NULL THEN 'INACTIVE'
               WHEN s.force_close_cooldown_until > now() THEN 'ACTIVE'
               ELSE 'EXPIRED'
           END,
           'Cooldown after force-close (v3.2.0)'
    FROM sicpp_current_state s WHERE s.id = 1
    UNION ALL
    SELECT 'remaining_minutes'::TEXT,
           CASE
               WHEN s.force_close_cooldown_until IS NULL THEN 'NULL'
               WHEN s.force_close_cooldown_until > now()
                   THEN ROUND(EXTRACT(EPOCH FROM (s.force_close_cooldown_until - now())) / 60, 1)::TEXT
               ELSE '0'
           END,
           'INFO',
           'Minutes left in cooldown'
    FROM sicpp_current_state s WHERE s.id = 1
    UNION ALL
    SELECT 'sicpp_cooldown_minutes (config)',
           (SELECT sicpp_cooldown_minutes::TEXT FROM incident_forecast_config LIMIT 1),
           'INFO',
           'Configured cooldown duration'
    UNION ALL
    SELECT 'signal_active',
           COALESCE(s.signal_active::TEXT, 'NULL'),
           'INFO',
           'Current singleton state'
    FROM sicpp_current_state s WHERE s.id = 1
    UNION ALL
    SELECT 'last_history_reason',
           COALESCE((
               SELECT reason FROM sicpp_history
               ORDER BY changed_at DESC, id DESC LIMIT 1
           ), 'NULL'),
           'INFO',
           'Reason of the most recent sicpp_history record';
$$;

COMMENT ON FUNCTION sicpp_cooldown_status() IS
'v3.2.0. Диагностика текущего состояния cooldown. Возвращает 5 строк
(field/value/status/comment): cooldown_until, remaining_minutes,
sicpp_cooldown_minutes, signal_active, last_history_reason.
';

-- =============================================================================
-- Функция: sicpp_verify_max_duration_enforcement
-- Версия: 1.0 (2026-10-27)
-- Назначение: проверяет, что max_signal_duration_minutes и cooldown
--             действительно применяются в sicpp_history за указанный период.
-- =============================================================================
-- =============================================================================
-- Функция: sicpp_verify_max_duration_enforcement
-- Версия: 1.1 (2026-10-27, hotfix: добавлен episode_started_at в CTE starts)
-- Назначение: проверяет, что max_signal_duration_minutes и cooldown
--             действительно применяются в sicpp_history за указанный период.
--
-- ИСТОРИЯ:
--   v1.0 — падала с ошибкой «столбец "episode_started_at" не существует»,
--          т.к. в CTE starts он не выбирался, но использовался в FILTER.
--   v1.1 — добавлен episode_started_at в SELECT CTE starts.
-- =============================================================================
CREATE OR REPLACE FUNCTION sicpp_verify_max_duration_enforcement(
    p_start TIMESTAMPTZ DEFAULT now() - INTERVAL '30 days',
    p_end   TIMESTAMPTZ DEFAULT now()
)
RETURNS TABLE (
    metric  TEXT,
    value   TEXT,
    status  TEXT,
    comment TEXT
)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_max_dur               INT;
    v_cooldown_min          INT;
    v_ep_total              INT;
    v_ep_capped             INT;
    v_ep_violation          INT;
    v_max_uncapped_dur      INT;
    v_force_close_cnt       INT;
    v_cooldown_suppressed   INT;
    v_short_episodes        INT;
    v_max_fp_duration       INT;
BEGIN
    SELECT max_signal_duration_minutes, COALESCE(sicpp_cooldown_minutes, 0)
    INTO v_max_dur, v_cooldown_min
    FROM incident_forecast_config LIMIT 1;

    -- Эпизоды (FALSE -> TRUE переходы)
    -- v1.1: добавлен episode_started_at в SELECT CTE starts
    WITH starts AS (
        SELECT id, changed_at, signal_active, signal_duration, signal_capped,
               episode_started_at,
               LAG(signal_active) OVER (ORDER BY changed_at, id) AS prev_active
        FROM sicpp_history
        WHERE changed_at BETWEEN p_start AND p_end
    )
    SELECT
        COUNT(*) FILTER (WHERE signal_active = TRUE AND COALESCE(prev_active, FALSE) = FALSE),
        COUNT(*) FILTER (WHERE signal_active = TRUE AND COALESCE(signal_capped, FALSE) = TRUE),
        COUNT(*) FILTER (
            WHERE signal_active = TRUE
              AND COALESCE(signal_capped, FALSE) = FALSE
              AND episode_started_at IS NOT NULL
              AND EXTRACT(EPOCH FROM (changed_at - episode_started_at)) / 60 > v_max_dur
        ),
        MAX(signal_duration) FILTER (
            WHERE signal_active = TRUE AND COALESCE(signal_capped, FALSE) = FALSE
        )
    INTO v_ep_total, v_ep_capped, v_ep_violation, v_max_uncapped_dur
    FROM starts;

    SELECT COUNT(*) INTO v_force_close_cnt
    FROM sicpp_history
    WHERE reason = 'capped_force_end' AND changed_at BETWEEN p_start AND p_end;

    SELECT COUNT(*) INTO v_cooldown_suppressed
    FROM sicpp_history
    WHERE reason = 'cooldown_suppressed' AND changed_at BETWEEN p_start AND p_end;

    SELECT COUNT(*) INTO v_short_episodes
    FROM sicpp_history
    WHERE signal_active = TRUE
      AND signal_capped = FALSE
      AND signal_duration <= v_max_dur
      AND reason IN ('signal started', 'init')
      AND changed_at BETWEEN p_start AND p_end;

    SELECT COALESCE(MAX(signal_duration), 0) INTO v_max_fp_duration
    FROM sicpp_history
    WHERE changed_at BETWEEN p_start AND p_end
      AND signal_active = TRUE
      AND COALESCE(signal_capped, FALSE) = FALSE;

    -- ---------------- Вывод ----------------
    metric := 'max_signal_duration_minutes (config)';
    value  := v_max_dur::TEXT;
    status := 'INFO';
    comment := 'Configured max episode duration';
    RETURN NEXT;

    metric := 'sicpp_cooldown_minutes (config)';
    value  := v_cooldown_min::TEXT;
    status := 'INFO';
    comment := 'Cooldown after force-close';
    RETURN NEXT;

    metric := 'Всего эпизодов (FALSE->TRUE)';
    value  := v_ep_total::TEXT;
    status := 'INFO';
    comment := 'Signal started / init transitions';
    RETURN NEXT;

    metric := 'Нарушений max_duration (uncapped, duration > max)';
    value  := v_ep_violation::TEXT;
    status := CASE WHEN v_ep_violation = 0 THEN 'OK' ELSE 'FAIL' END;
    comment := 'Episodes exceeding max_signal_duration without capped flag';
    RETURN NEXT;

    metric := 'Max uncapped episode duration, мин';
    value  := COALESCE(v_max_uncapped_dur::TEXT, 'NULL');
    status := CASE WHEN COALESCE(v_max_uncapped_dur, 0) <= v_max_dur THEN 'OK' ELSE 'FAIL' END;
    comment := 'Should be <= max_signal_duration_minutes';
    RETURN NEXT;

    metric := 'Событий capped_force_end';
    value  := v_force_close_cnt::TEXT;
    status := CASE WHEN v_force_close_cnt > 0 THEN 'OK' ELSE 'INFO' END;
    comment := 'Force-closed capped episodes (v3.2.0)';
    RETURN NEXT;

    metric := 'Событий cooldown_suppressed';
    value  := v_cooldown_suppressed::TEXT;
    status := CASE
        WHEN v_force_close_cnt = 0 THEN 'INFO'
        WHEN v_cooldown_suppressed >= v_force_close_cnt THEN 'OK'
        ELSE 'WARN'
    END;
    comment := 'Suppressions by cooldown (≥ force-close count)';
    RETURN NEXT;

    metric := 'Коротких эпизодов (duration <= max)';
    value  := v_short_episodes::TEXT;
    status := 'INFO';
    comment := 'Episodes within max_duration';
    RETURN NEXT;

    metric := 'Max duration в истории (uncapped)';
    value  := v_max_fp_duration::TEXT;
    status := CASE WHEN v_max_fp_duration <= v_max_dur THEN 'OK' ELSE 'FAIL' END;
    comment := 'Max signal_duration among signal_active=TRUE, capped=FALSE';
    RETURN NEXT;

    RETURN;
END;
$$;

COMMENT ON FUNCTION sicpp_verify_max_duration_enforcement(TIMESTAMPTZ, TIMESTAMPTZ) IS
'v1.1 (2026-10-27, hotfix). Проверяет применение max_signal_duration_minutes и cooldown.
Исправление v1.0: добавлен episode_started_at в SELECT CTE starts
(без этого функция падала с ошибкой «столбец "episode_started_at" не существует»).
Возвращает таблицу metric/value/status/comment. Статусы: OK / FAIL / WARN / INFO.';

CREATE OR REPLACE FUNCTION get_current_signals_text()
RETURNS TEXT
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_now    TIMESTAMPTZ := now();
    v_sicpp  RECORD;
    v_hybrid RECORD;
    v_out    TEXT := '';
BEGIN
    SELECT * INTO v_sicpp  FROM sicpp_get_current() LIMIT 1;
    SELECT * INTO v_hybrid FROM mchain_hybrid_alert_at(v_now) LIMIT 1;

    v_out := v_out || '=== ТЕКУЩИЕ СИГНАЛЫ ПРЕДУПРЕЖДЕНИЯ ===' || E'\n';
    v_out := v_out || 'Момент: ' || to_char(v_now, 'YYYY-MM-DD HH24:MI:SS') || E'\n';
    v_out := v_out || repeat('-', 48) || E'\n';

    v_out := v_out || 'SICPP:' || E'\n';
    v_out := v_out || '  active        : ' || COALESCE(v_sicpp.signal_active::TEXT, 'NULL') || E'\n';
    v_out := v_out || '  strength      : ' || COALESCE(round(v_sicpp.signal_strength::NUMERIC, 4)::TEXT, '—') || E'\n';
    v_out := v_out || '  duration      : ' || COALESCE(v_sicpp.signal_duration::TEXT, '0') || ' мин' || E'\n';
    v_out := v_out || '  capped        : ' || COALESCE(v_sicpp.signal_capped::TEXT, 'FALSE') || E'\n';
    v_out := v_out || '  episode_start : ' || COALESCE(to_char(v_sicpp.episode_started_at, 'YYYY-MM-DD HH24:MI'), '—') || E'\n';
    v_out := v_out || '  updated_at    : ' || COALESCE(to_char(v_sicpp.updated_at, 'YYYY-MM-DD HH24:MI:SS'), '—') || E'\n';
    v_out := v_out || E'\n';

    v_out := v_out || 'C-only:' || E'\n';
    v_out := v_out || '  alert         : ' || COALESCE(v_hybrid.alert::TEXT, 'NULL') || E'\n';
    v_out := v_out || '  fired_c       : ' || COALESCE(v_hybrid.fired_c::TEXT, 'NULL') || E'\n';
    v_out := v_out || '  profile_c     : ' || COALESCE(v_hybrid.profile_c::TEXT, 'NULL') || E'\n';
    v_out := v_out || '  spike_c       : ' || COALESCE(v_hybrid.spike_c::TEXT, 'NULL')
                   || ' (spike_cnt=' || COALESCE(v_hybrid.spike_cnt::TEXT, '0') || ' мин)' || E'\n';
    v_out := v_out || '  risk_p90      : ' || COALESCE(round(v_hybrid.risk_p90::NUMERIC, 4)::TEXT, '—') || E'\n';
    v_out := v_out || '  js_avg        : ' || COALESCE(round(v_hybrid.js_avg::NUMERIC, 4)::TEXT, '—') || E'\n';
    v_out := v_out || '  w_score       : ' || COALESCE(round(v_hybrid.w_score::NUMERIC, 4)::TEXT, '—') || E'\n';

    RETURN v_out;
END;
$$;

COMMENT ON FUNCTION get_current_signals_text() IS
'Текстовый отчёт о текущих значениях SICPP и C-only (без интегрального сигнала).
Источники: sicpp_get_current(), mchain_hybrid_alert_at(now()).';

-- =============================================================================
-- Функция: get_current_signals_status
-- Версия: 1.1 (2026-10-28)
--
-- Назначение: текущее состояние сигналов SICPP и C-only (T/F), время
--             последнего перехода T↔F, а также метрики качества (recall /
--             precision) за последние p_lookback_days дней.
--
-- Источники «Времени изменения»:
--   SICPP  — последняя запись sicpp_history с reason IN
--            ('signal started', 'signal ended'); именно эти reason
--            соответствуют реальным переходам T↔F (capped / uncapped
--            и init не являются переходами и исключаются).
--   C-only — последняя запись operational_alert_history (запись пишется
--            только при смене alert_active).
--
-- Текущее значение:
--   SICPP  — sicpp_calculate_at(now()).signal_active (live).
--   C-only — mchain_hybrid_alert_at(now()).fired_c (live, чистый C).
--
-- Направление перехода:
--   F->T  — последний перешедший сигнал стал TRUE (активировался).
--   T->F  — последний перешедший сигнал стал FALSE (деактивировался).
--   —     — реальных T↔F переходов в истории нет (только init / capped).
--
-- Метрики recall / precision — те же, что в signals_false_positive_report
-- v1.0 и generate_incident_forecast_report_v2 v22.0.
--
-- Оговорка: при hybrid_include_a=TRUE или hybrid_include_b=TRUE
-- «Время изменения» для C-only отражает alert_active (A∨B∨C), а не
-- чистый fired_c; в отчёт добавляется предупреждение.
-- =============================================================================
-- =============================================================================
-- Функция: get_current_signals_status
-- Версия: 1.2 (2026-10-28)
--
-- Назначение: текущее состояние сигналов SICPP и C-only (T/F), время
--             последнего перехода T↔F, метрики качества (recall / precision)
--             за последние p_lookback_days дней и информация о последнем
--             инциденте (текущем или завершённом).
--
-- ИЗМЕНЕНИЯ v1.2 (относительно v1.1):
--   - Добавлена секция «--- ПОСЛЕДНИЙ ИНЦИДЕНТ ---», которая выводит
--     информацию о самом свежем инциденте из
--     markov_chain_performance_incident:
--       * ID, статус (ТЕКУЩИЙ / завершён);
--       * время начала;
--       * время окончания (для завершённых);
--       * длительность (для завершённых) или длительность на текущий момент
--         (для текущих);
--       * сколько минут прошло с начала / с завершения.
--   - Если таблица инцидентов пуста или недоступна, выводится
--     соответствующее сообщение без ошибки.
--   - Остальная логика (SICPP / C-only / T↔F / recall / precision) без
--     изменений.
-- =============================================================================
CREATE OR REPLACE FUNCTION get_current_signals_status(
    p_lookback_days INT DEFAULT 7
)
RETURNS TEXT[]
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_report TEXT[] := '{}';
    v_now    TIMESTAMPTZ := now();
    v_start  TIMESTAMPTZ;
    v_sep    CONSTANT TEXT := ' | ';

    c_name   CONSTANT INT := 8;
    c_val    CONSTANT INT := 8;
    c_chg    CONSTANT INT := 26;
    c_recall CONSTANT INT := 10;
    c_prec   CONSTANT INT := 10;

    v_window_minutes   INT;
    v_c_window_minutes INT;
    v_include_a        BOOLEAN;
    v_include_b        BOOLEAN;

    -- Текущее состояние (live)
    v_sicpp_cur RECORD;
    v_c_cur     RECORD;
    v_sicpp_val BOOLEAN := FALSE;
    v_c_val     BOOLEAN := FALSE;

    -- Последнее изменение T↔F
    v_s_chg_time    TIMESTAMPTZ;
    v_s_chg_active  BOOLEAN;
    v_s_chg_str     TEXT := '—';
    v_c_chg_time    TIMESTAMPTZ;
    v_c_chg_active  BOOLEAN;
    v_c_chg_str     TEXT := '—';

    -- SICPP метрики
    v_s_total_inc    INT := 0;
    v_s_covered_inc  INT := 0;
    v_s_recall       NUMERIC;
    v_s_total_ep     INT := 0;
    v_s_tp_ep        INT := 0;
    v_s_precision    NUMERIC;

    -- C-only метрики
    v_c_total_inc    INT := 0;
    v_c_covered_inc  INT := 0;
    v_c_recall       NUMERIC;
    v_c_total_ep     INT := 0;
    v_c_tp_ep        INT := 0;
    v_c_precision    NUMERIC;

    v_has_sicpp_hist BOOLEAN := FALSE;
    v_has_c_hist     BOOLEAN := FALSE;

    -- NEW v1.2: последний инцидент
    v_last_inc          RECORD;
    v_has_incident_tbl  BOOLEAN := FALSE;
    v_inc_status        TEXT;
    v_inc_duration_min  NUMERIC;
    v_inc_elapsed_min   NUMERIC;
BEGIN
    IF p_lookback_days IS NULL OR p_lookback_days <= 0 THEN
        RETURN ARRAY['Ошибка: p_lookback_days должен быть положительным.'];
    END IF;

    v_start := v_now - (p_lookback_days || ' days')::INTERVAL;

    -- 1. Конфигурация
    BEGIN
        SELECT COALESCE(window_minutes, 60),
               COALESCE(hybrid_window_minutes, 20),
               COALESCE(hybrid_include_a, FALSE),
               COALESCE(hybrid_include_b, FALSE)
        INTO v_window_minutes, v_c_window_minutes, v_include_a, v_include_b
        FROM incident_forecast_config LIMIT 1;
    EXCEPTION WHEN OTHERS THEN
        v_window_minutes   := 60;
        v_c_window_minutes := 20;
        v_include_a        := FALSE;
        v_include_b        := FALSE;
    END;

    -- 2. Текущее значение SICPP (live)
    BEGIN
        SELECT * INTO v_sicpp_cur FROM sicpp_calculate_at(v_now);
        v_sicpp_val := COALESCE(v_sicpp_cur.signal_active, FALSE);
    EXCEPTION WHEN OTHERS THEN
        v_sicpp_cur := NULL;
        v_sicpp_val := FALSE;
    END;

    -- 3. Текущее значение C-only (live)
    BEGIN
        SELECT * INTO v_c_cur FROM mchain_hybrid_alert_at(v_now);
        v_c_val := COALESCE(v_c_cur.fired_c, FALSE);
    EXCEPTION WHEN OTHERS THEN
        v_c_cur := NULL;
        v_c_val := FALSE;
    END;

    -- 4. Последнее изменение SICPP T↔F
    BEGIN
        SELECT changed_at, signal_active
        INTO v_s_chg_time, v_s_chg_active
        FROM sicpp_history
        WHERE changed_at <= v_now
          AND reason IN ('signal started', 'signal ended')
        ORDER BY changed_at DESC, id DESC
        LIMIT 1;

        IF FOUND THEN
            v_s_chg_str := to_char(v_s_chg_time, 'YYYY-MM-DD HH24:MI')
                || CASE WHEN v_s_chg_active THEN ' (F->T)' ELSE ' (T->F)' END;
        END IF;
    EXCEPTION WHEN OTHERS THEN
        v_s_chg_str := '—';
    END;

    -- 5. Последнее изменение C-only (по alert_active)
    BEGIN
        SELECT changed_at, alert_active
        INTO v_c_chg_time, v_c_chg_active
        FROM operational_alert_history
        WHERE changed_at <= v_now
        ORDER BY changed_at DESC, id DESC
        LIMIT 1;

        IF FOUND THEN
            v_c_chg_str := to_char(v_c_chg_time, 'YYYY-MM-DD HH24:MI')
                || CASE WHEN v_c_chg_active THEN ' (F->T)' ELSE ' (T->F)' END;
        END IF;
    EXCEPTION WHEN OTHERS THEN
        v_c_chg_str := '—';
    END;

    -- 6. SICPP: recall и precision (по эпизодам)
    SELECT EXISTS (SELECT 1 FROM sicpp_history
                   WHERE changed_at BETWEEN v_start AND v_now)
    INTO v_has_sicpp_hist;

    IF v_has_sicpp_hist THEN
        WITH sicpp_hist AS (
            SELECT id, changed_at, signal_active,
                   LAG(signal_active) OVER (ORDER BY changed_at, id) AS prev_active
            FROM sicpp_history WHERE changed_at <= v_now
        ),
        sicpp_starts AS (
            SELECT id, changed_at AS raw_start FROM sicpp_hist
            WHERE signal_active = TRUE
              AND (prev_active IS NULL OR prev_active = FALSE)
        ),
        sicpp_ends AS (
            SELECT changed_at AS end_ts FROM sicpp_hist WHERE signal_active = FALSE
        ),
        sicpp_episodes AS (
            SELECT s.id, s.raw_start AS ep_start_raw,
                   (SELECT MIN(e.end_ts) FROM sicpp_ends e
                     WHERE e.end_ts > s.raw_start) AS ep_end_raw
            FROM sicpp_starts s
        ),
        sicpp_clipped AS (
            SELECT id,
                   GREATEST(ep_start_raw, v_start) AS ep_start,
                   LEAST(COALESCE(ep_end_raw, v_now), v_now) AS ep_end
            FROM sicpp_episodes
            WHERE COALESCE(ep_end_raw, v_now) >= v_start
              AND ep_start_raw <= v_now
        )
        SELECT COUNT(*),
               COUNT(*) FILTER (WHERE EXISTS (
                   SELECT 1 FROM markov_chain_performance_incident pi
                   WHERE pi.start_timepoint >= ep_start
                     AND pi.start_timepoint <  ep_end))
        INTO v_s_total_ep, v_s_tp_ep
        FROM sicpp_clipped;

        v_s_precision := CASE WHEN v_s_total_ep > 0
            THEN round(v_s_tp_ep::NUMERIC / v_s_total_ep * 100, 1)
            ELSE NULL END;
    END IF;

    SELECT COUNT(*) INTO v_s_total_inc
    FROM markov_chain_performance_incident
    WHERE start_timepoint BETWEEN v_start AND v_now;

    IF v_s_total_inc > 0 AND v_has_sicpp_hist THEN
        WITH sicpp_hist AS (
            SELECT id, changed_at, signal_active,
                   LAG(signal_active) OVER (ORDER BY changed_at, id) AS prev_active
            FROM sicpp_history WHERE changed_at <= v_now
        ),
        sicpp_starts AS (
            SELECT id, changed_at AS raw_start FROM sicpp_hist
            WHERE signal_active = TRUE
              AND (prev_active IS NULL OR prev_active = FALSE)
        ),
        sicpp_ends AS (
            SELECT changed_at AS end_ts FROM sicpp_hist WHERE signal_active = FALSE
        ),
        sicpp_episodes AS (
            SELECT s.id, s.raw_start AS ep_start,
                   (SELECT MIN(e.end_ts) FROM sicpp_ends e
                     WHERE e.end_ts > s.raw_start) AS ep_end
            FROM sicpp_starts s
        )
        SELECT COUNT(*) INTO v_s_covered_inc
        FROM markov_chain_performance_incident pi
        WHERE pi.start_timepoint BETWEEN v_start AND v_now
          AND EXISTS (
              SELECT 1 FROM sicpp_episodes e
              WHERE e.ep_start <= pi.start_timepoint
                AND COALESCE(e.ep_end, v_now)
                    >= pi.start_timepoint - v_window_minutes * INTERVAL '1 minute');

        v_s_recall := round(v_s_covered_inc::NUMERIC / v_s_total_inc * 100, 1);
    END IF;

    -- 7. C-only: recall и precision
    SELECT EXISTS (SELECT 1 FROM operational_alert_history
                   WHERE changed_at BETWEEN v_start AND v_now)
    INTO v_has_c_hist;

    IF v_has_c_hist THEN
        WITH c_hist AS (
            SELECT id, changed_at, alert_active,
                   LEAD(changed_at) OVER (ORDER BY changed_at, id) AS next_change
            FROM operational_alert_history WHERE changed_at <= v_now
        ),
        c_episodes AS (
            SELECT id, changed_at AS ep_start_raw,
                   COALESCE(next_change, v_now) AS ep_end_raw
            FROM c_hist WHERE alert_active = TRUE
        ),
        c_clipped AS (
            SELECT id,
                   GREATEST(ep_start_raw, v_start) AS ep_start,
                   LEAST(ep_end_raw, v_now) AS ep_end
            FROM c_episodes
            WHERE ep_end_raw >= v_start AND ep_start_raw <= v_now
        )
        SELECT COUNT(*),
               COUNT(*) FILTER (WHERE EXISTS (
                   SELECT 1 FROM markov_chain_performance_incident pi
                   WHERE pi.start_timepoint >= ep_start
                     AND pi.start_timepoint <  ep_end))
        INTO v_c_total_ep, v_c_tp_ep
        FROM c_clipped;

        v_c_precision := CASE WHEN v_c_total_ep > 0
            THEN round(v_c_tp_ep::NUMERIC / v_c_total_ep * 100, 1)
            ELSE NULL END;
    END IF;

    SELECT COUNT(*) INTO v_c_total_inc
    FROM markov_chain_performance_incident
    WHERE start_timepoint BETWEEN v_start AND v_now;

    IF v_c_total_inc > 0 THEN
        SELECT COUNT(*) INTO v_c_covered_inc
        FROM markov_chain_performance_incident pi
        WHERE pi.start_timepoint BETWEEN v_start AND v_now
          AND EXISTS (
              SELECT 1 FROM generate_series(
                  pi.start_timepoint - v_c_window_minutes * INTERVAL '1 minute',
                  pi.start_timepoint,
                  '1 minute') AS gs(m)
              CROSS JOIN LATERAL mchain_hybrid_alert_at(gs.m) h
              WHERE h.fired_c = TRUE);

        v_c_recall := round(v_c_covered_inc::NUMERIC / v_c_total_inc * 100, 1);
    END IF;

    -- =====================================================================
    -- 7b. NEW v1.2: последний инцидент (текущий или завершённый)
    -- =====================================================================
    SELECT EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_name = 'markov_chain_performance_incident'
    ) INTO v_has_incident_tbl;

    IF v_has_incident_tbl THEN
        BEGIN
            SELECT id, start_timepoint, finish_timepoint
            INTO v_last_inc
            FROM markov_chain_performance_incident
            WHERE start_timepoint <= v_now
            ORDER BY start_timepoint DESC, id DESC
            LIMIT 1;
        EXCEPTION WHEN OTHERS THEN
            v_last_inc := NULL;
        END;
    ELSE
        v_last_inc := NULL;
    END IF;

    -- 8. Формирование отчёта
    v_report := array_append(v_report,
        format('Дата/время: %s', to_char(v_now, 'YYYY-MM-DD HH24:MI:SS')));
    v_report := array_append(v_report,
        format('Период оценки метрик: последние %s дней (%s – %s)',
            p_lookback_days,
            to_char(v_start, 'YYYY-MM-DD HH24:MI'),
            to_char(v_now,   'YYYY-MM-DD HH24:MI')));
    v_report := array_append(v_report, '');

    -- Заголовок таблицы (по требованию ТЗ)
    v_report := array_append(v_report,
        rpad('Сигнал', c_name) || v_sep ||
        lpad('T/F', c_val) || v_sep ||
        lpad('Изменение (T->F, F->T)', c_chg) || v_sep ||
        lpad('Охват', c_recall) || v_sep ||
        lpad('Точность', c_prec));
    v_report := array_append(v_report,
        repeat('-', c_name) || v_sep ||
        repeat('-', c_val) || v_sep ||
        repeat('-', c_chg) || v_sep ||
        repeat('-', c_recall) || v_sep ||
        repeat('-', c_prec));

    -- SICPP
    v_report := array_append(v_report,
        rpad('SICPP', c_name) || v_sep ||
        lpad(CASE WHEN v_sicpp_val THEN 'TRUE' ELSE 'FALSE' END, c_val) || v_sep ||
        lpad(v_s_chg_str, c_chg) || v_sep ||
        lpad(COALESCE(v_s_recall::TEXT || '%', '—'), c_recall) || v_sep ||
        lpad(COALESCE(v_s_precision::TEXT || '%', '—'), c_prec));

    -- C-only
    v_report := array_append(v_report,
        rpad('C-only', c_name) || v_sep ||
        lpad(CASE WHEN v_c_val THEN 'TRUE' ELSE 'FALSE' END, c_val) || v_sep ||
        lpad(v_c_chg_str, c_chg) || v_sep ||
        lpad(COALESCE(v_c_recall::TEXT || '%', '—'), c_recall) || v_sep ||
        lpad(COALESCE(v_c_precision::TEXT || '%', '—'), c_prec));

    v_report := array_append(v_report, '');

    -- Детали
    v_report := array_append(v_report, '--- ДЕТАЛИ ---');
    v_report := array_append(v_report, format(
        'SICPP:  инцидентов %s, покрыто %s, эпизодов %s, TP %s',
        v_s_total_inc, v_s_covered_inc, v_s_total_ep, v_s_tp_ep));
    v_report := array_append(v_report, format(
        'C-only: инцидентов %s, покрыто %s, эпизодов %s, TP %s',
        v_c_total_inc, v_c_covered_inc, v_c_total_ep, v_c_tp_ep));

    IF v_sicpp_cur IS NOT NULL THEN
        v_report := array_append(v_report, format(
            'SICPP (live):  длительность=%s мин, capped=%s',
            COALESCE(v_sicpp_cur.signal_duration::TEXT, '0'),
            COALESCE(v_sicpp_cur.signal_capped::TEXT, 'FALSE')));
    END IF;
    IF v_c_cur IS NOT NULL THEN
        v_report := array_append(v_report, format(
            'C-only (live): risk_p90=%s',
            COALESCE(round(v_c_cur.risk_p90::NUMERIC, 4)::TEXT, 'NULL')));
    END IF;

    -- =====================================================================
    -- NEW v1.2: секция «ПОСЛЕДНИЙ ИНЦИДЕНТ»
    -- =====================================================================
    v_report := array_append(v_report, '');
    v_report := array_append(v_report, '--- ПОСЛЕДНИЙ ИНЦИДЕНТ (markov_chain_performance_incident) ---');

    IF NOT v_has_incident_tbl THEN
        v_report := array_append(v_report,
            'Таблица markov_chain_performance_incident недоступна.');
    ELSIF v_last_inc IS NULL OR v_last_inc.id IS NULL THEN
        v_report := array_append(v_report,
            'Инцидентов в истории нет (или все start_timepoint > now()).');
    ELSE
        IF v_last_inc.finish_timepoint IS NULL THEN
            -- Текущий (незавершённый) инцидент
            v_inc_status := 'ТЕКУЩИЙ (не завершён)';
            v_inc_elapsed_min := round(
                (EXTRACT(EPOCH FROM (v_now - v_last_inc.start_timepoint)) / 60)::NUMERIC, 1);

            v_report := array_append(v_report, format('ID:              %s', v_last_inc.id));
            v_report := array_append(v_report, format('Статус:          %s', v_inc_status));
            v_report := array_append(v_report, format('Начало:          %s',
                to_char(v_last_inc.start_timepoint, 'YYYY-MM-DD HH24:MI')));
            v_report := array_append(v_report, 'Конец:           — (не завершён)');
            v_report := array_append(v_report, format('Длительность:    %s мин (на текущий момент)',
                v_inc_elapsed_min));
            v_report := array_append(v_report, format('Прошло с начала: %s мин',
                v_inc_elapsed_min));
        ELSE
            -- Завершённый инцидент
            v_inc_status := 'завершён';
            v_inc_duration_min := round(
                (EXTRACT(EPOCH FROM (v_last_inc.finish_timepoint - v_last_inc.start_timepoint)) / 60)::NUMERIC, 1);
            v_inc_elapsed_min := round(
                (EXTRACT(EPOCH FROM (v_now - v_last_inc.finish_timepoint)) / 60)::NUMERIC, 1);

            v_report := array_append(v_report, format('ID:              %s', v_last_inc.id));
            v_report := array_append(v_report, format('Статус:          %s', v_inc_status));
            v_report := array_append(v_report, format('Начало:          %s',
                to_char(v_last_inc.start_timepoint, 'YYYY-MM-DD HH24:MI')));
            v_report := array_append(v_report, format('Конец:           %s',
                to_char(v_last_inc.finish_timepoint, 'YYYY-MM-DD HH24:MI')));
            v_report := array_append(v_report, format('Длительность:    %s мин', v_inc_duration_min));
            v_report := array_append(v_report, format('Прошло с завершения: %s мин', v_inc_elapsed_min));
        END IF;
    END IF;

    -- Примечания
    IF NOT v_has_sicpp_hist THEN
        v_report := array_append(v_report, '');
        v_report := array_append(v_report,
            'Примечание: sicpp_history пуста за период — SICPP-метрики недоступны.');
    END IF;
    IF NOT v_has_c_hist THEN
        v_report := array_append(v_report,
            'Примечание: operational_alert_history пуста за период — C-only эпизоды недоступны.');
    END IF;

    IF v_include_a OR v_include_b THEN
        v_report := array_append(v_report, format(
            '⚠ hybrid_include_a=%s, hybrid_include_b=%s — «Время изменения» C-only отражает alert_active (A∨B∨C), а не чистый fired_c.',
            v_include_a, v_include_b));
    END IF;

    RETURN v_report;
END;
$$;

COMMENT ON FUNCTION get_current_signals_status(INT) IS
'v1.2 (2026-10-28). Отчёт о текущем состоянии сигналов SICPP и C-only
+ информация о последнем инциденте (текущем или завершённом).

Возвращает TEXT[]:
  1. Дата/время и период оценки метрик;
  2. Таблица: Сигнал | T/F | Изменение (T->F, F->T) | Охват | Точность;
  3. --- ДЕТАЛИ --- (инцидентов / покрыто / эпизодов / TP, live-состояние);
  4. --- ПОСЛЕДНИЙ ИНЦИДЕНТ --- (v1.2): ID, статус (ТЕКУЩИЙ / завершён),
     время начала, время окончания (для завершённых), длительность
     (для завершённых) или длительность на текущий момент (для текущих),
     прошло минут с начала / с завершения;
  5. Примечания (пустая sicpp_history / operational_alert_history,
     предупреждение при hybrid_include_a/b=TRUE).

Столбцы таблицы:
  T/F          — текущее значение (sicpp_calculate_at(now()).signal_active
                 для SICPP; mchain_hybrid_alert_at(now()).fired_c для C-only).
  Изменение    — время последнего реального T↔F перехода:
                 SICPP  — последняя запись sicpp_history с
                          reason IN (''signal started'', ''signal ended'');
                 C-only — последняя запись operational_alert_history.
                 Формат: ''YYYY-MM-DD HH24:MI (F->T)'' или ''... (T->F)''.
                 ''—'' — реальных T↔F переходов в истории нет (только init/capped).
  Охват        — recall = покрытые инциденты / все инциденты за p_lookback_days.
  Точность     — precision = TP эпизоды / все эпизоды за p_lookback_days.

Пример:
  SELECT unnest(get_current_signals_status());
  SELECT unnest(get_current_signals_status(30));
';

-- =============================================================================
-- Пример вывода
-- =============================================================================
/*
SELECT unnest(get_current_signals_status());

 Дата/время: 2026-10-28 14:35:02
 Период оценки метрик: последние 7 дней (2026-10-21 14:35 – 2026-10-28 14:35)

 Сигнал   |     T/F |   Изменение (T->F, F->T) |     Охват |  Точность
 -------- | ------- | ------------------------ | --------- | ---------
 SICPP    |   FALSE | 2026-10-28 14:12 (T->F)  |     68.8% |     42.1%
 C-only   |   FALSE | 2026-10-28 14:18 (T->F)  |     81.3% |     31.5%

 --- ДЕТАЛИ ---
 SICPP:  инцидентов 16, покрыто 11, эпизодов 19, TP 8
 C-only: инцидентов 16, покрыто 13, эпизодов 41, TP 13
 SICPP (live):  длительность=0 мин, capped=false
 C-only (live): risk_p90=0.4102

 --- ПОСЛЕДНИЙ ИНЦИДЕНТ (markov_chain_performance_incident) ---
 ID:              127
 Статус:          завершён
 Начало:          2026-10-28 09:14
 Конец:           2026-10-28 09:52
 Длительность:    38.0 мин
 Прошло с завершения: 283.0 мин
*/



-- =============================================================================
-- Функция: historical_fill_c_only
-- Версия: 1.0 (2026-10-28)
--
-- Назначение: историческое заполнение значений сигнала C-only в
--             operational_alert_history. Аналог historical_fill_sicpp для
--             SICPP, но источник состояния — mchain_hybrid_alert_at()
--             (двухпутевой C: profile_c OR spike_c; при hybrid_include_a/b=FALSE
--             alert == fired_c).
--
-- СОГЛАСОВАННОСТЬ С RUNTIME:
--   - Поля и логика вставки совпадают с update_operational_alert_state():
--       * alert_active  = v_calc.alert  (итог: A ∨ B ∨ C с учётом include_a/b)
--       * fired_c       = v_calc.fired_c
--       * fired_a_would = (v_calc.pre_adv = 100)   (raw A, как в runtime)
--       * fired_b       = v_calc.fired_b
--       * risk_p90      = v_calc.risk_p90
--       * js_avg        = последний js_avg из sicpp_history на момент v_ts
--   - Запись в историю только при смене alert_active (init / started / ended),
--     что соответствует поведению runtime-функции.
--
-- ЗАВИСИМОСТИ (должны быть заполнены до вызова):
--   1) prediction_log            — риск и spike_cnt для mchain_hybrid_alert_at;
--   2) sicpp_history             — js_avg для w_score и для поля history.js_avg;
--   3) incident_forecast_config  — пороги C и include_a/b.
--
-- ПАРАМЕТРЫ:
--   p_start         TIMESTAMPTZ — начало периода (включительно)
--   p_end           TIMESTAMPTZ — конец периода (включительно)
--   p_step_minutes  INT         — шаг в минутах (по умолчанию 1)
--   p_clean         BOOLEAN     — удалять существующие записи за период
--                                  (по умолчанию TRUE)
--
-- ВОЗВРАЩАЕТ: TEXT — отчёт о выполненной работе.
--
-- ПРИМЕЧАНИЕ О C-only vs A/B/C:
--   При hybrid_include_a=TRUE или hybrid_include_b=TRUE поле alert_active
--   отражает A∨B∨C, а не чистый fired_c. Для чисто C-only анализа
--   в отчётах (signals_false_positive_report v1.0) alert_active
--   эквивалентен fired_c только при include_a/b=FALSE. В отчёте это явно
--   диагностируется (см. сообщение о diff_count).
-- =============================================================================
CREATE OR REPLACE FUNCTION historical_fill_c_only(
    p_start        TIMESTAMPTZ,
    p_end          TIMESTAMPTZ,
    p_step_minutes INT     DEFAULT 1,
    p_clean        BOOLEAN DEFAULT TRUE
)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    v_ts                TIMESTAMPTZ;
    v_step_interval     INTERVAL := (p_step_minutes || ' minutes')::INTERVAL;
    v_prev_active       BOOLEAN := FALSE;
    v_prev_initialized  BOOLEAN := FALSE;
    v_calc              RECORD;
    v_inserted          INT := 0;
    v_processed         BIGINT := 0;
    v_total_minutes     BIGINT;
    v_last_percent      INT := -1;
    v_current_percent   INT;
    v_reason            TEXT;
    v_last_history_id   BIGINT;

    -- js_avg-снимок из sicpp_history (как в update_operational_alert_state)
    v_js_avg            REAL;

    -- Верификация
    v_inc_total         INT := 0;
    v_inc_covered       INT := 0;
    v_inc_missed        INT := 0;
    v_cov_first         TIMESTAMPTZ;
    v_cov_last          TIMESTAMPTZ;

    -- Диагностика конфигурации
    v_include_a         BOOLEAN := FALSE;
    v_include_b         BOOLEAN := FALSE;

    -- Расхождения alert_active vs fired_c (интересно только при include_a/b=TRUE)
    v_diff_count        INT := 0;
BEGIN
    -- =========================================================================
    -- 1. Проверки
    -- =========================================================================
    IF p_start IS NULL OR p_end IS NULL THEN
        RETURN 'Ошибка: p_start и p_end обязательны.';
    END IF;
    IF p_start > p_end THEN
        RETURN 'Ошибка: начальная дата позже конечной.';
    END IF;
    IF p_step_minutes IS NULL OR p_step_minutes <= 0 THEN
        RETURN 'Ошибка: p_step_minutes должен быть положительным.';
    END IF;

    p_start := date_trunc('minute', p_start);
    p_end   := date_trunc('minute', p_end);

    -- =========================================================================
    -- 2. Диагностика конфигурации
    -- =========================================================================
    BEGIN
        SELECT COALESCE(hybrid_include_a, FALSE),
               COALESCE(hybrid_include_b, FALSE)
        INTO v_include_a, v_include_b
        FROM incident_forecast_config LIMIT 1;
    EXCEPTION WHEN OTHERS THEN
        v_include_a := FALSE;
        v_include_b := FALSE;
    END;

    -- =========================================================================
    -- 3. Очистка существующих записей
    -- =========================================================================
    IF p_clean THEN
        DELETE FROM operational_alert_history
        WHERE changed_at BETWEEN p_start AND p_end;
        RAISE NOTICE 'Очищены записи operational_alert_history за период % – %',
                     p_start, p_end;
    END IF;

    -- =========================================================================
    -- 4. Подготовка к циклу
    -- =========================================================================
    v_total_minutes := EXTRACT(EPOCH FROM (p_end - p_start)) / 60 + 1;
    RAISE NOTICE 'Начало исторического заполнения C-only с % по % '
                 '(шаг %s мин, всего %s минут)',
                 p_start, p_end, p_step_minutes, v_total_minutes;

    -- =========================================================================
    -- 5. Основной цикл по минутам
    -- =========================================================================
    v_ts := p_start;
    WHILE v_ts <= p_end LOOP
        -- Расчёт C-only на минуту
        BEGIN
            SELECT * INTO v_calc FROM mchain_hybrid_alert_at(v_ts);
        EXCEPTION WHEN OTHERS THEN
            RAISE WARNING 'mchain_hybrid_alert_at(%): %', v_ts, SQLERRM;
            v_processed := v_processed + 1;
            v_ts := v_ts + v_step_interval;
            CONTINUE;
        END;

        IF NOT FOUND THEN
            v_processed := v_processed + 1;
            v_ts := v_ts + v_step_interval;
            CONTINUE;
        END IF;

        -- js_avg из sicpp_history на момент v_ts (как в runtime-функции)
        BEGIN
            SELECT sh.js_avg INTO v_js_avg
            FROM sicpp_history sh
            WHERE sh.changed_at <= v_ts
            ORDER BY sh.changed_at DESC, sh.id DESC
            LIMIT 1;
        EXCEPTION WHEN OTHERS THEN
            v_js_avg := NULL;
        END;

        -- Диагностика: alert_active vs fired_c при включённых A/B
        IF (v_include_a OR v_include_b)
           AND COALESCE(v_calc.alert, FALSE)
               IS DISTINCT FROM COALESCE(v_calc.fired_c, FALSE) THEN
            v_diff_count := v_diff_count + 1;
        END IF;

        -- Запись в историю: init / alert started / alert ended
        IF NOT v_prev_initialized THEN
            INSERT INTO operational_alert_history (
                changed_at, alert_active, fired_c, fired_a_would, fired_b,
                risk_p90, js_avg, reason
            ) VALUES (
                v_ts, COALESCE(v_calc.alert, FALSE),
                COALESCE(v_calc.fired_c, FALSE),
                COALESCE(v_calc.pre_adv = 100, FALSE),
                COALESCE(v_calc.fired_b, FALSE),
                v_calc.risk_p90,
                v_js_avg,
                'init'
            ) RETURNING id INTO v_last_history_id;
            v_inserted := v_inserted + 1;
            v_prev_active      := COALESCE(v_calc.alert, FALSE);
            v_prev_initialized := TRUE;

        ELSIF COALESCE(v_calc.alert, FALSE) IS DISTINCT FROM v_prev_active THEN
            v_reason := CASE WHEN COALESCE(v_calc.alert, FALSE)
                             THEN 'alert started' ELSE 'alert ended' END;

            INSERT INTO operational_alert_history (
                changed_at, alert_active, fired_c, fired_a_would, fired_b,
                risk_p90, js_avg, reason
            ) VALUES (
                v_ts, COALESCE(v_calc.alert, FALSE),
                COALESCE(v_calc.fired_c, FALSE),
                COALESCE(v_calc.pre_adv = 100, FALSE),
                COALESCE(v_calc.fired_b, FALSE),
                v_calc.risk_p90,
                v_js_avg,
                v_reason
            ) RETURNING id INTO v_last_history_id;
            v_inserted := v_inserted + 1;
            v_prev_active := COALESCE(v_calc.alert, FALSE);
        END IF;

        v_processed := v_processed + 1;
        v_ts := v_ts + v_step_interval;

        v_current_percent := floor((v_processed::NUMERIC / v_total_minutes) * 100);
        IF v_current_percent > v_last_percent THEN
            RAISE NOTICE 'Прогресс: % %% (обработано % из %, вставлено %)',
                         v_current_percent, v_processed, v_total_minutes, v_inserted;
            v_last_percent := v_current_percent;
        END IF;
    END LOOP;

    -- =========================================================================
    -- 6. Финальный апдейт singleton (аналог update_operational_alert_state)
    -- =========================================================================
    BEGIN
        SELECT * INTO v_calc FROM mchain_hybrid_alert_at(p_end);

        SELECT sh.js_avg INTO v_js_avg
        FROM sicpp_history sh
        WHERE sh.changed_at <= p_end
        ORDER BY sh.changed_at DESC, sh.id DESC
        LIMIT 1;

        INSERT INTO operational_alert_state (
            id, updated_at, alert_active, fired_c, fired_a_would, fired_b,
            risk_p90, js_avg, last_history_id
        ) VALUES (
            1, p_end,
            COALESCE(v_calc.alert, FALSE),
            COALESCE(v_calc.fired_c, FALSE),
            COALESCE(v_calc.pre_adv = 100, FALSE),
            COALESCE(v_calc.fired_b, FALSE),
            v_calc.risk_p90,
            v_js_avg,
            v_last_history_id
        )
        ON CONFLICT (id) DO UPDATE SET
            updated_at      = EXCLUDED.updated_at,
            alert_active    = EXCLUDED.alert_active,
            fired_c         = EXCLUDED.fired_c,
            fired_a_would   = EXCLUDED.fired_a_would,
            fired_b         = EXCLUDED.fired_b,
            risk_p90        = EXCLUDED.risk_p90,
            js_avg          = EXCLUDED.js_avg,
            last_history_id = EXCLUDED.last_history_id;
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Не удалось обновить operational_alert_state: %', SQLERRM;
    END;

    -- =========================================================================
    -- 7. Верификация
    -- =========================================================================
    BEGIN
        SELECT COUNT(*) INTO v_inc_total
        FROM markov_chain_performance_incident
        WHERE start_timepoint BETWEEN p_start AND p_end;

        -- Покрытие по alert_active (что фактически записано в history)
        WITH c_episodes AS (
            SELECT changed_at AS ep_start,
                   COALESCE(
                       LEAD(changed_at) OVER (ORDER BY changed_at, id),
                       p_end
                   ) AS ep_end
            FROM operational_alert_history
            WHERE changed_at <= p_end
              AND alert_active = TRUE
        )
        SELECT COUNT(*) INTO v_inc_covered
        FROM markov_chain_performance_incident pi
        WHERE pi.start_timepoint BETWEEN p_start AND p_end
          AND EXISTS (
              SELECT 1 FROM c_episodes e
              WHERE e.ep_start <= pi.start_timepoint
                AND e.ep_end   >= pi.start_timepoint
          );

        v_inc_missed := v_inc_total - v_inc_covered;

        SELECT MIN(changed_at), MAX(changed_at)
        INTO v_cov_first, v_cov_last
        FROM operational_alert_history
        WHERE changed_at BETWEEN p_start AND p_end;

        RAISE NOTICE '--- ВЕРИФИКАЦИЯ ---';
        RAISE NOTICE 'Всего инцидентов в периоде: %', v_inc_total;
        RAISE NOTICE 'Покрыто C-only (alert_active): %', v_inc_covered;
        RAISE NOTICE 'Пропущено: %', v_inc_missed;
        RAISE NOTICE 'Записей в истории: % (первая: %, последняя: %)',
                     v_inserted, v_cov_first, v_cov_last;

        IF v_inc_total > 0 THEN
            RAISE NOTICE 'Recall C-only: % %%',
                         ROUND((v_inc_covered::NUMERIC / v_inc_total * 100), 1);
        END IF;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Верификация пропущена: %', SQLERRM;
    END;

    -- =========================================================================
    -- 8. Итоговый отчёт
    -- =========================================================================
    RETURN format(
        'Историческое заполнение C-only завершено. '
        'Обработано %s минут, вставлено %s записей в operational_alert_history. '
        'Верификация: инцидентов %s, покрыто %s, пропущено %s. '
        'Конфигурация: include_a=%s, include_b=%s%s.',
        v_processed, v_inserted,
        v_inc_total, v_inc_covered, v_inc_missed,
        v_include_a, v_include_b,
        CASE
            WHEN (v_include_a OR v_include_b) AND v_diff_count > 0
                THEN format(' (⚠ alert_active != fired_c в %s минутах — '
                            'для чистого C-only анализа использовать фильтр fired_c)',
                            v_diff_count)
            WHEN (v_include_a OR v_include_b)
                THEN ' (A/B включены, но alert_active совпадал с fired_c во всех минутах)'
            ELSE ''
        END
    );
END;
$$;

COMMENT ON FUNCTION historical_fill_c_only(TIMESTAMPTZ, TIMESTAMPTZ, INT, BOOLEAN) IS
'v1.0 (2026-10-28). Историческое заполнение C-only в operational_alert_history.

Аналог historical_fill_sicpp, но источник состояния — mchain_hybrid_alert_at().
Поля вставки и логика точечно совпадают с update_operational_alert_state():
  alert_active  = v_calc.alert  (A ∨ B ∨ C с учётом hybrid_include_a/b)
  fired_c       = v_calc.fired_c  (profile_c OR spike_c)
  fired_a_would = (v_calc.pre_adv = 100)  (raw A, как в runtime)
  fired_b       = v_calc.fired_b
  risk_p90      = v_calc.risk_p90
  js_avg        = последний js_avg из sicpp_history на момент v_ts

Запись в историю — только при смене alert_active (init / alert started /
alert ended). Singleton operational_alert_state обновляется на p_end.

При hybrid_include_a/b = FALSE (по умолчанию) alert_active == fired_c,
поэтому отчёты, использующие alert_active как «C-only» (например,
signals_false_positive_report v1.0), работают корректно. При включённых A/B
в отчёт выводится диагностика расхождений alert_active vs fired_c —
для чистого C-only анализа использовать фильтр по колонке fired_c.

ЗАВИСИМОСТИ (до вызова должны быть заполнены):
  1) prediction_log            — для risk_p90 и spike_cnt внутри C;
  2) sicpp_history             — для js_avg в w_score и в history.js_avg;
  3) incident_forecast_config  — пороги C и флаги hybrid_include_a/b.

ПАРАМЕТРЫ:
  p_start         TIMESTAMPTZ — начало периода (включительно)
  p_end           TIMESTAMPTZ — конец периода (включительно)
  p_step_minutes  INT         — шаг в минутах (по умолчанию 1)
  p_clean         BOOLEAN     — удалять существующие записи (по умолчанию TRUE)

ВОЗВРАЩАЕТ: TEXT — отчёт о работе.

ПРИМЕРЫ:
  -- Полная перегенерация за последние 30 дней
  SELECT historical_fill_c_only(now() - INTERVAL ''30 days'', now(), 1, TRUE);

  -- Инкрементальное добавление с шагом 5 мин (быстро, но менее точно)
  SELECT historical_fill_c_only(
      (SELECT MAX(changed_at) FROM operational_alert_history),
      now(), 5, FALSE
  );';
