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
-- version 11.1
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
  - collect_prediction_15min : Формирование истории по прогнозу 
  - update_prediction_outcomes_15min : Обновление исходов для прогнозов, которым уже > 15 минут
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

  
- **Отчеты**  
  - mchain_summary_report :  Сводный отчёт по состоянию цепи Маркова mchain_reliability_report+mchain_incident_transitions_report
  - mchain_incident_state_detail_report : Детализированный отчёт по каждому аварийному состоянию.
  - mchain_quality_report_15min : Отчет по качеству прогнозов
  
  - mchain_health_check : Проверяет состояние цепи Маркова и возвращает статус (OK, WARNING, CRITICAL)
  
  - mchain_reliability_report : Возвращает расширенный текстовый отчёт о достоверности прогнозов с метриками, порогами и рекомендациями
  - mchain_incident_transitions_report : Анализ переходов в аварийные состояния 
  
  - mchain_state_transition_matrix_report : Формирует матрицу переходов между укрупнёнными группами состояний. Источник: markov_probabilities (усреднение по состояниям внутри группы)
  
  -- 11.1 
  - refresh_critical_states : автоматическое обновление списка критических состояний на основе  
  - **Прогнозирование риска**
  - mchain_predict_risk_k_v2 :Вероятность хотя бы одного попадания в критическое множество за k шагов
  - mchain_predict_risk_15min_v2 :  Прогноз риска аварии на ближайшие 15 минут
  - mchain_predict_risk_30min_v2 :  Прогноз риска аварии на ближайшие 30 минут
  - mchain_predict_risk_1hour_v2 :  Прогноз риска аварии на ближайший час

  
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
-- # Обновление исходов каждые 5 минут (чтобы не перегружать)
--  */5 * * * * psql -d expecto_db -U expecto_user -c "SELECT update_prediction_outcomes_15min();"

-- # Расчёт суточных метрик в 02:00
-- 0 2 * * * psql -d expecto_db -U expecto_user -c "SELECT calculate_daily_quality_metrics();"

-- # Обновление critical_states еженедельно (воскресенье в 03:00)
-- 0 3 * * 0 psql -d expecto_db -U expecto_user -c "SELECT refresh_critical_states();" >/postgres/pg_expecto/sh/refresh_critical_states.log 2>&1

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
	PERFORM collect_prediction_15min();
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
CREATE OR REPLACE FUNCTION mchain_apply_forgetting(alpha_override REAL DEFAULT NULL)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    cfg RECORD;
    effective_alpha REAL;
    days_since REAL;
    is_sufficient BOOLEAN;
    details_text TEXT;
    err_context JSONB;
BEGIN
    SELECT use_adaptive_alpha, alpha, base_alpha, min_alpha,
           incident_half_life_days, last_incident_time,
           adaptive_forgetting_enabled
    INTO cfg
    FROM markov_config LIMIT 1;

    -- Если адаптивное забывание отключено глобально – ничего не делаем
    IF NOT cfg.adaptive_forgetting_enabled THEN
        RAISE DEBUG 'mchain_apply_forgetting: skipped because adaptive_forgetting_enabled = false';
        RETURN;
    END IF;

    -- Проверяем, достаточно ли обучена модель для применения забывания
    SELECT mchain_check_sufficiency() INTO is_sufficient;
    IF NOT is_sufficient THEN
        RAISE DEBUG 'mchain_apply_forgetting: skipped due to insufficient training data';
        INSERT INTO apply_forgetting_log (effective_alpha, adaptive_used, days_since_incident, alpha_override, details)
        VALUES (0.0, cfg.use_adaptive_alpha, NULL, alpha_override, 'Skipped - insufficient data');
        RETURN;
    END IF;

    -- Расчёт эффективного alpha
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

    IF effective_alpha <= 0.0 THEN
        RAISE DEBUG 'mchain_apply_forgetting: skipped because effective_alpha <= 0';
        INSERT INTO apply_forgetting_log (effective_alpha, adaptive_used, days_since_incident, alpha_override, details)
        VALUES (0.0, cfg.use_adaptive_alpha, days_since, alpha_override, 'Skipped - alpha zero');
        RETURN;
    END IF;

    -- Применяем забывание (оборачиваем в блок с обработкой ошибок)
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
        RAISE; -- перевыбрасываем, чтобы вызывающий знал о проблеме
    END;

    INSERT INTO apply_forgetting_log (effective_alpha, adaptive_used, days_since_incident, alpha_override, details)
    VALUES (effective_alpha, cfg.use_adaptive_alpha, days_since, alpha_override, details_text);

    RAISE DEBUG 'mchain_apply_forgetting: applied alpha=%', effective_alpha;
END;
$$;

COMMENT ON FUNCTION mchain_apply_forgetting(REAL) IS 'Применяет забывание (адаптивное или по конфигурации)';

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
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    cfg_min_transitions INT;
    total_transitions BIGINT;
    max_change REAL;
