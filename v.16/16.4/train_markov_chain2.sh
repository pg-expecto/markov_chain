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
# version 14.1 – добавлено сохранение периода обучения в markov_config
#
# train_markov_chain2.sh – гибкое историческое обучение цепи Маркова с возможностью указания произвольного периода (--start, --end).
# Основные отличия от train_markov_chain.sh:
#   - позволяет задать как начальную, так и конечную дату обучения;
#   - корректно устанавливает last_forget_time в начало обучаемого периода,
#     обеспечивая правильную работу забывания при частичном обучении;
#   - инкрементально заполняет performance_history только за заданный период,
#     не перезаписывая существующие данные.
# 
# Скрипт выполняет те же этапы: очистку таблиц, адаптивную настройку,
# пакетное обучение, подбор горизонта, забывание, расчёт метрик и проверку.
#
# Использование:
#   ./train_markov_chain2.sh [--start "YYYY-MM-DD HH:MI:SS"] [--end "YYYY-MM-DD HH:MI:SS"]
#   Если аргументы не указаны, начало определяется как MIN(curr_timestamp)
#   из cluster_stat_median, конец – текущее время UTC.
set -euo pipefail

# ---------------------- Конфигурация подключения к БД -------------------------
export PGHOST="${PGHOST:-localhost}"
export PGPORT="${PGPORT:-5432}"
export PGUSER="${PGUSER:-expecto_user}"
export PGDATABASE="${PGDATABASE:-expecto_db}"
export PGPASSWORD="${PGPASSWORD:-}"

# ---------------------- Параметры скрипта ------------------------------------
START_TIME=""
END_TIME=""

# Обработка аргументов командной строки
while [[ $# -gt 0 ]]; do
    case "$1" in
        --start)
            START_TIME="$2"
            shift 2
            ;;
        --end)
            END_TIME="$2"
            shift 2
            ;;
        *)
            echo "Неизвестный аргумент: $1"
            echo "Использование: $0 [--start \"YYYY-MM-DD HH:MI:SS\"] [--end \"YYYY-MM-DD HH:MI:SS\"]"
            exit 1
            ;;
    esac
done

# Если конечная дата не задана, используем текущее время UTC
if [[ -z "$END_TIME" ]]; then
    END_TIME=$(date -u +"%Y-%m-%d %H:%M:%S")
fi

# Если начальная дата не задана, определяем как MIN(curr_timestamp) из cluster_stat_median
if [[ -z "$START_TIME" ]]; then
    START_TIME=$(psql -t -A -c "SELECT to_char(MIN(curr_timestamp), 'YYYY-MM-DD HH24:MI:SS') FROM cluster_stat_median;" | xargs)
    if [[ -z "$START_TIME" || "$START_TIME" == "0" ]]; then
        echo "Ошибка: нет данных в cluster_stat_median или MIN(curr_timestamp) равен NULL."
        exit 1
    fi
    echo "Начальная дата не задана, определена как MIN(curr_timestamp): $START_TIME"
fi

echo "Начальная дата обучения: $START_TIME (UTC)"
echo "Конечная дата обучения: $END_TIME (UTC)"

# ---------------------- Проверка psql -----------------------------------------
if ! command -v psql &> /dev/null; then
    echo "Ошибка: psql не найден."
    exit 1
fi

# =============================================================================
# 0. ДОБАВЛЕНИЕ КОЛОНОК ДЛЯ ХРАНЕНИЯ ПЕРИОДА ОБУЧЕНИЯ И СОХРАНЕНИЕ ПЕРИОДА
# =============================================================================
echo "=== Шаг 0: Добавление колонок для периода обучения (если отсутствуют) и сохранение периода ==="
psql -v ON_ERROR_STOP=1 <<EOSQL
ALTER TABLE markov_config ADD COLUMN IF NOT EXISTS training_start_time TIMESTAMPTZ;
ALTER TABLE markov_config ADD COLUMN IF NOT EXISTS training_end_time TIMESTAMPTZ;
UPDATE markov_config SET
    training_start_time = '$START_TIME'::TIMESTAMPTZ,
    training_end_time   = '$END_TIME'::TIMESTAMPTZ;
EOSQL

# =============================================================================
# 0.1. Полная очистка данных модели (кроме конфигурации)
# =============================================================================
echo "=== Шаг 0.1: Очистка всех таблиц цепи Маркова (кроме конфигурации) ==="
psql -v ON_ERROR_STOP=1 <<EOSQL
TRUNCATE TABLE transition_log RESTART IDENTITY CASCADE;
TRUNCATE TABLE markov_frequencies RESTART IDENTITY CASCADE;
TRUNCATE TABLE markov_probabilities RESTART IDENTITY CASCADE;
TRUNCATE TABLE markov_chain RESTART IDENTITY CASCADE;
TRUNCATE TABLE prediction_log RESTART IDENTITY CASCADE;
TRUNCATE TABLE apply_forgetting_log RESTART IDENTITY CASCADE;
TRUNCATE TABLE mchain_error_log RESTART IDENTITY CASCADE;
TRUNCATE TABLE mchain_quality_metrics_history RESTART IDENTITY CASCADE;
EOSQL

