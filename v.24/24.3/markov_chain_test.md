# Инструкция по запуску и сопровождению тестовой нагрузки цепи Маркова

> Версия документа: 1.2 (соответствует v24.3)
> СУБД: PostgreSQL. Схема/БД — `expecto_db`, пользователь — `expecto_user`.
>
> **Изменения в v1.2:**
> - Добавлен новый раздел **«0. Установка таблиц и хранимых функций цепи Маркова»** — последовательное применение `markov_chain_tables.sql`, `markov_chain_profile_tables.sql`, `performance_metrics_for_markov_chain.sql`, `markov_chain_functions.sql`, `markov_chain_profile_functions.sql` после установки pg_expecto.
> - Раздел «Предварительные проверки» перенесён в п. 1 и сокращён (часть проверок перешла в п. 0.4).
> - Остальные разделы переномерованы.
>
> **Изменения в v1.1 (сохранены):**
> - Удалён устаревший скрипт `baseload.sh`.
> - Уточнён механизм запуска `mchain_train_step()` — он вызывается **внутри** `performance_metrics()` (в `pg_expecto.sh`), а не отдельным cron-заданием.
> - Флаг `configuration.is_markov_chain_enabled` — единая точка включения/выключения обучения.

---

## 0. Установка таблиц и хранимых функций цепи Маркова

Выполняется **однократно**, сразу после установки и настройки pg_expecto по адресу:
<https://github.com/pg-expecto/pg_expecto/blob/main/pg_expecto_install.md>

### 0.1. Предварительные условия

- pg_expecto уже установлен и работает: в БД `expecto_db` присутствует `cluster_stat_median` и хотя бы одна запись:
  ```sql
  SELECT count(*) FROM cluster_stat_median;   -- > 0
  ```
- Пользователь `expecto_user` имеет права `CREATE TABLE` и `CREATE FUNCTION` в схеме `public` БД `expecto_db`.
- Расширения `pg_stat_statements` и `pg_wait_sampling` установлены (они уже нужны pg_expecto).
- SQL-файлы цепи Маркова скопированы на сервер, например в `/postgres/pg_expecto/sql/`.

### 0.2. Состав и порядок применения

| № | Файл | Назначение | Зависимости |
|---|---|---|---|
| 1 | `markov_chain_tables.sql` | Базовые таблицы модели: `markov_config`, `transition_log`, `markov_frequencies`, `markov_probabilities`, `markov_absorbing`, `state_descriptions`, `markov_chain`, `critical_states`, `prediction_log`, `mchain_quality_metrics_history`, `mchain_quality_errors`, `mchain_error_log`, `apply_forgetting_log`, `forgetting_optimization_log`, `mchain_train_progress_log`, `performance_history`, `markov_chain_performance_incident` | — |
| 2 | `markov_chain_profile_tables.sql` | Таблицы профилирования и сигналов: `profile_aggregated`, `profile_baseline`, `anomaly_log`, `incident_free_window_current`, `profile_comparison_log`, `pre_incident_profiles`, `pre_incident_match_log`, `incident_forecast_config`, `profile_change_indicator`, `sicpp_history`, `sicpp_current_state`, `sicpp_coverage_alerts`, `operational_alert_state`, `operational_alert_history`, `c_threshold_history`, `sicpp_threshold_history`, `c_only_incident_flag_history`, `sicpp_incident_flag_state`, `sicpp_incident_flag_history` | — |
| 3 | `performance_metrics_for_markov_chain.sql` | Функция `get_current_os_waiting_correlation_for_markov_chain()` — «мостик» от pg_expecto (`cluster_stat_median`) к модели | pg_expecto |
| 4 | `markov_chain_functions.sql` | Ядро модели: обучение (`mchain_train_step`, `mchain_apply_forgetting`, `mchain_initial_train_from_history`), логирование, прогноз (`collect_prediction`, `mchain_predict_risk_k_v2`, `mchain_predict_risk_k_v2_with_matrix`), отчёты, диагностика | п. 1–3 |
| 5 | `markov_chain_profile_functions.sql` | Профилирование (`calculate_profile_metrics`, `compare_profiles`, `save_baseline_profile`, `find_incident_free_window`, `is_valid_baseline_window`), SICPP (`sicpp_calculate_at`, `sicpp_update_state`, `historical_fill_sicpp`), C-only (`mchain_hybrid_alert_at`, `update_operational_alert_state`), флаги инцидентов (`sicpp_incident_flag_update_step`, `c_only_incident_flag_update_step`), адаптация порогов, аналитические отчёты | п. 1–4 |

