#!/bin/bash
# Copyright 2026 Ринат (pg_expecto)
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
# http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# 
# train_markov_chain.sh
# version 13.8
#
# Скрипт для исторического обучения цепи Маркова с динамическим подбором горизонта
# и итеративной коррекцией критических состояний. Реализованы усиленные параметры
# забывания и финальный протокол проверок.
# Использование:
#   ./train_markov_chain.sh [YYYY-MM-DD HH:MI:SS]
#   Если аргумент не указан, используется текущее время (UTC) как правая граница.

set -euo pipefail

# ---------------------- Конфигурация подключения к БД -------------------------
export PGHOST="${PGHOST:-localhost}"
export PGPORT="${PGPORT:-5432}"
export PGUSER="${PGUSER:-expecto_user}"
export PGDATABASE="${PGDATABASE:-expecto_db}"
export PGPASSWORD="${PGPASSWORD:-}"

# ---------------------- Параметры скрипта ------------------------------------
END_TIME="${1:-$(date -u +"%Y-%m-%d %H:%M:%S")}"
echo "Запуск исторического обучения до: $END_TIME (UTC)"

# ---------------------- Проверка psql -----------------------------------------
if ! command -v psql &> /dev/null; then
    echo "Ошибка: psql не найден."
    exit 1
fi

# =============================================================================
# 0. Полная очистка данных модели (кроме конфигурации)
# =============================================================================
echo "=== Шаг 0: Очистка всех таблиц цепи Маркова (кроме конфигурации) ==="
psql -v ON_ERROR_STOP=1 <<EOSQL
TRUNCATE TABLE transition_log RESTART IDENTITY CASCADE;
TRUNCATE TABLE markov_frequencies RESTART IDENTITY CASCADE;
TRUNCATE TABLE markov_probabilities RESTART IDENTITY CASCADE;
TRUNCATE TABLE markov_chain RESTART IDENTITY CASCADE;
TRUNCATE TABLE prediction_log RESTART IDENTITY CASCADE;
TRUNCATE TABLE apply_forgetting_log RESTART IDENTITY CASCADE;
TRUNCATE TABLE mchain_error_log RESTART IDENTITY CASCADE;
TRUNCATE TABLE mchain_quality_metrics_history RESTART IDENTITY CASCADE;
UPDATE markov_config SET last_forget_time = (SELECT MIN(curr_timestamp) FROM cluster_stat_median);
EOSQL

# =============================================================================
# 0.5. Адаптивная настройка конфигурации (до обучения) – оставляем как есть
# =============================================================================
echo "=== Шаг 0.5: Адаптивная настройка конфигурации цепи Маркова (до обучения) ==="
ADAPT_REPORT=$(psql -v ON_ERROR_STOP=1 -t -A -c "SELECT adaptive_configure_markov_chain('$END_TIME'::TIMESTAMPTZ);")
echo "$ADAPT_REPORT"

# =============================================================================
# 1. Заполнение performance_history
# =============================================================================
echo "=== Шаг 1: Заполнение performance_history (при необходимости) ==="
START_EPOCH=$(psql -t -c "SELECT EXTRACT(EPOCH FROM MIN(curr_timestamp))::BIGINT FROM cluster_stat_median;" | xargs)
if [[ -z "$START_EPOCH" || "$START_EPOCH" == "0" ]]; then
    echo "Ошибка: нет данных в cluster_stat_median или MIN(curr_timestamp) равен NULL."
    exit 1
fi

END_EPOCH=$(date -u -d "$END_TIME" +%s 2>/dev/null || echo 0)
if [[ $END_EPOCH -eq 0 ]]; then
    echo "Ошибка: неверный формат END_TIME: $END_TIME. Ожидается YYYY-MM-DD HH:MI:SS"
    exit 1
fi

START_DATE=$(date -u -d "@$START_EPOCH" +"%Y-%m-%d %H:%M:%S")
echo "Начальная дата: $START_DATE (UNIX $START_EPOCH)"

psql -v ON_ERROR_STOP=1 <<EOSQL
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM performance_history LIMIT 1) THEN
        PERFORM fill_performance_history(
            (SELECT MIN(curr_timestamp) FROM cluster_stat_median),
            '$END_TIME'::TIMESTAMPTZ
        );
    END IF;
