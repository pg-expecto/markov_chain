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
--  version 16.10
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
	max_predicted_risk      REAL,
	pre_alert_flag 			INTEGER DEFAULT 0, 
    status                  TEXT,                     -- итоговый статус (CRITICAL, WARNING, NORMAL)
    js_divergence           REAL,
    report                  JSONB,                    -- полный отчёт в виде массива строк
    details                 JSONB ,                     -- дополнительные метрики (опционально)
	high_risk_percentile    REAL,
	js_threshold_used       REAL,
	stability_met           BOOLEAN,
	pre_alert_flag_advanced INT DEFAULT 0 , 
	matched_pre_incident_id BIGINT  	
);

-- Внешний ключ 
--ALTER TABLE profile_comparison_log ADD CONSTRAINT fk_profile_comparison_log_pre_incident FOREIGN KEY (matched_pre_incident_id) REFERENCES pre_incident_profiles(id) ON DELETE SET NULL;

-- Индекс для ускорения выборок по этой колонке
CREATE INDEX idx_profile_comparison_log_matched_pre_incident ON profile_comparison_log(matched_pre_incident_id);

CREATE INDEX IF NOT EXISTS idx_profile_comparison_log_window_end_js
    ON profile_comparison_log (current_window_end, js_divergence)
    WHERE js_divergence IS NOT NULL;

COMMENT ON TABLE profile_comparison_log IS 'Журнал сравнений эталонного и текущего профилей';
COMMENT ON COLUMN profile_comparison_log.status IS 'Итоговый статус из compare_profile_windows (например, "КРИТИЧЕСКОЕ")';
COMMENT ON COLUMN profile_comparison_log.js_divergence IS 'JS-дивергенция гистограмм состояний';
COMMENT ON COLUMN profile_comparison_log.report IS 'Полный отчёт в формате JSON-массива строк';
COMMENT ON COLUMN profile_comparison_log.details IS 'Дополнительные метрики (средняя корреляция, critical_ratio и т.д.)';
COMMENT ON COLUMN profile_comparison_log.max_predicted_risk IS 'Максимальное значение predicted_risk из prediction_log за текущее окно (current_window_start, current_window_end)';
COMMENT ON COLUMN profile_comparison_log.pre_alert_flag IS '100, если js_divergence >= 0.4 и max_predicted_risk = 1; иначе 0';
COMMENT ON COLUMN profile_comparison_log.high_risk_percentile IS '90-й перцентиль predicted_risk за текущее окно';
COMMENT ON COLUMN profile_comparison_log.js_threshold_used IS 'Значение порога JS-дивергенции, взятое из markov_config.js_divergence_threshold';
COMMENT ON COLUMN profile_comparison_log.stability_met IS 'Выполнено ли условие устойчивости (3 из 5 последних минут)';
COMMENT ON COLUMN profile_comparison_log.pre_alert_flag_advanced IS 'Индикатор изменения профиля производительности (100 – активен, 0 – неактивен). Вычисляется по комплексному критерию: JS-дивергенция ≥ порога, 90-й перцентиль риска ≥ 0.95, устойчивость 3 из 5 мин.';

CREATE INDEX idx_profile_comparison_log_created_at ON profile_comparison_log (created_at);

---------------------------
-- version 15
-- Таблица для библиотеки профилей, собранных перед инцидентами
CREATE TABLE IF NOT EXISTS pre_incident_profiles (
    id                  BIGSERIAL PRIMARY KEY,
    incident_id         BIGINT NOT NULL,                     -- ссылка на performance_incident.id
    window_start        TIMESTAMPTZ NOT NULL,
    window_end          TIMESTAMPTZ NOT NULL,
    state_histogram     JSONB NOT NULL,
    avg_correlation     REAL,
    critical_ratio      REAL,
    entropy             REAL,
    avg_os_angle        REAL,
    avg_wait_angle      REAL,
    unique_states_count INT,
    avg_transition_length REAL,
    self_loop_ratio     REAL,
    top_transition      JSONB,
    created_at          TIMESTAMPTZ DEFAULT now()
);
COMMENT ON TABLE pre_incident_profiles IS 'таблица для библиотеки пред-инцидентных профилей';

