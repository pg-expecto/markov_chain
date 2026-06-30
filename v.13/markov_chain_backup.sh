#!/bin/bash
# Copyright 2026 Ринат (markov_chain)
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
# markov_chain_backup.sh – бекап и восстановление Марковской цепи с пост-восстановительными проверками
# и с восстановлением пропущенных переходов
# Использование: ./markov_chain_backup.sh {backup|restore}
######################################################################
# Бекап
# ./markov_chain_backup.sh backup
# Файл сохранится в /tmp/markov_chain_backup_YYYYMMDD_HHMMSS.dump.
# 
# Восстановление
# ./markov_chain_backup.sh restore
# Будет автоматически взят самый свежий файл бекапа из /tmp. Перед восстановлением запрашивается подтверждение.
# 
# Примечания
# Все параметры подключения жёстко зафиксированы (expecto_db, expecto_user, localhost, 5432).
# 
# Для аутентификации можно использовать переменную PGPASSWORD или настроить .pgpass.
# 
# Скрипт предполагает, что утилиты pg_dump и pg_restore установлены и доступны в PATH.
######################################################################

set -euo pipefail

DB_NAME="expecto_db"
DB_USER="expecto_user"
DB_HOST="localhost"
DB_PORT="5432"
BACKUP_DIR="/tmp"
BACKUP_PREFIX="markov_chain_tables"

ACTION="${1:-}"

if [[ -z "$ACTION" ]]; then
    echo "Ошибка: укажите действие: backup или restore"
    exit 1
fi

if [[ "$ACTION" != "backup" && "$ACTION" != "restore" ]]; then
    echo "Ошибка: действие должно быть 'backup' или 'restore'"
    exit 1
fi

# Список таблиц, относящихся к цепи Маркова (включая вспомогательные)
TABLES=(
    "markov_config"
    "mchain_error_log"
    "markov_frequencies"
    "transition_log"
    "markov_probabilities"
    "markov_absorbing"
    "state_descriptions"
    "markov_chain"
    "apply_forgetting_log"
    "prediction_log"
    "mchain_quality_metrics_history"
    "mchain_quality_errors"
    "critical_states"
    "forgetting_optimization_log"
    "backup_metadata"
)

# Формируем строку параметров -t для pg_dump
TABLE_ARGS=""
for tbl in "${TABLES[@]}"; do
    TABLE_ARGS+=" -t $tbl"
done

# Функция выполнения SQL-запроса и вывода результата (без возврата значения)
run_sql() {
    local sql="$1"
    local label="$2"
    echo "   ➜ $label"
    PGPASSWORD="${PGPASSWORD:-}" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "$sql" 2>&1 | sed 's/^/      /'
}

# Функция выполнения SQL-запроса, возвращающего одно значение (в виде строки)
run_sql_scalar() {
    local sql="$1"
    PGPASSWORD="${PGPASSWORD:-}" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "$sql" | xargs
}

# Проверка/создание таблицы backup_metadata (если её нет)
ensure_backup_metadata() {
    run_sql "
        CREATE TABLE IF NOT EXISTS backup_metadata (
            id SERIAL PRIMARY KEY,
            backup_time TIMESTAMPTZ NOT NULL,
            created_at TIMESTAMPTZ DEFAULT now()
        );
    " "Проверка/создание таблицы backup_metadata"
}

