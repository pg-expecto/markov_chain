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
-- markov_chain_reports_tables.sql
-- version 26.2.1.1
--------------------------------------------------------------------------------
-- Таблицы для отчетов по цепи Маркова 
--------------------------------------------------------------------------------
-- ============================================================================
-- Таблица: profile_hourly
-- Назначение: хранение агрегированных метрик профиля производительности
--             с часовой детализацией. Используется для оперативных дашбордов
--             и отслеживания изменений в течение дня.
-- Заполняется: build_profile_hourly()
-- Версия: 26.2.1.1
-- ============================================================================
CREATE TABLE IF NOT EXISTS profile_hourly (
    bucket_hour timestamptz PRIMARY KEY,        -- начало часового интервала (округление до часа)
    avg_speed numeric,                          -- средняя операционная скорость за час
    avg_waitings numeric,                       -- среднее суммарное время ожидания за час
    avg_correlation numeric,                    -- средняя корреляция speed/waitings
    avg_slope_speed numeric,                    -- средний наклон тренда операционной скорости
    avg_slope_waitings numeric,                 -- средний наклон тренда времени ожидания
    avg_js_divergence numeric,                  -- средняя JS-дивергенция текущего профиля с эталоном
    max_js_divergence numeric,                  -- максимальная JS-дивергенция в часе (пиковые отклонения)
    avg_entropy numeric,                        -- средняя энтропия распределения состояний
    critical_state_share numeric,               -- доля критических состояний (0–1)
    anomaly_count integer,                      -- число записей anomaly_log за час
    sicpp_active_share numeric,                 -- доля времени активности сигнала SICPP (0–1)
    sicpp_activations integer,                  -- количество активаций сигнала SICPP
    sicpp_lead_time_avg numeric,                -- среднее время упреждения SICPP (мин)
    c_only_active_share numeric,                -- доля времени активности флага C-only (0–1)
    c_only_activations integer,                 -- количество активаций флага C-only
    c_only_lead_time_avg numeric,               -- среднее время упреждения C-only (мин)
    created_at timestamptz DEFAULT now()        -- время последней записи/обновления
);

COMMENT ON TABLE profile_hourly IS
    'Часовое агрегирование метрик профиля производительности PostgreSQL. Используется для оперативной визуализации и анализа в течение дня.';
COMMENT ON COLUMN profile_hourly.bucket_hour IS 'Начало часового интервала (date_trunc(''hour'', timestamp)).';
COMMENT ON COLUMN profile_hourly.avg_speed IS 'Средняя операционная скорость за час (базовая метрика цепи Маркова).';
COMMENT ON COLUMN profile_hourly.avg_waitings IS 'Среднее время ожидания по wait_event_type за час.';
COMMENT ON COLUMN profile_hourly.avg_correlation IS 'Средняя корреляция между операционной скоростью и временем ожидания.';
COMMENT ON COLUMN profile_hourly.avg_slope_speed IS 'Средний угол наклона тренда операционной скорости; <0 — признак деградации.';
COMMENT ON COLUMN profile_hourly.avg_slope_waitings IS 'Средний угол наклона тренда времени ожидания; >0 — признак деградации.';
COMMENT ON COLUMN profile_hourly.avg_js_divergence IS 'Средняя JS-дивергенция между текущим и эталонным профилями (порог WARNING = 0.05).';
COMMENT ON COLUMN profile_hourly.max_js_divergence IS 'Максимальная JS-дивергенция в часе; используется для выявления пиковых отклонений.';
COMMENT ON COLUMN profile_hourly.avg_entropy IS 'Средняя энтропия распределения состояний; рост указывает на хаотизацию профиля.';
COMMENT ON COLUMN profile_hourly.critical_state_share IS 'Доля времени в критических состояниях (0–1).';
COMMENT ON COLUMN profile_hourly.anomaly_count IS 'Количество аномалий из anomaly_log, зарегистрированных за час.';
COMMENT ON COLUMN profile_hourly.sicpp_active_share IS 'Доля времени, в течение которого сигнал SICPP был активен (0–1).';
COMMENT ON COLUMN profile_hourly.sicpp_activations IS 'Количество переходов SICPP из неактивного в активное состояние.';
COMMENT ON COLUMN profile_hourly.sicpp_lead_time_avg IS 'Среднее время упреждения SICPP до инцидента, мин.';
COMMENT ON COLUMN profile_hourly.c_only_active_share IS 'Доля времени активности флага C-only (0–1).';
COMMENT ON COLUMN profile_hourly.c_only_activations IS 'Количество активаций флага C-only.';
COMMENT ON COLUMN profile_hourly.c_only_lead_time_avg IS 'Среднее время упреждения флага C-only до инцидента, мин.';
COMMENT ON COLUMN profile_hourly.created_at IS 'Время последнего обновления записи.';

