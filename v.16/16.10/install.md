# Инструкция по инсталляции цепи Маркова

## 1. Предварительные требования

- PostgreSQL 13+
- Установленная БД `expecto_db`, пользователь `expecto_user` с правами на создание объектов.
- Таблица `cluster_stat_median` с полями `curr_timestamp`, `curr_op_speed`, `curr_waitings` — источник метрик производительности.
- Таблица `performance_incident` с полями `id`, `start_timepoint`, `finish_timepoint`, `priority` — источник инцидентов.
- Таблица `configuration` с флагом `is_markov_chain_enabled BOOLEAN` — управляет вызовом `mchain_train_step()` из приложения.
- Каталог `/postgres/pg_expecto/sh` для скриптов и логов.

---

## 2. Подготовка файлов

```bash
cd /postgres/pg_expecto/sh

# Просмотреть/отредактировать при необходимости
vi markov_chain_tables.sql
vi markov_chain_profile_tables.sql
vi markov_chain_functions.sql
vi markov_chain_profile_functions.sql
vi performance_metrics_for_markov_chain.sql
```

---

## 3. Создание схемы БД

Файлы загружаются строго в указанном порядке (зависимости по типам и функциям):

```bash
cd /postgres/pg_expecto/sh

psql -d expecto_db -U expecto_user -v ON_ERROR_STOP=on --echo-errors \
     -f markov_chain_tables.sql            > markov_chain_tables.log 2>&1

psql -d expecto_db -U expecto_user -v ON_ERROR_STOP=on --echo-errors \
     -f markov_chain_profile_tables.sql    > markov_chain_profile_tables.log 2>&1

psql -d expecto_db -U expecto_user -v ON_ERROR_STOP=on --echo-errors \
     -f markov_chain_functions.sql         > markov_chain_functions.log 2>&1

psql -d expecto_db -U expecto_user -v ON_ERROR_STOP=on --echo-errors \
     -f markov_chain_profile_functions.sql > markov_chain_profile_functions.log 2>&1

psql -d expecto_db -U expecto_user -v ON_ERROR_STOP=on --echo-errors \
     -f performance_metrics_for_markov_chain.sql > performance_metrics_for_markov_chain.log 2>&1
```

Проверить логи на ошибки:

```bash
grep -i "error" markov_chain_tables.log markov_chain_profile_tables.log \
     markov_chain_functions.log markov_chain_profile_functions.log \
     performance_metrics_for_markov_chain.log || echo "OK"
```

---

## 4. Настройка конфигурации

### 4.1. Параметры отчёта по прогнозированию

```bash
psql -d expecto_db -U expecto_user -c "
UPDATE incident_forecast_config
   SET signal_mode     = 'WEIGHTED',
       weight_js       = 0.9,
       weight_risk     = 0.1,
       extended_report = TRUE
"
```

### 4.2. Включение цепи Маркова в приложении

```bash
psql -d expecto_db -U expecto_user -c "
UPDATE configuration SET is_markov_chain_enabled = TRUE
"
```

> **Важно.** Если приложение НЕ вызывает `mchain_train_step()` автоматически (проверьте флаг `configuration.is_markov_chain_enabled`), добавьте вызов в cron (см. §6, закомментированная строка).

### 4.3. Параметры забывания (рекомендуемые значения)

Проверить и при необходимости скорректировать:

```sql
SELECT alpha, interval_minute, adaptive_forgetting_enabled, use_adaptive_alpha,
       base_alpha, min_alpha, incident_half_life_days,
       min_transitions_for_forgetting, forecast_horizon_minutes, min_freq_for_stability
FROM markov_config;
```

Рекомендуемые значения для тестовой СУБД (уже установлены по умолчанию):

| Параметр | Значение |
|---|---|
| `alpha` | 0.1 |
| `interval_minute` | 360 |
| `adaptive_forgetting_enabled` | true |
| `use_adaptive_alpha` | true |
| `base_alpha` | 0.05 |
| `min_alpha` | 0.001 |
| `incident_half_life_days` | 30 |
| `min_transitions_for_forgetting` | 5000 |
| `forecast_horizon_minutes` | 10 |
| `min_freq_for_stability` | 300 |

---

## 5. Первоначальное заполнение данных

### 5.1. Определение периода обучения

Установить границы периода в `markov_config` (используется функциями `fill_profile_comparison_historically`, `historical_fill_sicpp`):

```sql
UPDATE markov_config
   SET training_start_time = (SELECT MIN(curr_timestamp) FROM cluster_stat_median),
       training_end_time   = (SELECT MAX(curr_timestamp) FROM cluster_stat_median);
```

### 5.2. Историческое обучение цепи Маркова

Используется скрипт `train_markov_chain2.sh` (обёртка над `mchain_initial_train_from_history` / `mchain_train_historical`):

```bash
cd /postgres/pg_expecto/sh
vi train_markov_chain2.sh
chmod 750 train_markov_chain2.sh

./train_markov_chain2.sh >/tmp/train_markov_chain2_progress.txt 2>train_markov_chain2.log
```

Скрипт последовательно:

