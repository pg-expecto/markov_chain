# Реализация цепи Маркова для прогнозирования риска в PostgreSQL

## Общее описание

Данный механизм представляет собой полноценную реализацию **цепи Маркова с дискретными состояниями** в экосистеме PostgreSQL, предназначенную для **прогнозирования риска инцидентов производительности СУБД** на основе анализа динамики трёх ключевых метрик:

- **Корреляции** между операционной скоростью и временем ожидания
- **Тренда операционной скорости** (OS)
- **Тренда времени ожидания** (Wait)

Система состоит из 189 дискретных состояний, полученных путём комбинации значений корреляции (21 градация от -1.0 до +1.0 с шагом 0.1) и трендов (-1, 0, +1 для OS и Wait). Каждое состояние описывает текущее поведение системы и используется для построения марковской модели переходов.

### Ключевые особенности

- **Пошаговое обучение в реальном времени**: функция `mchain_train_step()` вызывается каждую минуту с новыми метриками производительности
- **Адаптивное забывание**: динамическая коррекция вероятностей с учётом времени, прошедшего с последнего инцидента
- **Прогнозирование риска**: вычисление вероятности попадания в критическое состояние в течение заданного горизонта (от 5 до 120 минут)
- **Критические состояния**: динамически обновляемый список состояний с высоким эмпирическим риском
- **Самодиагностика**: метрики качества прогнозов (Brier, Log-Loss, ROC-AUC, калибровка) и оценка достоверности модели

### Архитектурная схема

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        Внешний сборщик метрик                               │
│              performance_metrics (ежеминутный вызов)                        │
└───────────────────────────────┬─────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                    mchain_train_step() — корневая функция                   │
│  • Получение метрик (correlation, os_trend, wait_trend)                    │
│  • Определение state_id                                                    │
│  • Логирование перехода                                                    │
│  • Обновление цепи (markov_chain)                                          │
│  • Плановое забывание (если интервал истёк)                                │
│  • Формирование прогноза (collect_prediction)                              │
└───────────────────────────────┬─────────────────────────────────────────────┘
                                │
        ┌───────────────────────┼────────────────────────────────┐
        │                       │                                │
        ▼                       ▼                                ▼
┌───────────────┐       ┌───────────────┐                ┌──────────────┐
│transition_log │       │markov_        │                │prediction_log│
│(журнал        │       │frequencies    │                │(прогнозы)    │
│переходов)     │       │(частоты)      │                │              │
└───────────────┘       └───────┬───────┘                └──────┬───────┘
                                │                                │
                                ▼                                │
┌────────────────────────────────────────────┐                    │
│    update_markov_probabilities()           │                    │
│    rebuild_markov_absorbing()              │◄───────────────────┘
└────────────────────────────────────────────┘
```

---

## Подробное описание корневой функции `mchain_train_step()`

### Назначение

Ежеминутный шаг обучения цепи Маркова. Вызывается из внешнего сборщика метрик производительности. Выполняет полный цикл обновления модели: определение текущего состояния, логирование перехода, обновление частот, плановое забывание и формирование прогноза.

### Алгоритм работы

```sql
CREATE OR REPLACE FUNCTION mchain_train_step()
RETURNS TEXT
LANGUAGE plpgsql AS $$
```

**Шаг 1. Инициализация справочника состояний**
```sql
IF NOT EXISTS (SELECT 1 FROM state_descriptions) THEN
    PERFORM fill_state_descriptions();