END \$\$;
EOSQL

# =============================================================================
# 2. Пакетное историческое обучение
# =============================================================================
echo "=== Шаг 2: Пакетное историческое обучение (порциями по 60 минут) ==="
psql -c "ALTER TABLE transition_log DISABLE TRIGGER trigger_update_incident_time;"

CURRENT_EPOCH=$START_EPOCH
CHUNK_MINUTES=60
CHUNK_SECONDS=$((CHUNK_MINUTES * 60))

while [[ $CURRENT_EPOCH -lt $END_EPOCH ]]; do
    NEXT_EPOCH=$((CURRENT_EPOCH + CHUNK_SECONDS))
    if [[ $NEXT_EPOCH -gt $END_EPOCH ]]; then
        NEXT_EPOCH=$END_EPOCH
    fi
    CURRENT_TS=$(date -u -d "@$CURRENT_EPOCH" +"%Y-%m-%d %H:%M:%S")
    NEXT_TS=$(date -u -d "@$NEXT_EPOCH" +"%Y-%m-%d %H:%M:%S")
    echo "  Обработка порции: $CURRENT_TS -> $NEXT_TS"
    psql -v ON_ERROR_STOP=1 -c "SELECT mchain_train_historical_chunk('$CURRENT_TS'::TIMESTAMPTZ, '$NEXT_TS'::TIMESTAMPTZ);"
    CURRENT_EPOCH=$NEXT_EPOCH
done

echo "=== Шаг 3: Восстановление триггера и обновление last_incident_time ==="
psql -v ON_ERROR_STOP=1 <<EOSQL
ALTER TABLE transition_log ENABLE TRIGGER trigger_update_incident_time;
UPDATE markov_config SET last_incident_time = (
    SELECT MAX(ts) FROM transition_log
    WHERE to_state IN (SELECT state_id FROM critical_states)
);
EOSQL

echo "=== Шаг 4: Обновление исходов прогнозов (для первоначального горизонта) ==="
psql -c "SELECT update_prediction_outcomes();"

echo "=== Шаг 5: Пересчёт вероятностей и поглощающей матрицы ==="
psql -v ON_ERROR_STOP=1 <<EOSQL
SELECT update_markov_probabilities();
SELECT rebuild_markov_absorbing();
EOSQL

# Шаг 5.1 УДАЛЁН – больше не используется.

# =============================================================================
# 6. Динамический подбор горизонта и итеративная коррекция
# =============================================================================
echo "=== Шаг 6: Динамический подбор оптимального горизонта ==="

# --- НАСТРОЙКИ (изменены согласно рекомендациям) ---
RISK_THRESHOLD=0.20
MAX_ITER=6                     # увеличено до 6
ITER=1
TARGET_INCIDENT_RATE=0.15      # согласовано с find_optimal_horizon
TOLERANCE=0.03                 # ±3%

# Функция для вычисления фактической доли инцидентов среди прогнозов
get_incident_rate() {
    psql -t -A -c "
        SELECT COALESCE(AVG(actual_outcome), 0)
        FROM prediction_log
        WHERE actual_outcome IS NOT NULL;
    " | xargs
}

# Основной цикл подбора
while [[ $ITER -le $MAX_ITER ]]; do
    echo "=== Итерация $ITER: порог риска = $RISK_THRESHOLD ==="

    # 1. Обновляем критические состояния с текущим порогом
    echo "  Обновление critical_states с порогом $RISK_THRESHOLD..."
    psql -v ON_ERROR_STOP=1 -c "SELECT refresh_critical_states(p_risk_threshold => $RISK_THRESHOLD, p_min_transitions => 50, p_dry_run => FALSE, p_audit => TRUE);"

    # 2. Находим оптимальный горизонт (используем целевую долю 0.15)
    OPTIMAL_HORIZON=$(psql -t -A -c "SELECT find_optimal_horizon(0.15, 5, 120, 5);")
    echo "  Оптимальный горизонт: $OPTIMAL_HORIZON минут"

    # 3. Устанавливаем горизонт и усиленные параметры забывания
    NEW_INTERVAL=$((2 * OPTIMAL_HORIZON))
    if [ $NEW_INTERVAL -lt 30 ]; then NEW_INTERVAL=30; fi
    if [ $NEW_INTERVAL -gt 720 ]; then NEW_INTERVAL=720; fi
    # Усиленные параметры (alpha=0.15, half_life=5)
    NEW_BASE_ALPHA=0.15
    NEW_HALF_LIFE=5

    psql -v ON_ERROR_STOP=1 <<EOSQL