**Порядок важен**, потому что:

- `markov_chain_functions.sql` содержит `mchain_train_step()`, который вызывает `get_current_os_waiting_correlation_for_markov_chain()` (из п. 3) и функции профилирования (из п. 5). PL/pgSQL ленив, но при первом выполнении все зависимости должны быть на месте.
- `performance_metrics_for_markov_chain.sql` требует установленного pg_expecto (обращается к `cluster_stat_median`). Функция не падает при создании без этой таблицы (внутри есть проверка `tbl_exists`), но фактически бесполезна до установки pg_expecto.

### 0.3. Команды установки

Перейдите в каталог с файлами и выполните (по одному):

```bash
cd /postgres/pg_expecto/sql/

psql -d expecto_db -U expecto_user -v ON_ERROR_STOP=1 -f markov_chain_tables.sql
psql -d expecto_db -U expecto_user -v ON_ERROR_STOP=1 -f markov_chain_profile_tables.sql
psql -d expecto_db -U expecto_user -v ON_ERROR_STOP=1 -f performance_metrics_for_markov_chain.sql
psql -d expecto_db -U expecto_user -v ON_ERROR_STOP=1 -f markov_chain_functions.sql
psql -d expecto_db -U expecto_user -v ON_ERROR_STOP=1 -f markov_chain_profile_functions.sql
```

Либо одной командой с проверкой кода возврата:

```bash
set -e
for f in markov_chain_tables.sql \
         markov_chain_profile_tables.sql \
         performance_metrics_for_markov_chain.sql \
         markov_chain_functions.sql \
         markov_chain_profile_functions.sql; do
  echo "=== Applying $f ==="
  psql -d expecto_db -U expecto_user -v ON_ERROR_STOP=1 -f "$f"
done
echo "=== All installed ==="
```

> ⚠ **Внимание — возможна потеря данных.**
> Файлы `markov_chain_tables.sql` и `markov_chain_profile_tables.sql` содержат `DROP TABLE IF EXISTS ...;` для ряда таблиц, включая `markov_config`, `transition_log`, `markov_frequencies`, `critical_states`, `prediction_log`, `performance_history`, `profile_aggregated`, `profile_baseline`, `profile_comparison_log`, `incident_forecast_config`, `sicpp_history` и др. Повторное применение **удалит все накопленные данные и настройки** этих таблиц. Используйте повторное применение только при «чистой» переустановке или полном переобучении. На «живой» системе сначала сделайте дамп:
> ```bash
> pg_dump -d expecto_db -U expecto_user \
>   -t 'markov_*' -t 'profile_*' -t 'sicpp_*' -t 'c_only_*' \
>   -t 'operational_*' -t 'critical_states' -t 'transition_log' \
>   -t 'prediction_log' -t 'performance_history' -t 'incident_forecast_config' \
>   > /backup/markov_before_upgrade.sql
> ```
> Функции объявлены через `CREATE OR REPLACE FUNCTION` — их повторное применение безопасно.

### 0.4. Проверка установки

1. **Таблицы созданы:**
   ```sql
   SELECT count(*) FROM information_schema.tables
   WHERE table_schema = 'public'
     AND table_name IN (
        'markov_config','incident_forecast_config','transition_log',
        'markov_frequencies','markov_probabilities','critical_states',
        'prediction_log','mchain_quality_metrics_history','performance_history',
        'markov_chain_performance_incident','state_descriptions','markov_absorbing',
        'profile_aggregated','profile_baseline','anomaly_log',
        'incident_free_window_current','profile_comparison_log',
        'pre_incident_profiles','profile_change_indicator',
        'sicpp_history','sicpp_current_state','operational_alert_state',
        'operational_alert_history','c_only_incident_flag_history',
        'sicpp_incident_flag_state','sicpp_incident_flag_history'
     );
   -- ожидается: 26
   ```

2. **Ключевые функции созданы:**
   ```sql
   SELECT proname FROM pg_proc
   WHERE proname IN (
     'mchain_train_step','mchain_apply_forgetting','mchain_initial_train_from_history',
     'get_current_os_waiting_correlation_for_markov_chain',
     'sicpp_update_state','sicpp_incident_flag_update_step',
     'c_only_incident_flag_update_step','compare_profiles',
     'update_operational_alert_state'
   )
   ORDER BY proname;
   -- ожидается 9 функций
   ```

