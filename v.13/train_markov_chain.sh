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
# version 13.1
#
# Скрипт для исторического обучения цепи Маркова на основе данных из cluster_stat_median.
# Скрипт исторического обучения цепи Маркова с пакетной обработкой (почасово)
# для предотвращения переполнения разделяемой памяти блокировками.
# Использование:
#   ./train_markov_chain.sh [YYYY-MM-DD HH:MI:SS]
#   Если аргумент не указан, используется текущее время (UTC) как правая граница.
# ./train_markov_chain.sh > train_markov_chain.log 2>&1
# tail -f train_markov_chain.log | grep -E "Начало обучения порции|Порция завершена|Diagnostic|Готово"

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

# ---------------------- 0. Полная очистка данных модели -----------------------
echo "=== Шаг 0: Очистка всех таблиц цепи Маркова (кроме конфигурации) ==="
psql -v ON_ERROR_STOP=1 <<-EOSQL
    TRUNCATE TABLE transition_log RESTART IDENTITY CASCADE;
    TRUNCATE TABLE markov_frequencies RESTART IDENTITY CASCADE;
    TRUNCATE TABLE markov_probabilities RESTART IDENTITY CASCADE;
    TRUNCATE TABLE markov_chain RESTART IDENTITY CASCADE;
    TRUNCATE TABLE prediction_log RESTART IDENTITY CASCADE;
    TRUNCATE TABLE apply_forgetting_log RESTART IDENTITY CASCADE;
    TRUNCATE TABLE mchain_error_log RESTART IDENTITY CASCADE;
    TRUNCATE TABLE mchain_quality_metrics_history RESTART IDENTITY CASCADE;
    -- Сброс last_forget_time на начало периода (будет установлено точно позже)
    UPDATE markov_config SET last_forget_time = (SELECT MIN(curr_timestamp) FROM cluster_stat_median);
EOSQL

echo "=== Шаг 1: Заполнение performance_history (при необходимости) ==="
# Получаем начальную метку времени в секундах (UNIX epoch) из базы
START_EPOCH=$(psql -t -c "SELECT EXTRACT(EPOCH FROM MIN(curr_timestamp))::BIGINT FROM cluster_stat_median;" | xargs)
if [[ -z "$START_EPOCH" || "$START_EPOCH" == "0" ]]; then
    echo "Ошибка: нет данных в cluster_stat_median или MIN(curr_timestamp) равен NULL."
    exit 1
fi

# Преобразуем END_TIME в секунды
END_EPOCH=$(date -u -d "$END_TIME" +%s 2>/dev/null || echo 0)
if [[ $END_EPOCH -eq 0 ]]; then
    echo "Ошибка: неверный формат END_TIME: $END_TIME. Ожидается YYYY-MM-DD HH:MI:SS"
    exit 1
fi

# Строковое представление начальной даты для вывода и для SQL
START_DATE=$(date -u -d "@$START_EPOCH" +"%Y-%m-%d %H:%M:%S")
echo "Начальная дата: $START_DATE (UNIX $START_EPOCH)"

# Заполняем performance_history, если она пуста или не покрывает весь период
psql -v ON_ERROR_STOP=1 <<-EOSQL
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
    # Преобразуем эпохи в строки для передачи в SQL
    CURRENT_TS=$(date -u -d "@$CURRENT_EPOCH" +"%Y-%m-%d %H:%M:%S")
    NEXT_TS=$(date -u -d "@$NEXT_EPOCH" +"%Y-%m-%d %H:%M:%S")

    echo "  Обработка порции: $CURRENT_TS -> $NEXT_TS"
    psql -v ON_ERROR_STOP=1 -c "SELECT mchain_train_historical_chunk('$CURRENT_TS'::TIMESTAMPTZ, '$NEXT_TS'::TIMESTAMPTZ);"

    CURRENT_EPOCH=$NEXT_EPOCH
done

echo "=== Шаг 3: Восстановление триггера и обновление last_incident_time ==="
psql -v ON_ERROR_STOP=1 <<-EOSQL
    ALTER TABLE transition_log ENABLE TRIGGER trigger_update_incident_time;
    UPDATE markov_config SET last_incident_time = (
        SELECT MAX(ts) FROM transition_log
        WHERE to_state IN (SELECT state_id FROM critical_states)
    );
EOSQL

echo "=== Шаг 4: Обновление исходов прогнозов ==="
psql -c "SELECT update_prediction_outcomes();"

echo "=== Шаг 5: Пересчёт вероятностей и поглощающей матрицы ==="
psql -v ON_ERROR_STOP=1 <<-EOSQL
    SELECT update_markov_probabilities();
    SELECT rebuild_markov_absorbing();
EOSQL

echo "=== Шаг 5.1: Пересчёт прогнозов на финальной модели ==="
psql -c "SELECT recalculate_prediction_risks();"

echo "=== Шаг 6: Расчёт суточных метрик качества ==="
# Получаем минимальную и максимальную даты для расчёта метрик
START_DATE_METRICS=$(psql -t -c "SELECT to_char(MIN(ts), 'YYYY-MM-DD') FROM transition_log;" | xargs)
END_DATE_METRICS=$(psql -t -c "SELECT to_char('$END_TIME'::TIMESTAMPTZ, 'YYYY-MM-DD');" | xargs)
if [[ -z "$START_DATE_METRICS" || -z "$END_DATE_METRICS" ]]; then
    echo "Предупреждение: не удалось определить даты для расчёта метрик."
else
    CURRENT_DATE="$START_DATE_METRICS"
    while [[ $(date -d "$CURRENT_DATE" +%s) -le $(date -d "$END_DATE_METRICS" +%s) ]]; do
        echo "  Расчёт метрик за $CURRENT_DATE"
        psql -c "SELECT calculate_daily_quality_metrics('$CURRENT_DATE'::DATE, 30);"
        CURRENT_DATE=$(date -d "$CURRENT_DATE + 1 day" +"%Y-%m-%d")
    done
fi

echo "=== Готово! Историческое обучение завершено ==="