-- Copyright 2026 Ринат (markov_chain)
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
-- 
-- http://www.apache.org/licenses/LICENSE-2.0
-- 
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
--------------------------------------------------------------------------------
-- markov_chain_profile_tables.sql
-- version 14.3
--------------------------------------------------------------------------------
-- Таблицы для расчета метрик профиля нагрузки на основе цепи Маркова 
--------------------------------------------------------------------------------

-- ============================================================================
-- 13. Таблицы для профилирования производительности на основе цепи Маркова
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 13.1. Агрегированные профили (оперативный, суточный, недельный)
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS profile_aggregated;
CREATE TABLE profile_aggregated (
    id                  BIGSERIAL PRIMARY KEY,
    profile_type        TEXT NOT NULL ,
    ts                  TIMESTAMPTZ NOT NULL,          -- Время формирования профиля (верхняя граница окна)
    hour                SMALLINT NOT NULL,             -- Час дня (0–23) для привязки к сезонности
    dow                 SMALLINT NOT NULL,             -- День недели (0–6, 0 = воскресенье)
    window_start        TIMESTAMPTZ NOT NULL,          -- Начало окна
    window_end          TIMESTAMPTZ NOT NULL,          -- Конец окна

    -- Метрики профиля
    state_histogram     JSONB NOT NULL,                -- {state_id: доля} – гистограмма состояний
    avg_correlation     REAL,                          -- Средняя корреляция
    critical_ratio      REAL,                          -- Доля времени в критических состояниях
    entropy             REAL,                          -- Энтропия распределения состояний
    avg_os_angle        REAL,                          -- Средний угол наклона OS
    avg_wait_angle      REAL,                          -- Средний угол наклона Wait
    unique_states_count INT,                           -- Количество уникальных состояний
    avg_transition_length REAL,                        -- Средняя длина перехода (|from - to|)
    self_loop_ratio     REAL,                          -- Доля петель (from_state = to_state)
    top_transition      JSONB                          -- {from_state, to_state, frequency} – самый частый переход
);

COMMENT ON TABLE profile_aggregated IS 'Агрегированные профили производительности (оперативные, суточные, недельные)';
COMMENT ON COLUMN profile_aggregated.profile_type IS 'Тип профиля: operational – последние 60 мин, daily – последние 24 ч, weekly – последние 7 дней';
COMMENT ON COLUMN profile_aggregated.ts IS 'Время расчёта профиля (верхняя граница окна)';
COMMENT ON COLUMN profile_aggregated.hour IS 'Час дня (0–23) – используется для сезонного сравнения';
COMMENT ON COLUMN profile_aggregated.dow IS 'День недели (0–6) – используется для сезонного сравнения';
COMMENT ON COLUMN profile_aggregated.state_histogram IS 'Гистограмма состояний: JSON-объект вида {"state_id": доля_времени}';
COMMENT ON COLUMN profile_aggregated.critical_ratio IS 'Доля переходов, завершившихся в критическом состоянии';
COMMENT ON COLUMN profile_aggregated.entropy IS 'Энтропия Шеннона распределения состояний (бит)';
COMMENT ON COLUMN profile_aggregated.top_transition IS 'Самый частый переход в окне: {"from_state": ..., "to_state": ..., "frequency": ...}';

-- Индексы для быстрых выборок
CREATE INDEX idx_profile_aggregated_ts ON profile_aggregated (ts);
CREATE INDEX idx_profile_aggregated_type_ts ON profile_aggregated (profile_type, ts);
CREATE INDEX idx_profile_aggregated_hour_dow ON profile_aggregated (hour, dow);
ALTER TABLE profile_aggregated ADD CONSTRAINT profile_aggregated_profile_type_check CHECK (profile_type IN ('operational', 'daily', 'weekly', 'baseline', 'current'));