3. **Singleton-строки в конфигурационных таблицах:**
   ```sql
   SELECT 'markov_config'            AS tbl, count(*) FROM markov_config
   UNION ALL
   SELECT 'incident_forecast_config',       count(*) FROM incident_forecast_config
   UNION ALL
   SELECT 'sicpp_current_state',            count(*) FROM sicpp_current_state
   UNION ALL
   SELECT 'operational_alert_state',        count(*) FROM operational_alert_state
   UNION ALL
   SELECT 'sicpp_incident_flag_state',      count(*) FROM sicpp_incident_flag_state;
   -- ожидается по 1 в каждой строке
   ```

4. **Справочник состояний заполнен:**
   ```sql
   SELECT count(*) FROM state_descriptions;   -- 189
   ```
   Если `0`, выполните:
   ```sql
   SELECT fill_state_descriptions();
   ```

5. **`critical_states` инициализирован seed-данными (≈23 записи из `markov_chain_tables.sql`):**
   ```sql
   SELECT count(*) FROM critical_states;      -- > 0
   ```

6. **«Мостик» от pg_expecto работает:**
   ```sql
   SELECT * FROM get_current_os_waiting_correlation_for_markov_chain();
   -- одна строка: (current_correlation, current_os_trend, current_wait_trend)
   ```

7. **Smoke-тест обучения (вручную, до настройки cron):**
   ```sql
   -- Сначала убедитесь, что обучение выключено, чтобы не мешать
   SELECT is_markov_chain_enabled();

   -- Заполнить справочник, если пуст
   SELECT fill_state_descriptions();

   -- Пробный шаг обучения на текущих метриках
   SELECT mchain_train_step();
   -- ожидается 'Step completed' (или 'No metrics available', если
   -- cluster_stat_median ещё не наполнялась)
   ```

8. **Проверка, что историческое обучение ещё не проводилось (таблицы пусты):**
   ```sql
   SELECT count(*) FROM transition_log;         -- 0
   SELECT count(*) FROM markov_frequencies;     -- 0
   SELECT count(*) FROM prediction_log;         -- 0
   ```
   Это ожидаемо: следующий шаг — п. 2 «Историческое заполнение данных».

---

## 1. Предварительные проверки перед запуском

После выполнения п. 0 убедитесь, что:

1. `markov_config` содержит ровно одну строку:
   ```sql
   SELECT * FROM markov_config;
   ```
2. `incident_forecast_config` содержит ровно одну строку:
   ```sql
   SELECT * FROM incident_forecast_config;
   ```
3. `configuration` содержит ровно одну строку, флаг обучения выставлен:
   ```sql
   SELECT * FROM configuration;
   -- на время исторического заполнения (п. 2) выставите FALSE:
   UPDATE configuration SET is_markov_chain_enabled = FALSE;
   -- после исторического заполнения — TRUE (см. п. 2.11)
   ```
4. Справочник состояний заполнен:
   ```sql
   SELECT count(*) FROM state_descriptions;   -- 189
   ```
   Если `0`, выполните `SELECT fill_state_descriptions();`.
5. Источник метрик `cluster_stat_median` доступен и содержит данные:
   ```sql
   SELECT MIN(curr_timestamp), MAX(curr_timestamp), count(*) FROM cluster_stat_median;
   ```

---

## 2. Историческое заполнение данных

Историческое заполнение выполняется **однократно** после развёртывания (или при полном переобучении) и **последовательно**, в указанном ниже порядке.

### 2.1. Зафиксировать период обучения в `markov_config`

```sql
UPDATE markov_config
SET training_start_time = '2026-06-01 00:00+03',
    training_end_time   = '2026-08-31 23:59+03';
```

### 2.2. Первичное обучение цепи (ядро)

```sql
CALL mchain_initial_train_from_history(
    p_end              => '2026-08-31 23:59+03',
    p_start            => '2026-06-01 00:00+03',
    p_refresh_critical => TRUE,
    p_risk_threshold   => 0.10,
    p_min_transitions  => 20,
    p_interval_min     => NULL
);
```

Проверка после шага:

```sql
SELECT count(*) FROM transition_log;
SELECT count(*) FROM markov_frequencies;
SELECT count(*) FROM prediction_log;
SELECT count(*) FROM critical_states;
SELECT mchain_forecast_reliability();
```

### 2.3. Пересчёт исходов прогнозов

