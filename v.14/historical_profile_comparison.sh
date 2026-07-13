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
# =============================================================================
# historical_profile_comparison.sh
# version 14.6
# Заполняет profile_comparison_log историческими сравнениями профилей,
# разбивая диапазон на куски по 1 дню.
# Использует процедуру historical_fill_profile_comparison_log.
#
# Режимы работы (только два варианта):
#   1) Без аргументов – все параметры по умолчанию:
#        START_DATE = MIN(prediction_time) из БД,
#        END_DATE   = текущее время,
#        WINDOW_MINUTES = 60,
#        STEP_MINUTES   = 1,
#        LOG_FILE = ./historical_comparison.log
#   2) С пятью аргументами – все параметры задаются явно:
#        $0 <start_date> <end_date> <window_minutes> <step_minutes> <log_file>
#        Формат дат: 'YYYY-MM-DD HH24:MI'
# =============================================================================

set -euo pipefail

# Параметры подключения к БД (измените под себя)
DB_HOST="localhost"
DB_PORT="5432"
DB_NAME="expecto_db"
DB_USER="expecto_user"
export PGPASSWORD="${PGPASSWORD:-}"

# Проверка наличия psql
if ! command -v psql &> /dev/null; then
    echo "Ошибка: psql не найден. Установите PostgreSQL client."
    exit 1
fi

# Функция логирования (используется после определения параметров)
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# --- Обработка аргументов ---
EXPECTED_ARGS=5
ARGC=$#

if [[ $ARGC -eq 0 ]]; then
    # Режим 1: все по умолчанию
    echo "Режим: все параметры по умолчанию."

    # Получаем START_DATE из БД
    SQL_GET_MIN="SELECT to_char(min(prediction_time), 'YYYY-MM-DD HH24:MI') FROM prediction_log;"
    START_DATE=$(psql -h "$DB_HOST" -p "$DB_PORT" -d "$DB_NAME" -U "$DB_USER" -t -A -c "$SQL_GET_MIN" 2>/dev/null || true)

    if [[ -z "$START_DATE" || "$START_DATE" == "NULL" ]]; then
        echo "Ошибка: не удалось получить минимальное prediction_time из таблицы prediction_log."
        echo "Возможно, таблица пуста или не существует."
        exit 1
    fi

    # Остальные параметры по умолчанию
    END_DATE=$(date '+%Y-%m-%d %H:%M')
    WINDOW_MINUTES=60
    STEP_MINUTES=1
    LOG_FILE="./historical_comparison.log"

elif [[ $ARGC -eq $EXPECTED_ARGS ]]; then
    # Режим 2: все параметры заданы явно
    START_DATE="$1"
    END_DATE="$2"
    WINDOW_MINUTES="$3"
    STEP_MINUTES="$4"
    LOG_FILE="$5"

    # Проверяем, что WINDOW_MINUTES и STEP_MINUTES - числа
    if ! [[ "$WINDOW_MINUTES" =~ ^[0-9]+$ ]] || ! [[ "$STEP_MINUTES" =~ ^[0-9]+$ ]]; then
        echo "Ошибка: WINDOW_MINUTES и STEP_MINUTES должны быть целыми положительными числами."
        exit 1
    fi

else
    echo "Ошибка: неверное количество аргументов."
    echo "Использование:"
    echo "  Без аргументов (всё по умолчанию): $0"
    echo "  Все параметры явно: $0 <start_date> <end_date> <window_minutes> <step_minutes> <log_file>"
    echo "Формат дат: 'YYYY-MM-DD HH24:MI' (например, '2026-06-01 10:30')"
    exit 1
fi

# --- Проверка и преобразование дат ---
start_full="$START_DATE"
end_full="$END_DATE"

# Извлечение даты без времени для итерации по дням
start_date_only=$(date -d "$start_full" +%Y-%m-%d 2>/dev/null || true)
end_date_only=$(date -d "$end_full" +%Y-%m-%d 2>/dev/null || true)

if [[ -z "$start_date_only" || -z "$end_date_only" ]]; then
    log "Ошибка: не удалось распарсить даты. Убедитесь в формате 'YYYY-MM-DD HH24:MI'."
    exit 1
fi

# Проверка, что START_DATE <= END_DATE
start_epoch=$(date -d "$start_full" +%s 2>/dev/null || true)
end_epoch=$(date -d "$end_full" +%s 2>/dev/null || true)
if [[ -z "$start_epoch" || -z "$end_epoch" || $start_epoch -gt $end_epoch ]]; then
    log "Ошибка: START_DATE должна быть меньше или равна END_DATE."
    exit 1
fi

# --- Основной цикл ---
log "Запуск исторического заполнения profile_comparison_log по дням"
log "Диапазон: $start_full – $end_full, окно: $WINDOW_MINUTES мин, шаг: $STEP_MINUTES мин"
log "Лог-файл: $LOG_FILE"

total_days=$(( ($(date -d "$end_date_only" +%s) - $(date -d "$start_date_only" +%s)) / 86400 + 1 ))
log "Всего дней для обработки: $total_days"

current_day="$start_date_only"
day_counter=0

while [[ $(date -d "$current_day" +%Y%m%d 2>/dev/null || echo "0") -le $(date -d "$end_date_only" +%Y%m%d 2>/dev/null || echo "0") ]]; do
    day_counter=$((day_counter + 1))

    # Определяем границы текущего дня с учётом точного времени начала и конца диапазона
    if [[ "$current_day" == "$start_date_only" && "$current_day" == "$end_date_only" ]]; then
        day_start="$start_full"
        day_end="$end_full"
    elif [[ "$current_day" == "$start_date_only" ]]; then
        day_start="$start_full"
        day_end=$(date -d "$current_day 23:59:59" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "")
    elif [[ "$current_day" == "$end_date_only" ]]; then
        day_start=$(date -d "$current_day 00:00:00" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "")
        day_end="$end_full"
    else
        day_start=$(date -d "$current_day 00:00:00" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "")
        day_end=$(date -d "$current_day 23:59:59" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "")
    fi

    if [[ -z "$day_start" || -z "$day_end" ]]; then
        log "Ошибка при вычислении границ дня $current_day. Прерывание."
        exit 1
    fi

    log "--- День $day_counter/$total_days: $current_day ($day_start – $day_end) ---"

    SQL_CMD="CALL historical_fill_profile_comparison_log(
        '$day_start'::timestamptz,
        '$day_end'::timestamptz,
        $WINDOW_MINUTES,
        $STEP_MINUTES,
        TRUE
    );"

    if psql -h "$DB_HOST" -p "$DB_PORT" -d "$DB_NAME" -U "$DB_USER" -c "$SQL_CMD" >> "$LOG_FILE" 2>&1; then
        log "День $current_day обработан успешно."
    else
        log "ОШИБКА при обработке дня $current_day. Прерывание."
        exit 1
    fi

    current_day=$(date -d "$current_day + 1 day" +%Y-%m-%d 2>/dev/null || echo "")
    if [[ -z "$current_day" ]]; then
        log "Ошибка при переходе к следующему дню. Прерывание."
        exit 1
    fi
done

log "Все дни обработаны. Заполнение завершено."