-- ============================================================================
-- Таблица: profile_daily
-- Назначение: суточное агрегирование метрик профиля производительности.
--             Используется для ежедневных отчётов и выявления устойчивых
--             трендов.
-- Заполняется: build_profile_daily()
-- Версия: 26.2.1.1
-- ============================================================================
CREATE TABLE IF NOT EXISTS profile_daily (
    bucket_day date PRIMARY KEY,                -- календарный день
    avg_speed numeric,                          -- средняя операционная скорость за день
    avg_waitings numeric,                       -- среднее время ожидания за день
    avg_correlation numeric,                    -- средняя корреляция за день
    avg_slope_speed numeric,                    -- средний наклон тренда скорости
    avg_slope_waitings numeric,                 -- средний наклон тренда ожиданий
    avg_js_divergence numeric,                  -- средняя JS-дивергенция за день
    max_js_divergence numeric,                  -- максимальная JS-дивергенция за день
    avg_entropy numeric,                        -- средняя энтропия за день
    critical_state_share numeric,               -- доля критических состояний
    anomaly_count integer,                      -- число аномалий за день
    sicpp_true_positive_rate numeric,           -- доля подтверждённых активаций SICPP
    c_only_precision numeric,                   -- точность флага C-only
    incident_coverage_total numeric,            -- общее покрытие инцидентов сигналами
    false_positive_episode_count integer,       -- количество ложных эпизодов
    created_at timestamptz DEFAULT now()        -- время последней записи/обновления
);

COMMENT ON TABLE profile_daily IS
    'Суточное агрегирование метрик профиля производительности PostgreSQL. Основа ежедневных отчётов и анализа устойчивых трендов.';
COMMENT ON COLUMN profile_daily.bucket_day IS 'Календарный день (date_trunc(''day'', timestamp)).';
COMMENT ON COLUMN profile_daily.avg_js_divergence IS 'Средняя JS-дивергенция за день относительно эталонного профиля.';
COMMENT ON COLUMN profile_daily.max_js_divergence IS 'Максимальное значение JS-дивергенции за день.';
COMMENT ON COLUMN profile_daily.critical_state_share IS 'Доля времени в критических состояниях за день (0–1).';
COMMENT ON COLUMN profile_daily.sicpp_true_positive_rate IS 'Доля активаций SICPP, подтверждённых последующим инцидентом (точность).';
COMMENT ON COLUMN profile_daily.c_only_precision IS 'Точность флага C-only: доля активаций, подтверждённых инцидентом.';
COMMENT ON COLUMN profile_daily.incident_coverage_total IS 'Доля инцидентов, которым предшествовал хотя бы один сигнал (SICPP или C-only).';
COMMENT ON COLUMN profile_daily.false_positive_episode_count IS 'Число эпизодов активации сигнала без последующего инцидента.';

-- ============================================================================
-- Таблица: profile_weekly
-- Назначение: недельное агрегирование метрик профиля производительности.
--             Используется для еженедельных отчётов и стратегического анализа.
-- Заполняется: build_profile_weekly()
-- Версия: 26.2.1.1
-- ============================================================================
CREATE TABLE IF NOT EXISTS profile_weekly (
    week_start date PRIMARY KEY,                -- дата начала недели (понедельник)
    avg_speed numeric,                          -- средняя операционная скорость за неделю
    avg_waitings numeric,                       -- среднее время ожидания за неделю
    avg_correlation numeric,                    -- средняя корреляция за неделю
    avg_js_divergence numeric,                  -- средняя JS-дивергенция за неделю
    max_js_divergence numeric,                  -- максимальная JS-дивергенция за неделю
    avg_entropy numeric,                        -- средняя энтропия за неделю
    critical_state_share numeric,               -- доля критических состояний
    anomaly_count integer,                      -- число аномалий за неделю
    transition_period_count integer,            -- число переходных периодов за неделю
    sicpp_weekly_coverage numeric,              -- покрытие инцидентов сигналом SICPP
    c_only_weekly_coverage numeric,             -- покрытие инцидентов флагом C-only
    avg_lead_time_sicpp numeric,                -- среднее время упреждения SICPP, мин
    avg_lead_time_c_only numeric,               -- среднее время упреждения C-only, мин
    created_at timestamptz DEFAULT now()        -- время последней записи/обновления
);

COMMENT ON TABLE profile_weekly IS
    'Недельное агрегирование метрик профиля производительности PostgreSQL. Основа еженедельных отчётов и стратегического анализа.';