```sql
SELECT update_prediction_outcomes();
```

### 2.4. Заполнение истории профильного сравнения

```sql
SELECT fill_profile_comparison_historically(
    p_start          => '2026-06-01 00:00+03',
    p_end            => '2026-08-31 23:59+03',
    p_step_minutes   => 5,
    p_window_minutes => 60,
    p_lookback_days  => 30,
    p_clean          => TRUE
);
```

### 2.5. Заполнение истории SICPP

```sql
SELECT historical_fill_sicpp(
    p_start        => '2026-06-01 00:00+03',
    p_end          => '2026-08-31 23:59+03',
    p_step_minutes => 1,
    p_clean        => TRUE
);
```

### 2.6. Заполнение истории C-only ALERT и флага `c_only_incident_flag`

```sql
SELECT historical_fill_c_only(
    p_start        => '2026-06-01 00:00+03',
    p_end          => '2026-08-31 23:59+03',
    p_step_minutes => 1,
    p_clean        => TRUE
);
```

### 2.7. Заполнение истории флага `sicpp_incident_flag`

```sql
SELECT sicpp_incident_flag_fill_from_history(
    p_start => '2026-06-01 00:00+03',
    p_end   => '2026-08-31 23:59+03',
    p_clean => TRUE
);
```

### 2.8. Заполнение `profile_change_indicator`

```sql
SELECT historical_fill_profile_change_indicator(
    p_start => '2026-06-01 00:00+03',
    p_end   => '2026-08-31 23:59+03'
);
```

### 2.9. Сбор пред-инцидентных профилей

```sql
SELECT collect_pre_incident_profiles(
    p_start          => '2026-06-01 00:00+03',
    p_end            => '2026-08-31 23:59+03',
    p_window_minutes => 60
);
```

### 2.10. Проверка корректности исторического заполнения

```sql
SELECT * FROM get_signals_valid_from();
SELECT unnest(operational_signals_report(
    '2026-06-01 00:00+03', '2026-08-31 23:59+03'));
SELECT mchain_quality_report('2026-06-01'::date, '2026-08-31'::date);
SELECT unnest(get_current_signals_status(30));
SELECT * FROM sicpp_verify_max_duration_enforcement(
    '2026-06-01 00:00+03', '2026-08-31 23:59+03');
```

### 2.11. Включить онлайн-обучение

После исторического заполнения разрешите `mchain_train_step()` вызываться из `performance_metrics()`:

```sql
UPDATE configuration SET is_markov_chain_enabled = TRUE;
SELECT is_markov_chain_enabled();
```

---

## 3. Настройка тестовой нагрузки

### 3.1. Скрипты тестового стенда

Скрипты расположены в `/postgres/pg_expecto/sh/`:

| Скрипт | Назначение | Рекомендуемое расписание |
|---|---|---|
| `pg_expecto.sh` | **Корневой сборщик метрик** (SQL-статистика, `cluster_stat_median`, vmstat, iostat) и **точка входа для обучения цепи** (через `performance_metrics()` → `mchain_train_step()`) | `*/1 * * * *` |
| `load_test.sh` | Сбор метрик под нагрузкой (pgbench-сессии, сценарии) | `*/1 * * * *` |
| `test.sh 4` | Генератор инцидентов (аварийная нагрузка) | `0 * * * *` (каждый час) |

> **Примечание.** Скрипт `baseload.sh` (постоянная фоновая нагрузка) в v24.3 **не используется** и в cron-расписании отсутствует. Фоновую нагрузку при необходимости моделируйте через `load_test.sh` или `pgbench` вручную.

### 3.2. Механизм вызова `mchain_train_step()`

**Важно:** `mchain_train_step()` **не вызывается отдельным cron-заданием**. Он исполняется внутри функции `performance_metrics()` (`pg_expecto.sql`), которая, в свою очередь, вызывается из корневого скрипта `pg_expecto.sh` **каждую минуту**.

Цепочка вызовов:

```
cron: */1 * * * *  →  /postgres/pg_expecto/sh/pg_expecto.sh
                        │
                        ├── statement_stat()              — сбор SQL-статистики
                        ├── cluster_stat_median()         — сбор метрик кластера
                        ├── performance_metrics()         — расчёт скор./ожид. + ВЫЗОВ mchain_train_step()
                        │     └── IF is_markov_chain_enabled() THEN
                        │           PERFORM mchain_train_step();
                        │         END IF;
                        ├── pg_stat_statements_reset()
                        ├── pg_wait_sampling_reset_profile()
                        ├── os_stat_vmstat(...)
                        ├── os_stat_iostat_device(...)
                        ├── cleaning()
                        └── [если включено] mchain_reliability_report() + get_current_signals_status()
```

