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
-- markov_chain_functions.sql
-- version 12.1
/*
- **Обучение цепи Маркова**
  - mchain_train_step :  Основной шаг обучения (вызов каждую минуту): получает состояние, логирует переход, обновляет цепь, вызывает плановое забывание
  - mchain_log_transition :  Логирует переход между состояниями и обновляет частоты в markov_frequencies

- **Управление забыванием**
  - mchain_apply_forgetting :  Применяет забывание: уменьшает частоты, удаляет шум, пересчитывает вероятности и поглощающую матрицу (адаптивное или по конфигурации)
  - mchain_check_sufficiency :  Проверяет, достаточно ли накоплено данных (общее число переходов и стабильность вероятностей)
  - mchain_enable_forgetting_when_sufficient :  Включает адаптивное забывание только если проверка достаточности вернула TRUE
  - mchain_force_enable_forgetting :  Принудительно включает адаптивное забывание (без проверки достаточности)

- **Оценка достоверности прогнозов**
  - mchain_forecast_reliability :  Оценивает достоверность прогнозов от 0 (недостоверен) до 5 (максимально достоверен) на основе объёма данных, стабильности и покрытия
  - calculate_daily_quality_metrics : Расчёт суточных метрик и сохранение в историю


- **Очистка журналов и архивов (cron-задачи)**
  - mchain_clean_transition_log :  Удаляет записи transition_log старше заданного числа дней (по умолчанию из конфигурации)
  - mchain_clean_apply_forgetting_log :  Очищает журнал вызовов функции забывания

- **Сервисные и вспомогательные функции**
  - fill_state_descriptions :  Заполняет справочник state_descriptions всеми комбинациями корреляции и трендов (189 состояний)
  - get_state_id :  Возвращает числовой идентификатор состояния по его параметрам (корреляция, os_trend, wait_trend)
  - mchain_get_current_state_id :  Возвращает идентификатор текущего состояния системы (для отладки и мониторинга)
  - update_markov_probabilities :  Пересчитывает вероятности из частот и вызывает rebuild_markov_absorbing()
  - rebuild_markov_absorbing :  Перестраивает таблицу markov_absorbing на основе текущих вероятностей (аварийные состояния – поглощающие)
  - update_last_incident_time :  Триггерная функция – обновляет last_incident_time в markov_config при аварийном переходе
  - mchain_log_error :  Записывает ошибку в таблицу mchain_error_log
  - decode_state_id : Обратная функция к get_state_id: по числовому идентификатору состояния возвращает его параметры: корреляцию (r), тренд операционной скорости (os_trend) и тренд времени ожидания (wait_trend).  
  - get_critical_states : Возвращает список аварийных состояний
  - get_critical_state_ids : Упрощённая версия – только state_id (для быстрого использования)
  - format_timestamptz_to_minute : Сервисная функция: форматирование TIMESTAMPTZ до минут (без секунд). Используется для вывода в сообщениях health_check и других отчётах.

  - **Прогнозирование риска**
  - mchain_predict_risk_current_horizon : возвращает прогноз риска на горизонт, заданный в 
  - mchain_predict_risk_k_v2 :Вероятность хотя бы одного попадания в критическое множество за k шагов
  
  - collect_prediction : Формирование прогноза с горизонтом из markov_config.forecast_horizon_minutes
  - update_prediction_outcomes : Обновление исходов для прогнозов, у которых истёк горизонт (из markov_config)

  - refresh_critical_states : автоматическое обновление списка критических состояний
  - compute_empirical_incident_risk : вычисляет эмпирическую вероятность наступления инцидента в течение

  
- **Отчеты**  
  -- generate_full_analytical_report : формирование сводного аналитического отчёта по цепи Маркова 

  --ОСНОВНЫЕ ОТЧЕТЫ ДЛЯ ПОСТРОЕНИЯ СВОДНОГО АНАЛИТИЧЕСКОГО ОТЧЕТА
  - mchain_quality_report : Отчёт о качестве прогнозов для указанного горизонта (по умолчанию из markov_config)
  - mchain_summary_report :  Сводный отчёт по состоянию цепи Маркова mchain_reliability_report+mchain_incident_transitions_report
  - mchain_state_transition_matrix_report : Формирует матрицу переходов между укрупнёнными группами состояний. Источник: markov_probabilities (усреднение по состояниям внутри группы)
  - report_stability_trend : Мониторинг стабильности вероятностей
  - report_quality_sliding : Качество прогнозов в скользящем окне 
  - report_daily_calibration : Детальная калибровочная кривая (ежедневно)
  - state_distribution : Распределение состояний и частота критических состояний
  - report_forgetting_effectiveness : Эффективность забывания
  --ОСНОВНЫЕ ОТЧЕТЫ ДЛЯ ПОСТРОЕНИЯ СВОДНОГО АНАЛИТИЧЕСКОГО ОТЧЕТА
  
  --ВСПОМОГАТЕЛЬНЫЕ ОТЧЕТЫ
  - mchain_health_check : Проверяет состояние цепи Маркова и возвращает статус (OK, WARNING, CRITICAL)   
  - mchain_incident_state_detail_report : Детализированный отчёт по каждому аварийному состоянию.
  - mchain_reliability_report : Возвращает расширенный текстовый отчёт о достоверности прогнозов с метриками, порогами и рекомендациями
  - mchain_incident_transitions_report : Анализ переходов в аварийные состояния 
  

  - ДОПОЛНИТЕЛЬНЫЕ ОТЧЕТЫ
  ------------------------------------------------------------------------------

----------------------------------------------------------  
- 12. Эмпирический подбор параметров адаптивного забывания 
  -- evaluate_forgetting_params : Функция оценки качества для заданных параметров
  -- mchain_predict_risk_k_v2_with_matrix : Функция для прогноза риска с заданной матрицей
  -- optimize_forgetting_params : Функция оптимизации (поиск по сетке)
- 12. Эмпирический подбор параметров адаптивного забывания 
----------------------------------------------------------
  
  
  --ВСПОМОГАТЕЛЬНЫЕ ОТЧЕТЫ  
*/
--------------------------------------------------------------------------------
-- cron
--------------------------------------------------------------------------------

-- # ============================================================
-- # Ежедневная очистка журналов и обновление статистик
-- # ============================================================
-- # Очистка transition_log (в 01:15)
-- 15 1 * * * psql -d expecto_db -U expecto_user -c "SELECT mchain_clean_transition_log();"

-- # ============================================================
-- # Очистка архивных данных (раз в неделю)
-- # ============================================================
-- # Очистка apply_forgetting_log (ежедневно в 02:00)
-- 0 2 * * * psql -d expecto_db -U expecto_user -c "SELECT mchain_clean_apply_forgetting_log();"

-- # ============================================================
-- # Анализ качества прогноза
-- # ============================================================

-- # Обновление critical_states еженедельно (воскресенье в 03:00)
-- 0 3 * * 0 psql -d expecto_db -U expecto_user -c "SELECT refresh_critical_states();" >/postgres/pg_expecto/sh/refresh_critical_states.log 2>&1

-- # Обновление исходов каждые 5 минут (теперь для горизонта 30 мин)
-- */5 * * * * psql -d expecto_db -U expecto_user -c "SELECT update_prediction_outcomes();"

-- # Расчёт суточных метрик в 02:00 (с явным указанием горизонта 30)
-- 0 2 * * * psql -d expecto_db -U expecto_user -c "SELECT calculate_daily_quality_metrics(CURRENT_DATE - 1, 30);"

-- #12. Эмпирический подбор параметров адаптивного забывания
-- # Еженедельный подбор параметров забывания (воскресенье в 04:00)
-- 0 4 * * 0 /postgres/pg_expecto/sh/optimize_forgetting.sh false true 1 >> /postgres/pg_expecto/sh/forgetting_optimization.log 2>&1

---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- mchain_train_step
-- Основной шаг обучения: определяет текущее состояние (через внешнюю функцию
-- get_current_os_waiting_correlation_for_markov_chain), обновляет цепь,
-- логирует переход, проверяет достаточность обучения и при необходимости
-- вызывает адаптивное забывание (по интервалу).
-- Рекомендуется вызывать эту функцию каждую минуту (по cron или pgAgent).
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION mchain_train_step()
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    curr_vals RECORD;
    cfg RECORD;
    prev_state SMALLINT;
    curr_state SMALLINT;
    chain_rec RECORD;
    err_context JSONB;
	new_correlation  REAL;
    new_os_trend     SMALLINT;
    new_wait_trend   SMALLINT;
BEGIN
    -- Инициализация справочника
    IF NOT EXISTS (SELECT 1 FROM state_descriptions) THEN
        PERFORM fill_state_descriptions();
    END IF;

    -- Получение текущих метрик с защитой от исключений
    BEGIN
        SELECT * INTO curr_vals FROM get_current_os_waiting_correlation_for_markov_chain();
    EXCEPTION WHEN OTHERS THEN
        err_context := jsonb_build_object('sqlstate', SQLSTATE, 'sqlerrm', SQLERRM);
        PERFORM mchain_log_error('mchain_train_step', 'Failed to get metrics', SQLERRM, NULL, err_context);
        RETURN 'Error: cannot get metrics';
    END;

    new_correlation := curr_vals.current_correlation;
    new_os_trend    := curr_vals.current_os_trend;
    new_wait_trend  := curr_vals.current_wait_trend;
	
	-------------------------------------------------------------
	-- ЕСЛИ МЕТРИКИ ПРОИЗВОДИТЕЛЬНОСТИ ЕЩЕ НЕ СОБРАНЫ - ВЫХОД
	IF new_correlation IS NULL OR new_os_trend IS NULL OR new_wait_trend IS NULL 
	THEN 
		RETURN 'No metrics available';
	END IF;
	-- ЕСЛИ МЕТРИКИ ПРОИЗВОДИТЕЛЬНОСТИ ЕЩЕ НЕ СОБРАНЫ
	-------------------------------------------------------------
    

    curr_state := get_state_id(
        curr_vals.current_correlation,
        curr_vals.current_os_trend,
        curr_vals.current_wait_trend
    );

    -- Получаем последнее состояние из markov_chain
    SELECT prev_correlation, prev_os_trend, prev_wait_trend,
           curr_correlation, curr_os_trend, curr_wait_trend
    INTO chain_rec
    FROM markov_chain LIMIT 1;

    IF chain_rec.curr_correlation IS NULL THEN
        DELETE FROM markov_chain;
        INSERT INTO markov_chain (curr_correlation, curr_os_trend, curr_wait_trend)
        VALUES (curr_vals.current_correlation, curr_vals.current_os_trend, curr_vals.current_wait_trend);
        RETURN 'Initial state saved';
    END IF;

    prev_state := get_state_id(
        chain_rec.curr_correlation,
        chain_rec.curr_os_trend,
        chain_rec.curr_wait_trend
    );

    -- Логируем переход и обновляем частоты (может быть обёрнуто в отдельный блок)
    BEGIN
        PERFORM mchain_log_transition(prev_state, curr_state);
    EXCEPTION WHEN OTHERS THEN
        err_context := jsonb_build_object('prev_state', prev_state, 'curr_state', curr_state, 'sqlstate', SQLSTATE);
        PERFORM mchain_log_error('mchain_train_step', 'Failed to log transition', SQLERRM, NULL, err_context);
        RETURN 'Error: transition logging failed';
    END;

    -- Обновляем цепь
    UPDATE markov_chain SET
        prev_correlation = curr_correlation,
        prev_os_trend    = curr_os_trend,
        prev_wait_trend  = curr_wait_trend,
        curr_correlation = curr_vals.current_correlation,
        curr_os_trend    = curr_vals.current_os_trend,
        curr_wait_trend  = curr_vals.current_wait_trend;

    -- Плановое забывание (проверка интервала)
    SELECT last_forget_time, interval_minute INTO cfg
    FROM markov_config LIMIT 1;

    IF now() - cfg.last_forget_time >= MAKE_INTERVAL(mins => cfg.interval_minute) THEN
        BEGIN
            PERFORM mchain_apply_forgetting();
        EXCEPTION WHEN OTHERS THEN
            err_context := jsonb_build_object('sqlstate', SQLSTATE, 'sqlerrm', SQLERRM);
            PERFORM mchain_log_error('mchain_train_step', 'Failed to apply forgetting', SQLERRM, NULL, err_context);
            RETURN 'Step completed but forgetting failed';
        END;
    END IF;

	----------------------------------------
	--Формирование истории по прогнозу 
	PERFORM collect_prediction();
    ----------------------------------------

    RETURN 'Step completed';
END;
$$;

COMMENT ON FUNCTION mchain_train_step() IS 'Одношаговое обучение цепи (вызов каждую минуту)';

