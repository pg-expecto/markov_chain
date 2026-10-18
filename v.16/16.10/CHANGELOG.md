# CHANGELOG

Все заметные изменения проекта `markov_chain`.

---

## [v3.1.1] — 2026-10-18 — документационный патч

### Изменено
- `generate_incident_forecast_report_v2` — только текст, без изменения логики:
  - Легенда: «часть покрытых инцидентов **имеет** `lead = 0`» →
    «**может иметь** `lead = 0`» (на практике `min lead = 8` мин, нулевых нет).
  - Легенда: «стартовал за **1-2 минуты**» → «стартовал за **несколько минут**»
    (при наблюдаемых `lead` 8, 23, 37 мин формулировка «1-2 минуты» неточна).
  - `COMMENT ON FUNCTION`: добавлено ожидаемое значение метрики
    «покрытие с lead >= 60 мин» — 88 % (22 из 25) на данных
    2026-09-18 … 2026-10-18.
- В шапке отчёта и в `COMMENT` версия `v3.1.0` → `v3.1.1`.

### Логика
- Не менялась. Приёмочные проверки v3.1.0 (test5) остаются в силе.

---

## [v3.1.0] — 2026-10-18

### Добавлено
- `incident_forecast_config.coverage_lead_threshold_min`
  (`INT NOT NULL DEFAULT 60`) — порог lead time для метрики
  «покрытие с учётом lead time».
- Раздел «ПОКРЫТИЕ С УЧЁТОМ LEAD TIME» в `generate_incident_forecast_report_v2`:
  - число инцидентов с `lead >= порога` (предсказано заранее);
  - число инцидентов с `lead < порога` (сигнал активен, но не предсказал);
  - предупреждение при доле < 50 %.

### Изменено
- Легенда отчёта: добавлено пояснение «покрыт ≠ предсказал заранее».
- Предупреждение о бимодальности lead time переработано:
  - сравниваются `old` и `fresh` lead (медианы);
  - если `Δ = |old - fresh| / old * 100 < 20 %` — выводится
    «ДЛИТЕЛЬНОЕ ПРЕДАВАРИЙНОЕ СОСТОЯНИЕ, а не latch-эффект SICPP»;
  - иначе — «LATCH-ЭФФЕКТ SICPP существенен»;
  - если `fresh` недоступен — отдельная ветка.

### Результаты (test5)
- Покрытие: 25/25 (100 %).
- С `lead >= 60` мин: 22/25 (**88 %**) — предсказано заранее.
- С `lead < 60` мин: 3/25 (ID 86, 94, 119; `lead` = 37, 8, 23 мин).
- При пороге 120 мин: 16/25 (64 %) — предсказано заранее.
- Precision эпизодов: 37.5 % (18 TP / 30 FP из 48 эпизодов).

### ⚠ ВАЖНО: горизонт прогноза изменён с 30 на 120 минут

В `markov_config.forecast_horizon_minutes` значение **`30` → `120`**
(изменение выполнено вне рамок этой миграции; фиксируется здесь
как факт, влияющий на сопоставимость исторических данных).

Влияние:
- `prediction_log.actual_outcome` обновляется на горизонте 120 мин
  (вместо 30).
- Калибровочная таблица в отчётах строится по
  `prediction_log.horizon_minutes = 120`.
- Показатели `ROC-AUC` и `Brier` **несопоставимы напрямую** с отчётами
  до изменения горизонта.

Сравнение с историческими данными (горизонт 30 мин, отчёт v1):
- `ROC-AUC`: 0.9540 (30) → 0.9568 (120) — рост +0.0028, незначим.
- `Brier`: 0.0644 (30) → 0.0652 (120) — рост +0.0008, стабильно.

Рекомендации:
- При каждом изменении `forecast_horizon_minutes` фиксировать его
  в этом файле с указанием старого/нового значения.
- В отчётах (`generate_incident_forecast_report_v2`) горизонт уже
  выводится в заголовке; при внешнем сравнении указывать оба значения.

---

## [v3.0.2] — 2026-10-18

### Исправлено
- `diagnose_incident_coverage`:
  - в CTE `history` добавлены `first_signal_time` и `signal_duration`:
    CTE `started` обращался к несуществующим полям
    `h.first_signal_time` / `h.signal_duration` → ошибка
    «столбец h.first_signal_time не существует».

---

## [v3.0.1] — 2026-10-18

### Исправлено
- `diagnose_incident_coverage`:
  - `format('%.3f', ...)` → `format('%s', ...)` с предварительным
    `round()`. PostgreSQL-функция `format()` не поддерживает
    `printf`-спецификаторы (`%.3f`), только `%s`, `%I`, `%L`, `%%`.
    Ошибка проявлялась как «нераспознанный спецификатор типа
    format(): "."».

---

## [v3.0.0] — 2026-10-18 — консолидация отчётности

### Добавлено
- `generate_incident_forecast_report_v2` v3.0.0 — единственная отчётная
  функция по прогнозированию инцидентов.
  - Источник сигнала — `sicpp_history` (вместо `calculate_signal`).
  - Episode-based coverage:
    `episode_start <= start_timepoint AND episode_end >= start_timepoint - window`.
  - Разделы: «ПОКРЫТИЕ ПО ПРИОРИТЕТАМ», «ТОЧНОСТЬ СИГНАЛА (PRECISION
    эпизодов)», «РАСПРЕДЕЛЕНИЕ LEAD TIME», «КРИТИЧЕСКИЕ АЛЕРТЫ
    (P3 без сигнала)».
  - Калибровка: `WIDTH_BUCKET(LEAST(predicted_risk, 0.999999), 0, 1, 10)`
    вместо `FLOOR(predicted_risk / 0.1) * 0.1` — устранён артефакт
    `[1.0-1.1]`.
  - Серийный фильтр: `v_last_status='INCIDENT' AND предыдущий инцидент
    не завершён`.
- DDL:
  - `sicpp_coverage_alerts` — алерты о P3 без сигнала SICPP.
  - `incident_forecast_config.series_filter_enabled` (BOOLEAN NOT NULL
    DEFAULT TRUE).
  - `incident_forecast_config.sicpp_coverage_warn_threshold_pct`
    (REAL DEFAULT 10.0).
- `diagnose_incident_coverage` v3.0.0 — диагностика покрытия инцидента.

### Изменено
- `diagnose_incident_coverage` — переработана под v3.0.0:
  `priority_filter`, `status_filter`, `series_filter`, episode-based
  coverage, `WEIGHTED score`.

### Удалено (deprecation)
- `generate_incident_forecast_report` (v1) →
  `_deprecated_generate_incident_forecast_report_v1`,
  заглушка с `RAISE WARNING`.
- `report_incidents_vs_sicpp` →
  `_deprecated_report_incidents_vs_sicpp`,
  заглушка с `RAISE WARNING`.

### Результаты (test3, test4)
- Покрытие: 25/25 (100 %) — было 22/25 (88 %) в v2.0.1;
  разница объясняется сменой семантики (episode-based coverage),
  а не «улучшением» модели.
- ROC-AUC: 0.9568; Brier: 0.0652.

---

## [предыдущие версии]

Изменения до v3.0.0 в этом файле не документированы. См. историю
git / резервные копии.
