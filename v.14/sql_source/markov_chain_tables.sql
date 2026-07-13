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
-- markov_chain_tables.sql
-- version 14.6
--------------------------------------------------------------------------------
-- Таблицы для расчета цепи Маркова 
--------------------------------------------------------------------------------
/*
- Конфигурация и управление
  - markov_config :  Хранение параметров обучения, забывания, порогов, флагов адаптивности и времени последнего инцидента

- Журналы переходов и частоты
  - transition_log :  Журнал всех переходов между состояниями с временными метками (используется для анализа и проверки достаточности обучения)
  - markov_frequencies :  Накопление сырых частот переходов между состояниями (основа для расчёта вероятностей)

- Матрицы вероятностей и поглощения
  - markov_probabilities :  Матрица вероятностей переходов, рассчитанная из частот
  - markov_absorbing :  Поглощающая матрица для многошагового прогноза риска (аварийные состояния – поглощающие)

- Справочники и текущее состояние
  - state_descriptions :  Справочник всех 189 состояний (код состояния, корреляция, тренды OS и ожиданий)
  - markov_chain :  Хранит текущее и предыдущее состояния цепи для пошагового обучения (всегда одна строка)

- Логирование ошибок и забывания
  - mchain_error_log :  Журнал ошибок, возникающих при работе mchain-функций
  - apply_forgetting_log :  Лог всех вызовов функции забывания (применённый alpha, детали расчёта)
  
- Анализ качества прогнозов риска
  - prediction_log – журнал прогнозов (горизонт фиксирован)
  - mchain_quality_metrics_history – агрегированные метрики по дням
  - mchain_quality_errors - Ошибки прогноза
  
-- 11
  - critical_states - Динамический список состояний, считающихся аварийными (поглощающими) для прогноза риска.
  
  
*/
--------------------------------------------------------------------------------
-- Таблицы для расчёта цепи Маркова с комментариями.
--------------------------------------------------------------------------------

-- ============================================================================
-- КОНФИГУРАЦИЯ
-- ============================================================================

/*
-- Эмпирически подобранные значения для тестовой СУБД 
alpha                               | 0.1
interval_minute                     | 360
transition_log_retention_days       | 30
apply_forgetting_log_retention_days | 30
adaptive_forgetting_enabled         | t
use_adaptive_alpha                  | t
base_alpha                          | 0.05
min_alpha                           | 0.001
incident_half_life_days             | 30
min_transitions_for_forgetting      | 5000
forecast_horizon_minutes            | 10
min_freq_for_stability              | 300
*/
DROP TABLE IF EXISTS markov_config;
CREATE UNLOGGED TABLE IF NOT EXISTS markov_config (
    -- Основные параметры обучения и забывания
    last_forget_time  TIMESTAMPTZ NOT NULL DEFAULT now(),   -- Время последнего вызова планового забывания
    alpha             REAL       NOT NULL DEFAULT 0.1,      -- Скорость забывания (если use_adaptive_alpha = false)
    interval_minute   INT        NOT NULL DEFAULT 360,       -- Интервал между плановыми забываниями (минуты)

    -- Глубина хранения журналов (используется функциями очистки)
    transition_log_retention_days SMALLINT DEFAULT 30,          -- Срок хранения переходов
	apply_forgetting_log_retention_days INT DEFAULT 30, -- Срок хранения журнала apply_forgetting_log
	profile_comparison_retention_days INT DEFAULT 30 ,
	
	adaptive_forgetting_enabled BOOLEAN DEFAULT TRUE , 
	
	-- Адаптивное забывание 
    use_adaptive_alpha BOOLEAN DEFAULT TRUE,           -- Включить динамический alpha на основе времени с последнего инцидента
    base_alpha REAL DEFAULT 0.05,                       -- Базовый alpha (при частых инцидентах)
    min_alpha REAL DEFAULT 0.001,                       -- Минимальный alpha (при очень редких инцидентах)
    incident_half_life_days REAL DEFAULT 30.0,          -- Период полураспада веса инцидента (дни)
    last_incident_time TIMESTAMPTZ DEFAULT NULL,       -- Время последнего аварийного перехода (обновляется триггером)
    min_transitions_for_forgetting INT DEFAULT 5000,    -- Минимальное число переходов для начала забывания
	
	--Горизонт
	forecast_horizon_minutes INT DEFAULT 10 ,
	
	min_freq_for_stability INT DEFAULT 300
);