UPDATE markov_config SET
    forecast_horizon_minutes = $OPTIMAL_HORIZON,
    base_alpha = $NEW_BASE_ALPHA,
    incident_half_life_days = $NEW_HALF_LIFE,
    interval_minute = $NEW_INTERVAL,
    min_transitions_for_forgetting = 3000,
    min_freq_for_stability = 50,
    use_adaptive_alpha = TRUE,
    adaptive_forgetting_enabled = TRUE;
EOSQL

    # 4. Пересоздаём прогнозы с новым горизонтом
    echo "  Пересоздание прогнозов с горизонтом $OPTIMAL_HORIZON минут..."
    psql -c "TRUNCATE TABLE prediction_log RESTART IDENTITY CASCADE;"
    psql -v ON_ERROR_STOP=1 <<EOSQL
INSERT INTO prediction_log (prediction_time, predicted_risk, current_state_id, horizon_minutes, situation)
SELECT
    ts,
    mchain_predict_risk_k_v2(from_state, $OPTIMAL_HORIZON) AS risk,
    from_state,
    $OPTIMAL_HORIZON,
    'risk_calculated'
FROM transition_log
WHERE from_state IS NOT NULL
ORDER BY ts;
EOSQL

    # 5. Обновляем исходы (циклически, пока есть необработанные прогнозы)
    echo "  Обновление исходов для новых прогнозов..."
    while true; do
        UPDATED=$(psql -t -A -c "SELECT update_prediction_outcomes();" | grep -oE '[0-9]+' | head -1)
        if [[ -z "$UPDATED" || "$UPDATED" -eq 0 ]]; then
            break
        fi
        echo "    Обновлено исходов: $UPDATED"
    done

    # 6. Вычисляем фактическую долю инцидентов
    INCIDENT_RATE=$(get_incident_rate)
    echo "  Фактическая доля инцидентов: $INCIDENT_RATE (цель ~$TARGET_INCIDENT_RATE)"

    # 7. Проверяем, достигли ли целевого диапазона
    if (( $(echo "$INCIDENT_RATE >= $TARGET_INCIDENT_RATE - $TOLERANCE" | bc -l) )) && \
       (( $(echo "$INCIDENT_RATE <= $TARGET_INCIDENT_RATE + $TOLERANCE" | bc -l) )); then
        echo "✅ Доля инцидентов в целевом диапазоне. Завершаем подбор."
        break
    fi

    # Если не достигли, увеличиваем порог риска для следующей итерации
    RISK_THRESHOLD=$(echo "$RISK_THRESHOLD + 0.05" | bc)
    ITER=$((ITER + 1))
done

if [[ $ITER -gt $MAX_ITER ]]; then
    echo "⚠️  Не удалось достичь целевой доли инцидентов за $MAX_ITER итераций."
    echo "   Текущая доля: $INCIDENT_RATE, горизонт: $OPTIMAL_HORIZON, порог риска: $RISK_THRESHOLD"
    echo "   Рекомендуется ручная настройка или увеличение количества итераций."
fi

# =============================================================================
# 6.5. Усиленное забывание для стабилизации вероятностей (alpha=0.15)
# =============================================================================
echo "=== Применение усиленного забывания для стабилизации вероятностей ==="
psql -c "SELECT mchain_apply_forgetting(0.15);"
psql -c "SELECT refresh_stability_threshold();"

# Повторный пересчёт вероятностей после забывания
psql -v ON_ERROR_STOP=1 <<EOSQL
SELECT update_markov_probabilities();
SELECT rebuild_markov_absorbing();
EOSQL

# =============================================================================
# 7. Расчёт суточных метрик качества
# =============================================================================
echo "=== Шаг 7: Расчёт суточных метрик качества ==="
START_DATE_METRICS=$(psql -t -c "SELECT to_char(MIN(ts), 'YYYY-MM-DD') FROM transition_log;" | xargs)
END_DATE_METRICS=$(psql -t -c "SELECT to_char('$END_TIME'::TIMESTAMPTZ, 'YYYY-MM-DD');" | xargs)
if [[ -z "$START_DATE_METRICS" || -z "$END_DATE_METRICS" ]]; then
    echo "Предупреждение: не удалось определить даты для расчёта метрик."