-- Индекс для быстрого поиска по инциденту
CREATE INDEX IF NOT EXISTS idx_pre_incident_profiles_incident_id ON pre_incident_profiles(incident_id);
-- Индекс для выборки последних записей
CREATE INDEX IF NOT EXISTS idx_pre_incident_profiles_created_at ON pre_incident_profiles(created_at DESC);


-- =============================================================================
-- Таблица для логирования совпадений текущего профиля с пред-инцидентными шаблонами
-- =============================================================================
DROP TABLE IF EXISTS pre_incident_match_log;
CREATE TABLE IF NOT EXISTS pre_incident_match_log (
    id                          BIGSERIAL PRIMARY KEY,
    matched_at                  TIMESTAMPTZ DEFAULT now(),
    current_window_start        TIMESTAMPTZ NOT NULL,
    current_window_end          TIMESTAMPTZ NOT NULL,
    matched_pre_incident_id     BIGINT NOT NULL,
    divergence                  REAL NOT NULL,
    incident_id                 BIGINT,
    incident_time               TIMESTAMPTZ,
    threshold_used              REAL NOT NULL,
    CONSTRAINT fk_pre_incident_match_log_pre_incident
        FOREIGN KEY (matched_pre_incident_id)
        REFERENCES pre_incident_profiles(id)
        ON DELETE CASCADE
);

COMMENT ON TABLE pre_incident_match_log IS 'Журнал совпадений текущего профиля нагрузки с пред-инцидентными профилями (найдено функцией compare_with_pre_incident_profiles)';
COMMENT ON COLUMN pre_incident_match_log.current_window_start IS 'Начало окна текущего профиля (обычно now() - 60 мин)';
COMMENT ON COLUMN pre_incident_match_log.current_window_end IS 'Конец окна текущего профиля (обычно now())';
COMMENT ON COLUMN pre_incident_match_log.matched_pre_incident_id IS 'ID совпавшего пред-инцидентного профиля из pre_incident_profiles';
COMMENT ON COLUMN pre_incident_match_log.divergence IS 'JS-дивергенция между текущей гистограммой и гистограммой шаблона';
COMMENT ON COLUMN pre_incident_match_log.incident_id IS 'ID инцидента, которому принадлежит шаблон (из performance_incident)';
COMMENT ON COLUMN pre_incident_match_log.incident_time IS 'Время начала инцидента';
COMMENT ON COLUMN pre_incident_match_log.threshold_used IS 'Порог JS-дивергенции, использованный при поиске совпадений';

CREATE INDEX idx_pre_incident_match_log_matched_at ON pre_incident_match_log(matched_at);
CREATE INDEX idx_pre_incident_match_log_incident_id ON pre_incident_match_log(incident_id);