COMMENT ON TABLE markov_config IS 'Конфигурация цепи Маркова (используется mchain_*)';
COMMENT ON COLUMN markov_config.last_forget_time IS 'Время последнего забывания (для проверки interval_minute)';
COMMENT ON COLUMN markov_config.alpha IS 'Скорость забывания, если адаптивный режим выключен';
COMMENT ON COLUMN markov_config.interval_minute IS 'Как часто (в минутах) вызывать забывание';
COMMENT ON COLUMN markov_config.transition_log_retention_days IS 'Срок хранения переходов';
COMMENT ON COLUMN markov_config.apply_forgetting_log_retention_days IS 'Срок хранения журнала apply_forgetting_log';
COMMENT ON COLUMN markov_config.adaptive_forgetting_enabled IS 'Глобальное включение/выключение забывания (если false – забывание не применяется)';
COMMENT ON COLUMN markov_config.use_adaptive_alpha IS 'Если true – alpha = base_alpha * exp(-days_since / half_life)';
COMMENT ON COLUMN markov_config.base_alpha IS 'Базовый alpha (при частых инцидентах)';
COMMENT ON COLUMN markov_config.min_alpha IS ' Минимальный alpha (при очень редких инцидентах)';
COMMENT ON COLUMN markov_config.incident_half_life_days IS ' Период полураспада веса инцидента (дни)';
COMMENT ON COLUMN markov_config.last_incident_time IS 'Автоматически обновляется триггером при аварийном переходе';
COMMENT ON COLUMN markov_config.min_transitions_for_forgetting IS 'Пока общее число переходов меньше этого порога, забывание не применяется (alpha=0)';
COMMENT ON COLUMN markov_config.forecast_horizon_minutes IS 'Основной горизонт прогноза (минуты), используемый в collect и отчётах';
COMMENT ON COLUMN markov_config.min_freq_for_stability IS 'Минимальное число переходов из состояния за анализируемый период для включения в расчёт стабильности вероятностей.';
COMMENT ON COLUMN markov_config.profile_comparison_retention_days IS 'Срок хранения записей в profile_comparison_log (дни)';

-- Начальная инициализация (если таблица пуста)
INSERT INTO markov_config (last_forget_time) VALUES (now()) ON CONFLICT DO NOTHING;

-- ============================================================================
-- Таблица логирования ошибок (используется mchain_log_error)
-- ============================================================================
DROP TABLE IF EXISTS mchain_error_log;
CREATE TABLE mchain_error_log (
    id            BIGSERIAL PRIMARY KEY,
    ts            TIMESTAMPTZ NOT NULL DEFAULT now(),
    function_name TEXT NOT NULL,       -- Имя функции, где произошла ошибка
    error_message TEXT,                -- Текст ошибки (SQLERRM)
    error_detail  TEXT,                -- Детали (SQLSTATE и пр.)
    error_hint    TEXT,                -- Подсказка (опционально)
    context       JSONB                -- Дополнительный контекст (параметры вызова)
);
COMMENT ON TABLE mchain_error_log IS 'Журнал ошибок, возникающих при работе mchain_* функций';

-- ============================================================================
-- Основная таблица переходных частот (ядро модели)
-- ============================================================================
DROP TABLE IF EXISTS markov_frequencies;
CREATE TABLE markov_frequencies (
    from_state  SMALLINT NOT NULL,   -- Исходное состояние (0..188)
    to_state    SMALLINT NOT NULL,   -- Целевое состояние (0..188)
    frequency   REAL     NOT NULL DEFAULT 0.0  -- Накопленная частота (не обязательно целое)
);
ALTER TABLE markov_frequencies ADD CONSTRAINT markov_frequencies_pk PRIMARY KEY (from_state, to_state);
COMMENT ON TABLE markov_frequencies IS 'Накопленные частоты переходов (обновляются каждую минуту)';
COMMENT ON COLUMN markov_frequencies.frequency IS 'Может быть дробной после применения забывания';

-- ============================================================================
-- Журнал переходов (история для анализа и проверки достаточности)
-- ============================================================================
DROP TABLE IF EXISTS transition_log;
CREATE TABLE transition_log (
    id          BIGSERIAL PRIMARY KEY,
    ts          TIMESTAMPTZ  NOT NULL DEFAULT now(),
    from_state  SMALLINT     NOT NULL,
    to_state    SMALLINT     NOT NULL
);
CREATE INDEX idx_transition_log_ts ON transition_log (ts);
CREATE INDEX idx_transition_log_from ON transition_log (from_state);
CREATE INDEX idx_transition_log_ts_from ON transition_log (ts, from_state);
COMMENT ON TABLE transition_log IS 'Посекундный/минутный журнал всех переходов';