END IF;
```

**Шаг 2. Получение текущих метрик производительности**
```sql
SELECT * INTO curr_vals 
FROM get_current_os_waiting_correlation_for_markov_chain();
```
Внешняя функция `get_current_os_waiting_correlation_for_markov_chain()` возвращает:
- `current_correlation` — коэффициент корреляции (REAL, -1.0 … +1.0)
- `current_os_trend` — тренд операционной скорости (-1, 0, 1)
- `current_wait_trend` — тренд времени ожидания (-1, 0, 1)

Если метрики не собраны (`NULL`), функция завершается с сообщением `'No metrics available'`.

**Шаг 3. Преобразование метрик в state_id**
```sql
curr_state := get_state_id(
    curr_vals.current_correlation,
    curr_vals.current_os_trend,
    curr_vals.current_wait_trend
);
```
Функция `get_state_id()` вычисляет числовой идентификатор состояния (0…188) по формуле:
```
state_id = (round((r + 1.0) / 0.1)::int * 9) + ((os_trend + 1)::int * 3) + (wait_trend + 1)::int
```

**Шаг 4. Получение предыдущего состояния из `markov_chain`**
```sql
SELECT prev_correlation, prev_os_trend, prev_wait_trend,
       curr_correlation, curr_os_trend, curr_wait_trend
INTO chain_rec
FROM markov_chain LIMIT 1;
```
Если цепь пуста (первый запуск), сохраняется начальное состояние и функция завершается.

**Шаг 5. Логирование перехода**
```sql
prev_state := get_state_id(chain_rec.curr_correlation, 
                           chain_rec.curr_os_trend, 
                           chain_rec.curr_wait_trend);
PERFORM mchain_log_transition(prev_state, curr_state);
```
Функция `mchain_log_transition()`:
- Добавляет запись в `transition_log` (с меткой времени)
- Обновляет или вставляет частоту в `markov_frequencies`

**Шаг 6. Обновление состояния в `markov_chain`**
```sql
UPDATE markov_chain SET
    prev_correlation = curr_correlation,
    prev_os_trend    = curr_os_trend,
    prev_wait_trend  = curr_wait_trend,
    curr_correlation = curr_vals.current_correlation,
    curr_os_trend    = curr_vals.current_os_trend,
    curr_wait_trend  = curr_vals.current_wait_trend;
```

**Шаг 7. Плановое забывание**
```sql
IF now() - cfg.last_forget_time >= MAKE_INTERVAL(mins => cfg.interval_minute) THEN
    PERFORM mchain_apply_forgetting();