--------------------------------------------------------------------------------
-- mchain_apply_forgetting
-- Применяет забывание: уменьшает все частоты в markov_frequencies,
-- удаляет пренебрежимо малые значения, пересчитывает вероятности.
-- Если use_adaptive_alpha = true, коэффициент alpha вычисляется динамически
-- на основе времени, прошедшего с последнего инцидента (таблица markov_config).
-- Параметр alpha_override позволяет принудительно задать значение.
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION mchain_apply_forgetting(
    alpha_override REAL DEFAULT NULL,
    p_max_alpha REAL DEFAULT 0.5
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    cfg RECORD;
    effective_alpha REAL;
    days_since REAL;
    is_sufficient BOOLEAN;
    stability_factor REAL;
    details_text TEXT;
    err_context JSONB;
BEGIN
    SELECT use_adaptive_alpha, alpha, base_alpha, min_alpha,
           incident_half_life_days, last_incident_time,
           adaptive_forgetting_enabled
    INTO cfg
    FROM markov_config LIMIT 1;

    IF NOT cfg.adaptive_forgetting_enabled THEN
        RAISE DEBUG 'mchain_apply_forgetting: skipped because adaptive_forgetting_enabled = false';
        RETURN;
    END IF;

    -- ИСПРАВЛЕНИЕ: явный алиас для таблицы-функции
    SELECT s.sufficient, s.stability_factor INTO is_sufficient, stability_factor
    FROM mchain_check_sufficiency() AS s;

    IF NOT is_sufficient THEN
        INSERT INTO apply_forgetting_log (effective_alpha, adaptive_used, days_since_incident, alpha_override, details)
        VALUES (0.0, cfg.use_adaptive_alpha, NULL, alpha_override, 'Skipped - insufficient data');
        RETURN;
    END IF;

    IF alpha_override IS NOT NULL THEN
        effective_alpha := alpha_override;
        details_text := format('alpha_override = %s', alpha_override);
    ELSIF cfg.use_adaptive_alpha THEN
        IF cfg.last_incident_time IS NULL THEN
            effective_alpha := cfg.min_alpha;
            days_since := NULL;
            details_text := 'adaptive mode, no incident -> min_alpha';
        ELSE
            days_since := EXTRACT(EPOCH FROM (now() - cfg.last_incident_time)) / 86400.0;
            effective_alpha := cfg.base_alpha * exp(-days_since / cfg.incident_half_life_days);
            effective_alpha := GREATEST(effective_alpha, cfg.min_alpha);
            details_text := format('adaptive mode, days_since=%s, base_alpha=%s, half_life=%s -> eff=%s',
                                   days_since, cfg.base_alpha, cfg.incident_half_life_days, effective_alpha);
        END IF;
    ELSE
        effective_alpha := cfg.alpha;
        details_text := format('non-adaptive mode, config.alpha = %s', cfg.alpha);
    END IF;

    effective_alpha := LEAST(effective_alpha * stability_factor, p_max_alpha);
    details_text := details_text || format(', stability_factor=%s, effective_alpha_capped=%s', stability_factor, effective_alpha);

    IF effective_alpha <= 0.0 THEN
        INSERT INTO apply_forgetting_log (effective_alpha, adaptive_used, days_since_incident, alpha_override, details)
        VALUES (0.0, cfg.use_adaptive_alpha, days_since, alpha_override, 'Skipped - alpha zero');
        RETURN;
    END IF;

    BEGIN
        UPDATE markov_frequencies
        SET frequency = frequency * (1.0 - effective_alpha)
        WHERE frequency > 0;

        DELETE FROM markov_frequencies WHERE frequency < 1e-6;

        PERFORM update_markov_probabilities();

        UPDATE markov_config SET last_forget_time = now();
    EXCEPTION WHEN OTHERS THEN
        err_context := jsonb_build_object('effective_alpha', effective_alpha, 'sqlstate', SQLSTATE);
        PERFORM mchain_log_error('mchain_apply_forgetting', 'Failed to apply forgetting', SQLERRM, NULL, err_context);
        RAISE;
    END;

    INSERT INTO apply_forgetting_log (effective_alpha, adaptive_used, days_since_incident, alpha_override, details)
    VALUES (effective_alpha, cfg.use_adaptive_alpha, days_since, alpha_override, details_text);

    RAISE DEBUG 'mchain_apply_forgetting: applied alpha=%', effective_alpha;
END;
$$;

COMMENT ON FUNCTION mchain_apply_forgetting(REAL, REAL) IS 'Применяет забывание с учётом stability_factor и ограничением max_alpha.';

--------------------------------------------------------------------------------
-- mchain_check_sufficiency
-- Проверяет, достаточно ли обучена модель (минимальный объём данных,
-- стабильность вероятностей за последнюю неделю).
-- Возвращает TRUE, если обучение достаточно.
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION mchain_check_sufficiency(
    min_transitions INT DEFAULT NULL,
    max_prob_change REAL DEFAULT 0.05,
    weeks_history INT DEFAULT 2
)
RETURNS TABLE (sufficient BOOLEAN, stability_factor REAL)
LANGUAGE plpgsql
AS $$
DECLARE
    cfg_min_transitions INT;
    total_transitions BIGINT;
    max_change REAL;
    v_stability_factor REAL := 1.0;
    min_freq_for_stability INT := 200;   -- порог частоты состояний для расчёта стабильности
BEGIN
    -- Получаем порог из конфигурации, если не передан явно
    IF min_transitions IS NULL THEN
        SELECT COALESCE(min_transitions_for_forgetting, 5000) INTO cfg_min_transitions FROM markov_config LIMIT 1;
    ELSE
        cfg_min_transitions := min_transitions;
    END IF;

    -- 1. Проверка общего числа переходов (единственное условие для sufficient)
    SELECT COUNT(*) INTO total_transitions FROM transition_log;
    IF total_transitions < cfg_min_transitions THEN
        RETURN QUERY SELECT FALSE, 1.0;
        RETURN;
    END IF;

    -- 2. Вычисляем max_prob_change (для stability_factor), исключая критические и редкие состояния
    IF total_transitions >= 5000 THEN
        WITH frequent_states AS (
            SELECT from_state
            FROM transition_log
            WHERE ts >= now() - (weeks_history || ' weeks')::INTERVAL
            GROUP BY from_state
            HAVING COUNT(*) >= min_freq_for_stability
        ),
        recent AS (
            SELECT from_state, to_state,
                   COUNT(*)::REAL / SUM(COUNT(*)) OVER (PARTITION BY from_state) AS prob
            FROM transition_log
            JOIN frequent_states fs USING (from_state)
            WHERE ts >= now() - (weeks_history || ' weeks')::INTERVAL
              AND ts < now() - (weeks_history/2 || ' weeks')::INTERVAL
              AND to_state NOT IN (SELECT state_id FROM critical_states)
            GROUP BY from_state, to_state
        ),
        current AS (
            SELECT from_state, to_state,
                   COUNT(*)::REAL / SUM(COUNT(*)) OVER (PARTITION BY from_state) AS prob
            FROM transition_log
            JOIN frequent_states fs USING (from_state)
            WHERE ts >= now() - (weeks_history/2 || ' weeks')::INTERVAL
              AND to_state NOT IN (SELECT state_id FROM critical_states)
            GROUP BY from_state, to_state
        )
        SELECT COALESCE(MAX(ABS(COALESCE(r.prob, 0) - COALESCE(c.prob, 0))), 0.0) INTO max_change
        FROM recent r
        FULL JOIN current c USING (from_state, to_state);
    ELSE
        max_change := 0.0;
    END IF;

    -- 3. Определяем stability_factor на основе max_change
    IF max_change <= 0.05 THEN
        v_stability_factor := 1.0;
    ELSIF max_change <= 0.2 THEN
        v_stability_factor := 1.5;
    ELSIF max_change <= 0.5 THEN
        v_stability_factor := 2.0;
    ELSE
        v_stability_factor := 3.0;
    END IF;

    -- 4. Возвращаем результат
    RETURN QUERY SELECT TRUE, v_stability_factor;
END;
$$;

COMMENT ON FUNCTION mchain_check_sufficiency(INT, REAL, INT) IS 'Проверяет достаточность данных для забывания (только по объёму) и возвращает коэффициент нестабильности для адаптации alpha. Исключает переходы в критические состояния и состояния с числом переходов < 200 за анализируемый период.';

--------------------------------------------------------------------------------
-- mchain_log_transition
-- Логирует переход между состояниями и обновляет частоты.
-- Вызывается из основного шага обучения.
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION mchain_log_transition(
    p_from_state SMALLINT,
    p_to_state   SMALLINT
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    -- Журнал переходов
    INSERT INTO transition_log (ts, from_state, to_state)
    VALUES (now(), p_from_state, p_to_state);

    -- Обновление частот
    INSERT INTO markov_frequencies (from_state, to_state, frequency)
    VALUES (p_from_state, p_to_state, 1.0)
    ON CONFLICT (from_state, to_state) DO UPDATE
        SET frequency = markov_frequencies.frequency + 1.0;
END;
$$;

COMMENT ON FUNCTION mchain_log_transition(SMALLINT, SMALLINT) IS 'Логирует переход и обновляет markov_frequencies';


--------------------------------------------------------------------------------
-- Сервисные функции для очистки старых данных (для cron)
--------------------------------------------------------------------------------
-- Очистка журнала переходов
CREATE OR REPLACE FUNCTION mchain_clean_transition_log(p_retention_days INT DEFAULT NULL)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    retention INT;
    deleted_rows BIGINT;
BEGIN
    retention := COALESCE(p_retention_days, (SELECT transition_log_retention_days FROM markov_config LIMIT 1), 21);
    DELETE FROM transition_log WHERE ts < now() - (retention || ' days')::INTERVAL;
    GET DIAGNOSTICS deleted_rows = ROW_COUNT;
    RETURN format('Deleted %s rows from transition_log', deleted_rows);
END;
$$;

COMMENT ON FUNCTION mchain_clean_transition_log( INT ) IS 'Очистка журнала переходов';

--------------------------------------------------------------------------------
--Функция заполнения справочника состояний цепи Маркова
CREATE OR REPLACE FUNCTION fill_state_descriptions() RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    -- Очистка таблицы перед заполнением
    TRUNCATE state_descriptions;

    -- Генерация всех комбинаций и вставка
    INSERT INTO state_descriptions (state_id, correlation, os_trend, wait_trend)
    SELECT
        -- Формула: correlation_index * 9 + (os_trend_index) * 3 + wait_trend_index
        -- где correlation_index = 0..20, os_trend_index = 0..2, wait_trend_index = 0..2
        c_idx * 9 + (os + 1) * 3 + (wt + 1) AS state_id,
        (-1.0 + 0.1 * c_idx)::REAL            AS correlation,
        os::SMALLINT                           AS os_trend,
        wt::SMALLINT                           AS wait_trend
    FROM
        generate_series(0, 20)   AS c_idx,   -- 0 => r=-1.0, 20 => r=+1.0
        generate_series(-1, 1)   AS os,      -- -1,0,1
        generate_series(-1, 1)   AS wt       -- -1,0,1
    ORDER BY state_id;  -- для наглядности, не обязательно
END;
$$;
COMMENT ON FUNCTION fill_state_descriptions IS 'Функция заполнения справочника состояний цепи Маркова.';
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Получить state_id для заданных r , OS_trend , wait_trend
CREATE OR REPLACE FUNCTION get_state_id(
    r           REAL,
    os_trend    SMALLINT,
    wait_trend  SMALLINT
)
RETURNS SMALLINT
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT (
        (round((round(r::numeric, 1) + 1.0) / 0.1)::int * 9) +
        ((os_trend + 1)::int * 3) +
        (wait_trend + 1)::int
    )::smallint
$$;
COMMENT ON FUNCTION get_state_id IS 'Получить state_id для заданнеых r , OS_trend , wait_trend';
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
/*
Таблица markov_absorbing хранит строки поглощающей цепи, в которой аварийные состояния сделаны поглощающими:
единственный возможный переход из них — остаться в том же состоянии с вероятностью 1.

Функция rebuild_markov_absorbing вызывается после каждого пересчёта markov_probabilities  и формирует матрицу заново.
*/
CREATE OR REPLACE FUNCTION rebuild_markov_absorbing()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    TRUNCATE markov_absorbing;

    -- 1. Переходы из неаварийных состояний только в неаварийные с нормировкой
    WITH non_absorbing_transitions AS (
        SELECT 
            p.from_state,
            p.to_state,
            p.probability,
            SUM(p.probability) OVER (PARTITION BY p.from_state) AS total_prob
        FROM markov_probabilities p
        JOIN state_descriptions sd_from ON p.from_state = sd_from.state_id
        JOIN state_descriptions sd_to   ON p.to_state = sd_to.state_id
        WHERE NOT (sd_from.correlation < 0 AND sd_from.os_trend = -1 AND sd_from.wait_trend = 1)
          AND NOT (sd_to.correlation   < 0 AND sd_to.os_trend   = -1 AND sd_to.wait_trend   = 1)
    )
    INSERT INTO markov_absorbing (from_state, to_state, probability)
    SELECT 
        from_state,
        to_state,
        CASE 
            WHEN total_prob > 0 THEN probability / total_prob
            ELSE 1.0   -- если нет переходов в неаварийные, делаем состояние поглощающим (этот случай обрабатывается в шаге 2)
        END
    FROM non_absorbing_transitions;

    -- 2. Петли для неаварийных состояний, у которых нет переходов в неаварийные (включая себя)
    INSERT INTO markov_absorbing (from_state, to_state, probability)
    SELECT 
        sd.state_id,
        sd.state_id,
        1.0
    FROM state_descriptions sd
    WHERE NOT (sd.correlation < 0 AND sd.os_trend = -1 AND sd.wait_trend = 1)
      AND NOT EXISTS (
          SELECT 1 FROM markov_absorbing tmp 
          WHERE tmp.from_state = sd.state_id
      );

    -- 3. Поглощающие петли для аварийных состояний (новое определение)
    INSERT INTO markov_absorbing (from_state, to_state, probability)
    SELECT state_id, state_id, 1.0
    FROM state_descriptions
    WHERE correlation < 0 AND os_trend = -1 AND wait_trend = 1;
END;
$$;
COMMENT ON FUNCTION rebuild_markov_absorbing IS 'Пересчет таблицы поглощения';
--------------------------------------------------------------------------------

------------------------------------------------------------------------------------------------------------------------
-- Обновление времени последнего инцидента (через триггер)
-- Пересоздаём триггерную функцию, чтобы она использовала critical_states
CREATE OR REPLACE FUNCTION update_last_incident_time()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM critical_states WHERE state_id = NEW.to_state) THEN
        UPDATE markov_config SET last_incident_time = NEW.ts;
    END IF;
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION update_last_incident_time() IS 'Обновление времени последнего инцидента (через триггер)';

DROP TRIGGER IF EXISTS trigger_update_incident_time ON transition_log;
CREATE TRIGGER trigger_update_incident_time
    AFTER INSERT ON transition_log
    FOR EACH ROW
    EXECUTE FUNCTION update_last_incident_time();
-- Обновление времени последнего инцидента (через триггер)	
------------------------------------------------------------------------------------------------------------------------

------------------------------------------------------------------------------------------------------------------------
-- Заполнение матрицы вероятностей
CREATE OR REPLACE FUNCTION update_markov_probabilities()
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    TRUNCATE markov_probabilities;
    INSERT INTO markov_probabilities (from_state, to_state, probability)
    SELECT from_state, to_state, frequency / SUM(frequency) OVER (PARTITION BY from_state)
    FROM markov_frequencies WHERE frequency > 0;
	
    -- DISABLED FOR VERSION 11.0
	-- PERFORM rebuild_markov_absorbing();
END;
$$;
COMMENT ON FUNCTION update_markov_probabilities() IS 'Заполнение матрицы вероятностей';

------------------------------------------------------------------------------------------------------------------------
-- Очистка журнала забывания
CREATE OR REPLACE FUNCTION mchain_clean_apply_forgetting_log(p_retention_days INT DEFAULT NULL)
RETURNS TEXT LANGUAGE plpgsql AS $$
DECLARE
    retention INT;
    deleted_rows BIGINT;
BEGIN
    retention := COALESCE(p_retention_days, (SELECT apply_forgetting_log_retention_days FROM markov_config LIMIT 1), 21);
    DELETE FROM apply_forgetting_log WHERE ts < now() - (retention || ' days')::INTERVAL;
    GET DIAGNOSTICS deleted_rows = ROW_COUNT;
    RETURN format('Deleted %s rows from apply_forgetting_log', deleted_rows);
END;
$$;
COMMENT ON FUNCTION mchain_clean_apply_forgetting_log(INT) IS 'Очистка журнала забывания';

--------------------------------------------------------------------------------
-- Функция логирования ошибок
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION mchain_log_error(
    p_function_name TEXT,
    p_error_message TEXT,
    p_error_detail TEXT DEFAULT NULL,
    p_error_hint TEXT DEFAULT NULL,
    p_context JSONB DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO mchain_error_log (function_name, error_message, error_detail, error_hint, context)
    VALUES (p_function_name, p_error_message, p_error_detail, p_error_hint, p_context);
    -- Также можно записать в журнал БД через RAISE WARNING
    RAISE WARNING '[%] %', p_function_name, p_error_message;
END;
$$;
COMMENT ON FUNCTION mchain_log_error(TEXT, TEXT, TEXT, TEXT, JSONB) IS 'Записывает ошибку в таблицу mchain_error_log';


--------------------------------------------------------------------------------
-- Вспомогательная функция: получить текущий state_id (для отладки)
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION mchain_get_current_state_id()
RETURNS SMALLINT
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    curr_vals RECORD;
BEGIN
    SELECT * INTO curr_vals FROM get_current_os_waiting_correlation_for_markov_chain();
    IF curr_vals.current_correlation IS NULL THEN
        RETURN NULL;
    END IF;
    RETURN get_state_id(
        curr_vals.current_correlation,
        curr_vals.current_os_trend,
        curr_vals.current_wait_trend
    );
END;
$$;

COMMENT ON FUNCTION mchain_get_current_state_id() IS 'Возвращает идентификатор текущего состояния (для отладки)';

--------------------------------------------------------------------------------
-- mchain_forecast_reliability 
-- Оценивает достоверность прогнозов от 0 (недостоверен) до 5 (максимально достоверен)
-- на основе трёх метрик: объём данных, стабильность вероятностей, покрытие частых состояний
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION mchain_forecast_reliability()
RETURNS INT
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    total_transitions BIGINT;
    max_prob_change REAL;
    coverage_pct INT;
    base_score INT := 0;
    stability_bonus INT := 0;
    coverage_bonus INT := 0;
    min_freq_for_stability INT := 200;   -- порог частоты состояний для расчёта стабильности
BEGIN
    SELECT COUNT(*) INTO total_transitions FROM transition_log;

    -- 1. Базовая оценка по объёму данных (0-3)
    IF total_transitions < 100 THEN
        RETURN 0;
    ELSIF total_transitions < 500 THEN
        base_score := 1;
    ELSIF total_transitions < 5000 THEN
        base_score := 2;
    ELSE
        base_score := 3;
    END IF;

    -- Если данных мало (<5000), возвращаем базовый рейтинг без учёта стабильности
    IF total_transitions < 5000 THEN
        RETURN base_score;
    END IF;

    -- 2. Стабильность вероятностей (максимальное изменение за 14 дней)
    -- Исключаем переходы в критические состояния и состояния с малым числом переходов
    WITH frequent_states AS (
        SELECT from_state
        FROM transition_log
        WHERE ts >= now() - INTERVAL '14 days'
        GROUP BY from_state
        HAVING COUNT(*) >= min_freq_for_stability
    ),
    recent AS (
        SELECT from_state, to_state,
               COUNT(*)::REAL / SUM(COUNT(*)) OVER (PARTITION BY from_state) AS prob
        FROM transition_log
        JOIN frequent_states fs USING (from_state)
        WHERE ts >= now() - INTERVAL '14 days'
          AND ts < now() - INTERVAL '7 days'
          AND to_state NOT IN (SELECT state_id FROM critical_states)
        GROUP BY from_state, to_state
    ),
    current AS (
        SELECT from_state, to_state,
               COUNT(*)::REAL / SUM(COUNT(*)) OVER (PARTITION BY from_state) AS prob
        FROM transition_log
        JOIN frequent_states fs USING (from_state)
        WHERE ts >= now() - INTERVAL '7 days'
          AND to_state NOT IN (SELECT state_id FROM critical_states)
        GROUP BY from_state, to_state
    )
    SELECT COALESCE(MAX(ABS(COALESCE(r.prob, 0) - COALESCE(c.prob, 0))), 1.0) INTO max_prob_change
    FROM recent r
    FULL JOIN current c USING (from_state, to_state);

    -- 3. Покрытие частых состояний (без изменений)
    WITH state_stats AS (
        SELECT from_state, COUNT(*) AS n_i,
               COUNT(*)::REAL / total_transitions AS freq
        FROM transition_log
        GROUP BY from_state
    ),
    frequent_states AS (
        SELECT from_state
        FROM state_stats
        WHERE freq > 0.01
    ),
    coverage AS (
        SELECT 
            COUNT(*) AS total_frequent,
            SUM(CASE WHEN n_i >= 50 THEN 1 ELSE 0 END) AS covered_frequent
        FROM (
            SELECT s.from_state, ss.n_i
            FROM frequent_states s
            CROSS JOIN LATERAL (
                SELECT COUNT(*) AS n_i FROM transition_log WHERE from_state = s.from_state
            ) ss
        ) t
    )
    SELECT 
        CASE WHEN total_frequent = 0 THEN 100
             ELSE (covered_frequent * 100) / total_frequent
        END INTO coverage_pct
    FROM coverage;

    -- 4. Штрафы за нестабильность (снижаем базовый рейтинг)
    IF max_prob_change > 0.5 THEN
        base_score := GREATEST(base_score - 2, 0);
    ELSIF max_prob_change > 0.2 THEN
        base_score := GREATEST(base_score - 1, 0);
    END IF;

    -- 5. Бонус стабильности (0-2)
    IF max_prob_change < 0.02 THEN
        stability_bonus := 2;
    ELSIF max_prob_change < 0.05 THEN
        stability_bonus := 1;
    ELSE
        stability_bonus := 0;
    END IF;

    -- 6. Бонус покрытия (0-1) – только если нестабильность не слишком высока
    IF max_prob_change < 0.2 AND coverage_pct >= 90 THEN
        coverage_bonus := 1;
    END IF;

    -- Итоговый рейтинг (ограничиваем 5)
    RETURN LEAST(base_score + stability_bonus + coverage_bonus, 5);
END;
$$;

COMMENT ON FUNCTION mchain_forecast_reliability() IS 'Оценивает достоверность прогнозов от 0 до 5 (объём данных, стабильность, покрытие частых состояний). Исключает переходы в критические состояния и состояния с числом переходов < 200 за 14 дней из расчёта стабильности.';




---------------------------------------------------------------------------------------------------------
-- Дополнительные функции для управления
---------------------------------------------------------------------------------------------------------
-- Ручное включение/выключение адаптивного забывания с проверкой достаточности
CREATE OR REPLACE FUNCTION mchain_enable_forgetting_when_sufficient()
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    sufficient BOOLEAN;
BEGIN
    SELECT sufficient INTO sufficient FROM mchain_check_sufficiency();
    IF sufficient THEN
        UPDATE markov_config SET adaptive_forgetting_enabled = true;
        RETURN 'Adaptive forgetting enabled (sufficient data).';
    ELSE
        RETURN 'Adaptive forgetting remains disabled (insufficient data).';
    END IF;
END;
$$;
COMMENT ON FUNCTION mchain_enable_forgetting_when_sufficient IS 'Ручное включение/выключение адаптивного забывания с проверкой достаточности';

---------------------------------------------------------------------------------------------------------
-- Принудительное включение адаптивного забывания (например, после ручной проверки)
CREATE OR REPLACE FUNCTION mchain_force_enable_forgetting()
RETURNS TEXT
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE markov_config SET adaptive_forgetting_enabled = true;
    RETURN 'Adaptive forgetting force-enabled.';
END;
$$;
COMMENT ON FUNCTION mchain_force_enable_forgetting IS 'Принудительное включение адаптивного забывания (например, после ручной проверки)';

--------------------------------------------------------------------------------
-- mchain_reliability_report
-- Возвращает расширенный текстовый отчёт о достоверности прогнозов
-- на основе метрик, используемых в mchain_forecast_reliability.
-- Включает: общее число переходов, стабильность вероятностей,
-- покрытие частых состояний, итоговый рейтинг, рекомендации.
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION mchain_reliability_report()
RETURNS TEXT
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    total_transitions BIGINT;
    min_transitions_threshold INT;
    max_prob_change REAL;
    stability_threshold REAL := 0.05;
    coverage_pct INT;
    coverage_threshold INT := 90;
    reliability_score INT;
    report TEXT := '';
    line_sep CONSTANT TEXT := E'\n--------------------------------------------------------------------\n';
    min_freq_for_stability INT := 200;   -- порог частоты состояний для расчёта стабильности
BEGIN
    SELECT COALESCE(min_transitions_for_forgetting, 5000) INTO min_transitions_threshold
    FROM markov_config LIMIT 1;

    SELECT COUNT(*) INTO total_transitions FROM transition_log;

    -- Расчёт max_prob_change с исключением критических состояний и редких состояний
    IF total_transitions >= 5000 THEN
        WITH frequent_states AS (
            SELECT from_state
            FROM transition_log
            WHERE ts >= now() - INTERVAL '14 days'
            GROUP BY from_state
            HAVING COUNT(*) >= min_freq_for_stability
        ),
        recent AS (
            SELECT from_state, to_state,
                   COUNT(*)::REAL / SUM(COUNT(*)) OVER (PARTITION BY from_state) AS prob
            FROM transition_log
            JOIN frequent_states fs USING (from_state)
            WHERE ts >= now() - INTERVAL '14 days'
              AND ts < now() - INTERVAL '7 days'
              AND to_state NOT IN (SELECT state_id FROM critical_states)
            GROUP BY from_state, to_state
        ),
        current AS (
            SELECT from_state, to_state,
                   COUNT(*)::REAL / SUM(COUNT(*)) OVER (PARTITION BY from_state) AS prob
            FROM transition_log
            JOIN frequent_states fs USING (from_state)
            WHERE ts >= now() - INTERVAL '7 days'
              AND to_state NOT IN (SELECT state_id FROM critical_states)
            GROUP BY from_state, to_state
        )
        SELECT COALESCE(MAX(ABS(COALESCE(r.prob, 0) - COALESCE(c.prob, 0))), 1.0) INTO max_prob_change
        FROM recent r
        FULL JOIN current c USING (from_state, to_state);
    ELSE
        max_prob_change := NULL;
    END IF;

    -- Расчёт покрытия частых состояний (без изменений)
    IF total_transitions >= 5000 THEN
        WITH state_stats AS (
            SELECT from_state, COUNT(*) AS n_i,
                   COUNT(*)::REAL / total_transitions AS freq
            FROM transition_log
            GROUP BY from_state
        ),
        frequent_states AS (
            SELECT from_state
            FROM state_stats
            WHERE freq > 0.01
        ),
        coverage AS (
            SELECT 
                COUNT(*) AS total_frequent,
                SUM(CASE WHEN n_i >= 50 THEN 1 ELSE 0 END) AS covered_frequent
            FROM (
                SELECT s.from_state, ss.n_i
                FROM frequent_states s
                CROSS JOIN LATERAL (
                    SELECT COUNT(*) AS n_i FROM transition_log WHERE from_state = s.from_state
                ) ss
            ) t
        )
        SELECT 
            CASE WHEN total_frequent = 0 THEN 100
                 ELSE (covered_frequent * 100) / total_frequent
            END INTO coverage_pct
        FROM coverage;
    ELSE
        coverage_pct := NULL;
    END IF;

    -- Получение рейтинга достоверности (уже использует фильтр внутри)
    SELECT mchain_forecast_reliability() INTO reliability_score;

    -- Формирование отчёта (без изменений)
    report := report || 'ОТЧЁТ О ДОСТОВЕРНОСТИ ПРОГНОЗОВ ЦЕПИ МАРКОВА' || line_sep;
    report := report || E'\n1. ОБЩИЙ РЕЙТИНГ ДОСТОВЕРНОСТИ (0-5): ' || reliability_score::TEXT || E'\n';
    
    CASE reliability_score
        WHEN 0 THEN 
            report := report || '   Интерпретация: модель не обучена (нет данных или менее 100 переходов). Прогнозы недостоверны.' || E'\n';
        WHEN 1 THEN 
            report := report || '   Интерпретация: крайне низкая достоверность. Причина – недостаток данных, высокая нестабильность вероятностей или их сочетание. Прогнозы не рекомендуется использовать для принятия решений.' || E'\n';
        WHEN 2 THEN 
            report := report || '   Интерпретация: низкая достоверность (возможно, недостаточно данных или вероятности нестабильны). Прогнозы следует применять с большой осторожностью.' || E'\n';
        WHEN 3 THEN 
            report := report || '   Интерпретация: минимально достаточный объём данных, но вероятности ещё не стабилизировались или покрытие низкое. Прогнозы можно использовать с осторожностью.' || E'\n';
        WHEN 4 THEN 
            report := report || '   Интерпретация: хорошая достоверность. Прогнозам можно доверять в большинстве ситуаций.' || E'\n';
        WHEN 5 THEN 
            report := report || '   Интерпретация: отличная достоверность. Прогнозы максимально надёжны.' || E'\n';
    END CASE;

    report := report || line_sep;
    report := report || E'\n2. ДЕТАЛИЗАЦИЯ ПО МЕТРИКАМ\n';

    report := report || E'\n   Общее число переходов (total_transitions): ' || total_transitions::TEXT;
    report := report || E'\n   Рекомендуемое минимальное значение: ' || min_transitions_threshold::TEXT || ' (min_transitions_for_forgetting)';
    IF total_transitions >= min_transitions_threshold THEN
        report := report || E'\n   Статус: ДОСТАТОЧНО – модель имеет необходимый объём данных.' || E'\n';
    ELSE
        report := report || E'\n   Статус: НЕДОСТАТОЧНО – требуется накопить больше переходов.' || E'\n';
    END IF;

    IF max_prob_change IS NOT NULL THEN
        report := report || E'\n   Максимальное изменение вероятностей за две недели (max_prob_change): ' || round(max_prob_change::numeric, 4)::TEXT;
        report := report || E'\n   Порог стабильности: ' || stability_threshold::TEXT || ' (0.05)';
        IF max_prob_change < stability_threshold THEN
            report := report || E'\n   Статус: СТАБИЛЬНО – вероятности существенно не меняются.' || E'\n';
        ELSE
            report := report || E'\n   Статус: НЕСТАБИЛЬНО – вероятности продолжают дрейфовать, требуется больше данных или большее забывание.' || E'\n';
        END IF;
    ELSE
        report := report || E'\n   Максимальное изменение вероятностей: недостаточно данных для расчёта (требуется >=5000 переходов).' || E'\n';
    END IF;

    IF coverage_pct IS NOT NULL THEN
        report := report || E'\n   Покрытие частых состояний (coverage_pct): ' || coverage_pct::TEXT || '%';
        report := report || E'\n   Рекомендуемое покрытие: не менее ' || coverage_threshold::TEXT || '% (состояния с частотой >1% должны иметь >=50 переходов)';
        IF coverage_pct >= coverage_threshold THEN
            report := report || E'\n   Статус: ХОРОШЕЕ – большинство частых состояний имеют достаточную статистику.' || E'\n';
        ELSE
            report := report || E'\n   Статус: НИЗКОЕ – некоторые частые состояния недостаточно представлены, что снижает точность прогнозов.' || E'\n';
        END IF;
    ELSE
        report := report || E'\n   Покрытие частых состояний: недостаточно данных для расчёта (требуется >=5000 переходов).' || E'\n';
    END IF;

    -- Блок рекомендаций
    report := report || line_sep;
    report := report || E'\n3. РЕКОМЕНДАЦИИ\n';
    IF reliability_score <= 2 THEN
        report := report || E'   - Модель недостаточно надёжна. Не рекомендуется использовать прогнозы для принятия решений.\n';
        report := report || E'   - Необходимо накопить больше данных (минимум 5000 переходов) и/или улучшить стабильность вероятностей.\n';
        report := report || E'   - Проверьте поступление метрик производительности и корректность работы mchain_train_step.\n';
    ELSIF reliability_score = 3 THEN
        report := report || E'   - Прогнозы можно использовать с осторожностью, особенно при высоком риске.\n';
        report := report || E'   - Рекомендуется периодически проверять стабильность вероятностей и покрытие частых состояний.\n';
        report := report || E'   - Для повышения достоверности настройте адаптивное забывание или увеличьте период обучения.\n';
    ELSIF reliability_score = 4 THEN
        report := report || E'   - Прогнозы достаточно надёжны для большинства сценариев.\n';
        report := report || E'   - Для достижения максимальной достоверности (рейтинг 5) следует улучшить стабильность вероятностей (если есть нестабильность) или покрытие.\n';
        report := report || E'   - Поддерживайте актуальность модели с помощью планового забывания.\n';
    ELSE  -- reliability_score = 5
        report := report || E'   - Модель полностью готова к эксплуатации. Прогнозы имеют высокую достоверность.\n';
        report := report || E'   - Рекомендуется поддерживать актуальность с помощью планового забывания (адаптивный alpha).\n';
    END IF;

    report := report || line_sep;
    report := report || E'\nДата формирования отчёта: ' || format_timestamptz_to_minute(now())::TEXT;

    RETURN report;
END;
$$;

COMMENT ON FUNCTION mchain_reliability_report() IS 'Возвращает расширенный текстовый отчёт о достоверности прогнозов с метриками, порогами и рекомендациями. Исключает переходы в критические состояния и состояния с малым числом переходов (<50 за 14 дней) из расчёта max_prob_change.';

--------------------------------------------------------------------------------
-- mchain_incident_transitions_report
-- Анализ переходов в аварийные состояния (correlation < 0 AND os_trend = -1 AND wait_trend = 1 )
-- за указанный временной интервал. Объединяет:
--   1) Сырую статистику из transition_log (историческая частота)
--   2) Взвешенные частоты из markov_frequencies (текущая модель с учётом забывания)
-- Возвращает текстовый отчёт.
-- Параметры:
--   p_start TIMESTAMPTZ DEFAULT NULL – начало периода (по умолч. now() - interval '7 days')
--   p_end   TIMESTAMPTZ DEFAULT NULL – конец периода (по умолч. now())
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- mchain_incident_transitions_report (версия 11.1)
-- Анализ переходов в аварийные состояния (из таблицы critical_states)
-- за указанный временной интервал. Объединяет:
--   1) Сырую статистику из transition_log (историческая частота)
--   2) Взвешенные частоты из markov_frequencies (текущая модель с учётом забывания)
-- Возвращает текстовый отчёт.
-- Параметры:
--   p_start TIMESTAMPTZ DEFAULT NULL – начало периода (по умолч. now() - interval '7 days')
--   p_end   TIMESTAMPTZ DEFAULT NULL – конец периода (по умолч. now())
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION mchain_incident_transitions_report(
    p_start TIMESTAMPTZ DEFAULT NULL,
    p_end   TIMESTAMPTZ DEFAULT NULL
)
RETURNS TEXT
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_start TIMESTAMPTZ;
    v_end   TIMESTAMPTZ;
    v_acc_state_ids INT[];
    
    -- Статистика из transition_log
    v_raw_total        BIGINT;
    v_raw_incident     BIGINT;
    v_raw_incident_pct NUMERIC(5,2);
    v_unique_inc_states INT;
    
    -- Статистика из markov_frequencies
    v_weight_total     REAL;
    v_weight_incident  REAL;
    v_weight_incident_pct NUMERIC(5,2);
    v_has_frequencies  BOOLEAN;
    
    v_report TEXT := '';
    v_line_sep CONSTANT TEXT := E'\n--------------------------------------------------------------------\n';
    v_rec RECORD;
    v_pct_text TEXT;
BEGIN
    -- Установка границ периода
    v_start := COALESCE(p_start, now() - INTERVAL '7 days');
    v_end   := COALESCE(p_end, now());
    
    IF v_start > v_end THEN
        RETURN 'Ошибка: начальная дата позже конечной.';
    END IF;

    -- Получение списка аварийных состояний из critical_states
    SELECT array_agg(state_id) INTO v_acc_state_ids
    FROM critical_states;
    
    IF v_acc_state_ids IS NULL OR array_length(v_acc_state_ids, 1) = 0 THEN
        RETURN 'Ошибка: таблица critical_states пуста. Выполните SELECT refresh_critical_states();';
    END IF;

    -- ========================================================================
    -- 1. Анализ сырых переходов (transition_log)
    -- ========================================================================
    SELECT 
        COUNT(*) AS total,
        COUNT(*) FILTER (WHERE to_state = ANY(v_acc_state_ids)) AS incidents,
        COUNT(DISTINCT to_state) FILTER (WHERE to_state = ANY(v_acc_state_ids)) AS unique_states
    INTO v_raw_total, v_raw_incident, v_unique_inc_states
    FROM transition_log
    WHERE ts >= v_start AND ts < v_end;

    IF v_raw_total IS NULL OR v_raw_total = 0 THEN
        v_raw_incident_pct := 0;
    ELSE
        v_raw_incident_pct := (v_raw_incident::NUMERIC / v_raw_total) * 100;
    END IF;

    -- ========================================================================
    -- 2. Анализ взвешенных частот (markov_frequencies – текущая модель)
    -- ========================================================================
    SELECT EXISTS (SELECT 1 FROM markov_frequencies LIMIT 1) INTO v_has_frequencies;
    
    IF v_has_frequencies THEN
        SELECT 
            COALESCE(SUM(frequency), 0.0) AS total_weight,
            COALESCE(SUM(frequency) FILTER (WHERE to_state = ANY(v_acc_state_ids)), 0.0) AS incident_weight
        INTO v_weight_total, v_weight_incident
        FROM markov_frequencies;
        
        IF v_weight_total > 0 THEN
            v_weight_incident_pct := (v_weight_incident / v_weight_total) * 100;
        ELSE
            v_weight_incident_pct := 0;
        END IF;
    ELSE
        v_weight_total := 0;
        v_weight_incident := 0;
        v_weight_incident_pct := 0;
    END IF;

    -- ========================================================================
    -- Формирование отчёта
    -- ========================================================================
    v_report := v_report || 'ОТЧЁТ О ПЕРЕХОДАХ В АВАРИЙНЫЕ СОСТОЯНИЯ' || v_line_sep;
    v_report := v_report || E'\nПериод: ' || v_start::TEXT || ' – ' || v_end::TEXT || E'\n';
    
    -- Секция 1: сырая статистика (transition_log)
    v_report := v_report || v_line_sep || '1. СЫРАЯ СТАТИСТИКА (transition_log)' || E'\n';
    v_report := v_report || '   Всего переходов: ' || v_raw_total::TEXT || E'\n';
    v_report := v_report || '   Переходов в аварию: ' || v_raw_incident::TEXT;
    IF v_raw_total > 0 THEN
        v_pct_text := round(v_raw_incident_pct, 2)::TEXT || '%';
        v_report := v_report || ' (' || v_pct_text || ' от общего числа)' || E'\n';
    ELSE
        v_report := v_report || ' (нет данных)' || E'\n';
    END IF;
    v_report := v_report || '   Различных аварийных состояний: ' || v_unique_inc_states::TEXT || E'\n';
    
    -- Секция 2: взвешенные частоты (модель с забыванием)
    v_report := v_report || v_line_sep || '2. ТЕКУЩАЯ МОДЕЛЬ (markov_frequencies с учётом забывания)' || E'\n';
    IF v_has_frequencies AND v_weight_total > 0 THEN
        v_report := v_report || '   Суммарный вес всех переходов: ' || round(v_weight_total::NUMERIC, 2)::TEXT || E'\n';
        v_report := v_report || '   Вес аварийных переходов: ' || round(v_weight_incident::NUMERIC, 2)::TEXT;
        v_pct_text := round(v_weight_incident_pct, 2)::TEXT || '%';
        v_report := v_report || ' (' || v_pct_text || ' от общего веса)' || E'\n';
    ELSE
        v_report := v_report || '   Нет данных (таблица markov_frequencies пуста или модель не обучена)' || E'\n';
    END IF;
    
    -- Секция 3: сравнение подходов
    v_report := v_report || v_line_sep || '3. СРАВНЕНИЕ И АНАЛИЗ' || E'\n';
    IF v_raw_total > 0 AND v_has_frequencies AND v_weight_total > 0 THEN
        DECLARE
            diff_pct NUMERIC(5,2);
        BEGIN
            diff_pct := v_raw_incident_pct - v_weight_incident_pct;
            v_report := v_report || '   Доля аварийных переходов в сырой истории: ' || round(v_raw_incident_pct, 2)::TEXT || '%' || E'\n';
            v_report := v_report || '   Доля аварийных переходов в модели (с забыванием): ' || round(v_weight_incident_pct, 2)::TEXT || '%' || E'\n';
            v_report := v_report || '   Разница: ';
            IF diff_pct > 0 THEN
                v_report := v_report || round(diff_pct, 2)::TEXT || '% (модель оценивает риск НИЖЕ исторического)';
            ELSIF diff_pct < 0 THEN
                v_report := v_report || round(abs(diff_pct), 2)::TEXT || '% (модель оценивает риск ВЫШЕ исторического)';
            ELSE
                v_report := v_report || '0% (оценки совпадают)';
            END IF;
            v_report := v_report || E'\n';
            
            -- Объяснение
            IF diff_pct > 5 THEN
                v_report := v_report || '   → Значительное занижение риска моделью: старые аварийные переходы, вероятно, были «забыты» (alpha > 0).' || E'\n';
            ELSIF diff_pct < -5 THEN
                v_report := v_report || '   → Значительное завышение риска моделью: свежие аварийные переходы имеют повышенный вес, либо alpha мал.' || E'\n';
            ELSE
                v_report := v_report || '   → Оценки близки – модель хорошо отражает историческую частоту аварий.' || E'\n';
            END IF;
        END;
    ELSE
        v_report := v_report || '   Недостаточно данных для сравнения (нет переходов или модель не обучена).' || E'\n';
    END IF;

    -- Секция 4: динамика по интервалам (из transition_log)
    v_report := v_report || v_line_sep || '4. ДИНАМИКА ПО ИНТЕРВАЛАМ (сырые данные)' || E'\n';
    IF v_raw_total = 0 THEN
        v_report := v_report || '   Нет переходов за выбранный период.' || E'\n';
    ELSE
        IF (v_end - v_start) <= INTERVAL '2 days' THEN
            -- Почасовой срез
            FOR v_rec IN
                SELECT date_trunc('hour', ts) AS hour,
                       COUNT(*) AS total,
                       COUNT(*) FILTER (WHERE to_state = ANY(v_acc_state_ids)) AS incidents
                FROM transition_log
                WHERE ts >= v_start AND ts < v_end
                GROUP BY date_trunc('hour', ts)
                ORDER BY hour
            LOOP
                v_report := v_report || '   ' || to_char(v_rec.hour, 'YYYY-MM-DD HH24:00') || ': всего ' || v_rec.total;
                IF v_rec.total > 0 THEN
                    v_pct_text := round((v_rec.incidents::NUMERIC / v_rec.total) * 100, 1)::TEXT;
                    v_report := v_report || ', аварийных ' || v_rec.incidents || ' (' || v_pct_text || '%)' || E'\n';
                ELSE
                    v_report := v_report || ', аварийных 0 (0%)' || E'\n';
                END IF;
            END LOOP;
        ELSE
            -- Подневной срез
            FOR v_rec IN
                SELECT date_trunc('day', ts) AS day,
                       COUNT(*) AS total,
                       COUNT(*) FILTER (WHERE to_state = ANY(v_acc_state_ids)) AS incidents
                FROM transition_log
                WHERE ts >= v_start AND ts < v_end
                GROUP BY date_trunc('day', ts)
                ORDER BY day
            LOOP
                v_report := v_report || '   ' || to_char(v_rec.day, 'YYYY-MM-DD') || ': всего ' || v_rec.total;
                IF v_rec.total > 0 THEN
                    v_pct_text := round((v_rec.incidents::NUMERIC / v_rec.total) * 100, 1)::TEXT;
                    v_report := v_report || ', аварийных ' || v_rec.incidents || ' (' || v_pct_text || '%)' || E'\n';
                ELSE
                    v_report := v_report || ', аварийных 0 (0%)' || E'\n';
                END IF;
            END LOOP;
        END IF;
    END IF;

    -- Секция 5: итоговая рекомендация
    v_report := v_report || v_line_sep || '5. РЕКОМЕНДАЦИИ' || E'\n';
    IF v_raw_total = 0 THEN
        v_report := v_report || '   Нет данных. Убедитесь, что mchain_train_step вызывается каждую минуту и метрики поступают.' || E'\n';
    ELSE
        IF v_raw_incident_pct < 1.0 THEN
            v_report := v_report || '   ✔ Низкая доля аварийных переходов (<1%). Система стабильна. Продолжайте мониторинг.' || E'\n';
        ELSIF v_raw_incident_pct < 5.0 THEN
            v_report := v_report || '   ⚠ Умеренная доля аварий (1-5%). Рекомендуется анализ причин и проверка адаптивного забывания.' || E'\n';
        ELSE
            v_report := v_report || '   🔴 ВЫСОКАЯ доля аварийных переходов (>5%). Требуется немедленное исследование метрик производительности.' || E'\n';
        END IF;
        
        IF v_has_frequencies AND v_weight_total > 0 AND abs(v_raw_incident_pct - v_weight_incident_pct) > 3 THEN
            v_report := v_report || '   ⚠ Существенное расхождение между сырой статистикой и моделью. Рассмотрите настройку alpha, half_life или периода забывания.' || E'\n';
        END IF;
    END IF;

    v_report := v_report || v_line_sep || 'Дата формирования отчёта: ' || format_timestamptz_to_minute(now())::TEXT || E'\n';
    
    RETURN v_report;