-- ----------------------------------------------------------------------------
-- 13.2. Эталонные профили (база для сравнения)
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS profile_baseline;
CREATE TABLE profile_baseline (
    id                              BIGSERIAL PRIMARY KEY,
    baseline_name                   TEXT NOT NULL,               -- Название эталона (например, 'v1_2026-07-01')
    hour                            SMALLINT NOT NULL,          -- Час дня (0–23)
    dow                             SMALLINT NOT NULL,          -- День недели (0–6)
    created_at                      TIMESTAMPTZ DEFAULT now(),
    period_start                    TIMESTAMPTZ NOT NULL,       -- Начало периода, по которому строился эталон
    period_end                      TIMESTAMPTZ NOT NULL,       -- Конец периода

    -- Средние и стандартные отклонения для каждой метрики
    state_histogram_mean            JSONB NOT NULL,             -- {state_id: средняя_доля}
    state_histogram_std             JSONB,                      -- {state_id: стандартное_отклонение}
    avg_correlation_mean            REAL,
    avg_correlation_std             REAL,
    critical_ratio_mean             REAL,
    critical_ratio_std              REAL,
    entropy_mean                    REAL,
    entropy_std                     REAL,
    avg_os_angle_mean               REAL,
    avg_os_angle_std                REAL,
    avg_wait_angle_mean             REAL,
    avg_wait_angle_std              REAL,
    unique_states_count_mean        REAL,
    unique_states_count_std         REAL,
    avg_transition_length_mean      REAL,
    avg_transition_length_std       REAL,
    self_loop_ratio_mean            REAL,
    self_loop_ratio_std             REAL,
    top_transition_freq_mean        REAL,                      -- Средняя частота самого частого перехода
    top_transition_freq_std         REAL,
    top_transition_pair             JSONB                      -- {from_state, to_state} – какой переход был самым частым в среднем
);

COMMENT ON TABLE profile_baseline IS 'Эталонные профили для сравнения – построены на периоде без инцидентов (или с исключением инцидентных окон)';
COMMENT ON COLUMN profile_baseline.baseline_name IS 'Имя эталона, например, "production_v1"';
COMMENT ON COLUMN profile_baseline.hour IS 'Час дня, для которого задан эталон';
COMMENT ON COLUMN profile_baseline.dow IS 'День недели, для которого задан эталон';
COMMENT ON COLUMN profile_baseline.period_start IS 'Начало периода, использованного для построения эталона';
COMMENT ON COLUMN profile_baseline.period_end IS 'Конец периода, использованного для построения эталона';
COMMENT ON COLUMN profile_baseline.state_histogram_mean IS 'Средняя гистограмма состояний (JSON-объект)';
COMMENT ON COLUMN profile_baseline.state_histogram_std IS 'Стандартное отклонение гистограммы (JSON-объект)';
COMMENT ON COLUMN profile_baseline.top_transition_pair IS 'Пара состояний, которая была самой частой в среднем';

CREATE UNIQUE INDEX idx_profile_baseline_unique ON profile_baseline (baseline_name, hour, dow);
CREATE INDEX idx_profile_baseline_hour_dow ON profile_baseline (hour, dow);

-- ----------------------------------------------------------------------------
-- 13.3. Лог аномалий профиля
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS anomaly_log;
CREATE TABLE anomaly_log (
    id                  BIGSERIAL PRIMARY KEY,
    ts                  TIMESTAMPTZ DEFAULT now(),
    profile_type        TEXT NOT NULL CHECK (profile_type IN ('operational', 'daily', 'weekly')),
    hour                SMALLINT,                          -- Опционально – час, для которого обнаружена аномалия
    dow                 SMALLINT,                          -- Опционально – день недели
    detected_at         TIMESTAMPTZ NOT NULL,             -- Время обнаружения
    anomaly_score       REAL,                             -- Обобщённая оценка отклонения (например, сумма Z-оценок)
    affected_metrics    JSONB,                            -- Список метрик, превысивших порог: [{"metric": "entropy", "z_score": 2.5}, ...]
    threshold_used      REAL DEFAULT 2.0,                 -- Использованный порог Z-оценки
    details             TEXT,                             -- Дополнительная информация (например, текущие значения)
    acknowledged        BOOLEAN DEFAULT FALSE,
    acknowledged_by     TEXT,
    acknowledged_at     TIMESTAMPTZ
);