Управление обучением — через флаг в таблице `configuration`:

```sql
-- Включить обучение цепи
UPDATE configuration SET is_markov_chain_enabled = TRUE;

-- Выключить (например, на время технического обслуживания)
UPDATE configuration SET is_markov_chain_enabled = FALSE;

-- Проверить текущее состояние
SELECT is_markov_chain_enabled();
```

Внутри `mchain_train_step()` уже выполняются:
1. Чтение метрик через `get_current_os_waiting_correlation_for_markov_chain()`.
2. Логирование перехода и обновление частот.
3. Забывание по интервалу.
4. Формирование прогноза (`collect_prediction()`).
5. Обновление `profile_change_indicator`, SICPP, `sicpp_incident_flag`, C-only ALERT, `c_only_incident_flag`.
6. Адаптация порогов (`adapt_c_thresholds()`, `adapt_sicpp_thresholds()`).
7. Дополнение `performance_history`.

### 3.3. Защита от параллельных запусков

Скрипт `pg_expecto.sh` использует lock-файл `/postgres/pg_expecto/PG_EXPECTO_IN_PROGRESS`. Если он существует — новый запуск пропускается (`exit 0`). Это исключает наложение минутных запусков.

```bash
# Проверить, не завис ли предыдущий запуск
ls -l /postgres/pg_expecto/PG_EXPECTO_IN_PROGRESS
# Если файл висит давно и мешает — удалить вручную:
rm -f /postgres/pg_expecto/PG_EXPECTO_IN_PROGRESS
```

> ⚠ Не запускайте `mchain_train_step()` вручную параллельно с `pg_expecto.sh` — это создаст гонки в `sicpp_incident_flag_update_step()` / `c_only_incident_flag_update_step()` (защита по `last_evaluated_minute` спасает от дублей, но лучше не создавать конфликтов).

### 3.4. Cron-задачи сопровождения

Полный набор — в `markov_chain_cron.txt`. Кратко:

| Группа | Задача | Расписание |
|---|---|---|
| [1] Нагрузка | `pg_expecto.sh` (включая `mchain_train_step()`) | `*/1 * * * *` |
| [1] Нагрузка | `load_test.sh` | `*/1 * * * *` |
| [1] Нагрузка | `test.sh 4` (генератор инцидентов) | `0 * * * *` |
| [2] Ядро | `mchain_clean_transition_log()` | `15 1 * * *` |
| [2] Ядро | `mchain_clean_apply_forgetting_log()` | `0 2 * * *` |
| [3] Качество | `refresh_critical_states(p_risk_threshold=>0.10)` | `0 3 * * *` |
| [3] Качество | `update_prediction_outcomes()` | `*/5 * * * *` |
| [3] Качество | `calculate_daily_quality_metrics(CURRENT_DATE - 1)` | `0 2 * * *` |
| [3] Качество | `refresh_stability_threshold()` | `0 1 * * 0` |
| [4] Профили | `clean_profile_comparison_log()` | `0 3 * * *` |
| [4] Профили | `collect_pre_incident_profiles(now()-1d, now(), 60)` | `30 2 * * *` |
| [4] Профили | `clean_old_profile_change_indicator(30)` | `0 2 * * *` |
| [5] SICPP | `sicpp_clean_history(90)` | `0 4 * * 0` |
| [5] SICPP | `DELETE FROM operational_alert_history … 90 days` | `30 2 * * *` |
| [6] Флаги | `clean_c_only_incident_flag_history(90)` | `30 2 * * *` |
| [6] Флаги | `clean_sicpp_incident_flag_history(90)` | `30 3 * * *` |

### 3.5. Проверка работоспособности в процессе нагрузки

```sql
-- Здоровье модели
SELECT * FROM mchain_health_check();

-- Обучение включено?
SELECT is_markov_chain_enabled();

-- Идут ли переходы (метрики поступают)?
SELECT count(*) FROM transition_log WHERE ts > now() - interval '10 min';

-- Последний запуск performance_metrics / mchain_train_step фиксируется в cluster_stat_median
SELECT max(curr_timestamp) FROM cluster_stat_median;

-- Текущие сигналы
SELECT get_current_signals_text();
SELECT unnest(get_current_signals_status(7));

-- Cooldown SICPP
SELECT * FROM sicpp_cooldown_status();

-- Прединцидентный статус (0 / 50 / 100)
SELECT get_current_preincident_status();
```