BEGIN
    -- Получаем порог из конфигурации, если не передан явно
    IF min_transitions IS NULL THEN
        SELECT COALESCE(min_transitions_for_forgetting, 5000) INTO cfg_min_transitions FROM markov_config LIMIT 1;
    ELSE
        cfg_min_transitions := min_transitions;
    END IF;

    -- 1. Проверка общего числа переходов
    SELECT COUNT(*) INTO total_transitions FROM transition_log;
    IF total_transitions < cfg_min_transitions THEN
        RAISE DEBUG 'mchain_check_sufficiency: too few transitions (%)', total_transitions;
        RETURN FALSE;
    END IF;

    -- 2. Проверка стабильности вероятностей (если достаточно данных для вычислений)
    IF total_transitions >= 2 * cfg_min_transitions THEN
        WITH recent AS (
            SELECT from_state, to_state,
                   COUNT(*)::REAL / SUM(COUNT(*)) OVER (PARTITION BY from_state) AS prob
            FROM transition_log
            WHERE ts >= now() - (weeks_history || ' weeks')::INTERVAL
              AND ts < now() - (weeks_history/2 || ' weeks')::INTERVAL
            GROUP BY from_state, to_state
        ),
        current AS (
            SELECT from_state, to_state,
                   COUNT(*)::REAL / SUM(COUNT(*)) OVER (PARTITION BY from_state) AS prob
            FROM transition_log
            WHERE ts >= now() - (weeks_history/2 || ' weeks')::INTERVAL
            GROUP BY from_state, to_state
        )
        SELECT MAX(ABS(COALESCE(r.prob, 0) - COALESCE(c.prob, 0))) INTO max_change
        FROM recent r
        FULL JOIN current c USING (from_state, to_state);

        IF max_change > max_prob_change THEN
            RAISE DEBUG 'mchain_check_sufficiency: probability change too high (%)', max_change;
            RETURN FALSE;
        END IF;
    END IF;

    RETURN TRUE;