# =============================================================================
# 0.2. Установка last_forget_time в начало обучаемого периода (КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ)
# =============================================================================
echo "=== Шаг 0.2: Установка last_forget_time = $START_TIME ==="
psql -v ON_ERROR_STOP=1 <<EOSQL
UPDATE markov_config SET last_forget_time = '$START_TIME'::TIMESTAMPTZ;
EOSQL

# =============================================================================
# 1. Адаптивная настройка конфигурации (до обучения)
# =============================================================================
echo "=== Шаг 1: Адаптивная настройка конфигурации цепи Маркова (до обучения) ==="
ADAPT_REPORT=$(psql -v ON_ERROR_STOP=1 -t -A -c "SELECT adaptive_configure_markov_chain('$END_TIME'::TIMESTAMPTZ);")
echo "$ADAPT_REPORT"

# =============================================================================
# 2. Заполнение performance_history (инкрементально за указанный период)
# =============================================================================
echo "=== Шаг 2: Заполнение performance_history (только за период обучения) ==="
psql -v ON_ERROR_STOP=1 <<EOSQL
DO \$\$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM performance_history
        WHERE ts >= '$START_TIME'::TIMESTAMPTZ AND ts <= '$END_TIME'::TIMESTAMPTZ
        LIMIT 1
    ) THEN
        PERFORM append_performance_history(
            '$START_TIME'::TIMESTAMPTZ,
            '$END_TIME'::TIMESTAMPTZ
        );
    END IF;
END \$\$;
EOSQL

# =============================================================================
# 3. Пакетное историческое обучение (порциями по 60 минут)
# =============================================================================
echo "=== Шаг 3: Пакетное историческое обучение (порциями по 60 минут) ==="
psql -c "ALTER TABLE transition_log DISABLE TRIGGER trigger_update_incident_time;"

LEARN_START_EPOCH=$(date -u -d "$START_TIME" +%s 2>/dev/null || echo 0)
LEARN_END_EPOCH=$(date -u -d "$END_TIME" +%s 2>/dev/null || echo 0)
if [[ $LEARN_START_EPOCH -eq 0 || $LEARN_END_EPOCH -eq 0 ]]; then
    echo "Ошибка: неверный формат даты."
    exit 1
fi

CURRENT_EPOCH=$LEARN_START_EPOCH
CHUNK_MINUTES=60
CHUNK_SECONDS=$((CHUNK_MINUTES * 60))

while [[ $CURRENT_EPOCH -lt $LEARN_END_EPOCH ]]; do
    NEXT_EPOCH=$((CURRENT_EPOCH + CHUNK_SECONDS))
    if [[ $NEXT_EPOCH -gt $LEARN_END_EPOCH ]]; then
        NEXT_EPOCH=$LEARN_END_EPOCH
    fi
    CURRENT_TS=$(date -u -d "@$CURRENT_EPOCH" +"%Y-%m-%d %H:%M:%S")
    NEXT_TS=$(date -u -d "@$NEXT_EPOCH" +"%Y-%m-%d %H:%M:%S")
    echo "  Обработка порции: $CURRENT_TS -> $NEXT_TS"
    psql -v ON_ERROR_STOP=1 -c "SELECT mchain_train_historical_chunk('$CURRENT_TS'::TIMESTAMPTZ, '$NEXT_TS'::TIMESTAMPTZ);"
    CURRENT_EPOCH=$NEXT_EPOCH
done

echo "=== Шаг 4: Восстановление триггера и обновление last_incident_time ==="
psql -v ON_ERROR_STOP=1 <<EOSQL
ALTER TABLE transition_log ENABLE TRIGGER trigger_update_incident_time;
UPDATE markov_config SET last_incident_time = (
    SELECT MAX(ts) FROM transition_log
    WHERE to_state IN (SELECT state_id FROM critical_states)
);
EOSQL

echo "=== Шаг 5: Обновление исходов прогнозов (для первоначального горизонта) ==="
psql -c "SELECT update_prediction_outcomes();"

echo "=== Шаг 6: Пересчёт вероятностей и поглощающей матрицы ==="
psql -v ON_ERROR_STOP=1 <<EOSQL
SELECT update_markov_probabilities();
SELECT rebuild_markov_absorbing();
EOSQL

# =============================================================================
# 7. Динамический подбор горизонта и итеративная коррекция
# =============================================================================
echo "=== Шаг 7: Динамический подбор оптимального горизонта ==="

# --- НАСТРОЙКИ ---
RISK_THRESHOLD=0.20
MAX_ITER=6
ITER=1
TARGET_INCIDENT_RATE=0.15
TOLERANCE=0.03

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

    # 2. Находим оптимальный горизонт
    OPTIMAL_HORIZON=$(psql -t -A -c "SELECT find_optimal_horizon(0.15, 5, 120, 5);")
    echo "  Оптимальный горизонт: $OPTIMAL_HORIZON минут"

    # 3. Устанавливаем горизонт и усиленные параметры забывания
    NEW_INTERVAL=$((2 * OPTIMAL_HORIZON))
    if [ $NEW_INTERVAL -lt 30 ]; then NEW_INTERVAL=30; fi
    if [ $NEW_INTERVAL -gt 720 ]; then NEW_INTERVAL=720; fi
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

    # 5. Обновляем исходы (циклически)
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

    RISK_THRESHOLD=$(echo "$RISK_THRESHOLD + 0.05" | bc)
    ITER=$((ITER + 1))