---------------------------------------
-- 15.2
-- Таблица для хранения параметров отчёта
DROP TABLE IF EXISTS incident_forecast_config;
CREATE TABLE incident_forecast_config (
    id                              SERIAL PRIMARY KEY,
    window_minutes                  INT     NOT NULL DEFAULT 60,
    js_threshold                    REAL    NOT NULL DEFAULT 0.15,   -- снижено с 0.2 (2026-10-12)
    risk_threshold                  REAL    NOT NULL DEFAULT 0.8,
    include_summary                 BOOLEAN NOT NULL DEFAULT TRUE,
    signal_mode                     TEXT    NOT NULL DEFAULT 'AND',
    min_signal_duration             INT     NOT NULL DEFAULT 3,
    use_priority_thresholds         BOOLEAN NOT NULL DEFAULT FALSE,
    weight_js                       REAL    NOT NULL DEFAULT 0.5,
    weight_risk                     REAL    NOT NULL DEFAULT 0.5,
    auto_threshold                  BOOLEAN NOT NULL DEFAULT FALSE,
    calibration_period_days         INT     NOT NULL DEFAULT 7,
    max_js_age_min                  INT     NOT NULL DEFAULT 60,
    min_data_points                 INT     NOT NULL DEFAULT 5,
    slope_window_minutes            INT     NOT NULL DEFAULT 10,
    extended_report                 BOOLEAN NOT NULL DEFAULT FALSE,
    optimize_thresholds             BOOLEAN NOT NULL DEFAULT FALSE,
    priority_filter                 INT[]   DEFAULT NULL,
    status_filter                   TEXT[]  DEFAULT NULL,
    csv_mode                        BOOLEAN NOT NULL DEFAULT FALSE,
    include_pre_incident_matches    BOOLEAN NOT NULL DEFAULT TRUE,
    updated_at                      TIMESTAMPTZ DEFAULT now() , 
	series_filter_enabled BOOLEAN NOT NULL DEFAULT TRUE ,
	sicpp_coverage_warn_threshold_pct REAL DEFAULT 10.0 ,
	coverage_lead_threshold_min INT NOT NULL DEFAULT 60
);

-- Индекс для быстрого доступа (всегда одна строка)
CREATE UNIQUE INDEX idx_incident_forecast_config_single ON incident_forecast_config ((1));

COMMENT ON COLUMN incident_forecast_config.series_filter_enabled IS 'TRUE — исключать серийные инциденты (v_last_status=INCIDENT AND предыдущий инцидент не завершён). FALSE — не исключать.';
COMMENT ON COLUMN incident_forecast_config.sicpp_coverage_warn_threshold_pct IS 'Порог (% от периода отчёта), ниже которого выводится предупреждение о неполном покрытии sicpp_history.';
-- optimize_thresholds: помечаем как not implemented (не удаляем — на случай внешних ссылок)
COMMENT ON COLUMN incident_forecast_config.optimize_thresholds IS 'NOT IMPLEMENTED с v3.0.0. Игнорируется. Используйте auto_threshold (percentile-based) или evaluate_forgetting_params.';
COMMENT ON COLUMN incident_forecast_config.coverage_lead_threshold_min IS 'Порог lead time (минут) для метрики «покрытие с учётом lead time». Инцидент считается «предсказанным заранее», если покрыт эпизодом SICPP И lead_time >= порога. 60 — отделяет «сигнал был активен при инциденте» от «сигнал предсказал заранее».';



-- Вставка начальной конфигурации (со значениями, соответствующими ранее используемым по умолчанию)
INSERT INTO incident_forecast_config (
    window_minutes, js_threshold, risk_threshold, include_summary,
    signal_mode, min_signal_duration, use_priority_thresholds,
    weight_js, weight_risk, auto_threshold, calibration_period_days,
    max_js_age_min, min_data_points, slope_window_minutes,
    extended_report, optimize_thresholds, priority_filter, status_filter,
    csv_mode, include_pre_incident_matches
) VALUES (
    60, 0.15, 0.8, TRUE,
    'OR', 3, FALSE,
    0.5, 0.5, FALSE, 7,
    60, 5, 10,
    FALSE, FALSE, NULL, NULL,
    FALSE, TRUE
) ON CONFLICT DO NOTHING;

-- Таблица для хранения состояний индикатора изменения профиля
DROP TABLE IF EXISTS profile_change_indicator;
CREATE TABLE profile_change_indicator (
    id              BIGSERIAL PRIMARY KEY,
    indicator_value BOOLEAN NOT NULL,          -- TRUE – профиль изменился (прединцидентный), FALSE – нормализовался
    changed_at      TIMESTAMPTZ NOT NULL       -- время изменения состояния
);

-- Индекс для быстрого получения последнего состояния
CREATE INDEX idx_profile_change_indicator_changed_at ON profile_change_indicator(changed_at DESC);