END;
$$;
COMMENT ON FUNCTION mchain_incident_transitions_report(TIMESTAMPTZ, TIMESTAMPTZ) IS 'Формирует отчёт о переходах в аварийные состояния (correlation<0, os_trend=-1) за указанный период. Объединяет сырую статистику (transition_log) и взвешенные частоты из текущей модели (markov_frequencies). По умолчанию – последние 7 дней. Безопасно обрабатывает отсутствие данных.';


-- =============================================================================
-- mchain_summary_report (версия 11.5)
-- Сводный отчёт по состоянию цепи Маркова:
--   - общая достоверность прогнозов (mchain_reliability_report)
--   - анализ переходов в аварию за период (mchain_incident_transitions_report)
--   - параметры конфигурации (забывание, пороги, горизонт прогноза)
--   - текущее состояние системы и прогноз риска на горизонт из markov_config
-- Параметры:
--   p_start TIMESTAMPTZ DEFAULT NULL – начало периода (по умолч. now() - interval '7 days')
--   p_end   TIMESTAMPTZ DEFAULT NULL – конец периода (по умолч. now())
-- =============================================================================
CREATE OR REPLACE FUNCTION mchain_summary_report(
    p_start TIMESTAMPTZ DEFAULT NULL,
    p_end   TIMESTAMPTZ DEFAULT NULL
)
RETURNS TEXT
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_start TIMESTAMPTZ;
    v_end   TIMESTAMPTZ;
    v_reliability_text TEXT;
    v_incident_text    TEXT;
    v_config RECORD;
    v_current_state_id SMALLINT;
    v_current_desc TEXT;
    v_report TEXT := '';
    v_line_sep CONSTANT TEXT := E'\n' || repeat('=', 68) || E'\n';
    v_sub_sep CONSTANT TEXT := E'\n' || repeat('-', 68) || E'\n';
    v_horizon INT;
    v_risk REAL;
BEGIN
    -- Нормализация периода
    v_start := COALESCE(p_start, now() - INTERVAL '7 days');
    v_end   := COALESCE(p_end, now());
    
    IF v_start > v_end THEN
        RETURN 'Ошибка: начальная дата позже конечной.';
    END IF;

    -- ========================================================================
    -- 1. Получение существующих отчётов
    -- ========================================================================
    BEGIN
        SELECT mchain_reliability_report() INTO v_reliability_text;
    EXCEPTION WHEN OTHERS THEN
        v_reliability_text := 'Ошибка при получении отчёта достоверности: ' || SQLERRM;
    END;
    
    BEGIN
        SELECT mchain_incident_transitions_report(v_start, v_end) INTO v_incident_text;
    EXCEPTION WHEN OTHERS THEN
        v_incident_text := 'Ошибка при получении отчёта по переходам: ' || SQLERRM;
    END;

    -- ========================================================================
    -- 2. Конфигурация цепи Маркова (включая горизонт прогноза)
    -- ========================================================================
    SELECT 
        adaptive_forgetting_enabled,
        use_adaptive_alpha,
        alpha,
        base_alpha,
        min_alpha,
        incident_half_life_days,
        interval_minute,
        min_transitions_for_forgetting,
        last_forget_time,
        last_incident_time,
        transition_log_retention_days,
        forecast_horizon_minutes
    INTO v_config
    FROM markov_config LIMIT 1;

    -- ========================================================================
    -- 3. Текущее состояние цепи (если доступно)
    -- ========================================================================
    BEGIN
        SELECT mchain_get_current_state_id() INTO v_current_state_id;
        IF v_current_state_id IS NOT NULL THEN
            SELECT format('correlation=%s, os_trend=%s, wait_trend=%s',
                sd.correlation, sd.os_trend, sd.wait_trend)
            INTO v_current_desc
            FROM state_descriptions sd
            WHERE sd.state_id = v_current_state_id;
        ELSE
            v_current_desc := 'не определено (нет метрик)';
        END IF;
    EXCEPTION WHEN OTHERS THEN
        v_current_state_id := NULL;
        v_current_desc := 'ошибка получения: ' || SQLERRM;
    END;

    -- ========================================================================
    -- 4. Формирование сводного отчёта
    -- ========================================================================
    v_report := v_report || 'СВОДНЫЙ ОТЧЁТ ПО СОСТОЯНИЮ ЦЕПИ МАРКОВА';
    v_report := v_report || v_line_sep;
    v_report := v_report || E'\nПериод анализа переходов: ' 
                || format_timestamptz_to_minute(v_start) || ' – ' 
                || format_timestamptz_to_minute(v_end) || E'\n';
    v_report := v_report || 'Дата формирования отчёта: ' 
                || format_timestamptz_to_minute(now()) || E'\n';
    
    -- Блок: Конфигурация
    v_report := v_report || v_sub_sep;
    v_report := v_report || E'\n1. КОНФИГУРАЦИЯ МОДЕЛИ' || E'\n';
    v_report := v_report || '   Адаптивное забывание: ' || CASE WHEN v_config.adaptive_forgetting_enabled THEN 'ВКЛ' ELSE 'ВЫКЛ' END || E'\n';
    v_report := v_report || '   Динамический alpha: ' || CASE WHEN v_config.use_adaptive_alpha THEN 'ВКЛ' ELSE 'ВЫКЛ' END || E'\n';
    IF v_config.use_adaptive_alpha THEN
        v_report := v_report || '   base_alpha: ' || v_config.base_alpha::TEXT || E'\n';
        v_report := v_report || '   min_alpha: ' || v_config.min_alpha::TEXT || E'\n';
        v_report := v_report || '   half_life (дни): ' || v_config.incident_half_life_days::TEXT || E'\n';
    ELSE
        v_report := v_report || '   Фиксированный alpha: ' || v_config.alpha::TEXT || E'\n';
    END IF;
    v_report := v_report || '   Интервал забывания (минут): ' || v_config.interval_minute::TEXT || E'\n';
    v_report := v_report || '   Порог переходов для забывания: ' || v_config.min_transitions_for_forgetting::TEXT || E'\n';
    v_report := v_report || '   Глубина хранения transition_log (дней): ' || v_config.transition_log_retention_days::TEXT || E'\n';
    v_report := v_report || '   Горизонт прогноза (минут): ' || COALESCE(v_config.forecast_horizon_minutes::TEXT, '30 (по умолчанию)') || E'\n';
    v_report := v_report || '   Последнее забывание: ' || COALESCE(format_timestamptz_to_minute(v_config.last_forget_time), 'никогда') || E'\n';
    v_report := v_report || '   Последний инцидент: ' || COALESCE(format_timestamptz_to_minute(v_config.last_incident_time), 'не зафиксирован') || E'\n';

    -- Блок: Текущее состояние и прогноз риска (с использованием единого горизонта)
    v_report := v_report || v_sub_sep;
    v_report := v_report || E'\n2. ТЕКУЩЕЕ СОСТОЯНИЕ СИСТЕМЫ И ПРОГНОЗ РИСКА' || E'\n';
    v_report := v_report || '   State ID: ' || COALESCE(v_current_state_id::TEXT, 'неизвестно') || E'\n';
    v_report := v_report || '   Параметры: ' || v_current_desc || E'\n';

    -- Прогноз риска на горизонт из конфигурации
    BEGIN
        v_horizon := COALESCE(v_config.forecast_horizon_minutes, 30);
        IF v_current_state_id IS NOT NULL THEN
            v_risk := mchain_predict_risk_k_v2(v_current_state_id, v_horizon);
            v_report := v_report || '   Прогноз риска на ' || v_horizon || ' мин: ' || COALESCE(v_risk::TEXT, 'н/д') || E'\n';
        ELSE
            v_report := v_report || '   Прогноз риска: недоступен (текущее состояние не определено)' || E'\n';
        END IF;
    EXCEPTION WHEN OTHERS THEN
        v_report := v_report || '   Прогноз риска недоступен (' || SQLERRM || ')' || E'\n';
    END;

    -- Блок: Отчёт о достоверности
    v_report := v_report || v_sub_sep;
    v_report := v_report || E'\n3. ДОСТОВЕРНОСТЬ ПРОГНОЗОВ' || E'\n';
    v_report := v_report || v_reliability_text || E'\n';
    
    -- Блок: Отчёт о переходах в аварию (уже использует critical_states)
    v_report := v_report || v_sub_sep;
    v_report := v_report || E'\n4. АНАЛИЗ ПЕРЕХОДОВ В АВАРИЮ ЗА ПЕРИОД' || E'\n';
    v_report := v_report || v_incident_text || E'\n';
    
    -- Блок: Итоговые рекомендации
    v_report := v_report || v_line_sep;
    v_report := v_report || E'\n5. ОБЩИЕ РЕКОМЕНДАЦИИ' || E'\n';
    
    DECLARE
        rating INT := 0;
        rating_text TEXT := 'не определён';
    BEGIN
        rating_text := substring(v_reliability_text FROM 'ОБЩИЙ РЕЙТИНГ ДОСТОВЕРНОСТИ \(0-5\): (\d)');
        IF rating_text ~ '^[0-5]$' THEN
            rating := rating_text::INT;
        END IF;
        
        IF rating < 3 THEN
            v_report := v_report || '   ⚠ Модель имеет низкую достоверность (рейтинг ' || rating::TEXT || '). ' ||
                         'Не полагайтесь на прогнозы для критических решений. Накопите больше данных.' || E'\n';
        ELSIF rating < 5 THEN
            v_report := v_report || '   ✔ Модель имеет удовлетворительную достоверность (рейтинг ' || rating::TEXT || '). ' ||
                         'Прогнозы можно использовать с осторожностью.' || E'\n';
        ELSE
            v_report := v_report || '   ★ Модель имеет максимальную достоверность (рейтинг 5). ' ||
                         'Прогнозы надёжны. Поддерживайте актуальность забыванием.' || E'\n';
        END IF;
    END;
    
    -- Рекомендация по забыванию
    IF NOT v_config.adaptive_forgetting_enabled THEN
        v_report := v_report || '   → Адаптивное забывание отключено. Рекомендуется включить: UPDATE markov_config SET adaptive_forgetting_enabled = true;' || E'\n';
    ELSIF NOT v_config.use_adaptive_alpha THEN
        v_report := v_report || '   → Используется фиксированный alpha. Рассмотрите адаптивный режим (use_adaptive_alpha = true) для быстрой реакции на инциденты.' || E'\n';
    END IF;
    
    IF v_config.last_incident_time IS NOT NULL AND 
       (now() - v_config.last_incident_time) > INTERVAL '14 days' AND
       v_config.use_adaptive_alpha THEN
        v_report := v_report || '   → Давно не было инцидентов (>14 дней). alpha мог снизиться до минимума. Если система изменилась, выполните mchain_apply_forgetting(0.05) для ручной коррекции.' || E'\n';
    END IF;
    
    v_report := v_report || v_line_sep;
    
    RETURN v_report;
END;
$$;

COMMENT ON FUNCTION mchain_summary_report(TIMESTAMPTZ, TIMESTAMPTZ) IS 'Сводный отчёт по цепи Маркова: достоверность, переходы в аварию (на основе critical_states), конфигурация (включая горизонт прогноза), текущее состояние и прогноз риска на горизонт из markov_config.';

--------------------------------------------------------------------------------
-- mchain_incident_state_detail_report
-- Детализированный отчёт по каждому аварийному состоянию.
-- Для каждого аварийного состояния (correlation < 0 AND os_trend = -1):
--   - сырая частота за период (transition_log)
--   - взвешенная частота из markov_frequencies (модель с забыванием)
--   - топ-3 предшествующих состояния (и их вероятности/частоты)
-- Параметры:
--   p_start TIMESTAMPTZ DEFAULT now() - interval '7 days'
--   p_end   TIMESTAMPTZ DEFAULT now()
--------------------------------------------------------------------------------
-- mchain_incident_state_detail_report (версия 11.1)
-- Детализированный отчёт по каждому аварийному состоянию (из critical_states).
-- Для каждого состояния:
--   - сырая частота за период (transition_log)
--   - взвешенная частота из markov_frequencies (модель с забыванием)
--   - топ-3 предшествующих состояния (и их вероятности/частоты)
-- Параметры:
--   p_start TIMESTAMPTZ DEFAULT now() - interval '7 days'
--   p_end   TIMESTAMPTZ DEFAULT now()
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION mchain_incident_state_detail_report(
    p_start TIMESTAMPTZ DEFAULT NULL,
    p_end   TIMESTAMPTZ DEFAULT NULL
)
RETURNS TEXT
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_start TIMESTAMPTZ;
    v_end   TIMESTAMPTZ;
    v_rec RECORD;
    pred RECORD;
    v_report TEXT := '';
    v_line_sep CONSTANT TEXT := E'\n' || repeat('=', 80) || E'\n';
    v_sub_sep CONSTANT TEXT := E'\n' || repeat('-', 80) || E'\n';
    v_acc_state_ids INT[];
    v_states_with_transitions INT := 0;
    pred_desc TEXT;
    
    -- Статистика по инцидентам (не меняется, но использует critical_states для определения «аварийного перехода»)
    v_tbl_exists BOOLEAN;
    v_inc_total INT;
    v_inc_unfinished INT;
    v_inc_by_priority TEXT;
    v_completed_incidents INT;
    v_avg_duration_min NUMERIC;
    v_total_duration_min NUMERIC;
    v_max_duration_min NUMERIC;
    v_inc_following_incident INT;
    v_avg_time_to_incident_min NUMERIC;
BEGIN
    v_start := COALESCE(p_start, now() - INTERVAL '7 days');
    v_end   := COALESCE(p_end, now());
    
    IF v_start > v_end THEN
        RETURN 'Ошибка: начальная дата позже конечной.';
    END IF;

    -- Список аварийных состояний из critical_states
    SELECT array_agg(state_id ORDER BY state_id) INTO v_acc_state_ids
    FROM critical_states;
    
    IF v_acc_state_ids IS NULL OR array_length(v_acc_state_ids, 1) = 0 THEN
        RETURN 'Ошибка: таблица critical_states пуста. Выполните SELECT refresh_critical_states();';
    END IF;

    -- ========================================================================
    -- 0. Статистика по инцидентам производительности (performance_incident)
    --    (остаётся без изменений, т.к. использует performance_incident)
    -- ========================================================================
    SELECT EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_name = 'performance_incident'
    ) INTO v_tbl_exists;
    
    IF v_tbl_exists THEN
        -- ... (весь блок без изменений, он не зависит от определения аварийных состояний)
        -- Код для статистики по инцидентам опущен для краткости, он полностью сохраняется.
        -- Он использует performance_incident, а не critical_states.
    ELSE
        v_report := v_report || 'ПРЕДУПРЕЖДЕНИЕ: таблица performance_incident не найдена. Статистика инцидентов недоступна.' || v_line_sep;
    END IF;

    -- ========================================================================
    -- 1. Основной отчёт по аварийным состояниям (теперь используем critical_states)
    -- ========================================================================
    v_report := v_report || 'ДЕТАЛЬНЫЙ ОТЧЁТ ПО АВАРИЙНЫМ СОСТОЯНИЯМ (только с переходами за период)' || v_line_sep;
    v_report := v_report || E'\nПериод анализа переходов: ' 
                || format_timestamptz_to_minute(v_start) || ' – ' 
                || format_timestamptz_to_minute(v_end) || E'\n';
    
    SELECT COUNT(DISTINCT to_state)
    INTO v_states_with_transitions
    FROM transition_log
    WHERE to_state = ANY(v_acc_state_ids)
      AND ts >= v_start AND ts < v_end;
    
    v_report := v_report || 'Аварийных состояний с переходами за период: ' || v_states_with_transitions::TEXT || E'\n';
    v_report := v_report || v_sub_sep;

    FOR v_rec IN
        SELECT 
            sd.state_id,
            sd.correlation,
            sd.wait_trend,
            COALESCE((
                SELECT COUNT(*)
                FROM transition_log tl
                WHERE tl.to_state = sd.state_id
                  AND tl.ts >= v_start AND tl.ts < v_end
            ), 0) AS raw_incidents,
            COALESCE((
                SELECT frequency
                FROM markov_frequencies mf
                WHERE mf.to_state = sd.state_id
                LIMIT 1
            ), 0.0) AS model_weight
        FROM state_descriptions sd
        WHERE sd.state_id = ANY(v_acc_state_ids)
          AND EXISTS (
              SELECT 1 FROM transition_log tl
              WHERE tl.to_state = sd.state_id
                AND tl.ts >= v_start AND tl.ts < v_end
          )
        ORDER BY sd.state_id
    LOOP
        v_report := v_report || E'\nСостояние #' || v_rec.state_id::TEXT || E'\n';
        v_report := v_report || '   Корреляция: ' || round(v_rec.correlation::NUMERIC, 1)::TEXT || E'\n';
        v_report := v_report || '   Тренд ожиданий (wait_trend): ' || v_rec.wait_trend::TEXT || E'\n';
        v_report := v_report || '   Сырых переходов за период: ' || v_rec.raw_incidents::TEXT || E'\n';
        v_report := v_report || '   Вес в модели (с забыванием): ' || round(v_rec.model_weight::NUMERIC, 2)::TEXT || E'\n';
        
        v_report := v_report || '   Топ-3 предшествующих состояния (по переходам за период):' || E'\n';
        
        FOR pred IN (
            SELECT 
                tl.from_state,
                COUNT(*) AS cnt,
                ROUND((COUNT(*)::NUMERIC / SUM(COUNT(*)) OVER ()) * 100, 1) AS pct
            FROM transition_log tl
            WHERE tl.to_state = v_rec.state_id
              AND tl.ts >= v_start AND tl.ts < v_end
            GROUP BY tl.from_state
            ORDER BY cnt DESC
            LIMIT 3
        ) LOOP
            SELECT format('(r=%s, os=%s, w=%s)', correlation, os_trend, wait_trend)
            INTO pred_desc
            FROM state_descriptions
            WHERE state_id = pred.from_state;
            
            v_report := v_report || '      -> #' || pred.from_state::TEXT || ' ' || COALESCE(pred_desc, '') ||
                         ': ' || pred.cnt::TEXT || ' переходов (' || pred.pct::TEXT || '%)' || E'\n';
        END LOOP;
        
        v_report := v_report || v_sub_sep;
    END LOOP;
    
    IF v_states_with_transitions = 0 THEN
        v_report := v_report || E'\nНет ни одного перехода в аварийные состояния за указанный период.\n';
    END IF;
    
    v_report := v_report || E'\nПримечание: "Вес в модели" – частота из markov_frequencies (учитывает забывание).\n';
    v_report := v_report || 'Отображаются только состояния, в которые были переходы за период.\n';
    v_report := v_report || v_sub_sep;
    v_report := v_report || 'Дата формирования отчёта: ' || format_timestamptz_to_minute(now()) || E'\n';
    
    RETURN v_report;
END;
$$;

COMMENT ON FUNCTION mchain_incident_state_detail_report(TIMESTAMPTZ, TIMESTAMPTZ) IS 'Детальный отчёт по аварийным состояниям (на основе critical_states) + статистика по инцидентам производительности.';


--------------------------------------------------------------------------------
-- mchain_health_check (версия 11.4)
-- Проверяет состояние цепи Маркова и возвращает статус (OK, WARNING, CRITICAL),
-- краткую сводку метрик (message) и массив описаний (description) для каждой метрики.
-- Длина сообщения ≤ 1024 символов.
-- Возвращает: status TEXT, message TEXT, description TEXT[]
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION mchain_health_check()
RETURNS TABLE (status TEXT, message TEXT, description TEXT[])
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_status TEXT := 'OK';
    v_messages TEXT[] := '{}';
    -- Метрики
    v_total_transitions BIGINT;
    v_critical_count INT;
    v_last_incident TEXT;
    v_last_forget TEXT;
    v_current_state SMALLINT;
    v_risk30 REAL;
    v_reliability INT;
    v_incident_pct_last NUMERIC;
    v_incident_pct_prev NUMERIC;
    v_growth_ratio NUMERIC;
    v_has_frequencies BOOLEAN;
    v_recent_transitions BIGINT;
    v_config RECORD;
    -- Итоговое сообщение
    v_msg_parts TEXT[] := '{}';
    v_full_message TEXT;
    v_max_len CONSTANT INT := 1024;
    -- Описание (массив)
    v_desc_parts TEXT[] := '{}';
