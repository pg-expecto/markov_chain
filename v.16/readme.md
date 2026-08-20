# Цепь Маркова для прогнозирования инцидентов производительности (v.16.3)

## Общее описание

Система на основе **цепи Маркова** для мониторинга и прогнозирования инцидентов производительности СУБД.  
Она использует исторические данные о производительности (операционная скорость, ожидания) для построения модели переходов между состояниями, определяемыми корреляцией и трендами. Модель позволяет:

- Прогнозировать **риск возникновения инцидента** на заданном горизонте (в минутах).
- Обнаруживать **аномалии профиля нагрузки** путём сравнения текущего поведения с эталонным.
- Генерировать **сигналы раннего предупреждения** на основе JS-дивергенции и прогнозируемого риска.

Система реализована в виде набора таблиц и функций PostgreSQL, полностью интегрируется в существующую базу данных мониторинга.

---

## Основные возможности

### 🧠 Обучение модели
- **Ежеминутное обучение** в реальном времени (`mchain_train_step`).
- **Историческое обучение** за произвольный период (`mchain_initial_train_from_history`).
- Пакетная обработка для больших объёмов данных (`mchain_train_historical_chunk`).

### 🔮 Прогнозирование риска
- Вероятность попадания в **критическое состояние** за K шагов (`mchain_predict_risk_k_v2`).
- Автоматическое сохранение прогнозов в `prediction_log`.
- Обновление фактических исходов прогнозов по мере поступления данных.

### 🧹 Адаптивное забывание
- Динамический коэффициент забывания (`alpha`) в зависимости от времени, прошедшего с последнего инцидента.
- Автоматическая проверка достаточности данных перед забыванием.
- Периодическое применение забывания по расписанию.

### 📊 Профилирование нагрузки
- Вычисление **гистограмм состояний**, **энтропии**, **доли критических состояний**, **доли петель** и других метрик за окно.
- Поддержка трёх типов профилей: *operational* (60 мин), *daily* (24 ч), *weekly* (7 дней).
- Сравнение текущего профиля с эталонным (безынцидентное окно) с расчётом **JS-дивергенции**.

### 🚨 Генерация сигналов
- Комплексный сигнал на основе JS-дивергенции и прогнозируемого риска.
- Режимы: `AND`, `OR`, `WEIGHTED`.
- Учёт минимальной длительности сигнала для снижения ложных срабатываний.

### 📈 Отчёты и аналитика
- Сводный отчёт по состоянию модели (`mchain_summary_report`).
- Отчёт качества прогнозов (`mchain_quality_report`) с калибровкой, Brier, ECE, MCE.
- Отчёт по прогнозированию инцидентов (`generate_incident_forecast_report`).
- Аналитические отчёты по профилям и аномалиям.
- Полный аналитический отчёт в формате Markdown (`generate_full_analytical_report`).

---

## Архитектура

### Основные таблицы

| Таблица | Назначение |
|---------|------------|
| `markov_config` | Конфигурация модели (параметры обучения, забывания, горизонт). |
| `transition_log` | Журнал всех переходов между состояниями. |
| `markov_frequencies` | Накопленные частоты переходов (обновляются каждую минуту). |
| `markov_probabilities` | Матрица вероятностей переходов, пересчитываемая при забывании. |
| `markov_absorbing` | Поглощающая матрица для многошагового прогноза (критические состояния – поглощающие). |
| `state_descriptions` | Справочник 189 состояний (корреляция, тренды OS и ожиданий). |
| `markov_chain` | Текущее и предыдущее состояние цепи (всегда одна строка). |
| `prediction_log` | Журнал прогнозов риска. |
| `critical_states` | Динамический список состояний, считающихся аварийными (поглощающими). |
| `mchain_quality_metrics_history` | Агрегированные метрики качества прогнозов по дням. |

### Таблицы профилирования

| Таблица | Назначение |
|---------|------------|
| `profile_aggregated` | Хранит вычисленные профили (operational, daily, weekly, baseline, current). |
| `profile_baseline` | Эталонные профили по часам и дням недели (средние и стандартные отклонения). |
| `profile_comparison_log` | Журнал сравнений текущего профиля с эталонным (статус, JS-дивергенция, детали). |
| `pre_incident_profiles` | Библиотека профилей, предшествовавших инцидентам. |
| `profile_change_indicator` | Индикатор изменения профиля (сигнал о предаварийном состоянии). |
| `incident_forecast_config` | Конфигурация для генерации сигналов и отчётов по инцидентам. |

### Основные функции