END;
$$;
COMMENT ON FUNCTION mchain_check_sufficiency(INT, REAL, INT) IS 'Проверяет достаточность обучения (объём данных + стабильность вероятностей)';

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
BEGIN
    -- Общее число переходов
    SELECT COUNT(*) INTO total_transitions FROM transition_log;

    -- 1. Базовая оценка по объёму данных (0-2)
    IF total_transitions < 100 THEN
        RETURN 0;
    ELSIF total_transitions < 500 THEN
        base_score := 1;
    ELSIF total_transitions < 5000 THEN
        base_score := 2;
    ELSE
        base_score := 3;  -- достаточно данных для минимальной достоверности
    END IF;

    -- Если данных мало (менее 5000), стабильность и покрытие не вычисляем
    IF total_transitions < 5000 THEN
        RETURN base_score;
    END IF;

    -- 2. Стабильность вероятностей (максимальное изменение за 14 дней)
    WITH recent AS (
        SELECT from_state, to_state,
               COUNT(*)::REAL / SUM(COUNT(*)) OVER (PARTITION BY from_state) AS prob
        FROM transition_log
        WHERE ts >= now() - INTERVAL '14 days'
          AND ts < now() - INTERVAL '7 days'
        GROUP BY from_state, to_state
    ),
    current AS (
        SELECT from_state, to_state,
               COUNT(*)::REAL / SUM(COUNT(*)) OVER (PARTITION BY from_state) AS prob
        FROM transition_log
        WHERE ts >= now() - INTERVAL '7 days'
        GROUP BY from_state, to_state
    )
    SELECT COALESCE(MAX(ABS(COALESCE(r.prob, 0) - COALESCE(c.prob, 0))), 1.0) INTO max_prob_change
    FROM recent r
    FULL JOIN current c USING (from_state, to_state);

    -- Бонус за стабильность (0-2)
    IF max_prob_change < 0.02 THEN
        stability_bonus := 2;
    ELSIF max_prob_change < 0.05 THEN
        stability_bonus := 1;
    ELSE
        stability_bonus := 0;
    END IF;

    -- 3. Покрытие частых состояний (аналог критерия C1 из evaluate_training_sufficiency)
    WITH state_stats AS (
        SELECT from_state, COUNT(*) AS n_i,
               COUNT(*)::REAL / total_transitions AS freq
        FROM transition_log
        GROUP BY from_state
    ),
    frequent_states AS (
        SELECT from_state
        FROM state_stats
        WHERE freq > 0.01   -- частота >1%
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

    -- Бонус за покрытие (0-1)
    IF coverage_pct >= 90 THEN
        coverage_bonus := 1;
    ELSIF coverage_pct >= 70 THEN
        coverage_bonus := 0;
    ELSE
        coverage_bonus := 0;  -- штраф не применяем, просто нет бонуса
    END IF;

    -- Итоговый рейтинг: база (3) + бонус стабильности (0-2) + бонус покрытия (0-1)
    RETURN base_score + stability_bonus + coverage_bonus;
END;
$$;

COMMENT ON FUNCTION mchain_forecast_reliability() IS 'Оценивает достоверность прогнозов от 0 до 5 (объём данных, стабильность, покрытие частых состояний)';



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
    SELECT mchain_check_sufficiency() INTO sufficient;
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
BEGIN
    -- Получаем порог из конфигурации
    SELECT COALESCE(min_transitions_for_forgetting, 5000) INTO min_transitions_threshold
    FROM markov_config LIMIT 1;

    -- 1. Общее число переходов
    SELECT COUNT(*) INTO total_transitions FROM transition_log;

    -- 2. Стабильность вероятностей (максимальное изменение за 14 дней)
    IF total_transitions >= 5000 THEN
        WITH recent AS (
            SELECT from_state, to_state,
                   COUNT(*)::REAL / SUM(COUNT(*)) OVER (PARTITION BY from_state) AS prob
            FROM transition_log
            WHERE ts >= now() - INTERVAL '14 days'
              AND ts < now() - INTERVAL '7 days'
            GROUP BY from_state, to_state
        ),
        current AS (
            SELECT from_state, to_state,
                   COUNT(*)::REAL / SUM(COUNT(*)) OVER (PARTITION BY from_state) AS prob
            FROM transition_log
            WHERE ts >= now() - INTERVAL '7 days'
            GROUP BY from_state, to_state
        )
        SELECT COALESCE(MAX(ABS(COALESCE(r.prob, 0) - COALESCE(c.prob, 0))), 1.0) INTO max_prob_change
        FROM recent r
        FULL JOIN current c USING (from_state, to_state);
    ELSE
        max_prob_change := NULL;
    END IF;

    -- 3. Покрытие частых состояний (только если данных достаточно)
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

    -- Итоговый рейтинг достоверности
    SELECT mchain_forecast_reliability() INTO reliability_score;

    -- Формирование отчёта
    report := report || 'ОТЧЁТ О ДОСТОВЕРНОСТИ ПРОГНОЗОВ ЦЕПИ МАРКОВА' || line_sep;
    report := report || E'\n1. ОБЩИЙ РЕЙТИНГ ДОСТОВЕРНОСТИ (0-5): ' || reliability_score::TEXT || E'\n';
    
    CASE reliability_score
        WHEN 0 THEN report := report || '   Интерпретация: модель не обучена (нет данных или менее 100 переходов). Прогнозы недостоверны.' || E'\n';
        WHEN 1 THEN report := report || '   Интерпретация: очень мало данных (100-499 переходов). Прогнозы случайны.' || E'\n';
        WHEN 2 THEN report := report || '   Интерпретация: недостаточно данных (500-4999 переходов). Прогнозы нестабильны.' || E'\n';
        WHEN 3 THEN report := report || '   Интерпретация: минимально достаточный объём данных, но вероятности ещё не стабилизировались или покрытие низкое.' || E'\n';
        WHEN 4 THEN report := report || '   Интерпретация: хорошая достоверность. Прогнозам можно доверять в большинстве ситуаций.' || E'\n';
        WHEN 5 THEN report := report || '   Интерпретация: отличная достоверность. Прогнозы максимально надёжны.' || E'\n';
    END CASE;

    report := report || line_sep;
    report := report || E'\n2. ДЕТАЛИЗАЦИЯ ПО МЕТРИКАМ\n';

    -- Общее число переходов
    report := report || E'\n   Общее число переходов (total_transitions): ' || total_transitions::TEXT;
    report := report || E'\n   Рекомендуемое минимальное значение: ' || min_transitions_threshold::TEXT || ' (min_transitions_for_forgetting)';
    IF total_transitions >= min_transitions_threshold THEN
        report := report || E'\n   Статус: ДОСТАТОЧНО – модель имеет необходимый объём данных.' || E'\n';
    ELSE
        report := report || E'\n   Статус: НЕДОСТАТОЧНО – требуется накопить больше переходов.' || E'\n';
    END IF;

    -- Стабильность вероятностей
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

    -- Покрытие частых состояний
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

    -- Рекомендации
    report := report || line_sep;
    report := report || E'\n3. РЕКОМЕНДАЦИИ\n';
    IF reliability_score < 3 THEN
        report := report || E'   - Продолжить обучение модели, не полагаясь на прогнозы для принятия решений.\n';
        report := report || E'   - Увеличить период накопления данных (минимум 5000 переходов).\n';
        report := report || E'   - Если прошло много времени, проверить поступление метрик в cluster_stat_median.\n';
    ELSIF reliability_score < 5 THEN
        report := report || E'   - Прогнозы можно использовать с осторожностью, особенно при высоком риске.\n';
        report := report || E'   - Для достижения максимальной достоверности следует улучшить стабильность вероятностей и покрытие частых состояний.\n';
    ELSE
        report := report || E'   - Модель полностью готова к эксплуатации. Прогнозы имеют высокую достоверность.\n';
        report := report || E'   - Рекомендуется поддерживать актуальность с помощью планового забывания (адаптивный alpha).\n';
    END IF;

    report := report || line_sep;
    report := report || E'\nДата формирования отчёта: ' || format_timestamptz_to_minute(now())::TEXT;

    RETURN report;
END;
$$;
COMMENT ON FUNCTION mchain_reliability_report() IS 'Возвращает расширенный текстовый отчёт о достоверности прогнозов с метриками, порогами и рекомендациями';

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

    -- Получение списка аварийных состояний (correlation < 0 AND os_trend = -1)
    SELECT array_agg(state_id) INTO v_acc_state_ids
    FROM state_descriptions
    WHERE correlation < 0 AND os_trend = -1 AND wait_trend = 1;
    
    IF v_acc_state_ids IS NULL OR array_length(v_acc_state_ids, 1) = 0 THEN
        RETURN 'Ошибка: не найдено ни одного аварийного состояния в state_descriptions. Выполните SELECT fill_state_descriptions();';
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
    -- Формирование отчёта (без использования спецификаторов %f, только %s и %%)
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


--------------------------------------------------------------------------------
-- mchain_summary_report
-- Сводный отчёт по состоянию цепи Маркова:
--   - общая достоверность прогнозов (mchain_reliability_report)
--   - анализ переходов в аварию за период (mchain_incident_transitions_report)
--   - параметры конфигурации (забывание, пороги)
--   - текущее состояние системы (если доступно)
-- Параметры:
--   p_start TIMESTAMPTZ DEFAULT NULL – начало периода (по умолч. now() - interval '7 days')
--   p_end   TIMESTAMPTZ DEFAULT NULL – конец периода (по умолч. now())
--------------------------------------------------------------------------------
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
    -- 2. Конфигурация цепи Маркова
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
        transition_log_retention_days
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
    -- 4. Формирование сводного отчёта (с использованием format_timestamptz_to_minute)
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
    v_report := v_report || '   Последнее забывание: ' || COALESCE(format_timestamptz_to_minute(v_config.last_forget_time), 'никогда') || E'\n';
    v_report := v_report || '   Последний инцидент: ' || COALESCE(format_timestamptz_to_minute(v_config.last_incident_time), 'не зафиксирован') || E'\n';
    
-- DISABLED FOR VERSION 11
/*
    -- Блок: Текущее состояние
    v_report := v_report || v_sub_sep;
    v_report := v_report || E'\n2. ТЕКУЩЕЕ СОСТОЯНИЕ СИСТЕМЫ' || E'\n';
    v_report := v_report || '   State ID: ' || COALESCE(v_current_state_id::TEXT, 'неизвестно') || E'\n';
    v_report := v_report || '   Параметры: ' || v_current_desc || E'\n';
    
    -- Прогноз риска на 1 минуту (дополнительно)
    BEGIN
        DECLARE
            risk1 REAL;
            sit TEXT;
        BEGIN
            SELECT risk, curr_situation INTO risk1, sit FROM mchain_predict_risk_1min();
            v_report := v_report || '   Прогноз риска на следующую минуту: ' || COALESCE(risk1::TEXT, 'н/д') || ' (' || COALESCE(sit, 'unknown') || ')' || E'\n';
        END;
    EXCEPTION WHEN OTHERS THEN
        v_report := v_report || '   Прогноз риска на следующую минуту: недоступен (' || SQLERRM || ')' || E'\n';
    END;
*/
-- DISABLED FOR VERSION 11

    -- Блок: Отчёт о достоверности (целиком)
    v_report := v_report || v_sub_sep;
    v_report := v_report || E'\n3. ДОСТОВЕРНОСТЬ ПРОГНОЗОВ' || E'\n';
    v_report := v_report || v_reliability_text || E'\n';
    
    -- Блок: Отчёт о переходах в аварию (целиком)
    v_report := v_report || v_sub_sep;
    v_report := v_report || E'\n4. АНАЛИЗ ПЕРЕХОДОВ В АВАРИЮ ЗА ПЕРИОД' || E'\n';
    v_report := v_report || v_incident_text || E'\n';
    
    -- Блок: Итоговые рекомендации
    v_report := v_report || v_line_sep;
    v_report := v_report || E'\n5. ОБЩИЕ РЕКОМЕНДАЦИИ' || E'\n';
    
    -- Оценка достоверности из первого отчёта (извлекаем числовой рейтинг)
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
    
    -- Проверка актуальности данных
    IF v_config.last_incident_time IS NOT NULL AND 
       (now() - v_config.last_incident_time) > INTERVAL '30 days' AND
       v_config.use_adaptive_alpha THEN
        v_report := v_report || '   → Давно не было инцидентов (>30 дней). alpha мог снизиться до минимума. Если система изменилась, выполните mchain_apply_forgetting(0.05) для ручной коррекции.' || E'\n';
    END IF;
    
    v_report := v_report || v_line_sep;
    
    RETURN v_report;
END;
$$;

COMMENT ON FUNCTION mchain_summary_report(TIMESTAMPTZ, TIMESTAMPTZ) IS 'Сводный отчёт по цепи Маркова: достоверность, переходы в аварию за период, конфигурация, текущее состояние. По умолчанию период – последние 7 дней. Временные метки округлены до минут.';
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
    
    -- Переменные для статистики по инцидентам
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

    -- Список аварийных состояний (correlation<0, os_trend=-1, wait_trend=1)
    SELECT array_agg(state_id ORDER BY state_id) INTO v_acc_state_ids
    FROM state_descriptions
    WHERE correlation < 0 AND os_trend = -1 AND wait_trend = 1;
    
    IF v_acc_state_ids IS NULL OR array_length(v_acc_state_ids, 1) = 0 THEN
        RETURN 'Ошибка: не найдено аварийных состояний. Выполните SELECT fill_state_descriptions();';
    END IF;

    -- ========================================================================
    -- 0. Статистика по инцидентам производительности (performance_incident)
    -- ========================================================================
    SELECT EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_name = 'performance_incident'
    ) INTO v_tbl_exists;
    
    IF v_tbl_exists THEN
        -- Все инциденты, которые пересекаются с периодом отчёта
        WITH incidents_in_period AS (
            SELECT 
                pi.id,
                pi.priority,
                pi.start_timepoint,
                pi.finish_timepoint,
                CASE WHEN pi.finish_timepoint IS NULL THEN TRUE ELSE FALSE END AS is_unfinished
            FROM performance_incident pi
            WHERE (pi.finish_timepoint IS NULL AND pi.start_timepoint < v_end)
               OR (pi.finish_timepoint IS NOT NULL 
                   AND pi.start_timepoint < v_end 
                   AND pi.finish_timepoint > v_start)
        )
        SELECT 
            COUNT(*) AS total,
            COUNT(*) FILTER (WHERE is_unfinished) AS unfinished,
            (SELECT string_agg(format('%s: %s', priority, cnt), ', ' ORDER BY priority)
             FROM (SELECT priority, COUNT(*) AS cnt FROM incidents_in_period GROUP BY priority) t) AS priority_dist,
            COUNT(*) FILTER (WHERE NOT is_unfinished) AS completed
        INTO v_inc_total, v_inc_unfinished, v_inc_by_priority, v_completed_incidents
        FROM incidents_in_period;
        
        -- Длительность (только для завершённых инцидентов)
        SELECT 
            AVG(EXTRACT(EPOCH FROM (finish_timepoint - start_timepoint))/60),
            SUM(EXTRACT(EPOCH FROM (finish_timepoint - start_timepoint))/60),
            MAX(EXTRACT(EPOCH FROM (finish_timepoint - start_timepoint))/60)
        INTO v_avg_duration_min, v_total_duration_min, v_max_duration_min
        FROM performance_incident pi
        WHERE pi.finish_timepoint IS NOT NULL
          AND pi.start_timepoint < v_end
          AND pi.finish_timepoint > v_start;
        
        -- Если нет завершённых, обнуляем
        IF v_completed_incidents IS NULL OR v_completed_incidents = 0 THEN
            v_avg_duration_min := 0;
            v_total_duration_min := 0;
            v_max_duration_min := 0;
        END IF;
        
        -- Инциденты, которым предшествовал аварийный переход в течение 5 минут
        WITH incidents_with_prev_acc AS (
            SELECT 
                pi.start_timepoint,
                (SELECT tl.ts
                 FROM transition_log tl
                 WHERE tl.to_state = ANY(v_acc_state_ids)
                   AND tl.ts <= pi.start_timepoint
                   AND pi.start_timepoint - tl.ts <= interval '5 minutes'
                 ORDER BY tl.ts DESC
                 LIMIT 1) AS prev_acc_time
            FROM performance_incident pi
            WHERE (pi.finish_timepoint IS NULL AND pi.start_timepoint < v_end)
               OR (pi.finish_timepoint IS NOT NULL 
                   AND pi.start_timepoint < v_end 
                   AND pi.finish_timepoint > v_start)
        )
        SELECT 
            COUNT(*) FILTER (WHERE prev_acc_time IS NOT NULL) AS following,
            AVG(EXTRACT(EPOCH FROM (start_timepoint - prev_acc_time))/60) FILTER (WHERE prev_acc_time IS NOT NULL) AS avg_lag_min
        INTO v_inc_following_incident, v_avg_time_to_incident_min
        FROM incidents_with_prev_acc;
        
        -- Формирование блока отчёта по инцидентам
        v_report := v_report || 'ИНЦИДЕНТЫ ПРОИЗВОДИТЕЛЬНОСТИ ЗА ПЕРИОД' || v_line_sep;
        v_report := v_report || 'Период отчёта: ' 
                    || format_timestamptz_to_minute(v_start) || ' – ' 
                    || format_timestamptz_to_minute(v_end) || E'\n';
        IF v_inc_total IS NULL OR v_inc_total = 0 THEN
            v_report := v_report || 'Нет инцидентов, пересекающихся с периодом.' || E'\n';
        ELSE
            v_report := v_report || 'Всего инцидентов: ' || v_inc_total::TEXT;
            IF v_inc_unfinished > 0 THEN
                v_report := v_report || ' (незавершённых: ' || v_inc_unfinished::TEXT || ')';
            END IF;
            v_report := v_report || E'\n';
            v_report := v_report || 'Распределение по приоритетам: ' || COALESCE(v_inc_by_priority, 'нет') || E'\n';
            
            IF v_completed_incidents > 0 THEN
                v_report := v_report || 'Завершённых инцидентов: ' || v_completed_incidents::TEXT || E'\n';
                v_report := v_report || 'Общая длительность завершённых инцидентов (минут): ' || round(v_total_duration_min, 1)::TEXT || E'\n';
                v_report := v_report || 'Средняя длительность завершённых инцидентов (минут): ' || round(v_avg_duration_min, 1)::TEXT || E'\n';
                v_report := v_report || 'Максимальная длительность завершённых инцидентов (минут): ' || round(v_max_duration_min, 1)::TEXT || E'\n';
            ELSE
                v_report := v_report || 'Нет завершённых инцидентов за период – длительность не рассчитывалась.' || E'\n';
            END IF;
            
            v_report := v_report || 'Инцидентов, начавшихся в течение 5 минут после аварийного перехода: ' || v_inc_following_incident::TEXT;
            IF v_inc_following_incident > 0 THEN
                v_report := v_report || ' (средняя задержка ' || round(v_avg_time_to_incident_min, 1)::TEXT || ' мин.)';
            END IF;
            v_report := v_report || E'\n';
        END IF;
        v_report := v_report || v_sub_sep;
    ELSE
        v_report := v_report || 'ПРЕДУПРЕЖДЕНИЕ: таблица performance_incident не найдена. Статистика инцидентов недоступна.' || v_line_sep;
    END IF;

    -- ========================================================================
    -- 1. Основной отчёт по аварийным состояниям
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
        WHERE correlation < 0 AND os_trend = -1 AND wait_trend = 1
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
    
    -- Добавляем дату формирования отчёта
    v_report := v_report || v_sub_sep;
    v_report := v_report || 'Дата формирования отчёта: ' || format_timestamptz_to_minute(now()) || E'\n';
    
    RETURN v_report;