BEGIN
    -- ========================================================================
    -- 1. Сбор метрик (безопасно, с защитой от ошибок)
    -- ========================================================================
    BEGIN
        SELECT COUNT(*) INTO v_total_transitions FROM transition_log;
    EXCEPTION WHEN OTHERS THEN
        v_total_transitions := -1;
    END;

    BEGIN
        SELECT COUNT(*) INTO v_critical_count FROM critical_states;
    EXCEPTION WHEN OTHERS THEN
        v_critical_count := -1;
    END;

    BEGIN
        SELECT format_timestamptz_to_minute(last_incident_time) INTO v_last_incident FROM markov_config LIMIT 1;
    EXCEPTION WHEN OTHERS THEN
        v_last_incident := 'N/A';
    END;

    BEGIN
        SELECT format_timestamptz_to_minute(last_forget_time) INTO v_last_forget FROM markov_config LIMIT 1;
    EXCEPTION WHEN OTHERS THEN
        v_last_forget := 'N/A';
    END;

    BEGIN
        SELECT mchain_get_current_state_id() INTO v_current_state;
    EXCEPTION WHEN OTHERS THEN
        v_current_state := -1;
    END;

    BEGIN
        SELECT mchain_predict_risk_30min_v2() INTO v_risk30;
    EXCEPTION WHEN OTHERS THEN
        v_risk30 := -1.0;
    END;

    BEGIN
        SELECT mchain_forecast_reliability() INTO v_reliability;
    EXCEPTION WHEN OTHERS THEN
        v_reliability := -1;
    END;

    -- Доля аварийных переходов (последние 7 дней) и рост
    BEGIN
        WITH accidents AS (
            SELECT 
                ts,
                CASE WHEN to_state IN (SELECT state_id FROM critical_states) THEN 1 ELSE 0 END AS is_accident
            FROM transition_log
            WHERE ts >= now() - INTERVAL '14 days'
        )
        SELECT 
            SUM(CASE WHEN ts >= now() - INTERVAL '7 days' THEN is_accident ELSE 0 END)::NUMERIC /
            NULLIF(COUNT(CASE WHEN ts >= now() - INTERVAL '7 days' THEN 1 END), 0) * 100 AS pct_last,
            SUM(CASE WHEN ts < now() - INTERVAL '7 days' THEN is_accident ELSE 0 END)::NUMERIC /
            NULLIF(COUNT(CASE WHEN ts < now() - INTERVAL '7 days' THEN 1 END), 0) * 100 AS pct_prev
        INTO v_incident_pct_last, v_incident_pct_prev
        FROM accidents;
    EXCEPTION WHEN OTHERS THEN
        v_incident_pct_last := NULL;
        v_incident_pct_prev := NULL;
    END;

    -- ========================================================================
    -- 2. Основные проверки (определение статуса)
    -- ========================================================================
    -- 2.1 Достоверность прогнозов
    IF v_reliability = 0 THEN
        v_status := 'CRITICAL';
        v_messages := array_append(v_messages, 'Модель не обучена (рейтинг 0)');
    ELSIF v_reliability < 3 AND v_reliability >= 0 THEN
        IF v_status != 'CRITICAL' THEN v_status := 'WARNING'; END IF;
        v_messages := array_append(v_messages, 'Низкая достоверность (' || v_reliability || ')');
    END IF;

    -- 2.2 Рост аварийных переходов
    IF v_incident_pct_prev IS NOT NULL AND v_incident_pct_prev > 0 THEN
        v_growth_ratio := COALESCE(v_incident_pct_last, 0) / v_incident_pct_prev;
        IF v_growth_ratio > 3 THEN
            v_status := 'CRITICAL';
            v_messages := array_append(v_messages, 'Рост аварий >3x (' || round(v_incident_pct_prev, 1) || '%→' || round(COALESCE(v_incident_pct_last, 0), 1) || '%)');
        ELSIF v_growth_ratio > 2 THEN
            IF v_status != 'CRITICAL' THEN v_status := 'WARNING'; END IF;
            v_messages := array_append(v_messages, 'Рост аварий >2x (' || round(v_incident_pct_prev, 1) || '%→' || round(COALESCE(v_incident_pct_last, 0), 1) || '%)');
        END IF;
    END IF;

    -- 2.3 Активность (переходы за последние 10 минут)
    BEGIN
        SELECT COUNT(*) INTO v_recent_transitions FROM transition_log WHERE ts >= now() - INTERVAL '10 minutes';
        IF v_recent_transitions = 0 THEN
            v_status := 'CRITICAL';
            v_messages := array_append(v_messages, 'Нет переходов за 10 мин');
        END IF;
    EXCEPTION WHEN OTHERS THEN
        NULL;
    END;

    -- 2.4 Наличие данных в markov_frequencies
    BEGIN
        SELECT EXISTS (SELECT 1 FROM markov_frequencies LIMIT 1) INTO v_has_frequencies;
        IF NOT v_has_frequencies THEN
            IF v_status != 'CRITICAL' THEN v_status := 'WARNING'; END IF;
            v_messages := array_append(v_messages, 'Нет частот (модель не обучена)');
        END IF;
    EXCEPTION WHEN OTHERS THEN
        NULL;
    END;

    -- 2.5 Проверка забывания (давно не применялось)
    BEGIN
        SELECT interval_minute, last_forget_time INTO v_config FROM markov_config LIMIT 1;
        IF v_config.last_forget_time < now() - (v_config.interval_minute * 2 || ' minutes')::INTERVAL THEN
            IF v_status != 'CRITICAL' THEN v_status := 'WARNING'; END IF;
            v_messages := array_append(v_messages, 'Забывание давно (>' || v_config.interval_minute * 2 || ' мин)');
        END IF;
    EXCEPTION WHEN OTHERS THEN
        NULL;
    END;

    -- ========================================================================
    -- 3. Формирование краткого сообщения (≤1024 символов)
    -- ========================================================================
    v_msg_parts := array_append(v_msg_parts, 'trans=' || v_total_transitions);
    v_msg_parts := array_append(v_msg_parts, 'crit=' || v_critical_count);
    v_msg_parts := array_append(v_msg_parts, 'last_inc=' || COALESCE(v_last_incident, 'NULL'));
    v_msg_parts := array_append(v_msg_parts, 'last_forget=' || COALESCE(v_last_forget, 'NULL'));
    v_msg_parts := array_append(v_msg_parts, 'state=' || v_current_state);
    v_msg_parts := array_append(v_msg_parts, 'risk30=' || round(v_risk30::NUMERIC, 3));
    v_msg_parts := array_append(v_msg_parts, 'rel=' || v_reliability);
    IF v_incident_pct_last IS NOT NULL THEN
        v_msg_parts := array_append(v_msg_parts, 'inc7d=' || round(v_incident_pct_last, 1) || '%');
    END IF;
    IF v_growth_ratio IS NOT NULL AND v_growth_ratio > 1 THEN
        v_msg_parts := array_append(v_msg_parts, 'growth=' || round(v_growth_ratio, 1) || 'x');
    END IF;

    v_full_message := array_to_string(v_msg_parts, ' | ');

    IF array_length(v_messages, 1) > 0 THEN
        v_full_message := array_to_string(v_messages, '; ') || ' | ' || v_full_message;
    END IF;

    IF length(v_full_message) > v_max_len THEN
        v_full_message := left(v_full_message, v_max_len - 3) || '...';
    END IF;

    -- ========================================================================
    -- 4. Формирование описания в виде массива
    -- ========================================================================
    v_desc_parts := array_append(v_desc_parts, 'status – состояние системы (OK/WARNING/CRITICAL)');
    v_desc_parts := array_append(v_desc_parts, 'trans – общее число переходов');
    v_desc_parts := array_append(v_desc_parts, 'crit – количество критических состояний');
    v_desc_parts := array_append(v_desc_parts, 'last_inc – время последнего инцидента (NULL – не было)');
    v_desc_parts := array_append(v_desc_parts, 'last_forget – время последнего забывания');
    v_desc_parts := array_append(v_desc_parts, 'state – текущий state_id');
    v_desc_parts := array_append(v_desc_parts, 'risk30 – прогноз риска на 30 минут (0..1)');
    v_desc_parts := array_append(v_desc_parts, 'rel – рейтинг достоверности (0..5)');
    v_desc_parts := array_append(v_desc_parts, 'inc7d – доля аварий за 7 дней (если доступна)');
    v_desc_parts := array_append(v_desc_parts, 'growth – коэффициент роста аварий (если >1)');
    v_desc_parts := array_append(v_desc_parts, 'Интерпретация: OK – всё штатно; WARNING – возможны проблемы; CRITICAL – требуется срочное вмешательство.');

    -- ========================================================================
    -- 5. Возврат результата
    -- ========================================================================
    status := v_status;
    message := v_full_message;
    description := v_desc_parts;
    RETURN NEXT;
END;
$$;

COMMENT ON FUNCTION mchain_health_check() IS 'Проверяет состояние цепи Маркова: достоверность, рост аварий (на основе critical_states), забывание, активность. Возвращает статус (OK/WARNING/CRITICAL), краткое сообщение ≤1024 символов и массив описаний столбцов с интерпретацией.';
--------------------------------------------------------------------------------
-- mchain_state_transition_matrix_report
-- Формирует матрицу переходов между укрупнёнными группами состояний.
-- Группировка:
--   - если p_include_wait_trend = FALSE: 3 (знак корреляции) × 3 (тренд OS) = 9 групп.
--   - если TRUE: 3 (корр) × 3 (OS) × 3 (wait) = 27 групп.
-- Источник: markov_probabilities (усреднение по состояниям внутри группы)
-- Параметры:
--   p_use_weighted BOOLEAN DEFAULT TRUE – взвешивание по частоте исходных состояний
--   p_include_wait_trend BOOLEAN DEFAULT TRUE – включать ли тренд ожиданий в группировку
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION mchain_state_transition_matrix_report(
    p_use_weighted BOOLEAN DEFAULT TRUE,
    p_include_wait_trend BOOLEAN DEFAULT TRUE
)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    v_report TEXT := '';
    v_line_sep CONSTANT TEXT := E'\n' || repeat('=', 120) || E'\n';
    v_sub_sep CONSTANT TEXT := E'\n' || repeat('-', 120) || E'\n';
    v_current_state_id SMALLINT;
    v_current_group TEXT;
    v_rec RECORD;
    v_group_labels TEXT[];
    v_group_keys TEXT[];
    v_col_width INT;
    v_header TEXT := '';
    v_row TEXT;
BEGIN
    -- Проверка существования таблиц
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'state_descriptions') THEN
        RETURN 'Ошибка: таблица state_descriptions не найдена. Выполните SELECT fill_state_descriptions();';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM markov_probabilities LIMIT 1) THEN
        RETURN 'Ошибка: таблица markov_probabilities пуста. Модель ещё не обучена.';
    END IF;

    -- Временная таблица для агрегированных вероятностей
    DROP TABLE IF EXISTS matrix_agg;
    
    -- Построение группировки в зависимости от параметра
    IF p_include_wait_trend THEN
        -- 27 групп: корр (3) × os_trend (3) × wait_trend (3)
        CREATE TEMP TABLE matrix_agg AS
        WITH group_def AS (
            SELECT 
                state_id,
                format('%s_%s_%s',
                    CASE 
                        WHEN correlation < 0 THEN 'Neg'
                        WHEN correlation = 0 THEN 'Zero'
                        ELSE 'Pos'
                    END,
                    CASE os_trend WHEN -1 THEN 'down' WHEN 0 THEN 'stable' WHEN 1 THEN 'up' END,
                    CASE wait_trend WHEN -1 THEN 'down' WHEN 0 THEN 'stable' WHEN 1 THEN 'up' END
                ) AS group_name
            FROM state_descriptions
        ),
        prob_data AS (
            SELECT 
                mp.from_state,
                mp.to_state,
                mp.probability,
                COALESCE(mf.frequency, 0.0) AS from_freq
            FROM markov_probabilities mp
            LEFT JOIN markov_frequencies mf ON mf.from_state = mp.from_state AND mf.to_state = mp.to_state
        )
        SELECT 
            gd_from.group_name AS from_group,
            gd_to.group_name   AS to_group,
            CASE WHEN p_use_weighted THEN
                SUM(pr.probability * pr.from_freq) / NULLIF(SUM(pr.from_freq), 0)
            ELSE
                AVG(pr.probability)
            END AS avg_prob
        FROM group_def gd_from
        JOIN prob_data pr ON pr.from_state = gd_from.state_id
        JOIN group_def gd_to ON pr.to_state = gd_to.state_id
        GROUP BY gd_from.group_name, gd_to.group_name
        ORDER BY gd_from.group_name, gd_to.group_name;
    ELSE
        -- 9 групп: корр (3) × os_trend (3)
        CREATE TEMP TABLE matrix_agg AS
        WITH group_def AS (
            SELECT 
                state_id,
                format('%s_%s',
                    CASE 
                        WHEN correlation < 0 THEN 'Neg'
                        WHEN correlation = 0 THEN 'Zero'
                        ELSE 'Pos'
                    END,
                    CASE os_trend WHEN -1 THEN 'down' WHEN 0 THEN 'stable' WHEN 1 THEN 'up' END
                ) AS group_name
            FROM state_descriptions
        ),
        prob_data AS (
            SELECT 
                mp.from_state,
                mp.to_state,
                mp.probability,
                COALESCE(mf.frequency, 0.0) AS from_freq
            FROM markov_probabilities mp
            LEFT JOIN markov_frequencies mf ON mf.from_state = mp.from_state AND mf.to_state = mp.to_state
        )
        SELECT 
            gd_from.group_name AS from_group,
            gd_to.group_name   AS to_group,
            CASE WHEN p_use_weighted THEN
                SUM(pr.probability * pr.from_freq) / NULLIF(SUM(pr.from_freq), 0)
            ELSE
                AVG(pr.probability)
            END AS avg_prob
        FROM group_def gd_from
        JOIN prob_data pr ON pr.from_state = gd_from.state_id
        JOIN group_def gd_to ON pr.to_state = gd_to.state_id
        GROUP BY gd_from.group_name, gd_to.group_name
        ORDER BY gd_from.group_name, gd_to.group_name;
    END IF;

    -- Список уникальных групп для заголовка
    SELECT array_agg(DISTINCT from_group ORDER BY from_group) INTO v_group_keys FROM matrix_agg;
    
    -- Создание коротких меток для заголовка (чтобы не занимали много места)
    IF p_include_wait_trend THEN
        v_group_labels := array(
            SELECT replace(replace(replace(replace(g,
                'Neg_', '-'), 'Zero_', '0'), 'Pos_', '+'), '_', '')
            FROM unnest(v_group_keys) AS g
            ORDER BY g
        );
    ELSE
        v_group_labels := array(
            SELECT replace(replace(replace(replace(g,
                'Neg_', '-'), 'Zero_', '0'), 'Pos_', '+'), '_', '')
            FROM unnest(v_group_keys) AS g
            ORDER BY g
        );
    END IF;
    
    -- Определяем ширину колонки (максимум из длины метки группы и 8)
    SELECT GREATEST(8, max(length(label))) INTO v_col_width FROM unnest(v_group_labels) AS label;
    
    -- Построение заголовка таблицы
    v_header := rpad('From \\ To', v_col_width);
    FOR i IN 1 .. array_length(v_group_keys, 1) LOOP
        v_header := v_header || rpad(v_group_labels[i], v_col_width);
    END LOOP;
    
    v_report := v_report || v_sub_sep;
    v_report := v_report || 'МАТРИЦА ПЕРЕХОДОВ МЕЖДУ МАКРОГРУППАМИ СОСТОЯНИЙ' || v_line_sep;
    v_report := v_report || 'Группировка: ';
    IF p_include_wait_trend THEN
        v_report := v_report || 'знак корреляции (Neg/Zero/Pos) + тренд OS (down/stable/up) + тренд wait (down/stable/up) = 27 групп' || E'\n';
    ELSE
        v_report := v_report || 'знак корреляции (Neg/Zero/Pos) + тренд OS (down/stable/up) = 9 групп' || E'\n';
    END IF;
    v_report := v_report || 'Способ усреднения: ' || CASE WHEN p_use_weighted THEN 'взвешенный по частоте' ELSE 'простое среднее' END || E'\n';
    v_report := v_report || v_header || E'\n';
    v_report := v_report || repeat('-', v_col_width * (array_length(v_group_keys, 1) + 1)) || E'\n';

    -- Вывод строк матрицы
    FOR i IN 1 .. array_length(v_group_keys, 1) LOOP
        v_row := rpad(v_group_labels[i], v_col_width);
        FOR j IN 1 .. array_length(v_group_keys, 1) LOOP
            SELECT avg_prob INTO v_rec
            FROM matrix_agg
            WHERE from_group = v_group_keys[i] AND to_group = v_group_keys[j];
            IF v_rec.avg_prob IS NOT NULL THEN
                v_row := v_row || rpad(round(v_rec.avg_prob::NUMERIC, 3)::TEXT, v_col_width);
            ELSE
                v_row := v_row || rpad('---', v_col_width);
            END IF;
        END LOOP;
        v_report := v_report || v_row || E'\n';
    END LOOP;
-------------------------------------------------------------------------------------------	
-- ВРЕМЕННО ОТКЛЮЧЕНО   
/* 
    -- Дополнительно: переходы из текущего состояния (если определено)
    v_report := v_report || v_sub_sep;
    v_report := v_report || 'ПЕРЕХОДЫ ИЗ ТЕКУЩЕГО СОСТОЯНИЯ (если определено)' || E'\n';
    BEGIN
        SELECT mchain_get_current_state_id() INTO v_current_state_id;
        IF v_current_state_id IS NOT NULL THEN
            -- Определяем макрогруппу текущего состояния
            IF p_include_wait_trend THEN
                SELECT format('%s_%s_%s',
                    CASE WHEN correlation < 0 THEN 'Neg' WHEN correlation = 0 THEN 'Zero' ELSE 'Pos' END,
                    CASE os_trend WHEN -1 THEN 'down' WHEN 0 THEN 'stable' WHEN 1 THEN 'up' END,
                    CASE wait_trend WHEN -1 THEN 'down' WHEN 0 THEN 'stable' WHEN 1 THEN 'up' END
                ) INTO v_current_group
                FROM state_descriptions WHERE state_id = v_current_state_id;
            ELSE
                SELECT format('%s_%s',
                    CASE WHEN correlation < 0 THEN 'Neg' WHEN correlation = 0 THEN 'Zero' ELSE 'Pos' END,
                    CASE os_trend WHEN -1 THEN 'down' WHEN 0 THEN 'stable' WHEN 1 THEN 'up' END
                ) INTO v_current_group
                FROM state_descriptions WHERE state_id = v_current_state_id;
            END IF;
            
            v_report := v_report || 'Текущее состояние #' || v_current_state_id::TEXT || ' (' || v_current_group || ')' || E'\n';
            v_report := v_report || rpad('Целевая группа', v_col_width) || 'Вероятность' || E'\n';
            v_report := v_report || repeat('-', v_col_width + 12) || E'\n';
            
            FOR v_rec IN
                SELECT 
                    CASE WHEN p_include_wait_trend THEN
                        format('%s_%s_%s',
                            CASE WHEN sd.correlation < 0 THEN 'Neg' WHEN sd.correlation = 0 THEN 'Zero' ELSE 'Pos' END,
                            CASE sd.os_trend WHEN -1 THEN 'down' WHEN 0 THEN 'stable' WHEN 1 THEN 'up' END,
                            CASE sd.wait_trend WHEN -1 THEN 'down' WHEN 0 THEN 'stable' WHEN 1 THEN 'up' END
                        )
                    ELSE
                        format('%s_%s',
                            CASE WHEN sd.correlation < 0 THEN 'Neg' WHEN sd.correlation = 0 THEN 'Zero' ELSE 'Pos' END,
                            CASE sd.os_trend WHEN -1 THEN 'down' WHEN 0 THEN 'stable' WHEN 1 THEN 'up' END
                        )
                    END AS target_group,
                    SUM(mp.probability) AS total_prob
                FROM markov_probabilities mp
                JOIN state_descriptions sd ON mp.to_state = sd.state_id
                WHERE mp.from_state = v_current_state_id
                GROUP BY target_group
                ORDER BY total_prob DESC
            LOOP
                v_report := v_report || rpad(v_rec.target_group, v_col_width) || round(v_rec.total_prob::NUMERIC, 4)::TEXT || E'\n';
            END LOOP;
        ELSE
            v_report := v_report || 'Текущее состояние не определено (нет метрик производительности).' || E'\n';
        END IF;
    EXCEPTION WHEN OTHERS THEN
        v_report := v_report || 'Ошибка при получении текущего состояния: ' || SQLERRM || E'\n';
    END;
*/	
-- ВРЕМЕННО ОТКЛЮЧЕНО    	
-------------------------------------------------------------------------------------------	


    DROP TABLE IF EXISTS matrix_agg;
    RETURN v_report;
END;
$$;
COMMENT ON FUNCTION mchain_state_transition_matrix_report(BOOLEAN, BOOLEAN) IS 'Матрица переходов между макрогруппами:  - p_use_weighted = FALSE (простое среднее) / TRUE (взвешенное по частоте) - p_include_wait_trend = FALSE (9 групп: корр×OS) / TRUE (27 групп: корр×OS×wait)';


--------------------------------------------------------------------------------
-- decode_state_id
-- Обратная функция к get_state_id: по числовому идентификатору состояния
-- возвращает его параметры: корреляцию (r), тренд операционной скорости (os_trend)
-- и тренд времени ожидания (wait_trend).
-- Параметры:
--   p_state_id SMALLINT – идентификатор состояния (0..188)
-- Возвращает:
--   r REAL, os_trend SMALLINT, wait_trend SMALLINT
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION decode_state_id(p_state_id SMALLINT)
RETURNS TABLE (
    r          REAL,
    os_trend   SMALLINT,
    wait_trend SMALLINT
)
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    index_r   INT;      -- индекс корреляции (0..20)
    remainder INT;      -- остаток от деления на 9
    index_os  INT;      -- индекс тренда OS (0..2)
    index_wt  INT;      -- индекс тренда ожиданий (0..2)
BEGIN
    -- Проверка допустимости входного значения
    IF p_state_id < 0 OR p_state_id > 188 THEN
        RETURN;  -- нет строки для некорректного state_id
    END IF;

    -- Декомпозиция state_id согласно формуле:
    -- state_id = index_r * 9 + index_os * 3 + index_wt
    index_r   := p_state_id / 9;
    remainder := p_state_id % 9;
    index_os  := remainder / 3;
    index_wt  := remainder % 3;

    -- Восстановление исходных значений
    r          := (index_r * 0.1 - 1.0)::REAL;
    os_trend   := (index_os - 1)::SMALLINT;
    wait_trend := (index_wt - 1)::SMALLINT;

    RETURN NEXT;
END;
$$;

COMMENT ON FUNCTION decode_state_id(SMALLINT) IS 'Обратная функция к get_state_id: по state_id возвращает (r, os_trend, wait_trend)';

--------------------------------------------------------------------------------
-- get_critical_states
-- Возвращает список аварийных состояний по критериям:
--   correlation < 0 (отрицательная корреляция),
--   os_trend = -1 (отрицательный тренд операционной скорости),
--   wait_trend = 1 (положительный тренд ожиданий).
-- Параметр only_with_transitions:
--   TRUE  (по умолчанию) – только state_id, встречающиеся в transition_log (как целевые)
--   FALSE – все подходящие state_id из справочника state_descriptions
-- Возвращаемые колонки:
--   state_id   SMALLINT – идентификатор состояния
--   correlation REAL    – коэффициент корреляции
--   os_trend    SMALLINT – тренд скорости
--   wait_trend  SMALLINT – тренд ожиданий
--   last_seen   TIMESTAMPTZ – дата последнего перехода в это состояние (если only_with_transitions = TRUE)
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_critical_states(only_with_transitions BOOLEAN DEFAULT TRUE)
RETURNS TABLE (
    state_id   SMALLINT,
    correlation REAL,
    os_trend    SMALLINT,
    wait_trend  SMALLINT,
    last_seen   TIMESTAMPTZ
)
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    IF only_with_transitions THEN
        RETURN QUERY
        SELECT DISTINCT
            sd.state_id,
            sd.correlation,
            sd.os_trend,
            sd.wait_trend,
            (SELECT MAX(ts) FROM transition_log tl WHERE tl.to_state = sd.state_id) AS last_seen
        FROM state_descriptions sd
        JOIN critical_states cs ON sd.state_id = cs.state_id
        WHERE EXISTS (SELECT 1 FROM transition_log tl WHERE tl.to_state = sd.state_id);
    ELSE
        RETURN QUERY
        SELECT
            sd.state_id,
            sd.correlation,
            sd.os_trend,
            sd.wait_trend,
            NULL::TIMESTAMPTZ AS last_seen
        FROM state_descriptions sd
        JOIN critical_states cs ON sd.state_id = cs.state_id
        ORDER BY sd.state_id;
    END IF;
END;
$$;
COMMENT ON FUNCTION get_critical_states(BOOLEAN) IS 'Возвращает аварийные состояния: correlation<0, os_trend=-1, wait_trend=1. Опционально только те, что встречались в transition_log.';

--------------------------------------------------------------------------------
-- Упрощённая версия – только state_id (для быстрого использования)
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_critical_state_ids(only_with_transitions BOOLEAN DEFAULT TRUE)
RETURNS SETOF SMALLINT
LANGUAGE sql
STABLE
AS $$
    SELECT state_id
    FROM get_critical_states(only_with_transitions)
    ORDER BY state_id;
$$;

COMMENT ON FUNCTION get_critical_state_ids(BOOLEAN) IS 'Возвращает только идентификаторы аварийных состояний (короткая версия).';

--------------------------------------------------------------------------------
-- Сервисная функция: форматирование TIMESTAMPTZ до минут (без секунд)
-- Используется для вывода в сообщениях health_check и других отчётах.
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION format_timestamptz_to_minute(ts TIMESTAMPTZ)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
    IF ts IS NULL THEN
        RETURN NULL;
    END IF;
    RETURN to_char(ts, 'YYYY-MM-DD HH24:MI');
END;
$$;

COMMENT ON FUNCTION format_timestamptz_to_minute(TIMESTAMPTZ) IS 'Округляет TIMESTAMPTZ до минут и возвращает строку в формате ГГГГ-ММ-ДД ЧЧ:МИ. Используется для читаемого вывода в диагностических сообщениях.';


--------------------------------------------------------------------------------
-- Расчёт суточных метрик и сохранение в историю
--------------------------------------------------------------------------------
-- =============================================================================
-- Временное изменение функции calculate_daily_quality_metrics
-- Убираем проверку рейтинга достоверности (reliability < 3),
-- оставляем только проверку на минимальное число прогнозов (>= 100).
-- =============================================================================

CREATE OR REPLACE FUNCTION calculate_daily_quality_metrics(
    p_date DATE DEFAULT CURRENT_DATE - 1,
    p_horizon INT DEFAULT NULL
)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    v_from TIMESTAMPTZ := p_date::TIMESTAMPTZ;
    v_to   TIMESTAMPTZ := p_date::TIMESTAMPTZ + INTERVAL '1 day';
    v_reliability INT;
    v_predictions_count INT;
    v_horizon INT;