END IF;
```
Проверяется, истёк ли интервал с последнего забывания. Если да — вызывается `mchain_apply_forgetting()`.

**Шаг 8. Формирование прогноза**
```sql
PERFORM collect_prediction();
```
Создаётся запись в `prediction_log` с текущим риском на горизонт из конфигурации.

### Результат
Функция возвращает текстовый статус:
- `'No metrics available'` — метрики не собраны
- `'Initial state saved'` — первый запуск, цепь инициализирована
- `'Step completed'` — успешное выполнение
- `'Step completed but forgetting failed'` — шаг выполнен, но забывание завершилось ошибкой
- `'Error: cannot get metrics'` — ошибка получения метрик
- `'Error: transition logging failed'` — ошибка логирования перехода

---

## Реализация обучения цепи Маркова

### 1. Историческое обучение (`train_markov_chain.sh`)

Скрипт предназначен для **первоначального обучения** модели на исторических данных из таблицы `cluster_stat_median`. Выполняется в несколько этапов:

#### Этап 0 — Полная очистка
```sql
TRUNCATE TABLE transition_log RESTART IDENTITY CASCADE;
TRUNCATE TABLE markov_frequencies RESTART IDENTITY CASCADE;
TRUNCATE TABLE markov_probabilities RESTART IDENTITY CASCADE;
TRUNCATE TABLE markov_chain RESTART IDENTITY CASCADE;
TRUNCATE TABLE prediction_log RESTART IDENTITY CASCADE;
TRUNCATE TABLE apply_forgetting_log RESTART IDENTITY CASCADE;
TRUNCATE TABLE mchain_error_log RESTART IDENTITY CASCADE;
TRUNCATE TABLE mchain_quality_metrics_history RESTART IDENTITY CASCADE;
```
Все таблицы модели очищаются, кроме `markov_config`.

#### Этап 0.5 — Адаптивная настройка конфигурации
```sql
SELECT adaptive_configure_markov_chain('$END_TIME'::TIMESTAMPTZ);
```
Параметры цепи (горизонт, alpha, half_life, интервал забывания) подбираются автоматически на основе частоты инцидентов за период, равный `transition_log_retention_days`.

#### Этап 1 — Заполнение `performance_history`
```sql
PERFORM fill_performance_history(
    (SELECT MIN(curr_timestamp) FROM cluster_stat_median),
    '$END_TIME'::TIMESTAMPTZ
);
```
Вычисляются корреляции и тренды за каждый час для всех минут в указанном диапазоне.

#### Этап 2 — Пакетное обучение (порциями по 60 минут)
```sql
SELECT mchain_train_historical_chunk('$CURRENT_TS'::TIMESTAMPTZ, '$NEXT_TS'::TIMESTAMPTZ);
```
Имитируется реальное поступление метрик. Для каждой минуты:
- Определяется состояние (correlation, os_trend, wait_trend)
- Логируется переход
- Обновляется цепь
- Применяется забывание (если интервал истёк)
- Формируется прогноз

#### Этап 3–5 — Финализация
- Восстанавливается триггер `trigger_update_incident_time`
- Обновляется `last_incident_time` в конфигурации
- Пересчитываются исходы прогнозов (`update_prediction_outcomes()`)
- Пересчитываются вероятности (`update_markov_probabilities()`)
- Перестраивается поглощающая матрица (`rebuild_markov_absorbing()`)

#### Этап 6 — Динамический подбор горизонта
Цикл из 6 итераций, цель — достичь целевой доли инцидентов среди прогнозов (≈15%):
1. Обновляются критические состояния с текущим порогом риска
2. Подбирается оптимальный горизонт (`find_optimal_horizon`)
3. Устанавливаются усиленные параметры забывания (`alpha=0.15`, `half_life=5`)
4. Пересоздаются прогнозы с новым горизонтом
5. Пересчитываются исходы
6. Проверяется фактическая доля инцидентов

#### Этап 6.5 — Усиленное забывание
```sql
SELECT mchain_apply_forgetting(0.15);
```
Применяется забывание с `alpha=0.15` для стабилизации вероятностей.

#### Этап 7–8 — Метрики и протокол
- Расчёт суточных метрик качества (`calculate_daily_quality_metrics`)
- Проверка рейтинга достоверности (`mchain_forecast_reliability`)
- При рейтинге < 3 — дополнительное забывание с `alpha=0.20`
- Формирование итогового протокола со всеми ключевыми метриками

### 2. Функция `mchain_initial_train_from_history`

Альтернативный способ обучения — встроенная процедура, которая выполняет полный цикл обучения на исторических данных из `cluster_stat_median` с логированием прогресса.

**Параметры:**
- `p_end TIMESTAMPTZ` — конечная точка обучения
- `p_refresh_critical BOOLEAN DEFAULT TRUE` — обновлять ли критические состояния
- `p_risk_threshold REAL DEFAULT 0.10` — порог риска для critical_states
- `p_min_transitions INT DEFAULT 50` — минимальное число переходов
- `p_interval_min INT DEFAULT 15` — интервал для расчёта эмпирического риска
- `INOUT result TEXT` — итоговый отчёт

**Прогресс** выводится через `RAISE NOTICE` каждые 1% и записывается в таблицу `mchain_train_progress_log`.

### 3. Функция `mchain_train_historical_chunk`

Обучение за один непрерывный отрезок времени. Используется в скрипте для пакетной обработки (порции по 60 минут). Не управляет триггерами и не изменяет `last_forget_time` (это делается один раз перед началом всего обучения).

---

## Реализация адаптивного забывания

### Основная функция `mchain_apply_forgetting()`

```sql
CREATE OR REPLACE FUNCTION mchain_apply_forgetting(
    alpha_override REAL DEFAULT NULL,
    p_max_alpha REAL DEFAULT 0.5
)
RETURNS VOID
```

**Логика работы:**

1. **Проверка глобального флага**
   ```sql
   IF NOT cfg.adaptive_forgetting_enabled THEN
       RETURN;
   END IF;
   ```
   Если забывание отключено в конфигурации — выход.

2. **Проверка достаточности данных**
   ```sql
   SELECT s.sufficient, s.stability_factor 
   INTO is_sufficient, stability_factor
   FROM mchain_check_sufficiency() AS s;
   ```
   - `sufficient` — общее число переходов >= `min_transitions_for_forgetting`
   - `stability_factor` — коэффициент, зависящий от `max_prob_change`:
     - ≤ 0.05 → 1.0
     - ≤ 0.2 → 1.5
     - ≤ 0.5 → 2.0
     - > 0.5 → 3.0

3. **Расчёт эффективного `alpha`**
   ```sql
   IF alpha_override IS NOT NULL THEN
       effective_alpha := alpha_override;
   ELSIF cfg.use_adaptive_alpha THEN
       days_since := EXTRACT(EPOCH FROM (now() - cfg.last_incident_time)) / 86400.0;
       effective_alpha := cfg.base_alpha * exp(-days_since / cfg.incident_half_life_days);
       effective_alpha := GREATEST(effective_alpha, cfg.min_alpha);
   ELSE
       effective_alpha := cfg.alpha;
   END IF;
   ```
   - **Адаптивный режим**: alpha уменьшается экспоненциально с момента последнего инцидента. Чем дольше не было инцидентов, тем меньше забывание.
   - **Фиксированный режим**: используется значение `alpha` из конфигурации.

4. **Масштабирование на коэффициент нестабильности**
   ```sql
   effective_alpha := LEAST(effective_alpha * stability_factor, p_max_alpha);
   ```
   Если вероятности нестабильны (`max_prob_change` высокий), alpha увеличивается для более быстрой адаптации.

5. **Применение забывания**
   ```sql
   UPDATE markov_frequencies
   SET frequency = frequency * (1.0 - effective_alpha)
   WHERE frequency > 0;
   
   DELETE FROM markov_frequencies WHERE frequency < 1e-6;
   ```
   Частоты уменьшаются, пренебрежимо малые значения удаляются.

6. **Пересчёт вероятностей и поглощающей матрицы**
   ```sql
   PERFORM update_markov_probabilities();
   UPDATE markov_config SET last_forget_time = now();
   ```
   На основе обновлённых частот пересчитываются вероятности переходов.

7. **Логирование**
   ```sql
   INSERT INTO apply_forgetting_log (...) VALUES (...);
   ```
   Сохраняется применённый `alpha`, детали расчёта и статус.

### Функция `mchain_check_sufficiency()`

Проверяет, достаточно ли накоплено данных для забывания:
- Общее число переходов ≥ `min_transitions_for_forgetting`
- Если переходов ≥ 5000 — дополнительно оценивается стабильность вероятностей за последние 2 недели (`max_prob_change`).

**Исключения:** переходы в критические состояния и из критических состояний **не участвуют** в расчёте `max_prob_change` для оценки стабильности.

### Функция `mchain_forecast_reliability()`

Оценивает достоверность прогнозов по шкале **0–5** на основе трёх компонентов:

| Компонент | Условия | Баллы |
|-----------|---------|-------|
| **Объём данных** | < 100 переходов → 0<br>< 500 → 1<br>< 5000 → 2<br>≥ 5000 → 3 | 0–3 |
| **Стабильность** | `max_prob_change` < 0.02 → +2<br>< 0.05 → +1 | 0–2 |
| **Покрытие** | покрытие ≥ 90% **и** `max_prob_change` < 0.2 → +1 | 0–1 |

Итоговый рейтинг: сумма баллов, ограниченная 5.

### Оптимизация параметров забывания

Процедура `optimize_forgetting_params()` выполняет **эмпирический подбор** параметров по сетке значений:

```sql
v_alphas    REAL[] := ARRAY[0.05, 0.1, 0.15, 0.2, 0.25];
v_halfs     REAL[] := ARRAY[2, 4, 7, 10, 14];
v_mins      REAL[] := ARRAY[0.005, 0.01, 0.015, 0.02];
v_intervals INT[] := ARRAY[60, 120, 180, 240];
```

Для каждой комбинации:
- Оценивается качество прогнозов на исторических данных (Brier score)
- Лучшая комбинация сохраняется в `forgetting_optimization_log`
- По завершении параметры обновляются в `markov_config`

**Пример запуска:**
```sql
CALL optimize_forgetting_params(result, p_dry_run => FALSE, p_verbose => TRUE);
```

---

## Функции прогнозирования риска

### `mchain_predict_risk_k_v2(state_id, k)`

Вычисляет вероятность хотя бы одного попадания в критическое множество за `k` шагов (минут). Использует **поглощающую матрицу** `markov_absorbing`, где критические состояния являются поглощающими.

**Алгоритм:**
1. Если текущее состояние уже критическое — возвращает 1.0
2. Инициализируется вектор распределения вероятностей
3. Для каждого шага `i = 1..k`:
   - Умножается вектор на матрицу переходов
   - Вероятность оказаться в критическом состоянии добавляется к накопленному риску
   - Вероятности в критических состояниях обнуляются (чтобы не учитывать повторные попадания)
4. Возвращается накопленный риск (ограниченный 1.0)

### `collect_prediction(p_time)`

Формирует прогноз для заданного времени:
```sql
risk := mchain_predict_risk_k_v2(curr_state, horizon);
INSERT INTO prediction_log (prediction_time, predicted_risk, current_state_id, horizon_minutes)
VALUES (p_time, risk, curr_state, horizon);
```

Горизонт берётся из `markov_config.forecast_horizon_minutes`.

### `update_prediction_outcomes()`

Обновляет исходы для прогнозов, у которых истёк горизонт. Для каждого прогноза ищется первый аварийный переход (`to_state` в `critical_states`) в интервале `(prediction_time, prediction_time + horizon]`. Устанавливаются:
- `actual_outcome` — 1 если инцидент был, иначе 0
- `first_incident_time` — время первого инцидента
- `incident_count` — общее число инцидентов в окне

---

## Отчёты и мониторинг

### `mchain_summary_report(p_start, p_end)`

Сводный отчёт, включающий:
- Достоверность прогнозов (`mchain_reliability_report`)
- Анализ переходов в аварийные состояния (`mchain_incident_transitions_report`)
- Конфигурацию модели
- Текущее состояние системы и прогноз риска

### `mchain_quality_report(p_start, p_end, p_horizon)`

Детальный отчёт о качестве прогнозов с метриками:
- Brier score
- Log-loss
- MAE
- **ECE (Expected Calibration Error)**
- **MCE (Maximum Calibration Error)**
- Precision/Recall при пороге 0.5
- ROC-AUC (с комментарием о применимости)
- Калибровочная таблица (10 бинов)

### `generate_full_analytical_report(p_start, p_end)`

Генерирует **полный аналитический отчёт** в формате Markdown (массив строк), который включает все ключевые разделы:
1. Общий обзор состояния цепи
2. Качество прогнозов
3. Матрица переходов между макрогруппами
4. Стабильность вероятностей
5. Скользящее качество прогнозов
6. Распределение состояний (топ-20)
7. Эффективность забывания
8. Калибровочная кривая за последний день

**Пример сохранения:**
```bash
psql -d expecto_db -U expecto_user -c \
  "select unnest(generate_full_analytical_report())" > /tmp/full_report.md