else
    CURRENT_DATE="$START_DATE_METRICS"
    while [[ $(date -d "$CURRENT_DATE" +%s) -le $(date -d "$END_DATE_METRICS" +%s) ]]; do
        echo "  Расчёт метрик за $CURRENT_DATE"
        psql -c "SELECT calculate_daily_quality_metrics('$CURRENT_DATE'::DATE);"
        CURRENT_DATE=$(date -d "$CURRENT_DATE + 1 day" +"%Y-%m-%d")
    done
fi

# =============================================================================
# 8. Проверка итогового состояния и формирование протокола
# =============================================================================
echo "=== Шаг 8: Проверка итогового состояния цепи ==="
RELIABILITY=$(psql -t -A -c "SELECT mchain_forecast_reliability();" | xargs)
echo "  Рейтинг достоверности: $RELIABILITY"

# Если рейтинг < 3 – применяем дополнительное забывание и пересчёт
if [ "$RELIABILITY" -lt 3 ]; then
    echo "⚠️  Рейтинг достоверности < 3. Применяем дополнительное забывание с alpha=0.20..."
    psql -c "SELECT mchain_apply_forgetting(0.20);"
    psql -c "SELECT refresh_stability_threshold();"
    psql -v ON_ERROR_STOP=1 <<EOSQL
SELECT update_markov_probabilities();
SELECT rebuild_markov_absorbing();
EOSQL
    # Пересчёт прогнозов с новыми вероятностями
    psql -c "SELECT recalculate_prediction_risks();"
    # Пересчёт исходов
    psql -c "SELECT update_prediction_outcomes();"
    # Повторная оценка рейтинга
    RELIABILITY=$(psql -t -A -c "SELECT mchain_forecast_reliability();" | xargs)
    echo "  Рейтинг достоверности после дополнительного забывания: $RELIABILITY"
fi

# =============================================================================
# Финальный протокол (дополнительные проверки)
# =============================================================================
echo ""
echo "=============================="
echo "    ИТОГОВЫЙ ПРОТОКОЛ"
echo "=============================="

# 1. Текущие параметры конфигурации
echo ""
echo "--- 1. Конфигурация цепи ---"
psql -t -A -c "
SELECT '  forecast_horizon_minutes = ' || forecast_horizon_minutes ||
       ', base_alpha = ' || base_alpha ||
       ', half_life = ' || incident_half_life_days ||
       ', interval_minute = ' || interval_minute ||
       ', min_transitions_for_forgetting = ' || min_transitions_for_forgetting ||
       ', min_freq_for_stability = ' || min_freq_for_stability
FROM markov_config;" | while read -r line; do echo "$line"; done

# 2. Количество переходов и прогнозов
echo ""
echo "--- 2. Статистика данных ---"
psql -t -A -c "
SELECT '  Всего переходов (transition_log): ' || COUNT(*) FROM transition_log;
SELECT '  Прогнозов всего: ' || COUNT(*) FROM prediction_log;
SELECT '  Прогнозов с известным исходом: ' || COUNT(*) FROM prediction_log WHERE actual_outcome IS NOT NULL;
SELECT '  Прогнозов с исходом 1: ' || COUNT(*) FROM prediction_log WHERE actual_outcome = 1;
"

# 3. Доля инцидентов в прогнозах (текущая фактическая)
CUR_INCIDENT_RATE=$(psql -t -A -c "SELECT COALESCE(AVG(actual_outcome), 0) FROM prediction_log WHERE actual_outcome IS NOT NULL;" | xargs)
echo "  Фактическая доля инцидентов среди прогнозов: $CUR_INCIDENT_RATE"

# 4. Рейтинг достоверности (повторно)
echo "  Рейтинг достоверности (mchain_forecast_reliability): $RELIABILITY"