1. Заполняет `performance_history` (`fill_performance_history`).
2. Очищает таблицы модели и запускает `mchain_initial_train_from_history` (или `mchain_train_historical`).
3. Обновляет `critical_states` (`refresh_critical_states`).
4. Пересчитывает исходы прогнозов (`update_prediction_outcomes`).

Прогресс пишется в `mchain_train_progress_log` и в `train_markov_chain2.log`.

### 5.3. Историческое заполнение сравнений профилей

```bash
psql -d expecto_db -U expecto_user -c "
SELECT fill_profile_comparison_historically()
" > /tmp/fill_profile_comparison_historically.txt 2>&1

cat /tmp/fill_profile_comparison_historically.txt
```

### 5.4. Историческое заполнение SICPP

Требуется для работы `generate_incident_forecast_report_v2()` и `report_incidents_vs_sicpp()`:

```bash
psql -d expecto_db -U expecto_user -c "
SELECT historical_fill_sicpp(
    (SELECT training_start_time FROM markov_config),
    (SELECT training_end_time   FROM markov_config),
    1, TRUE)
" > /tmp/historical_fill_sicpp.txt 2>&1

cat /tmp/historical_fill_sicpp.txt
```

В конце функция выводит верификацию: сколько инцидентов покрыто сигналом SICPP.

---

## 6. Настройка cron

Открыть crontab:

```bash
crontab -e
```

Вставить содержимое обновлённого `markov_chain_cron.txt` (см. §8). Затем перезагрузить cron (обычно не требуется):

```bash
systemctl reload cron    # или: service cron reload
```

---

## 7. Контроль и проверка

### 7.1. Логи

```bash
cd /postgres/pg_expecto/sh
tail -f pg_expecto.log
tail -f markov_chain.log
```

### 7.2. Проверка состояния модели

```sql
-- Здоровье цепи
SELECT * FROM mchain_health_check();

-- Текущее состояние SICPP
SELECT * FROM sicpp_get_current();

-- Последние переходы
SELECT * FROM transition_log ORDER BY ts DESC LIMIT 10;

-- Критические состояния
SELECT * FROM get_critical_states();

-- Активные P3-алерты
SELECT * FROM get_active_p3_alerts();
```

### 7.3. Отчёты

```sql
-- Сводный отчёт по цепи Маркова
SELECT unnest(generate_full_analytical_report()) AS line;

-- Отчёт по прогнозированию (v1, на основе calculate_signal)
SELECT unnest(generate_incident_forecast_report(now() - INTERVAL '30 days', now())) AS line;

-- Отчёт по прогнозированию (v2, на основе sicpp_history)
SELECT unnest(generate_incident_forecast_report_v2(now() - INTERVAL '30 days', now())) AS line;

-- Сравнительный анализ инцидентов и SICPP
SELECT unnest(report_incidents_vs_sicpp(now() - INTERVAL '30 days', now(), TRUE)) AS line;

-- Качество прогнозов
SELECT mchain_quality_report(now() - INTERVAL '30 days', now(), NULL);
```

### 7.4. Сохранение отчётов в файлы

```bash
psql -d expecto_db -U expecto_user -c "
SELECT unnest(generate_incident_forecast_report(now() - INTERVAL '30 days', now()))
" > /tmp/generate_incident_forecast_report.txt

psql -d expecto_db -U expecto_user -c "
SELECT unnest(report_incidents_vs_sicpp(now() - INTERVAL '30 days', now(), TRUE))
" > /tmp/report_incidents_vs_sicpp.txt
```

---

## 8. Обновлённый `markov_chain_cron.txt`

Ниже — актуальная версия с добавленными функциями (`sicpp_clean_history`, опциональный `mchain_train_step`) и без устаревших записей.