-- ============================================================================
-- Матрица вероятностей (рассчитывается из частот)
-- ============================================================================
DROP TABLE IF EXISTS markov_probabilities;
CREATE TABLE markov_probabilities (
    from_state  SMALLINT NOT NULL,
    to_state    SMALLINT NOT NULL,
    probability REAL NOT NULL   -- Условная вероятность P(to_state | from_state)
);
ALTER TABLE markov_probabilities ADD CONSTRAINT markov_probabilities_pk PRIMARY KEY (from_state, to_state);
COMMENT ON TABLE markov_probabilities IS 'Вероятности переходов, пересчитываемые при каждом забывании';

-- ============================================================================
-- Поглощающая матрица (для многошагового прогноза риска)
-- ============================================================================
DROP TABLE IF EXISTS markov_absorbing;
CREATE TABLE IF NOT EXISTS markov_absorbing (
    from_state  SMALLINT NOT NULL,
    to_state    SMALLINT NOT NULL,
    probability REAL    NOT NULL
);
ALTER TABLE markov_absorbing ADD CONSTRAINT markov_absorbing_pk PRIMARY KEY (from_state, to_state);
COMMENT ON TABLE markov_absorbing IS 'Модифицированная матрица: аварийные состояния – поглощающие (вероятность остаться = 1)';

-- ============================================================================
-- Справочник состояний (189 комбинаций)
-- ============================================================================
DROP TABLE IF EXISTS state_descriptions;
CREATE TABLE state_descriptions (
    state_id    SMALLINT PRIMARY KEY,
    correlation REAL    NOT NULL,   -- Коэффициент корреляции (округлённый до 0.1)
    os_trend    SMALLINT NOT NULL,  -- Тренд операционной скорости: -1, 0, 1
    wait_trend  SMALLINT NOT NULL   -- Тренд времени ожидания: -1, 0, 1
);
COMMENT ON TABLE state_descriptions IS 'Фиксированный справочник всех возможных состояний (заполняется fill_state_descriptions())';

-- ============================================================================
-- Текущее и предыдущее состояние цепи (для пошагового обучения)
-- ============================================================================
DROP TABLE IF EXISTS markov_chain;
CREATE UNLOGGED TABLE markov_chain (
    prev_correlation REAL,      -- Предыдущее значение корреляции (до сдвига)
    prev_os_trend    SMALLINT,
    prev_wait_trend  SMALLINT,
    curr_correlation REAL NOT NULL,  -- Текущее состояние (после сдвига)
    curr_os_trend    SMALLINT NOT NULL,
    curr_wait_trend  SMALLINT NOT NULL
);
COMMENT ON TABLE markov_chain IS 'Хранит только одну строку – последнее и предпоследнее состояние';

-- ============================================================================
-- Журнал вызовов apply_forgetting (для аудита)
-- ============================================================================
DROP TABLE IF EXISTS apply_forgetting_log;
CREATE TABLE apply_forgetting_log (
    id                  BIGSERIAL PRIMARY KEY,
    ts                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    effective_alpha     REAL NOT NULL,      -- Фактически применённый коэффициент
    adaptive_used       BOOLEAN NOT NULL,   -- Был ли включён адаптивный режим
    days_since_incident REAL,               -- Число дней с последнего инцидента (для адаптивного режима)
    alpha_override      REAL,               -- Если передан параметр alpha_override
    details             TEXT                -- Детали расчёта alpha
);
COMMENT ON TABLE apply_forgetting_log IS 'Лог всех вызовов функции забывания (успешных и пропущенных)';


