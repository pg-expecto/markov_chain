-- pg_hazel_markov_chain_functions.sql
-- Переопределенные функции для pg_hazel_markov_chain_functions
/*
-- Процедура: mchain_initial_train_from_history (модифицированная)
-- Назначение: первоначальное обучение цепи Маркова на основе исторических данных
--             из таблицы pgh_stat_cluster_analysis. Очищает все таблицы модели
--             (кроме markov_config), последовательно обрабатывает минуты с
--             доступными данными, логирует переходы, пересчитывает вероятности
--             и обновляет список критических состояний с учётом инцидентов
--             из performance_incident.

-- Функция: mchain_train_historical(end_time TIMESTAMPTZ)
-- Назначение: выполняет полное историческое обучение цепи Маркова
--             от минимальной даты в pgh_stat_cluster_analysis до end_time.
--             Логирует прогресс каждый час.

-- Функция: fill_performance_history
-- Назначение: заполнить performance_history за указанный период

-- Функция: append_performance_history
-- Назначение: Инкрементально добавляет или обновляет записи в performance_history за указанный период (без TRUNCATE). Использует cluster_stat_median как источник.

-- Функция: refresh_performance_history
-- Назначение: Дополнить таблицу performance_history


*/



-- =============================================================================
-- Процедура: mchain_initial_train_from_history (модифицированная)
-- Назначение: первоначальное обучение цепи Маркова на основе исторических данных
--             из таблицы pgh_stat_cluster_analysis. Очищает все таблицы модели
--             (кроме markov_config), последовательно обрабатывает минуты с
--             доступными данными, логирует переходы, пересчитывает вероятности
--             и обновляет список критических состояний с учётом инцидентов
--             из performance_incident.
-- Параметры:
--   p_end                TIMESTAMPTZ – конечная точка обучения (включительно). 
--                                      Начало определяется как MIN(curr_timestamp)
--                                      из pgh_stat_cluster_analysis.
--   p_refresh_critical   BOOLEAN     – обновлять ли critical_states после обучения
--                                      (по умолчанию TRUE)
--   p_risk_threshold     REAL        – порог риска для включения в critical_states
--                                      (по умолчанию 0.10)
--   p_min_transitions    INT         – минимальное число переходов для анализа
--                                      (по умолчанию 50)
--   p_interval_min       INT         – интервал прогноза в минутах для эмпирического
--                                      риска (по умолчанию 15)
-- Возвращает:
--   TEXT – отчёт о выполненной работе.
-- =============================================================================
-- =============================================================================
-- Процедура: mchain_initial_train_from_history
-- (с периодическим COMMIT, прогрессом и подавлением NOTICE о временных таблицах)
-- =============================================================================
CREATE OR REPLACE PROCEDURE mchain_initial_train_from_history(
    IN p_end                TIMESTAMPTZ,
    IN p_refresh_critical   BOOLEAN DEFAULT TRUE,
    IN p_risk_threshold     REAL    DEFAULT 0.10,
    IN p_min_transitions    INT     DEFAULT 50,
    IN p_interval_min       INT     DEFAULT 15,
    INOUT result            TEXT    DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_start         TIMESTAMPTZ;
    v_ts            TIMESTAMPTZ;
    v_op_speed      REAL;
    v_waitings      REAL;
    v_correlation   REAL;
    v_os_angle      REAL;
    v_wait_angle    REAL;
    v_os_trend      SMALLINT;
    v_wait_trend    SMALLINT;
    v_curr_state    SMALLINT;
    v_prev_state    SMALLINT;
    v_first         BOOLEAN := TRUE;
    v_total_minutes BIGINT := 0;
    v_transitions   BIGINT := 0;
    v_window        INTERVAL := INTERVAL '1 hour';
    v_angle_threshold REAL := 0.5;
    v_row           RECORD;
    -- Прогресс
    v_total_records   BIGINT;
    v_processed_records BIGINT := 0;
    v_last_percent    INT := -1;
    v_current_percent INT;
    -- Забывание
    v_interval_min    INT;
    v_last_forget     TIMESTAMPTZ;
    v_adaptive_enabled BOOLEAN;
    -- COMMIT
    v_commit_interval INT := 500;
    v_counter         INT := 0;
    -- Результат обновления critical_states
    v_critical_result TEXT;
    -- Для подавления NOTICE
    v_old_msg_level  TEXT;
    -- Для лога прогресса
    v_log_message    TEXT;
BEGIN
    -- ------------------------------------------------------------------
    -- 1. Создание таблицы для логов, если её нет
    -- ------------------------------------------------------------------
    CREATE TABLE IF NOT EXISTS mchain_train_progress_log (
        id                BIGSERIAL PRIMARY KEY,
        ts                TIMESTAMPTZ DEFAULT now(),
        total_records     BIGINT,
        processed_records BIGINT,
        percent           INT,
        transitions       BIGINT,
        message           TEXT
    );

    -- ------------------------------------------------------------------
    -- 2. Определение начала периода
    -- ------------------------------------------------------------------
    SELECT MIN(curr_timestamp) INTO v_start FROM pgh_stat_cluster_analysis;
    IF v_start IS NULL THEN
        result := 'Ошибка: таблица pgh_stat_cluster_analysis пуста. Невозможно обучить модель.';
        RETURN;
    END IF;

    IF p_end < v_start THEN
        result := format('Ошибка: конечная дата (%s) раньше начальной (%s).', p_end, v_start);
        RETURN;
    END IF;

    -- ------------------------------------------------------------------
    -- 3. Очистка таблиц модели
    -- ------------------------------------------------------------------
    TRUNCATE TABLE markov_frequencies;
    TRUNCATE TABLE transition_log;
    TRUNCATE TABLE markov_chain;
    TRUNCATE TABLE markov_probabilities;
    TRUNCATE TABLE markov_absorbing;
    TRUNCATE TABLE prediction_log;
    TRUNCATE TABLE mchain_quality_metrics_history;

    -- ------------------------------------------------------------------
    -- 4. Подготовка конфигурации
    -- ------------------------------------------------------------------
    UPDATE markov_config SET last_forget_time = v_start;
    SELECT interval_minute, adaptive_forgetting_enabled
    INTO v_interval_min, v_adaptive_enabled
    FROM markov_config LIMIT 1;

    -- ------------------------------------------------------------------
    -- 5. Подсчёт общего количества записей для прогресса
    -- ------------------------------------------------------------------
    SELECT COUNT(*) INTO v_total_records
    FROM pgh_stat_cluster_analysis
    WHERE curr_timestamp BETWEEN v_start AND p_end;

    RAISE NOTICE 'Начало обучения с % по % (всего % записей с данными)',
                 v_start, p_end, v_total_records;

    -- Запись начального события в лог
    INSERT INTO mchain_train_progress_log (total_records, processed_records, percent, transitions, message)
    VALUES (v_total_records, 0, 0, 0, 'Начало обучения');

    -- ------------------------------------------------------------------
    -- 6. Цикл по минутам
    -- ------------------------------------------------------------------
    FOR v_row IN
        SELECT curr_timestamp, op_speed_long, waitings_long
        FROM pgh_stat_cluster_analysis
        WHERE curr_timestamp BETWEEN v_start AND p_end
        ORDER BY curr_timestamp
    LOOP
        v_ts := v_row.curr_timestamp;
        v_op_speed := v_row.op_speed_long;
        v_waitings := v_row.waitings_long;

        v_total_minutes := v_total_minutes + 1;
        v_processed_records := v_processed_records + 1;

        -- 6.1 Вычисление корреляции и трендов (без изменений)
        BEGIN
            SELECT COALESCE(corr(op_speed_long, waitings_long), 0)
            INTO v_correlation
            FROM pgh_stat_cluster_analysis
            WHERE curr_timestamp BETWEEN v_ts - v_window AND v_ts;
        EXCEPTION WHEN OTHERS THEN
            v_correlation := 0.0;
        END;

        BEGIN
            WITH window_data AS (
                SELECT op_speed_long,
                       row_number() OVER (ORDER BY curr_timestamp) AS rn
                FROM pgh_stat_cluster_analysis
                WHERE curr_timestamp BETWEEN v_ts - v_window AND v_ts
            ),
            stats AS (
                SELECT AVG(rn::DOUBLE PRECISION) as avg1,
                       STDDEV(rn::DOUBLE PRECISION) as std1,
                       AVG(op_speed_long::DOUBLE PRECISION) as avg2,
                       STDDEV(op_speed_long::DOUBLE PRECISION) as std2
                FROM window_data
            ),
            standardized_data AS (
                SELECT (wd.rn::DOUBLE PRECISION - s.avg1) / NULLIF(s.std1, 0) as x_z,
                       (wd.op_speed_long::DOUBLE PRECISION - s.avg2) / NULLIF(s.std2, 0) as y_z
                FROM window_data wd, stats s
            )
            SELECT ATAN(REGR_SLOPE(y_z, x_z)) * 180 / PI()
            INTO v_os_angle
            FROM standardized_data;
        EXCEPTION WHEN OTHERS THEN
            v_os_angle := 0.0;
        END;

        BEGIN
            WITH window_data AS (
                SELECT waitings_long,
                       row_number() OVER (ORDER BY curr_timestamp) AS rn
                FROM pgh_stat_cluster_analysis
                WHERE curr_timestamp BETWEEN v_ts - v_window AND v_ts
            ),
            stats AS (
                SELECT AVG(rn::DOUBLE PRECISION) as avg1,
                       STDDEV(rn::DOUBLE PRECISION) as std1,
                       AVG(waitings_long::DOUBLE PRECISION) as avg2,
                       STDDEV(waitings_long::DOUBLE PRECISION) as std2
                FROM window_data
            ),
            standardized_data AS (
                SELECT (wd.rn::DOUBLE PRECISION - s.avg1) / NULLIF(s.std1, 0) as x_z,
                       (wd.waitings_long::DOUBLE PRECISION - s.avg2) / NULLIF(s.std2, 0) as y_z
                FROM window_data wd, stats s
            )
            SELECT ATAN(REGR_SLOPE(y_z, x_z)) * 180 / PI()
            INTO v_wait_angle
            FROM standardized_data;
        EXCEPTION WHEN OTHERS THEN
            v_wait_angle := 0.0;
        END;

        IF v_os_angle > v_angle_threshold THEN v_os_trend := 1;
        ELSIF v_os_angle < -v_angle_threshold THEN v_os_trend := -1;
        ELSE v_os_trend := 0;
        END IF;

        IF v_wait_angle > v_angle_threshold THEN v_wait_trend := 1;
        ELSIF v_wait_angle < -v_angle_threshold THEN v_wait_trend := -1;
        ELSE v_wait_trend := 0;
        END IF;

        v_curr_state := get_state_id(v_correlation, v_os_trend, v_wait_trend);

        -- 6.2 Логика первого состояния или перехода
        IF v_first THEN
            INSERT INTO markov_chain (curr_correlation, curr_os_trend, curr_wait_trend)
            VALUES (v_correlation, v_os_trend, v_wait_trend);
            v_prev_state := v_curr_state;
            v_first := FALSE;
        ELSE
            PERFORM mchain_log_transition(v_prev_state, v_curr_state);
            v_transitions := v_transitions + 1;

            UPDATE markov_chain SET
                prev_correlation = curr_correlation,
                prev_os_trend    = curr_os_trend,
                prev_wait_trend  = curr_wait_trend,
                curr_correlation = v_correlation,
                curr_os_trend    = v_os_trend,
                curr_wait_trend  = v_wait_trend;

            -- 6.2.1 Прогноз (с подавлением ошибок)
            BEGIN
                PERFORM collect_prediction(p_time => v_ts);
            EXCEPTION WHEN OTHERS THEN
                RAISE WARNING 'collect_prediction failed at %: %', v_ts, SQLERRM;
            END;

            -- 6.2.2 Плановое забывание
            IF v_adaptive_enabled THEN
                SELECT last_forget_time INTO v_last_forget FROM markov_config LIMIT 1;
                IF (v_ts - v_last_forget) >= (v_interval_min * INTERVAL '1 minute') THEN
                    BEGIN
                        PERFORM mchain_apply_forgetting();
                        SELECT last_forget_time INTO v_last_forget FROM markov_config LIMIT 1;
                    EXCEPTION WHEN OTHERS THEN
                        RAISE WARNING 'mchain_apply_forgetting failed at %: %', v_ts, SQLERRM;
                    END;
                END IF;
            END IF;

            v_prev_state := v_curr_state;
        END IF;

        -- 6.3 Периодический COMMIT
        v_counter := v_counter + 1;
        IF v_counter >= v_commit_interval THEN
            COMMIT;
            v_counter := 0;
            -- После COMMIT настройки сбрасываются, восстанавливаем подавление NOTICE
            SET LOCAL client_min_messages = WARNING;
            -- Заново читаем параметры забывания
            SELECT interval_minute, adaptive_forgetting_enabled
            INTO v_interval_min, v_adaptive_enabled
            FROM markov_config LIMIT 1;
        END IF;

        -- 6.4 Логирование прогресса (каждые 1% или каждые 1000 записей)
        v_current_percent := floor(v_processed_records * 100.0 / v_total_records);
        IF v_current_percent > v_last_percent THEN
            v_log_message := format('Прогресс: %s%% (обработано %s из %s, переходов: %s)',
                                    v_current_percent, v_processed_records, v_total_records, v_transitions);
            RAISE NOTICE '%', v_log_message;
            INSERT INTO mchain_train_progress_log (total_records, processed_records, percent, transitions, message)
            VALUES (v_total_records, v_processed_records, v_current_percent, v_transitions, v_log_message);
            v_last_percent := v_current_percent;
        ELSIF v_processed_records % 1000 = 0 THEN
            v_log_message := format('Детализация: обработано %s записей, переходов: %s',
                                    v_processed_records, v_transitions);
            RAISE NOTICE '%', v_log_message;
            INSERT INTO mchain_train_progress_log (total_records, processed_records, percent, transitions, message)
            VALUES (v_total_records, v_processed_records, v_current_percent, v_transitions, v_log_message);
        END IF;
    END LOOP;

    -- ------------------------------------------------------------------
    -- 7. Завершающий пересчёт
    -- ------------------------------------------------------------------
    PERFORM update_markov_probabilities();
    PERFORM rebuild_markov_absorbing();

    -- ------------------------------------------------------------------
    -- 8. Обновление исходов прогнозов
    -- ------------------------------------------------------------------
    PERFORM update_prediction_outcomes();

    -- ------------------------------------------------------------------
    -- 9. Обновление critical_states с подавлением NOTICE
    -- ------------------------------------------------------------------
    IF p_refresh_critical THEN
        BEGIN
            SHOW client_min_messages INTO v_old_msg_level;
            SET LOCAL client_min_messages = WARNING;

            RAISE NOTICE 'Обновление critical_states на основе исторических данных...';
            SELECT refresh_critical_states(
                p_start           => v_start,
                p_end             => p_end,
                p_min_transitions => p_min_transitions,
                p_interval_min    => p_interval_min,
                p_risk_threshold  => p_risk_threshold,
                p_dry_run         => FALSE,
                p_audit           => TRUE
            ) INTO v_critical_result;

            EXECUTE format('SET LOCAL client_min_messages = %I', v_old_msg_level);
            RAISE NOTICE 'Результат обновления critical_states: %', v_critical_result;
        EXCEPTION WHEN OTHERS THEN
            v_critical_result := format('Ошибка при обновлении critical_states: %s', SQLERRM);
            RAISE WARNING 'Ошибка при обновлении critical_states: %', SQLERRM;
            BEGIN
                EXECUTE format('SET LOCAL client_min_messages = %I', v_old_msg_level);
            EXCEPTION WHEN OTHERS THEN
                NULL;
            END;
        END;
    ELSE
        v_critical_result := 'Обновление critical_states пропущено (p_refresh_critical = FALSE).';
    END IF;

    -- ------------------------------------------------------------------
    -- 10. Итоговый отчёт
    -- ------------------------------------------------------------------
    RAISE NOTICE 'Обучение завершено. Обработано минут: %, переходов: %, прогнозов: %',
                 v_total_minutes, v_transitions, (SELECT COUNT(*) FROM prediction_log);
    result := format('Обучение завершено. Начало: %s, конец: %s. Обработано минут: %s, залогировано переходов: %s, создано прогнозов: %s. Текущее состояние: state_id=%s. %s',
                  v_start, p_end, v_total_minutes, v_transitions,
                  (SELECT COUNT(*) FROM prediction_log), v_curr_state, v_critical_result);

    -- Логируем завершение
    INSERT INTO mchain_train_progress_log (total_records, processed_records, percent, transitions, message)
    VALUES (v_total_records, v_processed_records, 100, v_transitions, 'Обучение завершено');
END;
$$;
COMMENT ON PROCEDURE mchain_initial_train_from_history(TIMESTAMPTZ, BOOLEAN, REAL, INT, INT, TEXT) IS 'Первоначальное обучение с имитацией реального времени. Прогресс пишется в таблицу mchain_train_progress_log и дублируется в консоль. Все NOTICE о временных таблицах подавлены.';

-- =====================================================================================
-- Функция: mchain_train_historical(end_time TIMESTAMPTZ)
-- Назначение: выполняет полное историческое обучение цепи Маркова
--             от минимальной даты в pgh_stat_cluster_analysis до end_time.
--             Логирует прогресс каждый час.
-- =====================================================================================
CREATE OR REPLACE FUNCTION mchain_train_historical(end_time TIMESTAMPTZ)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    start_time TIMESTAMPTZ;
    curr_ts TIMESTAMPTZ;
    total_minutes BIGINT;
    processed BIGINT := 0;
    last_log_hour TIMESTAMPTZ := NULL;
    step_result TEXT;
BEGIN
    SELECT MIN(curr_timestamp) INTO start_time FROM pgh_stat_cluster_analysis;
    IF start_time IS NULL THEN
        RAISE EXCEPTION 'No data in pgh_stat_cluster_analysis';
    END IF;

    -- Заполнение performance_history, если необходимо
    IF NOT EXISTS (SELECT 1 FROM performance_history WHERE ts BETWEEN start_time AND end_time LIMIT 1) THEN
        PERFORM fill_performance_history(start_time, end_time);
    END IF;

    -- Установка last_forget_time в начало периода
    UPDATE markov_config SET last_forget_time = start_time;

    -- Отключение триггера (уже сделано в скрипте, но на всякий случай)
    ALTER TABLE transition_log DISABLE TRIGGER trigger_update_incident_time;

    total_minutes := EXTRACT(EPOCH FROM (end_time - start_time)) / 60 + 1;
    curr_ts := start_time;

    RAISE NOTICE 'Начало исторического обучения с % по % (всего % минут)', start_time, end_time, total_minutes;

    WHILE curr_ts <= end_time LOOP
        BEGIN
            step_result := mchain_train_step_at(curr_ts);
        EXCEPTION WHEN OTHERS THEN
            RAISE WARNING 'Ошибка на %: %', curr_ts, SQLERRM;
        END;

        processed := processed + 1;

        IF last_log_hour IS NULL OR curr_ts - last_log_hour >= INTERVAL '1 hour' THEN
            RAISE NOTICE 'Прогресс: % из % минут (% pct)', processed, total_minutes, (processed::FLOAT / total_minutes * 100)::INT;
            last_log_hour := curr_ts;
        END IF;

        curr_ts := curr_ts + INTERVAL '1 minute';
    END LOOP;

    ALTER TABLE transition_log ENABLE TRIGGER trigger_update_incident_time;

    UPDATE markov_config SET last_incident_time = (
        SELECT MAX(ts) FROM transition_log
        WHERE to_state IN (SELECT state_id FROM critical_states)
    );

    RAISE NOTICE 'Обучение завершено. Обработано % минут.', processed;
    RETURN format('Историческое обучение завершено. Обработано %s минут.', processed);
END;
$$;

-- ====================================================================================================
-- Функция: заполнить performance_history за указанный период
-- ====================================================================================================
-- Модифицированная функция fill_performance_history с выводом прогресса через RAISE NOTICE
/*
select fill_performance_history( to_timestamp('2026-06-25 00:00' , 'YYYY-MM-DD HH24:MI') , to_timestamp('2026-06-26 00:00' , 'YYYY-MM-DD HH24:MI') );

psql -d expecto_db -U expecto_user -c "select fill_performance_history( to_timestamp('2026-06-25 00:00' , 'YYYY-MM-DD HH24:MI') , to_timestamp('2026-06-26 00:00' , 'YYYY-MM-DD HH24:MI') )"
psql -d expecto_db -U expecto_user -c "select ph.* , pi.* from performance_history ph LEFT JOIN performance_incident pi ON ( ph.ts = pi.start_timepoint ) ORDER BY ph.ts " > /tmp/performance_history.txt 
psql -d expecto_db -U expecto_user -c "select mchain_summary_report(to_timestamp('2026-06-22 00:00' , 'YYYY-MM-DD HH24:MI') , to_timestamp('2026-06-23 00:00' , 'YYYY-MM-DD HH24:MI') )" > /tmp/mchain_summary_report.txt
*/
CREATE OR REPLACE FUNCTION fill_performance_history(
    p_start TIMESTAMPTZ,
    p_end   TIMESTAMPTZ
)
RETURNS TEXT
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
    v_ts          TIMESTAMPTZ;
    v_window      INTERVAL := INTERVAL '1 hour';
    v_op_speed    REAL;
    v_waitings    REAL;
    v_correlation REAL;
    v_os_angle    REAL;
    v_wait_angle  REAL;
    v_inserted    INT := 0;
    v_skip        BOOLEAN;
    v_total_minutes BIGINT;
    v_processed   BIGINT := 0;
    v_last_percent INT := -1;
    v_current_percent INT;
    v_start_ts    TIMESTAMPTZ;
    v_end_ts      TIMESTAMPTZ;
BEGIN
    -- Проверка корректности диапазона
    IF p_start > p_end THEN
        RETURN 'Ошибка: время начала должно быть меньше или равно времени окончания.';
    END IF;
	
	TRUNCATE TABLE performance_history ; 

    -- Округляем до минут для единообразия
    v_start_ts := date_trunc('minute', p_start);
    v_end_ts   := date_trunc('minute', p_end);

    -- Общее количество минут в диапазоне
    v_total_minutes := EXTRACT(EPOCH FROM (v_end_ts - v_start_ts)) / 60 + 1;

    RAISE NOTICE 'Начало заполнения performance_history за период с % по % (всего % минут)',
                 v_start_ts, v_end_ts, v_total_minutes;

    -- Начинаем с первой минуты
    v_ts := v_start_ts;

    WHILE v_ts <= v_end_ts LOOP
        v_skip := FALSE;

        -- 1. Получаем значения скорости и ожиданий в точный момент времени
        SELECT op_speed_long, waitings_long
        INTO v_op_speed, v_waitings
        FROM pgh_stat_cluster_analysis
        WHERE curr_timestamp = v_ts;

        -- Если точной записи нет – пропускаем эту минуту
        IF NOT FOUND THEN
            v_ts := v_ts + INTERVAL '1 minute';
            v_processed := v_processed + 1;
            -- Вывод прогресса даже для пропущенных минут (чтобы пользователь видел движение)
            v_current_percent := floor(v_processed * 100.0 / v_total_minutes);
            IF v_current_percent > v_last_percent THEN
                RAISE NOTICE 'Прогресс: % % (обработано % из % минут)',
                             v_current_percent, '%', v_processed, v_total_minutes;
                v_last_percent := v_current_percent;
            END IF;
            CONTINUE;
        END IF;

        -- 2. Вычисляем корреляцию за окно
        BEGIN
            SELECT COALESCE(corr(op_speed_long, waitings_long), 0)
            INTO v_correlation
            FROM pgh_stat_cluster_analysis
            WHERE curr_timestamp BETWEEN v_ts - v_window AND v_ts;
        EXCEPTION
            WHEN OTHERS THEN
                v_correlation := 0.0;
        END;

        -- 3. Вычисляем угол наклона тренда операционной скорости
        BEGIN
            WITH window_data AS (
                SELECT
                    op_speed_long,
                    row_number() OVER (ORDER BY curr_timestamp) AS rn
                FROM pgh_stat_cluster_analysis
                WHERE curr_timestamp BETWEEN v_ts - v_window AND v_ts
            ),
            stats AS (
                SELECT
                    AVG(rn::DOUBLE PRECISION) as avg1,
                    STDDEV(rn::DOUBLE PRECISION) as std1,
                    AVG(op_speed_long::DOUBLE PRECISION) as avg2,
                    STDDEV(op_speed_long::DOUBLE PRECISION) as std2
                FROM window_data
            ),
            standardized_data AS (
                SELECT
                    (wd.rn::DOUBLE PRECISION - s.avg1) / NULLIF(s.std1, 0) as x_z,
                    (wd.op_speed_long::DOUBLE PRECISION - s.avg2) / NULLIF(s.std2, 0) as y_z
                FROM window_data wd, stats s
            )
            SELECT
                ATAN(REGR_SLOPE(y_z, x_z)) * 180 / PI()
            INTO v_os_angle
            FROM standardized_data;
        EXCEPTION
            WHEN OTHERS THEN
                v_os_angle := 0.0;
        END;

        -- 4. Вычисляем угол наклона тренда ожиданий
        BEGIN
            WITH window_data AS (
                SELECT
                    waitings_long,
                    row_number() OVER (ORDER BY curr_timestamp) AS rn
                FROM pgh_stat_cluster_analysis
                WHERE curr_timestamp BETWEEN v_ts - v_window AND v_ts
            ),
            stats AS (
                SELECT
                    AVG(rn::DOUBLE PRECISION) as avg1,
                    STDDEV(rn::DOUBLE PRECISION) as std1,
                    AVG(waitings_long::DOUBLE PRECISION) as avg2,
                    STDDEV(waitings_long::DOUBLE PRECISION) as std2
                FROM window_data
            ),
            standardized_data AS (
                SELECT
                    (wd.rn::DOUBLE PRECISION - s.avg1) / NULLIF(s.std1, 0) as x_z,
                    (wd.waitings_long::DOUBLE PRECISION - s.avg2) / NULLIF(s.std2, 0) as y_z
                FROM window_data wd, stats s
            )
            SELECT
                ATAN(REGR_SLOPE(y_z, x_z)) * 180 / PI()
            INTO v_wait_angle
            FROM standardized_data;
        EXCEPTION
            WHEN OTHERS THEN
                v_wait_angle := 0.0;
        END;

        -- 5. Вставляем запись в performance_history
        INSERT INTO performance_history (ts, op_speed, waitings, correlation, os_angle, wait_angle)
        VALUES (v_ts, v_op_speed, v_waitings, v_correlation, v_os_angle, v_wait_angle)
        ON CONFLICT (ts) DO UPDATE SET
            op_speed = EXCLUDED.op_speed,
            waitings = EXCLUDED.waitings,
            correlation = EXCLUDED.correlation,
            os_angle = EXCLUDED.os_angle,
            wait_angle = EXCLUDED.wait_angle;

        v_inserted := v_inserted + 1;

        -- Переходим к следующей минуте и увеличиваем счётчик
        v_ts := v_ts + INTERVAL '1 minute';
        v_processed := v_processed + 1;

        -- Вывод прогресса каждые 10%
        v_current_percent := floor(v_processed * 100.0 / v_total_minutes);
        IF v_current_percent > v_last_percent THEN
            RAISE NOTICE 'Прогресс: % % (обработано % из % минут)',
                         v_current_percent, '%', v_processed, v_total_minutes;
            v_last_percent := v_current_percent;
        END IF;
    END LOOP;

    RAISE NOTICE 'Заполнение завершено. Вставлено/обновлено записей: %.', v_inserted;
    RETURN format('Обработано %s минут. Вставлено/обновлено записей: %s.',
                  v_total_minutes, v_inserted);
END;
$$;

COMMENT ON FUNCTION fill_performance_history(TIMESTAMPTZ, TIMESTAMPTZ) IS 'Заполняет таблицу performance_history за указанный период с выводом прогресса через RAISE NOTICE каждые 10% выполнения.';

-- Инкрементально добавляет или обновляет записи в performance_history за указанный период (без TRUNCATE). Использует pgh_stat_cluster_analysis как источник.
CREATE OR REPLACE FUNCTION append_performance_history(
    p_start TIMESTAMPTZ,
    p_end   TIMESTAMPTZ
)
RETURNS TEXT
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
    v_ts          TIMESTAMPTZ;
    v_window      INTERVAL := INTERVAL '1 hour';
    v_op_speed    REAL;
    v_waitings    REAL;
    v_correlation REAL;
    v_os_angle    REAL;
    v_wait_angle  REAL;
    v_inserted    INT := 0;
    v_total_minutes BIGINT;
    v_processed   BIGINT := 0;
    v_last_percent INT := -1;
    v_current_percent INT;
    v_start_ts    TIMESTAMPTZ;
    v_end_ts      TIMESTAMPTZ;
BEGIN
    -- Проверка корректности диапазона
    IF p_start > p_end THEN
        RETURN 'Ошибка: время начала должно быть меньше или равно времени окончания.';
    END IF;

    -- Округляем до минут для единообразия
    v_start_ts := date_trunc('minute', p_start);
    v_end_ts   := date_trunc('minute', p_end);

    v_total_minutes := EXTRACT(EPOCH FROM (v_end_ts - v_start_ts)) / 60 + 1;

    RAISE NOTICE 'Начало добавления записей в performance_history за период с % по % (всего % минут)',
                 v_start_ts, v_end_ts, v_total_minutes;

    v_ts := v_start_ts;

    WHILE v_ts <= v_end_ts LOOP
        -- 1. Получаем значения скорости и ожиданий в точный момент времени
        SELECT op_speed_long, waitings_long
        INTO v_op_speed, v_waitings
        FROM pgh_stat_cluster_analysis
        WHERE curr_timestamp = v_ts;

        IF NOT FOUND THEN
            v_ts := v_ts + INTERVAL '1 minute';
            v_processed := v_processed + 1;
            v_current_percent := floor(v_processed * 100.0 / v_total_minutes);
            IF v_current_percent > v_last_percent THEN
                RAISE NOTICE 'Прогресс: % % (обработано % из % минут)',
                             v_current_percent, '%', v_processed, v_total_minutes;
                v_last_percent := v_current_percent;
            END IF;
            CONTINUE;
        END IF;

        -- 2. Вычисляем корреляцию за окно
        BEGIN
            SELECT COALESCE(corr(op_speed_long, waitings_long), 0)
            INTO v_correlation
            FROM pgh_stat_cluster_analysis
            WHERE curr_timestamp BETWEEN v_ts - v_window AND v_ts;
        EXCEPTION
            WHEN OTHERS THEN
                v_correlation := 0.0;
        END;

        -- 3. Вычисляем угол наклона тренда OS
        BEGIN
            WITH window_data AS (
                SELECT op_speed_long,
                       row_number() OVER (ORDER BY curr_timestamp) AS rn
                FROM pgh_stat_cluster_analysis
                WHERE curr_timestamp BETWEEN v_ts - v_window AND v_ts
            ),
            stats AS (
                SELECT AVG(rn::DOUBLE PRECISION) as avg1,
                       STDDEV(rn::DOUBLE PRECISION) as std1,
                       AVG(op_speed_long::DOUBLE PRECISION) as avg2,
                       STDDEV(op_speed_long::DOUBLE PRECISION) as std2
                FROM window_data
            ),
            standardized_data AS (
                SELECT (wd.rn::DOUBLE PRECISION - s.avg1) / NULLIF(s.std1, 0) as x_z,
                       (wd.op_speed_long::DOUBLE PRECISION - s.avg2) / NULLIF(s.std2, 0) as y_z
                FROM window_data wd, stats s
            )
            SELECT ATAN(REGR_SLOPE(y_z, x_z)) * 180 / PI()
            INTO v_os_angle
            FROM standardized_data;
        EXCEPTION
            WHEN OTHERS THEN
                v_os_angle := 0.0;
        END;

        -- 4. Вычисляем угол наклона тренда ожиданий
        BEGIN
            WITH window_data AS (
                SELECT waitings_long,
                       row_number() OVER (ORDER BY curr_timestamp) AS rn
                FROM pgh_stat_cluster_analysis
                WHERE curr_timestamp BETWEEN v_ts - v_window AND v_ts
            ),
            stats AS (
                SELECT AVG(rn::DOUBLE PRECISION) as avg1,
                       STDDEV(rn::DOUBLE PRECISION) as std1,
                       AVG(waitings_long::DOUBLE PRECISION) as avg2,
                       STDDEV(waitings_long::DOUBLE PRECISION) as std2
                FROM window_data
            ),
            standardized_data AS (
                SELECT (wd.rn::DOUBLE PRECISION - s.avg1) / NULLIF(s.std1, 0) as x_z,
                       (wd.waitings_long::DOUBLE PRECISION - s.avg2) / NULLIF(s.std2, 0) as y_z
                FROM window_data wd, stats s
            )
            SELECT ATAN(REGR_SLOPE(y_z, x_z)) * 180 / PI()
            INTO v_wait_angle
            FROM standardized_data;
        EXCEPTION
            WHEN OTHERS THEN
                v_wait_angle := 0.0;
        END;

        -- 5. Вставляем или обновляем запись в performance_history
        INSERT INTO performance_history (ts, op_speed, waitings, correlation, os_angle, wait_angle)
        VALUES (v_ts, v_op_speed, v_waitings, v_correlation, v_os_angle, v_wait_angle)
        ON CONFLICT (ts) DO UPDATE SET
            op_speed = EXCLUDED.op_speed,
            waitings = EXCLUDED.waitings,
            correlation = EXCLUDED.correlation,
            os_angle = EXCLUDED.os_angle,
            wait_angle = EXCLUDED.wait_angle;

        v_inserted := v_inserted + 1;

        v_ts := v_ts + INTERVAL '1 minute';
        v_processed := v_processed + 1;

        v_current_percent := floor(v_processed * 100.0 / v_total_minutes);
        IF v_current_percent > v_last_percent THEN
            RAISE NOTICE 'Прогресс: % % (обработано % из % минут)',
                         v_current_percent, '%', v_processed, v_total_minutes;
            v_last_percent := v_current_percent;
        END IF;
    END LOOP;

    RAISE NOTICE 'Добавление завершено. Вставлено/обновлено записей: %.', v_inserted;
    RETURN format('Обработано %s минут. Вставлено/обновлено записей: %s.',
                  v_total_minutes, v_inserted);
END;
$$;

COMMENT ON FUNCTION append_performance_history(TIMESTAMPTZ, TIMESTAMPTZ) IS
'Инкрементально добавляет или обновляет записи в performance_history за указанный период (без TRUNCATE). Использует pgh_stat_cluster_analysis как источник.';

-- =============================================================================
-- Функция: refresh_performance_history
-- Назначение: Дополнить таблицу performance_history
CREATE OR REPLACE FUNCTION refresh_performance_history()
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    last_ts TIMESTAMPTZ;
    start_ts TIMESTAMPTZ;
    end_ts TIMESTAMPTZ := now();
    result TEXT;
BEGIN
    -- Определяем последнюю запись в performance_history
    SELECT MAX(ts) INTO last_ts FROM performance_history;
    
    IF last_ts IS NULL THEN
        -- Если таблица пуста, берём самую раннюю минуту из pgh_stat_cluster_analysis
        SELECT MIN(curr_timestamp) INTO start_ts FROM pgh_stat_cluster_analysis;
        IF start_ts IS NULL THEN
            RETURN 'Нет данных в pgh_stat_cluster_analysis';
        END IF;
    ELSE
        -- Начинаем со следующей минуты
        start_ts := last_ts + INTERVAL '1 minute';
    END IF;
    
    IF start_ts > end_ts THEN
        RETURN 'Новых данных нет';
    END IF;
    
    -- Вызываем инкрементальное добавление
    result := append_performance_history(start_ts, end_ts);
    RETURN result;
END;
$$;