--------------------------------------------------------------------------------
-- markov_chain_backup_functions.sql
-- ФУНКЦИИ восстановление реальных переходов из внешних логов
-- для обеспечения скрипта 
-- markov_chain_backup.sh
--------------------------------------------------------------------------------

-- ====================================================================================================
-- Функция: получить состояние (state_id) для заданного времени
-- Использует те же окна, что и сбор метрик производительности: 60 минут
-- ====================================================================================================
-- Функция: получить состояние для заданного времени, полностью повторяя логику
-- get_current_os_waiting_correlation_for_markov_chain, но для произвольного timestamp.
CREATE OR REPLACE FUNCTION get_state_at_time(
    p_timestamp TIMESTAMPTZ
)
RETURNS TABLE (
    state_id   SMALLINT,
    correlation REAL,
    os_trend   SMALLINT,
    wait_trend SMALLINT
)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_timepoint timestamptz;
    speed_waitings_correlation DOUBLE PRECISION;
    speed_angle DOUBLE PRECISION;
    waitings_angle DOUBLE PRECISION;
    v_window INTERVAL := INTERVAL '1 hour';
BEGIN
    v_timepoint := p_timestamp;

    -- Корреляция скорость-ожидания за окно
    SELECT COALESCE(corr(curr_op_speed, curr_waitings), 0) INTO speed_waitings_correlation
    FROM cluster_stat_median
    WHERE curr_timestamp BETWEEN v_timepoint - v_window AND v_timepoint;

    -- Регрессия операционной скорости (без временной таблицы)
    BEGIN
        WITH window_data AS (
            SELECT
                curr_op_speed,
                row_number() OVER (ORDER BY curr_timestamp) AS rn
            FROM cluster_stat_median
            WHERE curr_timestamp BETWEEN v_timepoint - v_window AND v_timepoint
        ),
        stats AS (
            SELECT
                AVG(rn::DOUBLE PRECISION) as avg1,
                STDDEV(rn::DOUBLE PRECISION) as std1,
                AVG(curr_op_speed::DOUBLE PRECISION) as avg2,
                STDDEV(curr_op_speed::DOUBLE PRECISION) as std2
            FROM window_data
        ),
        standardized_data AS (
            SELECT
                (wd.rn::DOUBLE PRECISION - s.avg1) / s.std1 as x_z,
                (wd.curr_op_speed::DOUBLE PRECISION - s.avg2) / s.std2 as y_z
            FROM window_data wd, stats s
        )
        SELECT
            ATAN(REGR_SLOPE(y_z, x_z)) * 180 / PI()
        INTO speed_angle
        FROM standardized_data;
    EXCEPTION
        WHEN division_by_zero OR others THEN
            speed_angle := 0.0;
    END;

    -- Регрессия ожиданий (аналогично)
    BEGIN
        WITH window_data AS (
            SELECT
                curr_waitings,
                row_number() OVER (ORDER BY curr_timestamp) AS rn
            FROM cluster_stat_median
            WHERE curr_timestamp BETWEEN v_timepoint - v_window AND v_timepoint
        ),
        stats AS (
            SELECT
                AVG(rn::DOUBLE PRECISION) as avg1,
                STDDEV(rn::DOUBLE PRECISION) as std1,
                AVG(curr_waitings::DOUBLE PRECISION) as avg2,
                STDDEV(curr_waitings::DOUBLE PRECISION) as std2
            FROM window_data
        ),
        standardized_data AS (
            SELECT
                (wd.rn::DOUBLE PRECISION - s.avg1) / s.std1 as x_z,
                (wd.curr_waitings::DOUBLE PRECISION - s.avg2) / s.std2 as y_z
            FROM window_data wd, stats s
        )
        SELECT
            ATAN(REGR_SLOPE(y_z, x_z)) * 180 / PI()
        INTO waitings_angle
        FROM standardized_data;
    EXCEPTION
        WHEN division_by_zero OR others THEN
            waitings_angle := 0.0;
    END;

    -- Формирование результата
    correlation := round(speed_waitings_correlation::NUMERIC, 1)::REAL;
    os_trend := SIGN(speed_angle)::SMALLINT;
    wait_trend := SIGN(waitings_angle)::SMALLINT;
    state_id := get_state_id(correlation, os_trend, wait_trend);

    RETURN NEXT;
END;
$$;
COMMENT ON FUNCTION get_state_at_time(TIMESTAMPTZ) IS 'Возвращает состояние для произвольного момента времени, используя ту же логику, что и get_current_os_waiting_correlation_for_markov_chain (окно 1 час). Без временных таблиц.';

