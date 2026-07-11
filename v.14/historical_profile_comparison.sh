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
# version 14.3
# Заполняет profile_comparison_log историческими сравнениями профилей,
# разбивая диапазон на куски по 1 дню.
# Использует процедуру historical_fill_profile_comparison_log.
# =============================================================================

set -euo pipefail

# Параметры подключения к БД (измените под себя)
DB_HOST="localhost"
DB_PORT="5432"
DB_NAME="expecto_db"
DB_USER="expecto_user"
export PGPASSWORD="${PGPASSWORD:-}"

# Параметры скрипта
START_DATE="${1:-}"   # формат 'YYYY-MM-DD' или 'YYYY-MM-DD HH:MI:SS'
END_DATE="${2:-}"     # аналогично
WINDOW_MINUTES="${3:-30}"
STEP_MINUTES="${4:-1}"
LOG_FILE="${5:-./historical_comparison.log}"

# Проверка обязательных параметров
if [[ -z "$START_DATE" || -z "$END_DATE" ]]; then
    echo "Использование: $0 <start_date> <end_date> [window_minutes] [step_minutes] [log_file]"
    echo "Пример: $0 '2026-06-01' '2026-06-07' 30 1 ./log.txt"
    exit 1
fi

# Проверка наличия psql
if ! command -v psql &> /dev/null; then
    echo "Ошибка: psql не найден. Установите PostgreSQL client."
    exit 1
fi

# Функция логирования
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Преобразование входных строк в даты (без времени)
start_day=$(date -d "$START_DATE" +%Y-%m-%d)
end_day=$(date -d "$END_DATE" +%Y-%m-%d)

if [[ -z "$start_day" || -z "$end_day" ]]; then
    log "Ошибка: не удалось распарсить даты."
    exit 1
fi

log "Запуск исторического заполнения profile_comparison_log по дням"
log "Диапазон: $start_day – $end_day, окно: $WINDOW_MINUTES мин, шаг: $STEP_MINUTES мин"
log "Лог-файл: $LOG_FILE"

# Количество дней в диапазоне
total_days=$(( ($(date -d "$end_day" +%s) - $(date -d "$start_day" +%s)) / 86400 + 1 ))
log "Всего дней для обработки: $total_days"

current_day="$start_day"
day_counter=0

while [[ $(date -d "$current_day" +%Y%m%d) -le $(date -d "$end_day" +%Y%m%d) ]]; do
    day_counter=$((day_counter + 1))
    
    # Начало дня (00:00:00)
    day_start="${current_day} 00:00:00"
    # Конец дня (23:59:59) – используем +1 день -1 секунда
    day_end=$(date -d "$current_day + 1 day - 1 second" '+%Y-%m-%d %H:%M:%S')
    
    log "--- День $day_counter/$total_days: $current_day ($day_start – $day_end) ---"
    
    # Формируем SQL-запрос
    SQL_CMD="CALL historical_fill_profile_comparison_log(
        '$day_start'::timestamptz,
        '$day_end'::timestamptz,
        $WINDOW_MINUTES,
        $STEP_MINUTES,
        TRUE
    );"
    
    # Выполняем и перенаправляем вывод в лог (stdout+stderr)
    if psql -h "$DB_HOST" -p "$DB_PORT" -d "$DB_NAME" -U "$DB_USER" -c "$SQL_CMD" >> "$LOG_FILE" 2>&1; then
        log "День $current_day обработан успешно."
    else
        log "ОШИБКА при обработке дня $current_day. Прерывание."
        exit 1
    fi
    
    # Переходим к следующему дню
    current_day=$(date -d "$current_day + 1 day" +%Y-%m-%d)
done

log "Все дни обработаны. Заполнение завершено."