| Функция | Назначение |
|---------|------------|
| `mchain_train_step()` | Ежеминутный шаг обучения (вызывается по cron). |
| `mchain_initial_train_from_history()` | Первоначальное историческое обучение с имитацией реального времени. |
| `mchain_train_historical()` | Полное историческое обучение от минимальной даты до указанной. |
| `mchain_predict_risk_k_v2()` | Прогноз риска попадания в критическое состояние за K шагов. |
| `mchain_apply_forgetting()` | Применение забывания с адаптивным или фиксированным alpha. |
| `collect_prediction()` | Сохранение прогноза в `prediction_log`. |
| `update_prediction_outcomes()` | Обновление фактических исходов прогнозов после истечения горизонта. |
| `calculate_profile_metrics()` | Вычисление метрик профиля для заданного временного окна. |
| `compare_profiles()` | Сравнение текущего и эталонного профилей с записью в лог. |
| `calculate_signal()` | Вычисление сигнала на основе JS-дивергенции и риска. |
| `generate_incident_forecast_report()` | Отчёт по прогнозированию инцидентов. |

---

## Установка и настройка

Подробная инструкция по установке и настройке приведена в файле **[install.md](install.md)**.

Основные шаги:

1. Создать таблицы и функции, выполнив SQL-скрипты в правильном порядке.
2. Настроить конфигурационные параметры (при необходимости).
3. Настроить cron-задачи для автоматического обслуживания.
4. Запустить историческое обучение с помощью скрипта `train_markov_chain2.sh`.

---

## Использование

### Обучение модели

**Первоначальное историческое обучение**  
Запустите скрипт, указав период (или без параметров – от начала данных до текущего момента):

```bash
./train_markov_chain2.sh --start "2024-01-01 00:00:00" --end "2024-01-31 23:59:59"
```

**Ежеминутное обучение в реальном времени**  
Настройте cron для вызова:

```sql
SELECT mchain_train_step();
```

### Получение прогноза

Текущий прогноз риска на горизонт, заданный в `markov_config.forecast_horizon_minutes`:

```sql
SELECT mchain_predict_risk_current_horizon();
```

### Просмотр отчётов

- **Сводный отчёт** по состоянию цепи:
  ```sql
  SELECT mchain_summary_report();
  ```
- **Отчёт качества прогнозов** за период:
  ```sql
  SELECT unnest(mchain_quality_report('2024-01-01', '2024-01-31'));
  ```
- **Полный аналитический отчёт** в формате Markdown:
  ```sql
  SELECT unnest(generate_full_analytical_report());
  ```
- **Отчёт по прогнозированию инцидентов** (за последние 7 дней):
  ```sql
  SELECT unnest(generate_incident_forecast_report());
  ```

### Управление профилями и сигналами

- Сохранить эталонный профиль на основе текущего безынцидентного окна:
  ```sql
  SELECT save_baseline_profile();
  ```
- Сохранить текущий профиль (например, за 60 минут):
  ```sql
  SELECT save_current_profile(60);
  ```
- Сравнить текущий профиль с эталонным:
  ```sql
  SELECT unnest(compare_profiles());
  ```
- Обновить индикатор изменения профиля (ежеминутно):
  ```sql
  SELECT update_profile_change_indicator();
  ```

---

## Конфигурация

### Основные параметры в `markov_config`

| Параметр | Описание |
|----------|----------|
| `forecast_horizon_minutes` | Горизонт прогноза (минуты). |
| `base_alpha` | Базовый коэффициент забывания (при частых инцидентах). |
| `min_alpha` | Минимальный alpha (при редких инцидентах). |
| `incident_half_life_days` | Период полураспада веса инцидента (дни). |
| `interval_minute` | Интервал между применениями забывания (минуты). |
| `min_transitions_for_forgetting` | Минимальное число переходов для включения забывания. |
| `min_freq_for_stability` | Минимальное число переходов из состояния для оценки стабильности. |
| `js_divergence_threshold` | Порог JS-дивергенции для сравнения профилей. |

### Параметры сигнала в `incident_forecast_config`

| Параметр | Описание |
|----------|----------|
| `js_threshold` | Порог JS-дивергенции. |
| `risk_threshold` | Порог прогнозируемого риска. |
| `signal_mode` | Режим комбинации: `'AND'`, `'OR'`, `'WEIGHTED'`. |
| `min_signal_duration` | Минимальная длительность сигнала (в минутах) для подтверждения. |
| `weight_js`, `weight_risk` | Веса для режима `WEIGHTED`. |
| `extended_report` | Включать ли расширенные столбцы в отчёте. |