-- ====================================================================================================
/*
Функция fill_missing_transitions
Определяет все минуты в пропущенном диапазоне.
Для каждой минуты вычисляет состояние.
Вставляет переходы между последовательными состояниями.
Пересчитывает вероятности и поглощающую матрицу.
*/
-- ====================================================================================================
-- Функция: восстановить переходы за пропущенный период
CREATE OR REPLACE FUNCTION fill_missing_transitions(
    p_backup_time TIMESTAMPTZ,
    p_restore_time TIMESTAMPTZ DEFAULT now()
)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    v_prev_state SMALLINT;
    v_curr_state SMALLINT;
    v_prev_rec RECORD;
    v_curr_rec RECORD;
    v_ts TIMESTAMPTZ;
    v_last_incident TIMESTAMPTZ;
    v_inserted INT := 0;
    v_incident_exists BOOLEAN;
BEGIN
    -- Проверка диапазона
    IF p_backup_time >= p_restore_time THEN
        RETURN 'Ошибка: время бекапа должно быть меньше времени восстановления.';
    END IF;

    -- Получаем первое состояние (на момент бекапа) из таблицы markov_chain
    -- (предполагаем, что после восстановления там правильное состояние)
    SELECT curr_correlation, curr_os_trend, curr_wait_trend INTO v_prev_rec
    FROM markov_chain LIMIT 1;

    IF NOT FOUND THEN
        RETURN 'Ошибка: таблица markov_chain пуста. Сначала выполните mchain_train_step().';
    END IF;

    v_prev_state := get_state_id(v_prev_rec.curr_correlation,
                                 v_prev_rec.curr_os_trend,
                                 v_prev_rec.curr_wait_trend);

    -- Цикл по минутам от p_backup_time до p_restore_time (исключая границы)
    v_ts := date_trunc('minute', p_backup_time) + INTERVAL '1 minute';
    WHILE v_ts <= date_trunc('minute', p_restore_time) LOOP
        -- Получаем состояние для текущей минуты
        SELECT state_id, correlation, os_trend, wait_trend INTO v_curr_rec
        FROM get_state_at_time(v_ts);

        IF v_curr_rec.state_id IS NOT NULL THEN
            v_curr_state := v_curr_rec.state_id;

            -- Если состояние изменилось, логируем переход
            IF v_curr_state != v_prev_state THEN
                -- Вставляем в transition_log
                INSERT INTO transition_log (ts, from_state, to_state)
                VALUES (v_ts, v_prev_state, v_curr_state);

                -- Обновляем частоты
                INSERT INTO markov_frequencies (from_state, to_state, frequency)
                VALUES (v_prev_state, v_curr_state, 1.0)
                ON CONFLICT (from_state, to_state) DO UPDATE
                    SET frequency = markov_frequencies.frequency + 1.0;

                v_inserted := v_inserted + 1;
            END IF;

            -- Обновляем предыдущее состояние
            v_prev_state := v_curr_state;
            v_prev_rec.curr_correlation := v_curr_rec.correlation;
            v_prev_rec.curr_os_trend := v_curr_rec.os_trend;
            v_prev_rec.curr_wait_trend := v_curr_rec.wait_trend;
        END IF;

        v_ts := v_ts + INTERVAL '1 minute';
    END LOOP;

    -- Обновляем markov_chain на последнее состояние
    UPDATE markov_chain SET
        curr_correlation = v_prev_rec.curr_correlation,
        curr_os_trend = v_prev_rec.curr_os_trend,
        curr_wait_trend = v_prev_rec.curr_wait_trend,
        prev_correlation = COALESCE(prev_correlation, curr_correlation),
        prev_os_trend = COALESCE(prev_os_trend, curr_os_trend),
        prev_wait_trend = COALESCE(prev_wait_trend, curr_wait_trend);

    -- Обновляем время последнего инцидента (если в пропущенном периоде были инциденты)
    SELECT MAX(start_timepoint) INTO v_last_incident
    FROM performance_incident
    WHERE start_timepoint > p_backup_time
      AND start_timepoint <= p_restore_time;

    IF v_last_incident IS NOT NULL THEN
        UPDATE markov_config SET last_incident_time = v_last_incident;
        v_incident_exists := TRUE;
    ELSE
        v_incident_exists := FALSE;
    END IF;

    -- Пересчёт вероятностей и поглощающей матрицы
    PERFORM update_markov_probabilities();
    PERFORM rebuild_markov_absorbing();

    -- Возврат отчёта
    RETURN format('Восстановлено %s переходов за период %s – %s. Инциденты: %s.',
                  v_inserted,
                  p_backup_time,
                  p_restore_time,
                  CASE WHEN v_incident_exists THEN 'обновлён last_incident_time' ELSE 'не было' END);
END;
$$;

COMMENT ON FUNCTION fill_missing_transitions(TIMESTAMPTZ, TIMESTAMPTZ) IS 'Восстанавливает переходы за пропущенный период, используя cluster_stat_median и performance_incident.';


