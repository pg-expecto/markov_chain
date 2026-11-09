--------------------------------------------------------------------------------
-- performance_metrics_for_markov_chain.sql
-- version 16.1
/*
- **Получение текущих метрик**
  - get_current_os_waiting_correlation_for_markov_chain :  Возвращает текущие метрики: корреляцию, тренд операционной скорости, тренд ожиданий на окне 1 час
*/
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- get_current_os_waiting_correlation_for_markov_chain - получить текущее значение коэффициента корреляции для цепи маркова на окне 1 час 
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Улучшенная версия get_current_os_waiting_correlation_for_markov_chain
-- с проверкой существования таблицы cluster_stat_median и обработкой ошибок
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_current_os_waiting_correlation_for_markov_chain()
RETURNS TABLE
(
  current_correlation REAL,
  current_os_trend    SMALLINT,
  current_wait_trend  SMALLINT
)
LANGUAGE plpgsql
AS $$
DECLARE
    timepoint timestamptz;
    tbl_exists BOOLEAN;
    
    speed_waitings_correlation DOUBLE PRECISION;
    speed_regr_slope_value DOUBLE PRECISION;
    waitings_regr_slope_value DOUBLE PRECISION;

    -- Переменные для регрессии скорости
    speed_slope DOUBLE PRECISION;
    speed_angle DOUBLE PRECISION;
    speed_r2    DOUBLE PRECISION;

    -- Переменные для регрессии ожиданий
    waitings_slope DOUBLE PRECISION;
    waitings_angle DOUBLE PRECISION;
    waitings_r2    DOUBLE PRECISION;
	
BEGIN
    -- Проверка существования таблицы cluster_stat_median
    SELECT EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_name = 'cluster_stat_median'
    ) INTO tbl_exists;
    
    IF NOT tbl_exists THEN
        RAISE DEBUG 'get_current_os_waiting_correlation_for_markov_chain: cluster_stat_median not found, returning defaults';
        RETURN QUERY SELECT 0.0::REAL, 0::SMALLINT, 0::SMALLINT;
        RETURN;
    END IF;

    SELECT MAX(curr_timestamp) INTO timepoint FROM cluster_stat_median;
    IF timepoint IS NULL THEN
        RETURN QUERY SELECT 0.0::REAL, 0::SMALLINT, 0::SMALLINT;
        RETURN;
    END IF;

    -- Корреляция скорость-ожидания
    SELECT COALESCE(corr(curr_op_speed, curr_waitings), 0) INTO speed_waitings_correlation
    FROM cluster_stat_median
    WHERE curr_timestamp BETWEEN timepoint - interval '1 hour' AND timepoint;

    -- Временная таблица (безопасно)
    DROP TABLE IF EXISTS tmp_timepoints;
    CREATE TEMP TABLE tmp_timepoints AS
    SELECT
        curr_timestamp,
        row_number() OVER (ORDER BY curr_timestamp) AS curr_timepoint
    FROM cluster_stat_median
    WHERE curr_timestamp BETWEEN timepoint - interval '1 hour' AND timepoint
    ORDER BY curr_timestamp;

    -- ОПЕРАЦИОННАЯ СКОРОСТЬ (линия регрессии)
    BEGIN
        WITH stats AS (
            SELECT
                AVG(t.curr_timepoint::DOUBLE PRECISION) as avg1,
                STDDEV(t.curr_timepoint::DOUBLE PRECISION) as std1,
                AVG(s.curr_op_speed::DOUBLE PRECISION) as avg2,
                STDDEV(s.curr_op_speed::DOUBLE PRECISION) as std2
            FROM cluster_stat_median s
            JOIN tmp_timepoints t ON s.curr_timestamp = t.curr_timestamp
            WHERE t.curr_timestamp BETWEEN timepoint - interval '1 hour' AND timepoint
        ),
        standardized_data AS (
            SELECT
                (t.curr_timepoint::DOUBLE PRECISION - avg1) / std1 as x_z,
                (s.curr_op_speed::DOUBLE PRECISION - avg2) / std2 as y_z
            FROM cluster_stat_median s
            JOIN tmp_timepoints t ON s.curr_timestamp = t.curr_timestamp, stats
            WHERE t.curr_timestamp BETWEEN timepoint - interval '1 hour' AND timepoint
        )
        SELECT
            REGR_SLOPE(y_z, x_z),
            ATAN(REGR_SLOPE(y_z, x_z)) * 180 / PI(),
            REGR_R2(y_z, x_z)
        INTO speed_slope, speed_angle, speed_r2
        FROM standardized_data;
    EXCEPTION
        WHEN division_by_zero THEN
            speed_slope := 1.0;
            speed_angle := 0.0;
            speed_r2 := 0.0;
    END;
    speed_regr_slope_value := SIGN(speed_angle);

    -- ОЖИДАНИЯ (линия регрессии) – аналогично
    BEGIN
        WITH stats AS (
            SELECT
                AVG(t.curr_timepoint::DOUBLE PRECISION) as avg1,
                STDDEV(t.curr_timepoint::DOUBLE PRECISION) as std1,
                AVG(s.curr_waitings::DOUBLE PRECISION) as avg2,
                STDDEV(s.curr_waitings::DOUBLE PRECISION) as std2
            FROM cluster_stat_median s
            JOIN tmp_timepoints t ON s.curr_timestamp = t.curr_timestamp
            WHERE t.curr_timestamp BETWEEN timepoint - interval '1 hour' AND timepoint
        ),
        standardized_data AS (
            SELECT
                (t.curr_timepoint::DOUBLE PRECISION - avg1) / std1 as x_z,
                (s.curr_waitings::DOUBLE PRECISION - avg2) / std2 as y_z
            FROM cluster_stat_median s
            JOIN tmp_timepoints t ON s.curr_timestamp = t.curr_timestamp, stats
            WHERE t.curr_timestamp BETWEEN timepoint - interval '1 hour' AND timepoint
        )
        SELECT
            REGR_SLOPE(y_z, x_z),
            ATAN(REGR_SLOPE(y_z, x_z)) * 180 / PI(),
            REGR_R2(y_z, x_z)
        INTO waitings_slope, waitings_angle, waitings_r2
        FROM standardized_data;
    EXCEPTION
        WHEN division_by_zero THEN
            waitings_slope := 1.0;
            waitings_angle := 0.0;
            waitings_r2 := 0.0;
    END;
    waitings_regr_slope_value := SIGN(waitings_angle);

    DROP TABLE IF EXISTS tmp_timepoints;

    RETURN QUERY
    SELECT
        round(speed_waitings_correlation::numeric,1)::REAL,
        speed_regr_slope_value::SMALLINT,
        waitings_regr_slope_value::SMALLINT;
END;
$$;

COMMENT ON FUNCTION get_current_os_waiting_correlation_for_markov_chain IS 'получить текущее значение коэффициента корреляции для цепи маркова на окне 1 час ';