```

### `mchain_health_check()`

Проверяет состояние системы и возвращает:
- `status` — OK, WARNING или CRITICAL
- `message` — краткая сводка (≤1024 символов)
- `description[]` — массив описаний столбцов

Проверки включают:
- Достоверность прогнозов (рейтинг ≥ 3)
- Рост аварийных переходов (>2x за неделю)
- Активность (есть ли переходы за последние 10 минут)
- Наличие частот (`markov_frequencies`)
- Давность забывания

---

## Cron-задачи

| Время | Команда | Назначение |
|-------|---------|------------|
| `15 1 * * *` | `mchain_clean_transition_log()` | Очистка журнала переходов старше `transition_log_retention_days` |
| `0 2 * * *` | `mchain_clean_apply_forgetting_log()` | Очистка журнала забывания |
| `0 2 * * *` | `calculate_daily_quality_metrics(CURRENT_DATE - 1)` | Расчёт суточных метрик качества |
| `0 3 * * 6` | `refresh_critical_states()` | Обновление критических состояний (еженедельно, суббота) |
| `0 1 * * 0` | `refresh_stability_threshold()` | Адаптивная настройка `min_freq_for_stability` (воскресенье) |
| `*/5 * * * *` | `update_prediction_outcomes()` | Обновление исходов прогнозов (каждые 5 минут) |

---

## Критические состояния (`critical_states`)

Таблица критических состояний — **динамический список** состояний, считающихся аварийными (поглощающими). Обновляется функцией `refresh_critical_states()` на основе эмпирических рисков:

```sql
SELECT refresh_critical_states(
    p_start           => now() - interval '14 days',
    p_end             => now(),
    p_min_transitions => 50,
    p_interval_min    => 15,
    p_risk_threshold  => 0.10,
    p_dry_run         => FALSE,
    p_audit           => TRUE
);
```

**Алгоритм обновления:**
1. Для каждого состояния вычисляется эмпирическая вероятность инцидента в течение `interval_min` минут после перехода в это состояние
2. Состояния с `empirical_risk > risk_threshold` и числом переходов ≥ `min_transitions` становятся критическими
3. Состояния, переставшие удовлетворять критериям, удаляются из списка

**История изменений** сохраняется в таблице `critical_states_audit`.

---

## Рекомендации по эксплуатации

### 1. Первоначальное обучение
```bash
./train_markov_chain.sh "2026-06-30 23:59:59"
```
Обучает модель на всех исторических данных до указанной даты. Рекомендуется выполнять после развёртывания системы.

### 2. Регулярная оптимизация параметров
```sql
CALL optimize_forgetting_params(
    result        => '',
    p_dry_run     => FALSE,
    p_verbose     => TRUE,
    p_commit_every => 10
);
```
Выполнять ежемесячно или при ухудшении качества прогнозов.

### 3. Мониторинг достоверности
```sql
SELECT mchain_forecast_reliability();
```
При рейтинге < 3 — прогнозы ненадёжны, требуется накопление данных или настройка параметров.

### 4. Анализ качества
```sql
SELECT mchain_quality_report(CURRENT_DATE - 7, CURRENT_DATE - 1);
```
Контролировать Brier score и ECE. Целевые значения:
- Brier < 0.05 — отлично
- Brier 0.05–0.1 — хорошо
- ECE < 0.05 — отличная калибровка

### 5. Восстановление после сбоев
Если модель потеряна или повреждена:
```sql
TRUNCATE TABLE transition_log, markov_frequencies, markov_probabilities, markov_absorbing, markov_chain, prediction_log;
-- Затем выполнить историческое обучение заново
```

---

## Заключение

Представленная реализация цепи Маркова обеспечивает **полный цикл управления рисками** производительности СУБД:
- Автоматическое обучение на исторических и текущих данных
- Адаптивное забывание с учётом динамики инцидентов
- Многошаговое прогнозирование риска с калиброванными вероятностями
- Комплексный мониторинг качества и достоверности

Система готова к промышленной эксплуатации и может быть интегрирована с любым сборщиком метрик производительности PostgreSQL.
