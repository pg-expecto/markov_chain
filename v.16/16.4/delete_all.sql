-- =============================================================================
-- Скрипт полного удаления объектов цепи Маркова (таблицы, функции, процедуры,
-- триггеры, индексы, последовательности) из базы данных PostgreSQL.
-- ВНИМАНИЕ! Скрипт удаляет все перечисленные объекты без возможности восстановления.
-- Рекомендуется выполнить в транзакции и предварительно сделать резервную копию.
-- Предполагается, что объекты находятся в схеме public.
-- =============================================================================

BEGIN;

-- Отключаем вывод NOTICE о несуществующих объектах
SET client_min_messages = WARNING;

-- =============================================================================
-- 1. Удаление таблиц (CASCADE удалит зависимые индексы, триггеры, внешние ключи,
--    последовательности, принадлежащие таблицам)
-- =============================================================================
DROP TABLE IF EXISTS critical_states_audit CASCADE;
DROP TABLE IF EXISTS profile_change_indicator CASCADE;
DROP TABLE IF EXISTS incident_forecast_config CASCADE;
DROP TABLE IF EXISTS pre_incident_match_log CASCADE;
DROP TABLE IF EXISTS pre_incident_profiles CASCADE;
DROP TABLE IF EXISTS profile_comparison_log CASCADE;
DROP TABLE IF EXISTS incident_free_window_current CASCADE;
DROP TABLE IF EXISTS anomaly_log CASCADE;
DROP TABLE IF EXISTS profile_baseline CASCADE;
DROP TABLE IF EXISTS profile_aggregated CASCADE;
DROP TABLE IF EXISTS performance_history CASCADE;
DROP TABLE IF EXISTS mchain_train_progress_log CASCADE;
DROP TABLE IF EXISTS forgetting_optimization_log CASCADE;
DROP TABLE IF EXISTS critical_states CASCADE;
DROP TABLE IF EXISTS mchain_quality_errors CASCADE;
DROP TABLE IF EXISTS mchain_quality_metrics_history CASCADE;
DROP TABLE IF EXISTS prediction_log CASCADE;
DROP TABLE IF EXISTS apply_forgetting_log CASCADE;
DROP TABLE IF EXISTS markov_chain CASCADE;
DROP TABLE IF EXISTS state_descriptions CASCADE;
DROP TABLE IF EXISTS markov_absorbing CASCADE;
DROP TABLE IF EXISTS markov_probabilities CASCADE;
DROP TABLE IF EXISTS transition_log CASCADE;
DROP TABLE IF EXISTS markov_frequencies CASCADE;
DROP TABLE IF EXISTS mchain_error_log CASCADE;
DROP TABLE IF EXISTS markov_config CASCADE;

-- =============================================================================
-- 2. Удаление функций и процедур
-- =============================================================================
DO $$
DECLARE
    r RECORD;
    func_names TEXT[] := ARRAY[
        -- из markov_chain_functions.sql
        'adaptive_configure_markov_chain',
        'mchain_initial_train_from_history',
        'fill_performance_history',
        'mchain_train_step',
        'mchain_apply_forgetting',
        'mchain_check_sufficiency',
        'mchain_log_transition',
        'mchain_clean_transition_log',
        'fill_state_descriptions',
        'get_state_id',
        'rebuild_markov_absorbing',
        'update_last_incident_time',
        'update_markov_probabilities',
        'mchain_clean_apply_forgetting_log',
        'mchain_log_error',
        'mchain_get_current_state_id',
        'mchain_forecast_reliability',
        'mchain_reliability_report',
        'mchain_incident_transitions_report',
        'mchain_summary_report',
        'mchain_incident_state_detail_report',
        'mchain_health_check',
        'mchain_state_transition_matrix_report',
        'decode_state_id',
        'get_critical_states',
        'get_critical_state_ids',
        'format_timestamptz_to_minute',
        'calculate_daily_quality_metrics',
        'refresh_critical_states',
        'ensure_audit_table',
        'mchain_predict_risk_k_v2',
        'compute_empirical_incident_risk',
        'collect_prediction',
        'update_prediction_outcomes',
        'mchain_quality_report',
        'mchain_predict_risk_current_horizon',
        'evaluate_forgetting_params',
        'mchain_predict_risk_k_v2_with_matrix',
        'report_stability_trend',
        'report_quality_sliding',
        'report_daily_calibration',
        'state_distribution',
        'report_forgetting_effectiveness',
        'generate_full_analytical_report',
        'refresh_stability_threshold',
        'mchain_log_transition_at',
        'mchain_train_step_at',
        'mchain_train_historical',
        'recalculate_prediction_risks',
        'trigger_recalculate_risks_on_config_change',
        'report_prediction_incident_summary',
        'find_optimal_horizon',
        -- из markov_chain_profile_functions.sql
        'calculate_profile_metrics',
        'detect_anomaly',
        'get_deviation_report',
        'log_anomaly',
        'append_performance_history',
        'generate_profile_summary_report',
        'generate_detailed_profile_report',
        'refresh_performance_history',
        'find_incident_free_window',
        'save_baseline_profile',
        'save_current_profile',
        'histogram_divergence',
        'compare_profiles',
        'clean_profile_comparison_log',
        'get_incident_free_window_before',
        'generate_profile_incident_analytics_report',
        'generate_comprehensive_analytical_report',
        'generate_analytical_report',
        'collect_pre_incident_profiles',
        'compare_with_pre_incident_profiles',
        'find_matching_pre_incident_profile',
        'generate_pre_incident_audit_report',
        'generate_incident_forecast_report',
        'update_profile_change_indicator',
        'historical_fill_profile_change_indicator',
        'clean_old_profile_change_indicator',
        'calculate_signal',
        'compare_with_fixed_baseline',
        'historical_fill_profile_comparison',
        'compare_profiles_at',
        'fill_profile_comparison_historically',
        'generate_profile_comparison_report',
        -- из performance_metrics_for_markov_chain.sql
        'get_current_os_waiting_correlation_for_markov_chain'
    ];
BEGIN
    FOR r IN
        SELECT n.nspname, p.proname, pg_get_function_identity_arguments(p.oid) AS args
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname = ANY(func_names)
    LOOP
        EXECUTE format('DROP ROUTINE IF EXISTS %I.%I(%s) CASCADE', r.nspname, r.proname, r.args);
    END LOOP;
END $$;

COMMIT;

-- =============================================================================
-- Примечания:
-- 1. Скрипт не удаляет внешние таблицы cluster_stat_median и performance_incident,
--    так как они не являются частью цепи Маркова.
-- 2. Если в вашей базе есть другие функции/процедуры с префиксами mchain_,
--    markov_, profile_, generate_, report_ и т.п., которых нет в списке,
--    добавьте их имена в массив func_names.
-- 3. Для полного удаления можно также выполнить:
--    DROP SCHEMA public CASCADE;  -- но это удалит ВСЕ объекты схемы!
-- =============================================================================