```cron
#################################################################
# Markov chain
# 16.9
# ============================================================
# Ежедневная очистка журналов и обновление статистик
# ============================================================
# Очистка transition_log (в 01:15)
15 1 * * * psql -d expecto_db -U expecto_user -c "SELECT mchain_clean_transition_log();"

# ============================================================
# Очистка архивных данных (раз в неделю)
# ============================================================
# Очистка apply_forgetting_log (ежедневно в 02:00)
0 2 * * * psql -d expecto_db -U expecto_user -c "SELECT mchain_clean_apply_forgetting_log();"

# ============================================================
# Анализ качества прогноза
# ============================================================
# Обновление critical_states еженедельно (суббота в 03:00)
0 3 * * 6 psql -d expecto_db -U expecto_user -c "SELECT refresh_critical_states(p_risk_threshold => 0.10, p_dry_run => FALSE, p_audit => TRUE);" >/postgres/pg_expecto/sh/refresh_critical_states.log 2>&1

# Обновление исходов каждые 5 минут
*/5 * * * * psql -d expecto_db -U expecto_user -c "SELECT update_prediction_outcomes();"

# Расчёт суточных метрик в 02:00
0 2 * * * psql -d expecto_db -U expecto_user -c "SELECT calculate_daily_quality_metrics(CURRENT_DATE - 1);"

# Еженедельная адаптивная настройка min_freq_for_stability (воскресенье в 01:00)
0 1 * * 0 psql -d expecto_db -U expecto_user -c "SELECT refresh_stability_threshold();"

#################################################################################################
# Расчет метрик профиля нагрузки на основе цепи Маркова
# Ежедневная очистка (в 03:00)
0 3 * * * psql -d expecto_db -U expecto_user -c "SELECT clean_profile_comparison_log();"

# Ежедневно в 02:30 добавляем профили для инцидентов за предыдущий день
30 2 * * * psql -d expecto_db -U expecto_user -c "SELECT collect_pre_incident_profiles(now() - interval '1 day', now(), 60);" > /postgres/pg_expecto/sh/collect_pre_incident.log 2>&1

# Очистка старых данных индикатора изменения профиля (каждый день в 2:00)
0 2 * * * psql -d expecto_db -U expecto_user -c "SELECT clean_old_profile_change_indicator(30);" > /postgres/pg_expecto/sh/clean_old_profile_change_indicator.log 2>&1

# Расчет метрик профиля нагрузки на основе цепи Маркова
#################################################################################################

# ============================================================
# SICPP (Signal Indicating a Change in the Performance Profile)
# ============================================================
# Еженедельная очистка истории SICPP (воскресенье в 04:00)
0 4 * * 0 psql -d expecto_db -U expecto_user -c "SELECT sicpp_clean_history(90);" >/postgres/pg_expecto/sh/sicpp_clean_history.log 2>&1

# Ежечасная проверка P3-покрытия (алерты записываются в sicpp_coverage_alerts)
0 * * * * psql -d expecto_db -U expecto_user -c "SELECT * FROM check_p3_coverage_gaps(now() - interval '7 days', now(), TRUE);" >/postgres/pg_expecto/sh/check_p3_coverage_gaps.log 2>&1

# ============================================================
# Основной шаг обучения цепи Маркова
# ============================================================
# ВНИМАНИЕ: mchain_train_step() вызывается приложением автоматически,
# если в таблице configuration установлен флаг is_markov_chain_enabled = TRUE.
# Если приложение НЕ выполняет этот вызов — раскомментируйте строку ниже:
# * * * * * psql -d expecto_db -U expecto_user -c "SELECT mchain_train_step();" >> /postgres/pg_expecto/sh/mchain_train_step.log 2>&1

# Markov chain
#################################################################
```

### Что изменилось по сравнению с предыдущей версией

| Действие | Функция | Комментарий |
|---|---|---|
| **Добавлено** | `sicpp_clean_history(90)` | Еженедельная очистка `sicpp_history` (новая в v1.0.0) |
| **Добавлено** | `check_p3_coverage_gaps(...)` с редиректом в лог | Ранее была без лога |
| **Добавлено** | Комментарий про `mchain_train_step()` | Опциональный вызов, если приложение не делает это само |
| **Сохранено** | `mchain_clean_transition_log()` | Без изменений |
| **Сохранено** | `mchain_clean_apply_forgetting_log()` | Без изменений |
| **Сохранено** | `refresh_critical_states(p_risk_threshold => 0.10, ...)` | Явно зафиксирован рекомендованный порог 0.10 |
| **Сохранено** | `update_prediction_outcomes()` | Без изменений |
| **Сохранено** | `calculate_daily_quality_metrics(CURRENT_DATE - 1)` | Без изменений |
| **Сохранено** | `refresh_stability_threshold()` | Без изменений |
| **Сохранено** | `clean_profile_comparison_log()` | Без изменений |
| **Сохранено** | `collect_pre_incident_profiles(...)` | Без изменений |
| **Сохранено** | `clean_old_profile_change_indicator(30)` | Без изменений |

> **Устаревших функций в cron не обнаружено** — все перечисленные функции присутствуют в текущей версии SQL-модулей. Единственное добавление — `sicpp_clean_history` (появилась в v1.0.0).

---

## 9. Быстрая проверка после установки

```bash
# 1. Все таблицы созданы
psql -d expecto_db -U expecto_user -c "\dt" | grep -E "markov|profile|sicpp|prediction|critical|performance_history"

# 2. Ключевые функции доступны
psql -d expecto_db -U expecto_user -c "\df mchain_train_step"
psql -d expecto_db -U expecto_user -c "\df sicpp_update_state"
psql -d expecto_db -U expecto_user -c "\df report_incidents_vs_sicpp"

# 3. Модель обучена (должно быть > 0)
psql -d expecto_db -U expecto_user -c "SELECT COUNT(*) FROM transition_log"
psql -d expecto_db -U expecto_user -c "SELECT COUNT(*) FROM prediction_log"

# 4. SICPP инициализирован
psql -d expecto_db -U expecto_user -c "SELECT * FROM sicpp_get_current()"

# 5. Health-check
psql -d expecto_db -U expecto_user -c "SELECT * FROM mchain_health_check()"
```

Ожидаемый результат: `mchain_health_check().status` ∈ `{OK, WARNING}` (CRITICAL — только при отсутствии переходов за 10 минут или при рейтинге достоверности 0).