END;
$$;

COMMENT ON FUNCTION mchain_incident_state_detail_report(TIMESTAMPTZ, TIMESTAMPTZ) IS 'Детальный отчёт по аварийным состояниям + статистика по инцидентам производительности. Незавершённые инциденты (finish IS NULL) считаются пересекающимися с периодом, если start_timepoint < p_end. Длительность рассчитывается только по завершённым инцидентам. Временные метки округлены до минут.';

COMMENT ON FUNCTION mchain_incident_state_detail_report(TIMESTAMPTZ, TIMESTAMPTZ) IS 'Детальный отчёт по аварийным состояниям + статистика по инцидентам производительности. Незавершённые инциденты (finish IS NULL) считаются пересекающимися с периодом, если start_timepoint < p_end. Длительность рассчитывается только по завершённым инцидентам.';


--------------------------------------------------------------------------------
-- mchain_health_check
-- Проверяет состояние цепи Маркова и возвращает статус (OK, WARNING, CRITICAL)
-- с подробным сообщением. Предназначена для систем мониторинга.
-- Возвращает: status TEXT, message TEXT
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION mchain_health_check()
RETURNS TABLE (status TEXT, message TEXT)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_status TEXT := 'OK';
    v_messages TEXT[] := '{}';
    v_reliability INT;
    v_last_incident_period_pct NUMERIC;
    v_prev_period_pct NUMERIC;
    v_growth_ratio NUMERIC;
    v_config RECORD;
    v_recent_transitions BIGINT;
    v_has_frequencies BOOLEAN;
    v_incident_pct_last NUMERIC;
    v_incident_pct_prev NUMERIC;