-- ========================================================================================================================================================
-- 10.1.6
-- ============================================================================
-- журнал прогнозов (горизонт фиксирован)
-- ============================================================================
DROP TABLE IF EXISTS prediction_log;
CREATE TABLE prediction_log (
    id                 BIGSERIAL PRIMARY KEY,
    prediction_time    TIMESTAMPTZ NOT NULL,
    predicted_risk     REAL NOT NULL,           -- вероятность (0..1)
    situation          TEXT,                    -- 'unknown_state', 'no_risk', 'risk_calculated'
    transitions_to_risk INT,
    total_transitions_known INT,
    current_state_id   SMALLINT,                -- идентификатор состояния на момент прогноза
    -- Поля, заполняемые позже (при обновлении исходов)
    actual_outcome     SMALLINT DEFAULT NULL,   -- 1 – инцидент произошёл в окне, 0 – нет, NULL – ещё не известно
    first_incident_time TIMESTAMPTZ DEFAULT NULL,
    incident_count     SMALLINT DEFAULT 0,
	horizon_minutes INT DEFAULT 30
);

-- Индексы для быстрых обновлений и отчётов
CREATE INDEX idx_prediction_time ON prediction_log (prediction_time);
CREATE INDEX idx_outcome_null ON prediction_log (actual_outcome) WHERE actual_outcome IS NULL;
CREATE INDEX idx_outcome_actual ON prediction_log (actual_outcome);

COMMENT ON TABLE prediction_log IS 'Журнал всех прогнозов';
COMMENT ON COLUMN prediction_log.horizon_minutes IS 'Горизонт прогноза в минутах (фиксированное значение для всех записей после перехода на 30 мин)';

-- ============================================================================
-- агрегированные метрики по дням
-- ============================================================================
DROP TABLE IF EXISTS mchain_quality_metrics_history;
CREATE TABLE mchain_quality_metrics_history (
    id                 BIGSERIAL PRIMARY KEY,
    date_from          DATE NOT NULL,
    date_to            DATE NOT NULL,           -- обычно date_from = date_to (сутки)
    total_predictions  INT NOT NULL,
    incident_rate      REAL,                    -- доля инцидентов
    brier_score        REAL,
    log_loss           REAL,
    roc_auc            REAL,
    precision_at_05    REAL,
    recall_at_05       REAL,
    mae                REAL,
	notes              TEXT , 
    calibration_summary JSONB,                  -- массив бинов: {bin_low, bin_high, avg_pred, obs_freq, count}
    calculated_at      TIMESTAMPTZ DEFAULT now()
	ece REAL , 
	mce REAL
);

CREATE UNIQUE INDEX ON mchain_quality_metrics_history (date_from, date_to);