# 5. Стабильность max_prob_change
MAX_PROB_CHANGE=$(psql -t -A -c "
WITH frequent_states AS (
    SELECT from_state
    FROM transition_log
    WHERE ts >= now() - INTERVAL '14 days'
      AND from_state NOT IN (SELECT state_id FROM critical_states)
    GROUP BY from_state
    HAVING COUNT(*) >= (SELECT min_freq_for_stability FROM markov_config)
),
recent AS (
    SELECT from_state, to_state,
           COUNT(*)::REAL / SUM(COUNT(*)) OVER (PARTITION BY from_state) AS prob
    FROM transition_log
    JOIN frequent_states fs USING (from_state)
    WHERE ts >= now() - INTERVAL '14 days'
      AND ts < now() - INTERVAL '7 days'
      AND to_state NOT IN (SELECT state_id FROM critical_states)
      AND from_state NOT IN (SELECT state_id FROM critical_states)
    GROUP BY from_state, to_state
),
current AS (
    SELECT from_state, to_state,
           COUNT(*)::REAL / SUM(COUNT(*)) OVER (PARTITION BY from_state) AS prob
    FROM transition_log
    JOIN frequent_states fs USING (from_state)
    WHERE ts >= now() - INTERVAL '7 days'
      AND to_state NOT IN (SELECT state_id FROM critical_states)
      AND from_state NOT IN (SELECT state_id FROM critical_states)
    GROUP BY from_state, to_state
)
SELECT COALESCE(MAX(ABS(COALESCE(r.prob, 0) - COALESCE(c.prob, 0))), 0.0)
FROM recent r
FULL JOIN current c USING (from_state, to_state);
" | xargs)
echo "  max_prob_change (последние 14 дней): $MAX_PROB_CHANGE"

# 6. Покрытие частых состояний
COVERAGE=$(psql -t -A -c "
WITH total_transitions AS (
    SELECT COUNT(*) AS total FROM transition_log
),
state_stats AS (
    SELECT from_state, COUNT(*) AS n_i,
           COUNT(*)::REAL / (SELECT total FROM total_transitions) AS freq
    FROM transition_log
    GROUP BY from_state
),
frequent_states AS (
    SELECT from_state FROM state_stats WHERE freq > 0.01
),
coverage AS (
    SELECT
        COUNT(*) AS total_frequent,
        SUM(CASE WHEN ss.n_i >= 50 THEN 1 ELSE 0 END) AS covered_frequent
    FROM frequent_states f
    CROSS JOIN LATERAL (
        SELECT COUNT(*) AS n_i FROM transition_log WHERE from_state = f.from_state
    ) ss
)
SELECT
    CASE WHEN total_frequent = 0 THEN 100
         ELSE (covered_frequent * 100) / total_frequent
    END
FROM coverage;
" | xargs)
echo "  Покрытие частых состояний (coverage_pct): $COVERAGE%"

# 7. Количество критических состояний
CRIT_COUNT=$(psql -t -A -c "SELECT COUNT(*) FROM critical_states;" | xargs)
echo "  Количество критических состояний: $CRIT_COUNT"

# 8. Время последнего инцидента (из конфигурации)
LAST_INCIDENT=$(psql -t -A -c "SELECT format_timestamptz_to_minute(last_incident_time) FROM markov_config;" | xargs)
echo "  Последний инцидент: ${LAST_INCIDENT:-нет}"

# 9. Проверка ошибок (последние 5)
ERRORS=$(psql -t -A -c "SELECT COUNT(*) FROM mchain_error_log;" | xargs)
echo "  Ошибок в логе: $ERRORS"
if [ "$ERRORS" -gt 0 ]; then
    echo "    Последние ошибки:"
    psql -t -A -c "SELECT function_name || ': ' || error_message FROM mchain_error_log ORDER BY ts DESC LIMIT 5;" | while read -r line; do echo "      $line"; done
fi

# 10. Общий вердикт
echo ""
echo "--- 3. Вердикт ---"
if [ "$RELIABILITY" -ge 3 ]; then
    echo "✅ Цепь Маркова в штатном состоянии (рейтинг >= 3)."
else
    echo "⚠️  Рейтинг достоверности < 3. Рекомендуется дополнительная настройка:"
    echo "   - Увеличьте период обучения (убедитесь, что данных достаточно)."
    echo "   - Запустите оптимизацию параметров забывания: CALL optimize_forgetting_params();"
    echo "   - Проверьте корректность поступления метрик производительности."
fi
echo "=============================="
echo ""
echo "=== Готово! Историческое обучение завершено ==="