COMMENT ON TABLE profile_change_indicator IS 'Хранит историю изменений индикатора изменения профиля (сигнал прединцидентного состояния)';
COMMENT ON COLUMN profile_change_indicator.indicator_value IS 'TRUE – сигнал сработал (профиль изменился), FALSE – сигнал сброшен';
COMMENT ON COLUMN profile_change_indicator.changed_at IS 'Время, когда индикатор изменил своё значение';

---------------------------------------
-- 16.8
-- =============================================================================
-- Таблица: sicpp_history
-- Версия: 1.0.0
-- Назначение: хранит историю изменений состояния сигнала SICPP.
--             Записи добавляются только при смене состояния (OFF→ON или ON→OFF).
-- =============================================================================
CREATE TABLE IF NOT EXISTS sicpp_history (
    id                  BIGSERIAL       PRIMARY KEY,
    changed_at          TIMESTAMPTZ     NOT NULL DEFAULT now(),
    signal_active       BOOLEAN         NOT NULL,
    signal_strength     REAL,
    first_signal_time   TIMESTAMPTZ,
    signal_duration     INT,
    max_signal_strength REAL,
    js_avg              REAL,
    js_min              REAL,
    js_max              REAL,
    js_cnt              INT,
    risk_avg            REAL,
    risk_min            REAL,
    risk_max            REAL,
    risk_cnt            INT,
    js_slope            REAL,
    risk_slope          REAL,
    data_sufficient     TEXT,
    confidence          REAL,
    signal_mode         TEXT,
    js_threshold        REAL,
    risk_threshold      REAL,
    window_minutes      INT,
    min_signal_duration INT,
    reason              TEXT,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT now()
);


COMMENT ON COLUMN sicpp_history.id                  IS 'Уникальный идентификатор записи (автоинкремент).';
COMMENT ON COLUMN sicpp_history.changed_at          IS 'Момент времени, когда состояние сигнала изменилось (минутная метка).';
COMMENT ON COLUMN sicpp_history.signal_strength     IS 'Значение силы сигнала в момент изменения состояния. Для WEIGHTED: (risk/risk_threshold)*weight_risk + (js/js_threshold)*weight_js.';
COMMENT ON COLUMN sicpp_history.max_signal_strength IS 'Максимальное значение силы сигнала за время текущего пробега.';
COMMENT ON COLUMN sicpp_history.js_avg              IS 'Средняя JS-дивергенция за окно window_minutes до момента changed_at.';
COMMENT ON COLUMN sicpp_history.js_min              IS 'Минимальная JS-дивергенция за окно window_minutes.';
COMMENT ON COLUMN sicpp_history.js_max              IS 'Максимальная JS-дивергенция за окно window_minutes.';
COMMENT ON COLUMN sicpp_history.js_cnt              IS 'Количество точек JS в окне. -1 — использовано последнее известное значение вне окна.';
COMMENT ON COLUMN sicpp_history.risk_avg            IS 'Средний предсказанный риск за окно window_minutes.';
COMMENT ON COLUMN sicpp_history.risk_min            IS 'Минимальный предсказанный риск за окно.';
COMMENT ON COLUMN sicpp_history.risk_max            IS 'Максимальный предсказанный риск за окно.';
COMMENT ON COLUMN sicpp_history.risk_cnt            IS 'Количество точек риска в окне. -1 — использовано последнее значение вне окна.';
COMMENT ON COLUMN sicpp_history.js_slope            IS 'Скорость изменения JS-дивергенции за последние slope_window_minutes (единиц в минуту).';
COMMENT ON COLUMN sicpp_history.risk_slope          IS 'Скорость изменения риска за последние slope_window_minutes (единиц в минуту).';
COMMENT ON COLUMN sicpp_history.data_sufficient     IS 'Достаточность данных: OK / LOW_JS / LOW_RISK / LOW_BOTH.';
COMMENT ON COLUMN sicpp_history.confidence          IS 'Среднее превышение порогов (нормированное) за время сигнала.';
COMMENT ON COLUMN sicpp_history.signal_mode         IS 'Использованный режим сигнала (AND/OR/WEIGHTED/OR_WITH_DURATION).';
COMMENT ON COLUMN sicpp_history.js_threshold        IS 'Порог JS-дивергенции на момент расчёта.';
COMMENT ON COLUMN sicpp_history.risk_threshold      IS 'Порог риска на момент расчёта.';
COMMENT ON COLUMN sicpp_history.window_minutes      IS 'Длина окна анализа (минут).';
COMMENT ON COLUMN sicpp_history.min_signal_duration IS 'Минимальная длительность непрерывного сигнала (минут).';
COMMENT ON COLUMN sicpp_history.created_at          IS 'Техническая метка времени вставки записи.';
COMMENT ON COLUMN sicpp_history.signal_active IS 'Новое состояние сигнала SICPP: TRUE — в окне был подходящий пробег, FALSE — не было. Соответствует колонке «Сигнал» отчёта.';
COMMENT ON COLUMN sicpp_history.first_signal_time IS 'Начало последнего подходящего пробега в окне [changed_at - window, changed_at - 1 мин]. Если пробег начался до начала окна, используется начало окна.';
COMMENT ON COLUMN sicpp_history.signal_duration IS 'Длительность последнего подходящего пробега в минутах, как она наблюдалась в пределах окна.';
COMMENT ON COLUMN sicpp_history.reason IS 'Причина изменения: init / signal started (появился подходящий пробег в окне) / signal ended (подходящий пробег вышел за пределы окна).';