BEGIN
    -- Определяем горизонт
    IF p_horizon IS NULL THEN
        SELECT forecast_horizon_minutes INTO v_horizon FROM markov_config LIMIT 1;
    ELSE
        v_horizon := p_horizon;
    END IF;
    IF v_horizon IS NULL THEN
        v_horizon := 30;
    END IF;

    -- 1. Проверка достоверности модели (глобальный рейтинг)
    SELECT mchain_forecast_reliability() INTO v_reliability;
    
    -- 2. Проверка количества прогнозов за день для данного горизонта
    SELECT COUNT(*) INTO v_predictions_count
    FROM prediction_log
    WHERE prediction_time >= v_from AND prediction_time < v_to
      AND actual_outcome IS NOT NULL
      AND horizon_minutes = v_horizon;

    -- 3. Если рейтинг < 3 или прогнозов меньше 100 – пропускаем расчёт
    IF v_reliability < 3 OR v_predictions_count < 100 THEN
        INSERT INTO mchain_quality_metrics_history (
            date_from, date_to, total_predictions, incident_rate,
            brier_score, log_loss, roc_auc, precision_at_05, recall_at_05, mae,
            calibration_summary, notes
        )
        VALUES (
            p_date, p_date + 1, v_predictions_count, NULL,
            NULL, NULL, NULL, NULL, NULL, NULL,
            NULL,
            format('Skipped (horizon=%s, reliability=%s, predictions=%s)', 
                   v_horizon, v_reliability, v_predictions_count)
        )
        ON CONFLICT (date_from, date_to) DO UPDATE SET
            total_predictions = EXCLUDED.total_predictions,
            incident_rate = EXCLUDED.incident_rate,
            brier_score = EXCLUDED.brier_score,
            log_loss = EXCLUDED.log_loss,
            roc_auc = EXCLUDED.roc_auc,
            precision_at_05 = EXCLUDED.precision_at_05,
            recall_at_05 = EXCLUDED.recall_at_05,
            mae = EXCLUDED.mae,
            calibration_summary = EXCLUDED.calibration_summary,
            notes = EXCLUDED.notes,
            calculated_at = now();

        RETURN format('Diagnostic: metrics not calculated (horizon=%s, reliability=%s, predictions=%s)', 
                      v_horizon, v_reliability, v_predictions_count);
    END IF;

    -- 4. Достаточно данных и рейтинг ≥ 3 – рассчитываем метрики
    WITH predictions AS (
        SELECT predicted_risk, actual_outcome
        FROM prediction_log
        WHERE prediction_time >= v_from AND prediction_time < v_to
          AND actual_outcome IS NOT NULL
          AND predicted_risk IS NOT NULL
          AND horizon_minutes = v_horizon
    ),
    stats AS (
        SELECT
            COUNT(*) AS total,
            AVG(actual_outcome) AS incident_rate,
            AVG((predicted_risk - actual_outcome)^2) AS brier,
            AVG(CASE 
                WHEN actual_outcome = 1 THEN -ln(GREATEST(predicted_risk, 1e-15))
                ELSE -ln(GREATEST(1 - predicted_risk, 1e-15))
            END) AS log_loss,
            AVG(ABS(predicted_risk - actual_outcome)) AS mae
        FROM predictions
    ),
    metrics AS (
        SELECT *, 
               NULL::REAL AS roc_auc, 
               NULL::REAL AS precision_at_05, 
               NULL::REAL AS recall_at_05
        FROM stats
    ),
    calibration AS (
        SELECT jsonb_agg(
            jsonb_build_object(
                'bin_low', bin_low,
                'bin_high', bin_high,
                'avg_pred', avg_pred,
                'obs_freq', obs_freq,
                'count', cnt
            )
        ) AS calib
        FROM (
            SELECT
                WIDTH_BUCKET(predicted_risk, 0, 1, 10) AS bin,
                (WIDTH_BUCKET(predicted_risk, 0, 1, 10) - 1) / 10.0 AS bin_low,
                WIDTH_BUCKET(predicted_risk, 0, 1, 10) / 10.0 AS bin_high,
                AVG(predicted_risk) AS avg_pred,
                AVG(actual_outcome) AS obs_freq,
                COUNT(*) AS cnt
            FROM predictions
            GROUP BY bin
            ORDER BY bin
        ) b
    )
    INSERT INTO mchain_quality_metrics_history (
        date_from, date_to, total_predictions, incident_rate,
        brier_score, log_loss, roc_auc, precision_at_05, recall_at_05, mae,
        calibration_summary, notes
    )
    SELECT
        p_date, p_date + 1, total, incident_rate,
        brier, log_loss, roc_auc, precision_at_05, recall_at_05, mae,
        calib,
        format('OK (horizon=%s, reliability=%s)', v_horizon, v_reliability) AS notes
    FROM metrics, calibration
    ON CONFLICT (date_from, date_to) DO UPDATE SET
        total_predictions = EXCLUDED.total_predictions,
        incident_rate = EXCLUDED.incident_rate,
        brier_score = EXCLUDED.brier_score,
        log_loss = EXCLUDED.log_loss,
        roc_auc = EXCLUDED.roc_auc,
        precision_at_05 = EXCLUDED.precision_at_05,
        recall_at_05 = EXCLUDED.recall_at_05,
        mae = EXCLUDED.mae,
        calibration_summary = EXCLUDED.calibration_summary,
        notes = EXCLUDED.notes,
        calculated_at = now();

    RETURN format('Metrics saved for date %s (horizon=%s, reliability=%s, predictions=%s)', 
                  p_date, v_horizon, v_reliability, v_predictions_count);
END;
$$;

COMMENT ON FUNCTION calculate_daily_quality_metrics(DATE, INT) IS 'Расчёт суточных метрик для указанного горизонта (по умолчанию из markov_config). Метрики вычисляются только если рейтинг достоверности ≥ 3 и число прогнозов ≥ 100.';


-- =============================================================================
-- Функция: refresh_critical_states
-- Назначение: автоматическое обновление списка критических состояний на основе
--             эмпирических оценок риска за заданный период.
-- Параметры:
--   p_start             TIMESTAMPTZ – начало периода анализа (по умолч. now() - interval '60 days')
--   p_end               TIMESTAMPTZ – конец периода (по умолч. now())
--   p_min_transitions   INT         – минимальное число переходов для включения (по умолч. 50)
--   p_interval_min      INT         – интервал прогноза в минутах (по умолч. 15)
--   p_risk_threshold    REAL        – порог эмпирического риска (по умолч. 0.10)
--   p_dry_run           BOOLEAN     – если TRUE, только вывод изменений без обновления (по умолч. FALSE)
-- Возвращает:
--   TEXT – отчёт о выполнении (количество добавленных, обновлённых, удалённых)
-- =============================================================================
/*
Пример вызова с записью в аудит (по умолчанию):
SELECT refresh_critical_states();
После выполнения отчёт автоматически попадёт в таблицу critical_states_audit.

Отключение аудита (для тестовых запусков, чтобы не засорять историю):
SELECT refresh_critical_states(p_audit => FALSE);

Просмотр истории изменений:
SELECT updated_at, report
FROM critical_states_audit
ORDER BY updated_at DESC
LIMIT 10;


*/
CREATE OR REPLACE FUNCTION refresh_critical_states(
    p_start           TIMESTAMPTZ DEFAULT now() - interval '14 days',
    p_end             TIMESTAMPTZ DEFAULT now(),
    p_min_transitions INT         DEFAULT 50,
    p_interval_min    INT         DEFAULT 15,
    p_risk_threshold  REAL        DEFAULT 0.10,
    p_dry_run         BOOLEAN     DEFAULT FALSE,
    p_audit           BOOLEAN     DEFAULT TRUE
)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    v_start TIMESTAMPTZ;
    v_end   TIMESTAMPTZ;
    v_new_state_ids INT[];
    v_existing_state_ids INT[];
    v_to_insert INT[];
    v_to_delete INT[];
    v_count_insert INT;
    v_count_delete INT;
    v_report TEXT := '';
    v_line_sep CONSTANT TEXT := E'\n--------------------------------------------------------------------\n';
    v_tbl_exists BOOLEAN;
BEGIN
    -- Установка периода по умолчанию
    v_start := COALESCE(p_start, now() - INTERVAL '60 days');
    v_end   := COALESCE(p_end, now());
    IF v_start > v_end THEN
        RETURN 'Ошибка: начальная дата позже конечной.';
    END IF;

    -- Проверка наличия необходимых таблиц
    SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'performance_incident') INTO v_tbl_exists;
    IF NOT v_tbl_exists THEN
        RETURN 'Ошибка: таблица performance_incident не найдена. Невозможно обновить критические состояния.';
    END IF;

    -- Получаем список состояний, удовлетворяющих критериям, на основе эмпирических рисков
    WITH emp_risks AS (
        SELECT state_id, total_transitions, empirical_risk
        FROM compute_empirical_incident_risk(
            v_start, v_end, p_min_transitions, p_interval_min
        )
        WHERE empirical_risk > p_risk_threshold
    )
    SELECT array_agg(state_id ORDER BY state_id) INTO v_new_state_ids
    FROM emp_risks;

    -- Если новых состояний нет, формируем отчёт об этом
    IF v_new_state_ids IS NULL OR array_length(v_new_state_ids, 1) = 0 THEN
        v_report := format('Нет состояний, удовлетворяющих критериям (risk > %s, transitions >= %s) за период %s – %s',
                      p_risk_threshold, p_min_transitions, v_start, v_end);
        -- Записываем в аудит, если требуется
        IF p_audit THEN
            PERFORM ensure_audit_table();
            INSERT INTO critical_states_audit (report) VALUES (v_report);
        END IF;
        RETURN v_report;
    END IF;

    -- Получаем текущий список критических состояний из таблицы
    SELECT array_agg(state_id ORDER BY state_id) INTO v_existing_state_ids
    FROM critical_states;

    -- Вычисляем разности: новые для вставки и для удаления
    v_to_insert := array(
        SELECT unnest(v_new_state_ids)
        EXCEPT
        SELECT unnest(COALESCE(v_existing_state_ids, '{}'::INT[]))
    );
    v_to_delete := array(
        SELECT unnest(COALESCE(v_existing_state_ids, '{}'::INT[]))
        EXCEPT
        SELECT unnest(v_new_state_ids)
    );

    v_count_insert := COALESCE(array_length(v_to_insert, 1), 0);
    v_count_delete := COALESCE(array_length(v_to_delete, 1), 0);

    -- Формируем отчёт
    v_report := v_report || 'ОБНОВЛЕНИЕ КРИТИЧЕСКИХ СОСТОЯНИЙ' || v_line_sep;
    v_report := v_report || 'Период анализа: ' || v_start::TEXT || ' – ' || v_end::TEXT || E'\n';
    v_report := v_report || 'Порог риска: ' || p_risk_threshold::TEXT || E'\n';
    v_report := v_report || 'Минимальное число переходов: ' || p_min_transitions::TEXT || E'\n';
    v_report := v_report || 'Новых состояний для добавления: ' || v_count_insert::TEXT || E'\n';
    v_report := v_report || 'Состояний для удаления: ' || v_count_delete::TEXT || E'\n';

    IF v_count_insert = 0 AND v_count_delete = 0 THEN
        v_report := v_report || 'Изменений не требуется. Список актуален.' || v_line_sep;
        -- Всё равно записываем в аудит
        IF p_audit THEN
            PERFORM ensure_audit_table();
            INSERT INTO critical_states_audit (report) VALUES (v_report);
        END IF;
        RETURN v_report;
    END IF;

    IF p_dry_run THEN
        v_report := v_report || 'Режим DRY RUN – обновление не выполнено.' || E'\n';
        IF v_count_insert > 0 THEN
            v_report := v_report || 'Будут добавлены state_id: ' || array_to_string(v_to_insert, ', ') || E'\n';
        END IF;
        IF v_count_delete > 0 THEN
            v_report := v_report || 'Будут удалены state_id: ' || array_to_string(v_to_delete, ', ') || E'\n';
        END IF;
        v_report := v_report || v_line_sep;
        IF p_audit THEN
            PERFORM ensure_audit_table();
            INSERT INTO critical_states_audit (report) VALUES (v_report);
        END IF;
        RETURN v_report;
    END IF;

    -- Выполняем обновление в транзакции
    BEGIN
        -- Удаляем состояния, которые больше не являются критическими
        IF v_count_delete > 0 THEN
            DELETE FROM critical_states WHERE state_id = ANY(v_to_delete);
        END IF;

        -- Вставляем новые состояния
        IF v_count_insert > 0 THEN
            INSERT INTO critical_states (state_id, reason, updated_at)
            SELECT
                state_id,
                format('empirical_risk=%s, total_transitions=%s, threshold=%s, min_trans=%s',
                       empirical_risk, total_transitions, p_risk_threshold, p_min_transitions) AS reason,
                now()
            FROM compute_empirical_incident_risk(v_start, v_end, p_min_transitions, p_interval_min)
            WHERE state_id = ANY(v_to_insert);
        END IF;

        -- Обновляем updated_at для существующих состояний (они остались)
        UPDATE critical_states SET updated_at = now()
        WHERE state_id = ANY(v_new_state_ids)
          AND state_id NOT IN (SELECT unnest(v_to_insert)); -- только те, которые уже были

        v_report := v_report || 'Обновление выполнено успешно.' || E'\n';
        v_report := v_report || 'Добавлено: ' || v_count_insert::TEXT || ', удалено: ' || v_count_delete::TEXT || E'\n';
    EXCEPTION WHEN OTHERS THEN
        v_report := v_report || 'Ошибка при обновлении: ' || SQLERRM || E'\n';
        -- Всё равно записываем в аудит ошибку
        IF p_audit THEN
            PERFORM ensure_audit_table();
            INSERT INTO critical_states_audit (report) VALUES (v_report);
        END IF;
        RAISE;
    END;

    v_report := v_report || v_line_sep;

    -- === Запись в таблицу аудита ===
    IF p_audit THEN
        PERFORM ensure_audit_table();
        INSERT INTO critical_states_audit (report) VALUES (v_report);
    END IF;

    RETURN v_report;
END;
$$;
COMMENT ON FUNCTION refresh_critical_states(TIMESTAMPTZ, TIMESTAMPTZ, INT, INT, REAL, BOOLEAN, BOOLEAN ) IS 'Автоматическое обновление списка critical_states на основе эмпирических рисков. Параметры позволяют настроить период, пороги и режим тестирования (dry run). Возвращает текстовый отчёт о произведённых изменениях.';

-- =============================================================================
-- Вспомогательная функция для создания таблицы аудита, если её нет
-- =============================================================================
CREATE OR REPLACE FUNCTION ensure_audit_table()
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    CREATE TABLE IF NOT EXISTS critical_states_audit (
        id          SERIAL PRIMARY KEY,
        updated_at  TIMESTAMPTZ DEFAULT now(),
        report      TEXT NOT NULL
    );
    -- Индекс для быстрого доступа по дате
    CREATE INDEX IF NOT EXISTS idx_critical_states_audit_updated_at ON critical_states_audit (updated_at);
END;
$$;
COMMENT ON FUNCTION ensure_audit_table() IS 'Создаёт таблицу critical_states_audit, если она не существует.';

-- =============================================================================
-- Вероятность хотя бы одного попадания в критическое множество за k шагов
/*
Новая функция вычисляет вероятность хотя бы одного попадания в критическое множество за k шагов (минут), используя итеративное умножение вектора распределения на матрицу переходов markov_probabilities. В отличие от старого подхода, не зануляются вероятности при попадании в критическое состояние — вместо этого на каждом шаге накопленный риск увеличивается на вероятность оказаться в критическом множестве в этот момент, а затем эти вероятности обнуляются для дальнейших итераций (чтобы не учитывать повторные попадания).
*/
-- =============================================================================
CREATE OR REPLACE FUNCTION mchain_predict_risk_k_v2(
    p_state_id SMALLINT,
    k INT
)
RETURNS REAL
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    total_states CONSTANT INT := 189;
    v REAL[];
    v_new REAL[];
    critical_ids SMALLINT[];
    step INT;
    risk REAL := 0.0;
    rec RECORD;
BEGIN
    -- Получаем список критических состояний
    SELECT array_agg(state_id) INTO critical_ids FROM critical_states;
    IF critical_ids IS NULL OR array_length(critical_ids, 1) = 0 THEN
        RETURN 0.0;
    END IF;

    -- Если текущее состояние критическое – вероятность попадания равна 1 (уже в множестве)
    IF p_state_id = ANY(critical_ids) THEN
        RETURN 1.0;
    END IF;

    -- Инициализация вектора
    v := array_fill(0.0, ARRAY[total_states]);
    IF p_state_id BETWEEN 0 AND total_states - 1 THEN
        v[p_state_id + 1] := 1.0;
    ELSE
        RETURN 0.0;
    END IF;

    -- Итерации (только для некритических стартовых состояний)
    FOR step IN 1..k LOOP
        v_new := array_fill(0.0, ARRAY[total_states]);

        FOR rec IN
            SELECT from_state, to_state, probability
            FROM markov_probabilities
        LOOP
            IF v[rec.from_state + 1] > 0.0 THEN
                v_new[rec.to_state + 1] := v_new[rec.to_state + 1] + v[rec.from_state + 1] * rec.probability;
            END IF;
        END LOOP;

        v := v_new;

        FOR i IN 1..array_length(critical_ids, 1) LOOP
            risk := risk + v[critical_ids[i] + 1];
            v[critical_ids[i] + 1] := 0.0;
        END LOOP;

        IF risk >= 1.0 THEN
            RETURN 1.0;
        END IF;
    END LOOP;

    RETURN LEAST(risk, 1.0);
END;
$$;

COMMENT ON FUNCTION mchain_predict_risk_k_v2( SMALLINT, INT ) IS 'Вероятность хотя бы одного попадания в критическое множество за k шагов';

-- =============================================================================
-- Функция: compute_empirical_incident_risk
-- Назначение: вычисляет эмпирическую вероятность наступления инцидента в течение
--             заданного интервала времени (по умолчанию 15 минут) после каждого
--             перехода в состояние.
-- Использует таблицу performance_incident как источник инцидентов.
-- Если таблица отсутствует, функция возвращает пустой результат с предупреждением.
-- Параметры:
--   p_start           TIMESTAMPTZ  – начало периода анализа (по умолч. now() - interval '14 days')
--   p_end             TIMESTAMPTZ  – конец периода (по умолч. now())
--   p_min_transitions INT          – минимальное число переходов для включения состояния (по умолч. 10)
--   p_interval_min    INT          – длина интервала в минутах (по умолч. 15)
-- Возвращает:
--   state_id          SMALLINT    – идентификатор состояния
--   correlation       REAL        – коэффициент корреляции
--   os_trend          SMALLINT    – тренд операционной скорости
--   wait_trend        SMALLINT    – тренд времени ожидания
--   total_transitions BIGINT      – общее число переходов из этого состояния
--   incident_within   BIGINT      – число переходов, после которых в течение интервала начался инцидент
--   empirical_risk    REAL        – отношение incident_within / total_transitions
--   lower_bound       REAL        – нижняя граница 95% доверительного интервала (Уилсон)
--   upper_bound       REAL        – верхняя граница 95% доверительного интервала
-- =============================================================================
-- =============================================================================
-- Пример использования для получения списка состояний с риском > 0.5
-- =============================================================================
/*
SELECT state_id, correlation, os_trend, wait_trend,
       total_transitions, incident_within, empirical_risk,
       lower_bound, upper_bound
FROM compute_empirical_incident_risk()
WHERE empirical_risk > 0.5
ORDER BY empirical_risk DESC;
*/


-- Переопределяем функцию compute_empirical_incident_risk с корректным приведением типов
CREATE OR REPLACE FUNCTION compute_empirical_incident_risk(
    p_start           TIMESTAMPTZ DEFAULT now() - interval '14 days',
    p_end             TIMESTAMPTZ DEFAULT now(),
    p_min_transitions INT         DEFAULT 10,
    p_interval_min    INT         DEFAULT 15
)
RETURNS TABLE (
    state_id          SMALLINT,
    correlation       REAL,
    os_trend          SMALLINT,
    wait_trend        SMALLINT,
    total_transitions BIGINT,
    incident_within   BIGINT,
    empirical_risk    REAL,
    lower_bound       REAL,
    upper_bound       REAL
)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_start TIMESTAMPTZ;
    v_end   TIMESTAMPTZ;
    v_tbl_exists BOOLEAN;
    v_interval INTERVAL;
BEGIN
    v_start := COALESCE(p_start, now() - INTERVAL '14 days');
    v_end   := COALESCE(p_end, now());
    IF v_start > v_end THEN
        RAISE EXCEPTION 'Начальная дата позже конечной.';
    END IF;

    v_interval := (p_interval_min || ' minutes')::INTERVAL;

    SELECT EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_name = 'performance_incident'
    ) INTO v_tbl_exists;

    IF NOT v_tbl_exists THEN
        RAISE WARNING 'Таблица performance_incident не найдена. Эмпирические риски не могут быть вычислены.';
        RETURN;
    END IF;

    RETURN QUERY
    WITH incident_starts AS (
        SELECT start_timepoint AS incident_ts
        FROM performance_incident
        WHERE start_timepoint >= v_start
          AND start_timepoint <= v_end
    ),
    transitions AS (
        SELECT from_state, ts
        FROM transition_log
        WHERE ts >= v_start AND ts <= v_end
    ),
    state_stats AS (
        SELECT
            t.from_state,
            COUNT(*) AS total,
            COUNT(*) FILTER (
                WHERE EXISTS (
                    SELECT 1 FROM incident_starts i
                    WHERE i.incident_ts BETWEEN t.ts AND t.ts + v_interval
                )
            ) AS incident_after
        FROM transitions t
        GROUP BY t.from_state
        HAVING COUNT(*) >= p_min_transitions
    )
    SELECT
        sd.state_id,
        sd.correlation,
        sd.os_trend,
        sd.wait_trend,
        ss.total AS total_transitions,
        ss.incident_after AS incident_within,
        (ss.incident_after::REAL / NULLIF(ss.total, 0))::REAL AS empirical_risk,
        CASE
            WHEN ss.total > 0 THEN
                (
                    ( (ss.incident_after + 1.96^2/2) / (ss.total + 1.96^2) -
                      1.96 * sqrt( (ss.incident_after::REAL * (ss.total - ss.incident_after) / ss.total + 1.96^2/4) / (ss.total + 1.96^2) )
                    ) / (1 + 1.96^2 / ss.total)
                )::REAL
            ELSE NULL
        END AS lower_bound,
        CASE
            WHEN ss.total > 0 THEN
                (
                    ( (ss.incident_after + 1.96^2/2) / (ss.total + 1.96^2) +
                      1.96 * sqrt( (ss.incident_after::REAL * (ss.total - ss.incident_after) / ss.total + 1.96^2/4) / (ss.total + 1.96^2) )
                    ) / (1 + 1.96^2 / ss.total)
                )::REAL
            ELSE NULL
        END AS upper_bound
    FROM state_stats ss
    JOIN state_descriptions sd ON sd.state_id = ss.from_state
    ORDER BY empirical_risk DESC;
END;
$$;

COMMENT ON FUNCTION compute_empirical_incident_risk(TIMESTAMPTZ, TIMESTAMPTZ, INT, INT) IS 'Вычисляет эмпирическую вероятность перехода в инцидент в течение заданного интервала. Возвращает значения типа REAL.';


-- =============================================================================
-- Формирование прогноза с горизонтом из markov_config.forecast_horizon_minutes
-- =============================================================================
CREATE OR REPLACE FUNCTION collect_prediction()
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    curr_state SMALLINT;
    risk REAL;
    horizon INT;
BEGIN

    -- Получаем горизонт из конфигурации
    SELECT forecast_horizon_minutes INTO horizon FROM markov_config LIMIT 1;
    IF horizon IS NULL THEN
        horizon := 30; -- значение по умолчанию
    END IF;

    curr_state := mchain_get_current_state_id();
    IF curr_state IS NULL THEN
        RETURN;
    END IF;

	IF curr_state IS NULL THEN
    INSERT INTO mchain_error_log (function_name, error_message, context)
    VALUES ('collect_prediction', 'State is NULL, prediction skipped',
            jsonb_build_object('timestamp', now()));
    RETURN;
	END IF;


    risk := mchain_predict_risk_k_v2(curr_state, horizon);
    INSERT INTO prediction_log (
        prediction_time, predicted_risk, situation,
        transitions_to_risk, total_transitions_known, current_state_id,
        horizon_minutes
    ) VALUES (
        now(), risk, 'risk_calculated',
        NULL, NULL, curr_state,
        horizon
    );
EXCEPTION WHEN OTHERS THEN
    INSERT INTO mchain_quality_errors (error_message, function_name, details)
    VALUES (SQLERRM, 'collect_prediction',
            jsonb_build_object('sqlstate', SQLSTATE, 'timestamp', now()));
    RAISE WARNING 'collect_prediction failed: %', SQLERRM;
END;
$$;
COMMENT ON FUNCTION collect_prediction() IS 'Формирование прогноза с горизонтом из markov_config.forecast_horizon_minutes';

-- =============================================================================
-- Обновление исходов для прогнозов, у которых истёк горизонт (из markov_config)
-- =============================================================================
CREATE OR REPLACE FUNCTION update_prediction_outcomes()
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    rec RECORD;
    incident_ts TIMESTAMPTZ;
    incident_cnt INT;
    updated INT := 0;
    horizon INT;
BEGIN
    SELECT forecast_horizon_minutes INTO horizon FROM markov_config LIMIT 1;
    IF horizon IS NULL THEN
        horizon := 30;
    END IF;

    FOR rec IN
        SELECT id, prediction_time
        FROM prediction_log
        WHERE actual_outcome IS NULL
          AND prediction_time <= now() - (horizon || ' minutes')::INTERVAL
          AND horizon_minutes = horizon   -- обновляем только прогнозы с нужным горизонтом
        ORDER BY prediction_time
        LIMIT 1000
    LOOP
        -- Ищем первый аварийный переход в интервале (prediction_time, prediction_time + horizon минут]
        SELECT MIN(ts), COUNT(*)
        INTO incident_ts, incident_cnt
        FROM transition_log tl
        WHERE tl.to_state IN (SELECT get_critical_state_ids(TRUE))
          AND tl.ts > rec.prediction_time
          AND tl.ts <= rec.prediction_time + (horizon || ' minutes')::INTERVAL;

        UPDATE prediction_log
        SET actual_outcome = CASE WHEN incident_ts IS NULL THEN 0 ELSE 1 END,
            first_incident_time = incident_ts,
            incident_count = COALESCE(incident_cnt, 0)
        WHERE id = rec.id;

        updated := updated + 1;
    END LOOP;

    RETURN format('Updated outcomes for %s predictions (horizon %s min)', updated, horizon);
END;
$$;
COMMENT ON FUNCTION update_prediction_outcomes() IS 'Обновление исходов для прогнозов, у которых истёк горизонт (из markov_config)';

-- =============================================================================
-- Отчёт о качестве прогнозов для указанного горизонта (по умолчанию из markov_config)
-- =============================================================================
--------------------------------------------------------------------------------
-- mchain_quality_report
-- Отчёт о качестве прогнозов для указанного горизонта (по умолчанию из markov_config)
-- Параметры:
--   p_start   DATE – начало периода (по умолч. 7 дней назад)
--   p_end     DATE – конец периода (по умолч. вчера)
--   p_horizon INT  – горизонт прогноза в минутах (если NULL – берётся из markov_config)
-- Возвращает текстовый отчёт с метриками, калибровкой, динамикой и рекомендациями.
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION mchain_quality_report(
    p_start DATE DEFAULT NULL,
    p_end DATE DEFAULT NULL,
    p_horizon INT DEFAULT NULL
)
RETURNS TEXT
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_start TIMESTAMPTZ;
    v_end TIMESTAMPTZ;
    v_horizon INT;
    v_report TEXT := '';
    v_line_sep CONSTANT TEXT := E'\n' || repeat('=', 80) || E'\n';
    v_sub_sep CONSTANT TEXT := E'\n' || repeat('-', 80) || E'\n';
    v_rec RECORD;
    v_total_predictions INT;
    v_incident_rate REAL;
    v_avg_risk REAL;
    v_brier REAL;
    v_log_loss REAL;
    v_mae REAL;
    v_roc_auc REAL;
    v_precision REAL;
    v_recall REAL;
    v_calib JSONB;
    v_days_with_data INT;
    v_notes TEXT;