---

## Примеры запросов

```sql
-- Получить текущий прогноз риска
SELECT mchain_predict_risk_current_horizon();

-- Рейтинг достоверности модели (0–5)
SELECT mchain_forecast_reliability();

-- Последние 10 сравнений профилей
SELECT created_at, status, js_divergence
FROM profile_comparison_log
ORDER BY created_at DESC LIMIT 10;

-- Все критические состояния
SELECT * FROM critical_states;

-- Распределение статусов сравнения за последние 7 дней
SELECT status, COUNT(*)
FROM profile_comparison_log
WHERE created_at >= now() - INTERVAL '7 days'
GROUP BY status;

-- Очистка старых записей сравнения (по расписанию)
SELECT clean_profile_comparison_log();
```

---

## Лицензия

Система распространяется под лицензией **Apache License, Version 2.0**.  
Полный текст лицензии доступен в файле [LICENSE](LICENSE).

---

## Поддержка

По вопросам и предложениям обращайтесь к разработчику: **Ринат** (марковская цепь, pg_expecto).

Репозиторий: [https://github.com/pg-expecto/markov_chain/tree/main/v.16](https://github.com/pg-expecto/markov_chain/tree/main/v.16)

---

# Установка цепи Маркова версии 16.3

## Требования

- PostgreSQL версии 13 или выше.
- Расширение `plpgsql` (обычно установлено по умолчанию).
- Утилита `bc` для вычислений в скриптах оболочки.
- Таблица `cluster_stat_median`, содержащая исторические данные производительности (поля `curr_timestamp`, `curr_op_speed`, `curr_waitings`).
- Права на создание таблиц, функций и выполнение процедур в целевой базе данных.

---

## Шаги установки

### 1. Подготовка файлов

Скопируйте все SQL-файлы в директорию на сервере, например:

```bash
mkdir -p /postgres/pg_expecto/sh
cd /postgres/pg_expecto/sh
```

Передайте файлы:

- `markov_chain_tables.sql`
- `markov_chain_profile_tables.sql`
- `markov_chain_functions.sql`
- `markov_chain_profile_functions.sql`
- `performance_metrics_for_markov_chain.sql`

### 2. Создание таблиц и функций

Выполните скрипты в указанном порядке.  
Для удобства можно использовать следующий блок (замените параметры подключения при необходимости):

```bash
psql -d expecto_db -U expecto_user -v ON_ERROR_STOP=on --echo-errors -f markov_chain_tables.sql > markov_chain_tables.log 2>&1
psql -d expecto_db -U expecto_user -v ON_ERROR_STOP=on --echo-errors -f markov_chain_profile_tables.sql > markov_chain_profile_tables.log 2>&1
psql -d expecto_db -U expecto_user -v ON_ERROR_STOP=on --echo-errors -f markov_chain_functions.sql > markov_chain_functions.log 2>&1
psql -d expecto_db -U expecto_user -v ON_ERROR_STOP=on --echo-errors -f markov_chain_profile_functions.sql > markov_chain_profile_functions.log 2>&1
psql -d expecto_db -U expecto_user -v ON_ERROR_STOP=on --echo-errors -f performance_metrics_for_markov_chain.sql > performance_metrics_for_markov_chain.log 2>&1
```

Проверьте логи на наличие ошибок.

### 3. Настройка параметров сигнала (опционально)

По умолчанию используется режим сигнала `'OR'`. Вы можете изменить его, например, на взвешенный:

```bash
psql -d expecto_db -U expecto_user -c "UPDATE incident_forecast_config SET signal_mode = 'WEIGHTED', weight_js = 0.9, weight_risk = 0.1, extended_report = TRUE;"
```

### 4. Настройка cron-задач

Для автоматической работы системы добавьте задачи из файла `markov_chain_cron.txt` в crontab пользователя, под которым работает PostgreSQL:

```bash
crontab -e
```

Вставьте содержимое:

```
# Очистка transition_log
15 1 * * * psql -d expecto_db -U expecto_user -c "SELECT mchain_clean_transition_log();"

# Очистка apply_forgetting_log
0 2 * * * psql -d expecto_db -U expecto_user -c "SELECT mchain_clean_apply_forgetting_log();"

# Обновление critical_states (суббота в 3:00)
0 3 * * 6 psql -d expecto_db -U expecto_user -c "SELECT refresh_critical_states();" >/postgres/pg_expecto/sh/refresh_critical_states.log 2>&1

# Обновление исходов прогнозов каждые 5 минут
*/5 * * * * psql -d expecto_db -U expecto_user -c "SELECT update_prediction_outcomes();"

# Расчёт суточных метрик качества в 2:00
0 2 * * * psql -d expecto_db -U expecto_user -c "SELECT calculate_daily_quality_metrics(CURRENT_DATE - 1);"

# Адаптивная настройка min_freq_for_stability (воскресенье в 1:00)
0 1 * * 0 psql -d expecto_db -U expecto_user -c "SELECT refresh_stability_threshold();"

# Очистка profile_comparison_log (в 3:00)
0 3 * * * psql -d expecto_db -U expecto_user -c "SELECT clean_profile_comparison_log();"

# Сбор пред-инцидентных профилей за предыдущий день (в 2:30)
30 2 * * * psql -d expecto_db -U expecto_user -c "SELECT collect_pre_incident_profiles(now() - interval '1 day', now(), 60);" > /postgres/pg_expecto/sh/collect_pre_incident.log 2>&1

# Очистка старых данных индикатора изменения профиля (в 2:00)
0 2 * * * psql -d expecto_db -U expecto_user -c "SELECT clean_old_profile_change_indicator(30);" > /postgres/pg_expecto/sh/clean_old_profile_change_indicator.log 2>&1
```

### 5. Первоначальное историческое обучение

Скопируйте скрипт `train_markov_chain2.sh` в рабочую директорию и сделайте его исполняемым:

```bash
chmod 750 train_markov_chain2.sh
```

Запустите обучение. Укажите период, за который есть исторические данные в `cluster_stat_median`:

```bash
./train_markov_chain2.sh --start "2024-01-01 00:00:00" --end "2024-01-31 23:59:59"
```

Если аргументы не указаны, обучение будет выполнено от самой ранней записи в `cluster_stat_median` до текущего момента UTC.

Во время выполнения скрипта выводится прогресс в консоль и в файл `/tmp/train_markov_chain2_progress.txt`.  
Рекомендуется отслеживать ход выполнения:

```bash
tail -f /tmp/train_markov_chain2_progress.txt
```

После завершения обучения будет сформирован итоговый протокол с оценкой качества модели.

---

## Проверка установки

- Проверьте, что таблицы созданы:
  ```bash
  psql -d expecto_db -U expecto_user -c "\dt"
  ```
- Проверьте, что функции доступны:
  ```bash
  psql -d expecto_db -U expecto_user -c "\df mchain_*" | head -20
  ```
- Выполните простой тестовый запрос (должен вернуть число, например, 0.5):
  ```sql
  SELECT mchain_predict_risk_current_horizon();
  ```
- Сгенерируйте сводный отчёт:
  ```sql
  SELECT unnest(generate_full_analytical_report());
  ```

---

## Дополнительные шаги (при необходимости)

- **Заполнение профилей и сравнений**  
  Если требуется заполнить исторические сравнения профилей (для последующей аналитики), выполните:
  ```sql
  SELECT fill_profile_comparison_historically();
  ```
  Эта функция использует параметры `training_start_time` и `training_end_time` из `markov_config`, которые устанавливаются во время обучения. Можно также передать явные даты.

- **Обновление конфигурации**  
  При необходимости измените параметры вручную:
  ```sql
  UPDATE markov_config SET forecast_horizon_minutes = 15, base_alpha = 0.1;
  ```

- **Ручное применение забывания**  
  ```sql
  SELECT mchain_apply_forgetting(0.1);  -- принудительно с alpha=0.1
  ```

---

## Устранение неполадок

- **Ошибка «relation "cluster_stat_median" does not exist»** – убедитесь, что таблица с историческими данными существует и содержит данные.
- **Функция `get_current_os_waiting_correlation_for_markov_chain` возвращает NULL** – проверьте, что в таблице `cluster_stat_median` есть данные за последний час.
- **Низкий рейтинг достоверности** – возможно, недостаточно данных или нестабильные вероятности. Увеличьте период обучения или настройте параметры забывания.
- **Логи ошибок** – просмотрите таблицу `mchain_error_log`:
  ```sql
  SELECT * FROM mchain_error_log ORDER BY ts DESC LIMIT 10;
  ```

---

## Контакты

Разработчик: **Ринат**  
Репозиторий: [https://github.com/pg-expecto/markov_chain/tree/main/v.16](https://github.com/pg-expecto/markov_chain/tree/main/v.16)

По всем вопросам обращайтесь через Issues на GitHub или по электронной почте.