-- =============================================================================
-- Обновление комментариев к sicpp_history (в связи с v1.1.0 sicpp_calculate_at)
-- =============================================================================
COMMENT ON TABLE sicpp_history IS
'История изменений состояния сигнала SICPP (Signal Indicating a Change in the Performance Profile). Записи добавляются только при смене состояния (OFF→ON или ON→OFF) функцией sicpp_update_state(), вызываемой из mchain_train_step().

Семантика состояния (v1.1.0):
  signal_active = TRUE означает, что в окне [changed_at - window_minutes, changed_at - 1 мин]
  был хотя бы один непрерывный пробег длительностью >= min_signal_duration.
  Это соответствует колонке «Сигнал» в отчёте generate_incident_forecast_report().

Latch-эффект: signal_active остаётся TRUE в течение ~window_minutes после завершения
последнего подходящего пробега, пока пробег не выйдет за пределы окна.';


CREATE INDEX IF NOT EXISTS idx_sicpp_history_changed_at     ON sicpp_history (changed_at DESC);
CREATE INDEX IF NOT EXISTS idx_sicpp_history_signal_active  ON sicpp_history (signal_active, changed_at DESC);

-- =============================================================================
-- Таблица: sicpp_current_state
-- Версия: 1.0.0
-- Назначение: singleton-таблица с текущим состоянием SICPP.
-- =============================================================================
CREATE TABLE IF NOT EXISTS sicpp_current_state (
    id                  INT             PRIMARY KEY DEFAULT 1,
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT now(),
    signal_active       BOOLEAN         NOT NULL DEFAULT FALSE,
    signal_strength     REAL,
    first_signal_time   TIMESTAMPTZ,
    signal_duration     INT             DEFAULT 0,
    max_signal_strength REAL,
    consecutive_run     INT             DEFAULT 0,
    last_minute_js      REAL,
    last_minute_risk    REAL,
    last_history_id     BIGINT,
    CONSTRAINT sicpp_current_state_singleton CHECK (id = 1)
);

COMMENT ON TABLE sicpp_current_state IS
'Текущее (последнее) состояние сигнала SICPP. Singleton-таблица (ровно одна строка с id=1). Обновляется функцией sicpp_update_state() при каждом вызове mchain_train_step(). Используется для быстрого доступа к текущему состоянию без сканирования sicpp_history.';

