--------------------------------------------------------------------------------
-- markov_chain_backup_tables.sql
-- Таблицы восстановление реальных переходов из внешних логов
-- для обеспечения скрипта 
-- markov_chain_backup.sh
--------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS backup_metadata (
    id SERIAL PRIMARY KEY,
    backup_time TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);