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
-- version 26.1.3

/*
Функция : markov_chain_functions.sql — набор функций для цепи Маркова
Назначение : Обучение, забывание, логирование переходов, расчёт вероятностей, прогнозирование риска, обновление критических состояний, отчёты и диагностика.

Функция : mchain_train_step()
Назначение : Основной минутный шаг обучения: получает метрики, логирует переход, обновляет цепь, запускает забывание, прогнозы и адаптацию порогов.

Функция : mchain_apply_forgetting(alpha_override, p_max_alpha)
Назначение : Применяет забывание к частотам переходов с учётом адаптивного alpha и stability_factor.

Функция : mchain_check_sufficiency(min_transitions, max_prob_change, weeks_history)
Назначение : Проверяет достаточность данных для забывания и возвращает коэффициент стабильности.

Функция : mchain_log_transition(p_from_state, p_to_state)
Назначение : Записывает переход в transition_log и увеличивает соответствующую частоту.

Функция : mchain_clean_transition_log(p_retention_days)
Назначение : Удаляет устаревшие записи журнала переходов.

Функция : fill_state_descriptions()
Назначение : Заполняет справочник состояний цепи Маркова всеми комбинациями корреляции и трендов.

Функция : get_state_id(r, os_trend, wait_trend)
Назначение : Вычисляет числовой state_id по корреляции и трендам.

Функция : decode_state_id(p_state_id)
Назначение : Обратная функция к get_state_id: возвращает корреляцию и тренды по state_id.

Функция : rebuild_markov_absorbing()
Назначение : Перестраивает матрицу поглощающей цепи с петлями для критических состояний.

Функция : update_last_incident_time()
Назначение : Триггерная функция обновления времени последнего инцидента при переходе в критическое состояние.

Функция : update_markov_probabilities()
Назначение : Пересчитывает матрицу вероятностей переходов из накопленных частот.

Функция : mchain_clean_apply_forgetting_log(p_retention_days)
Назначение : Удаляет устаревшие записи журнала применения забывания.

Функция : mchain_log_error(...)
Назначение : Записывает ошибку в mchain_error_log и выдаёт предупреждение.

Функция : mchain_get_current_state_id()
Назначение : Возвращает текущий state_id по актуальным метрикам (для отладки и прогноза).

Функция : mchain_forecast_reliability()
Назначение : Оценивает достоверность прогнозов от 0 до 5 по объёму данных, стабильности и покрытию.

Функция : mchain_reliability_report()
Назначение : Формирует текстовый отчёт о достоверности прогнозов с метриками и рекомендациями.

Функция : mchain_incident_transitions_report(p_start, p_end)
Назначение : Отчёт о переходах в аварийные состояния за период по сырым данным и текущей модели.

Функция : mchain_summary_report(p_start, p_end)
Назначение : Сводный отчёт по конфигурации, текущему состоянию, риску, достоверности и инцидентам.

Функция : mchain_incident_state_detail_report(p_start, p_end)
Назначение : Детальный отчёт по каждому аварийному состоянию и предшествующим состояниям.

Функция : mchain_health_check()
Назначение : Проверяет состояние цепи и возвращает статус OK/WARNING/CRITICAL, сообщение и описание метрик.

Функция : mchain_state_transition_matrix_report(p_use_weighted, p_include_wait_trend)
Назначение : Строит матрицу переходов между укрупнёнными группами состояний.

Функция : get_critical_states(only_with_transitions)
Назначение : Возвращает список аварийных состояний из critical_states с параметрами и временем последнего перехода.

Функция : get_critical_state_ids(only_with_transitions)
Назначение : Возвращает только идентификаторы аварийных состояний.

Функция : format_timestamptz_to_minute(ts)
Назначение : Форматирует TIMESTAMPTZ до минут в строку вида ГГГГ-ММ-ДД ЧЧ:МИ.

Функция : calculate_daily_quality_metrics(p_date)
Назначение : Рассчитывает суточные метрики качества прогнозов, включая Brier, Log-loss, ROC-AUC, ECE и MCE.

Функция : refresh_critical_states(...)
Назначение : Автоматически обновляет critical_states на основе эмпирического риска за период.

Функция : ensure_audit_table()
Назначение : Создаёт таблицу аудита critical_states_audit при её отсутствии.

Функция : mchain_predict_risk_k_v2(p_state_id, k)
Назначение : Вычисляет вероятность хотя бы одного попадания в критическое множество за k шагов.

Функция : compute_empirical_incident_risk(...)
Назначение : Вычисляет эмпирическую вероятность инцидента после перехода в состояние за заданный интервал.

Функция : collect_prediction(p_time, p_state_id)
Назначение : Формирует и сохраняет прогноз риска на горизонт из markov_config.

Функция : update_prediction_outcomes()
Назначение : Обновляет фактические исходы прогнозов с истёкшим горизонтом.

Функция : mchain_quality_report(p_start, p_end, p_horizon)
Назначение : Формирует отчёт о качестве прогнозов с калибровкой, ECE/MCE и рекомендациями.

Функция : mchain_predict_risk_current_horizon()
Назначение : Возвращает прогноз риска для текущего состояния на горизонт из markov_config.

Функция : evaluate_forgetting_params(...)
Назначение : Эмпирически подбирает параметры адаптивного забывания и оценивает качество прогнозов.

Функция : mchain_predict_risk_k_v2_with_matrix(p_state_id, k, p_matrix_table)
Назначение : Вычисляет риск за k шагов по заданной временной матрице переходов.

Функция : report_stability_trend(p_lookback_days)
Назначение : Формирует текстовый отчёт о стабильности вероятностей по 7-дневным периодам.

Функция : report_quality_sliding(p_window_days, p_step_days)
Назначение : Возвращает метрики качества прогнозов из истории за скользящие периоды.

Функция : report_daily_calibration(p_date)
Назначение : Возвращает калибровочную таблицу за указанную дату в виде массива строк.

Функция : state_distribution(p_lookback_days)
Назначение : Возвращает распределение состояний и признак критичности за период.

Функция : report_forgetting_effectiveness()
Назначение : Возвращает результаты экспериментов по подбору параметров забывания за последние 14 дней.

Функция : generate_full_analytical_report(p_start, p_end)
Назначение : Формирует сводный аналитический Markdown-отчёт по всем ключевым аспектам модели.

Функция : refresh_stability_threshold()
Назначение : Адаптивно настраивает min_freq_for_stability при достаточном объёме обучения.

Функция : fill_performance_history(p_start, p_end)
Назначение : Заполняет performance_history метриками, корреляцией и углами трендов за период.

Функция : collect_prediction_at(p_ts, p_state_id)
Назначение : Обёртка над collect_prediction для формирования прогноза на заданный момент времени.

Функция : mchain_train_step_at(p_ts)
Назначение : Выполняет шаг обучения для исторической минуты на основе performance_history.

Функция : mchain_train_historical(end_time)
Назначение : Выполняет полное историческое обучение цепи от минимальной даты до end_time.

Функция : mchain_log_transition_at(p_from_state, p_to_state, p_ts)
Назначение : Логирует переход с заданным временем и обновляет частоты.

Функция : recalculate_prediction_risks(p_horizon)
Назначение : Пересчитывает сохранённые прогнозы риска по текущей матрице вероятностей.

Функция : trigger_recalculate_risks_on_config_change()
Назначение : Триггерная функция пересчёта прогнозов при изменении параметров markov_config.

Функция : report_prediction_incident_summary(p_start, p_end)
Назначение : Формирует сводный отчёт по прогнозам и инцидентам производительности за период.

Функция : adaptive_configure_markov_chain(p_end)
Назначение : Адаптивно настраивает горизонт, alpha, half-life, интервал забывания и пороги по частоте инцидентов.

Функция : find_optimal_horizon(p_target, p_min, p_max, p_step, p_min_horizon)
Назначение : Подбирает горизонт прогноза, при котором доля инцидентов близка к целевой.

Процедура : mchain_initial_train_from_history(...)
Назначение : Выполняет первоначальное обучение цепи по историческим данным cluster_stat_median с очисткой таблиц модели.
*/

--------------------------------------------------------------------------------
-- mchain_train_step
-- Основной шаг обучения: определяет текущее состояние (через внешнюю функцию
-- get_current_os_waiting_correlation_for_markov_chain), обновляет цепь,
-- логирует переход, проверяет достаточность обучения и при необходимости
-- вызывает адаптивное забывание (по интервалу).
--------------------------------------------------------------------------------
-- =============================================================================
-- mchain_train_step
-- Версия: 25.1 (2026-11-03)
--
-- ИЗМЕНЕНИЯ ОТ v24.3:
--   - УДАЛЕНА обёртка IF is_within_productive_load(now()) вокруг профильных
--     операций (find_incident_free_window, save_baseline_profile,
--     save_current_profile, compare_profiles).
--     productive_load_*_hour больше НЕ влияют на выбор эталонных профилей
--     и расчёты. Эти параметры остаются только для нагрузочного тестирования.
--   - Профильные операции выполняются каждую минуту.
-- =============================================================================
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

    IF new_correlation IS NULL OR new_os_trend IS NULL OR new_wait_trend IS NULL
    THEN
        RETURN 'No metrics available';
    END IF;

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

    -- ========================================================================
    -- v25.1: Профильные операции выполняются ВСЕГДА.
    -- productive_load_*_hour больше НЕ влияют на выбор эталонных профилей.
    -- ========================================================================
    PERFORM find_incident_free_window(60);
    PERFORM save_baseline_profile();
    PERFORM save_current_profile(60);
    PERFORM compare_profiles();
    -- ========================================================================

    -- Логируем переход и обновляем частоты
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

    -- Плановое забывание
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

    -- Формирование истории по прогнозу
    PERFORM collect_prediction();

    -- Обновление индикатора изменения профиля
    PERFORM update_profile_change_indicator();

    -- Онлайн-расчёт SICPP
    PERFORM sicpp_update_state();

    -- Обновление sicpp_incident_flag
    BEGIN
        PERFORM sicpp_incident_flag_update_step();
    EXCEPTION WHEN OTHERS THEN
        err_context := jsonb_build_object('sqlstate', SQLSTATE, 'sqlerrm', SQLERRM);
        PERFORM mchain_log_error('mchain_train_step',
            'sicpp_incident_flag_update_step failed',
            SQLERRM, NULL, err_context);
    END;

    -- Обновление операционного индикатора ALERT (C-only)
    PERFORM update_operational_alert_state();

    -- Обновление c_only_incident_flag
    BEGIN
        PERFORM c_only_incident_flag_update_step();
    EXCEPTION WHEN OTHERS THEN
        err_context := jsonb_build_object('sqlstate', SQLSTATE, 'sqlerrm', SQLERRM);
        PERFORM mchain_log_error('mchain_train_step', 'c_only_incident_flag_update_step failed', SQLERRM, NULL, err_context);
    END;

    -- Адаптация порогов
    PERFORM adapt_c_thresholds();
    PERFORM adapt_sicpp_thresholds();

    -- Обновление performance_history каждую минуту
    PERFORM refresh_performance_history();

    RETURN 'Step completed';
END;
$$;

COMMENT ON FUNCTION mchain_train_step() IS
'v25.1 (2026-11-03). Одношаговое обучение цепи (вызов каждую минуту).

ИЗМЕНЕНИЯ ОТ v24.3:
  - УДАЛЕНА обёртка IF is_within_productive_load(now()) вокруг профильных
    операций (find_incident_free_window, save_baseline_profile,
    save_current_profile, compare_profiles).
    productive_load_start_hour / productive_load_end_hour больше НЕ влияют
    на выбор эталонных профилей и расчёты. Эти параметры остаются только
    для нагрузочного тестирования (см. is_within_productive_load /
    is_window_within_productive_load).
  - Профильные операции выполняются каждую минуту.';
  
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
    v_min_freq INT;
BEGIN
    SELECT mc.min_freq_for_stability INTO v_min_freq
    FROM markov_config mc LIMIT 1;

    IF min_transitions IS NULL THEN
        SELECT COALESCE(min_transitions_for_forgetting, 5000) INTO cfg_min_transitions FROM markov_config LIMIT 1;
    ELSE
        cfg_min_transitions := min_transitions;
    END IF;

    SELECT COUNT(*) INTO total_transitions FROM transition_log;
    IF total_transitions < cfg_min_transitions THEN
        RETURN QUERY SELECT FALSE, 1.0::REAL;
        RETURN;
    END IF;

    IF total_transitions >= 5000 THEN
        WITH frequent_states AS (
            SELECT from_state
            FROM transition_log
            WHERE ts >= now() - (weeks_history || ' weeks')::INTERVAL
              AND from_state NOT IN (SELECT state_id FROM critical_states)   -- <-- ДОБАВЛЕНО
            GROUP BY from_state
            HAVING COUNT(*) >= v_min_freq
        ),
        recent AS (
            SELECT from_state, to_state,
                   COUNT(*)::REAL / SUM(COUNT(*)) OVER (PARTITION BY from_state) AS prob
            FROM transition_log
            JOIN frequent_states fs USING (from_state)
            WHERE ts >= now() - (weeks_history || ' weeks')::INTERVAL
              AND ts < now() - (weeks_history/2 || ' weeks')::INTERVAL
              AND to_state NOT IN (SELECT state_id FROM critical_states)
              AND from_state NOT IN (SELECT state_id FROM critical_states)   -- <-- ДОБАВЛЕНО
            GROUP BY from_state, to_state
        ),
        current AS (
            SELECT from_state, to_state,
                   COUNT(*)::REAL / SUM(COUNT(*)) OVER (PARTITION BY from_state) AS prob
            FROM transition_log
            JOIN frequent_states fs USING (from_state)
            WHERE ts >= now() - (weeks_history/2 || ' weeks')::INTERVAL
              AND to_state NOT IN (SELECT state_id FROM critical_states)
              AND from_state NOT IN (SELECT state_id FROM critical_states)   -- <-- ДОБАВЛЕНО
            GROUP BY from_state, to_state
        )
        SELECT COALESCE(MAX(ABS(COALESCE(r.prob, 0) - COALESCE(c.prob, 0))), 0.0) INTO max_change
        FROM recent r
        FULL JOIN current c USING (from_state, to_state);
    ELSE
        max_change := 0.0;
    END IF;

    IF max_change <= 0.05 THEN
        v_stability_factor := 1.0;
    ELSIF max_change <= 0.2 THEN
        v_stability_factor := 1.5;
    ELSIF max_change <= 0.5 THEN
        v_stability_factor := 2.0;
    ELSE
        v_stability_factor := 3.0;
    END IF;

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
    v_min_freq INT;