COMMENT ON COLUMN profile_weekly.week_start IS 'Дата начала недели (date_trunc(''week'', timestamp)::date).';
COMMENT ON COLUMN profile_weekly.transition_period_count IS 'Количество переходных периодов, зафиксированных за неделю.';
COMMENT ON COLUMN profile_weekly.sicpp_weekly_coverage IS 'Доля инцидентов за неделю, которым предшествовал сигнал SICPP.';
COMMENT ON COLUMN profile_weekly.c_only_weekly_coverage IS 'Доля инцидентов за неделю, которым предшествовал флаг C-only.';
COMMENT ON COLUMN profile_weekly.avg_lead_time_sicpp IS 'Среднее время упреждения SICPP за неделю, мин.';
COMMENT ON COLUMN profile_weekly.avg_lead_time_c_only IS 'Среднее время упреждения C-only за неделю, мин.';

-- ============================================================================
-- Таблица: profile_transition_periods
-- Назначение: хранение обнаруженных переходных периодов (деградация,
--             восстановление, нестабильность) с указанием подтверждающих
--             сигналов и атрибутов критичности.
-- Заполняется: detect_transition_periods()
-- Версия: 26.2.1.1
-- ============================================================================
CREATE TABLE IF NOT EXISTS profile_transition_periods (
    period_id bigserial PRIMARY KEY,            -- суррогатный идентификатор периода
    start_time timestamptz NOT NULL,            -- начало переходного периода
    end_time timestamptz NOT NULL,              -- окончание переходного периода
    duration_minutes integer,                   -- длительность периода, мин
    period_type text,                           -- degradation / recovery / instability
    status text,                                -- WARNING / CRITICAL / INCIDENT
    confirming_signals text[],                  -- перечень подтверждающих сигналов
    max_js numeric,                             -- максимальная JS-дивергенция за период
    avg_js numeric,                             -- средняя JS-дивергенция за период
    max_z_score numeric,                        -- максимальная Z-оценка метрик
    slope_speed numeric,                        -- средний наклон тренда скорости
    slope_waitings numeric,                     -- средний наклон тренда ожиданий
    correlation numeric,                        -- средняя корреляция
    entropy numeric,                            -- средняя энтропия
    critical_state_share numeric,               -- доля критических состояний
    affected_metrics text[],                    -- перечень затронутых метрик
    related_anomaly_ids bigint[],               -- связанные записи anomaly_log
    criticality text,                           -- low / medium / high
    confidence text,                            -- low / medium / high
    probable_cause text,                        -- предварительная причина/гипотеза
    recommendation text,                        -- рекомендуемое действие
    created_at timestamptz DEFAULT now()        -- время записи
);

COMMENT ON TABLE profile_transition_periods IS
    'Обнаруженные переходные периоды профиля производительности с подтверждающими сигналами, атрибутами критичности и рекомендациями.';
COMMENT ON COLUMN profile_transition_periods.period_id IS 'Суррогатный первичный ключ переходного периода.';
COMMENT ON COLUMN profile_transition_periods.start_time IS 'Начало переходного периода (первый час с устойчивым отклонением).';
COMMENT ON COLUMN profile_transition_periods.end_time IS 'Окончание переходного периода (последний час отклонения + 1 час).';
COMMENT ON COLUMN profile_transition_periods.duration_minutes IS 'Длительность периода в минутах.';
COMMENT ON COLUMN profile_transition_periods.period_type IS 'Тип периода: degradation (деградация), recovery (восстановление), instability (нестабильность).';
COMMENT ON COLUMN profile_transition_periods.status IS 'Статус периода: WARNING, CRITICAL или INCIDENT.';
COMMENT ON COLUMN profile_transition_periods.confirming_signals IS 'Массив подтверждающих сигналов (JS, Z-оценки, тренды, энтропия, SICPP, C-only).';
COMMENT ON COLUMN profile_transition_periods.max_js IS 'Максимальная JS-дивергенция за период.';
COMMENT ON COLUMN profile_transition_periods.avg_js IS 'Средняя JS-дивергенция за период.';
COMMENT ON COLUMN profile_transition_periods.max_z_score IS 'Максимальная Z-оценка по ключевым метрикам за период.';
COMMENT ON COLUMN profile_transition_periods.affected_metrics IS 'Перечень метрик, по которым зафиксированы отклонения.';
COMMENT ON COLUMN profile_transition_periods.related_anomaly_ids IS 'Идентификаторы связанных записей anomaly_log.';
COMMENT ON COLUMN profile_transition_periods.criticality IS 'Степень критичности: low / medium / high.';
COMMENT ON COLUMN profile_transition_periods.confidence IS 'Уверенность в обнаружении: low / medium / high.';
COMMENT ON COLUMN profile_transition_periods.probable_cause IS 'Предварительная гипотеза о причине переходного периода.';