done

if [[ $ITER -gt $MAX_ITER ]]; then
    echo "⚠️  Не удалось достичь целевой доли инцидентов за $MAX_ITER итераций."
    echo "   Текущая доля: $INCIDENT_RATE, горизонт: $OPTIMAL_HORIZON, порог риска: $RISK_THRESHOLD"
    echo "   Рекомендуется ручная настройка или увеличение количества итераций."
fi

# =============================================================================
# 8. Усиленное забывание для стабилизации вероятностей
# =============================================================================
echo "=== Шаг 8: Применение усиленного забывания для стабилизации вероятностей ==="
psql -c "SELECT mchain_apply_forgetting(0.15);"
psql -c "SELECT refresh_stability_threshold();"

psql -v ON_ERROR_STOP=1 <<EOSQL
SELECT update_markov_probabilities();
SELECT rebuild_markov_absorbing();
EOSQL

# =============================================================================
# 9. Расчёт суточных метрик качества
# =============================================================================
echo "=== Шаг 9: Расчёт суточных метрик качества ==="
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
# 10. Проверка итогового состояния и формирование протокола
# =============================================================================
echo "=== Шаг 10: Проверка итогового состояния цепи ==="
RELIABILITY=$(psql -t -A -c "SELECT mchain_forecast_reliability();" | xargs)
echo "  Рейтинг достоверности: $RELIABILITY"

if [ "$RELIABILITY" -lt 3 ]; then
    echo "⚠️  Рейтинг достоверности < 3. Применяем дополнительное забывание с alpha=0.20..."
    psql -c "SELECT mchain_apply_forgetting(0.20);"
    psql -c "SELECT refresh_stability_threshold();"
    psql -v ON_ERROR_STOP=1 <<EOSQL
SELECT update_markov_probabilities();
SELECT rebuild_markov_absorbing();
EOSQL
    psql -c "SELECT recalculate_prediction_risks();"
    psql -c "SELECT update_prediction_outcomes();"
    RELIABILITY=$(psql -t -A -c "SELECT mchain_forecast_reliability();" | xargs)
    echo "  Рейтинг достоверности после дополнительного забывания: $RELIABILITY"
fi

# =============================================================================
# 11. Обновление training_end_time в markov_config (на случай, если оно изменилось)
# =============================================================================
echo "=== Шаг 11: Обновление training_end_time в markov_config ==="
psql -v ON_ERROR_STOP=1 <<EOSQL
UPDATE markov_config SET training_end_time = '$END_TIME'::TIMESTAMPTZ;
EOSQL

# =============================================================================
# Финальный протокол
# =============================================================================
echo ""
echo "=============================="
echo "    ИТОГОВЫЙ ПРОТОКОЛ"
echo "=============================="

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

echo ""
echo "--- 2. Статистика данных ---"
psql -t -A -c "
SELECT '  Всего переходов (transition_log): ' || COUNT(*) FROM transition_log;
SELECT '  Прогнозов всего: ' || COUNT(*) FROM prediction_log;
SELECT '  Прогнозов с известным исходом: ' || COUNT(*) FROM prediction_log WHERE actual_outcome IS NOT NULL;
SELECT '  Прогнозов с исходом 1: ' || COUNT(*) FROM prediction_log WHERE actual_outcome = 1;
"

CUR_INCIDENT_RATE=$(psql -t -A -c "SELECT COALESCE(AVG(actual_outcome), 0) FROM prediction_log WHERE actual_outcome IS NOT NULL;" | xargs)
echo "  Фактическая доля инцидентов среди прогнозов: $CUR_INCIDENT_RATE"
echo "  Рейтинг достоверности (mchain_forecast_reliability): $RELIABILITY"

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

CRIT_COUNT=$(psql -t -A -c "SELECT COUNT(*) FROM critical_states;" | xargs)
echo "  Количество критических состояний: $CRIT_COUNT"

LAST_INCIDENT=$(psql -t -A -c "SELECT format_timestamptz_to_minute(last_incident_time) FROM markov_config;" | xargs)
echo "  Последний инцидент: ${LAST_INCIDENT:-нет}"

ERRORS=$(psql -t -A -c "SELECT COUNT(*) FROM mchain_error_log;" | xargs)
echo "  Ошибок в логе: $ERRORS"
if [ "$ERRORS" -gt 0 ]; then
    echo "    Последние ошибки:"
    psql -t -A -c "SELECT function_name || ': ' || error_message FROM mchain_error_log ORDER BY ts DESC LIMIT 5;" | while read -r line; do echo "      $line"; done
fi

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