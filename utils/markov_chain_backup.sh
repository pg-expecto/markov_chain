#!/bin/bash
# markov_chain_backup.sh – бекап и восстановление Марковской цепи с пост-восстановительными проверками и с восстановлением пропущенных переходов
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

#!/bin/bash
# markov_chain_backup.sh – бекап и восстановление ТОЛЬКО таблиц цепи Маркова
# (без других объектов базы данных)
# Использование: ./markov_chain_backup.sh {backup|restore}

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

# Функция выполнения SQL-запроса и вывода результата
run_sql() {
    local sql="$1"
    local label="$2"
    echo "   ➜ $label"
    PGPASSWORD="${PGPASSWORD:-}" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "$sql" 2>&1 | sed 's/^/      /'
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
}

do_backup() {
    ensure_backup_metadata
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="${BACKUP_DIR}/${BACKUP_PREFIX}_${timestamp}.dump"
    echo "▶️  Создание выборочного бекапа таблиц цепи Маркова в ${backup_file}..."
    # Используем pg_dump с явным списком таблиц
    PGPASSWORD="${PGPASSWORD:-}" pg_dump -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" \
        -Fc $TABLE_ARGS -f "$backup_file" "$DB_NAME"
    if [[ $? -eq 0 ]]; then
        echo "✅ Бекап создан: ${backup_file}"
        # Запись времени бекапа в таблицу (она есть в бекапе, но мы запишем отдельно, чтобы после восстановления она была)
        run_sql "INSERT INTO backup_metadata (backup_time) VALUES (now());" "Сохранение времени бекапа"
    else
        echo "❌ Ошибка при создании бекапа"
        exit 1
    fi
}

do_restore() {
    # Находим последний файл бекапа
    local backup_file=$(ls -t ${BACKUP_DIR}/${BACKUP_PREFIX}_*.dump 2>/dev/null | head -n1)
    if [[ -z "$backup_file" ]]; then
        echo "❌ Не найден ни один файл бекапа в ${BACKUP_DIR}"
        exit 1
    fi

    echo "▶️  Восстановление таблиц цепи Маркова из ${backup_file}..."
    echo "   ВНИМАНИЕ: все таблицы цепи Маркова в базе ${DB_NAME} будут заменены данными из бекапа!"
    read -p "   Продолжить? [y/N]: " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Отмена."
        exit 0
    fi

    # Восстановление только таблиц (с очисткой)
    PGPASSWORD="${PGPASSWORD:-}" pg_restore -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" \
        --clean --if-exists --dbname="$DB_NAME" "$backup_file"
    if [[ $? -ne 0 ]]; then
        echo "❌ Ошибка при восстановлении"
        exit 1
    fi
    echo "✅ Восстановление таблиц завершено."

    # Пост-восстановительные шаги
    echo ""
    echo "▶️  Выполнение пост-восстановительных операций..."

    # Проверка наличия вспомогательных функций (они не были в бекапе, но должны существовать)
    ensure_helper_functions

    # 1. Обновление текущего состояния
    run_sql "SELECT mchain_train_step();" "Обновление текущего состояния (mchain_train_step)"

    # 2. Получение времени бекапа из таблицы backup_metadata (она уже восстановлена)
    local backup_ts=$(PGPASSWORD="${PGPASSWORD:-}" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT backup_time FROM backup_metadata ORDER BY id DESC LIMIT 1;")
    if [[ -z "$backup_ts" ]]; then
        echo "⚠️  Не найдено время бекапа. Пропускаем восстановление переходов."
    else
        backup_ts=$(echo "$backup_ts" | xargs)
        echo "   Время бекапа: $backup_ts"
        run_sql "SELECT fill_missing_transitions('$backup_ts'::timestamptz, now());" "Восстановление переходов за пропущенный период"
    fi

    # 3. Пересчёт критических состояний
    run_sql "SELECT refresh_critical_states(p_start => now() - interval '14 days', p_end => now(), p_min_transitions => 50, p_risk_threshold => 0.10, p_dry_run => FALSE);" "Обновление критических состояний (refresh_critical_states)"

    # 4. Принудительный пересчёт вероятностей и поглощающей матрицы (на всякий случай)
    run_sql "SELECT update_markov_probabilities();" "Пересчёт вероятностей"
    run_sql "SELECT rebuild_markov_absorbing();" "Пересчёт поглощающей матрицы"

    # 5. Проверка прогноза
    run_sql "SELECT mchain_predict_risk_current_horizon();" "Проверка прогноза (должен вернуть число от 0 до 1)"

    echo ""
    echo "✅ Все пост-восстановительные операции успешно выполнены."
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