### 3.6. Изменение параметров нагрузки

Пороговые значения сигналов хранятся в `incident_forecast_config`:

```sql
-- Переход на «Вариант C» (C-only, auto_threshold = FALSE)
UPDATE incident_forecast_config
SET js_threshold = 0.15,
    risk_threshold = 0.85,
    auto_threshold = FALSE,
    hybrid_js_min_threshold = 0.14,
    hybrid_p90_min_threshold = 0.98,
    hybrid_w_score_min_threshold = 0.0,
    hybrid_window_minutes = 20,
    hybrid_include_a = FALSE,
    hybrid_include_b = FALSE;

-- Пересобрать историю сигналов после смены порогов:
SELECT historical_fill_sicpp('<p_start>', '<p_end>', 1, TRUE);
SELECT historical_fill_c_only('<p_start>', '<p_end>', 1, TRUE);
SELECT sicpp_incident_flag_fill_from_history('<p_start>', '<p_end>', TRUE);
```

При изменении `markov_config.base_alpha`, `incident_half_life_days`, `min_alpha`, `interval_minute`, `forecast_horizon_minutes` срабатывает триггер `trg_recalculate_risks_on_config_change` → `recalculate_prediction_risks()`.

---

## 4. Формирование отчётов для анализа текущих результатов

Все отчёты возвращают `TEXT` или `TEXT[]`. Сохранение в файл:

```bash
psql -d expecto_db -U expecto_user -At \
  -c "SELECT unnest(generate_full_analytical_report())" \
  > /tmp/full_report_$(date +%Y%m%d_%H%M).txt
```

### 4.1. Экспресс-проверка (ежедневно)

```sql
SELECT mchain_summary_report(now() - interval '7 days', now());
SELECT * FROM mchain_health_check();
SELECT unnest(get_current_signals_status(7));
SELECT get_current_signals_text();
```

### 4.2. Качество прогнозов (ежедневно / еженедельно)

```sql
SELECT mchain_quality_report('2026-10-01'::date, '2026-10-31'::date);
SELECT * FROM report_quality_sliding(30, 1);
SELECT unnest(report_daily_calibration('2026-10-31'::date));
SELECT unnest(report_prediction_incident_summary(now() - interval '7 days', now()));
```

### 4.3. Анализ сигналов (еженедельно / по запросу)

```sql
SELECT unnest(signals_report(now() - interval '7 days', now()));
SELECT unnest(signals_false_positive_report(now() - interval '7 days', now(), 30));
SELECT unnest(operational_signals_report(now() - interval '30 days', now()));
SELECT unnest(generate_incident_forecast_report_v2(
    now() - interval '7 days', now(), TRUE));
SELECT unnest(diagnose_incident_coverage(<incident_id>));
```

### 4.4. Анализ профилей нагрузки

```sql
SELECT unnest(generate_profile_comparison_report(
    now() - interval '30 days', now()));
SELECT unnest(generate_profile_incident_analytics_report(
    now() - interval '30 days', now()));
SELECT unnest(generate_profile_summary_report());
SELECT unnest(generate_detailed_profile_report());
```

### 4.5. Сводные аналитические отчёты

```sql
SELECT unnest(generate_full_analytical_report(
    CURRENT_DATE - 7, CURRENT_DATE - 1));
SELECT unnest(generate_comprehensive_analytical_report(
    now() - interval '30 days', now()));
SELECT unnest(generate_analytical_report(
    '2026-10-01 00:00', '2026-10-31 00:00'));
```

### 4.6. Стабильность и забывание

```sql
SELECT report_stability_trend(30);
SELECT * FROM report_forgetting_effectiveness();
SELECT * FROM state_distribution(7);
```

### 4.7. Матрица переходов и критические состояния

```sql
SELECT mchain_state_transition_matrix_report(TRUE, TRUE);
SELECT mchain_incident_transitions_report(now() - interval '7 days', now());
SELECT mchain_incident_state_detail_report(now() - interval '7 days', now());
```

### 4.8. Сводная таблица видов отчётов