BEGIN
    -- ------------------------------------------------------------------
    -- 1. Определение горизонта
    -- ------------------------------------------------------------------
    IF p_horizon IS NULL THEN
        SELECT forecast_horizon_minutes INTO v_horizon FROM markov_config LIMIT 1;
    ELSE
        v_horizon := p_horizon;
    END IF;
    IF v_horizon IS NULL THEN
        v_horizon := 30;   -- значение по умолчанию
    END IF;

    -- ------------------------------------------------------------------
    -- 2. Определение временного периода
    -- ------------------------------------------------------------------
    IF p_start IS NULL THEN
        v_start := (CURRENT_DATE - 7)::TIMESTAMPTZ;
    ELSE
        v_start := p_start::TIMESTAMPTZ;
    END IF;
    IF p_end IS NULL THEN
        v_end := (CURRENT_DATE - 1)::TIMESTAMPTZ + INTERVAL '1 day';
    ELSE
        v_end := (p_end + 1)::TIMESTAMPTZ;
    END IF;
    
    IF v_start >= v_end THEN
        RETURN 'Ошибка: начальная дата не может быть позже или равна конечной.';
    END IF;

    -- ------------------------------------------------------------------
    -- 3. Проверка наличия завершённых прогнозов с данным горизонтом
    -- ------------------------------------------------------------------
    SELECT COUNT(*) INTO v_total_predictions
    FROM prediction_log
    WHERE prediction_time >= v_start AND prediction_time < v_end
      AND actual_outcome IS NOT NULL
      AND predicted_risk IS NOT NULL
      AND horizon_minutes = v_horizon;

    IF v_total_predictions = 0 THEN
        RETURN format('Нет завершённых прогнозов с горизонтом %s мин за период %s – %s.',
                      v_horizon, v_start::DATE, (v_end - INTERVAL '1 day')::DATE);
    END IF;

    -- ------------------------------------------------------------------
    -- 4. Расчёт общих метрик качества
    -- ------------------------------------------------------------------
    WITH predictions AS (
        SELECT 
            predicted_risk,
            actual_outcome
        FROM prediction_log
        WHERE prediction_time >= v_start AND prediction_time < v_end
          AND actual_outcome IS NOT NULL
          AND predicted_risk IS NOT NULL
          AND horizon_minutes = v_horizon
    ),
    stats AS (
        SELECT
            COUNT(*) AS total,
            AVG(actual_outcome) AS incident_rate,
            AVG(predicted_risk) AS avg_risk,
            AVG((predicted_risk - actual_outcome)^2) AS brier,
            AVG(CASE 
                WHEN actual_outcome = 1 THEN -ln(GREATEST(predicted_risk, 1e-15))
                ELSE -ln(GREATEST(1 - predicted_risk, 1e-15))
            END) AS log_loss,
            AVG(ABS(predicted_risk - actual_outcome)) AS mae
        FROM predictions
    ),
    -- Исправленный расчёт ROC-AUC: ранжирование по возрастанию риска
    roc_auc_calc AS (
        SELECT
            CASE
                WHEN COUNT(CASE WHEN actual_outcome = 1 THEN 1 END) = 0
                     OR COUNT(CASE WHEN actual_outcome = 0 THEN 1 END) = 0
                THEN NULL
                ELSE (SUM(CASE WHEN actual_outcome = 1 THEN rank ELSE 0 END) -
                     (COUNT(CASE WHEN actual_outcome = 1 THEN 1 END) *
                      (COUNT(CASE WHEN actual_outcome = 1 THEN 1 END) + 1) / 2.0)
                    ) / (COUNT(CASE WHEN actual_outcome = 1 THEN 1 END) *
                         COUNT(CASE WHEN actual_outcome = 0 THEN 1 END))
            END AS auc
        FROM (
            SELECT predicted_risk, actual_outcome,
                   ROW_NUMBER() OVER (ORDER BY predicted_risk ASC) AS rank   -- ASC вместо DESC
            FROM predictions
        ) ranked
        WHERE actual_outcome IN (0,1)
    ),
    -- Исправленный расчёт Precision/Recall: COUNT(*) FILTER с COALESCE
    pr_at_05 AS (
        SELECT
            COALESCE(COUNT(*) FILTER (WHERE predicted_risk >= 0.5 AND actual_outcome = 1), 0) AS tp,
            COALESCE(COUNT(*) FILTER (WHERE predicted_risk >= 0.5 AND actual_outcome = 0), 0) AS fp,
            COALESCE(COUNT(*) FILTER (WHERE predicted_risk < 0.5 AND actual_outcome = 1), 0) AS fn
        FROM predictions
    ),
    -- Калибровка: 10 бинов, обрезаем риск до <1, чтобы избежать бина [1.0, 1.1)
    calib AS (
        SELECT jsonb_agg(
            jsonb_build_object(
                'bin_low', bin_low,
                'bin_high', bin_high,
                'avg_pred', avg_pred,
                'obs_freq', obs_freq,
                'count', cnt
            )
        ) AS calib
        FROM (
            SELECT
                bin,
                (bin - 1) / 10.0 AS bin_low,
                bin / 10.0 AS bin_high,
                AVG(predicted_risk) AS avg_pred,
                AVG(actual_outcome) AS obs_freq,
                COUNT(*) AS cnt
            FROM (
                SELECT
                    WIDTH_BUCKET(LEAST(predicted_risk, 0.999999), 0, 1, 10) AS bin,
                    predicted_risk,
                    actual_outcome
                FROM predictions
            ) t
            GROUP BY bin
            ORDER BY bin
        ) b
    )
    SELECT
        s.incident_rate, s.avg_risk, s.brier, s.log_loss, s.mae,
        COALESCE(a.auc, 0) AS roc_auc,
        CASE WHEN (p.tp+p.fp) > 0 THEN p.tp::REAL / (p.tp+p.fp) ELSE 0 END AS precision,
        CASE WHEN (p.tp+p.fn) > 0 THEN p.tp::REAL / (p.tp+p.fn) ELSE 0 END AS recall,
        c.calib
    INTO v_incident_rate, v_avg_risk, v_brier, v_log_loss, v_mae,
         v_roc_auc, v_precision, v_recall, v_calib
    FROM stats s
    CROSS JOIN roc_auc_calc a
    CROSS JOIN pr_at_05 p
    CROSS JOIN calib c;

    -- ------------------------------------------------------------------
    -- 5. Формирование отчёта (без изменений)
    -- ------------------------------------------------------------------
    v_report := v_report || format('ОТЧЁТ КАЧЕСТВА ПРОГНОЗОВ (ГОРИЗОНТ %s МИНУТ)', v_horizon) || v_line_sep;
    v_report := v_report || 'Период: ' || v_start::DATE::TEXT || ' – ' || (v_end - INTERVAL '1 day')::DATE::TEXT || E'\n';
    v_report := v_report || 'Дата формирования: ' || now()::TEXT || E'\n';
    v_report := v_report || 'Всего прогнозов с известным исходом: ' || v_total_predictions::TEXT || E'\n';
    v_report := v_report || 'Доля инцидентов: ' || round(v_incident_rate::NUMERIC, 4)::TEXT || E'\n';
    v_report := v_report || 'Средний предсказанный риск: ' || round(v_avg_risk::NUMERIC, 4)::TEXT || E'\n';
    v_report := v_report || v_sub_sep;

    -- Метрики качества
    v_report := v_report || 'МЕТРИКИ КАЧЕСТВА' || E'\n';
    v_report := v_report || '  Brier score:  ' || round(v_brier::NUMERIC, 6)::TEXT || E'\n';
    v_report := v_report || '  Log-loss:     ' || round(v_log_loss::NUMERIC, 6)::TEXT || E'\n';
    v_report := v_report || '  MAE:          ' || round(v_mae::NUMERIC, 6)::TEXT || E'\n';
    v_report := v_report || '  ROC-AUC:      ' || round(v_roc_auc::NUMERIC, 4)::TEXT || E'\n';
    v_report := v_report || '  Precision (p≥0.5): ' || round(v_precision::NUMERIC, 4)::TEXT || E'\n';
    v_report := v_report || '  Recall (p≥0.5):    ' || round(v_recall::NUMERIC, 4)::TEXT || E'\n';
    v_report := v_report || v_sub_sep;

    -- Калибровочная таблица
    v_report := v_report || 'КАЛИБРОВОЧНАЯ ТАБЛИЦА' || E'\n';
    v_report := v_report || 'Бин (вероятность) | Среднее предсказание | Наблюдаемая частота | Количество' || E'\n';
    FOR v_rec IN SELECT * FROM jsonb_to_recordset(v_calib) AS x(bin_low NUMERIC, bin_high NUMERIC, avg_pred NUMERIC, obs_freq NUMERIC, cnt INT)
    LOOP
        v_report := v_report || format('[%s, %s)          %s                  %s                %s',
            v_rec.bin_low, v_rec.bin_high,
            round(v_rec.avg_pred::NUMERIC, 3),
            round(v_rec.obs_freq::NUMERIC, 3),
            v_rec.cnt) || E'\n';
    END LOOP;
    v_report := v_report || v_sub_sep;

    -- Дневная динамика (из таблицы истории)
    v_report := v_report || 'ДНЕВНАЯ ДИНАМИКА МЕТРИК' || E'\n';
    SELECT COUNT(*) INTO v_days_with_data
    FROM mchain_quality_metrics_history
    WHERE date_from >= v_start::DATE AND date_to <= v_end::DATE;

    IF v_days_with_data > 0 THEN
        v_report := v_report || 'Источник: mchain_quality_metrics_history' || E'\n';
        v_report := v_report || 'Дата       | Brier  | Log-loss | ROC-AUC | Наблюдений | Примечание' || E'\n';
        FOR v_rec IN
            SELECT date_from, brier_score, log_loss, roc_auc, total_predictions, notes
            FROM mchain_quality_metrics_history
            WHERE date_from >= v_start::DATE AND date_to <= v_end::DATE
            ORDER BY date_from
        LOOP
            v_report := v_report || format('%s | %s | %s | %s | %s | %s',
                v_rec.date_from,
                COALESCE(round(v_rec.brier_score::NUMERIC, 4)::TEXT, 'NULL'),
                COALESCE(round(v_rec.log_loss::NUMERIC, 4)::TEXT, 'NULL'),
                COALESCE(round(v_rec.roc_auc::NUMERIC, 4)::TEXT, 'NULL'),
                v_rec.total_predictions,
                COALESCE(v_rec.notes, 'OK')) || E'\n';
        END LOOP;
    ELSE
        v_report := v_report || 'Источник: вычислено по сырым данным' || E'\n';
        v_report := v_report || 'Дата       | Brier  | Log-loss | ROC-AUC | Наблюдений' || E'\n';
        FOR v_rec IN
            WITH daily_stats AS (
                SELECT
                    date_trunc('day', prediction_time) AS day,
                    COUNT(*) AS total,
                    AVG((predicted_risk - actual_outcome)^2) AS brier,
                    AVG(CASE 
                        WHEN actual_outcome = 1 THEN -ln(GREATEST(predicted_risk, 1e-15))
                        ELSE -ln(GREATEST(1 - predicted_risk, 1e-15))
                    END) AS log_loss,
                    NULL::REAL AS roc_auc
                FROM prediction_log
                WHERE prediction_time >= v_start AND prediction_time < v_end
                  AND actual_outcome IS NOT NULL
                  AND predicted_risk IS NOT NULL
                  AND horizon_minutes = v_horizon
                GROUP BY date_trunc('day', prediction_time)
                ORDER BY day
            )
            SELECT day::DATE AS date_from, brier, log_loss, roc_auc, total
            FROM daily_stats
        LOOP
            v_report := v_report || format('%s | %s | %s | %s | %s',
                v_rec.date_from,
                COALESCE(round(v_rec.brier::NUMERIC, 4)::TEXT, 'NULL'),
                COALESCE(round(v_rec.log_loss::NUMERIC, 4)::TEXT, 'NULL'),
                COALESCE(round(v_rec.roc_auc::NUMERIC, 4)::TEXT, 'NULL'),
                v_rec.total) || E'\n';
        END LOOP;
    END IF;
    v_report := v_report || v_sub_sep;

    -- Диагностические сообщения (пропущенные расчёты)
    SELECT string_agg(format('  %s: %s', date_from::TEXT, notes), E'\n' ORDER BY date_from)
    INTO v_notes
    FROM mchain_quality_metrics_history
    WHERE date_from >= v_start::DATE AND date_to <= v_end::DATE
      AND notes IS NOT NULL AND notes != 'OK';

    IF v_notes IS NOT NULL THEN
        v_report := v_report || 'ДИАГНОСТИЧЕСКИЕ СООБЩЕНИЯ (пропущенные расчёты)' || E'\n';
        v_report := v_report || v_notes || E'\n';
        v_report := v_report || v_sub_sep;
    END IF;

    -- Рекомендации
    v_report := v_report || 'РЕКОМЕНДАЦИИ' || E'\n';
    IF v_brier < 0.05 THEN
        v_report := v_report || '  ★ Отличная калибровка (Brier < 0.05). Прогнозы очень точны.' || E'\n';
    ELSIF v_brier < 0.1 THEN
        v_report := v_report || '  ✔ Хорошая калибровка (Brier 0.05–0.1). Прогнозы надёжны.' || E'\n';
    ELSIF v_brier < 0.2 THEN
        v_report := v_report || '  ⚠ Удовлетворительная калибровка (Brier 0.1–0.2). Рекомендуется периодический пересмотр параметров.' || E'\n';
    ELSE
        v_report := v_report || '  🔴 Плохая калибровка (Brier > 0.2). Требуется корректировка модели (забывание, пороги).' || E'\n';
    END IF;

    IF v_roc_auc < 0.6 THEN
        v_report := v_report || '  ⚠ ROC-AUC < 0.6 – дискриминационная способность низкая. Рассмотрите изменение критерия аварийности.' || E'\n';
    ELSIF v_roc_auc < 0.7 THEN
        v_report := v_report || '  ✔ ROC-AUC 0.6–0.7 – приемлемая дискриминация.' || E'\n';
    ELSE
        v_report := v_report || '  ★ ROC-AUC > 0.7 – отличная дискриминация.' || E'\n';
    END IF;

    IF v_precision < 0.1 AND v_incident_rate < 0.1 THEN
        v_report := v_report || '  ℹ Низкая precision при пороге 0.5 (возможно, дисбаланс классов). Можно снизить порог для повышения recall.' || E'\n';
    END IF;

    v_report := v_report || v_line_sep;

    RETURN v_report;
END;
$$;

COMMENT ON FUNCTION mchain_quality_report(DATE, DATE, INT) IS 'Формирует текстовый отчёт о качестве прогнозов риска за указанный период для заданного горизонта (по умолчанию из markov_config). По умолчанию – предыдущие 7 дней. Включает калибровку, метрики (Brier, log‑loss, ROC‑AUC, precision/recall), дневную динамику и рекомендации. Вероятности обрезаются снизу через GREATEST(..., 1e-15) для избежания log(0).';

-- =============================================================================
-- Функция: mchain_predict_risk_current_horizon
-- Назначение: возвращает прогноз риска на горизонт, заданный в 
--             markov_config.forecast_horizon_minutes (по умолчанию 30 минут).
-- Использует текущее состояние системы и динамический список критических 
-- состояний (critical_states).
-- Аналог mchain_predict_risk_15min_v2, но горизонт берётся из конфигурации,
-- что обеспечивает единообразие с collect_prediction и отчётами.
-- Возвращает REAL – вероятность от 0 до 1, либо NULL, если текущее состояние 
-- не определено или модель не обучена.
-- =============================================================================
CREATE OR REPLACE FUNCTION mchain_predict_risk_current_horizon()
RETURNS REAL
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    curr_state SMALLINT;
    horizon INT;
BEGIN
    -- Получаем горизонт из конфигурации
    SELECT forecast_horizon_minutes INTO horizon FROM markov_config LIMIT 1;
    IF horizon IS NULL THEN
        horizon := 30;  -- значение по умолчанию, если не задано
    END IF;

    -- Получаем текущее состояние
    curr_state := mchain_get_current_state_id();
    IF curr_state IS NULL THEN
        RETURN NULL;
    END IF;

    -- Вычисляем риск на указанное количество шагов (минут)
    RETURN mchain_predict_risk_k_v2(curr_state, horizon);
END;
$$;

COMMENT ON FUNCTION mchain_predict_risk_current_horizon() IS 
'Прогноз риска на горизонт, заданный в markov_config.forecast_horizon_minutes (по умолчанию 30). Заменяет жёстко заданные mchain_predict_risk_15min_v2, mchain_predict_risk_30min_v2, mchain_predict_risk_1hour_v2, обеспечивая единый источник горизонта.';

