#################################################################
# Markov chain
# 16.9
# ============================================================
# Ежедневная очистка журналов и обновление статистик
# ============================================================
# Очистка transition_log (в 01:15)
15 1 * * * psql -d expecto_db -U expecto_user -c "SELECT mchain_clean_transition_log();"

# ============================================================
# Очистка архивных данных (раз в неделю)
# ============================================================
# Очистка apply_forgetting_log (ежедневно в 02:00)
0 2 * * * psql -d expecto_db -U expecto_user -c "SELECT mchain_clean_apply_forgetting_log();"

# ============================================================
# Анализ качества прогноза
# ============================================================
# Обновление critical_states еженедельно (суббота в 03:00)
0 3 * * 6 psql -d expecto_db -U expecto_user -c "SELECT refresh_critical_states(p_risk_threshold => 0.10, p_dry_run => FALSE, p_audit => TRUE);" >/postgres/pg_expecto/sh/refresh_critical_states.log 2>&1

# Обновление исходов каждые 5 минут
*/5 * * * * psql -d expecto_db -U expecto_user -c "SELECT update_prediction_outcomes();"

# Расчёт суточных метрик в 02:00
0 2 * * * psql -d expecto_db -U expecto_user -c "SELECT calculate_daily_quality_metrics(CURRENT_DATE - 1);"

# Еженедельная адаптивная настройка min_freq_for_stability (воскресенье в 01:00)
0 1 * * 0 psql -d expecto_db -U expecto_user -c "SELECT refresh_stability_threshold();"

#################################################################################################
# Расчет метрик профиля нагрузки на основе цепи Маркова
# Ежедневная очистка (в 03:00)
0 3 * * * psql -d expecto_db -U expecto_user -c "SELECT clean_profile_comparison_log();"

# Ежедневно в 02:30 добавляем профили для инцидентов за предыдущий день
30 2 * * * psql -d expecto_db -U expecto_user -c "SELECT collect_pre_incident_profiles(now() - interval '1 day', now(), 60);" > /postgres/pg_expecto/sh/collect_pre_incident.log 2>&1

# Очистка старых данных индикатора изменения профиля (каждый день в 2:00)
0 2 * * * psql -d expecto_db -U expecto_user -c "SELECT clean_old_profile_change_indicator(30);" > /postgres/pg_expecto/sh/clean_old_profile_change_indicator.log 2>&1

# Расчет метрик профиля нагрузки на основе цепи Маркова
#################################################################################################

# ============================================================
# SICPP (Signal Indicating a Change in the Performance Profile)
# ============================================================
# Еженедельная очистка истории SICPP (воскресенье в 04:00)
0 4 * * 0 psql -d expecto_db -U expecto_user -c "SELECT sicpp_clean_history(90);" >/postgres/pg_expecto/sh/sicpp_clean_history.log 2>&1

# Ежечасная проверка P3-покрытия (алерты записываются в sicpp_coverage_alerts)
0 * * * * psql -d expecto_db -U expecto_user -c "SELECT * FROM check_p3_coverage_gaps(now() - interval '7 days', now(), TRUE);" >/postgres/pg_expecto/sh/check_p3_coverage_gaps.log 2>&1

# ============================================================
# Основной шаг обучения цепи Маркова
# ============================================================
# ВНИМАНИЕ: mchain_train_step() вызывается приложением автоматически,
# если в таблице configuration установлен флаг is_markov_chain_enabled = TRUE.
# Если приложение НЕ выполняет этот вызов — раскомментируйте строку ниже:
# * * * * * psql -d expecto_db -U expecto_user -c "SELECT mchain_train_step();" >> /postgres/pg_expecto/sh/mchain_train_step.log 2>&1

# Markov chain
#################################################################
