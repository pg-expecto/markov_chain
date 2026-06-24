#!/bin/bash
# =============================================================================
# optimize_forgetting.sh
# Скрипт для запуска процедуры optimize_forgetting_params с мониторингом прогресса
# Логирование в /tmp/optimize_forgetting_params.log
# =============================================================================
# Использование:
#   ./optimize_forgetting.sh [dry_run] [verbose] [commit_every]
#
# Параметры (все опциональны):
#   dry_run      - true/false (по умолчанию false)
#   verbose      - true/false (по умолчанию true)
#   commit_every - число итераций между COMMIT (по умолчанию 1)
#
# Пример:
#   ./optimize_forgetting.sh true true 1
#   ./optimize_forgetting.sh false true 5
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Конфигурация подключения к БД (переопределяется переменными окружения)
# -----------------------------------------------------------------------------
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-expecto_db}"
DB_USER="${DB_USER:-expecto_user}"
# Пароль можно задать через PGPASSWORD или в файле .pgpass

# -----------------------------------------------------------------------------
# Параметры скрипта
# -----------------------------------------------------------------------------
LOG_FILE="/tmp/optimize_forgetting_params.log"
DRY_RUN="${1:-false}"
VERBOSE="${2:-true}"
COMMIT_EVERY="${3:-1}"

# -----------------------------------------------------------------------------
# Проверка наличия psql
# -----------------------------------------------------------------------------
if ! command -v psql &>/dev/null; then
    echo "Ошибка: psql не найден. Установите PostgreSQL client."
    exit 1
fi

# -----------------------------------------------------------------------------
# Очистка лог-файла и подготовка SQL-скрипта
# -----------------------------------------------------------------------------
> "$LOG_FILE"

SQL_FILE=$(mktemp /tmp/optimize_call_XXXXXX.sql)
trap 'rm -f "$SQL_FILE"' EXIT

cat > "$SQL_FILE" <<EOF
DO \$\$
DECLARE
    res TEXT;
BEGIN
    CALL optimize_forgetting_params(
        result => res,
        p_dry_run => $DRY_RUN,
        p_verbose => $VERBOSE,
        p_commit_every => $COMMIT_EVERY
    );
    RAISE NOTICE 'Final result: %', res;
END \$\$;
EOF

# -----------------------------------------------------------------------------
# Запуск с мониторингом
# -----------------------------------------------------------------------------
echo "======================================================================" | tee -a "$LOG_FILE"
echo "Запуск оптимизации параметров забывания $(date)" | tee -a "$LOG_FILE"
echo "Параметры: dry_run=$DRY_RUN, verbose=$VERBOSE, commit_every=$COMMIT_EVERY" | tee -a "$LOG_FILE"
echo "Лог-файл: $LOG_FILE" | tee -a "$LOG_FILE"
echo "======================================================================" | tee -a "$LOG_FILE"

# Запускаем tail в фоне для вывода прогресса в реальном времени
tail -f "$LOG_FILE" &
TAIL_PID=$!

# Выполняем SQL-скрипт через psql
psql -h "$DB_HOST" -p "$DB_PORT" -d "$DB_NAME" -U "$DB_USER" -f "$SQL_FILE" >> "$LOG_FILE" 2>&1
PSQL_EXIT=$?

# Останавливаем tail
kill $TAIL_PID 2>/dev/null

# -----------------------------------------------------------------------------
# Завершение
# -----------------------------------------------------------------------------
echo "======================================================================" | tee -a "$LOG_FILE"
echo "Оптимизация завершена $(date) с кодом возврата $PSQL_EXIT" | tee -a "$LOG_FILE"
echo "Последние строки лога:" | tee -a "$LOG_FILE"
tail -n 20 "$LOG_FILE"

if [ $PSQL_EXIT -eq 0 ]; then
    echo "Успешно завершено." | tee -a "$LOG_FILE"
else
    echo "Ошибка при выполнении (код $PSQL_EXIT). Проверьте лог-файл." | tee -a "$LOG_FILE"
fi

exit $PSQL_EXIT