COMMENT ON TABLE mchain_quality_metrics_history IS 'агрегированные метрики по дням';
COMMENT ON COLUMN mchain_quality_metrics_history.id IS 'Первичный ключ, автоматически генерируемый идентификатор записи.';
COMMENT ON COLUMN mchain_quality_metrics_history.date_from IS 'Начало периода агрегации (обычно 00:00 дня расчёта).';
COMMENT ON COLUMN mchain_quality_metrics_history.date_from IS 'Конец периода агрегации (обычно следующий день, 00:00). Для суточных данных date_to = date_from + 1. Уникальность пары (date_from, date_to) гарантирует отсутствие дублей.';
COMMENT ON COLUMN mchain_quality_metrics_history.total_predictions IS 'Общее количество прогнозов за период, для которых уже известен фактический исход (actual_outcome не NULL). Если значение меньше порога (например, 100), метрики могут быть пропущены.';
COMMENT ON COLUMN mchain_quality_metrics_history.incident_rate IS 'Доля фактических инцидентов (аварийных переходов) среди всех прогнозов за период. Вычисляется как AVG(actual_outcome).';
COMMENT ON COLUMN mchain_quality_metrics_history.brier_score IS 'Среднеквадратичная ошибка вероятности: AVG((predicted_risk - actual_outcome)²). Диапазон [0, 1], чем меньше, тем лучше.';
COMMENT ON COLUMN mchain_quality_metrics_history.log_loss IS 'Логистическая потеря: AVG(-[actual_outcome·ln(p) + (1−actual_outcome)·ln(1−p)]). Чувствительна к уверенным неправильным прогнозам.';
COMMENT ON COLUMN mchain_quality_metrics_history.roc_auc IS 'Площадь под ROC-кривой (дискриминационная способность). Значение > 0.7 считается хорошим, < 0.6 – низким. Вычисляется ранговым методом Манна‑Уитни.';
COMMENT ON COLUMN mchain_quality_metrics_history.precision_at_05 IS 'Точность (Precision) при пороге классификации 0.5: TP/(TP+FP).';
COMMENT ON COLUMN mchain_quality_metrics_history.recall_at_05 IS 'Полнота (Recall) при пороге 0.5: TP/(TP+FN).';
COMMENT ON COLUMN mchain_quality_metrics_history.mae IS 'Средняя абсолютная ошибка: AVG(|predicted_risk - actual_outcome|).';
COMMENT ON COLUMN mchain_quality_metrics_history.calibration_summary IS 'Детальная калибровочная таблица в формате JSON. Содержит массив бинов вероятности (по 10 интервалов от 0 до 1). Каждый бин включает: bin_low, bin_high, avg_pred (среднее предсказание в бине), obs_freq (наблюдаемая частота инцидентов), count (количество прогнозов в бине).';
COMMENT ON COLUMN mchain_quality_metrics_history.notes IS 'Дополнительная диагностическая информация. Если расчёт метрик был пропущен (например, из-за низкого рейтинга достоверности <3 или недостаточного числа прогнозов <100), здесь сохраняется причина. Для успешных расчётов – OK или NULL.';
COMMENT ON COLUMN mchain_quality_metrics_history.calculated_at IS 'Время вычисления и вставки записи (по умолчанию now()).';
COMMENT ON COLUMN mchain_quality_metrics_history.ece IS 'Expected Calibration Error (ECE) – средневзвешенное абсолютное отклонение между средней предсказанной вероятностью и наблюдаемой частотой в бинах. Характеризует систематическую ошибку калибровки. Чем меньше, тем лучше (цель < 0.05).';
COMMENT ON COLUMN mchain_quality_metrics_history.mce IS 'Maximum Calibration Error (MCE) – максимальное абсолютное отклонение между средней предсказанной вероятностью и наблюдаемой частотой среди всех бинов. Показывает наихудшую ошибку калибровки. Цель < 0.1.';
/*
Примеры использования
Получить динамику Brier score за последний месяц
SELECT date_from, brier_score, total_predictions
FROM mchain_quality_metrics_history
WHERE date_from >= CURRENT_DATE - INTERVAL '30 days'
  AND notes = 'OK'
ORDER BY date_from;

Проверить, были ли пропуски расчётов
SELECT date_from, notes
FROM mchain_quality_metrics_history
WHERE notes != 'OK'
ORDER BY date_from DESC
LIMIT 10;

Получить калибровочную кривую для конкретной даты
SELECT jsonb_pretty(calibration_summary)
FROM mchain_quality_metrics_history
WHERE date_from = '2026-06-15';
*/
-- ============================================================================
-- Ошибки прогноза
-- ============================================================================
DROP TABLE IF EXISTS mchain_quality_errors;
CREATE TABLE mchain_quality_errors (
    id BIGSERIAL PRIMARY KEY,
    ts TIMESTAMPTZ DEFAULT now(),
    error_message TEXT,
    function_name TEXT,
    details JSONB
);
COMMENT ON TABLE mchain_quality_errors IS 'Ошибки прогноза';


----------------------------------------------------------------------------------
-- 11. Создание и заполнение таблицы критических состояний

-- ============================================================================
-- Динамический список состояний, считающихся аварийными (поглощающими) для прогноза риска.
-- ============================================================================
DROP TABLE IF EXISTS critical_states;
CREATE TABLE IF NOT EXISTS critical_states (
    state_id   SMALLINT PRIMARY KEY,
    reason     TEXT,
    updated_at TIMESTAMPTZ DEFAULT now()
);
COMMENT ON TABLE critical_states IS 'Динамический список состояний, считающихся аварийными (поглощающими) для прогноза риска.';

INSERT INTO critical_states (state_id, reason)
VALUES
    (45, 'empirical_risk=0.3846, n=52'),
    (54, 'empirical_risk=0.3208, n=53'),
    (81, 'empirical_risk=0.3032, n=155'),
    (71, 'empirical_risk=0.2571, n=140'),
    (63, 'empirical_risk=0.2442, n=86'),
    (38, 'empirical_risk=0.2410, n=444'),
    (72, 'empirical_risk=0.2403, n=129'),
    (89, 'empirical_risk=0.2383, n=235'),
    (99, 'empirical_risk=0.2160, n=287'),
    (90, 'empirical_risk=0.1985, n=267'),
    (80, 'empirical_risk=0.1928, n=166'),
    (47, 'empirical_risk=0.1637, n=397'),
    (110, 'empirical_risk=0.1600, n=75'),
    (116, 'empirical_risk=0.1520, n=329'),
    (107, 'empirical_risk=0.1467, n=259'),
    (108, 'empirical_risk=0.1406, n=320'),
    (98, 'empirical_risk=0.1329, n=286'),
    (96, 'empirical_risk=0.1314, n=175'),
    (101, 'empirical_risk=0.1182, n=110'),
    (125, 'empirical_risk=0.1099, n=382'),
    (134, 'empirical_risk=0.1059, n=340'),
    (62, 'empirical_risk=0.1053, n=57'),
    (29, 'empirical_risk=0.1011, n=445')