BEGIN
    -- 1. Проверка достоверности прогнозов
    BEGIN
        SELECT mchain_forecast_reliability() INTO v_reliability;
        IF v_reliability = 0 THEN
            v_status := 'CRITICAL';
            v_messages := v_messages || 'Модель не обучена (рейтинг 0). Нет данных или менее 100 переходов.';
        ELSIF v_reliability < 3 THEN
            IF v_status != 'CRITICAL' THEN v_status := 'WARNING'; END IF;
            v_messages := v_messages || format('Низкая достоверность (%s). Требуется больше данных.', v_reliability);
        END IF;
    EXCEPTION WHEN OTHERS THEN
        v_status := 'CRITICAL';
        v_messages := v_messages || 'Ошибка при получении достоверности: ' || SQLERRM;
    END;

    -- 2. Проверка роста аварийных переходов (последние 7 дней vs предыдущие 7 дней)
    BEGIN
        WITH accidents AS (
            SELECT 
                ts,
                CASE WHEN to_state IN (
                    SELECT state_id FROM state_descriptions 
                    WHERE correlation < 0 AND os_trend = -1 AND wait_trend = 1
                ) THEN 1 ELSE 0 END AS is_accident
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
        
        IF v_incident_pct_prev IS NOT NULL AND v_incident_pct_prev > 0 THEN
            v_growth_ratio := (COALESCE(v_incident_pct_last, 0) / v_incident_pct_prev);
            IF v_growth_ratio > 3 THEN
                v_status := 'CRITICAL';
                v_messages := v_messages || format('Рост аварийных переходов более чем в 3 раза (%.1f%% -> %.1f%%)', 
                    v_incident_pct_prev, COALESCE(v_incident_pct_last, 0));
            ELSIF v_growth_ratio > 2 THEN
                IF v_status != 'CRITICAL' THEN v_status := 'WARNING'; END IF;
                v_messages := v_messages || format('Значительный рост аварийных переходов (%.1f%% -> %.1f%%)', 
                    v_incident_pct_prev, COALESCE(v_incident_pct_last, 0));
            END IF;
        END IF;
    EXCEPTION WHEN OTHERS THEN
        NULL;
    END;

    -- 3. Проверка забывания: давно ли не применялось (с использованием сервисной функции форматирования)
    BEGIN
        SELECT interval_minute, last_forget_time INTO v_config FROM markov_config LIMIT 1;
        IF v_config.last_forget_time < now() - (v_config.interval_minute * 2 || ' minutes')::INTERVAL THEN
            IF v_status != 'CRITICAL' THEN v_status := 'WARNING'; END IF;
            v_messages := v_messages || format('Забывание не применялось с %s (> %s мин)',
                                               format_timestamptz_to_minute(v_config.last_forget_time),
                                               v_config.interval_minute * 2);
        END IF;
    EXCEPTION WHEN OTHERS THEN
        v_messages := v_messages || 'Не удалось проверить забывание (нет markov_config?)';
    END;

    -- 4. Проверка активности: есть ли переходы за последние 10 минут
    BEGIN
        SELECT COUNT(*) INTO v_recent_transitions FROM transition_log WHERE ts >= now() - INTERVAL '10 minutes';
        IF v_recent_transitions = 0 THEN
            v_status := 'CRITICAL';
            v_messages := v_messages || 'Нет переходов за последние 10 минут (возможно, остановлен mchain_train_step).';
        END IF;
    EXCEPTION WHEN OTHERS THEN
        v_messages := v_messages || 'Ошибка при проверке переходов: ' || SQLERRM;
    END;

    -- 5. Проверка наличия данных в markov_frequencies
    BEGIN
        SELECT EXISTS (SELECT 1 FROM markov_frequencies LIMIT 1) INTO v_has_frequencies;
        IF NOT v_has_frequencies THEN
            IF v_status != 'CRITICAL' THEN v_status := 'WARNING'; END IF;
            v_messages := v_messages || 'Таблица markov_frequencies пуста (модель не обучена).';
        END IF;
    EXCEPTION WHEN OTHERS THEN
        v_messages := v_messages || 'Ошибка при проверке markov_frequencies: ' || SQLERRM;
    END;

    -- Формирование итогового сообщения
    IF array_length(v_messages, 1) IS NULL OR array_length(v_messages, 1) = 0 THEN
        message := 'Все проверки пройдены. Цепь Маркова работает штатно.';
    ELSE
        message := array_to_string(v_messages, '; ');
    END IF;
    status := v_status;
    
    RETURN NEXT;
END;
$$;

COMMENT ON FUNCTION mchain_health_check() IS 'Проверяет состояние цепи Маркова: достоверность, рост аварий, забывание, активность. Возвращает статус (OK/WARNING/CRITICAL) и сообщение.';

COMMENT ON FUNCTION mchain_health_check() IS 'Проверяет состояние цепи Маркова: достоверность, рост аварий, забывание, активность. Возвращает статус (OK/WARNING/CRITICAL) и сообщение.';


--------------------------------------------------------------------------------
-- mchain_state_transition_matrix_report
-- Формирует матрицу переходов между укрупнёнными группами состояний.
-- Группировка:
--   - если p_include_wait_trend = FALSE: 3 (знак корреляции) × 3 (тренд OS) = 9 групп.
--   - если TRUE: 3 (корр) × 3 (OS) × 3 (wait) = 27 групп.
-- Источник: markov_probabilities (усреднение по состояниям внутри группы)
-- Параметры:
--   p_use_weighted BOOLEAN DEFAULT FALSE – взвешивание по частоте исходных состояний
--   p_include_wait_trend BOOLEAN DEFAULT FALSE – включать ли тренд ожиданий в группировку
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION mchain_state_transition_matrix_report(
    p_use_weighted BOOLEAN DEFAULT FALSE,
    p_include_wait_trend BOOLEAN DEFAULT FALSE
)
RETURNS TEXT
LANGUAGE plpgsql
STABLE
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
        PERFORM (SELECT 1); -- заглушка для синтаксиса
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
-- Формирование истории по прогнозу 
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION collect_prediction_15min()
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    curr_state SMALLINT;
    risk REAL;
BEGIN
    curr_state := mchain_get_current_state_id();
    IF curr_state IS NULL THEN
        RETURN;
    END IF;
    risk := mchain_predict_risk_k_v2(curr_state, 15);
    INSERT INTO prediction_log (
        prediction_time, predicted_risk, situation,
        transitions_to_risk, total_transitions_known, current_state_id
    ) VALUES (
        now(), risk, 'risk_calculated',
        NULL, NULL, curr_state
    );
EXCEPTION WHEN OTHERS THEN
    INSERT INTO mchain_quality_errors (error_message, function_name, details)
    VALUES (SQLERRM, 'collect_prediction_15min',
            jsonb_build_object('sqlstate', SQLSTATE, 'timestamp', now()));
    RAISE WARNING 'collect_prediction_15min failed: %', SQLERRM;
END;
$$;
COMMENT ON FUNCTION collect_prediction_15min IS 'Формирование истории по прогнозу ';

--------------------------------------------------------------------------------
-- Обновление исходов для прогнозов, которым уже > 15 минут
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION update_prediction_outcomes_15min()
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    rec RECORD;
    incident_ts TIMESTAMPTZ;
    incident_cnt INT;
    updated INT := 0;
BEGIN
    FOR rec IN
        SELECT id, prediction_time
        FROM prediction_log
        WHERE actual_outcome IS NULL
          AND prediction_time <= now() - INTERVAL '15 minutes'
        ORDER BY prediction_time
        LIMIT 1000  -- защита от перегрузки
    LOOP
        -- Ищем первый аварийный переход в интервале (prediction_time, prediction_time + 15 мин]
        SELECT MIN(ts), COUNT(*)
        INTO incident_ts, incident_cnt
        FROM transition_log tl
        WHERE tl.to_state IN (SELECT get_critical_state_ids(TRUE))
          AND tl.ts > rec.prediction_time
          AND tl.ts <= rec.prediction_time + INTERVAL '15 minutes';

        UPDATE prediction_log
        SET actual_outcome = CASE WHEN incident_ts IS NULL THEN 0 ELSE 1 END,
            first_incident_time = incident_ts,
            incident_count = COALESCE(incident_cnt, 0)
        WHERE id = rec.id;

        updated := updated + 1;
    END LOOP;

    RETURN format('Updated outcomes for %s predictions', updated);
END;
$$;
COMMENT ON FUNCTION update_prediction_outcomes_15min IS 'Обновление исходов для прогнозов, которым уже > 15 минут';

--------------------------------------------------------------------------------
-- Расчёт суточных метрик и сохранение в историю
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION calculate_daily_quality_metrics(p_date DATE DEFAULT CURRENT_DATE - 1)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    v_from TIMESTAMPTZ := p_date::TIMESTAMPTZ;
    v_to   TIMESTAMPTZ := p_date::TIMESTAMPTZ + INTERVAL '1 day';
    v_reliability INT;
    v_predictions_count INT;
    v_metrics JSONB;
    v_result TEXT;
BEGIN
    -- 1. Проверка достоверности модели (глобальный рейтинг)
    SELECT mchain_forecast_reliability() INTO v_reliability;
    
    -- 2. Проверка количества прогнозов за день (дополнительный критерий)
    SELECT COUNT(*) INTO v_predictions_count
    FROM prediction_log
    WHERE prediction_time >= v_from AND prediction_time < v_to
      AND actual_outcome IS NOT NULL;

    -- 3. Если рейтинг < 3 ИЛИ прогнозов за день меньше 100 – диагностическое сообщение
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
            format('Skipped: reliability=%s, predictions=%s (min 100 required)', 
                   v_reliability, v_predictions_count)
        );
        RETURN format('Diagnostic: metrics not calculated (reliability=%s, predictions=%s)', 
                      v_reliability, v_predictions_count);
    END IF;

    -- 4. Достаточно данных – рассчитываем метрики
    WITH predictions AS (
        SELECT predicted_risk, actual_outcome
        FROM prediction_log
        WHERE prediction_time >= v_from AND prediction_time < v_to
          AND actual_outcome IS NOT NULL
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
        'OK' AS notes
    FROM metrics, calibration;

    RETURN format('Metrics saved for date %s (reliability=%s, predictions=%s)', 
                  p_date, v_reliability, v_predictions_count);
END;
$$;
COMMENT ON FUNCTION calculate_daily_quality_metrics IS 'Расчёт суточных метрик и сохранение в историю';

--------------------------------------------------------------------------------
-- Отчет по качеству прогнозов
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION mchain_quality_report_15min(
    p_start DATE DEFAULT NULL,
    p_end DATE DEFAULT NULL
)
RETURNS TEXT
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_start TIMESTAMPTZ;
    v_end TIMESTAMPTZ;
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
    -- 1. Определение временного периода (по умолчанию предыдущие 7 дней)
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
    -- 2. Проверка наличия завершённых прогнозов
    -- ------------------------------------------------------------------
    SELECT COUNT(*) INTO v_total_predictions
    FROM prediction_log
    WHERE prediction_time >= v_start AND prediction_time < v_end
      AND actual_outcome IS NOT NULL
      AND predicted_risk IS NOT NULL;

    IF v_total_predictions = 0 THEN
        RETURN format('Нет завершённых прогнозов за период %s – %s. Возможно, данные ещё не обновлены.',
                      v_start::DATE, (v_end - INTERVAL '1 day')::DATE);
    END IF;

    -- ------------------------------------------------------------------
    -- 3. Расчёт общих метрик качества с защитой от log(0)
    --    Используем GREATEST для обрезки снизу в аргументе логарифма
    -- ------------------------------------------------------------------
    WITH predictions AS (
        SELECT 
            predicted_risk,
            actual_outcome
        FROM prediction_log
        WHERE prediction_time >= v_start AND prediction_time < v_end
          AND actual_outcome IS NOT NULL
          AND predicted_risk IS NOT NULL
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
    -- Вычисление ROC-AUC через ранжирование (Mann-Whitney U)
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
                   ROW_NUMBER() OVER (ORDER BY predicted_risk DESC) AS rank
            FROM predictions
        ) ranked
        WHERE actual_outcome IN (0,1)
    ),
    -- Precision и Recall при пороге 0.5
    pr_at_05 AS (
        SELECT
            SUM(CASE WHEN predicted_risk >= 0.5 AND actual_outcome = 1 THEN 1 ELSE 0 END) AS tp,
            SUM(CASE WHEN predicted_risk >= 0.5 AND actual_outcome = 0 THEN 1 ELSE 0 END) AS fp,
            SUM(CASE WHEN predicted_risk < 0.5 AND actual_outcome = 1 THEN 1 ELSE 0 END) AS fn
        FROM predictions
    ),
    -- Калибровка (10 бинов по 0.1)
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
                    WIDTH_BUCKET(predicted_risk, 0, 1, 10) AS bin,
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
        CASE WHEN (p.tp+p.fp) > 0 THEN p.tp/(p.tp+p.fp) ELSE 0 END AS precision,
        CASE WHEN (p.tp+p.fn) > 0 THEN p.tp/(p.tp+p.fn) ELSE 0 END AS recall,
        c.calib
    INTO v_incident_rate, v_avg_risk, v_brier, v_log_loss, v_mae,
         v_roc_auc, v_precision, v_recall, v_calib
    FROM stats s
    CROSS JOIN roc_auc_calc a
    CROSS JOIN pr_at_05 p
    CROSS JOIN calib c;

    -- ------------------------------------------------------------------
    -- 4. Формирование отчёта
    -- ------------------------------------------------------------------
    -- Заголовок и общая сводка
    v_report := v_report || 'ОТЧЁТ КАЧЕСТВА ПРОГНОЗОВ (ГОРИЗОНТ 15 МИНУТ)' || v_line_sep;
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

    -- Дневная динамика (из таблицы истории, если есть)
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
        -- Если в истории нет записей – вычисляем динамику на лету по сырым данным
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

    -- Диагностические сообщения (пропущенные расчёты из-за низкого рейтинга)
    -- ИСПРАВЛЕНИЕ: ORDER BY перенесён внутрь string_agg
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