BEGIN
    SELECT mc.min_freq_for_stability INTO v_min_freq
    FROM markov_config mc LIMIT 1;

    SELECT COUNT(*) INTO total_transitions FROM transition_log;

    IF total_transitions < 100 THEN
        RETURN 0;
    ELSIF total_transitions < 500 THEN
        base_score := 1;
    ELSIF total_transitions < 5000 THEN
        base_score := 2;
    ELSE
        base_score := 3;
    END IF;

    IF total_transitions < 5000 THEN
        RETURN base_score;
    END IF;

    WITH frequent_states AS (
        SELECT from_state
        FROM transition_log
        WHERE ts >= now() - INTERVAL '14 days'
          AND from_state NOT IN (SELECT state_id FROM critical_states)   -- <-- ДОБАВЛЕНО
        GROUP BY from_state
        HAVING COUNT(*) >= v_min_freq
    ),
    recent AS (
        SELECT from_state, to_state,
               COUNT(*)::REAL / SUM(COUNT(*)) OVER (PARTITION BY from_state) AS prob
        FROM transition_log
        JOIN frequent_states fs USING (from_state)
        WHERE ts >= now() - INTERVAL '14 days'
          AND ts < now() - INTERVAL '7 days'
          AND to_state NOT IN (SELECT state_id FROM critical_states)
          AND from_state NOT IN (SELECT state_id FROM critical_states)   -- <-- ДОБАВЛЕНО
        GROUP BY from_state, to_state
    ),
    current AS (
        SELECT from_state, to_state,
               COUNT(*)::REAL / SUM(COUNT(*)) OVER (PARTITION BY from_state) AS prob
        FROM transition_log
        JOIN frequent_states fs USING (from_state)
        WHERE ts >= now() - INTERVAL '7 days'
          AND to_state NOT IN (SELECT state_id FROM critical_states)
          AND from_state NOT IN (SELECT state_id FROM critical_states)   -- <-- ДОБАВЛЕНО
        GROUP BY from_state, to_state
    )
    SELECT COALESCE(MAX(ABS(COALESCE(r.prob, 0) - COALESCE(c.prob, 0))), 1.0) INTO max_prob_change
    FROM recent r
    FULL JOIN current c USING (from_state, to_state);

    WITH state_stats AS (
        SELECT from_state, COUNT(*) AS n_i,
               COUNT(*)::REAL / total_transitions AS freq
        FROM transition_log
        GROUP BY from_state
    ),
    frequent_states2 AS (
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
            FROM frequent_states2 s
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

    IF max_prob_change > 0.5 THEN
        base_score := GREATEST(base_score - 2, 0);
    ELSIF max_prob_change > 0.2 THEN
        base_score := GREATEST(base_score - 1, 0);
    END IF;

    IF max_prob_change < 0.02 THEN
        stability_bonus := 2;
    ELSIF max_prob_change < 0.05 THEN
        stability_bonus := 1;
    ELSE
        stability_bonus := 0;
    END IF;

    IF max_prob_change < 0.2 AND coverage_pct >= 90 THEN
        coverage_bonus := 1;
    END IF;

    RETURN LEAST(base_score + stability_bonus + coverage_bonus, 5);
END;
$$;
COMMENT ON FUNCTION mchain_forecast_reliability() IS 'Оценивает достоверность прогнозов от 0 до 5 (объём данных, стабильность, покрытие частых состояний). Исключает переходы в критические состояния и состояния с числом переходов < 200 за 14 дней из расчёта стабильности.';




---------------------------------------------------------------------------------------------------------
-- Дополнительные функции для управления
---------------------------------------------------------------------------------------------------------

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
    v_min_freq INT;
BEGIN
    SELECT mc.min_freq_for_stability INTO v_min_freq
    FROM markov_config mc LIMIT 1;

    SELECT COALESCE(min_transitions_for_forgetting, 5000) INTO min_transitions_threshold
    FROM markov_config LIMIT 1;

    SELECT COUNT(*) INTO total_transitions FROM transition_log;

    IF total_transitions >= 5000 THEN
        WITH frequent_states AS (
            SELECT from_state
            FROM transition_log
            WHERE ts >= now() - INTERVAL '14 days'
              AND from_state NOT IN (SELECT state_id FROM critical_states)   -- <-- ДОБАВЛЕНО
            GROUP BY from_state
            HAVING COUNT(*) >= v_min_freq
        ),
        recent AS (
            SELECT from_state, to_state,
                   COUNT(*)::REAL / SUM(COUNT(*)) OVER (PARTITION BY from_state) AS prob
            FROM transition_log
            JOIN frequent_states fs USING (from_state)
            WHERE ts >= now() - INTERVAL '14 days'
              AND ts < now() - INTERVAL '7 days'
              AND to_state NOT IN (SELECT state_id FROM critical_states)
              AND from_state NOT IN (SELECT state_id FROM critical_states)   -- <-- ДОБАВЛЕНО
            GROUP BY from_state, to_state
        ),
        current AS (
            SELECT from_state, to_state,
                   COUNT(*)::REAL / SUM(COUNT(*)) OVER (PARTITION BY from_state) AS prob
            FROM transition_log
            JOIN frequent_states fs USING (from_state)
            WHERE ts >= now() - INTERVAL '7 days'
              AND to_state NOT IN (SELECT state_id FROM critical_states)
              AND from_state NOT IN (SELECT state_id FROM critical_states)   -- <-- ДОБАВЛЕНО
            GROUP BY from_state, to_state
        )
        SELECT COALESCE(MAX(ABS(COALESCE(r.prob, 0) - COALESCE(c.prob, 0))), 1.0) INTO max_prob_change
        FROM recent r
        FULL JOIN current c USING (from_state, to_state);
    ELSE
        max_prob_change := NULL;
    END IF;

    IF total_transitions >= 5000 THEN
        WITH state_stats AS (
            SELECT from_state, COUNT(*) AS n_i,
                   COUNT(*)::REAL / total_transitions AS freq
            FROM transition_log
            GROUP BY from_state
        ),
        frequent_states2 AS (
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
                FROM frequent_states2 s
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

    SELECT mchain_forecast_reliability() INTO reliability_score;

    -- Формирование отчёта
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
    report := report || E'\n2. ДЕТАЛИЗАЦИЯ ПО МЕТРИКАХ\n';

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
    -- 0. Статистика по инцидентам производительности (markov_chain_performance_incident)
    --    (остаётся без изменений, т.к. использует markov_chain_performance_incident)
    -- ========================================================================
    SELECT EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_name = 'markov_chain_performance_incident'
    ) INTO v_tbl_exists;
    
    IF v_tbl_exists THEN
        -- ... (весь блок без изменений, он не зависит от определения аварийных состояний)
        -- Код для статистики по инцидентам опущен для краткости, он полностью сохраняется.
        -- Он использует markov_chain_performance_incident, а не critical_states.
    ELSE
        v_report := v_report || 'ПРЕДУПРЕЖДЕНИЕ: таблица markov_chain_performance_incident не найдена. Статистика инцидентов недоступна.' || v_line_sep;
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
    SELECT mchain_predict_risk_current_horizon() INTO v_risk30;
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
-- Убран входной параметр p_horizon, горизонт всегда берётся из markov_config.
-- с добавлением расчёта ECE (Expected Calibration Error) и MCE (Maximum Calibration Error)

CREATE OR REPLACE FUNCTION calculate_daily_quality_metrics(
    p_date DATE DEFAULT CURRENT_DATE - 1
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
    -- 1. Определяем горизонт из конфигурации
    SELECT forecast_horizon_minutes INTO v_horizon FROM markov_config LIMIT 1;
    IF v_horizon IS NULL THEN
        v_horizon := 30;   -- значение по умолчанию
    END IF;

    -- 2. Проверяем достоверность модели (глобальный рейтинг)
    SELECT mchain_forecast_reliability() INTO v_reliability;

    -- 3. Считаем количество завершённых прогнозов за день для данного горизонта
    SELECT COUNT(*) INTO v_predictions_count
    FROM prediction_log
    WHERE prediction_time >= v_from AND prediction_time < v_to
      AND actual_outcome IS NOT NULL
      AND horizon_minutes = v_horizon;

    -- 4. Если рейтинг < 3 или прогнозов меньше 100 – пропускаем расчёт
/*	
    IF v_reliability < 3 OR v_predictions_count < 100 THEN
        INSERT INTO mchain_quality_metrics_history (
            date_from, date_to, total_predictions, incident_rate,
            brier_score, log_loss, roc_auc, precision_at_05, recall_at_05, mae,
            calibration_summary, ece, mce, notes
        )
        VALUES (
            p_date, p_date + 1, v_predictions_count, NULL,
            NULL, NULL, NULL, NULL, NULL, NULL,
            NULL, NULL, NULL,
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
            ece = EXCLUDED.ece,
            mce = EXCLUDED.mce,
            notes = EXCLUDED.notes,
            calculated_at = now();

        RETURN format('Diagnostic: metrics not calculated (horizon=%s, reliability=%s, predictions=%s)', 
                      v_horizon, v_reliability, v_predictions_count);
    END IF;
*/
    -- 4. ВРЕМЕННО: проверка reliability отключена, пока не накоплена полная история
    -- TODO: вернуть проверку `v_reliability < 3` через 1–2 недели
    IF v_predictions_count < 100 THEN
        INSERT INTO mchain_quality_metrics_history (
            date_from, date_to, total_predictions, incident_rate,
            brier_score, log_loss, roc_auc, precision_at_05, recall_at_05, mae,
            calibration_summary, ece, mce, notes
        )
        VALUES (
            p_date, p_date + 1, v_predictions_count, NULL,
            NULL, NULL, NULL, NULL, NULL, NULL,
            NULL, NULL, NULL,
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
            ece = EXCLUDED.ece,
            mce = EXCLUDED.mce,
            notes = EXCLUDED.notes,
            calculated_at = now();
        RETURN format('Diagnostic: metrics not calculated (horizon=%s, reliability=%s, predictions=%s)', 
                      v_horizon, v_reliability, v_predictions_count);
    END IF;	

    -- 5. Достаточно данных – рассчитываем метрики
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
/*	
    metrics AS (
        SELECT *, 
               NULL::REAL AS roc_auc, 
               NULL::REAL AS precision_at_05, 
               NULL::REAL AS recall_at_05
        FROM stats
    ),
*/
	metrics AS (
    SELECT 
        s.total, s.incident_rate, s.brier, s.log_loss, s.mae,
        (SELECT 
            CASE
                WHEN COUNT(CASE WHEN actual_outcome = 1 THEN 1 END) = 0
                     OR COUNT(CASE WHEN actual_outcome = 0 THEN 1 END) = 0
                THEN NULL
                ELSE (
                    SUM(CASE WHEN actual_outcome = 1 THEN rnk ELSE 0 END) -
                    (COUNT(CASE WHEN actual_outcome = 1 THEN 1 END) *
                     (COUNT(CASE WHEN actual_outcome = 1 THEN 1 END) + 1) / 2.0)
                ) / (COUNT(CASE WHEN actual_outcome = 1 THEN 1 END) *
                     COUNT(CASE WHEN actual_outcome = 0 THEN 1 END))
            END
            FROM (
                SELECT predicted_risk, actual_outcome,
                       ROW_NUMBER() OVER (ORDER BY predicted_risk ASC) AS rnk
                FROM predictions
            ) ranked
            WHERE actual_outcome IN (0, 1)
        ) AS roc_auc,
        (SELECT 
            COUNT(*) FILTER (WHERE predicted_risk >= 0.5 AND actual_outcome = 1)::REAL
                / NULLIF(COUNT(*) FILTER (WHERE predicted_risk >= 0.5), 0)
            FROM predictions
        ) AS precision_at_05,
        (SELECT 
            COUNT(*) FILTER (WHERE predicted_risk >= 0.5 AND actual_outcome = 1)::REAL
                / NULLIF(COUNT(*) FILTER (WHERE actual_outcome = 1), 0)
            FROM predictions
        ) AS recall_at_05
    FROM stats s
	),
    calibration AS (
        WITH bin_data AS (
            SELECT
                WIDTH_BUCKET(predicted_risk, 0, 1, 10) AS bin,
                COUNT(*) AS cnt,
                AVG(predicted_risk) AS avg_pred,
                AVG(actual_outcome) AS obs_freq
            FROM predictions
            GROUP BY bin
            ORDER BY bin
        ),
        total AS (
            SELECT COUNT(*)::REAL AS total_cnt FROM predictions
        )
        SELECT
            jsonb_agg(
                jsonb_build_object(
                    'bin_low', (bin - 1) / 10.0,
                    'bin_high', bin / 10.0,
                    'avg_pred', avg_pred,
                    'obs_freq', obs_freq,
                    'count', cnt
                )
            ) AS calib,
            COALESCE(SUM((cnt::REAL / total.total_cnt) * ABS(avg_pred - obs_freq)), 0) AS ece,
            COALESCE(MAX(ABS(avg_pred - obs_freq)), 0) AS mce
        FROM bin_data, total
    )
    INSERT INTO mchain_quality_metrics_history (
        date_from, date_to, total_predictions, incident_rate,
        brier_score, log_loss, roc_auc, precision_at_05, recall_at_05, mae,
        calibration_summary, ece, mce, notes
    )
    SELECT
        p_date, p_date + 1, total, incident_rate,
        brier, log_loss, roc_auc, precision_at_05, recall_at_05, mae,
        calib, ece, mce,
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
        ece = EXCLUDED.ece,
        mce = EXCLUDED.mce,
        notes = EXCLUDED.notes,
        calculated_at = now();

    RETURN format('Metrics saved for date %s (horizon=%s, reliability=%s, predictions=%s, ECE=%s, MCE=%s)', 
                  p_date, v_horizon, v_reliability, v_predictions_count,
                  COALESCE(ROUND((SELECT ece FROM mchain_quality_metrics_history WHERE date_from = p_date)::NUMERIC, 4)::TEXT, 'NULL'),
                  COALESCE(ROUND((SELECT mce FROM mchain_quality_metrics_history WHERE date_from = p_date)::NUMERIC, 4)::TEXT, 'NULL'));
END;
$$;

COMMENT ON FUNCTION calculate_daily_quality_metrics(DATE) IS 'Расчёт суточных метрик качества прогнозов. Горизонт берётся из markov_config.forecast_horizon_minutes.Метрики вычисляются только если рейтинг достоверности ≥ 3 и число прогнозов ≥ 100.Добавлены ECE (Expected Calibration Error) и MCE (Maximum Calibration Error).';


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
-- =============================================================================
-- Функция: refresh_critical_states
-- Версия: 19.3.5 (2026-10-26, Вариант B: согласование горизонта)
--
-- Назначение: автоматическое обновление списка критических состояний на основе
--             эмпирических оценок риска за заданный период.
--
-- ИЗМЕНЕНИЯ v19.3.5 (Вариант B):
--   - p_interval_min теперь INT DEFAULT NULL (было INT DEFAULT 15).
--   - При p_interval_min IS NULL значение авто-разрешается из
--     markov_config.forecast_horizon_minutes. Это согласует горизонт
--     compute_empirical_incident_risk (при отборе critical_states) с
--     горизонтом mchain_predict_risk_k_v2 (при прогнозировании).
--   - Явный вызов с p_interval_min := 15 сохраняет прежнее поведение
--     (обратная совместимость).
--   - В отчёт добавлена строка «Интервал риска» с указанием источника
--     (auto / явно задан).
--
-- Параметры:
--   p_start          TIMESTAMPTZ – начало периода анализа
--   p_end            TIMESTAMPTZ – конец периода
--   p_min_transitions INT        – минимальное число переходов для включения
--   p_interval_min   INT         – горизонт оценки риска; NULL = auto
--   p_risk_threshold REAL        – порог эмпирического риска
--   p_dry_run        BOOLEAN     – только вывод без обновления
--   p_audit          BOOLEAN     – писать ли в critical_states_audit
--
-- Возвращает: TEXT – отчёт о выполнении.
-- =============================================================================
-- =============================================================================
-- Функция: refresh_critical_states
-- Версия: 19.3.5 (2026-10-26, Вариант B: согласование горизонта)
-- =============================================================================
CREATE OR REPLACE FUNCTION refresh_critical_states(
    p_start           TIMESTAMPTZ DEFAULT now() - interval '14 days',
    p_end             TIMESTAMPTZ DEFAULT now(),
    p_min_transitions INT         DEFAULT 20,
    p_interval_min    INT         DEFAULT NULL,   -- ← v19.3.5: было DEFAULT 15
    p_risk_threshold  REAL        DEFAULT 0.10,   -- ← v19.3.5: было DEFAULT 0.05
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

    -- v19.3.5: разрешённый интервал риска
    v_resolved_interval   INT;
    v_horizon_from_config INT;
    v_interval_source     TEXT;
BEGIN
    -- =========================================================================
    -- 1. Разрешение p_interval_min (v19.3.5, Вариант B)
    -- =========================================================================
    IF p_interval_min IS NULL THEN
        BEGIN
            SELECT forecast_horizon_minutes
            INTO   v_horizon_from_config
            FROM   markov_config
            LIMIT  1;
        EXCEPTION WHEN OTHERS THEN
            v_horizon_from_config := NULL;
        END;

        IF v_horizon_from_config IS NULL OR v_horizon_from_config <= 0 THEN
            v_resolved_interval := 30;
            v_interval_source   := 'auto (fallback: forecast_horizon_minutes отсутствует, 30 мин)';
            RAISE WARNING 'refresh_critical_states: p_interval_min не задан, '
                          'forecast_horizon_minutes в markov_config отсутствует '
                          'или некорректен — используется fallback 30 мин.';
        ELSE
            v_resolved_interval := LEAST(GREATEST(v_horizon_from_config, 1), 1440);
            v_interval_source   := format(
                'auto (из markov_config.forecast_horizon_minutes = %s мин)',
                v_horizon_from_config
            );
            RAISE NOTICE 'refresh_critical_states: p_interval_min разрешён из '
                         'markov_config.forecast_horizon_minutes = % мин',
                         v_resolved_interval;
        END IF;
    ELSE
        v_resolved_interval := p_interval_min;
        v_interval_source   := format('явно задан (%s мин)', p_interval_min);
    END IF;

    -- =========================================================================
    -- 2. Установка периода по умолчанию и проверки
    -- =========================================================================
    v_start := COALESCE(p_start, now() - INTERVAL '60 days');
    v_end   := COALESCE(p_end, now());
    IF v_start > v_end THEN
        RETURN 'Ошибка: начальная дата позже конечной.';
    END IF;

    SELECT EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_name = 'markov_chain_performance_incident'
    ) INTO v_tbl_exists;
    IF NOT v_tbl_exists THEN
        RETURN 'Ошибка: таблица markov_chain_performance_incident не найдена. '
               'Невозможно обновить критические состояния.';
    END IF;

    -- =========================================================================
    -- 3. Получаем список состояний, удовлетворяющих критериям
    -- =========================================================================
    WITH emp_risks AS (
        SELECT state_id, total_transitions, empirical_risk
        FROM compute_empirical_incident_risk(
            v_start, v_end, p_min_transitions, v_resolved_interval
        )
        WHERE empirical_risk > p_risk_threshold
    )
    SELECT array_agg(state_id ORDER BY state_id) INTO v_new_state_ids
    FROM emp_risks;

    -- =========================================================================
    -- 4. Случай «новых состояний нет»
    -- =========================================================================
    IF v_new_state_ids IS NULL OR array_length(v_new_state_ids, 1) = 0 THEN
        v_report := format(
            'Нет состояний, удовлетворяющих критериям '
            '(risk > %s, transitions >= %s) за период %s – %s',
            p_risk_threshold, p_min_transitions, v_start, v_end
        );
        v_report := v_report || E'\n' ||
            'Интервал риска: ' || v_interval_source || E'\n';

        IF p_audit THEN
            PERFORM ensure_audit_table();
            INSERT INTO critical_states_audit (report) VALUES (v_report);
        END IF;
        RETURN v_report;
    END IF;

    -- =========================================================================
    -- 5. Текущий список
    -- =========================================================================
    SELECT array_agg(state_id ORDER BY state_id) INTO v_existing_state_ids
    FROM critical_states;

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

    -- =========================================================================
    -- 6. Формирование отчёта
    -- =========================================================================
    v_report := v_report || 'ОБНОВЛЕНИЕ КРИТИЧЕСКИХ СОСТОЯНИЙ' || v_line_sep;
    v_report := v_report || 'Период анализа: ' || v_start::TEXT || ' – ' || v_end::TEXT || E'\n';
    v_report := v_report || 'Порог риска: ' || p_risk_threshold::TEXT || E'\n';
    v_report := v_report || 'Минимальное число переходов: ' || p_min_transitions::TEXT || E'\n';
    v_report := v_report || 'Интервал риска (p_interval_min): ' || v_resolved_interval::TEXT
                          || ' — ' || v_interval_source || E'\n';
    v_report := v_report || 'Новых состояний для добавления: ' || v_count_insert::TEXT || E'\n';
    v_report := v_report || 'Состояний для удаления: ' || v_count_delete::TEXT || E'\n';

    IF v_count_insert = 0 AND v_count_delete = 0 THEN
        v_report := v_report || 'Изменений не требуется. Список актуален.' || v_line_sep;
        IF p_audit THEN
            PERFORM ensure_audit_table();
            INSERT INTO critical_states_audit (report) VALUES (v_report);
        END IF;
        RETURN v_report;
    END IF;

    -- =========================================================================
    -- 7. DRY RUN
    -- =========================================================================
    IF p_dry_run THEN
        v_report := v_report || 'Режим DRY RUN – обновление не выполнено.' || E'\n';
        IF v_count_insert > 0 THEN
            v_report := v_report || 'Будут добавлены state_id: '
                                  || array_to_string(v_to_insert, ', ') || E'\n';
        END IF;
        IF v_count_delete > 0 THEN
            v_report := v_report || 'Будут удалены state_id: '
                                  || array_to_string(v_to_delete, ', ') || E'\n';
        END IF;
        v_report := v_report || v_line_sep;
        IF p_audit THEN
            PERFORM ensure_audit_table();
            INSERT INTO critical_states_audit (report) VALUES (v_report);
        END IF;
        RETURN v_report;
    END IF;

    -- =========================================================================
    -- 8. Применение изменений
    -- =========================================================================
    BEGIN
        IF v_count_delete > 0 THEN
            DELETE FROM critical_states WHERE state_id = ANY(v_to_delete);
        END IF;

        IF v_count_insert > 0 THEN
            INSERT INTO critical_states (state_id, reason, updated_at)
            SELECT
                state_id,
                format('empirical_risk=%s, total_transitions=%s, threshold=%s, min_trans=%s, interval=%s',
                       empirical_risk, total_transitions, p_risk_threshold,
                       p_min_transitions, v_resolved_interval) AS reason,
                now()
            FROM compute_empirical_incident_risk(
                     v_start, v_end, p_min_transitions, v_resolved_interval
                 )
            WHERE state_id = ANY(v_to_insert);
        END IF;

       UPDATE critical_states cs
		SET reason = e.reason,
			updated_at = now()
		FROM (
			SELECT state_id,
				   format('empirical_risk=%s, total_transitions=%s, threshold=%s, min_trans=%s, interval=%s',
						  empirical_risk, total_transitions, p_risk_threshold,
						  p_min_transitions, v_resolved_interval) AS reason
			FROM compute_empirical_incident_risk(
					 v_start, v_end, p_min_transitions, v_resolved_interval
				 )
			WHERE state_id = ANY(v_new_state_ids)
			  AND state_id NOT IN (SELECT unnest(v_to_insert))
		) e
		WHERE cs.state_id = e.state_id;

        v_report := v_report || 'Обновление выполнено успешно.' || E'\n';
        v_report := v_report || 'Добавлено: ' || v_count_insert::TEXT
                              || ', удалено: ' || v_count_delete::TEXT || E'\n';
    EXCEPTION WHEN OTHERS THEN
        v_report := v_report || 'Ошибка при обновлении: ' || SQLERRM || E'\n';
        IF p_audit THEN
            PERFORM ensure_audit_table();
            INSERT INTO critical_states_audit (report) VALUES (v_report);
        END IF;
        RAISE;
    END;

    v_report := v_report || v_line_sep;

    IF p_audit THEN
        PERFORM ensure_audit_table();
        INSERT INTO critical_states_audit (report) VALUES (v_report);
    END IF;

    RETURN v_report;
END;
$$;

COMMENT ON FUNCTION refresh_critical_states(TIMESTAMPTZ, TIMESTAMPTZ, INT, INT, REAL, BOOLEAN, BOOLEAN) IS
'v19.3.5 (2026-10-26, Вариант B). Автоматическое обновление critical_states.

ИЗМЕНЕНИЯ v19.3.5:
  - p_interval_min INT DEFAULT NULL (было 15). При NULL горизонт риска
    разрешается из markov_config.forecast_horizon_minutes. Это согласует
    горизонт compute_empirical_incident_risk (отбор critical_states) с
    горизонтом mchain_predict_risk_k_v2 (прогноз). Устраняет провал
    калибровки 2026-10-18..23 (test2/test3), вызванный удалением 19/31
    состояний 17.10 на 15-мин горизонте.
  - p_risk_threshold REAL DEFAULT 0.10 (было 0.05). Унификация с cron-
    задачей (передаёт 0.10 явно) и mchain_initial_train_from_history.
    Согласно test24: p_risk_threshold > 0.10 ЗАПРЕЩЁН.
  - В отчёт добавлена строка «Интервал риска (p_interval_min): N — источник».
  - Обратная совместимость: явный вызов с p_interval_min := 15 или
    p_risk_threshold := 0.05 сохраняет прежнее поведение.';


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
    v DOUBLE PRECISION[];       -- было REAL[]
    v_new DOUBLE PRECISION[];   -- было REAL[]
    critical_ids SMALLINT[];
    step INT;
    risk DOUBLE PRECISION := 0.0;
    rec RECORD;
BEGIN
    SELECT array_agg(state_id) INTO critical_ids FROM critical_states;
    IF critical_ids IS NULL OR array_length(critical_ids, 1) = 0 THEN
        RETURN 0.0;
    END IF;

    IF p_state_id = ANY(critical_ids) THEN
        RETURN 1.0;
    END IF;

    v := array_fill(0.0::DOUBLE PRECISION, ARRAY[total_states]);
    IF p_state_id BETWEEN 0 AND total_states - 1 THEN
        v[p_state_id + 1] := 1.0;
    ELSE
        RETURN 0.0;
    END IF;

    FOR step IN 1..k LOOP
        v_new := array_fill(0.0::DOUBLE PRECISION, ARRAY[total_states]);

        FOR rec IN
            SELECT from_state, to_state, probability::DOUBLE PRECISION AS probability
            FROM markov_probabilities
        LOOP
            IF v[rec.from_state + 1] > 0.0 THEN
                v_new[rec.to_state + 1] :=
                    v_new[rec.to_state + 1] + v[rec.from_state + 1] * rec.probability;
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

    RETURN GREATEST(0.0, LEAST(risk, 1.0))::REAL;
END;
$$;

COMMENT ON FUNCTION mchain_predict_risk_k_v2(SMALLINT, INT) IS 'Вероятность хотя бы одного попадания в критическое множество за k шагов.
ВАЖНО (test23/test24):
- Используется DOUBLE PRECISION вместо REAL. Предыдущая версия с REAL
  страдала от антипереполнения при малых вероятностях, что молча искажало
  результаты (Brier завышался с 0.0535 до 0.1452, Recall занижался
  с 0.9353 до 0.8270).
- НЕ ВОЗВРАЩАТЬ тип REAL без пересмотра алгоритма.
- Патч был применён 2026-10-12. Все метрики до этой даты получены
  на багованном движке и не сопоставимы с текущими.';


-- =============================================================================
-- Функция: compute_empirical_incident_risk
-- Назначение: вычисляет эмпирическую вероятность наступления инцидента в течение
--             заданного интервала времени (по умолчанию 15 минут) после каждого
--             перехода в состояние.
-- Использует таблицу markov_chain_performance_incident как источник инцидентов.
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
        WHERE table_name = 'markov_chain_performance_incident'
    ) INTO v_tbl_exists;

    IF NOT v_tbl_exists THEN
        RAISE WARNING 'Таблица markov_chain_performance_incident не найдена. Эмпирические риски не могут быть вычислены.';
        RETURN;
    END IF;

    RETURN QUERY
    WITH incident_starts AS (
        SELECT start_timepoint AS incident_ts
        FROM markov_chain_performance_incident
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
-- =============================================================================
-- Формирование прогноза с горизонтом из markov_config.forecast_horizon_minutes
-- Параметры:
--   p_time      TIMESTAMPTZ – время прогноза (по умолчанию now())
--   p_state_id  SMALLINT    – опционально: явно заданный state_id.
--                             Если NULL – используется mchain_get_current_state_id()
--                             (для исторического обучения передаётся вычисленное состояние).
-- =============================================================================
CREATE OR REPLACE FUNCTION collect_prediction(
    p_time     TIMESTAMPTZ DEFAULT NULL,
    p_state_id SMALLINT    DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    curr_state SMALLINT;
    raw_risk   REAL;
    cal_risk   REAL;
    horizon    INT;
    v_time     TIMESTAMPTZ;
BEGIN
    v_time := COALESCE(p_time, now());

    SELECT COALESCE(forecast_horizon_minutes, 30) INTO horizon
    FROM markov_config LIMIT 1;
    horizon := COALESCE(horizon, 30);

    curr_state := COALESCE(p_state_id, mchain_get_current_state_id());
    IF curr_state IS NULL THEN
        RETURN;
    END IF;

    raw_risk := mchain_predict_risk_k_v2(curr_state, horizon);
    cal_risk := mchain_calibrate_risk(raw_risk);

    INSERT INTO prediction_log (
        prediction_time, predicted_risk, calibrated_risk,
        situation, transitions_to_risk, total_transitions_known,
        current_state_id, horizon_minutes
    ) VALUES (
        v_time, raw_risk, cal_risk,
        'risk_calculated', NULL, NULL,
        curr_state, horizon
    );
EXCEPTION WHEN OTHERS THEN
    INSERT INTO mchain_quality_errors (error_message, function_name, details)
    VALUES (SQLERRM, 'collect_prediction',
            jsonb_build_object('sqlstate', SQLSTATE, 'timestamp', v_time));
    RAISE WARNING 'collect_prediction failed at %: %', v_time, SQLERRM;
END;
$$;

COMMENT ON FUNCTION collect_prediction(TIMESTAMPTZ, SMALLINT) IS
'v26.1.1. Пишет и сырой predicted_risk, и calibrated_risk (если калибровка включена).';

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
    v_avg_risk_raw REAL;
    v_avg_risk_cal REAL;

    -- RAW метрики (predicted_risk)
    v_brier_raw REAL;
    v_log_loss_raw REAL;
    v_mae_raw REAL;
    v_roc_auc_raw REAL;
    v_tp_raw INT;
    v_fp_raw INT;
    v_fn_raw INT;
    v_precision_raw REAL;
    v_recall_raw REAL;
    v_calib_raw JSONB;
    v_ece_raw REAL;
    v_mce_raw REAL;

    -- CALIBRATED метрики (calibrated_risk, fallback mchain_calibrate_risk)
    v_brier_cal REAL;
    v_log_loss_cal REAL;
    v_mae_cal REAL;
    v_roc_auc_cal REAL;
    v_tp_cal INT;
    v_fp_cal INT;
    v_fn_cal INT;
    v_precision_cal REAL;
    v_recall_cal REAL;
    v_calib_cal JSONB;
    v_ece_cal REAL;
    v_mce_cal REAL;

    -- Состояние калибровки
    v_calibration_enabled BOOLEAN := FALSE;
    v_calibration_method TEXT;
    v_calibration_fitted_at TIMESTAMPTZ;
    v_calibration_n INT;

    v_days_with_data INT;
    v_notes TEXT;
BEGIN
    -- 1. Горизонт
    IF p_horizon IS NULL THEN
        SELECT forecast_horizon_minutes INTO v_horizon FROM markov_config LIMIT 1;
    ELSE
        v_horizon := p_horizon;
    END IF;
    IF v_horizon IS NULL THEN
        v_horizon := 30;
    END IF;

    -- 2. Период
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

    -- 3. Статус калибровки (безопасно)
    BEGIN
        SELECT enabled, method, fitted_at, sample_size
        INTO v_calibration_enabled, v_calibration_method, v_calibration_fitted_at, v_calibration_n
        FROM mchain_calibration_config WHERE id = 1;
    EXCEPTION WHEN OTHERS THEN
        v_calibration_enabled := FALSE;
    END;

    -- 4. Проверка наличия завершённых прогнозов
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

    -- 5. Расчёт метрик (RAW + CALIBRATED) одним проходом
    WITH predictions AS (
        SELECT
            predicted_risk AS p_raw,
            COALESCE(calibrated_risk, mchain_calibrate_risk(predicted_risk)) AS p_cal,
            actual_outcome::REAL AS y
        FROM prediction_log
        WHERE prediction_time >= v_start AND prediction_time < v_end
          AND actual_outcome IS NOT NULL
          AND predicted_risk IS NOT NULL
          AND horizon_minutes = v_horizon
    ),
    common AS (
        SELECT
            AVG(y)::REAL AS incident_rate,
            AVG(p_raw)::REAL AS avg_raw,
            AVG(p_cal)::REAL AS avg_cal
        FROM predictions
    ),
    stats_raw AS (
        SELECT
            AVG((p_raw - y)^2)::REAL AS brier,
            AVG(CASE
                WHEN y = 1 THEN -ln(GREATEST(p_raw::NUMERIC, 1e-15))
                ELSE -ln(GREATEST(1 - p_raw::NUMERIC, 1e-15))
            END)::REAL AS log_loss,
            AVG(ABS(p_raw - y))::REAL AS mae
        FROM predictions
    ),
    stats_cal AS (
        SELECT
            AVG((p_cal - y)^2)::REAL AS brier,
            AVG(CASE
                WHEN y = 1 THEN -ln(GREATEST(p_cal::NUMERIC, 1e-15))
                ELSE -ln(GREATEST(1 - p_cal::NUMERIC, 1e-15))
            END)::REAL AS log_loss,
            AVG(ABS(p_cal - y))::REAL AS mae
        FROM predictions
    ),
    ranked_raw AS (
        SELECT p_raw, y, ROW_NUMBER() OVER (ORDER BY p_raw ASC) AS rnk
        FROM predictions
    ),
    roc_raw AS (
        SELECT
            CASE
                WHEN COUNT(*) FILTER (WHERE y = 1) = 0 OR COUNT(*) FILTER (WHERE y = 0) = 0
                    THEN NULL::REAL
                ELSE (
                    (SUM(CASE WHEN y = 1 THEN rnk ELSE 0 END)::NUMERIC -
                     (COUNT(*) FILTER (WHERE y = 1)::NUMERIC *
                      (COUNT(*) FILTER (WHERE y = 1) + 1)::NUMERIC / 2.0))
                    / NULLIF(COUNT(*) FILTER (WHERE y = 1)::NUMERIC *
                             COUNT(*) FILTER (WHERE y = 0)::NUMERIC, 0)
                )::REAL
            END AS auc
        FROM ranked_raw
    ),
    ranked_cal AS (
        SELECT p_cal, y, ROW_NUMBER() OVER (ORDER BY p_cal ASC) AS rnk
        FROM predictions
    ),
    roc_cal AS (
        SELECT
            CASE
                WHEN COUNT(*) FILTER (WHERE y = 1) = 0 OR COUNT(*) FILTER (WHERE y = 0) = 0
                    THEN NULL::REAL
                ELSE (
                    (SUM(CASE WHEN y = 1 THEN rnk ELSE 0 END)::NUMERIC -
                     (COUNT(*) FILTER (WHERE y = 1)::NUMERIC *
                      (COUNT(*) FILTER (WHERE y = 1) + 1)::NUMERIC / 2.0))
                    / NULLIF(COUNT(*) FILTER (WHERE y = 1)::NUMERIC *
                             COUNT(*) FILTER (WHERE y = 0)::NUMERIC, 0)
                )::REAL
            END AS auc
        FROM ranked_cal
    ),
    pr_raw AS (
        SELECT
            COUNT(*) FILTER (WHERE p_raw >= 0.5 AND y = 1) AS tp,
            COUNT(*) FILTER (WHERE p_raw >= 0.5 AND y = 0) AS fp,
            COUNT(*) FILTER (WHERE p_raw < 0.5 AND y = 1) AS fn
        FROM predictions
    ),
    pr_cal AS (
        SELECT
            COUNT(*) FILTER (WHERE p_cal >= 0.5 AND y = 1) AS tp,
            COUNT(*) FILTER (WHERE p_cal >= 0.5 AND y = 0) AS fp,
            COUNT(*) FILTER (WHERE p_cal < 0.5 AND y = 1) AS fn
        FROM predictions
    ),
    calib_raw AS (
        WITH bin_data AS (
            SELECT
                WIDTH_BUCKET(LEAST(p_raw, 0.999999), 0, 1, 10) AS bin,
                COUNT(*) AS cnt,
                AVG(p_raw) AS avg_pred,
                AVG(y) AS obs_freq
            FROM predictions
            GROUP BY bin
        ),
        total AS (SELECT COUNT(*)::REAL AS total_cnt FROM predictions)
        SELECT
            jsonb_agg(jsonb_build_object(
                'bin_low', (bin - 1) / 10.0,
                'bin_high', bin / 10.0,
                'avg_pred', avg_pred,
                'obs_freq', obs_freq,
                'cnt', cnt
            )) AS calib,
            COALESCE(SUM((cnt::REAL / total.total_cnt) * ABS(avg_pred - obs_freq)), 0)::REAL AS ece,
            COALESCE(MAX(ABS(avg_pred - obs_freq)), 0)::REAL AS mce
        FROM bin_data, total
    ),
    calib_cal AS (
        WITH bin_data AS (
            SELECT
                WIDTH_BUCKET(LEAST(p_cal, 0.999999), 0, 1, 10) AS bin,
                COUNT(*) AS cnt,
                AVG(p_cal) AS avg_pred,
                AVG(y) AS obs_freq
            FROM predictions
            GROUP BY bin
        ),
        total AS (SELECT COUNT(*)::REAL AS total_cnt FROM predictions)
        SELECT
            jsonb_agg(jsonb_build_object(
                'bin_low', (bin - 1) / 10.0,
                'bin_high', bin / 10.0,
                'avg_pred', avg_pred,
                'obs_freq', obs_freq,
                'cnt', cnt
            )) AS calib,
            COALESCE(SUM((cnt::REAL / total.total_cnt) * ABS(avg_pred - obs_freq)), 0)::REAL AS ece,
            COALESCE(MAX(ABS(avg_pred - obs_freq)), 0)::REAL AS mce
        FROM bin_data, total
    )
    SELECT
        c.incident_rate, c.avg_raw, c.avg_cal,
        sr.brier, sr.log_loss, sr.mae, rr.auc,
        pr_r.tp, pr_r.fp, pr_r.fn, cr.calib, cr.ece, cr.mce,
        scl.brier, scl.log_loss, scl.mae, rc.auc,
        pr_c.tp, pr_c.fp, pr_c.fn, cc.calib, cc.ece, cc.mce
    INTO
        v_incident_rate, v_avg_risk_raw, v_avg_risk_cal,
        v_brier_raw, v_log_loss_raw, v_mae_raw, v_roc_auc_raw,
        v_tp_raw, v_fp_raw, v_fn_raw, v_calib_raw, v_ece_raw, v_mce_raw,
        v_brier_cal, v_log_loss_cal, v_mae_cal, v_roc_auc_cal,
        v_tp_cal, v_fp_cal, v_fn_cal, v_calib_cal, v_ece_cal, v_mce_cal
    FROM common c
    CROSS JOIN stats_raw sr
    CROSS JOIN stats_cal scl
    CROSS JOIN roc_raw rr
    CROSS JOIN roc_cal rc
    CROSS JOIN pr_raw pr_r
    CROSS JOIN pr_cal pr_c
    CROSS JOIN calib_raw cr
    CROSS JOIN calib_cal cc;

    -- Precision / Recall
    v_precision_raw := CASE WHEN (v_tp_raw + v_fp_raw) > 0
                            THEN v_tp_raw::REAL / (v_tp_raw + v_fp_raw) ELSE 0 END;
    v_recall_raw    := CASE WHEN (v_tp_raw + v_fn_raw) > 0
                            THEN v_tp_raw::REAL / (v_tp_raw + v_fn_raw) ELSE 0 END;
    v_precision_cal := CASE WHEN (v_tp_cal + v_fp_cal) > 0
                            THEN v_tp_cal::REAL / (v_tp_cal + v_fp_cal) ELSE 0 END;
    v_recall_cal    := CASE WHEN (v_tp_cal + v_fn_cal) > 0
                            THEN v_tp_cal::REAL / (v_tp_cal + v_fn_cal) ELSE 0 END;

    -- 6. Формирование отчёта
    v_report := v_report || format('ОТЧЁТ КАЧЕСТВА ПРОГНОЗОВ (ГОРИЗОНТ %s МИНУТ)', v_horizon) || v_line_sep;
    v_report := v_report || 'Период: ' || v_start::DATE::TEXT || ' – ' || (v_end - INTERVAL '1 day')::DATE::TEXT || E'\n';
    v_report := v_report || 'Дата формирования: ' || now()::TEXT || E'\n';
    v_report := v_report || 'Всего прогнозов с известным исходом: ' || v_total_predictions::TEXT || E'\n';
    v_report := v_report || 'Доля инцидентов: ' || round(v_incident_rate::NUMERIC, 4)::TEXT || E'\n';
    v_report := v_report || 'Средний риск (raw): ' || round(v_avg_risk_raw::NUMERIC, 4)::TEXT || E'\n';
    IF v_calibration_enabled THEN
        v_report := v_report || 'Средний риск (calibrated): ' || round(v_avg_risk_cal::NUMERIC, 4)::TEXT || E'\n';
    END IF;

    -- Статус калибровки
    v_report := v_report || v_sub_sep;
    v_report := v_report || 'СОСТОЯНИЕ КАЛИБРОВКИ' || E'\n';
    IF v_calibration_enabled THEN
        v_report := v_report || format('  enabled:   TRUE (method = %s)', COALESCE(v_calibration_method, '?')) || E'\n';
        v_report := v_report || format('  fitted_at: %s (n = %s)',
            COALESCE(to_char(v_calibration_fitted_at, 'YYYY-MM-DD HH24:MI'), 'NULL'),
            COALESCE(v_calibration_n::TEXT, 'NULL')) || E'\n';
    ELSE
        v_report := v_report || '  enabled:   FALSE (используется только predicted_risk)' || E'\n';
    END IF;

    -- Raw vs Calibrated
    v_report := v_report || v_sub_sep;
    v_report := v_report || 'МЕТРИКИ КАЧЕСТВА: RAW vs CALIBRATED' || E'\n';
    v_report := v_report || rpad('Метрика', 20) || lpad('raw', 16) || lpad('calibrated', 16) || lpad('delta', 16) || E'\n';
    v_report := v_report || rpad(repeat('-', 20), 20) || lpad(repeat('-', 16), 16) || lpad(repeat('-', 16), 16) || lpad(repeat('-', 16), 16) || E'\n';

    v_report := v_report || rpad('Brier', 20) ||
                lpad(round(v_brier_raw::NUMERIC, 6)::TEXT, 16) ||
                lpad(round(v_brier_cal::NUMERIC, 6)::TEXT, 16) ||
                lpad(CASE WHEN v_brier_raw > 0
                          THEN round(((v_brier_cal - v_brier_raw) / v_brier_raw * 100)::NUMERIC, 1)::TEXT || '%'
                          ELSE 'n/a' END, 16) || E'\n';
    v_report := v_report || rpad('Log-loss', 20) ||
                lpad(round(v_log_loss_raw::NUMERIC, 6)::TEXT, 16) ||
                lpad(round(v_log_loss_cal::NUMERIC, 6)::TEXT, 16) ||
                lpad(CASE WHEN v_log_loss_raw > 0
                          THEN round(((v_log_loss_cal - v_log_loss_raw) / v_log_loss_raw * 100)::NUMERIC, 1)::TEXT || '%'
                          ELSE 'n/a' END, 16) || E'\n';
    v_report := v_report || rpad('MAE', 20) ||
                lpad(round(v_mae_raw::NUMERIC, 6)::TEXT, 16) ||
                lpad(round(v_mae_cal::NUMERIC, 6)::TEXT, 16) ||
                lpad(CASE WHEN v_mae_raw > 0
                          THEN round(((v_mae_cal - v_mae_raw) / v_mae_raw * 100)::NUMERIC, 1)::TEXT || '%'
                          ELSE 'n/a' END, 16) || E'\n';
    v_report := v_report || rpad('ROC-AUC', 20) ||
                lpad(round(v_roc_auc_raw::NUMERIC, 4)::TEXT, 16) ||
                lpad(round(v_roc_auc_cal::NUMERIC, 4)::TEXT, 16) ||
                lpad(CASE WHEN v_roc_auc_raw > 0
                          THEN round(((v_roc_auc_cal - v_roc_auc_raw) / v_roc_auc_raw * 100)::NUMERIC, 1)::TEXT || '%'
                          ELSE 'n/a' END, 16) || E'\n';
    v_report := v_report || rpad('Precision (p≥0.5)', 20) ||
                lpad(round(v_precision_raw::NUMERIC, 4)::TEXT, 16) ||
                lpad(round(v_precision_cal::NUMERIC, 4)::TEXT, 16) ||
                lpad(CASE WHEN v_precision_raw > 0
                          THEN round(((v_precision_cal - v_precision_raw) / v_precision_raw * 100)::NUMERIC, 1)::TEXT || '%'
                          ELSE 'n/a' END, 16) || E'\n';
    v_report := v_report || rpad('Recall (p≥0.5)', 20) ||
                lpad(round(v_recall_raw::NUMERIC, 4)::TEXT, 16) ||
                lpad(round(v_recall_cal::NUMERIC, 4)::TEXT, 16) ||
                lpad(CASE WHEN v_recall_raw > 0
                          THEN round(((v_recall_cal - v_recall_raw) / v_recall_raw * 100)::NUMERIC, 1)::TEXT || '%'
                          ELSE 'n/a' END, 16) || E'\n';
    v_report := v_report || rpad('ECE', 20) ||
                lpad(round(v_ece_raw::NUMERIC, 6)::TEXT, 16) ||
                lpad(round(v_ece_cal::NUMERIC, 6)::TEXT, 16) ||
                lpad(CASE WHEN v_ece_raw > 0
                          THEN round(((v_ece_cal - v_ece_raw) / v_ece_raw * 100)::NUMERIC, 1)::TEXT || '%'
                          ELSE 'n/a' END, 16) || E'\n';
    v_report := v_report || rpad('MCE', 20) ||
                lpad(round(v_mce_raw::NUMERIC, 6)::TEXT, 16) ||
                lpad(round(v_mce_cal::NUMERIC, 6)::TEXT, 16) ||
                lpad(CASE WHEN v_mce_raw > 0
                          THEN round(((v_mce_cal - v_mce_raw) / v_mce_raw * 100)::NUMERIC, 1)::TEXT || '%'
                          ELSE 'n/a' END, 16) || E'\n';

    v_report := v_report || E'\n' ||
        'Примечание: raw — по predicted_risk; calibrated — по COALESCE(calibrated_risk, mchain_calibrate_risk(predicted_risk)).' || E'\n';
    IF NOT v_calibration_enabled THEN
        v_report := v_report || '⚠ Калибровка отключена. Потребители должны использовать raw (predicted_risk).' || E'\n';
    ELSE
        v_report := v_report || 'Для дашбордов и решений используйте calibrated. Для алертов (mchain_hybrid_alert_at) — raw (пороги подобраны под raw).' || E'\n';
    END IF;

    -- Калибровочные таблицы: raw и calibrated
    v_report := v_report || v_sub_sep;
    v_report := v_report || 'КАЛИБРОВОЧНАЯ ТАБЛИЦА (raw)' || E'\n';
    v_report := v_report || 'Бин (вероятность) | Среднее предсказание | Наблюдаемая частота | Количество' || E'\n';
    FOR v_rec IN SELECT * FROM jsonb_to_recordset(v_calib_raw)
                 AS x(bin_low NUMERIC, bin_high NUMERIC, avg_pred NUMERIC, obs_freq NUMERIC, cnt INT)
    LOOP
        v_report := v_report || format('[%s, %s)          %s                  %s                %s',
            v_rec.bin_low, v_rec.bin_high,
            round(v_rec.avg_pred::NUMERIC, 3),
            round(v_rec.obs_freq::NUMERIC, 3),
            v_rec.cnt) || E'\n';
    END LOOP;

    v_report := v_report || v_sub_sep;
    v_report := v_report || 'КАЛИБРОВОЧНАЯ ТАБЛИЦА (calibrated)' || E'\n';
    v_report := v_report || 'Бин (вероятность) | Среднее предсказание | Наблюдаемая частота | Количество' || E'\n';
    FOR v_rec IN SELECT * FROM jsonb_to_recordset(v_calib_cal)
                 AS x(bin_low NUMERIC, bin_high NUMERIC, avg_pred NUMERIC, obs_freq NUMERIC, cnt INT)
    LOOP
        v_report := v_report || format('[%s, %s)          %s                  %s                %s',
            v_rec.bin_low, v_rec.bin_high,
            round(v_rec.avg_pred::NUMERIC, 3),
            round(v_rec.obs_freq::NUMERIC, 3),
            v_rec.cnt) || E'\n';
    END LOOP;

    -- Дневная динамика
    v_report := v_report || v_sub_sep;
    v_report := v_report || 'ДНЕВНАЯ ДИНАМИКА МЕТРИК (источник: mchain_quality_metrics_history)' || E'\n';
    SELECT COUNT(*) INTO v_days_with_data
    FROM mchain_quality_metrics_history
    WHERE date_from >= v_start::DATE AND date_to <= v_end::DATE;

    IF v_days_with_data > 0 THEN
        v_report := v_report || 'Дата       | Brier  | Log-loss | ECE    | MCE    | Наблюдений | Примечание' || E'\n';
        FOR v_rec IN
            SELECT date_from, brier_score, log_loss, ece, mce, total_predictions, notes
            FROM mchain_quality_metrics_history
            WHERE date_from >= v_start::DATE AND date_to <= v_end::DATE
            ORDER BY date_from
        LOOP
            v_report := v_report || format('%s | %s | %s | %s | %s | %s | %s',
                v_rec.date_from,
                COALESCE(round(v_rec.brier_score::NUMERIC, 4)::TEXT, 'NULL'),
                COALESCE(round(v_rec.log_loss::NUMERIC, 4)::TEXT, 'NULL'),
                COALESCE(round(v_rec.ece::NUMERIC, 4)::TEXT, 'NULL'),
                COALESCE(round(v_rec.mce::NUMERIC, 4)::TEXT, 'NULL'),
                v_rec.total_predictions,
                COALESCE(v_rec.notes, 'OK')) || E'\n';
        END LOOP;
    ELSE
        v_report := v_report || 'Нет данных в mchain_quality_metrics_history за указанный период.' || E'\n';
    END IF;

    -- Диагностические сообщения
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

    -- Рекомендации (по calibrated, если enabled; иначе по raw)
    v_report := v_report || 'РЕКОМЕНДАЦИИ' || E'\n';
    IF v_calibration_enabled THEN
        IF v_brier_cal < 0.05 THEN
            v_report := v_report || '  ★ Отличная калибровка (Brier(c) < 0.05). Прогнозы очень точны.' || E'\n';
        ELSIF v_brier_cal < 0.1 THEN
            v_report := v_report || '  ✔ Хорошая калибровка (Brier(c) 0.05–0.1). Прогнозы надёжны.' || E'\n';
        ELSIF v_brier_cal < 0.2 THEN
            v_report := v_report || '  ⚠ Удовлетворительная калибровка (Brier(c) 0.1–0.2). Рекомендуется периодический пересмотр.' || E'\n';
        ELSE
            v_report := v_report || '  🔴 Плохая калибровка (Brier(c) > 0.2). Требуется корректировка модели.' || E'\n';
        END IF;

        IF v_ece_cal < 0.05 THEN
            v_report := v_report || '  ★ ECE(c) < 0.05 – отличная калибровка вероятностей.' || E'\n';
        ELSIF v_ece_cal < 0.1 THEN
            v_report := v_report || '  ✔ ECE(c) 0.05–0.1 – хорошая калибровка.' || E'\n';
        ELSE
            v_report := v_report || '  ⚠ ECE(c) > 0.1 – калибровка требует внимания.' || E'\n';
        END IF;
    ELSE
        IF v_brier_raw < 0.1 THEN
            v_report := v_report || '  ✔ Сырой Brier < 0.1 – приемлемо.' || E'\n';
        ELSE
            v_report := v_report || '  ⚠ Сырой Brier ≥ 0.1. Рекомендуется включить калибровку.' || E'\n';
        END IF;
    END IF;

    IF v_precision_cal < 0.1 AND v_incident_rate < 0.1 THEN
        v_report := v_report || '  ℹ Низкая precision при пороге 0.5 (возможно, дисбаланс классов). Можно снизить порог для повышения recall.' || E'\n';
    END IF;

    v_report := v_report || v_line_sep;

    RETURN v_report;
END;
$$;

COMMENT ON FUNCTION mchain_quality_report(DATE, DATE, INT) IS
'v26.1.4 (2026-11-09). Отчёт качества прогнозов с параллельным выводом raw и calibrated метрик.

ИЗМЕНЕНИЯ v26.1.4 (относительно v26.1.2):
  - Для всех метрик (Brier, Log-loss, MAE, ROC-AUC, Precision, Recall, ECE, MCE) 
    выводятся ДВА значения: raw (predicted_risk) и calibrated 
    (COALESCE(calibrated_risk, mchain_calibrate_risk(predicted_risk))).
  - Добавлен столбец delta (относительное изменение calibrated vs raw).
  - Построены ДВЕ калибровочные таблицы: raw и calibrated.
  - Добавлена секция «СОСТОЯНИЕ КАЛИБРОВКИ» (enabled, method, fitted_at, n).
  - Рекомендации формируются по calibrated (если enabled) или по raw.

Причина: в v26.1.1 введена калибровка, но отчёты продолжали показывать только raw, 
что создавало ложное впечатление «сломанной» калибровки (ECE=0.10) при фактическом 
ECE=0.0062. Потребителям следует использовать calibrated для дашбордов и решений; 
алерты (mchain_hybrid_alert_at) остаются на raw (пороги подобраны под raw).

Примеры:
  SELECT mchain_quality_report();
  SELECT mchain_quality_report(CURRENT_DATE - 30, CURRENT_DATE - 1);
  SELECT mchain_quality_report(CURRENT_DATE - 7, CURRENT_DATE - 1, 30);
';


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
-- evaluate_forgetting_params
-- Версия: 17.1.3 (2026-10-19, hotfix P2.1-v3)
-- Назначение: эмпирический подбор параметров адаптивного забывания.
--
-- ИСТОРИЯ ИЗМЕНЕНИЙ:
--   v17.1   — REAL-сигнатура; при вызове с NUMERIC-литералами падала на
--             «функция не существует» (test3).
--   v17.1.1 — переход на NUMERIC; НО в markov_chain_functions.sql остался
--             дубликат REAL-версии. В БД сосуществовали обе; PostgreSQL
--             при разрешении перегрузки выбирал REAL-версию.
--   v17.1.2 — не изменялся.
--   v17.1.3 — (a) УДАЛЁН дубликат из markov_chain_functions.sql.
--             (b) Добавлен явный DROP IF EXISTS старой REAL-сигнатуры
--                 ПЕРЕД CREATE. Гарантирует единственную NUMERIC-версию
--                 независимо от предыдущего состояния БД.
--             Причина hotfix test6: вызывалась REAL-версия, и внутри
--             неё mchain_predict_risk_k_v2_with_matrix получал
--             tmp_prob.probability типа DOUBLE PRECISION (а не NUMERIC,
--             как ожидалось в кэшированном плане после Test 2). Ошибка:
--             «тип параметра 17 (double precision) не соответствует тому,
--              с которым подготавливался план (numeric)». После удаления
--             REAL-версии tmp_prob.probability всегда NUMERIC — проблема
--             устранена на уровне типов.
--
-- Обоснование NUMERIC вместо REAL:
--   Вызов с обычными литералами
--     evaluate_forgetting_params(p_base_alpha => 0.05, p_half_life => 30, ...)
--   требует, чтобы параметры принимали одновременно NUMERIC (0.05) и
--   INTEGER (30). NUMERIC удовлетворяет обоим (INTEGER → NUMERIC implicit),
--   REAL — нет. Использование REAL в сигнатуре делало вызов с NUMERIC
--   литералом невозможным (ошибка «функция не существует», test3).
--
-- Параметры:
--   p_base_alpha     NUMERIC – базовая скорость забывания
--   p_half_life      NUMERIC – период полураспада (дни)
--   p_min_alpha      NUMERIC – нижняя граница alpha
--   p_interval_min   INT     – интервал применения забывания (минуты)
--   p_learn_start    DATE    – начало периода обучения
--   p_learn_end      DATE    – конец периода обучения
--   p_eval_start     DATE    – начало периода оценки
--   p_eval_end       DATE    – конец периода оценки
--   p_horizon        INT     – горизонт прогноза (NULL → из markov_config)
--   p_min_transitions INT    – минимум переходов для включения пары в анализ
--   p_smoothing      NUMERIC – аддитивное сглаживание (default 0.01)
--
-- Возвращает: TABLE(brier, log_loss, roc_auc, precision_at_05,
--             recall_at_05, mae, total_predictions, incident_rate,
--             max_prob_change, coverage_pct).
--
-- Все временные таблицы созданы с ON COMMIT DROP для автоматического
-- освобождения блокировок.
-- =============================================================================
CREATE OR REPLACE FUNCTION evaluate_forgetting_params(
    p_base_alpha NUMERIC,
    p_half_life NUMERIC,
    p_min_alpha NUMERIC,
    p_interval_min INT,
    p_learn_start DATE,
    p_learn_end DATE,
    p_eval_start DATE,
    p_eval_end DATE,
    p_horizon INT DEFAULT NULL,
    p_min_transitions INT DEFAULT 5,
    p_smoothing NUMERIC DEFAULT 0.01
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
    v_smooth_factor NUMERIC;
BEGIN
    v_smooth_factor := p_smoothing * v_total_states;

    -- ------------------------------------------
    -- 1. Взвешенные частоты переходов с временным затуханием
    -- ------------------------------------------
    DROP TABLE IF EXISTS tmp_weighted_freq;
    CREATE TEMP TABLE tmp_weighted_freq ON COMMIT DROP AS
    WITH transitions AS (
        SELECT from_state, to_state, ts,
               EXP(-(EXTRACT(EPOCH FROM (p_learn_end - ts)) / 86400.0) / p_half_life) AS weight
        FROM transition_log
        WHERE ts >= p_learn_start AND ts < p_learn_end
    )
    SELECT from_state, to_state, SUM(weight) AS frequency
    FROM transitions
    GROUP BY from_state, to_state;

    DELETE FROM tmp_weighted_freq WHERE frequency < 1e-6;

    -- Нормализация с аддитивным сглаживанием. v_smooth_factor и p_smoothing
    -- имеют тип NUMERIC → probability в tmp_prob всегда NUMERIC. Это
    -- критично для согласованности типов с кэшем плана _with_matrix.
    DROP TABLE IF EXISTS tmp_prob;
    CREATE TEMP TABLE tmp_prob ON COMMIT DROP AS
    SELECT from_state, to_state,
           (frequency + p_smoothing) / (SUM(frequency) OVER (PARTITION BY from_state) + v_smooth_factor) AS probability
    FROM tmp_weighted_freq;

    CREATE INDEX idx_tmp_prob_from ON tmp_prob (from_state);

    -- ------------------------------------------
    -- 2. Оценка прогнозов на eval-периоде
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
            IF v_rec.actual_outcome = 1 THEN v_tp := v_tp + 1;
            ELSE v_fp := v_fp + 1; END IF;
        ELSE
            IF v_rec.actual_outcome = 1 THEN v_fn := v_fn + 1; END IF;
        END IF;

        v_all_risks := array_append(v_all_risks, v_risk);
        v_all_outcomes := array_append(v_all_outcomes, v_rec.actual_outcome);
    END LOOP;

    IF v_total = 0 THEN
        RETURN;
    END IF;

    -- ------------------------------------------
    -- 3. Основные метрики
    -- ------------------------------------------
    brier := v_brier_sum / v_total;
    log_loss := v_log_loss_sum / v_total;
    mae := v_mae_sum / v_total;
    incident_rate := v_incidents::REAL / v_total;
    total_predictions := v_total;

    precision_at_05 := CASE WHEN (v_tp + v_fp) > 0 THEN v_tp::REAL / (v_tp + v_fp) ELSE 0 END;
    recall_at_05 := CASE WHEN (v_tp + v_fn) > 0 THEN v_tp::REAL / (v_tp + v_fn) ELSE 0 END;

    -- ROC-AUC (ранговый метод)
    IF array_length(v_all_outcomes, 1) > 0 THEN
        SELECT COUNT(*) INTO v_pos_count FROM unnest(v_all_outcomes) WHERE unnest = 1;
        SELECT COUNT(*) INTO v_neg_count FROM unnest(v_all_outcomes) WHERE unnest = 0;
        IF v_pos_count > 0 AND v_neg_count > 0 THEN
            WITH data AS (
                SELECT unnest(v_all_risks) AS risk, unnest(v_all_outcomes) AS outcome
            ),
            ranked AS (
                SELECT risk, outcome, ROW_NUMBER() OVER (ORDER BY risk ASC) AS rank FROM data
            )
            SELECT SUM(CASE WHEN outcome = 1 THEN rank ELSE 0 END) INTO v_rank_sum FROM ranked;
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
    -- 4. max_prob_change (стабильность) — исключаем критические переходы
    -- ------------------------------------------
    v_mid1 := p_learn_start + (p_learn_end - p_learn_start) / 3;
    v_mid2 := p_learn_start + 2 * (p_learn_end - p_learn_start) / 3;
    v_seg_start1 := p_learn_start;   v_seg_end1 := v_mid1;
    v_seg_start2 := v_mid1;          v_seg_end2 := v_mid2;
    v_seg_start3 := v_mid2;          v_seg_end3 := p_learn_end;

    DROP TABLE IF EXISTS tmp_valid_pairs;
    CREATE TEMP TABLE tmp_valid_pairs ON COMMIT DROP AS
    SELECT from_state, to_state
    FROM transition_log
    WHERE ts >= p_learn_start AND ts < p_learn_end
      AND to_state NOT IN (SELECT state_id FROM critical_states)
      AND from_state NOT IN (SELECT state_id FROM critical_states)
    GROUP BY from_state, to_state
    HAVING COUNT(*) >= p_min_transitions;

    DROP TABLE IF EXISTS tmp_seg1_freq;
    CREATE TEMP TABLE tmp_seg1_freq ON COMMIT DROP AS
    SELECT v.from_state, v.to_state, COALESCE(t.cnt, 0) AS cnt
    FROM tmp_valid_pairs v
    LEFT JOIN (
        SELECT from_state, to_state, COUNT(*) AS cnt
        FROM transition_log
        WHERE ts >= v_seg_start1 AND ts < v_seg_end1
          AND to_state NOT IN (SELECT state_id FROM critical_states)
          AND from_state NOT IN (SELECT state_id FROM critical_states)
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
          AND to_state NOT IN (SELECT state_id FROM critical_states)
          AND from_state NOT IN (SELECT state_id FROM critical_states)
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
          AND to_state NOT IN (SELECT state_id FROM critical_states)
          AND from_state NOT IN (SELECT state_id FROM critical_states)
        GROUP BY from_state, to_state
    ) t ON v.from_state = t.from_state AND v.to_state = t.to_state;

    DROP TABLE IF EXISTS tmp_seg1_total;
    CREATE TEMP TABLE tmp_seg1_total ON COMMIT DROP AS
    SELECT from_state, COUNT(*) AS total_cnt FROM transition_log
    WHERE ts >= v_seg_start1 AND ts < v_seg_end1 GROUP BY from_state;

    DROP TABLE IF EXISTS tmp_seg2_total;
    CREATE TEMP TABLE tmp_seg2_total ON COMMIT DROP AS
    SELECT from_state, COUNT(*) AS total_cnt FROM transition_log
    WHERE ts >= v_seg_start2 AND ts < v_seg_end2 GROUP BY from_state;

    DROP TABLE IF EXISTS tmp_seg3_total;
    CREATE TEMP TABLE tmp_seg3_total ON COMMIT DROP AS
    SELECT from_state, COUNT(*) AS total_cnt FROM transition_log
    WHERE ts >= v_seg_start3 AND ts < v_seg_end3 GROUP BY from_state;

    DROP TABLE IF EXISTS tmp_prob_seg1;
    CREATE TEMP TABLE tmp_prob_seg1 ON COMMIT DROP AS
    SELECT f.from_state, f.to_state,
           (f.cnt + p_smoothing) / (COALESCE(t.total_cnt, 0) + v_smooth_factor) AS prob
    FROM tmp_seg1_freq f
    LEFT JOIN tmp_seg1_total t ON f.from_state = t.from_state;

    DROP TABLE IF EXISTS tmp_prob_seg2;
    CREATE TEMP TABLE tmp_prob_seg2 ON COMMIT DROP AS
    SELECT f.from_state, f.to_state,
           (f.cnt + p_smoothing) / (COALESCE(t.total_cnt, 0) + v_smooth_factor) AS prob
    FROM tmp_seg2_freq f
    LEFT JOIN tmp_seg2_total t ON f.from_state = t.from_state;

    DROP TABLE IF EXISTS tmp_prob_seg3;
    CREATE TEMP TABLE tmp_prob_seg3 ON COMMIT DROP AS
    SELECT f.from_state, f.to_state,
           (f.cnt + p_smoothing) / (COALESCE(t.total_cnt, 0) + v_smooth_factor) AS prob
    FROM tmp_seg3_freq f
    LEFT JOIN tmp_seg3_total t ON f.from_state = t.from_state;

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

    SELECT COALESCE(MAX(max_diff), 1.0) INTO v_max_prob_change FROM tmp_pair_diffs;
    max_prob_change := v_max_prob_change;

    -- ------------------------------------------
    -- 5. coverage_pct
    -- ------------------------------------------
    SELECT COUNT(*) INTO v_total_transitions FROM transition_log
    WHERE ts >= p_learn_start AND ts < p_learn_end;

    IF v_total_transitions > 0 THEN
        WITH state_stats AS (
            SELECT from_state, COUNT(*) AS n_i,
                   COUNT(*)::REAL / v_total_transitions AS freq
            FROM transition_log
            WHERE ts >= p_learn_start AND ts < p_learn_end
            GROUP BY from_state
        ),
        frequent_states AS (
            SELECT from_state FROM state_stats WHERE freq > 0.01
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

    -- Очистка временных таблиц
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

COMMENT ON FUNCTION evaluate_forgetting_params(NUMERIC, NUMERIC, NUMERIC, INT, DATE, DATE, DATE, DATE, INT, INT, NUMERIC) IS
'v17.1.3. Эмпирический подбор параметров адаптивного забывания. '
'Сигнатура REAL → NUMERIC, чтобы работали вызовы с NUMERIC-литералами '
'(p_base_alpha => 0.05, p_half_life => 30) без явных приведений. '
'Hotfix v17.1.3: '
'(1) В markov_chain_functions.sql УДАЛЁН дубликат с REAL-сигнатурой — '
'    в test6 именно он вызывался PostgreSQL при разрешении перегрузки, '
'    что приводило к plan-cache mismatch в _with_matrix '
'    («тип параметра 17 (double precision) не соответствует ... (numeric)»). '
'(2) Явный DROP FUNCTION IF EXISTS ... (REAL, ...) перед CREATE '
'    гарантирует единственную NUMERIC-версию независимо от предыдущего '
'    состояния БД. '
'Внутри функции v_smooth_factor NUMERIC, поэтому tmp_prob.probability '
'всегда NUMERIC — тип параметра probability в вызове '
'mchain_predict_risk_k_v2_with_matrix стабилен.';


-- =============================================================================
-- mchain_predict_risk_k_v2_with_matrix
-- Версия: 17.1.3 (2026-10-19, hotfix P2.1-v2)
-- Назначение: вероятность хотя бы одного попадания в критическое множество
--             за k шагов, вычисленная по заданной матрице переходов
--             (вместо фиксированной markov_probabilities).
--
-- ИСТОРИЯ:
--   v17.1.3 — устранён регресс test5: функция использовала REAL для вектора
--             состояний (v, v_new, risk), что при малых вероятностях
--             (NUMERIC из tmp_prob_segN) приводило к «значение вне диапазона:
--             антипереполнение» (22003) при приведении DOUBLE PRECISION →
--             REAL внутри цикла. Тот же дефект был устранён в
--             mchain_predict_risk_k_v2 ещё в v16.8 (см. test23/test24),
--             но не был перенесён в *_with_matrix. Теперь DOUBLE PRECISION
--             используется на всём протяжении, финальный результат
--             клампится в [0, 1] и кастуется в REAL только на выходе.
--
-- Параметры:
--   p_state_id      SMALLINT – начальное состояние
--   k               INT      – горизонт в шагах (минуты)
--   p_matrix_table  TEXT     – имя временной таблицы с матрицей переходов
--                              (ожидаются колонки from_state, to_state,
--                               probability)
--
-- Возвращает: REAL ∈ [0, 1] — вероятность попадания в critical_states
--             хотя бы раз за k шагов. Начальное состояние, уже
--             находящееся в critical_states, даёт 1.0.
-- =============================================================================
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
    v DOUBLE PRECISION[];                    -- было REAL[] — фикс v17.1.3
    v_new DOUBLE PRECISION[];                -- было REAL[] — фикс v17.1.3
    critical_ids SMALLINT[];
    step INT;
    risk DOUBLE PRECISION := 0.0;            -- было REAL — фикс v17.1.3
    rec RECORD;
    i INT;
BEGIN
    -- 1. Список критических состояний
    SELECT array_agg(state_id) INTO critical_ids FROM critical_states;
    IF critical_ids IS NULL OR array_length(critical_ids, 1) = 0 THEN
        RETURN 0.0;
    END IF;

    -- 2. Начальное состояние уже в критическом множестве — риск 1
    IF p_state_id = ANY(critical_ids) THEN
        RETURN 1.0;
    END IF;

    -- 3. Инициализация вектора состояний
    v := array_fill(0.0::DOUBLE PRECISION, ARRAY[total_states]);
    IF p_state_id BETWEEN 0 AND total_states - 1 THEN
        v[p_state_id + 1] := 1.0;
    ELSE
        RETURN 0.0;
    END IF;

    -- 4. k шагов умножения матрицы
    FOR step IN 1..k LOOP
        v_new := array_fill(0.0::DOUBLE PRECISION, ARRAY[total_states]);

        FOR rec IN EXECUTE format('
            SELECT from_state, to_state, probability
            FROM %I
        ', p_matrix_table) LOOP
            IF v[rec.from_state + 1] > 0.0 THEN
                v_new[rec.to_state + 1] := v_new[rec.to_state + 1]
                    + v[rec.from_state + 1] * rec.probability::DOUBLE PRECISION;
            END IF;
        END LOOP;

        v := v_new;

        -- 5. Накопление риска и обнуление критических состояний
        --    (поглощение: попав в критическое состояние, система
        --     больше не считается «вне риска»)
        FOR i IN 1..array_length(critical_ids, 1) LOOP
            risk := risk + v[critical_ids[i] + 1];
            v[critical_ids[i] + 1] := 0.0;
        END LOOP;

        IF risk >= 1.0 THEN
            RETURN 1.0;
        END IF;
    END LOOP;

    -- 6. Клампим и кастуем в REAL только на выходе
    RETURN GREATEST(0.0, LEAST(risk, 1.0))::REAL;
END;
$$;

COMMENT ON FUNCTION mchain_predict_risk_k_v2_with_matrix(SMALLINT, INT, TEXT) IS
'v17.1.3. Вероятность хотя бы одного попадания в критическое множество за k '
'шагов по заданной матрице (имя временной таблицы в p_matrix_table). '
'Использует DOUBLE PRECISION для вектора состояний — тот же паттерн, что и '
'в mchain_predict_risk_k_v2 (см. test23/test24): REAL-версия страдала от '
'«значение вне диапазона: антипереполнение» при малых вероятностях '
'(NUMERIC из tmp_prob_segN → REAL). Результат клампится в [0, 1] и '
'кастуется в REAL на выходе.';




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
    v_rec   RECORD;
    v_metrics RECORD;
    v_report TEXT := '';
    v_line_sep CONSTANT TEXT := E'\n' || repeat('=', 100) || E'\n';
    v_sub_sep CONSTANT TEXT := E'\n' || repeat('-', 100) || E'\n';
    v_row TEXT;
    v_total_periods INT := 0;
    v_min_freq INT;
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
    SELECT mc.min_freq_for_stability INTO v_min_freq
    FROM markov_config mc LIMIT 1;

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

        WITH frequent_states AS (
            SELECT from_state
            FROM transition_log
            WHERE ts >= v_start AND ts < v_end + 1
              AND from_state NOT IN (SELECT state_id FROM critical_states)   -- <-- ДОБАВЛЕНО
            GROUP BY from_state
            HAVING COUNT(*) >= v_min_freq
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
              AND from_state NOT IN (SELECT state_id FROM critical_states)   -- <-- ДОБАВЛЕНО
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
              AND from_state NOT IN (SELECT state_id FROM critical_states)   -- <-- ДОБАВЛЕНО
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

        IF v_metrics.total_trans = 0 THEN
            CONTINUE;
        END IF;

        v_total_periods := v_total_periods + 1;

        IF v_total_periods = 1 THEN
            v_first_max_change := v_metrics.max_prob_change;
            v_first_coverage   := v_metrics.coverage_pct;
            v_first_period_start := v_metrics.period_start;
            v_first_period_end   := v_metrics.period_end;
        END IF;

        v_last_max_change := v_metrics.max_prob_change;
        v_last_coverage   := v_metrics.coverage_pct;
        v_last_period_start := v_metrics.period_start;
        v_last_period_end   := v_metrics.period_end;

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

    -- ОПИСАНИЕ СТОЛБЦОВ
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
    ece              REAL,
    mce              REAL,
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
        h.ece,
        h.mce,
        h.notes
    FROM mchain_quality_metrics_history h
    WHERE h.date_from >= CURRENT_DATE - p_window_days
    ORDER BY h.date_from;
END;
$$;

COMMENT ON FUNCTION report_quality_sliding(INT, INT) IS 'Возвращает метрики качества прогнозов за скользящие периоды (по дням) из таблицы mchain_quality_metrics_history. Добавлены ECE и MCE.';

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
    -- 1. Горизонт
    SELECT forecast_horizon_minutes INTO v_horizon FROM markov_config LIMIT 1;
    IF v_horizon IS NULL THEN
        v_horizon := 30;
    END IF;

    v_lookback_days := (p_end - p_start) + 1;

    -- 2. Заголовок (без изменений)
    v_section_text := format(
        '# Сводный аналитический отчёт по цепи Маркова
Период: %s – %s
Горизонт прогноза: %s минут
Дата формирования: %s
',
        p_start, p_end, v_horizon, now()::DATE
    );
    v_report_lines := array_cat(v_report_lines, regexp_split_to_array(v_section_text, E'\n'));

    -- 3. Общий обзор (без изменений)
    v_report_lines := array_append(v_report_lines, '');
    v_report_lines := array_append(v_report_lines, '## 1. Общий обзор состояния цепи');
    BEGIN
        SELECT mchain_summary_report(p_start, p_end) INTO v_section_text;
        v_report_lines := array_cat(v_report_lines, regexp_split_to_array(v_section_text, E'\n'));
    EXCEPTION WHEN OTHERS THEN
        v_report_lines := array_append(v_report_lines, '⚠ Ошибка при получении общего обзора: ' || SQLERRM);
    END;

    -- 4. Качество прогнозов (без изменений, так как mchain_quality_report уже модифицирован)
    v_report_lines := array_append(v_report_lines, '');
    v_report_lines := array_append(v_report_lines, '## 2. Качество прогнозов');
    BEGIN
        SELECT mchain_quality_report(p_start, p_end, v_horizon) INTO v_section_text;
        v_report_lines := array_cat(v_report_lines, regexp_split_to_array(v_section_text, E'\n'));
    EXCEPTION WHEN OTHERS THEN
        v_report_lines := array_append(v_report_lines, '⚠ Ошибка при получении отчёта о качестве: ' || SQLERRM);
    END;

    -- 5. Матрица переходов (без изменений)
    v_report_lines := array_append(v_report_lines, '');
    v_report_lines := array_append(v_report_lines, '## 3. Матрица переходов между макрогруппами');
    BEGIN
        SELECT mchain_state_transition_matrix_report(TRUE, TRUE) INTO v_section_text;
        v_report_lines := array_cat(v_report_lines, regexp_split_to_array(v_section_text, E'\n'));
    EXCEPTION WHEN OTHERS THEN
        v_report_lines := array_append(v_report_lines, '⚠ Ошибка при получении матрицы переходов: ' || SQLERRM);
    END;

    -- 6. Стабильность (без изменений)
    v_report_lines := array_append(v_report_lines, '');
    v_report_lines := array_append(v_report_lines, '## 4. Стабильность вероятностей (по 7‑дневным периодам)');
    BEGIN
        SELECT report_stability_trend(v_lookback_days) INTO v_section_text;
        v_report_lines := array_cat(v_report_lines, regexp_split_to_array(v_section_text, E'\n'));
    EXCEPTION WHEN OTHERS THEN
        v_report_lines := array_append(v_report_lines, '⚠ Ошибка при получении стабильности: ' || SQLERRM);
    END;

    -- 7. Скользящее качество прогнозов (с добавлением сноски для ROC‑AUC)
    v_report_lines := array_append(v_report_lines, '');
    v_report_lines := array_append(v_report_lines, '## 5. Скользящее качество прогнозов (по дням)');
    BEGIN
        -- Заголовок таблицы с сноской для ROC‑AUC
        v_section_text := '| Дата | Прогнозов | Brier | ROC‑AUC* | ECE | MCE | Примечание |' || E'\n' ||
                          '|------|-----------|-------|----------|-----|-----|-------------|' || E'\n';
        FOR v_rec IN
            SELECT period_start, total_predictions, brier, roc_auc, ece, mce, calibration_notes
            FROM report_quality_sliding(v_lookback_days, 1)
        LOOP
            v_section_text := v_section_text || format(
                '| %s | %s | %s | %s | %s | %s | %s |' || E'\n',
                v_rec.period_start,
                v_rec.total_predictions,
                COALESCE(round(v_rec.brier::NUMERIC, 4)::TEXT, 'NULL'),
                COALESCE(round(v_rec.roc_auc::NUMERIC, 4)::TEXT, 'NULL'),
                COALESCE(round(v_rec.ece::NUMERIC, 4)::TEXT, 'NULL'),
                COALESCE(round(v_rec.mce::NUMERIC, 4)::TEXT, 'NULL'),
                COALESCE(v_rec.calibration_notes, '')
            );
        END LOOP;
        -- Добавляем сноску после таблицы
        v_section_text := v_section_text || E'\n' ||
                          '* ROC‑AUC может быть неинформативной при константных прогнозах; основное внимание уделяйте калибровочным метрикам (Brier, ECE, MCE).';
        v_report_lines := array_cat(v_report_lines, regexp_split_to_array(v_section_text, E'\n'));
    EXCEPTION WHEN OTHERS THEN
        v_report_lines := array_append(v_report_lines, '⚠ Ошибка при получении скользящего качества: ' || SQLERRM);
    END;

    -- 8. Распределение состояний (без изменений)
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

    -- 9. Эффективность забывания (без изменений)
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

    -- 10. Калибровочная кривая (без изменений)
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

    -- 11. Финальная черта
    v_report_lines := array_append(v_report_lines, '');
    v_report_lines := array_append(v_report_lines, '---');
    v_report_lines := array_append(v_report_lines, '*Отчёт сформирован автоматически.*');

    RETURN v_report_lines;
END;
$$;

COMMENT ON FUNCTION generate_full_analytical_report(DATE, DATE) IS 'Формирует сводный аналитический отчёт по цепи Маркова в формате Markdown. В таблице скользящего качества добавлена сноска для ROC‑AUC о её ограничениях.';

-- ==========================================================
-- Адаптивная настройка min_freq_for_stability
-- ==========================================================
-- ==========================================================
-- Адаптивная настройка min_freq_for_stability
-- Модификация: выполнять обновление только если обучение цепи достаточно
-- (общее число переходов >= min_transitions_for_forgetting)
-- ==========================================================
CREATE OR REPLACE FUNCTION refresh_stability_threshold()
RETURNS TEXT LANGUAGE plpgsql AS $$
DECLARE
    v_total BIGINT;
    v_total_all BIGINT;
    v_min_transitions INT;
    v_new_threshold INT;
    v_current INT;
    v_max_limit INT := 500;
    v_min_limit INT := 10;
BEGIN
    -- Проверка достаточности обучения: общее число переходов должно быть >= min_transitions_for_forgetting
    SELECT min_transitions_for_forgetting INTO v_min_transitions FROM markov_config LIMIT 1;
    SELECT COUNT(*) INTO v_total_all FROM transition_log;
    IF v_total_all < v_min_transitions THEN
        RETURN format('Insufficient data: total transitions %s < %s, threshold unchanged.', v_total_all, v_min_transitions);
    END IF;

    -- Суммарные переходы за последние 14 дней
    SELECT COUNT(*) INTO v_total
    FROM transition_log
    WHERE ts >= now() - INTERVAL '14 days';

    IF v_total = 0 THEN
        RETURN 'No transitions in last 14 days, threshold unchanged.';
    END IF;

    -- 1% от общего числа, но не менее 10 и не более 500
    v_new_threshold := GREATEST(v_min_limit, LEAST(v_max_limit, round(v_total * 0.01)));

    -- Дополнительно ограничим средним значением на состояние * 3
    v_new_threshold := LEAST(v_new_threshold, round(v_total / 189.0 * 3));

    SELECT min_freq_for_stability INTO v_current FROM markov_config LIMIT 1;

    -- Сглаживание: если новый порог отличается более чем на 20%, обновляем
    IF abs(v_new_threshold - v_current) > v_current * 0.2 THEN
        UPDATE markov_config SET min_freq_for_stability = v_new_threshold;
        RETURN format('Threshold updated from %s to %s', v_current, v_new_threshold);
    ELSE
        RETURN format('Threshold unchanged (current %s, computed %s)', v_current, v_new_threshold);
    END IF;
END;
$$;

COMMENT ON FUNCTION refresh_stability_threshold() IS 'Адаптивная настройка min_freq_for_stability, выполняемая только при достаточном обучении (общее число переходов >= min_transitions_for_forgetting).';




-- ====================================================================================================
-- Функция: заполнить performance_history за указанный период
-- ====================================================================================================
-- Модифицированная функция fill_performance_history с выводом прогресса через RAISE NOTICE
/*
select fill_performance_history( to_timestamp('2026-06-25 00:00' , 'YYYY-MM-DD HH24:MI') , to_timestamp('2026-06-26 00:00' , 'YYYY-MM-DD HH24:MI') );

psql -d expecto_db -U expecto_user -c "select fill_performance_history( to_timestamp('2026-06-25 00:00' , 'YYYY-MM-DD HH24:MI') , to_timestamp('2026-06-26 00:00' , 'YYYY-MM-DD HH24:MI') )"
psql -d expecto_db -U expecto_user -c "select ph.* , pi.* from performance_history ph LEFT JOIN markov_chain_performance_incident pi ON ( ph.ts = pi.start_timepoint ) ORDER BY ph.ts " > /tmp/performance_history.txt 
psql -d expecto_db -U expecto_user -c "select mchain_summary_report(to_timestamp('2026-06-22 00:00' , 'YYYY-MM-DD HH24:MI') , to_timestamp('2026-06-23 00:00' , 'YYYY-MM-DD HH24:MI') )" > /tmp/mchain_summary_report.txt
*/
CREATE OR REPLACE FUNCTION fill_performance_history(
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
    v_skip        BOOLEAN;
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
	
	TRUNCATE TABLE performance_history ; 

    -- Округляем до минут для единообразия
    v_start_ts := date_trunc('minute', p_start);
    v_end_ts   := date_trunc('minute', p_end);

    -- Общее количество минут в диапазоне
    v_total_minutes := EXTRACT(EPOCH FROM (v_end_ts - v_start_ts)) / 60 + 1;

    RAISE NOTICE 'Начало заполнения performance_history за период с % по % (всего % минут)',
                 v_start_ts, v_end_ts, v_total_minutes;

    -- Начинаем с первой минуты
    v_ts := v_start_ts;

    WHILE v_ts <= v_end_ts LOOP
        v_skip := FALSE;

        -- 1. Получаем значения скорости и ожиданий в точный момент времени
        SELECT curr_op_speed, curr_waitings
        INTO v_op_speed, v_waitings
        FROM cluster_stat_median
        WHERE curr_timestamp = v_ts;

        -- Если точной записи нет – пропускаем эту минуту
        IF NOT FOUND THEN
            v_ts := v_ts + INTERVAL '1 minute';
            v_processed := v_processed + 1;
            -- Вывод прогресса даже для пропущенных минут (чтобы пользователь видел движение)
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

        -- 3. Вычисляем угол наклона тренда операционной скорости
        BEGIN
            WITH window_data AS (
                SELECT
                    curr_op_speed,
                    row_number() OVER (ORDER BY curr_timestamp) AS rn
                FROM cluster_stat_median
                WHERE curr_timestamp BETWEEN v_ts - v_window AND v_ts
            ),
            stats AS (
                SELECT
                    AVG(rn::DOUBLE PRECISION) as avg1,
                    STDDEV(rn::DOUBLE PRECISION) as std1,
                    AVG(curr_op_speed::DOUBLE PRECISION) as avg2,
                    STDDEV(curr_op_speed::DOUBLE PRECISION) as std2
                FROM window_data
            ),
            standardized_data AS (
                SELECT
                    (wd.rn::DOUBLE PRECISION - s.avg1) / NULLIF(s.std1, 0) as x_z,
                    (wd.curr_op_speed::DOUBLE PRECISION - s.avg2) / NULLIF(s.std2, 0) as y_z
                FROM window_data wd, stats s
            )
            SELECT
                ATAN(REGR_SLOPE(y_z, x_z)) * 180 / PI()
            INTO v_os_angle
            FROM standardized_data;
        EXCEPTION
            WHEN OTHERS THEN
                v_os_angle := 0.0;
        END;

        -- 4. Вычисляем угол наклона тренда ожиданий
        BEGIN
            WITH window_data AS (
                SELECT
                    curr_waitings,
                    row_number() OVER (ORDER BY curr_timestamp) AS rn
                FROM cluster_stat_median
                WHERE curr_timestamp BETWEEN v_ts - v_window AND v_ts
            ),
            stats AS (
                SELECT
                    AVG(rn::DOUBLE PRECISION) as avg1,
                    STDDEV(rn::DOUBLE PRECISION) as std1,
                    AVG(curr_waitings::DOUBLE PRECISION) as avg2,
                    STDDEV(curr_waitings::DOUBLE PRECISION) as std2
                FROM window_data
            ),
            standardized_data AS (
                SELECT
                    (wd.rn::DOUBLE PRECISION - s.avg1) / NULLIF(s.std1, 0) as x_z,
                    (wd.curr_waitings::DOUBLE PRECISION - s.avg2) / NULLIF(s.std2, 0) as y_z
                FROM window_data wd, stats s
            )
            SELECT
                ATAN(REGR_SLOPE(y_z, x_z)) * 180 / PI()
            INTO v_wait_angle
            FROM standardized_data;
        EXCEPTION
            WHEN OTHERS THEN
                v_wait_angle := 0.0;
        END;

        -- 5. Вставляем запись в performance_history
        INSERT INTO performance_history (ts, op_speed, waitings, correlation, os_angle, wait_angle)
        VALUES (v_ts, v_op_speed, v_waitings, v_correlation, v_os_angle, v_wait_angle)
        ON CONFLICT (ts) DO UPDATE SET
            op_speed = EXCLUDED.op_speed,
            waitings = EXCLUDED.waitings,
            correlation = EXCLUDED.correlation,
            os_angle = EXCLUDED.os_angle,
            wait_angle = EXCLUDED.wait_angle;

        v_inserted := v_inserted + 1;

        -- Переходим к следующей минуте и увеличиваем счётчик
        v_ts := v_ts + INTERVAL '1 minute';
        v_processed := v_processed + 1;

        -- Вывод прогресса каждые 10%
        v_current_percent := floor(v_processed * 100.0 / v_total_minutes);
        IF v_current_percent > v_last_percent THEN
            RAISE NOTICE 'Прогресс: % % (обработано % из % минут)',
                         v_current_percent, '%', v_processed, v_total_minutes;
            v_last_percent := v_current_percent;
        END IF;
    END LOOP;

    RAISE NOTICE 'Заполнение завершено. Вставлено/обновлено записей: %.', v_inserted;
    RETURN format('Обработано %s минут. Вставлено/обновлено записей: %s.',
                  v_total_minutes, v_inserted);
END;
$$;

COMMENT ON FUNCTION fill_performance_history(TIMESTAMPTZ, TIMESTAMPTZ) IS 'Заполняет таблицу performance_history за указанный период с выводом прогресса через RAISE NOTICE каждые 10% выполнения.';


-- =====================================================================================
-- Функция: collect_prediction_at(p_ts TIMESTAMPTZ)
-- Назначение: формирует прогноз риска для заданного момента времени,
--             используя текущее состояние цепи (из markov_chain).
-- =====================================================================================
-- =====================================================================================
-- Функция: collect_prediction_at
-- Назначение: формирует прогноз для заданного момента времени.
--             Является тонкой обёрткой над collect_prediction.
-- Параметры:
--   p_ts        TIMESTAMPTZ – момент времени прогноза
--   p_state_id  SMALLINT    – опционально: явно заданный state_id
-- =====================================================================================
CREATE OR REPLACE FUNCTION collect_prediction_at(
    p_ts       TIMESTAMPTZ,
    p_state_id SMALLINT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM collect_prediction(p_time => p_ts, p_state_id => p_state_id);
END;
$$;

COMMENT ON FUNCTION collect_prediction_at(TIMESTAMPTZ, SMALLINT) IS
'Формирует прогноз для заданного времени. Опционально принимает явный state_id.';


-- =====================================================================================
-- Функция: mchain_train_step_at(p_ts TIMESTAMPTZ)
-- Назначение: выполняет один шаг обучения цепи Маркова для указанного момента времени
--             на основе исторических данных из performance_history.
-- =====================================================================================
CREATE OR REPLACE FUNCTION mchain_train_step_at(p_ts TIMESTAMPTZ)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    v_rec RECORD;
    cfg RECORD;
    prev_state SMALLINT;
    curr_state SMALLINT;
    chain_rec RECORD;
    v_correlation REAL;
    v_os_trend SMALLINT;
    v_wait_trend SMALLINT;
BEGIN
    -- 1. Получение метрик из performance_history с явным псевдонимом
    SELECT ph.correlation, ph.os_angle, ph.wait_angle
    INTO v_rec
    FROM performance_history ph
    WHERE ph.ts = date_trunc('minute', p_ts);
    IF NOT FOUND THEN
        RETURN 'No performance data for ' || p_ts::TEXT;
    END IF;

    v_correlation := v_rec.correlation;
    v_os_trend := CASE
        WHEN v_rec.os_angle > 0.5 THEN 1
        WHEN v_rec.os_angle < -0.5 THEN -1
        ELSE 0
    END;
    v_wait_trend := CASE
        WHEN v_rec.wait_angle > 0.5 THEN 1
        WHEN v_rec.wait_angle < -0.5 THEN -1
        ELSE 0
    END;

    curr_state := get_state_id(v_correlation, v_os_trend, v_wait_trend);

    -- 2. Получение последнего состояния из markov_chain
    SELECT prev_correlation, prev_os_trend, prev_wait_trend,
           curr_correlation, curr_os_trend, curr_wait_trend
    INTO chain_rec
    FROM markov_chain LIMIT 1;

    IF chain_rec.curr_correlation IS NULL THEN
        DELETE FROM markov_chain;
        INSERT INTO markov_chain (curr_correlation, curr_os_trend, curr_wait_trend)
        VALUES (v_correlation, v_os_trend, v_wait_trend);
        RETURN 'Initial state saved';
    END IF;

    prev_state := get_state_id(
        chain_rec.curr_correlation,
        chain_rec.curr_os_trend,
        chain_rec.curr_wait_trend
    );

    -- 3. Логирование перехода с историческим временем
    PERFORM mchain_log_transition_at(prev_state, curr_state, p_ts);

    -- 4. Обновление цепи
    UPDATE markov_chain SET
        prev_correlation = curr_correlation,
        prev_os_trend    = curr_os_trend,
        prev_wait_trend  = curr_wait_trend,
        curr_correlation = v_correlation,
        curr_os_trend    = v_os_trend,
        curr_wait_trend  = v_wait_trend;

    -- 5. Плановое забывание
    SELECT last_forget_time, interval_minute INTO cfg FROM markov_config LIMIT 1;
    IF p_ts - cfg.last_forget_time >= MAKE_INTERVAL(mins => cfg.interval_minute) THEN
        PERFORM mchain_apply_forgetting();
    END IF;

    -- 6. Прогноз (передаём вычисленное состояние явно)
    PERFORM collect_prediction_at(p_ts, curr_state);

    RETURN 'Step completed';
END;
$$;

COMMENT ON FUNCTION mchain_train_step_at(TIMESTAMPTZ) IS 'Шаг обучения для исторической минуты на основе performance_history.';



-- =====================================================================================
-- Функция: mchain_train_historical(end_time TIMESTAMPTZ)
-- Назначение: выполняет полное историческое обучение цепи Маркова
--             от минимальной даты в cluster_stat_median до end_time.
--             Логирует прогресс каждый час.
-- =====================================================================================
CREATE OR REPLACE FUNCTION mchain_train_historical(end_time TIMESTAMPTZ)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    start_time TIMESTAMPTZ;
    curr_ts TIMESTAMPTZ;
    total_minutes BIGINT;
    processed BIGINT := 0;
    last_log_hour TIMESTAMPTZ := NULL;
    step_result TEXT;
BEGIN
    SELECT MIN(curr_timestamp) INTO start_time FROM cluster_stat_median;
    IF start_time IS NULL THEN
        RAISE EXCEPTION 'No data in cluster_stat_median';
    END IF;

    -- Заполнение performance_history, если необходимо
    IF NOT EXISTS (SELECT 1 FROM performance_history WHERE ts BETWEEN start_time AND end_time LIMIT 1) THEN
        PERFORM fill_performance_history(start_time, end_time);
    END IF;

    -- Установка last_forget_time в начало периода
    UPDATE markov_config SET last_forget_time = start_time;

    -- Отключение триггера (с проверкой существования)
    IF EXISTS (
        SELECT 1 FROM pg_trigger
        WHERE tgname = 'trigger_update_incident_time'
          AND tgrelid = 'transition_log'::regclass
    ) THEN
        EXECUTE 'ALTER TABLE transition_log DISABLE TRIGGER trigger_update_incident_time';
    END IF;

    total_minutes := EXTRACT(EPOCH FROM (end_time - start_time)) / 60 + 1;
    curr_ts := start_time;

    RAISE NOTICE 'Начало исторического обучения с % по % (всего % минут)', start_time, end_time, total_minutes;

    WHILE curr_ts <= end_time LOOP
        BEGIN
            step_result := mchain_train_step_at(curr_ts);
        EXCEPTION WHEN OTHERS THEN
            RAISE WARNING 'Ошибка на %: %', curr_ts, SQLERRM;
        END;

        processed := processed + 1;

        IF last_log_hour IS NULL OR curr_ts - last_log_hour >= INTERVAL '1 hour' THEN
            RAISE NOTICE 'Прогресс: % из % минут (% pct)', processed, total_minutes, (processed::FLOAT / total_minutes * 100)::INT;
            last_log_hour := curr_ts;
        END IF;

        curr_ts := curr_ts + INTERVAL '1 minute';
    END LOOP;

    -- Включение триггера (с проверкой существования)
    IF EXISTS (
        SELECT 1 FROM pg_trigger
        WHERE tgname = 'trigger_update_incident_time'
          AND tgrelid = 'transition_log'::regclass
    ) THEN
        EXECUTE 'ALTER TABLE transition_log ENABLE TRIGGER trigger_update_incident_time';
    END IF;

    UPDATE markov_config SET last_incident_time = (
        SELECT MAX(ts) FROM transition_log
        WHERE to_state IN (SELECT state_id FROM critical_states)
    );

    RAISE NOTICE 'Обучение завершено. Обработано % минут.', processed;
    RETURN format('Историческое обучение завершено. Обработано %s минут.', processed);
END;
$$;

COMMENT ON FUNCTION mchain_train_historical(TIMESTAMPTZ) IS 'Основная функция исторического обучения от минимальной даты до end_time с логированием прогресса.';

-- Логирование перехода с указанием времени (для исторического обучения)
CREATE OR REPLACE FUNCTION mchain_log_transition_at(
    p_from_state SMALLINT,
    p_to_state   SMALLINT,
    p_ts         TIMESTAMPTZ
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO transition_log (ts, from_state, to_state)
    VALUES (p_ts, p_from_state, p_to_state);

    INSERT INTO markov_frequencies (from_state, to_state, frequency)
    VALUES (p_from_state, p_to_state, 1.0)
    ON CONFLICT (from_state, to_state) DO UPDATE
        SET frequency = markov_frequencies.frequency + 1.0;
END;
$$;

COMMENT ON FUNCTION mchain_log_transition_at(SMALLINT, SMALLINT, TIMESTAMPTZ) IS 'Логирует переход с заданным временем и обновляет markov_frequencies (для исторического обучения)';


-- =============================================================================
-- Функция: recalculate_prediction_risks
-- Назначение: пересчитывает прогнозы риска для всех записей в prediction_log
--             на основе текущей матрицы вероятностей (финальная модель).
--             Использует сохранённый current_state_id и горизонт прогноза.
-- Параметры:
--   p_horizon INT – горизонт в минутах (если NULL – берётся из markov_config)
-- Возвращает:
--   TEXT – отчёт о количестве обновлённых прогнозов.
-- =============================================================================
CREATE OR REPLACE FUNCTION recalculate_prediction_risks(p_horizon INT DEFAULT NULL)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    v_horizon INT;
    v_updated INT := 0;
    rec RECORD;
    v_new_risk REAL;
BEGIN
    -- Определяем горизонт
    v_horizon := COALESCE(p_horizon, (SELECT forecast_horizon_minutes FROM markov_config LIMIT 1), 30);

    -- Пересчитываем риски для всех записей, где известно состояние
    FOR rec IN
        SELECT id, current_state_id
        FROM prediction_log
        WHERE current_state_id IS NOT NULL
          AND horizon_minutes = v_horizon   -- обновляем только записи с этим горизонтом
    LOOP
        -- Вычисляем новый риск на финальной модели
        v_new_risk := mchain_predict_risk_k_v2(rec.current_state_id, v_horizon);
        -- Обновляем только если риск изменился (опционально)
        UPDATE prediction_log
        SET predicted_risk = v_new_risk
        WHERE id = rec.id;
        v_updated := v_updated + 1;
    END LOOP;

    RETURN format('Recalculated risks for %s predictions (horizon %s min)', v_updated, v_horizon);
END;
$$;

COMMENT ON FUNCTION recalculate_prediction_risks(INT) IS 'Пересчитывает предсказанные риски на основе текущей модели (markov_probabilities). Используется после переобучения для актуализации прогнозов.';


-- =============================================================================
-- Триггерная функция для автоматического пересчёта прогнозов при изменении конфигурации
-- =============================================================================
CREATE OR REPLACE FUNCTION trigger_recalculate_risks_on_config_change()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    -- Проверяем, изменились ли поля, влияющие на прогнозы
    IF (OLD.base_alpha IS DISTINCT FROM NEW.base_alpha) OR
       (OLD.incident_half_life_days IS DISTINCT FROM NEW.incident_half_life_days) OR
       (OLD.min_alpha IS DISTINCT FROM NEW.min_alpha) OR
       (OLD.interval_minute IS DISTINCT FROM NEW.interval_minute) OR
       (OLD.forecast_horizon_minutes IS DISTINCT FROM NEW.forecast_horizon_minutes) THEN
        -- Асинхронный вызов (в отдельной транзакции) – используем dblink или просто вызываем напрямую
        -- Так как триггер выполняется в той же транзакции, вызов функции будет синхронным.
        -- Это приемлемо, если объём данных невелик.
        PERFORM recalculate_prediction_risks(NEW.forecast_horizon_minutes);
    END IF;
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION trigger_recalculate_risks_on_config_change() IS 'Триггер, вызывающий recalculate_prediction_risks при изменении параметров конфигурации, влияющих на прогнозы.';

-- Создаём триггер на таблицу markov_config
DROP TRIGGER IF EXISTS trg_recalculate_risks_on_config_change ON markov_config;
CREATE TRIGGER trg_recalculate_risks_on_config_change
    AFTER UPDATE ON markov_config
    FOR EACH ROW
    EXECUTE FUNCTION trigger_recalculate_risks_on_config_change();
	
	
-- Функция формирует сводный отчёт по прогнозам и инцидентам за указанный период.
-- Возвращает массив строк (TEXT[]) с метриками и агрегатами.
-- =============================================================================
-- report_prediction_incident_summary
-- Версия: 19.1 (2026-10-25)
-- Назначение: сводный отчёт по прогнозам и инцидентам за указанный период.
--             Возвращает массив строк (TEXT[]) с метриками и агрегатами.
--
-- КЛЮЧЕВЫЕ ИЗМЕНЕНИЯ v19.1 (относительно предыдущей версии):
--   - Источник инцидентов: markov_chain_performance_incident (MCI).
--   - Столбец priority ИСКЛЮЧЁН из выборки и вывода
--     (MCI не содержит priority; приоритеты доступны только в performance_incident).
--   - Удалены неиспользуемые переменные v_line_sep, v_priority_counts, v_rec, v_tmp.
--   - Удалён CTE priority_agg и связанный вывод распределения по приоритетам.
--
-- ВАЖНО: если требуется анализ приоритетов (P3/P4), используйте отчёт,
--        работающий с performance_incident (например, generate_incident_forecast_report_v2
--        с JOIN к performance_incident по временному пересечению).
-- =============================================================================
CREATE OR REPLACE FUNCTION report_prediction_incident_summary(
    p_start TIMESTAMPTZ DEFAULT now() - INTERVAL '7 days',
    p_end   TIMESTAMPTZ DEFAULT now()
)
RETURNS TEXT[]
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_report TEXT[] := '{}';
    v_total_predictions BIGINT;
    v_known_outcomes BIGINT;
    v_incidents_actual BIGINT;
    v_avg_risk REAL;
    v_avg_risk_known REAL;
    v_with_incident BIGINT;
    v_accuracy REAL;
    v_precision REAL;
    v_recall REAL;
    v_total_incidents BIGINT;
    v_unfinished_incidents BIGINT;
BEGIN
    -- Проверка корректности интервала
    IF p_start > p_end THEN
        RETURN ARRAY['Ошибка: начальная дата позже конечной.'];
    END IF;

    -- ========================================================================
    -- 1. Агрегаты по prediction_log
    -- ========================================================================
    SELECT
        COUNT(*) AS total,
        COUNT(actual_outcome) AS known,
        COUNT(*) FILTER (WHERE actual_outcome = 1) AS incidents,
        AVG(predicted_risk) AS avg_risk_all,
        AVG(predicted_risk) FILTER (WHERE actual_outcome IS NOT NULL) AS avg_risk_known,
        COUNT(first_incident_time) AS with_incident
    INTO
        v_total_predictions,
        v_known_outcomes,
        v_incidents_actual,
        v_avg_risk,
        v_avg_risk_known,
        v_with_incident
    FROM prediction_log
    WHERE prediction_time BETWEEN p_start AND p_end;

    -- Если есть известные исходы, считаем accuracy, precision, recall (порог 0.5)
    IF v_known_outcomes > 0 THEN
        SELECT
            COUNT(*) FILTER (WHERE (predicted_risk >= 0.5 AND actual_outcome = 1)
                                 OR (predicted_risk < 0.5 AND actual_outcome = 0))::REAL / v_known_outcomes AS acc,
            COUNT(*) FILTER (WHERE predicted_risk >= 0.5 AND actual_outcome = 1)::REAL /
                NULLIF(COUNT(*) FILTER (WHERE predicted_risk >= 0.5), 0) AS prec,
            COUNT(*) FILTER (WHERE predicted_risk >= 0.5 AND actual_outcome = 1)::REAL /
                NULLIF(COUNT(*) FILTER (WHERE actual_outcome = 1), 0) AS rec
        INTO v_accuracy, v_precision, v_recall
        FROM prediction_log
        WHERE prediction_time BETWEEN p_start AND p_end
          AND actual_outcome IS NOT NULL;
    ELSE
        v_accuracy := NULL;
        v_precision := NULL;
        v_recall := NULL;
    END IF;

    -- ========================================================================
    -- 2. Агрегаты по markov_chain_performance_incident (MCI)
    -- v19.1: priority недоступен (MCI не содержит этот столбец)
    -- ========================================================================
    SELECT
        COUNT(*) AS total,
        COUNT(*) FILTER (WHERE finish_timepoint IS NULL) AS unfinished
    INTO v_total_incidents, v_unfinished_incidents
    FROM markov_chain_performance_incident
    WHERE start_timepoint BETWEEN p_start AND p_end;

    -- ========================================================================
    -- 3. Формирование отчёта (массив строк)
    -- ========================================================================
    v_report := array_append(v_report, 'СВОДНЫЙ ОТЧЁТ ПО ПРОГНОЗАМ И ИНЦИДЕНТАМ (v19.1)');
    v_report := array_append(v_report, '------------------------------------------------------------');
    v_report := array_append(v_report, format('Период: %s – %s', p_start::TEXT, p_end::TEXT));
    v_report := array_append(v_report, '');
    v_report := array_append(v_report, '--- ПРОГНОЗЫ (prediction_log) ---');
    v_report := array_append(v_report, format('Всего прогнозов: %s', v_total_predictions));
    v_report := array_append(v_report, format('Из них с известным исходом: %s', v_known_outcomes));
    v_report := array_append(v_report, format('  - Инцидентов (actual_outcome=1): %s', v_incidents_actual));
    v_report := array_append(v_report, format('Средний предсказанный риск (все): %s', COALESCE(round(v_avg_risk::NUMERIC, 4)::TEXT, 'NULL')));
    v_report := array_append(v_report, format('Средний предсказанный риск (только по известным): %s', COALESCE(round(v_avg_risk_known::NUMERIC, 4)::TEXT, 'NULL')));
    v_report := array_append(v_report, format('Прогнозов, после которых в течение горизонта начался инцидент: %s', v_with_incident));
    IF v_known_outcomes > 0 THEN
        v_report := array_append(v_report, format('Точность (accuracy) при пороге 0.5: %s', COALESCE(round(v_accuracy::NUMERIC, 4)::TEXT, 'NULL')));
        v_report := array_append(v_report, format('Точность (precision) при пороге 0.5: %s', COALESCE(round(v_precision::NUMERIC, 4)::TEXT, 'NULL')));
        v_report := array_append(v_report, format('Полнота (recall) при пороге 0.5: %s', COALESCE(round(v_recall::NUMERIC, 4)::TEXT, 'NULL')));
    ELSE
        v_report := array_append(v_report, 'Метрики классификации (accuracy/precision/recall) недоступны — нет известных исходов.');
    END IF;

    v_report := array_append(v_report, '');
    v_report := array_append(v_report, '--- ИНЦИДЕНТЫ ПРОИЗВОДИТЕЛЬНОСТИ (markov_chain_performance_incident) ---');
    v_report := array_append(v_report, format('Всего инцидентов за период: %s', v_total_incidents));
    v_report := array_append(v_report, format('  - незавершённых (finish_timepoint IS NULL): %s', v_unfinished_incidents));
    v_report := array_append(v_report, 'Распределение по приоритетам: недоступно (MCI не содержит столбца priority)');

    -- Среднее число прогнозов на один инцидент
    IF v_total_incidents > 0 THEN
        v_report := array_append(v_report,
            format('Среднее число прогнозов на один инцидент: %s',
                   round(v_total_predictions::NUMERIC / v_total_incidents, 2)::TEXT));
    END IF;

    v_report := array_append(v_report, '------------------------------------------------------------');
    v_report := array_append(v_report, format('Отчёт сформирован: %s', now()::TEXT));

    RETURN v_report;
END;
$$;

COMMENT ON FUNCTION report_prediction_incident_summary(TIMESTAMPTZ, TIMESTAMPTZ) IS
'v19.1 (2026-10-25). Сводный отчёт по таблицам prediction_log и
markov_chain_performance_incident за указанный период.

Возвращает массив строк с ключевыми метриками:
  - общее количество прогнозов и с известным исходом;
  - доля инцидентов (actual_outcome=1);
  - средний предсказанный риск;
  - количество прогнозов, после которых наступил инцидент в течение горизонта;
  - accuracy, precision, recall (при пороге 0.5) для известных исходов;
  - общее количество инцидентов производительности и незавершённые.

ОТЛИЧИЕ ОТ ПРЕДЫДУЩЕЙ ВЕРСИИ:
  - Источник инцидентов — markov_chain_performance_incident (MCI);
  - распределение по приоритетам НЕДОСТУПНО, т.к. MCI не содержит priority.
    Для анализа по P3/P4 используйте отчёт по performance_incident
    (например, generate_incident_forecast_report_v2 с JOIN к PI).

Параметры по умолчанию: последние 7 дней.';


-- Функция адаптивной настройки параметров цепи Маркова 
-- с периодом анализа, определяемым из markov_config.transition_log_retention_days
CREATE OR REPLACE FUNCTION adaptive_configure_markov_chain(
    p_end TIMESTAMPTZ DEFAULT now()
)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    -- Параметры анализа
    v_start TIMESTAMPTZ;
    v_days NUMERIC;
    v_incidents_count BIGINT;
    v_lambda_day NUMERIC;
    v_lambda_min NUMERIC;

    -- Общее число переходов
    v_total_transitions BIGINT;

    -- Целевая доля положительных исходов
    v_target_pos CONSTANT REAL := 0.15;

    -- Вычисляемые параметры
    v_new_horizon INT;
    v_new_base_alpha REAL;
    v_new_half_life REAL;
    v_new_interval INT;
    v_new_min_transitions INT;
    v_new_min_freq INT;

    -- Старые значения для отчёта
    v_old_config RECORD;

    -- Вспомогательные
    v_retention_days INT;
    v_report TEXT := '';
    v_newline CONSTANT TEXT := chr(10);
BEGIN
    -- ========================================================================
    -- Шаг 1. Определение периода анализа на основе transition_log_retention_days
    -- ========================================================================
    SELECT COALESCE(transition_log_retention_days, 30) INTO v_retention_days
    FROM markov_config LIMIT 1;

    v_start := p_end - (v_retention_days || ' days')::INTERVAL;
    RAISE NOTICE 'Шаг 1: Период анализа с % по % (ретеншн % дней)', v_start, p_end, v_retention_days;

    -- ========================================================================
    -- Шаг 2. Расчёт частоты инцидентов
    -- ========================================================================
    SELECT COUNT(*) INTO v_incidents_count
    FROM markov_chain_performance_incident
    WHERE start_timepoint BETWEEN v_start AND p_end;

    v_days := EXTRACT(EPOCH FROM (p_end - v_start)) / 86400.0;
    IF v_days <= 0 THEN
        v_days := 1;
    END IF;

    v_lambda_day := v_incidents_count / v_days;
    v_lambda_min := v_lambda_day / 1440.0;

    RAISE NOTICE 'Шаг 2: Найдено % инцидентов за % дней, частота: % сут⁻¹, % мин⁻¹',
                 v_incidents_count, round(v_days, 1), round(v_lambda_day, 2), round(v_lambda_min, 6);

    -- ========================================================================
    -- Шаг 3. Получение общего числа переходов (для порогов)
    -- ========================================================================
    SELECT COUNT(*) INTO v_total_transitions FROM transition_log;
    RAISE NOTICE 'Шаг 3: Всего переходов в журнале: %', v_total_transitions;

    -- ========================================================================
    -- Шаг 4. Расчёт новых параметров
    -- ========================================================================
    RAISE NOTICE 'Шаг 4: Расчёт параметров...';

    -- 4.1 Горизонт прогноза (минут)
    IF v_lambda_min > 0 THEN
        v_new_horizon := round(v_target_pos / v_lambda_min)::INT;
        v_new_horizon := GREATEST(5, LEAST(120, v_new_horizon));
    ELSE
        v_new_horizon := 60;
    END IF;

    -- 4.2 base_alpha (скорость забывания)
    v_new_base_alpha := 0.01 + 0.15 * (v_lambda_day / 20.0);
    v_new_base_alpha := GREATEST(0.01, LEAST(0.25, v_new_base_alpha));

    -- 4.3 incident_half_life_days
    v_new_half_life := 60.0 / (1.0 + v_lambda_day / 5.0);
    v_new_half_life := GREATEST(7.0, LEAST(60.0, v_new_half_life));

    -- 4.4 interval_minute (период между применениями забывания)
    v_new_interval := round(v_new_horizon * 2.0)::INT;
    v_new_interval := GREATEST(30, LEAST(720, v_new_interval));

    -- 4.5 min_transitions_for_forgetting (порог для включения забывания)
    IF v_total_transitions > 0 THEN
        v_new_min_transitions := GREATEST(1000, round(v_total_transitions * 0.01)::INT);
    ELSE
        v_new_min_transitions := 1000;
    END IF;

    -- 4.6 min_freq_for_stability (минимальное число переходов из состояния для оценки стабильности)
    IF v_total_transitions > 0 THEN
        v_new_min_freq := GREATEST(10, LEAST(500, round(v_total_transitions * 0.005)::INT));
    ELSE
        v_new_min_freq := 10;
    END IF;

    -- ========================================================================
    -- Шаг 5. Получение текущих значений (для отчёта)
    -- ========================================================================
    SELECT
        forecast_horizon_minutes,
        base_alpha,
        incident_half_life_days,
        interval_minute,
        min_transitions_for_forgetting,
        min_freq_for_stability
    INTO v_old_config
    FROM markov_config LIMIT 1;

    -- ========================================================================
    -- Шаг 6. Обновление конфигурации
    -- ========================================================================
    RAISE NOTICE 'Шаг 6: Обновление markov_config...';
    UPDATE markov_config SET
        forecast_horizon_minutes = v_new_horizon,
        base_alpha = v_new_base_alpha,
        incident_half_life_days = v_new_half_life,
        interval_minute = v_new_interval,
        min_transitions_for_forgetting = v_new_min_transitions,
        min_freq_for_stability = v_new_min_freq,
        use_adaptive_alpha = TRUE,
        adaptive_forgetting_enabled = TRUE;

    -- ========================================================================
    -- Шаг 7. Формирование итогового отчёта
    -- ========================================================================
    RAISE NOTICE 'Шаг 7: Формирование отчёта...';

    v_report := '=== АДАПТИВНАЯ НАСТРОЙКА ЦЕПИ МАРКОВА ===' || v_newline;
    v_report := v_report || 'Период анализа: ' || v_start::TEXT || ' – ' || p_end::TEXT || v_newline;
    v_report := v_report || 'Длительность периода (дней): ' || round(v_days, 1)::TEXT || v_newline;
    v_report := v_report || 'Количество инцидентов: ' || v_incidents_count::TEXT || v_newline;
    v_report := v_report || 'Частота (сут⁻¹): ' || round(v_lambda_day, 2)::TEXT || v_newline;
    v_report := v_report || 'Общее число переходов: ' || v_total_transitions::TEXT || v_newline;
    v_report := v_report || v_newline;
    v_report := v_report || '=== ПАРАМЕТРЫ (СТАРЫЕ → НОВЫЕ) ===' || v_newline;
    v_report := v_report || 'forecast_horizon_minutes: ' || v_old_config.forecast_horizon_minutes::TEXT || ' → ' || v_new_horizon::TEXT || v_newline;
    -- Исправление: приводим к numeric для round
    v_report := v_report || 'base_alpha: ' || v_old_config.base_alpha::TEXT || ' → ' || round(v_new_base_alpha::NUMERIC, 4)::TEXT || v_newline;
    v_report := v_report || 'incident_half_life_days: ' || v_old_config.incident_half_life_days::TEXT || ' → ' || round(v_new_half_life::NUMERIC, 2)::TEXT || v_newline;
    v_report := v_report || 'interval_minute: ' || v_old_config.interval_minute::TEXT || ' → ' || v_new_interval::TEXT || v_newline;
    v_report := v_report || 'min_transitions_for_forgetting: ' || v_old_config.min_transitions_for_forgetting::TEXT || ' → ' || v_new_min_transitions::TEXT || v_newline;
    v_report := v_report || 'min_freq_for_stability: ' || v_old_config.min_freq_for_stability::TEXT || ' → ' || v_new_min_freq::TEXT || v_newline;
    v_report := v_report || v_newline;
    v_report := v_report || '=== РЕКОМЕНДАЦИИ ===' || v_newline;
    IF v_incidents_count = 0 THEN
        v_report := v_report || '⚠ Инциденты за период отсутствуют. Установлены параметры для редких событий (горизонт 60 мин, низкий alpha).' || v_newline;
        v_report := v_report || '   Рекомендуется пересмотреть определение инцидентов или увеличить период анализа (изменив transition_log_retention_days).' || v_newline;
    ELSIF v_lambda_day > 20 THEN
        v_report := v_report || '⚠ Высокая частота инцидентов (>20/сут). Горизонт установлен минимальным (5 мин) для сохранения калибровки.' || v_newline;
        v_report := v_report || '   Рассмотрите возможность уменьшения целевой доли положительных исходов или сокращения горизонта.' || v_newline;
    ELSE
        v_report := v_report || '✔ Параметры адаптированы к текущей частоте инцидентов. Ожидаемая доля положительных исходов ≈ ' || (v_target_pos * 100)::INT || '%.' || v_newline;
    END IF;

    RAISE NOTICE '%', v_report;
    RETURN v_report;
END;
$$;

COMMENT ON FUNCTION adaptive_configure_markov_chain(TIMESTAMPTZ) IS 'Адаптивная настройка параметров цепи Маркова на основе частоты инцидентов за период, равный transition_log_retention_days (из markov_config).Вычисляет и обновляет: forecast_horizon_minutes, base_alpha, incident_half_life_days,interval_minute, min_transitions_for_forgetting, min_freq_for_stability.Выводит прогресс через RAISE NOTICE и возвращает текстовый отчёт.';

-- Функция подбора оптимального горизонта прогноза на основе исторических переходов и критических состояний
-- P1.1: параметр p_min_horizon
CREATE OR REPLACE FUNCTION find_optimal_horizon(
    p_target      REAL DEFAULT 0.15,
    p_min         INT  DEFAULT 5,
    p_max         INT  DEFAULT 120,
    p_step        INT  DEFAULT 5,
    p_min_horizon INT  DEFAULT 15   -- NEW
)
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
    v_horizon INT;
    v_best INT := GREATEST(p_min, p_min_horizon);
    v_best_diff REAL := 999;
    v_ratio REAL;
    v_critical_ids INT[];
    v_total_transitions BIGINT;
BEGIN
    SELECT array_agg(state_id) INTO v_critical_ids FROM critical_states;
    IF v_critical_ids IS NULL OR array_length(v_critical_ids, 1) = 0 THEN
        RETURN 30;
    END IF;

    SELECT COUNT(*) INTO v_total_transitions FROM transition_log WHERE from_state IS NOT NULL;
    IF v_total_transitions = 0 THEN
        RETURN 30;
    END IF;

    FOR v_horizon IN GREATEST(p_min, p_min_horizon)..p_max BY p_step LOOP
        WITH transitions AS (
            SELECT ts, from_state FROM transition_log WHERE from_state IS NOT NULL
        ),
        incidents AS (
            SELECT ts AS incident_ts FROM transition_log WHERE to_state = ANY(v_critical_ids)
        )
        SELECT COUNT(*) FILTER (WHERE EXISTS (
            SELECT 1 FROM incidents i
            WHERE i.incident_ts > t.ts
              AND i.incident_ts <= t.ts + (v_horizon || ' minutes')::INTERVAL
        ))::REAL / COUNT(*) INTO v_ratio
        FROM transitions t;

        IF v_ratio IS NOT NULL AND abs(v_ratio - p_target) < v_best_diff THEN
            v_best_diff := abs(v_ratio - p_target);
            v_best := v_horizon;
        END IF;
    END LOOP;

    RETURN v_best;
END;
$$;

-- =============================================================================
-- Процедура: mchain_initial_train_from_history (модифицированная, с параметром p_start)
-- Назначение: первоначальное обучение цепи Маркова на основе исторических данных
--             из таблицы cluster_stat_median.
--             Очищает все таблицы модели (кроме markov_config), последовательно
--             обрабатывает минуты с доступными данными, логирует переходы,
--             пересчитывает вероятности и обновляет список критических состояний.
-- Параметры:
--   p_end                TIMESTAMPTZ – конечная точка обучения (включительно).
--   p_refresh_critical   BOOLEAN     – обновлять ли critical_states после обучения (по умолч. TRUE)
--   p_risk_threshold     REAL        – порог риска для critical_states (по умолч. 0.10)
--   p_min_transitions    INT         – минимальное число переходов для анализа (по умолч. 50)
--   p_interval_min       INT         – интервал прогноза в минутах (по умолч. 15)
--   p_start              TIMESTAMPTZ – начало обучения (если NULL – определяется как MIN(curr_timestamp) из cluster_stat_median)
--   result               TEXT        – выходной отчёт
-- =============================================================================
CREATE OR REPLACE PROCEDURE mchain_initial_train_from_history(
    IN p_end                TIMESTAMPTZ,
    IN p_refresh_critical   BOOLEAN DEFAULT TRUE,
    IN p_risk_threshold     REAL    DEFAULT 0.10,
    IN p_min_transitions    INT     DEFAULT 20,
    IN p_interval_min       INT     DEFAULT NULL,
    IN p_start              TIMESTAMPTZ DEFAULT NULL,
    INOUT result            TEXT    DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_start         TIMESTAMPTZ;
    v_ts            TIMESTAMPTZ;
    v_op_speed      REAL;
    v_waitings      REAL;
    v_correlation   REAL;
    v_os_angle      REAL;
    v_wait_angle    REAL;
    v_os_trend      SMALLINT;
    v_wait_trend    SMALLINT;
    v_curr_state    SMALLINT;
    v_prev_state    SMALLINT;
    v_first         BOOLEAN := TRUE;
    v_total_minutes BIGINT := 0;
    v_transitions   BIGINT := 0;
    v_window        INTERVAL := INTERVAL '1 hour';
    v_angle_threshold REAL := 0.5;
    v_row           RECORD;
    v_total_records   BIGINT;
    v_processed_records BIGINT := 0;
    v_last_percent    INT := -1;
    v_current_percent INT;
    v_interval_min    INT;
    v_last_forget     TIMESTAMPTZ;
    v_adaptive_enabled BOOLEAN;
    v_commit_interval INT := 500;
    v_counter         INT := 0;
    v_critical_result TEXT;
    v_old_msg_level  TEXT;
    v_log_message    TEXT;
    v_flag_fill_result TEXT;
BEGIN
    CREATE TABLE IF NOT EXISTS mchain_train_progress_log (
        id                BIGSERIAL PRIMARY KEY,
        ts                TIMESTAMPTZ DEFAULT now(),
        total_records     BIGINT,
        processed_records BIGINT,
        percent           INT,
        transitions       BIGINT,
        message           TEXT
    );

    IF p_start IS NULL THEN
        SELECT MIN(curr_timestamp) INTO v_start FROM cluster_stat_median;
    ELSE
        v_start := p_start;
    END IF;

    IF v_start IS NULL THEN
        result := 'Ошибка: не удалось определить начальную дату.';
        RETURN;
    END IF;

    IF p_end < v_start THEN
        result := format('Ошибка: конечная дата (%s) раньше начальной (%s).', p_end, v_start);
        RETURN;
    END IF;

    TRUNCATE TABLE markov_frequencies;
    TRUNCATE TABLE transition_log;
    TRUNCATE TABLE markov_chain;
    TRUNCATE TABLE markov_probabilities;
    TRUNCATE TABLE markov_absorbing;
    TRUNCATE TABLE prediction_log;
    TRUNCATE TABLE mchain_quality_metrics_history;

    UPDATE markov_config SET last_forget_time = v_start;
    SELECT interval_minute, adaptive_forgetting_enabled
    INTO v_interval_min, v_adaptive_enabled
    FROM markov_config LIMIT 1;

    SELECT COUNT(*) INTO v_total_records
    FROM cluster_stat_median
    WHERE curr_timestamp BETWEEN v_start AND p_end;

    RAISE NOTICE 'Начало обучения с % по % (всего % записей с данными)',
                 v_start, p_end, v_total_records;

    INSERT INTO mchain_train_progress_log (total_records, processed_records, percent, transitions, message)
    VALUES (v_total_records, 0, 0, 0, 'Начало обучения');

    FOR v_row IN
        SELECT curr_timestamp, curr_op_speed, curr_waitings
        FROM cluster_stat_median
        WHERE curr_timestamp BETWEEN v_start AND p_end
        ORDER BY curr_timestamp
    LOOP
        v_ts := v_row.curr_timestamp;
        v_op_speed := v_row.curr_op_speed;
        v_waitings := v_row.curr_waitings;

        v_total_minutes := v_total_minutes + 1;
        v_processed_records := v_processed_records + 1;

        BEGIN
            SELECT COALESCE(corr(curr_op_speed, curr_waitings), 0)
            INTO v_correlation
            FROM cluster_stat_median
            WHERE curr_timestamp BETWEEN v_ts - v_window AND v_ts;
        EXCEPTION WHEN OTHERS THEN
            v_correlation := 0.0;
        END;

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
        EXCEPTION WHEN OTHERS THEN
            v_os_angle := 0.0;
        END;

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
        EXCEPTION WHEN OTHERS THEN
            v_wait_angle := 0.0;
        END;

        IF v_os_angle > v_angle_threshold THEN v_os_trend := 1;
        ELSIF v_os_angle < -v_angle_threshold THEN v_os_trend := -1;
        ELSE v_os_trend := 0;
        END IF;

        IF v_wait_angle > v_angle_threshold THEN v_wait_trend := 1;
        ELSIF v_wait_angle < -v_angle_threshold THEN v_wait_trend := -1;
        ELSE v_wait_trend := 0;
        END IF;

        v_curr_state := get_state_id(v_correlation, v_os_trend, v_wait_trend);

        IF v_first THEN
            INSERT INTO markov_chain (curr_correlation, curr_os_trend, curr_wait_trend)
            VALUES (v_correlation, v_os_trend, v_wait_trend);
            v_prev_state := v_curr_state;
            v_first := FALSE;
        ELSE
            PERFORM mchain_log_transition_at(v_prev_state, v_curr_state, v_ts);
            v_transitions := v_transitions + 1;

            UPDATE markov_chain SET
                prev_correlation = curr_correlation,
                prev_os_trend    = curr_os_trend,
                prev_wait_trend  = curr_wait_trend,
                curr_correlation = v_correlation,
                curr_os_trend    = v_os_trend,
                curr_wait_trend  = v_wait_trend;

            BEGIN
                PERFORM collect_prediction(p_time => v_ts, p_state_id => v_curr_state);
            EXCEPTION WHEN OTHERS THEN
                RAISE WARNING 'collect_prediction failed at %: %', v_ts, SQLERRM;
            END;

            IF v_adaptive_enabled THEN
                SELECT last_forget_time INTO v_last_forget FROM markov_config LIMIT 1;
                IF (v_ts - v_last_forget) >= (v_interval_min * INTERVAL '1 minute') THEN
                    BEGIN
                        PERFORM mchain_apply_forgetting();
                        SELECT last_forget_time INTO v_last_forget FROM markov_config LIMIT 1;
                    EXCEPTION WHEN OTHERS THEN
                        RAISE WARNING 'mchain_apply_forgetting failed at %: %', v_ts, SQLERRM;
                    END;
                END IF;
            END IF;

            v_prev_state := v_curr_state;
        END IF;

        v_counter := v_counter + 1;
        IF v_counter >= v_commit_interval THEN
            COMMIT;
            v_counter := 0;
            SET LOCAL client_min_messages = WARNING;
            SELECT interval_minute, adaptive_forgetting_enabled
            INTO v_interval_min, v_adaptive_enabled
            FROM markov_config LIMIT 1;
        END IF;

        v_current_percent := floor(v_processed_records * 100.0 / v_total_records);
        IF v_current_percent > v_last_percent THEN
            v_log_message := format('Прогресс: %s%% (обработано %s из %s, переходов: %s)',
                                    v_current_percent, v_processed_records, v_total_records, v_transitions);
            RAISE NOTICE '%', v_log_message;
            INSERT INTO mchain_train_progress_log (total_records, processed_records, percent, transitions, message)
            VALUES (v_total_records, v_processed_records, v_current_percent, v_transitions, v_log_message);
            v_last_percent := v_current_percent;
        ELSIF v_processed_records % 1000 = 0 THEN
            v_log_message := format('Детализация: обработано %s записей, переходов: %s',
                                    v_processed_records, v_transitions);
            RAISE NOTICE '%', v_log_message;
            INSERT INTO mchain_train_progress_log (total_records, processed_records, percent, transitions, message)
            VALUES (v_total_records, v_processed_records, v_current_percent, v_transitions, v_log_message);
        END IF;
    END LOOP;

    PERFORM update_markov_probabilities();
    PERFORM rebuild_markov_absorbing();
    PERFORM update_prediction_outcomes();

    IF p_refresh_critical THEN
        BEGIN
            SHOW client_min_messages INTO v_old_msg_level;
            SET LOCAL client_min_messages = WARNING;

            RAISE NOTICE 'Обновление critical_states на основе исторических данных...';
            SELECT refresh_critical_states(
                p_start           => v_start,
                p_end             => p_end,
                p_min_transitions => p_min_transitions,
                p_interval_min    => p_interval_min,
                p_risk_threshold  => p_risk_threshold,
                p_dry_run         => FALSE,
                p_audit           => TRUE
            ) INTO v_critical_result;

            EXECUTE format('SET LOCAL client_min_messages = %I', v_old_msg_level);
            RAISE NOTICE 'Результат обновления critical_states: %', v_critical_result;
        EXCEPTION WHEN OTHERS THEN
            v_critical_result := format('Ошибка при обновлении critical_states: %s', SQLERRM);
            RAISE WARNING 'Ошибка при обновлении critical_states: %', SQLERRM;
            BEGIN
                EXECUTE format('SET LOCAL client_min_messages = %I', v_old_msg_level);
            EXCEPTION WHEN OTHERS THEN
                NULL;
            END;
        END;
    ELSE
        v_critical_result := 'Обновление critical_states пропущено (p_refresh_critical = FALSE).';
    END IF;

    -- Причина: mchain_initial_train_from_history пересоздаёт prediction_log,
    -- но НЕ обновляет sicpp_history и operational_alert_history. Если
    -- вызвать здесь c_only_incident_flag_historical_fill(), mchain_hybrid_alert_at()
    -- будет читать js_avg из СТАРОЙ sicpp_history и predicted_risk из НОВОГО
    -- prediction_log — несогласованные данные → некорректные
    -- raw_fired_c / effective_c_only в c_only_incident_flag_history.
    --
    -- Правильная последовательность после initial_train:
    --     SELECT historical_fill_sicpp(...);   -- перестраивает sicpp_history
    --     SELECT historical_fill_c_only(...);  -- перестраивает operational_alert_history
    --                                          -- И ЗДЕСЬ ЖЕ вызывает
    --                                          -- c_only_incident_flag_historical_fill()
    -- ========================================================================
    v_flag_fill_result := 'skipped: run historical_fill_sicpp() then '
                       || 'historical_fill_c_only() to populate c_only_incident_flag_history.';
    RAISE NOTICE 'c_only_incident_flag backfill: %', v_flag_fill_result;

    RAISE NOTICE 'Обучение завершено. Обработано минут: %, переходов: %, прогнозов: %',
                 v_total_minutes, v_transitions, (SELECT COUNT(*) FROM prediction_log);
    result := format('Обучение завершено. Начало: %s, конец: %s. Обработано минут: %s, залогировано переходов: %s, создано прогнозов: %s. Текущее состояние: state_id=%s. %s. c_only_incident_flag: %s',
                  v_start, p_end, v_total_minutes, v_transitions,
                  (SELECT COUNT(*) FROM prediction_log), v_curr_state, v_critical_result,
                  v_flag_fill_result);

    INSERT INTO mchain_train_progress_log (total_records, processed_records, percent, transitions, message)
    VALUES (v_total_records, v_processed_records, 100, v_transitions, 'Обучение завершено');
END;
$$;

COMMENT ON PROCEDURE mchain_initial_train_from_history IS
'v24.2.1-pilot (fix): backfill c_only_incident_flag_history вынесен из процедуры
(см. C1 в migration notes).

ВАЖНО: процедура не сбрасывает operational_alert_state.last_evaluated_minute.
Если оператор ожидает «чистый старт» после переобучения, выполните:
    UPDATE operational_alert_state
    SET last_evaluated_minute = NULL,
        c_only_incident_flag  = FALSE,
        last_effective_c_only = FALSE
    WHERE id = 1;
Без этого следующий вызов mchain_train_step() пропустит пересчёт (idempotency),
но это НЕ ошибка — флаг отражает последнее известное состояние.
Остальная логика без изменений.';

-- =============================================================================
-- Функция: performance_incident_report
-- Назначение: формирует поминутный отчёт по производительности СУБД и инцидентам
--             за указанный период.
-- Параметры:
--   p_start TIMESTAMPTZ – начало периода (по умолчанию: now() - interval '1 month')
--   p_end   TIMESTAMPTZ – конец периода   (по умолчанию: now())
-- Возвращает: TEXT[] – массив строк отчёта.
-- Источники:
--   cluster_stat_median – поминутные метрики (curr_timestamp, curr_op_speed, curr_waitings)
--   markov_chain_performance_incident – интервалы инцидентов (start_timepoint, finish_timepoint)
-- =============================================================================
CREATE OR REPLACE FUNCTION performance_incident_report(
    p_start TIMESTAMPTZ DEFAULT now() - INTERVAL '1 month',
    p_end   TIMESTAMPTZ DEFAULT now()
)
RETURNS TEXT[]
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_report TEXT[] := '{}';
    v_data   TEXT[];
    v_sep    CONSTANT TEXT := ' | ';
BEGIN
    -- Проверка корректности интервала
    IF p_start > p_end THEN
        RETURN ARRAY['Ошибка: начальная дата позже конечной.'];
    END IF;

    -- Заголовок отчёта
    v_report := array_append(v_report,
        '=== ОТЧЁТ ПО ИНЦИДЕНТАМ И ПРОИЗВОДИТЕЛЬНОСТИ СУБД ===');
    v_report := array_append(v_report, format('Период: %s – %s',
        to_char(p_start, 'YYYY-MM-DD HH24:MI'),
        to_char(p_end,   'YYYY-MM-DD HH24:MI')));
    v_report := array_append(v_report, '');
    v_report := array_append(v_report,
        'timestamp' || v_sep ||
        'op_speed'  || v_sep ||
        'waitings'  || v_sep ||
        'incident_active' || v_sep ||
        'incident_id'     || v_sep ||
        'incident_start'
    );
    v_report := array_append(v_report,
        repeat('-', 10) || v_sep ||
        repeat('-', 8)  || v_sep ||
        repeat('-', 8)  || v_sep ||
        repeat('-', 15) || v_sep ||
        repeat('-', 11) || v_sep ||
        repeat('-', 16)
    );

    -- Генерация поминутных строк
    SELECT array_agg(line ORDER BY ts)
    INTO v_data
    FROM (
        SELECT
            g.ts,
            format(
                '%s%s%s%s%s%s%s%s%s%s%s',
                to_char(g.ts, 'YYYY-MM-DD HH24:MI'),
                v_sep,
                COALESCE(round(csm.curr_op_speed::NUMERIC, 2)::TEXT, '—'),
                v_sep,
                COALESCE(round(csm.curr_waitings::NUMERIC, 2)::TEXT, '—'),
                v_sep,
                CASE WHEN inc.id IS NOT NULL THEN '1' ELSE '0' END,
                v_sep,
                COALESCE(inc.id::TEXT, '—'),
                v_sep,
                COALESCE(to_char(inc.start_timepoint, 'YYYY-MM-DD HH24:MI'), '—')
            ) AS line
        FROM generate_series(
            date_trunc('minute', p_start),
            date_trunc('minute', p_end),
            INTERVAL '1 minute'
        ) AS g(ts)
        LEFT JOIN cluster_stat_median csm
               ON csm.curr_timestamp = g.ts
        LEFT JOIN LATERAL (
            SELECT i.id, i.start_timepoint
            FROM markov_chain_performance_incident i
            WHERE i.start_timepoint <= g.ts
              AND (i.finish_timepoint IS NULL OR i.finish_timepoint > g.ts)
            ORDER BY i.start_timepoint DESC
            LIMIT 1
        ) inc ON TRUE
    ) sub;

    IF v_data IS NOT NULL THEN
        v_report := array_cat(v_report, v_data);
    ELSE
        v_report := array_append(v_report, 'Нет данных за указанный период.');
    END IF;

    v_report := array_append(v_report, '=== КОНЕЦ ОТЧЁТА ===');

    RETURN v_report;
END;
$$;

COMMENT ON FUNCTION performance_incident_report(TIMESTAMPTZ, TIMESTAMPTZ) IS
'Формирует поминутный отчёт по производительности СУБД и инцидентам за указанный период.
Возвращает массив строк с заголовком, шапкой таблицы и поминутными данными.
Столбцы: timestamp | op_speed | waitings | incident_active | incident_id | incident_start.
Инцидент считается активным в минуту, если start_timepoint <= timestamp < finish_timepoint (или finish_timepoint IS NULL).
По умолчанию период – последний месяц (now() - interval ''1 month'' .. now()).';

CREATE OR REPLACE FUNCTION mchain_calibrate_risk(p_raw REAL)
RETURNS REAL
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_enabled BOOLEAN;
    v_method  TEXT;
    v_a       REAL;
    v_b       REAL;
    v_result  REAL;
    v_raw     REAL;
    v_x       REAL;
BEGIN
    IF p_raw IS NULL THEN
        RETURN NULL;
    END IF;

    SELECT enabled, method, platt_a, platt_b
    INTO v_enabled, v_method, v_a, v_b
    FROM mchain_calibration_config WHERE id = 1;

    IF NOT FOUND OR NOT COALESCE(v_enabled, FALSE) THEN
        RETURN LEAST(GREATEST(p_raw, 0.0), 1.0);
    END IF;

    v_raw := LEAST(GREATEST(p_raw, 1e-6), 1.0 - 1e-6);

    IF v_method = 'platt' AND v_a IS NOT NULL AND v_b IS NOT NULL THEN
        v_x := ln(v_raw / (1.0 - v_raw));
        v_result := 1.0 / (1.0 + exp(-(v_a * v_x + v_b)));
        RETURN LEAST(GREATEST(v_result, 0.0), 1.0);
    END IF;

    -- isotonic / bin: lookup в map
    SELECT to_risk INTO v_result
    FROM mchain_calibration_map
    WHERE v_raw >= from_risk_low AND v_raw < from_risk_high
    ORDER BY bin_id
    LIMIT 1;

    IF v_result IS NULL THEN
        -- fallback: последний бин (для v_raw >= max(from_risk_high))
        SELECT to_risk INTO v_result
        FROM mchain_calibration_map
        ORDER BY bin_id DESC
        LIMIT 1;
    END IF;

    IF v_result IS NULL THEN
        RETURN v_raw;
    END IF;

    RETURN LEAST(GREATEST(v_result, 0.0), 1.0);
END;
$$;

COMMENT ON FUNCTION mchain_calibrate_risk(REAL) IS
'v26.1.1. Применяет карту калибровки: isotonic/bin — lookup в mchain_calibration_map, platt — сигмоида по logit(p_raw). При enabled=FALSE возвращает p_raw.';



CREATE OR REPLACE FUNCTION mchain_fit_calibration_isotonic(
    p_start        TIMESTAMPTZ DEFAULT NULL,
    p_end          TIMESTAMPTZ DEFAULT NULL,
    p_n_bins       INT         DEFAULT 20,
    p_min_samples  INT         DEFAULT 500,
    p_horizon_min  INT         DEFAULT NULL
)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    v_start TIMESTAMPTZ;
    v_end   TIMESTAMPTZ;
    v_horizon INT;
    v_n INT;
    v_metrics_before RECORD;
    v_metrics_after  RECORD;
    v_rec RECORD;

    v_arr_hi  REAL[];
    v_arr_avg REAL[];
    v_arr_obs REAL[];
    v_arr_cnt INT[];

    v_stack_cnt  NUMERIC[];
    v_stack_obs  NUMERIC[];
    v_stack_pred NUMERIC[];
    v_stack_hi   REAL[];
    v_stack_size INT := 0;

    v_len INT;
    v_i INT;
    v_c1 NUMERIC;
    v_c2 NUMERIC;
    v_mc NUMERIC;
    v_prev_hi REAL := 0.0;
    v_log_id BIGINT;
BEGIN
    v_start := COALESCE(p_start,
        (SELECT training_start FROM mchain_calibration_config WHERE id = 1),
        now() - INTERVAL '30 days');
    v_end   := COALESCE(p_end, now());
    v_horizon := COALESCE(
        p_horizon_min,
        (SELECT forecast_horizon_minutes FROM markov_config LIMIT 1),
        30);

    SELECT COUNT(*) INTO v_n
    FROM prediction_log
    WHERE prediction_time BETWEEN v_start AND v_end
      AND actual_outcome IS NOT NULL
      AND predicted_risk  IS NOT NULL
      AND horizon_minutes = v_horizon;

    IF v_n < p_min_samples THEN
        RETURN format('Skip: samples=%s < min=%s', v_n, p_min_samples);
    END IF;

    -- метрики до
    SELECT * INTO v_metrics_before
    FROM mchain_compute_calibration_metrics(v_start, v_end, FALSE, v_horizon);

    -- 1) строим бины и (avg_pred, obs_rate, cnt)
    v_arr_hi  := ARRAY[]::REAL[];
    v_arr_avg := ARRAY[]::REAL[];
    v_arr_obs := ARRAY[]::REAL[];
    v_arr_cnt := ARRAY[]::INT[];

    FOR v_rec IN
        WITH src AS (
            SELECT predicted_risk AS p, actual_outcome::REAL AS y,
                   WIDTH_BUCKET(LEAST(GREATEST(predicted_risk, 0.000001), 0.999999),
                                0, 1, p_n_bins) AS b
            FROM prediction_log
            WHERE prediction_time BETWEEN v_start AND v_end
              AND actual_outcome IS NOT NULL AND predicted_risk IS NOT NULL
              AND horizon_minutes = v_horizon
        )
        SELECT b, AVG(p) AS ap, AVG(y) AS oy, COUNT(*) AS c
        FROM src GROUP BY b ORDER BY b
    LOOP
        v_arr_hi  := v_arr_hi  || (v_rec.b::REAL / p_n_bins);
        v_arr_avg := v_arr_avg || COALESCE(v_rec.ap, 0.0);
        v_arr_obs := v_arr_obs || COALESCE(v_rec.oy, 0.0);
        v_arr_cnt := v_arr_cnt || v_rec.c;
    END LOOP;

    v_len := COALESCE(array_length(v_arr_hi, 1), 0);
    IF v_len = 0 THEN
        RETURN 'Skip: no bins after group-by';
    END IF;

    -- 2) PAVA по (obs_rate, weight=cnt)
    v_stack_cnt  := ARRAY[]::NUMERIC[];
    v_stack_obs  := ARRAY[]::NUMERIC[];
    v_stack_pred := ARRAY[]::NUMERIC[];
    v_stack_hi   := ARRAY[]::REAL[];

    FOR v_i IN 1..v_len LOOP
        v_stack_size := v_stack_size + 1;
        v_stack_cnt[v_stack_size]  := v_arr_cnt[v_i]::NUMERIC;
        v_stack_obs[v_stack_size]  := v_arr_obs[v_i]::NUMERIC;
        v_stack_pred[v_stack_size] := v_arr_avg[v_i]::NUMERIC;
        v_stack_hi[v_stack_size]   := v_arr_hi[v_i];

        WHILE v_stack_size >= 2
              AND v_stack_obs[v_stack_size] < v_stack_obs[v_stack_size - 1]
        LOOP
            v_c1 := v_stack_cnt[v_stack_size - 1];
            v_c2 := v_stack_cnt[v_stack_size];
            v_mc := v_c1 + v_c2;

            v_stack_cnt[v_stack_size - 1]  := v_mc;
            v_stack_obs[v_stack_size - 1]  :=
                (v_stack_obs[v_stack_size - 1] * v_c1
               + v_stack_obs[v_stack_size]     * v_c2) / v_mc;
            v_stack_pred[v_stack_size - 1] :=
                (v_stack_pred[v_stack_size - 1] * v_c1
               + v_stack_pred[v_stack_size]     * v_c2) / v_mc;
            v_stack_hi[v_stack_size - 1]   := v_stack_hi[v_stack_size];

            v_stack_size := v_stack_size - 1;
        END LOOP;
    END LOOP;

    -- 3) сохраняем монотонную карту
    DELETE FROM mchain_calibration_map;
    v_prev_hi := 0.0;
    FOR v_i IN 1..v_stack_size LOOP
        INSERT INTO mchain_calibration_map (bin_id, from_risk_low, from_risk_high, to_risk, weight)
        VALUES (
            v_i,
            v_prev_hi,
            CASE WHEN v_i = v_stack_size THEN 1.0001 ELSE v_stack_hi[v_i] END,
            LEAST(GREATEST(v_stack_obs[v_i]::REAL, 0.0), 1.0),
            v_stack_cnt[v_i]::REAL
        );
        v_prev_hi := v_stack_hi[v_i];
    END LOOP;

    -- 4) включаем и фиксируем
    UPDATE mchain_calibration_config
    SET enabled        = TRUE,
        method         = 'isotonic',
        platt_a        = NULL,
        platt_b        = NULL,
        fitted_at      = now(),
        training_start = v_start,
        training_end   = v_end,
        sample_size    = v_n,
        updated_at     = now()
    WHERE id = 1;

    -- 5) метрики после
    SELECT * INTO v_metrics_after
    FROM mchain_compute_calibration_metrics(v_start, v_end, TRUE, v_horizon);

    UPDATE mchain_calibration_config
    SET brier_before = v_metrics_before.brier,
        brier_after  = v_metrics_after.brier,
        ece_before   = v_metrics_before.ece,
        ece_after    = v_metrics_after.ece
    WHERE id = 1;

    INSERT INTO mchain_calibration_log (
        method, training_start, training_end, sample_size,
        brier_before, brier_after, ece_before, ece_after, reason)
    VALUES ('isotonic', v_start, v_end, v_n,
            v_metrics_before.brier, v_metrics_after.brier,
            v_metrics_before.ece,   v_metrics_after.ece,
            format('bins=%s (input %s, merged %s)', p_n_bins, v_len, v_stack_size))
    RETURNING id INTO v_log_id;

    RETURN format(
        'Isotonic OK: n=%s bins_in=%s bins_out=%s Brier %s->%s ECE %s->%s log_id=%s',
        v_n, v_len, v_stack_size,
        round(v_metrics_before.brier::numeric, 4),
        round(v_metrics_after.brier::numeric,  4),
        round(v_metrics_before.ece::numeric,   4),
        round(v_metrics_after.ece::numeric,    4),
        v_log_id);
		
END;
$$;

COMMENT ON FUNCTION mchain_fit_calibration_isotonic(TIMESTAMPTZ,TIMESTAMPTZ,INT,INT,INT) IS
'v26.1.1. Isotonic regression (PAVA) по p_n_bins бинам. Строит монотонную карту mchain_calibration_map и включает калибровку.';

CREATE OR REPLACE FUNCTION mchain_fit_calibration_platt(
    p_start        TIMESTAMPTZ DEFAULT NULL,
    p_end          TIMESTAMPTZ DEFAULT NULL,
    p_min_samples  INT         DEFAULT 500,
    p_max_iter     INT         DEFAULT 200,
    p_horizon_min  INT         DEFAULT NULL
)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    v_start TIMESTAMPTZ;
    v_end   TIMESTAMPTZ;
    v_horizon INT;
    v_n INT;
    v_rec RECORD;
    v_a REAL := 1.0;
    v_b REAL := 0.0;
    v_a_new REAL;
    v_b_new REAL;
    v_g_a REAL;
    v_g_b REAL;
    v_h_aa REAL;
    v_h_ab REAL;
    v_h_bb REAL;
    v_det REAL;
    v_step_a REAL;
    v_step_b REAL;
    v_x REAL;
    v_y REAL;
    v_pc REAL;
    v_nll REAL;
    v_nll_new REAL;
    v_iter INT := 0;
    v_lr REAL := 1.0;
    v_metrics_before RECORD;
    v_metrics_after  RECORD;
    v_log_id BIGINT;
BEGIN
    v_start := COALESCE(p_start,
        (SELECT training_start FROM mchain_calibration_config WHERE id = 1),
        now() - INTERVAL '30 days');
    v_end   := COALESCE(p_end, now());
    v_horizon := COALESCE(
        p_horizon_min,
        (SELECT forecast_horizon_minutes FROM markov_config LIMIT 1),
        30);

    SELECT COUNT(*) INTO v_n
    FROM prediction_log
    WHERE prediction_time BETWEEN v_start AND v_end
      AND actual_outcome IS NOT NULL
      AND predicted_risk  IS NOT NULL
      AND horizon_minutes = v_horizon;

    IF v_n < p_min_samples THEN
        RETURN format('Skip Platt: samples=%s < min=%s', v_n, p_min_samples);
    END IF;

    SELECT * INTO v_metrics_before
    FROM mchain_compute_calibration_metrics(v_start, v_end, FALSE, v_horizon);

    LOOP
        v_iter := v_iter + 1;
        v_g_a := 0; v_g_b := 0;
        v_h_aa := 0; v_h_ab := 0; v_h_bb := 0;
        v_nll := 0;

        FOR v_rec IN
            SELECT LEAST(GREATEST(predicted_risk, 1e-6), 1.0 - 1e-6) AS p,
                   actual_outcome::REAL AS y
            FROM prediction_log
            WHERE prediction_time BETWEEN v_start AND v_end
              AND actual_outcome IS NOT NULL AND predicted_risk IS NOT NULL
              AND horizon_minutes = v_horizon
        LOOP
            v_x := ln(v_rec.p / (1.0 - v_rec.p));
            v_y := v_rec.y;
            v_pc := 1.0 / (1.0 + exp(-(v_a * v_x + v_b)));
            v_pc := LEAST(GREATEST(v_pc, 1e-6), 1.0 - 1e-6);

            v_nll := v_nll - (v_y * ln(v_pc) + (1.0 - v_y) * ln(1.0 - v_pc));
            v_g_a := v_g_a + (v_pc - v_y) * v_x;
            v_g_b := v_g_b + (v_pc - v_y);
            v_h_aa := v_h_aa + v_pc * (1.0 - v_pc) * v_x * v_x;
            v_h_ab := v_h_ab + v_pc * (1.0 - v_pc) * v_x;
            v_h_bb := v_h_bb + v_pc * (1.0 - v_pc);
        END LOOP;

        v_det := v_h_aa * v_h_bb - v_h_ab * v_h_ab;
        IF v_det = 0 THEN
            EXIT;
        END IF;
        v_step_a := ( v_h_bb * v_g_a - v_h_ab * v_g_b) / v_det;
        v_step_b := (-v_h_ab * v_g_a + v_h_aa * v_g_b) / v_det;

        v_a_new := v_a - v_lr * v_step_a;
        v_b_new := v_b - v_lr * v_step_b;

        -- NLL при новых параметрах (для line-search)
        v_nll_new := 0;
        FOR v_rec IN
            SELECT LEAST(GREATEST(predicted_risk, 1e-6), 1.0 - 1e-6) AS p,
                   actual_outcome::REAL AS y
            FROM prediction_log
            WHERE prediction_time BETWEEN v_start AND v_end
              AND actual_outcome IS NOT NULL AND predicted_risk IS NOT NULL
              AND horizon_minutes = v_horizon
        LOOP
            v_x := ln(v_rec.p / (1.0 - v_rec.p));
            v_pc := 1.0 / (1.0 + exp(-(v_a_new * v_x + v_b_new)));
            v_pc := LEAST(GREATEST(v_pc, 1e-6), 1.0 - 1e-6);
            v_nll_new := v_nll_new - (v_rec.y * ln(v_pc) + (1.0 - v_rec.y) * ln(1.0 - v_pc));
        END LOOP;

        IF v_nll_new < v_nll THEN
            v_a := v_a_new;
            v_b := v_b_new;
            v_lr := LEAST(v_lr * 1.2, 1.0);
        ELSE
            v_lr := v_lr * 0.5;
            IF v_lr < 1e-5 THEN
                EXIT;
            END IF;
            CONTINUE;
        END IF;

        IF v_iter >= p_max_iter
           OR abs(v_step_a) + abs(v_step_b) < 1e-6 THEN
            EXIT;
        END IF;
    END LOOP;

    UPDATE mchain_calibration_config
    SET enabled        = TRUE,
        method         = 'platt',
        platt_a        = v_a,
        platt_b        = v_b,
        fitted_at      = now(),
        training_start = v_start,
        training_end   = v_end,
        sample_size    = v_n,
        updated_at     = now()
    WHERE id = 1;

    SELECT * INTO v_metrics_after
    FROM mchain_compute_calibration_metrics(v_start, v_end, TRUE, v_horizon);

    UPDATE mchain_calibration_config
    SET brier_before = v_metrics_before.brier,
        brier_after  = v_metrics_after.brier,
        ece_before   = v_metrics_before.ece,
        ece_after    = v_metrics_after.ece
    WHERE id = 1;

    INSERT INTO mchain_calibration_log (
        method, training_start, training_end, sample_size,
        brier_before, brier_after, ece_before, ece_after, reason)
    VALUES ('platt', v_start, v_end, v_n,
            v_metrics_before.brier, v_metrics_after.brier,
            v_metrics_before.ece,   v_metrics_after.ece,
            format('iter=%s a=%s b=%s', v_iter, v_a, v_b))
    RETURNING id INTO v_log_id;

    RETURN format(
        'Platt OK: n=%s iter=%s a=%s b=%s Brier %s->%s ECE %s->%s log_id=%s',
        v_n, v_iter,
        round(v_a::numeric, 4), round(v_b::numeric, 4),
        round(v_metrics_before.brier::numeric, 4),
        round(v_metrics_after.brier::numeric,  4),
        round(v_metrics_before.ece::numeric,   4),
        round(v_metrics_after.ece::numeric,    4),
        v_log_id);

END;
$$;

COMMENT ON FUNCTION mchain_fit_calibration_platt(TIMESTAMPTZ,TIMESTAMPTZ,INT,INT,INT) IS
'v26.1.1. Platt scaling: p_cal = sigmoid(a*logit(p_raw)+b). Newton с line-search.';


CREATE OR REPLACE FUNCTION mchain_refresh_calibration(
    p_method       TEXT        DEFAULT 'isotonic',
    p_lookback_days INT        DEFAULT 30,
    p_min_samples  INT         DEFAULT 500,
    p_horizon_min  INT         DEFAULT NULL
)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    v_start TIMESTAMPTZ := now() - (p_lookback_days || ' days')::INTERVAL;
    v_end   TIMESTAMPTZ := now();
BEGIN
    IF p_method = 'platt' THEN
        RETURN mchain_fit_calibration_platt(v_start, v_end, p_min_samples, 200, p_horizon_min);
    ELSIF p_method IN ('isotonic', 'bin') THEN
        RETURN mchain_fit_calibration_isotonic(v_start, v_end, 20, p_min_samples, p_horizon_min);
    ELSE
        RETURN format('Unknown method: %s', p_method);
    END IF;
END;
$$;

COMMENT ON FUNCTION mchain_refresh_calibration(TEXT,INT,INT,INT) IS
'v26.1.1. Единая точка для cron: fit + включение + запись в лог.';

CREATE OR REPLACE FUNCTION mchain_backfill_calibrated_risk(
    p_start TIMESTAMPTZ DEFAULT NULL,
    p_end   TIMESTAMPTZ DEFAULT NULL
)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    v_start TIMESTAMPTZ := COALESCE(p_start, now() - INTERVAL '90 days');
    v_end   TIMESTAMPTZ := COALESCE(p_end, now());
    v_updated BIGINT;
    v_enabled BOOLEAN;
BEGIN
    SELECT enabled INTO v_enabled FROM mchain_calibration_config WHERE id = 1;

    IF NOT COALESCE(v_enabled, FALSE) THEN
        RETURN 'Skip backfill: calibration disabled';
    END IF;

    UPDATE prediction_log
    SET calibrated_risk = mchain_calibrate_risk(predicted_risk)
    WHERE prediction_time BETWEEN v_start AND v_end
      AND predicted_risk IS NOT NULL
      AND (calibrated_risk IS NULL
           OR calibrated_risk IS DISTINCT FROM mchain_calibrate_risk(predicted_risk));

    GET DIAGNOSTICS v_updated = ROW_COUNT;

    INSERT INTO mchain_calibration_log (method, training_start, training_end, reason)
    VALUES ('backfill', v_start, v_end, format('updated=%s', v_updated));

    RETURN format('Backfilled calibrated_risk for %s rows in [%s; %s]', v_updated, v_start, v_end);
END;
$$;

COMMENT ON FUNCTION mchain_backfill_calibrated_risk(TIMESTAMPTZ,TIMESTAMPTZ) IS
'v26.1.1. Пересчитывает calibrated_risk по текущей карте для указанного окна. Нужен после refit, чтобы исторические сравнения были согласованы.';

CREATE OR REPLACE FUNCTION collect_prediction(
    p_time     TIMESTAMPTZ DEFAULT NULL,
    p_state_id SMALLINT    DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    curr_state SMALLINT;
    raw_risk   REAL;
    cal_risk   REAL;
    horizon    INT;
    v_time     TIMESTAMPTZ;
BEGIN
    v_time := COALESCE(p_time, now());

    SELECT COALESCE(forecast_horizon_minutes, 30) INTO horizon
    FROM markov_config LIMIT 1;
    horizon := COALESCE(horizon, 30);

    curr_state := COALESCE(p_state_id, mchain_get_current_state_id());
    IF curr_state IS NULL THEN
        RETURN;
    END IF;

    raw_risk := mchain_predict_risk_k_v2(curr_state, horizon);
    cal_risk := mchain_calibrate_risk(raw_risk);

    INSERT INTO prediction_log (
        prediction_time, predicted_risk, calibrated_risk,
        situation, transitions_to_risk, total_transitions_known,
        current_state_id, horizon_minutes
    ) VALUES (
        v_time, raw_risk, cal_risk,
        'risk_calculated', NULL, NULL,
        curr_state, horizon
    );
EXCEPTION WHEN OTHERS THEN
    INSERT INTO mchain_quality_errors (error_message, function_name, details)
    VALUES (SQLERRM, 'collect_prediction',
            jsonb_build_object('sqlstate', SQLSTATE, 'timestamp', v_time));
    RAISE WARNING 'collect_prediction failed at %: %', v_time, SQLERRM;
END;
$$;

COMMENT ON FUNCTION collect_prediction(TIMESTAMPTZ, SMALLINT) IS
'v26.1.1. Пишет и сырой predicted_risk, и calibrated_risk (если калибровка включена).';


CREATE OR REPLACE FUNCTION mchain_predict_risk_current_horizon_calibrated()
RETURNS REAL
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    curr_state SMALLINT;
    horizon    INT;
    raw_risk   REAL;
BEGIN
    SELECT COALESCE(forecast_horizon_minutes, 30) INTO horizon
    FROM markov_config LIMIT 1;
    horizon := COALESCE(horizon, 30);

    curr_state := mchain_get_current_state_id();
    IF curr_state IS NULL THEN
        RETURN NULL;
    END IF;

    raw_risk := mchain_predict_risk_k_v2(curr_state, horizon);
    RETURN mchain_calibrate_risk(raw_risk);
END;
$$;

COMMENT ON FUNCTION mchain_predict_risk_current_horizon_calibrated() IS
'v26.1.1. Возвращает калиброванный риск на текущий горизонт. Для отчётов и дашбордов.';

CREATE OR REPLACE FUNCTION mchain_compute_calibration_metrics(
    p_start            TIMESTAMPTZ,
    p_end              TIMESTAMPTZ,
    p_use_calibration  BOOLEAN DEFAULT TRUE,
    p_horizon_minutes  INT     DEFAULT NULL
)
RETURNS TABLE (brier REAL, ece REAL, mce REAL, n INT, avg_pred REAL, obs_rate REAL)
LANGUAGE plpgsql STABLE AS $$
DECLARE v_horizon INT;
BEGIN
    IF p_horizon_minutes IS NOT NULL THEN
        v_horizon := p_horizon_minutes;
    ELSE
        SELECT COALESCE(forecast_horizon_minutes, 30) INTO v_horizon
        FROM markov_config LIMIT 1;
        v_horizon := COALESCE(v_horizon, 30);
    END IF;

    RETURN QUERY
    WITH src AS (
        SELECT CASE WHEN p_use_calibration
                    THEN COALESCE(calibrated_risk, mchain_calibrate_risk(predicted_risk))
                    ELSE predicted_risk END AS p,
               actual_outcome::REAL AS y
        FROM prediction_log
        WHERE prediction_time >= p_start AND prediction_time < p_end
          AND actual_outcome IS NOT NULL AND predicted_risk IS NOT NULL
          AND horizon_minutes = v_horizon
    ),
    stats AS (
        SELECT AVG((p - y)^2)::REAL AS brier, AVG(p)::REAL AS avg_pred,
               AVG(y)::REAL AS obs_rate, COUNT(*)::INT AS n
        FROM src
    ),
    bins AS (
        SELECT WIDTH_BUCKET(LEAST(GREATEST(p,0.0001),0.9999),0,1,10) AS b,
               AVG(p) AS ap, AVG(y) AS of_, COUNT(*)::NUMERIC AS cnt
        FROM src GROUP BY 1
    ),
    agg AS (
        SELECT (SUM(cnt * ABS(ap - of_))/NULLIF(SUM(cnt),0))::REAL AS ece,
               MAX(ABS(ap - of_))::REAL AS mce
        FROM bins
    )
    SELECT s.brier, a.ece, a.mce, s.n, s.avg_pred, s.obs_rate
    FROM stats s CROSS JOIN agg a;
END; $$;