ON CONFLICT (state_id) DO UPDATE SET reason = EXCLUDED.reason, updated_at = now();

----------------------------------------------------------------------------------
-- 12. Эмпирический подбор параметров адаптивного забывания

--------------------------------------------------------------
-- Таблица для логирования экспериментов по подбору параметров
--------------------------------------------------------------
DROP TABLE IF EXISTS forgetting_optimization_log;
-- Таблица для логирования экспериментов
CREATE TABLE IF NOT EXISTS forgetting_optimization_log (
    id SERIAL PRIMARY KEY,
    ts TIMESTAMPTZ DEFAULT now(),
    base_alpha REAL,
    half_life REAL,
    min_alpha REAL,
    interval_minute INT,
    period_start DATE,
    period_end DATE,
    eval_start DATE,
    eval_end DATE,
    total_predictions INT,
    incident_rate REAL,
    brier REAL,
    log_loss REAL,
    roc_auc REAL,
    precision_at_05 REAL,
    recall_at_05 REAL,
    mae REAL,
    max_prob_change REAL,
    coverage_pct INT,
    is_best BOOLEAN DEFAULT FALSE,
    notes TEXT
);

CREATE INDEX IF NOT EXISTS idx_forgetting_optimization_log_ts ON forgetting_optimization_log(ts);
CREATE INDEX IF NOT EXISTS idx_forgetting_optimization_log_is_best ON forgetting_optimization_log(is_best);
COMMENT ON TABLE forgetting_optimization_log IS 'Журнал экспериментов по подбору параметров забывания';

-- Таблица для логирования экспериментов по подбору параметров
--------------------------------------------------------------

----------------------------------------------------------------------------------------------------------------
-- v.13
-- Таблица для логирования прогресса обучения
DROP TABLE IF EXISTS mchain_train_progress_log;
CREATE TABLE IF NOT EXISTS mchain_train_progress_log (
    id                BIGSERIAL PRIMARY KEY,
    ts                TIMESTAMPTZ DEFAULT now(),
    total_records     BIGINT,
    processed_records BIGINT,
    percent           INT,
    transitions       BIGINT,
    message           TEXT
);
COMMENT ON TABLE mchain_train_progress_log IS 'Лог прогресса выполнения mchain_initial_train_from_history';

-- ====================================================================================================
-- Создание таблицы performance_history 
-- ====================================================================================================
DROP TABLE IF EXISTS performance_history;
CREATE TABLE IF NOT EXISTS performance_history (
    id          BIGSERIAL PRIMARY KEY,
    ts          TIMESTAMPTZ NOT NULL UNIQUE,
    op_speed    REAL,                     -- операционная скорость в данной точке
    waitings    REAL,                     -- ожидания СУБД в данной точке
    correlation REAL,                     -- корреляция скорость-ожидания за окно 1 час
    os_angle    REAL,                     -- угол наклона тренда операционной скорости (градусы)
    wait_angle  REAL                      -- угол наклона тренда ожиданий (градусы)
);

COMMENT ON TABLE performance_history IS 'История производительности с рассчитанными метриками за окно 1 час';
COMMENT ON COLUMN performance_history.ts IS 'Временная точка (минута)';
COMMENT ON COLUMN performance_history.op_speed IS 'Операционная скорость в этот момент (из cluster_stat_median)';
COMMENT ON COLUMN performance_history.waitings IS 'Ожидания СУБД в этот момент (из cluster_stat_median)';
COMMENT ON COLUMN performance_history.correlation IS 'Корреляция между скоростью и ожиданиями за предшествующий час';
COMMENT ON COLUMN performance_history.os_angle IS 'Угол наклона тренда операционной скорости за предшествующий час';
COMMENT ON COLUMN performance_history.wait_angle IS 'Угол наклона тренда ожиданий за предшествующий час';