COMMENT ON FUNCTION mchain_quality_report_15min(DATE, DATE) IS 'Формирует текстовый отчёт о качестве 15‑минутных прогнозов риска за указанный период.По умолчанию – предыдущие 7 дней. Включает калибровку, метрики (Brier, log‑loss, ROC‑AUC, precision/recall),дневную динамику и рекомендации. Учитывает диагностические записи из mchain_quality_metrics_history.Вероятности обрезаются снизу через GREATEST(..., 1e-15) для избежания log(0).';




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
    p_start           TIMESTAMPTZ DEFAULT NULL,
    p_end             TIMESTAMPTZ DEFAULT NULL,
    p_min_transitions INT         DEFAULT 50,
    p_interval_min    INT         DEFAULT 15,
    p_risk_threshold  REAL        DEFAULT 0.10,
    p_dry_run         BOOLEAN     DEFAULT FALSE,
    p_audit           BOOLEAN     DEFAULT TRUE   -- новый параметр
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

    -- Инициализация вектора
    v := array_fill(0.0, ARRAY[total_states]);
    IF p_state_id BETWEEN 0 AND total_states - 1 THEN
        v[p_state_id + 1] := 1.0;
    ELSE
        RETURN 0.0;
    END IF;

    -- Итерации
    FOR step IN 1..k LOOP
        v_new := array_fill(0.0, ARRAY[total_states]);

        -- Умножение вектора на матрицу вероятностей
        FOR rec IN
            SELECT from_state, to_state, probability
            FROM markov_probabilities
        LOOP
            IF v[rec.from_state + 1] > 0.0 THEN
                v_new[rec.to_state + 1] := v_new[rec.to_state + 1] + v[rec.from_state + 1] * rec.probability;
            END IF;
        END LOOP;

        v := v_new;

        -- Вычисляем вероятность оказаться в критическом состоянии на этом шаге
        FOR i IN 1..array_length(critical_ids, 1) LOOP
            risk := risk + v[critical_ids[i] + 1];
            v[critical_ids[i] + 1] := 0.0;  -- обнуляем, чтобы не учитывать повторно
        END LOOP;

        -- Если риск достиг 1, можно прерваться
        IF risk >= 1.0 THEN
            RETURN 1.0;
        END IF;
    END LOOP;

    RETURN LEAST(risk, 1.0);