| Отчёт | Периодичность | Кому |
|---|---|---|
| `mchain_health_check()` | ежечасно | дежурный |
| `mchain_summary_report` | ежедневно | дежурный/аналитик |
| `get_current_signals_status()` | ежечасно | дежурный |
| `mchain_quality_report` | еженедельно | аналитик |
| `signals_report` / `signals_false_positive_report` | еженедельно | аналитик |
| `generate_incident_forecast_report_v2` | еженедельно | аналитик |
| `operational_signals_report` | ежемесячно | аналитик |
| `generate_full_analytical_report` | ежемесячно/по запросу | руководитель |
| `report_stability_trend` | еженедельно | инженер модели |
| `sicpp_verify_max_duration_enforcement` | по запросу | инженер модели |

---

## 5. Типовые проблемы и действия

| Симптом | Вероятная причина | Что делать |
|---|---|---|
| `mchain_health_check()` = `CRITICAL` «Нет переходов за 10 мин» | `pg_expecto.sh` не вызывается / `is_markov_chain_enabled = FALSE` | проверить cron, `SELECT is_markov_chain_enabled();`, `SELECT count(*) FROM transition_log WHERE ts > now() - interval '10 min';` |
| «Модель не обучена (рейтинг 0)» | `transition_log` пуст | запустить `mchain_initial_train_from_history(...)` (п. 2.2) |
| Lock-файл `/postgres/pg_expecto/PG_EXPECTO_IN_PROGRESS` висит давно | предыдущий запуск `pg_expecto.sh` не завершился | проверить лог `/postgres/pg_expecto/pg_expecto.log`; при необходимости `rm -f PG_EXPECTO_IN_PROGRESS` |
| `SICPP skipped: inside incident` повторяется | инцидент не закрыт | `UPDATE markov_chain_performance_incident SET finish_timepoint = now() WHERE finish_timepoint IS NULL;` |
| `BLIND_ZONE` в `get_c_only_incident_flag_status()` дольше 2 минут | C-only активен, но `flag=FALSE` | убедиться, что `mchain_train_step()` отрабатывает (см. `SELECT is_markov_chain_enabled();`) |
| `critical_states` пуст | не выполнен `refresh_critical_states()` | `SELECT refresh_critical_states(p_risk_threshold => 0.10, p_dry_run => FALSE, p_audit => TRUE);` |
| `mchain_quality_report` возвращает «Нет завершённых прогнозов» | `update_prediction_outcomes()` не отработал | `SELECT update_prediction_outcomes();` |
| «Индекс покрытия SICPP низкий» | `historical_fill_sicpp()` не выполнялся | выполнить `historical_fill_sicpp(...)` (п. 2.5) |
| `last_seen` в `markov_chain` не обновляется | `mchain_train_step()` не вызывается из `performance_metrics()` | `SELECT * FROM configuration;` — проверить `is_markov_chain_enabled` |
| `function get_current_os_waiting_correlation_for_markov_chain() does not exist` | не применён `performance_metrics_for_markov_chain.sql` (п. 0.2) | применить файл по п. 0.3 |
| `relation "cluster_stat_median" does not exist` в `get_current_os_waiting_correlation_for_markov_chain` | pg_expecto не установлен | установить pg_expecto по инструкции, затем повторить п. 0.3 |

---

## 6. Чек-лист запуска (для оператора)

1. ☐ Установлен pg_expecto (`cluster_stat_median` существует, содержит записи).
2. ☐ Применены SQL-файлы цепи Маркова в порядке из п. 0.3:
   - ☐ `markov_chain_tables.sql`
   - ☐ `markov_chain_profile_tables.sql`
   - ☐ `performance_metrics_for_markov_chain.sql`
   - ☐ `markov_chain_functions.sql`
   - ☐ `markov_chain_profile_functions.sql`