COMMENT ON COLUMN sicpp_current_state.id                  IS 'Фиксированный идентификатор = 1 (singleton).';
COMMENT ON COLUMN sicpp_current_state.updated_at          IS 'Момент последнего обновления состояния.';
COMMENT ON COLUMN sicpp_current_state.signal_active       IS 'Текущее состояние SICPP: TRUE — активен, FALSE — неактивен.';
COMMENT ON COLUMN sicpp_current_state.signal_strength     IS 'Текущая сила сигнала (для последней минуты).';
COMMENT ON COLUMN sicpp_current_state.first_signal_time   IS 'Время начала текущего непрерывного сигнального пробега.';
COMMENT ON COLUMN sicpp_current_state.signal_duration     IS 'Длительность текущего пробега (минут).';
COMMENT ON COLUMN sicpp_current_state.max_signal_strength IS 'Максимум силы сигнала за текущий пробег.';
COMMENT ON COLUMN sicpp_current_state.consecutive_run     IS 'Счётчик последовательных минут с is_signal_minute = TRUE.';
COMMENT ON COLUMN sicpp_current_state.last_minute_js      IS 'Последнее известное значение JS-дивергенции.';
COMMENT ON COLUMN sicpp_current_state.last_minute_risk    IS 'Последнее известное значение предсказанного риска.';
COMMENT ON COLUMN sicpp_current_state.last_history_id     IS 'ID последней записи в sicpp_history (трассировка).';

INSERT INTO sicpp_current_state (id, signal_active, signal_duration, consecutive_run)
VALUES (1, FALSE, 0, 0)
ON CONFLICT (id) DO NOTHING;

-- 16.8
---------------------------------------

---------------------------------------
--16.9
-- =============================================================================
-- Таблица: sicpp_coverage_alerts
-- Назначение: алерты о P3-инцидентах, не покрытых сигналом SICPP.
--             Дедупликация по incident_id (UNIQUE).
-- =============================================================================
CREATE TABLE IF NOT EXISTS sicpp_coverage_alerts (
    id              BIGSERIAL    PRIMARY KEY,
    detected_at     TIMESTAMPTZ  NOT NULL DEFAULT now(),
    incident_id     BIGINT       NOT NULL UNIQUE,
    incident_start  TIMESTAMPTZ  NOT NULL,
    priority        SMALLINT     NOT NULL,
    reason          TEXT,
    acknowledged    BOOLEAN      NOT NULL DEFAULT FALSE,
    acknowledged_at TIMESTAMPTZ,
    acknowledged_by TEXT ,
    CONSTRAINT uq_sicpp_coverage_alerts_incident UNIQUE (incident_id)
);

CREATE INDEX IF NOT EXISTS idx_sicpp_coverage_alerts_detected_at
    ON sicpp_coverage_alerts (detected_at DESC);

CREATE INDEX IF NOT EXISTS idx_sicpp_coverage_alerts_unacked
    ON sicpp_coverage_alerts (detected_at DESC)
    WHERE acknowledged = FALSE;

CREATE INDEX IF NOT EXISTS idx_sicpp_coverage_alerts_ack
    ON sicpp_coverage_alerts (acknowledged, detected_at DESC)
    WHERE acknowledged = FALSE;

COMMENT ON TABLE sicpp_coverage_alerts IS
'Алерты по непокрытым P3-инцидентам. Заполняется generate_incident_forecast_report_v2 v3.0.0 (раздел «КРИТИЧЕСКИЕ АЛЕРТЫ») и check_p3_coverage_gaps.';

COMMENT ON COLUMN sicpp_coverage_alerts.incident_id IS
'ID инцидента из performance_incident (UNIQUE — один алерт на инцидент).';

--16.9
---------------------------------------

---------------------------------------
--16.10



-- =========================================================================
-- 1.2. incident_forecast_config — новые колонки
-- =========================================================================


--16.10
---------------------------------------