END;
$$;
COMMENT ON FUNCTION mchain_predict_risk_k_v2( SMALLINT, INT ) IS 'Вероятность хотя бы одного попадания в критическое множество за k шагов';

  
-- =============================================================================
-- Прогноз риска аварии на ближайшие 15 минут
-- =============================================================================
CREATE OR REPLACE FUNCTION mchain_predict_risk_15min_v2()
RETURNS REAL
LANGUAGE sql
STABLE
AS $$
    SELECT mchain_predict_risk_k_v2(mchain_get_current_state_id(), 15);
$$;
COMMENT ON FUNCTION mchain_predict_risk_15min_v2() IS 'Прогноз риска аварии на ближайшие 15 минут';

-- =============================================================================
-- Прогноз риска аварии на ближайшие 30 минут
-- =============================================================================
CREATE OR REPLACE FUNCTION mchain_predict_risk_30min_v2()
RETURNS REAL
LANGUAGE sql
STABLE
AS $$
    SELECT mchain_predict_risk_k_v2(mchain_get_current_state_id(), 30);
$$;
COMMENT ON FUNCTION mchain_predict_risk_30min_v2() IS 'Прогноз риска аварии на ближайшие 30 минут';

-- =============================================================================
-- Прогноз риска аварии на ближайший час
-- =============================================================================
CREATE OR REPLACE FUNCTION mchain_predict_risk_1hour_v2()
RETURNS REAL
LANGUAGE sql
STABLE
AS $$
    SELECT mchain_predict_risk_k_v2(mchain_get_current_state_id(), 60);
$$;
COMMENT ON FUNCTION mchain_predict_risk_1hour_v2() IS 'Прогноз риска аварии на ближайший час';