3. ☐ Проверки установки из п. 0.4 пройдены (таблицы, функции, singleton-строки, `state_descriptions`).
4. ☐ Проверить `markov_config` (1 строка, `training_start_time` / `training_end_time` заполнены).
5. ☐ Проверить `incident_forecast_config` (1 строка).
6. ☐ Выставить `configuration.is_markov_chain_enabled = FALSE` на время исторического заполнения.
7. ☐ `SELECT fill_state_descriptions();` (если `state_descriptions` пуст).
8. ☐ `CALL mchain_initial_train_from_history(...);` (однократно).
9. ☐ `SELECT fill_profile_comparison_historically(...);`.
10. ☐ `SELECT historical_fill_sicpp(...);`.
11. ☐ `SELECT historical_fill_c_only(...);`.
12. ☐ `SELECT sicpp_incident_flag_fill_from_history(...);`.
13. ☐ `SELECT historical_fill_profile_change_indicator(...);`.
14. ☐ `SELECT collect_pre_incident_profiles(...);`.
15. ☐ `SELECT * FROM mchain_health_check();` → OK/WARNING.
16. ☐ Выставить `configuration.is_markov_chain_enabled = TRUE`.
17. ☐ Включить cron:
    - ☐ `*/1 * * * * /postgres/pg_expecto/sh/pg_expecto.sh` — **основной драйвер** (включает `mchain_train_step()` при `is_markov_chain_enabled = TRUE`);
    - ☐ `*/1 * * * * /postgres/pg_expecto/sh/load_test/load_test.sh` — нагрузка + метрики;
    - ☐ `0 * * * * /postgres/pg_expecto/sh/load_test/test.sh 4` — генератор инцидентов;
    - ☐ задачи сопровождения из п. 3.4.
18. ☐ Ежедневно смотреть `mchain_summary_report` + `mchain_health_check`.
19. ☐ Еженедельно — `mchain_quality_report`, `signals_report`, `signals_false_positive_report`.
20. ☐ Ежемесячно — `generate_full_analytical_report` и `operational_signals_report`.

---

## 7. Приложение: единый скрипт установки + исторического заполнения

```bash
#!/bin/bash
# install_and_train.sh — установка цепи Маркова после pg_expecto
set -e

SQL_DIR=/postgres/pg_expecto/sql
DB=expecto_db
USER=expecto_user

echo "=== 1. Установка SQL-файлов цепи Маркова ==="
for f in markov_chain_tables.sql \
         markov_chain_profile_tables.sql \
         performance_metrics_for_markov_chain.sql \
         markov_chain_functions.sql \
         markov_chain_profile_functions.sql; do
  echo "--- Applying $f ---"
  psql -d "$DB" -U "$USER" -v ON_ERROR_STOP=1 -f "$SQL_DIR/$f"
done

echo "=== 2. Заполнение справочника состояний ==="
psql -d "$DB" -U "$USER" -v ON_ERROR_STOP=1 -c \
  "SELECT fill_state_descriptions();"

echo "=== 3. Историческое заполнение ==="
# Уточните даты под ваш исторический диапазон
psql -d "$DB" -U "$USER" -v ON_ERROR_STOP=1 <<'SQL'
UPDATE configuration SET is_markov_chain_enabled = FALSE;

UPDATE markov_config
SET training_start_time = '2026-06-01 00:00+03',
    training_end_time   = '2026-08-31 23:59+03';

CALL mchain_initial_train_from_history(
    p_end              => '2026-08-31 23:59+03',
    p_start            => '2026-06-01 00:00+03',
    p_refresh_critical => TRUE,
    p_risk_threshold   => 0.10,
    p_min_transitions  => 20,
    p_interval_min     => NULL
);

SELECT update_prediction_outcomes();

SELECT fill_profile_comparison_historically(
    '2026-06-01 00:00+03', '2026-08-31 23:59+03', 5, 60, 30, TRUE);

SELECT historical_fill_sicpp(
    '2026-06-01 00:00+03', '2026-08-31 23:59+03', 1, TRUE);

SELECT historical_fill_c_only(
    '2026-06-01 00:00+03', '2026-08-31 23:59+03', 1, TRUE);

SELECT sicpp_incident_flag_fill_from_history(
    '2026-06-01 00:00+03', '2026-08-31 23:59+03', TRUE);

SELECT historical_fill_profile_change_indicator(
    '2026-06-01 00:00+03', '2026-08-31 23:59+03');

SELECT collect_pre_incident_profiles(
    '2026-06-01 00:00+03', '2026-08-31 23:59+03', 60);

UPDATE configuration SET is_markov_chain_enabled = TRUE;
SQL

echo "=== 4. Итоговая проверка ==="
psql -d "$DB" -U "$USER" -v ON_ERROR_STOP=1 <<'SQL'
SELECT * FROM mchain_health_check();
SELECT * FROM get_signals_valid_from();
SELECT is_markov_chain_enabled();
SQL

echo "=== Готово. Не забудьте включить cron из п. 3.4. ==="
```

---

*Документ подготовлен на основе реализации v24.3. При обновлении схемы, сигнатур функций, состава тестовых скриптов или порядка применения SQL-файлов — обновляйте настоящую инструкцию.*