COMMENT ON TABLE anomaly_log IS 'Журнал обнаруженных аномалий профиля производительности';
COMMENT ON COLUMN anomaly_log.profile_type IS 'Тип профиля, в котором обнаружена аномалия';
COMMENT ON COLUMN anomaly_log.anomaly_score IS 'Суммарная Z-оценка отклонений (чем выше, тем сильнее аномалия)';
COMMENT ON COLUMN anomaly_log.affected_metrics IS 'Список метрик, превысивших порог, с их Z-оценками';
COMMENT ON COLUMN anomaly_log.threshold_used IS 'Порог Z-оценки, использованный для обнаружения';

CREATE INDEX idx_anomaly_log_ts ON anomaly_log (ts);
CREATE INDEX idx_anomaly_log_profile_type ON anomaly_log (profile_type);
CREATE INDEX idx_anomaly_log_acknowledged ON anomaly_log (acknowledged);

-- ----------------------------------------------------------------------------
-- 13.4. Вспомогательная таблица для исключаемых окон (при построении эталона)
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS excluded_windows;
CREATE TABLE excluded_windows (
    id          BIGSERIAL PRIMARY KEY,
    start_ts    TIMESTAMPTZ NOT NULL,
    end_ts      TIMESTAMPTZ NOT NULL,
    reason      TEXT,                     -- 'incident', 'pre_incident', 'post_incident', 'manual'
    incident_id BIGINT REFERENCES performance_incident(id) ON DELETE CASCADE,
    created_at  TIMESTAMPTZ DEFAULT now()
);

COMMENT ON TABLE excluded_windows IS 'Интервалы времени, исключаемые при построении эталонного профиля (инциденты и буферы)';
COMMENT ON COLUMN excluded_windows.reason IS 'Причина исключения: incident, pre_incident, post_incident, manual';

CREATE INDEX idx_excluded_windows_ts ON excluded_windows (start_ts, end_ts);

-- =============================================================================
-- Таблица для хранения текущего безынцидентного окна
-- =============================================================================
DROP TABLE IF EXISTS incident_free_window_current;
CREATE TABLE incident_free_window_current (
    id            SERIAL PRIMARY KEY,
    window_start  TIMESTAMPTZ NOT NULL,
    window_end    TIMESTAMPTZ NOT NULL,
    updated_at    TIMESTAMPTZ DEFAULT now()
);

COMMENT ON TABLE incident_free_window_current IS 'Хранит последнее найденное безынцидентное окно (одна строка).';


-- =============================================================================
-- 2. Создание таблицы для хранения результатов сравнения профилей
-- =============================================================================
DROP TABLE IF EXISTS profile_comparison_log;
CREATE TABLE profile_comparison_log (
    id                      BIGSERIAL PRIMARY KEY,
    created_at              TIMESTAMPTZ DEFAULT now(),
    baseline_window_start   TIMESTAMPTZ,
    baseline_window_end     TIMESTAMPTZ,
    current_window_start    TIMESTAMPTZ,
    current_window_end      TIMESTAMPTZ,
    status                  TEXT,                     -- итоговый статус (CRITICAL, WARNING, NORMAL)
    js_divergence           REAL,
    report                  JSONB,                    -- полный отчёт в виде массива строк
    details                 JSONB                     -- дополнительные метрики (опционально)
);

COMMENT ON TABLE profile_comparison_log IS 'Журнал сравнений эталонного и текущего профилей';
COMMENT ON COLUMN profile_comparison_log.status IS 'Итоговый статус из compare_profile_windows (например, "КРИТИЧЕСКОЕ")';
COMMENT ON COLUMN profile_comparison_log.js_divergence IS 'JS-дивергенция гистограмм состояний';
COMMENT ON COLUMN profile_comparison_log.report IS 'Полный отчёт в формате JSON-массива строк';
COMMENT ON COLUMN profile_comparison_log.details IS 'Дополнительные метрики (средняя корреляция, critical_ratio и т.д.)';

CREATE INDEX idx_profile_comparison_log_created_at ON profile_comparison_log (created_at);