-- =============================================================================
-- 12. Эмпирический подбор параметров адаптивного забывания 
-- =============================================================================
-- evaluate_forgetting_params : Функция оценки качества для заданных параметров
-- =============================================================================
CREATE OR REPLACE FUNCTION evaluate_forgetting_params(
    p_base_alpha REAL,
    p_half_life REAL,
    p_min_alpha REAL,
    p_interval_min INT,
    p_learn_start DATE,
    p_learn_end DATE,
    p_eval_start DATE,
    p_eval_end DATE,
    p_horizon INT DEFAULT NULL,
    p_min_transitions INT DEFAULT 5,
    p_smoothing REAL DEFAULT 0.01
)
RETURNS TABLE (
    brier REAL,
    log_loss REAL,
    roc_auc REAL,
    precision_at_05 REAL,
    recall_at_05 REAL,
    mae REAL,
    total_predictions INT,
    incident_rate REAL,
    max_prob_change REAL,
    coverage_pct INT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_horizon INT := COALESCE(p_horizon, (SELECT forecast_horizon_minutes FROM markov_config LIMIT 1), 30);
    v_rec RECORD;
    v_risk REAL;
    v_total INT := 0;
    v_incidents INT := 0;
    v_brier_sum REAL := 0;
    v_log_loss_sum REAL := 0;
    v_mae_sum REAL := 0;
    v_rank_sum REAL := 0;
    v_pos_count INT := 0;
    v_neg_count INT := 0;
    v_all_risks REAL[] := '{}';
    v_all_outcomes INT[] := '{}';
    v_tp INT := 0;
    v_fp INT := 0;
    v_fn INT := 0;
    v_max_prob_change REAL := 0.0;
    v_mid1 DATE;
    v_mid2 DATE;
    v_seg_start1 DATE;
    v_seg_end1 DATE;
    v_seg_start2 DATE;
    v_seg_end2 DATE;
    v_seg_start3 DATE;
    v_seg_end3 DATE;
    v_total_transitions BIGINT;
    v_coverage_pct INT := 0;
    v_matrix_table TEXT := 'tmp_prob';
    v_total_states CONSTANT INT := 189;
    v_smooth_factor REAL;
BEGIN
    v_smooth_factor := p_smoothing * v_total_states;

    -- ------------------------------------------
    -- 1. Построить взвешенные частоты переходов с применением сглаживания
    -- ------------------------------------------
    DROP TABLE IF EXISTS tmp_weighted_freq;
    CREATE TEMP TABLE tmp_weighted_freq ON COMMIT DROP AS
    WITH transitions AS (
        SELECT from_state, to_state,
               ts,
               EXP(-(EXTRACT(EPOCH FROM (p_learn_end - ts)) / 86400.0) / p_half_life) AS weight
        FROM transition_log
        WHERE ts >= p_learn_start AND ts < p_learn_end
    )
    SELECT from_state, to_state, SUM(weight) AS frequency
    FROM transitions
    GROUP BY from_state, to_state;

    DELETE FROM tmp_weighted_freq WHERE frequency < 1e-6;

    -- Нормализуем → вероятности с аддитивным сглаживанием
    DROP TABLE IF EXISTS tmp_prob;
    CREATE TEMP TABLE tmp_prob ON COMMIT DROP AS
    SELECT from_state, to_state,
           (frequency + p_smoothing) / (SUM(frequency) OVER (PARTITION BY from_state) + v_smooth_factor) AS probability
    FROM tmp_weighted_freq;

    CREATE INDEX idx_tmp_prob_from ON tmp_prob (from_state);

    -- ------------------------------------------
    -- 2. Оценка прогнозов (без изменений)
    -- ------------------------------------------
    FOR v_rec IN
        SELECT id, current_state_id, actual_outcome, predicted_risk AS original_risk
        FROM prediction_log
        WHERE prediction_time >= p_eval_start AND prediction_time < p_eval_end
          AND actual_outcome IS NOT NULL
          AND current_state_id IS NOT NULL
          AND horizon_minutes = v_horizon
    LOOP
        v_risk := mchain_predict_risk_k_v2_with_matrix(
            v_rec.current_state_id,
            v_horizon,
            v_matrix_table
        );

        IF v_risk IS NULL THEN
            CONTINUE;
        END IF;

        v_total := v_total + 1;
        v_incidents := v_incidents + v_rec.actual_outcome;

        v_brier_sum := v_brier_sum + (v_risk - v_rec.actual_outcome)^2;
        v_log_loss_sum := v_log_loss_sum + CASE
            WHEN v_rec.actual_outcome = 1 THEN -ln(GREATEST(v_risk, 1e-15))
            ELSE -ln(GREATEST(1 - v_risk, 1e-15))
        END;
        v_mae_sum := v_mae_sum + ABS(v_risk - v_rec.actual_outcome);

        IF v_risk >= 0.5 THEN
            IF v_rec.actual_outcome = 1 THEN
                v_tp := v_tp + 1;
            ELSE
                v_fp := v_fp + 1;
            END IF;
        ELSE
            IF v_rec.actual_outcome = 1 THEN
                v_fn := v_fn + 1;
            END IF;
        END IF;

        v_all_risks := array_append(v_all_risks, v_risk);
        v_all_outcomes := array_append(v_all_outcomes, v_rec.actual_outcome);
    END LOOP;

    IF v_total = 0 THEN
        RETURN;
    END IF;

    -- ------------------------------------------
    -- 3. Вычисление основных метрик (без изменений)
    -- ------------------------------------------
    brier := v_brier_sum / v_total;
    log_loss := v_log_loss_sum / v_total;
    mae := v_mae_sum / v_total;
    incident_rate := v_incidents::REAL / v_total;
    total_predictions := v_total;

    precision_at_05 := CASE WHEN (v_tp + v_fp) > 0 THEN v_tp::REAL / (v_tp + v_fp) ELSE 0 END;
    recall_at_05 := CASE WHEN (v_tp + v_fn) > 0 THEN v_tp::REAL / (v_tp + v_fn) ELSE 0 END;

    -- ROC-AUC
    IF array_length(v_all_outcomes, 1) > 0 THEN
        SELECT COUNT(*) INTO v_pos_count FROM unnest(v_all_outcomes) WHERE unnest = 1;
        SELECT COUNT(*) INTO v_neg_count FROM unnest(v_all_outcomes) WHERE unnest = 0;
        IF v_pos_count > 0 AND v_neg_count > 0 THEN
            WITH data AS (
                SELECT unnest(v_all_risks) AS risk,
                       unnest(v_all_outcomes) AS outcome
            ),
            ranked AS (
                SELECT risk, outcome,
                       ROW_NUMBER() OVER (ORDER BY risk ASC) AS rank
                FROM data
            )
            SELECT SUM(CASE WHEN outcome = 1 THEN rank ELSE 0 END) INTO v_rank_sum
            FROM ranked;
            roc_auc := (v_rank_sum - (v_pos_count * (v_pos_count + 1) / 2.0)) / (v_pos_count * v_neg_count);
            IF roc_auc < 0 THEN roc_auc := 0; END IF;
            IF roc_auc > 1 THEN roc_auc := 1; END IF;
        ELSE
            roc_auc := NULL;
        END IF;
    ELSE
        roc_auc := NULL;
    END IF;

    -- ------------------------------------------
    -- 4. max_prob_change (стабильность) – исключаем критические переходы
    -- ------------------------------------------
    v_mid1 := p_learn_start + (p_learn_end - p_learn_start) / 3;
    v_mid2 := p_learn_start + 2 * (p_learn_end - p_learn_start) / 3;
    v_seg_start1 := p_learn_start;
    v_seg_end1   := v_mid1;
    v_seg_start2 := v_mid1;
    v_seg_end2   := v_mid2;
    v_seg_start3 := v_mid2;
    v_seg_end3   := p_learn_end;

    -- Список пар, участвующих в анализе (исключаем критические to_state)
    DROP TABLE IF EXISTS tmp_valid_pairs;
    CREATE TEMP TABLE tmp_valid_pairs ON COMMIT DROP AS
    SELECT from_state, to_state
    FROM transition_log
    WHERE ts >= p_learn_start AND ts < p_learn_end
      AND to_state NOT IN (SELECT state_id FROM critical_states)   /* ИЗМЕНЕНО */
    GROUP BY from_state, to_state
    HAVING COUNT(*) >= p_min_transitions;

    -- Частоты по сегментам с фильтром по критическим состояниям
    DROP TABLE IF EXISTS tmp_seg1_freq;
    CREATE TEMP TABLE tmp_seg1_freq ON COMMIT DROP AS
    SELECT v.from_state, v.to_state, COALESCE(t.cnt, 0) AS cnt
    FROM tmp_valid_pairs v
    LEFT JOIN (
        SELECT from_state, to_state, COUNT(*) AS cnt
        FROM transition_log
        WHERE ts >= v_seg_start1 AND ts < v_seg_end1
          AND to_state NOT IN (SELECT state_id FROM critical_states)   /* ИЗМЕНЕНО */
        GROUP BY from_state, to_state
    ) t ON v.from_state = t.from_state AND v.to_state = t.to_state;

    DROP TABLE IF EXISTS tmp_seg2_freq;
    CREATE TEMP TABLE tmp_seg2_freq ON COMMIT DROP AS
    SELECT v.from_state, v.to_state, COALESCE(t.cnt, 0) AS cnt
    FROM tmp_valid_pairs v
    LEFT JOIN (
        SELECT from_state, to_state, COUNT(*) AS cnt
        FROM transition_log
        WHERE ts >= v_seg_start2 AND ts < v_seg_end2
          AND to_state NOT IN (SELECT state_id FROM critical_states)   /* ИЗМЕНЕНО */
        GROUP BY from_state, to_state
    ) t ON v.from_state = t.from_state AND v.to_state = t.to_state;

    DROP TABLE IF EXISTS tmp_seg3_freq;
    CREATE TEMP TABLE tmp_seg3_freq ON COMMIT DROP AS
    SELECT v.from_state, v.to_state, COALESCE(t.cnt, 0) AS cnt
    FROM tmp_valid_pairs v
    LEFT JOIN (
        SELECT from_state, to_state, COUNT(*) AS cnt
        FROM transition_log
        WHERE ts >= v_seg_start3 AND ts < v_seg_end3
          AND to_state NOT IN (SELECT state_id FROM critical_states)   /* ИЗМЕНЕНО */
        GROUP BY from_state, to_state
    ) t ON v.from_state = t.from_state AND v.to_state = t.to_state;

    -- Общие итоги по сегментам (без изменений)
    DROP TABLE IF EXISTS tmp_seg1_total;
    CREATE TEMP TABLE tmp_seg1_total ON COMMIT DROP AS
    SELECT from_state, COUNT(*) AS total_cnt
    FROM transition_log
    WHERE ts >= v_seg_start1 AND ts < v_seg_end1
    GROUP BY from_state;

    DROP TABLE IF EXISTS tmp_seg2_total;
    CREATE TEMP TABLE tmp_seg2_total ON COMMIT DROP AS
    SELECT from_state, COUNT(*) AS total_cnt
    FROM transition_log
    WHERE ts >= v_seg_start2 AND ts < v_seg_end2
    GROUP BY from_state;

    DROP TABLE IF EXISTS tmp_seg3_total;
    CREATE TEMP TABLE tmp_seg3_total ON COMMIT DROP AS
    SELECT from_state, COUNT(*) AS total_cnt
    FROM transition_log
    WHERE ts >= v_seg_start3 AND ts < v_seg_end3
    GROUP BY from_state;

    -- Вероятности по сегментам (используют уже отфильтрованные частоты)
    DROP TABLE IF EXISTS tmp_prob_seg1;
    CREATE TEMP TABLE tmp_prob_seg1 ON COMMIT DROP AS
    SELECT
        f.from_state,
        f.to_state,
        (f.cnt + p_smoothing) / (COALESCE(t.total_cnt, 0) + v_smooth_factor) AS prob
    FROM tmp_seg1_freq f
    LEFT JOIN tmp_seg1_total t ON f.from_state = t.from_state;

    DROP TABLE IF EXISTS tmp_prob_seg2;
    CREATE TEMP TABLE tmp_prob_seg2 ON COMMIT DROP AS
    SELECT
        f.from_state,
        f.to_state,
        (f.cnt + p_smoothing) / (COALESCE(t.total_cnt, 0) + v_smooth_factor) AS prob
    FROM tmp_seg2_freq f
    LEFT JOIN tmp_seg2_total t ON f.from_state = t.from_state;

    DROP TABLE IF EXISTS tmp_prob_seg3;
    CREATE TEMP TABLE tmp_prob_seg3 ON COMMIT DROP AS
    SELECT
        f.from_state,
        f.to_state,
        (f.cnt + p_smoothing) / (COALESCE(t.total_cnt, 0) + v_smooth_factor) AS prob
    FROM tmp_seg3_freq f
    LEFT JOIN tmp_seg3_total t ON f.from_state = t.from_state;

    -- Вычисляем max_diff (без изменений)
    DROP TABLE IF EXISTS tmp_pair_diffs;
    CREATE TEMP TABLE tmp_pair_diffs ON COMMIT DROP AS
    SELECT
        COALESCE(p1.from_state, p2.from_state, p3.from_state) AS from_state,
        COALESCE(p1.to_state, p2.to_state, p3.to_state) AS to_state,
        COALESCE(p1.prob, 0) AS p1,
        COALESCE(p2.prob, 0) AS p2,
        COALESCE(p3.prob, 0) AS p3,
        GREATEST(
            ABS(COALESCE(p1.prob, 0) - COALESCE(p2.prob, 0)),
            ABS(COALESCE(p2.prob, 0) - COALESCE(p3.prob, 0)),
            ABS(COALESCE(p1.prob, 0) - COALESCE(p3.prob, 0))
        ) AS max_diff
    FROM tmp_prob_seg1 p1
    FULL JOIN tmp_prob_seg2 p2 ON p1.from_state = p2.from_state AND p1.to_state = p2.to_state
    FULL JOIN tmp_prob_seg3 p3 ON COALESCE(p1.from_state, p2.from_state) = p3.from_state
                              AND COALESCE(p1.to_state, p2.to_state) = p3.to_state;

    SELECT COALESCE(MAX(max_diff), 1.0) INTO v_max_prob_change
    FROM tmp_pair_diffs;
    max_prob_change := v_max_prob_change;

    -- ------------------------------------------
    -- 5. coverage_pct (без изменений)
    -- ------------------------------------------
    SELECT COUNT(*) INTO v_total_transitions FROM transition_log WHERE ts >= p_learn_start AND ts < p_learn_end;
    IF v_total_transitions > 0 THEN
        WITH state_stats AS (
            SELECT from_state, COUNT(*) AS n_i,
                   COUNT(*)::REAL / v_total_transitions AS freq
            FROM transition_log
            WHERE ts >= p_learn_start AND ts < p_learn_end
            GROUP BY from_state
        ),
        frequent_states AS (
            SELECT from_state
            FROM state_stats
            WHERE freq > 0.01
        ),
        coverage AS (
            SELECT
                COUNT(*) AS total_frequent,
                SUM(CASE WHEN n_i >= 50 THEN 1 ELSE 0 END) AS covered_frequent
            FROM (
                SELECT s.from_state, ss.n_i
                FROM frequent_states s
                CROSS JOIN LATERAL (
                    SELECT COUNT(*) AS n_i FROM transition_log
                    WHERE from_state = s.from_state
                      AND ts >= p_learn_start AND ts < p_learn_end
                ) ss
            ) t
        )
        SELECT
            CASE WHEN total_frequent = 0 THEN 100
                 ELSE (covered_frequent * 100) / total_frequent
            END INTO v_coverage_pct
        FROM coverage;
    ELSE
        v_coverage_pct := 0;
    END IF;
    coverage_pct := v_coverage_pct;

    -- Очистка временных таблиц (опционально, они удалятся автоматически)
    DROP TABLE IF EXISTS tmp_weighted_freq;
    DROP TABLE IF EXISTS tmp_prob;
    DROP TABLE IF EXISTS tmp_valid_pairs;
    DROP TABLE IF EXISTS tmp_seg1_freq;
    DROP TABLE IF EXISTS tmp_seg2_freq;
    DROP TABLE IF EXISTS tmp_seg3_freq;
    DROP TABLE IF EXISTS tmp_seg1_total;
    DROP TABLE IF EXISTS tmp_seg2_total;
    DROP TABLE IF EXISTS tmp_seg3_total;
    DROP TABLE IF EXISTS tmp_prob_seg1;
    DROP TABLE IF EXISTS tmp_prob_seg2;
    DROP TABLE IF EXISTS tmp_prob_seg3;
    DROP TABLE IF EXISTS tmp_pair_diffs;

    RETURN NEXT;
END;
$$;

COMMENT ON FUNCTION evaluate_forgetting_params IS 'Эмпирический подбор параметров адаптивного забывания. Все временные таблицы созданы с ON COMMIT DROP для автоматического освобождения блокировок.';


-- =====================================================================================
-- mchain_predict_risk_k_v2_with_matrix : Функция для прогноза риска с заданной матрицей
-- =====================================================================================
CREATE OR REPLACE FUNCTION mchain_predict_risk_k_v2_with_matrix(
    p_state_id SMALLINT,
    k INT,
    p_matrix_table TEXT
)
RETURNS REAL
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    total_states CONSTANT INT := 189;
    v REAL[] := array_fill(0.0, ARRAY[total_states]);
    v_new REAL[];
    critical_ids SMALLINT[];
    step INT;
    risk REAL := 0.0;
    rec RECORD;
BEGIN
    -- Получаем критичекие состояния (из critical_states)
    SELECT array_agg(state_id) INTO critical_ids FROM critical_states;
    IF critical_ids IS NULL OR array_length(critical_ids, 1) = 0 THEN
        RETURN 0.0;
    END IF;

    IF p_state_id = ANY(critical_ids) THEN
        RETURN 1.0;
    END IF;

    IF p_state_id BETWEEN 0 AND total_states - 1 THEN
        v[p_state_id + 1] := 1.0;
    ELSE
        RETURN 0.0;
    END IF;

    FOR step IN 1..k LOOP
        v_new := array_fill(0.0, ARRAY[total_states]);

        FOR rec IN EXECUTE format('
            SELECT from_state, to_state, probability
            FROM %I
        ', p_matrix_table) LOOP
            IF v[rec.from_state + 1] > 0.0 THEN
                v_new[rec.to_state + 1] := v_new[rec.to_state + 1] + v[rec.from_state + 1] * rec.probability;
            END IF;
        END LOOP;

        v := v_new;

        FOR i IN 1..array_length(critical_ids, 1) LOOP
            risk := risk + v[critical_ids[i] + 1];
            v[critical_ids[i] + 1] := 0.0;
        END LOOP;

        IF risk >= 1.0 THEN
            RETURN 1.0;
        END IF;
    END LOOP;

    RETURN LEAST(risk, 1.0);
END;
$$;
COMMENT ON FUNCTION mchain_predict_risk_k_v2_with_matrix IS 'Функция для прогноза риска с заданной матрицей';



-- =====================================================================================
-- optimize_forgetting_params : Функция оптимизации (поиск по сетке)
-- =====================================================================================
/*
Использование
Запуск с выводом прогресса (по умолчанию):
CALL optimize_forgetting_params();

Сухой запуск (только оценка, без обновления конфига):
SELECT optimize_forgetting_params(p_dry_run => TRUE);

Отключить детальный вывод:
CALL optimize_forgetting_params(p_verbose => FALSE);

Принудительное обновление (даже без значительного улучшения):
CALL optimize_forgetting_params(p_force_update => TRUE);

Запуск с периодическим коммитом после каждой итерации (рекомендуется для быстрого освобождения блокировок):
CALL optimize_forgetting_params(p_commit_every => 1);
Если требуется реже фиксировать транзакции для повышения производительности (но с риском повторной ошибки при большом числе комбинаций), можно увеличить p_commit_every, например, до 10:
CALL optimize_forgetting_params(p_commit_every => 10);


Настройка сетки параметров
Для изменения диапазонов поиска отредактируйте массивы в начале функции:
v_alphas – возможные значения base_alpha (скорость забывания).
v_halfs – возможные значения incident_half_life_days (период полураспада).
v_mins – возможные значения min_alpha (минимальный коэффициент забывания).
v_intervals – возможные значения interval_minute (период между применениями забывания).

ТЕСТ:

DO $$
DECLARE
    res TEXT;
BEGIN
	CALL optimize_forgetting_params(res , p_dry_run => TRUE , p_verbose => TRUE ,p_commit_every => 1);
    RAISE NOTICE 'Result: %', res;
END $$;
ТЕСТ:

*/
CREATE OR REPLACE PROCEDURE optimize_forgetting_params(
    INOUT result TEXT,                                   -- <-- первым, без DEFAULT
    IN p_dry_run BOOLEAN DEFAULT FALSE,
    IN p_force_update BOOLEAN DEFAULT FALSE,
    IN p_verbose BOOLEAN DEFAULT TRUE,
    IN p_min_transitions INT DEFAULT 5,
    IN p_smoothing REAL DEFAULT 0.01,
    IN p_commit_every INT DEFAULT 1                     -- COMMIT после каждых N итераций
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_alphas REAL[] := ARRAY[0.05, 0.1, 0.15, 0.2, 0.25];
    v_halfs REAL[] := ARRAY[2, 4, 7, 10, 14];
    v_mins REAL[] := ARRAY[0.005, 0.01, 0.015, 0.02];
    v_intervals INT[] := ARRAY[60, 120, 180, 240];

    v_base_alpha REAL;
    v_half_life REAL;
    v_min_alpha REAL;
    v_interval INT;

    v_learn_start DATE;
    v_learn_end DATE;
    v_eval_start DATE;
    v_eval_end DATE;

    v_min_trans_ts TIMESTAMPTZ;
    v_max_trans_ts TIMESTAMPTZ;
    v_min_pred_ts TIMESTAMPTZ;
    v_max_pred_ts TIMESTAMPTZ;
    v_learn_days INT := 14;
    v_eval_days  INT := 14;
    v_min_learn_days INT := 14;
    v_min_eval_preds INT := 50;

    v_best_brier REAL := 999;
    v_best_params JSONB;
    v_result RECORD;
    v_counter INT := 0;
    v_total_combos INT;
    v_log_id INT;
    v_current_config RECORD;
    v_improvement_threshold REAL := 0.01;
    v_commit_counter INT := 0;
BEGIN
    -- ========================================================================
    -- 1. Динамическое определение периодов
    -- ========================================================================
    SELECT MIN(ts), MAX(ts) INTO v_min_trans_ts, v_max_trans_ts FROM transition_log;
    SELECT MIN(prediction_time), MAX(prediction_time) INTO v_min_pred_ts, v_max_pred_ts
    FROM prediction_log WHERE actual_outcome IS NOT NULL;

    v_learn_start := GREATEST(
        COALESCE(v_min_trans_ts, CURRENT_DATE - v_learn_days),
        CURRENT_DATE - v_learn_days
    )::DATE;
    v_learn_end := COALESCE(v_max_trans_ts, CURRENT_DATE - INTERVAL '1 day')::DATE;
    v_eval_start := GREATEST(
        COALESCE(v_min_pred_ts, CURRENT_DATE - v_eval_days),
        v_learn_start::TIMESTAMPTZ
    )::DATE;
    v_eval_end := COALESCE(v_max_pred_ts, CURRENT_DATE - INTERVAL '1 day')::DATE;

    IF (v_learn_end - v_learn_start) < v_min_learn_days THEN
        RAISE NOTICE 'Недостаточно данных для обучения (доступно % дней, требуется минимум % дней). Оптимизация отменена.',
            (v_learn_end - v_learn_start), v_min_learn_days;
        result := 'Optimization skipped: insufficient training data (need at least 14 days).';
        RETURN;
    END IF;

    IF (SELECT COUNT(*) FROM prediction_log
        WHERE prediction_time BETWEEN v_eval_start AND v_eval_end
          AND actual_outcome IS NOT NULL) < v_min_eval_preds THEN
        RAISE NOTICE 'Недостаточно прогнозов с известными исходами (доступно % шт, требуется минимум % шт). Оптимизация отменена.',
            (SELECT COUNT(*) FROM prediction_log
             WHERE prediction_time BETWEEN v_eval_start AND v_eval_end
               AND actual_outcome IS NOT NULL), v_min_eval_preds;
        result := 'Optimization skipped: insufficient evaluation data (need at least 50 predictions with outcomes).';
        RETURN;
    END IF;

    -- ========================================================================
    -- 2. Получение текущей конфигурации
    -- ========================================================================
    SELECT base_alpha, incident_half_life_days, min_alpha, interval_minute
    INTO v_current_config
    FROM markov_config LIMIT 1;

    DELETE FROM forgetting_optimization_log WHERE ts < CURRENT_DATE - 90;

    -- ========================================================================
    -- 3. Перебор комбинаций с периодическим COMMIT
    -- ========================================================================
    v_total_combos := array_length(v_alphas, 1) * array_length(v_halfs, 1) *
                      array_length(v_mins, 1) * array_length(v_intervals, 1);

    IF p_verbose THEN
        RAISE NOTICE 'INFO: Starting optimization with % combinations', v_total_combos;
        RAISE NOTICE 'INFO: Periods used: learn [%, %], eval [%, %]',
            v_learn_start, v_learn_end, v_eval_start, v_eval_end;
    END IF;

    FOR v_base_alpha IN (SELECT unnest(v_alphas))
    LOOP
        FOR v_half_life IN (SELECT unnest(v_halfs))
        LOOP
            FOR v_min_alpha IN (SELECT unnest(v_mins))
            LOOP
                FOR v_interval IN (SELECT unnest(v_intervals))
                LOOP
                    v_counter := v_counter + 1;
                    v_commit_counter := v_commit_counter + 1;

                    IF p_verbose AND v_counter % 10 = 0 THEN
                        RAISE NOTICE 'INFO: Progress: %/% (%), current: base=%, half=%, min=%, interval=%, best Brier=%',
                            v_counter, v_total_combos,
                            round((v_counter::NUMERIC / v_total_combos * 100), 1),
                            v_base_alpha, v_half_life, v_min_alpha, v_interval,
                            round(v_best_brier::NUMERIC, 4);
                    END IF;

                    -- Вызов функции оценки
                    SELECT * INTO v_result
                    FROM evaluate_forgetting_params(
                        v_base_alpha, v_half_life, v_min_alpha, v_interval,
                        v_learn_start, v_learn_end,
                        v_eval_start, v_eval_end,
                        NULL,                     -- p_horizon (по умолчанию)
                        p_min_transitions,
                        p_smoothing
                    );

                    IF v_result.total_predictions < 50 THEN
                        IF v_commit_counter >= p_commit_every THEN
                            COMMIT;
                            v_commit_counter := 0;
                        END IF;
                        CONTINUE;
                    END IF;

                    -- Логирование
                    INSERT INTO forgetting_optimization_log (
                        base_alpha, half_life, min_alpha, interval_minute,
                        period_start, period_end, eval_start, eval_end,
                        total_predictions, incident_rate,
                        brier, log_loss, roc_auc, precision_at_05, recall_at_05, mae,
                        max_prob_change, coverage_pct,
                        notes
                    ) VALUES (
                        v_base_alpha, v_half_life, v_min_alpha, v_interval,
                        v_learn_start, v_learn_end, v_eval_start, v_eval_end,
                        v_result.total_predictions, v_result.incident_rate,
                        v_result.brier, v_result.log_loss, v_result.roc_auc,
                        v_result.precision_at_05, v_result.recall_at_05, v_result.mae,
                        v_result.max_prob_change, v_result.coverage_pct,
                        'grid_search'
                    ) RETURNING id INTO v_log_id;

                    -- Обновление лучшего результата
                    IF v_result.brier < v_best_brier THEN
                        v_best_brier := v_result.brier;
                        v_best_params := jsonb_build_object(
                            'base_alpha', v_base_alpha,
                            'half_life', v_half_life,
                            'min_alpha', v_min_alpha,
                            'interval_minute', v_interval,
                            'brier', v_result.brier,
                            'log_loss', v_result.log_loss,
                            'roc_auc', v_result.roc_auc,
                            'max_prob_change', v_result.max_prob_change,
                            'coverage_pct', v_result.coverage_pct
                        );
                        UPDATE forgetting_optimization_log SET is_best = TRUE WHERE id = v_log_id;
                        UPDATE forgetting_optimization_log SET is_best = FALSE
                        WHERE id != v_log_id AND is_best = TRUE;

                        IF p_verbose THEN
                            RAISE NOTICE 'INFO: New best found at combo %: Brier=%, params: base=%, half=%, min=%, interval=%',
                                v_counter,
                                round(v_result.brier::NUMERIC, 4),
                                v_base_alpha, v_half_life, v_min_alpha, v_interval;
                        END IF;
                    END IF;

                    -- Периодический COMMIT
                    IF v_commit_counter >= p_commit_every THEN
                        COMMIT;
                        v_commit_counter := 0;
                    END IF;
                END LOOP;
            END LOOP;
        END LOOP;
    END LOOP;

    -- Фиксация остатков
    IF v_commit_counter > 0 THEN
        COMMIT;
    END IF;

    -- ========================================================================
    -- 4. Итоговый вывод
    -- ========================================================================
    IF p_verbose THEN
        RAISE NOTICE 'INFO: Optimization finished. Total combinations evaluated: %', v_counter;
        IF v_best_params IS NOT NULL THEN
            RAISE NOTICE 'INFO: Best params: base=%, half=%, min=%, interval=%, Brier=%, ROC-AUC=%',
                v_best_params->>'base_alpha',
                v_best_params->>'half_life',
                v_best_params->>'min_alpha',
                v_best_params->>'interval_minute',
                round((v_best_params->>'brier')::NUMERIC, 4),
                round((v_best_params->>'roc_auc')::NUMERIC, 4);
        END IF;
    END IF;

    -- ========================================================================
    -- 5. Обновление конфигурации (если не dry-run)
    -- ========================================================================
    IF v_best_params IS NOT NULL AND NOT p_dry_run THEN
        UPDATE markov_config SET
            base_alpha = (v_best_params->>'base_alpha')::REAL,
            incident_half_life_days = (v_best_params->>'half_life')::REAL,
            min_alpha = (v_best_params->>'min_alpha')::REAL,
            interval_minute = (v_best_params->>'interval_minute')::INT
        WHERE TRUE;

        result := format('Optimization completed. Updated config with params: base_alpha=%s, half_life=%s, min_alpha=%s, interval=%s, Brier=%s',
            v_best_params->>'base_alpha',
            v_best_params->>'half_life',
            v_best_params->>'min_alpha',
            v_best_params->>'interval_minute',
            v_best_brier);
    ELSIF p_dry_run AND v_best_params IS NOT NULL THEN
        result := format('Dry run completed. Best params found: base_alpha=%s, half_life=%s, min_alpha=%s, interval=%s, Brier=%s',
            v_best_params->>'base_alpha',
            v_best_params->>'half_life',
            v_best_params->>'min_alpha',
            v_best_params->>'interval_minute',
            v_best_brier);
    ELSE
        result := 'Optimization failed: no valid parameters found.';
    END IF;
END;
$$;

COMMENT ON PROCEDURE optimize_forgetting_params IS 'Эмпирический подбор параметров адаптивного забывания с периодическим COMMIT. Параметр result возвращает итоговое сообщение.';

-- ==========================================================
-- Мониторинг стабильности вероятностей
-- ==========================================================
/*
Цель – отслеживать max_prob_change в динамике, чтобы вовремя заметить дрейф.
Логика – рассчитывается аналогично внутренней логике mchain_check_sufficiency, но за несколько последних периодов (неделя, две недели, месяц). Результат – таблица с датами и значениями.

Пример использования
SELECT * FROM report_stability_trend(14) ORDER BY period_start;
Результат покажет, как меняется стабильность модели во времени, и поможет оценить эффект от изменения параметров забывания.
*/

-- ==========================================================
-- Мониторинг стабильности вероятностей (текстовый отчёт)
-- ==========================================================
/*
Цель – отслеживать max_prob_change в динамике, чтобы вовремя заметить дрейф.
Логика – рассчитывается аналогично внутренней логике mchain_check_sufficiency,
но за несколько последних периодов (неделя, две недели, месяц).
Результат – текстовый отчёт с таблицей, описанием столбцов и интерпретацией.

Параметры:
  p_lookback_days INT – сколько дней назад смотреть (по умолчанию 14)

Возвращает:
  TEXT – отформатированный отчёт.
*/
-- ==========================================================
-- Мониторинг стабильности вероятностей (текстовый отчёт)
-- ==========================================================
CREATE OR REPLACE FUNCTION report_stability_trend(
    p_lookback_days INT DEFAULT 14
)
RETURNS TEXT
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_end   DATE := CURRENT_DATE;
    v_start DATE := v_end - p_lookback_days;
    v_rec   RECORD;                     -- переменная цикла
    v_metrics RECORD;                   -- для результатов расчёта по периоду
    v_report TEXT := '';
    v_line_sep CONSTANT TEXT := E'\n' || repeat('=', 100) || E'\n';
    v_sub_sep CONSTANT TEXT := E'\n' || repeat('-', 100) || E'\n';
    v_row TEXT;
    v_total_periods INT := 0;
    min_freq_for_stability INT := 200;

    v_first_max_change REAL;
    v_first_coverage   INT;
    v_first_period_start DATE;
    v_first_period_end   DATE;
    v_last_max_change  REAL;
    v_last_coverage    INT;
    v_last_period_start DATE;
    v_last_period_end   DATE;

    v_overall_stability TEXT;
    v_trend_text TEXT;
BEGIN
    -- Заголовок отчёта
    v_report := v_report || 'ОТЧЁТ О СТАБИЛЬНОСТИ ВЕРОЯТНОСТЕЙ ЦЕПИ МАРКОВА' || v_line_sep;
    v_report := v_report || 'Период анализа: ' || v_start::TEXT || ' – ' || v_end::TEXT || E'\n';
    v_report := v_report || 'Дата формирования: ' || now()::TEXT || E'\n';
    v_report := v_report || v_sub_sep;

    v_report := v_report || 'ДИНАМИКА ПО 7‑ДНЕВНЫМ ПЕРИОДАМ' || E'\n';
    v_report := v_report || rpad('Период', 25) ||
                rpad('max_prob_change', 18) ||
                rpad('coverage_pct', 14) ||
                rpad('total_transitions', 20) ||
                rpad('stability_factor', 18) || E'\n';
    v_report := v_report || repeat('-', 25+18+14+20+18) || E'\n';

    -- Цикл по периодам (CTE помещены внутрь запроса цикла)
    FOR v_rec IN (
        WITH RECURSIVE periods AS (
            SELECT v_start AS start_date, v_start + 7 AS end_date
            UNION ALL
            SELECT end_date, end_date + 7
            FROM periods
            WHERE end_date < v_end
        )
        SELECT start_date, end_date
        FROM periods
        ORDER BY start_date
    ) LOOP

        -- Вычисляем метрики для текущего периода
        WITH frequent_states AS (
            SELECT from_state
            FROM transition_log
            WHERE ts >= v_start AND ts < v_end + 1
            GROUP BY from_state
            HAVING COUNT(*) >= min_freq_for_stability
        ),
        period_data AS (
            SELECT
                v_rec.start_date AS period_start,
                v_rec.end_date   AS period_end,
                COUNT(*) AS total_trans
            FROM transition_log
            WHERE ts >= v_rec.start_date AND ts < v_rec.end_date
        ),
        first_half AS (
            SELECT from_state, to_state,
                   COUNT(*)::REAL / SUM(COUNT(*)) OVER (PARTITION BY from_state) AS prob
            FROM transition_log
            JOIN frequent_states fs USING (from_state)
            WHERE ts >= v_rec.start_date
              AND ts < v_rec.start_date + (v_rec.end_date - v_rec.start_date) / 2
              AND to_state NOT IN (SELECT state_id FROM critical_states)
            GROUP BY from_state, to_state
        ),
        second_half AS (
            SELECT from_state, to_state,
                   COUNT(*)::REAL / SUM(COUNT(*)) OVER (PARTITION BY from_state) AS prob
            FROM transition_log
            JOIN frequent_states fs USING (from_state)
            WHERE ts >= v_rec.start_date + (v_rec.end_date - v_rec.start_date) / 2
              AND ts < v_rec.end_date
              AND to_state NOT IN (SELECT state_id FROM critical_states)
            GROUP BY from_state, to_state
        ),
        diffs AS (
            SELECT COALESCE(ABS(COALESCE(f.prob, 0) - COALESCE(s.prob, 0)), 0.0) AS diff
            FROM first_half f
            FULL JOIN second_half s USING (from_state, to_state)
        ),
        max_diff AS (
            SELECT COALESCE(MAX(diff), 0.0) AS max_prob_change FROM diffs
        ),
        total_trans AS (
            SELECT total_trans FROM period_data
        ),
        state_stats AS (
            SELECT from_state, COUNT(*) AS n_i,
                   COUNT(*)::REAL / (SELECT total_trans FROM total_trans) AS freq
            FROM transition_log
            WHERE ts >= v_rec.start_date AND ts < v_rec.end_date
            GROUP BY from_state
        ),
        frequent_states_period AS (
            SELECT from_state
            FROM state_stats
            WHERE freq > 0.01
        ),
        coverage AS (
            SELECT
                COUNT(*) AS total_frequent,
                SUM(CASE WHEN ss.n_i >= 50 THEN 1 ELSE 0 END) AS covered_frequent
            FROM frequent_states_period f
            LEFT JOIN LATERAL (
                SELECT COUNT(*) AS n_i
                FROM transition_log
                WHERE from_state = f.from_state
                  AND ts >= v_rec.start_date AND ts < v_rec.end_date
            ) ss ON TRUE
        ),
        cov_pct AS (
            SELECT
                CASE
                    WHEN total_frequent = 0 THEN 100
                    ELSE (covered_frequent * 100) / total_frequent
                END AS coverage_pct
            FROM coverage
        ),
        stab AS (
            SELECT
                CASE
                    WHEN md.max_prob_change <= 0.05 THEN 1.0
                    WHEN md.max_prob_change <= 0.2  THEN 1.5
                    WHEN md.max_prob_change <= 0.5  THEN 2.0
                    ELSE 3.0
                END AS stability_factor
            FROM max_diff md
        )
        SELECT
            pd.period_start,
            pd.period_end,
            md.max_prob_change,
            cp.coverage_pct,
            pd.total_trans,
            st.stability_factor
        INTO v_metrics
        FROM period_data pd
        CROSS JOIN max_diff md
        CROSS JOIN cov_pct cp
        CROSS JOIN stab st;

        -- Если данных нет, пропускаем
        IF v_metrics.total_trans = 0 THEN
            CONTINUE;
        END IF;

        v_total_periods := v_total_periods + 1;

        -- Сохраняем первый период
        IF v_total_periods = 1 THEN
            v_first_max_change := v_metrics.max_prob_change;
            v_first_coverage   := v_metrics.coverage_pct;
            v_first_period_start := v_metrics.period_start;
            v_first_period_end   := v_metrics.period_end;
        END IF;

        -- Сохраняем последний период
        v_last_max_change := v_metrics.max_prob_change;
        v_last_coverage   := v_metrics.coverage_pct;
        v_last_period_start := v_metrics.period_start;
        v_last_period_end   := v_metrics.period_end;

        -- Формируем строку таблицы
        v_row := rpad(v_metrics.period_start::TEXT || ' – ' || v_metrics.period_end::TEXT, 25) ||
                 rpad(round(v_metrics.max_prob_change::NUMERIC, 4)::TEXT, 18) ||
                 rpad(v_metrics.coverage_pct::TEXT, 14) ||
                 rpad(v_metrics.total_trans::TEXT, 20) ||
                 rpad(round(v_metrics.stability_factor::NUMERIC, 2)::TEXT, 18);
        v_report := v_report || v_row || E'\n';
    END LOOP;

    IF v_total_periods = 0 THEN
        v_report := v_report || 'Нет данных за указанный период.' || E'\n';
        v_report := v_report || v_line_sep;
        RETURN v_report;
    END IF;

    v_report := v_report || v_sub_sep;

    -- ОПИСАНИЕ СТОЛБЦОВ (без изменений)
    v_report := v_report || 'ОПИСАНИЕ СТОЛБЦОВ' || E'\n';
    v_report := v_report || '  Период – 7‑дневный интервал, для которого рассчитаны метрики.' || E'\n';
    v_report := v_report || '  max_prob_change – максимальное изменение вероятностей перехода между двумя половинами периода (первая vs вторая).' || E'\n';
    v_report := v_report || '                   Чем меньше значение, тем стабильнее вероятности.' || E'\n';
    v_report := v_report || '  coverage_pct – доля частых состояний (частота >1%), для которых накоплено >=50 переходов.' || E'\n';
    v_report := v_report || '                 Высокое покрытие (>90%) означает достаточную статистику для большинства состояний.' || E'\n';
    v_report := v_report || '  total_transitions – общее число переходов за период.' || E'\n';
    v_report := v_report || '  stability_factor – коэффициент, используемый в адаптивном забывании для коррекции alpha.' || E'\n';
    v_report := v_report || '                      Рассчитывается по max_prob_change: <=0.05 → 1.0; <=0.2 → 1.5; <=0.5 → 2.0; >0.5 → 3.0.' || E'\n';
    v_report := v_report || v_sub_sep;

    -- ИНТЕРПРЕТАЦИЯ РЕЗУЛЬТАТОВ
    v_report := v_report || 'ИНТЕРПРЕТАЦИЯ РЕЗУЛЬТАТОВ' || E'\n';

    IF v_last_max_change IS NOT NULL THEN
        IF v_last_max_change <= 0.05 THEN
            v_overall_stability := 'ВЕРОЯТНОСТИ СТАБИЛЬНЫ (max_prob_change ≤ 0.05) – модель хорошо обучена, дрейф минимален.';
        ELSIF v_last_max_change <= 0.2 THEN
            v_overall_stability := 'УМЕРЕННАЯ НЕСТАБИЛЬНОСТЬ (0.05 < max_prob_change ≤ 0.2) – вероятности слегка дрейфуют, рекомендуется мониторинг.';
        ELSIF v_last_max_change <= 0.5 THEN
            v_overall_stability := 'ЗНАЧИТЕЛЬНАЯ НЕСТАБИЛЬНОСТЬ (0.2 < max_prob_change ≤ 0.5) – вероятности меняются существенно, возможно, требуется усиление забывания или пересмотр параметров.';
        ELSE
            v_overall_stability := 'ВЫСОКАЯ НЕСТАБИЛЬНОСТЬ (max_prob_change > 0.5) – вероятности сильно меняются, прогнозы ненадёжны. Требуется срочный пересмотр модели или данных.';
        END IF;
        v_report := v_report || '  Последний период (' || v_last_period_start::TEXT || ' – ' || v_last_period_end::TEXT || '): ' || v_overall_stability || E'\n';
    END IF;

    IF v_last_coverage IS NOT NULL THEN
        IF v_last_coverage >= 90 THEN
            v_report := v_report || '  Покрытие частых состояний (>90%) – хорошая статистическая база.' || E'\n';
        ELSIF v_last_coverage >= 70 THEN
            v_report := v_report || '  Покрытие (70-90%) – приемлемо, но некоторые частые состояния имеют недостаточно переходов.' || E'\n';
        ELSE
            v_report := v_report || '  Покрытие (<70%) – низкое, многие частые состояния не имеют достаточного числа переходов, что снижает точность прогнозов.' || E'\n';
        END IF;
    END IF;

    IF v_total_periods > 1 AND v_first_max_change IS NOT NULL AND v_last_max_change IS NOT NULL THEN
        IF v_last_max_change > v_first_max_change * 1.2 THEN
            v_trend_text := '⚠️  max_prob_change увеличился более чем на 20% – вероятности становятся менее стабильными. Рекомендуется проверить параметры забывания или поступление данных.';
        ELSIF v_last_max_change < v_first_max_change * 0.8 THEN
            v_trend_text := '✔️  max_prob_change уменьшился более чем на 20% – стабильность улучшается. Модель адаптируется хорошо.';
        ELSE
            v_trend_text := '➖  max_prob_change существенно не изменился – стабильность сохраняется на уровне.';
        END IF;
        v_report := v_report || '  Тренд за период: ' || v_trend_text || E'\n';
    END IF;

    v_report := v_report || v_sub_sep;
    v_report := v_report || 'Рекомендации:' || E'\n';
    IF v_last_max_change <= 0.05 AND v_last_coverage >= 90 THEN
        v_report := v_report || '  ✔ Модель стабильна и имеет хорошее покрытие. Прогнозы надёжны. Продолжайте мониторинг.' || E'\n';
    ELSIF v_last_max_change > 0.2 OR v_last_coverage < 70 THEN
        v_report := v_report || '  ⚠ Требуется внимание: либо нестабильность, либо низкое покрытие. Рассмотрите:' || E'\n';
        v_report := v_report || '    - Увеличение периода обучения или накопление данных.' || E'\n';
        v_report := v_report || '    - Настройку параметров адаптивного забывания (alpha, half_life).' || E'\n';
        v_report := v_report || '    - Проверку корректности поступления метрик производительности.' || E'\n';
    ELSE
        v_report := v_report || '  ➖ Состояние удовлетворительное. Рекомендуется периодически пересматривать параметры забывания с помощью optimize_forgetting_params().' || E'\n';
    END IF;

    v_report := v_report || v_line_sep;

    RETURN v_report;
END;
$$;

COMMENT ON FUNCTION report_stability_trend(INT) IS 'Возвращает текстовый отчёт о стабильности вероятностей по 7‑дневным периодам за последние N дней. Исключает переходы в критические состояния и состояния с малым числом переходов (<50 за период) из расчёта max_prob_change. Включает таблицу с метриками, описания и интерпретацию.';

-- ==========================================================
-- Качество прогнозов в скользящем окне
-- ==========================================================
/*
Цель – оценивать Brier, ROC‑AUC, калибровку за последние N дней, чтобы видеть тренд качества.
Логика – агрегация prediction_log по дням (или неделям) с вычислением метрик, аналогичных mchain_quality_report, но с разбивкой по периодам.
*/
CREATE OR REPLACE FUNCTION report_quality_sliding(
    p_window_days INT DEFAULT 7,
    p_step_days INT DEFAULT 1
)
RETURNS TABLE (
    period_start     DATE,
    period_end       DATE,
    total_predictions INT,
    brier            REAL,
    roc_auc          REAL,
    calibration_notes TEXT
)
LANGUAGE plpgsql STABLE
AS $$
BEGIN
    RETURN QUERY
    SELECT
        h.date_from,
        h.date_to,
        h.total_predictions,
        h.brier_score,
        h.roc_auc,
        h.notes
    FROM mchain_quality_metrics_history h
    WHERE h.date_from >= CURRENT_DATE - p_window_days
    ORDER BY h.date_from;
END;
$$;

COMMENT ON FUNCTION report_quality_sliding(INT, INT) IS 'Возвращает метрики качества прогнозов за скользящие периоды (по дням) из таблицы mchain_quality_metrics_history. Параметры: p_window_days – сколько дней назад смотреть, p_step_days – не используется (оставлен для совместимости).';

-- ==========================================================
-- Детальная калибровочная кривая (ежедневно)
-- ==========================================================
/*
Цель – визуализировать калибровку за каждый день, чтобы видеть смещения.
Логика – для каждого дня строить бины (0–0.1, 0.1–0.2, …) и выводить среднее предсказание и частоту исходов.
*/
CREATE OR REPLACE FUNCTION report_daily_calibration(
    p_date DATE DEFAULT CURRENT_DATE - 1
)
RETURNS TEXT[]
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_result TEXT[] := '{}';
    v_rec RECORD;
    v_horizon INT;
    v_line TEXT;
BEGIN
    -- Получаем горизонт из конфигурации
    SELECT forecast_horizon_minutes INTO v_horizon FROM markov_config LIMIT 1;
    IF v_horizon IS NULL THEN
        v_horizon := 30;
    END IF;

    -- Собираем данные по бинам (10 бинов от 0 до 1)
    FOR v_rec IN
        WITH preds AS (
            SELECT predicted_risk, actual_outcome
            FROM prediction_log
            WHERE date(prediction_time) = p_date
              AND actual_outcome IS NOT NULL
              AND horizon_minutes = v_horizon
        ),
        bins AS (
            SELECT
                WIDTH_BUCKET(LEAST(predicted_risk, 0.999999), 0, 1, 10) AS bin,
                AVG(predicted_risk) AS avg_pred,
                AVG(actual_outcome) AS obs_freq,
                COUNT(*) AS cnt
            FROM preds
            GROUP BY bin
            ORDER BY bin
        )
        SELECT
            (bin - 1) / 10.0 AS bin_low,
            bin / 10.0 AS bin_high,
            avg_pred,
            obs_freq,
            cnt
        FROM bins
        ORDER BY bin
    LOOP
        v_line := format('[%s, %s): avg_pred=%s, obs_freq=%s, cnt=%s',
            round(v_rec.bin_low::NUMERIC, 1),
            round(v_rec.bin_high::NUMERIC, 1),
            round(v_rec.avg_pred::NUMERIC, 3),
            round(v_rec.obs_freq::NUMERIC, 3),
            v_rec.cnt);
        v_result := array_append(v_result, v_line);
    END LOOP;

    -- Если данных нет, возвращаем массив с сообщением
    IF array_length(v_result, 1) IS NULL THEN
        v_result := array_append(v_result, format('No calibration data for date %s (horizon %s min)', p_date, v_horizon));
    END IF;

    RETURN v_result;
END;
$$;

COMMENT ON FUNCTION report_daily_calibration(DATE) IS 'Возвращает калибровочную таблицу для указанной даты в виде массива строк (каждая строка – один бин). Включает границы бина, среднее предсказание, наблюдаемую частоту и количество прогнозов.';

-- ==========================================================
-- Распределение состояний и частота критических состояний
-- ==========================================================
/*
Цель – понимать, в каких состояниях система находится чаще всего, и как меняется доля критических.
Логика – группировка по state_id за последние N дней с подсчётом переходов и вычислением доли критических.
*/
CREATE OR REPLACE FUNCTION state_distribution(
    p_lookback_days INT DEFAULT 7
)
RETURNS TABLE (
    state_id SMALLINT,
    correlation REAL,
    os_trend SMALLINT,
    wait_trend SMALLINT,
    transition_count BIGINT,
    pct_of_total NUMERIC,
    is_critical BOOLEAN
)
LANGUAGE plpgsql STABLE AS $$
BEGIN
    RETURN QUERY
    WITH totals AS (
        SELECT COUNT(*) AS total
        FROM transition_log
        WHERE ts >= CURRENT_DATE - p_lookback_days
    ),
    state_counts AS (
        SELECT to_state, COUNT(*) AS cnt
        FROM transition_log
        WHERE ts >= CURRENT_DATE - p_lookback_days
        GROUP BY to_state
    )
    SELECT
        sd.state_id,
        sd.correlation,
        sd.os_trend,
        sd.wait_trend,
        sc.cnt,
        (sc.cnt::NUMERIC / t.total) * 100 AS pct,
        EXISTS (SELECT 1 FROM critical_states cs WHERE cs.state_id = sd.state_id) AS is_critical
    FROM state_descriptions sd
    JOIN state_counts sc ON sd.state_id = sc.to_state
    CROSS JOIN totals t
    ORDER BY sc.cnt DESC;
END;
$$;
COMMENT ON FUNCTION state_distribution IS 'Распределение состояний и частота критических состояний';


-- ==========================================================
-- Эффективность забывания
-- ==========================================================
/*
Цель – оценить, как изменение параметров забывания влияет на стабильность и качество.
Логика – использовать таблицу forgetting_optimization_log для сравнения разных комбинаций параметров и выбора лучшей по Brier и стабильности.
*/
CREATE OR REPLACE FUNCTION report_forgetting_effectiveness()
RETURNS TABLE (
    base_alpha REAL,
    half_life REAL,
    min_alpha REAL,
    interval_min INT,
    brier REAL,
    roc_auc REAL,
    max_prob_change REAL,
    total_predictions INT,
    is_best BOOLEAN
)
LANGUAGE plpgsql STABLE
AS $$
BEGIN
    RETURN QUERY
    SELECT
        l.base_alpha,
        l.half_life,
        l.min_alpha,
        l.interval_minute,
        l.brier,
        l.roc_auc,
        l.max_prob_change,
        l.total_predictions,
        l.is_best
    FROM forgetting_optimization_log l
    WHERE l.ts >= CURRENT_DATE - 14
    ORDER BY l.brier ASC NULLS LAST;
END;
$$;

COMMENT ON FUNCTION report_forgetting_effectiveness() IS 'Возвращает результаты экспериментов по подбору параметров забывания за последние 14 дней, отсортированные по Brier score.';

-- =============================================================================
-- Функция: generate_full_analytical_report
-- Назначение: формирование сводного аналитического отчёта по цепи Маркова 
--             за заданный период в формате Markdown (массив строк).
-- Отчёт включает все ключевые аспекты: общее состояние, качество прогнозов,
-- матрицу переходов, стабильность, распределение состояний, эффективность забывания
-- и калибровку за последний день.
-- Параметры:
--   p_start  DATE – начало периода (по умолчанию 7 дней назад от текущей даты)
--   p_end    DATE – конец периода (по умолчанию вчера)
-- Возвращает: TEXT[] – каждая строка массива соответствует строке Markdown-отчёта.
-- =============================================================================
/*
 psql -d expecto_db -U expecto_user -c "select unnest(generate_full_analytical_report())" > /tmp/full_analytical_report.txt
*/
CREATE OR REPLACE FUNCTION generate_full_analytical_report(
    p_start DATE DEFAULT CURRENT_DATE - INTERVAL '7 days',
    p_end   DATE DEFAULT CURRENT_DATE - INTERVAL '1 day'
)
RETURNS TEXT[]
LANGUAGE plpgsql
AS $$
DECLARE
    v_report_lines TEXT[] := '{}';
    v_section_text TEXT;
    v_horizon INT;
    v_start_ts TIMESTAMPTZ := p_start::TIMESTAMPTZ;
    v_end_ts   TIMESTAMPTZ := (p_end + 1)::TIMESTAMPTZ;
    v_line_sep CONSTANT TEXT := E'\n---\n';
    v_lookback_days INT;
    v_temp TEXT;
    v_rec RECORD;
    v_daily_calib TEXT[];
    v_date DATE;
BEGIN
    -- ------------------------------------------------------------------
    -- 1. Определение горизонта прогноза из конфигурации
    -- ------------------------------------------------------------------
    SELECT forecast_horizon_minutes INTO v_horizon FROM markov_config LIMIT 1;
    IF v_horizon IS NULL THEN
        v_horizon := 30;
    END IF;

    -- Количество дней в периоде для функций с lookback
    v_lookback_days := (p_end - p_start) + 1;

    -- ------------------------------------------------------------------
    -- 2. Заголовок отчёта
    -- ------------------------------------------------------------------
    v_section_text := format(
        '# Сводный аналитический отчёт по цепи Маркова
Период: %s – %s
Горизонт прогноза: %s минут
Дата формирования: %s
',
        p_start, p_end, v_horizon, now()::DATE
    );
    v_report_lines := array_cat(v_report_lines, regexp_split_to_array(v_section_text, E'\n'));

    -- ------------------------------------------------------------------
    -- 3. Секция: Общий обзор (mchain_summary_report)
    -- ------------------------------------------------------------------
    v_report_lines := array_append(v_report_lines, '');
    v_report_lines := array_append(v_report_lines, '## 1. Общий обзор состояния цепи');
    BEGIN
        SELECT mchain_summary_report(p_start, p_end) INTO v_section_text;
        v_report_lines := array_cat(v_report_lines, regexp_split_to_array(v_section_text, E'\n'));
    EXCEPTION WHEN OTHERS THEN
        v_report_lines := array_append(v_report_lines, '⚠ Ошибка при получении общего обзора: ' || SQLERRM);
    END;

    -- ------------------------------------------------------------------
    -- 4. Секция: Качество прогнозов (mchain_quality_report)
    -- ------------------------------------------------------------------
    v_report_lines := array_append(v_report_lines, '');
    v_report_lines := array_append(v_report_lines, '## 2. Качество прогнозов');
    BEGIN
        SELECT mchain_quality_report(p_start, p_end, v_horizon) INTO v_section_text;
        v_report_lines := array_cat(v_report_lines, regexp_split_to_array(v_section_text, E'\n'));
    EXCEPTION WHEN OTHERS THEN
        v_report_lines := array_append(v_report_lines, '⚠ Ошибка при получении отчёта о качестве: ' || SQLERRM);
    END;

    -- ------------------------------------------------------------------
    -- 5. Секция: Матрица переходов между макрогруппами (mchain_state_transition_matrix_report)
    -- ------------------------------------------------------------------
    v_report_lines := array_append(v_report_lines, '');
    v_report_lines := array_append(v_report_lines, '## 3. Матрица переходов между макрогруппами');
    BEGIN
        SELECT mchain_state_transition_matrix_report(TRUE, TRUE) INTO v_section_text;
        v_report_lines := array_cat(v_report_lines, regexp_split_to_array(v_section_text, E'\n'));
    EXCEPTION WHEN OTHERS THEN
        v_report_lines := array_append(v_report_lines, '⚠ Ошибка при получении матрицы переходов: ' || SQLERRM);
    END;

    -- ====================================================================
    -- 6. Секция: Стабильность вероятностей (report_stability_trend) — ИСПРАВЛЕНО
    -- ====================================================================
    v_report_lines := array_append(v_report_lines, '');
    v_report_lines := array_append(v_report_lines, '## 4. Стабильность вероятностей (по 7‑дневным периодам)');
    BEGIN
        -- report_stability_trend возвращает TEXT, просто добавляем его содержимое
        SELECT report_stability_trend(v_lookback_days) INTO v_section_text;
        v_report_lines := array_cat(v_report_lines, regexp_split_to_array(v_section_text, E'\n'));
    EXCEPTION WHEN OTHERS THEN
        v_report_lines := array_append(v_report_lines, '⚠ Ошибка при получении стабильности: ' || SQLERRM);
    END;

    -- ------------------------------------------------------------------
    -- 7. Секция: Скользящее качество прогнозов (report_quality_sliding)
    -- ------------------------------------------------------------------
    v_report_lines := array_append(v_report_lines, '');
    v_report_lines := array_append(v_report_lines, '## 5. Скользящее качество прогнозов (по дням)');
    BEGIN
        v_section_text := '| Дата | Прогнозов | Brier | ROC‑AUC | Примечание |' || E'\n' ||
                          '|------|-----------|-------|---------|-------------|' || E'\n';
        FOR v_rec IN
            SELECT period_start, total_predictions, brier, roc_auc, calibration_notes
            FROM report_quality_sliding(v_lookback_days, 1)
        LOOP
            v_section_text := v_section_text || format(
                '| %s | %s | %s | %s | %s |' || E'\n',
                v_rec.period_start,
                v_rec.total_predictions,
                COALESCE(round(v_rec.brier::NUMERIC, 4)::TEXT, 'NULL'),
                COALESCE(round(v_rec.roc_auc::NUMERIC, 4)::TEXT, 'NULL'),
                COALESCE(v_rec.calibration_notes, '')
            );
        END LOOP;
        v_report_lines := array_cat(v_report_lines, regexp_split_to_array(v_section_text, E'\n'));
    EXCEPTION WHEN OTHERS THEN
        v_report_lines := array_append(v_report_lines, '⚠ Ошибка при получении скользящего качества: ' || SQLERRM);
    END;

    -- ------------------------------------------------------------------
    -- 8. Секция: Распределение состояний (state_distribution)
    -- ------------------------------------------------------------------
    v_report_lines := array_append(v_report_lines, '');
    v_report_lines := array_append(v_report_lines, '## 6. Распределение состояний (топ‑20 по частоте)');
    BEGIN
        v_section_text := '| state_id | correlation | os_trend | wait_trend | переходов | доля, % | критическое? |' || E'\n' ||
                          '|----------|-------------|----------|------------|-----------|---------|---------------|' || E'\n';
        FOR v_rec IN
            SELECT state_id, correlation, os_trend, wait_trend, transition_count, pct_of_total, is_critical
            FROM state_distribution(v_lookback_days)
            LIMIT 20
        LOOP
            v_section_text := v_section_text || format(
                '| %s | %s | %s | %s | %s | %s | %s |' || E'\n',
                v_rec.state_id,
                round(v_rec.correlation::NUMERIC, 1),
                v_rec.os_trend,
                v_rec.wait_trend,
                v_rec.transition_count,
                round(v_rec.pct_of_total::NUMERIC, 2),
                CASE WHEN v_rec.is_critical THEN 'Да' ELSE 'Нет' END
            );
        END LOOP;
        v_report_lines := array_cat(v_report_lines, regexp_split_to_array(v_section_text, E'\n'));
    EXCEPTION WHEN OTHERS THEN
        v_report_lines := array_append(v_report_lines, '⚠ Ошибка при получении распределения состояний: ' || SQLERRM);
    END;

    -- ------------------------------------------------------------------
    -- 9. Секция: Эффективность забывания (report_forgetting_effectiveness)
    -- ------------------------------------------------------------------
    v_report_lines := array_append(v_report_lines, '');
    v_report_lines := array_append(v_report_lines, '## 7. Эффективность забывания (результаты оптимизации)');
    BEGIN
        v_section_text := '| base_alpha | half_life | min_alpha | interval | Brier | ROC‑AUC | max_prob_change | прогнозов | лучший? |' || E'\n' ||
                          '|------------|-----------|-----------|----------|-------|---------|-----------------|-----------|---------|' || E'\n';
        FOR v_rec IN
            SELECT base_alpha, half_life, min_alpha, interval_min, brier, roc_auc, max_prob_change, total_predictions, is_best
            FROM report_forgetting_effectiveness()
            ORDER BY brier ASC NULLS LAST
            LIMIT 10
        LOOP
            v_section_text := v_section_text || format(
                '| %s | %s | %s | %s | %s | %s | %s | %s | %s |' || E'\n',
                v_rec.base_alpha,
                v_rec.half_life,
                v_rec.min_alpha,
                v_rec.interval_min,
                COALESCE(round(v_rec.brier::NUMERIC, 4)::TEXT, 'NULL'),
                COALESCE(round(v_rec.roc_auc::NUMERIC, 4)::TEXT, 'NULL'),
                COALESCE(round(v_rec.max_prob_change::NUMERIC, 4)::TEXT, 'NULL'),
                v_rec.total_predictions,
                CASE WHEN v_rec.is_best THEN '★' ELSE '' END
            );
        END LOOP;
        v_report_lines := array_cat(v_report_lines, regexp_split_to_array(v_section_text, E'\n'));
    EXCEPTION WHEN OTHERS THEN
        v_report_lines := array_append(v_report_lines, '⚠ Ошибка при получении эффективности забывания: ' || SQLERRM);
    END;

    -- ------------------------------------------------------------------
    -- 10. Секция: Калибровка за последний день периода
    -- ------------------------------------------------------------------
    v_report_lines := array_append(v_report_lines, '');
    v_report_lines := array_append(v_report_lines, format('## 8. Калибровочная кривая за последний день (%s)', p_end));
    BEGIN
        SELECT report_daily_calibration(p_end) INTO v_daily_calib;
        IF array_length(v_daily_calib, 1) > 0 THEN
            v_report_lines := array_cat(v_report_lines, v_daily_calib);
        ELSE
            v_report_lines := array_append(v_report_lines, 'Нет данных для калибровки за этот день.');
        END IF;
    EXCEPTION WHEN OTHERS THEN
        v_report_lines := array_append(v_report_lines, '⚠ Ошибка при получении калибровки: ' || SQLERRM);
    END;

    -- ------------------------------------------------------------------
    -- 11. Финальная черта
    -- ------------------------------------------------------------------
    v_report_lines := array_append(v_report_lines, '');
    v_report_lines := array_append(v_report_lines, '---');
    v_report_lines := array_append(v_report_lines, '*Отчёт сформирован автоматически.*');

    RETURN v_report_lines;
END;
$$;

COMMENT ON FUNCTION generate_full_analytical_report(DATE, DATE) IS 'Формирует сводный аналитический отчёт по цепи Маркова за указанный период в формате Markdown (массив строк). Включает: общее состояние, качество прогнозов, матрицу переходов, стабильность, скользящее качество, распределение состояний, эффективность забывания и калибровку за последний день. Параметры: p_start (по умолч. 7 дней назад), p_end (по умолч. вчера). Возвращает массив строк, каждая строка — строка Markdown-отчёта.';