# Проверка существования вспомогательных функций (get_state_at_time, fill_missing_transitions)
ensure_helper_functions() {
    local func_exists=$(PGPASSWORD="${PGPASSWORD:-}" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT COUNT(*) FROM pg_proc WHERE proname = 'get_state_at_time';")
    if [[ "$func_exists" -eq 0 ]]; then
        echo "⚠️  Функция get_state_at_time не найдена. Создайте её перед использованием restore."
        exit 1
    fi
    func_exists=$(PGPASSWORD="${PGPASSWORD:-}" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT COUNT(*) FROM pg_proc WHERE proname = 'fill_missing_transitions';")
    if [[ "$func_exists" -eq 0 ]]; then
        echo "⚠️  Функция fill_missing_transitions не найдена. Создайте её перед использованием restore."
        exit 1
    fi
    echo "   ✅ Вспомогательные функции найдены."
}

do_backup() {
    ensure_backup_metadata
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="${BACKUP_DIR}/${BACKUP_PREFIX}_${timestamp}.dump"
    echo "▶️  Создание выборочного бекапа таблиц цепи Маркова в ${backup_file}..."
    local start_time=$(date +%s)
    PGPASSWORD="${PGPASSWORD:-}" pg_dump -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" \
        -Fc $TABLE_ARGS -f "$backup_file" "$DB_NAME"
    if [[ $? -eq 0 ]]; then
        local end_time=$(date +%s)
        local elapsed=$((end_time - start_time))
        local size=$(du -h "$backup_file" | cut -f1)
        echo "✅ Бекап создан: ${backup_file} (размер: ${size}, время: ${elapsed} сек)"
        # Запись времени бекапа в таблицу
        run_sql "INSERT INTO backup_metadata (backup_time) VALUES (now());" "Сохранение времени бекапа"
    else
        echo "❌ Ошибка при создании бекапа"
        exit 1
    fi
}

do_restore() {
    local overall_start=$(date +%s)

    # Находим последний файл бекапа
    local backup_file=$(ls -t ${BACKUP_DIR}/${BACKUP_PREFIX}_*.dump 2>/dev/null | head -n1)
    if [[ -z "$backup_file" ]]; then
        echo "❌ Не найден ни один файл бекапа в ${BACKUP_DIR}"
        exit 1
    fi

    local backup_size=$(du -h "$backup_file" | cut -f1)
    local backup_basename=$(basename "$backup_file")
    echo "▶️  Восстановление таблиц цепи Маркова из ${backup_file}"
    echo "   Размер файла: ${backup_size}"
    echo "   База данных: ${DB_NAME} на ${DB_HOST}:${DB_PORT}"
    echo "   ВНИМАНИЕ: все таблицы цепи Маркова в базе будут заменены данными из бекапа!"
    read -p "   Продолжить? [y/N]: " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Отмена."
        exit 0
    fi

    # Восстановление только таблиц (с очисткой)
    echo "▶️  Восстановление данных (pg_restore) ..."
    local restore_start=$(date +%s)
    # pg_restore может возвращать ненулевой код из-за нефатальных ошибок (например, параметры сессии)
    # Поэтому мы не прерываем скрипт, а лишь выводим предупреждение и продолжаем.
    if PGPASSWORD="${PGPASSWORD:-}" pg_restore -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" \
        --clean --if-exists --dbname="$DB_NAME" "$backup_file"; then
        local restore_end=$(date +%s)
        echo "✅ Восстановление таблиц завершено за $((restore_end - restore_start)) сек."
    else
        local rc=$?
        local restore_end=$(date +%s)
        echo "⚠️  pg_restore завершился с кодом $rc. Возможны предупреждения (например, о параметрах), но данные могли быть восстановлены."
        echo "   Продолжаем пост-восстановительные операции."
        # Не выходим, продолжаем
    fi

    # Пост-восстановительные шаги
    echo ""
    echo "▶️  Выполнение пост-восстановительных операций..."

    # Проверка наличия вспомогательных функций
    ensure_helper_functions

    # 1. Обновление текущего состояния
    echo "   ➜ Обновление текущего состояния (mchain_train_step)"
    local step_start=$(date +%s)
    run_sql "SELECT mchain_train_step();" "Обновление текущего состояния"
    local step_end=$(date +%s)
    echo "      Выполнено за $((step_end - step_start)) сек."

    # 2. Получение времени бекапа из таблицы backup_metadata
    local backup_ts=$(run_sql_scalar "SELECT backup_time FROM backup_metadata ORDER BY id DESC LIMIT 1;")
    local fill_result=""
    if [[ -z "$backup_ts" ]]; then
        echo "⚠️  Не найдено время бекапа. Пропускаем восстановление переходов."
    else
        echo "   ➜ Восстановление переходов за пропущенный период (fill_missing_transitions)"
        echo "      Время бекапа: $backup_ts, текущее время: $(date +'%Y-%m-%d %H:%M:%S%z')"
        local fill_start=$(date +%s)
        # Выполняем и сохраняем результат
        fill_result=$(PGPASSWORD="${PGPASSWORD:-}" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT fill_missing_transitions('$backup_ts'::timestamptz, now());" | xargs)
        local fill_end=$(date +%s)
        echo "      Результат: $fill_result"
        echo "      Выполнено за $((fill_end - fill_start)) сек."
    fi

    # 3. Пересчёт критических состояний
    echo "   ➜ Обновление критических состояний (refresh_critical_states)"
    local crit_start=$(date +%s)
    run_sql "SELECT refresh_critical_states(p_start => now() - interval '14 days', p_end => now(), p_min_transitions => 50, p_risk_threshold => 0.10, p_dry_run => FALSE);" "Обновление критических состояний"
    local crit_end=$(date +%s)
    echo "      Выполнено за $((crit_end - crit_start)) сек."

    # 4. Принудительный пересчёт вероятностей и поглощающей матрицы
    echo "   ➜ Пересчёт вероятностей (update_markov_probabilities)"
    local prob_start=$(date +%s)
    run_sql "SELECT update_markov_probabilities();" "Пересчёт вероятностей"
    local prob_end=$(date +%s)
    echo "      Выполнено за $((prob_end - prob_start)) сек."

    echo "   ➜ Пересчёт поглощающей матрицы (rebuild_markov_absorbing)"
    local abs_start=$(date +%s)
    run_sql "SELECT rebuild_markov_absorbing();" "Пересчёт поглощающей матрицы"
    local abs_end=$(date +%s)
    echo "      Выполнено за $((abs_end - abs_start)) сек."

    # 5. Проверка прогноза
    echo "   ➜ Проверка прогноза (mchain_predict_risk_current_horizon)"
    local pred_result=$(run_sql_scalar "SELECT mchain_predict_risk_current_horizon();")
    echo "      Прогноз риска: $pred_result (ожидается число от 0 до 1)"

    # Итоговый отчёт
    local overall_end=$(date +%s)
    local total_elapsed=$((overall_end - overall_start))
    echo ""
    echo "══════════════════════════════════════════════════════════════════"
    echo "  ✅ Восстановление успешно завершено!"
    echo "══════════════════════════════════════════════════════════════════"
    echo "  Файл бекапа        : $backup_basename (размер $backup_size)"
    echo "  Таблиц восстановлено: ${#TABLES[@]}"
    if [[ -n "$restore_end" && -n "$restore_start" ]]; then
        echo "  Восстановление таблиц: $((restore_end - restore_start)) сек."
    else
        echo "  Восстановление таблиц: время не определено (возможна ошибка)"
    fi
    if [[ -n "$fill_result" ]]; then
        echo "  Восстановлено переходов: $fill_result"
    else
        echo "  Восстановление переходов: пропущено (нет времени бекапа)"
    fi
    echo "  Прогноз риска      : $pred_result"
    echo "  Общее время        : ${total_elapsed} сек."
    echo "══════════════════════════════════════════════════════════════════"
    echo "   Цепь Маркова готова к работе."
}

case "$ACTION" in
    backup)
        do_backup
        ;;
    restore)
        do_restore
        ;;
esac