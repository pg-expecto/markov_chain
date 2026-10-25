--------------------------------------------------------------------------------
-- core_cluster_functions.sql
-- version 19.1
--------------------------------------------------------------------------------
-- Статистика производительности по кластеру
--
-- cluster_stat_median Текущие метрики оценки производительности
--
-- performance_metrics      Расчитать метрики оценки производительности  
-- start_incident 			Начать инцидент производительности приоритет с заданным приоритетов
-- stop_incidents           Завершить инциденты производительности 

--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
--Текущие метрики оценки производительности
CREATE OR REPLACE FUNCTION cluster_stat_median() RETURNS integer 
AS $$
DECLARE
  current_calls numeric ; 
  current_rows numeric ; 
  
  current_calls_long  numeric ; 
  current_rows_long  numeric ; 
  
  curr_operating_speed_long  numeric ; 
  curr_waiting_events_long  numeric ; 
    
  --------------------------------------------
  -- ОЖИДАНИЯ  
  bufferpin_long numeric ;
  extension_long numeric ;
  io_long numeric ;
  ipc_long numeric ;
  lock_long numeric ;
  lwlock_long numeric ;
  timeout_long numeric ;
  
  current_bufferpin  bigint  ;
  current_extension  bigint  ;
  current_io  bigint  ;
  current_ipc  bigint  ;
  current_lock  bigint  ;
  current_lwlock  bigint  ;
  current_timeout  bigint  ;  
  wait_stats_rec	record ;
  -- ОЖИДАНИЯ
  --------------------------------------------
  
  --------------------------------------------
  -- Чтение/Запись разделяемых блоков
  current_shared_blks_hit bigint ;
  current_shared_blks_read bigint ;
  current_shared_blks_dirtied bigint ;
  current_shared_blks_written bigint ; 
  current_shared_blk_read_time double precision ;
  current_shared_blk_write_time double precision;
  
  shared_blks_hit_long numeric ;
  shared_blks_read_long numeric ;
  shared_blks_dirtied_long numeric ;
  shared_blks_written_long numeric ;
  shared_blk_read_time_long numeric ;
  shared_blk_write_time_long numeric ;
  
  shared_blk_rec record ; 
  -- Чтение/Запись разделяемых блоков
  --------------------------------------------
  
	
	max_timestamp timestamptz ; 
	

	
BEGIN	
	SELECT 	date_trunc( 'minute' , CURRENT_TIMESTAMP ) 
	INTO 		max_timestamp ;
		
RAISE NOTICE '-- ТЕКУЩИЕ ЗНАЧЕНИЯ';	
-------------------------------------------------------------------------------------------------------------------------
-- ТЕКУЩИЕ ЗНАЧЕНИЯ
    ---------------------------------------------------------------
	-- ОПЕРАЦИОННАЯ СКОРОСТЬ
	SELECT 
		SUM ( st.calls )
	INTO 
		current_calls
	FROM 
		pg_stat_statements st JOIN pg_database pd ON ( pd.oid = st.dbid )
	WHERE 
	    st.toplevel AND  --True, если данный запрос выполнялся на верхнем уровне (всегда true, если для параметра pg_stat_statements.track задано значение top)
		pd.datname NOT IN ('postgres' , 'template1' , 'template0' , 'pgpropwr' , 'expecto_db' ) ;
	IF current_calls IS NULL THEN current_calls = 0 ; END IF ;

	SELECT SUM ( st.rows )
	INTO current_rows
	FROM 
		pg_stat_statements st JOIN pg_database pd ON ( pd.oid = st.dbid )
	WHERE 
	    st.toplevel AND  --True, если данный запрос выполнялся на верхнем уровне (всегда true, если для параметра pg_stat_statements.track задано значение top)
		pd.datname NOT IN ('postgres' , 'template1' , 'template0' , 'pgpropwr' , 'expecto_db' ) ;
	IF current_rows IS NULL THEN current_rows = 0 ; END IF ;
	-- ОПЕРАЦИОННАЯ СКОРОСТЬ
	---------------------------------------------------------------

	---------------------------------------------------------------
	-- ОЖИДАНИЯ		
	FOR wait_stats_rec IN 
	SELECT w.event_type , SUM( w.count ) AS  event_type_count
	FROM pg_wait_sampling_profile w 
		JOIN pg_stat_statements st ON (st.queryid = w.queryid) 
		JOIN pg_database pd ON ( st.dbid = pd.oid )
	WHERE 
	    st.toplevel AND  --True, если данный запрос выполнялся на верхнем уровне (всегда true, если для параметра pg_stat_statements.track задано значение top)
		w.event_type IS NOT NULL AND w.event_type NOT IN ('Activity' , 'Client') AND 
		pd.datname NOT IN ('postgres' , 'template1' , 'template0' , 'pgpropwr' , 'expecto_db' ) 
	GROUP BY w.event_type	
	LOOP
		CASE 
			WHEN wait_stats_rec.event_type = 'BufferPin' THEN current_bufferpin = COALESCE( wait_stats_rec.event_type_count , 0 );
			WHEN wait_stats_rec.event_type = 'Extension' THEN current_extension = COALESCE( wait_stats_rec.event_type_count , 0 );
			WHEN wait_stats_rec.event_type = 'IO' THEN current_io = COALESCE( wait_stats_rec.event_type_count , 0 );
			WHEN wait_stats_rec.event_type = 'IPC' THEN current_ipc = COALESCE( wait_stats_rec.event_type_count , 0 );
			WHEN wait_stats_rec.event_type = 'Lock' THEN current_lock = COALESCE( wait_stats_rec.event_type_count , 0 );
			WHEN wait_stats_rec.event_type = 'LWLock' THEN current_lwlock = COALESCE( wait_stats_rec.event_type_count , 0 );
			WHEN wait_stats_rec.event_type = 'Timeout' THEN current_timeout = COALESCE( wait_stats_rec.event_type_count , 0 );
		END CASE ;		
	END LOOP;
	-- ОЖИДАНИЯ		
	---------------------------------------------------------------
	
	---------------------------------------------------------------
    -- Чтение/Запись разделяемых блоков
	SELECT 
		SUM(shared_blks_hit ) AS sum_shared_blks_hit ,
		SUM(shared_blks_read ) AS sum_shared_blks_read ,
		SUM(shared_blks_dirtied ) AS sum_shared_blks_dirtied ,
		SUM(shared_blks_written ) AS sum_shared_blks_written ,
		SUM(shared_blk_read_time ) AS sum_shared_blk_read_time ,
		SUM(shared_blk_write_time ) AS sum_shared_blk_write_time 
	INTO 
		shared_blk_rec
	FROM 
		pg_stat_statements st JOIN pg_database pd ON ( pd.oid = st.dbid )
	WHERE 
	    st.toplevel AND  --True, если данный запрос выполнялся на верхнем уровне (всегда true, если для параметра pg_stat_statements.track задано значение top)
		pd.datname NOT IN ('postgres' , 'template1' , 'template0' , 'pgpropwr' , 'expecto_db' );
	-- Чтение/Запись разделяемых блоков
	---------------------------------------------------------------

	INSERT INTO cluster_stat
	(
		curr_timestamp  , 
		curr_calls ,
		curr_rows ,
		curr_bufferpin  ,
		curr_extension  ,
		curr_io  ,
		curr_ipc  ,
		curr_lock  ,
		curr_lwlock ,
		curr_timeout , 
		curr_shared_blks_hit , 
		curr_shared_blks_read , 
		curr_shared_blks_dirtied, 
		curr_shared_blks_written, 
		curr_shared_blk_read_time ,
		curr_shared_blk_write_time
	)
	VALUES 
	( 
		max_timestamp , 
		current_calls , 
		current_rows , 
		current_bufferpin  ,
		current_extension  ,
		current_io    ,
		current_ipc   ,
		current_lock  ,
		current_lwlock ,
		current_timeout ,
		shared_blk_rec.sum_shared_blks_hit,
		shared_blk_rec.sum_shared_blks_read,
		shared_blk_rec.sum_shared_blks_dirtied,
		shared_blk_rec.sum_shared_blks_written,
		shared_blk_rec.sum_shared_blk_read_time,
		shared_blk_rec.sum_shared_blk_write_time 
	);		
-- ТЕКУЩИЕ ЗНАЧЕНИЯ	
-------------------------------------------------------------------------------------------------------------------------

-----------------------------------------------------------------------------------
-- МЕДИАНЫ 
	-----------------------------------------------------------------------------
	-- ОПЕРАЦИОННАЯ СКОРОСТЬ
	--Долгая медиана calls	
	SELECT (percentile_cont(0.5) within group (order by curr_calls))::numeric
	INTO current_calls_long
	FROM cluster_stat
	WHERE curr_timestamp BETWEEN max_timestamp - (interval '60 minute') AND max_timestamp ;	
	IF current_calls_long IS NULL THEN current_calls_long = 0 ; END IF ;	
	
	--Долгая медиана rows
	SELECT (percentile_cont(0.5) within group (order by curr_rows))::numeric
	INTO current_rows_long
	FROM cluster_stat
	WHERE curr_timestamp BETWEEN max_timestamp - (interval '60 minute') AND max_timestamp ;	
	IF current_rows_long IS NULL THEN current_rows_long = 0 ; END IF ;	
	-- ОПЕРАЦИОННАЯ СКОРОСТЬ
	-----------------------------------------------------------------------------
	
	---------------------------------------------------------------------
	-- ОЖИДАНИЯ
	-- Долгая медиана по wait_event_type
	SELECT (percentile_cont(0.5) within group (order by curr_bufferpin))::numeric
	INTO bufferpin_long
	FROM cluster_stat
	WHERE curr_timestamp BETWEEN max_timestamp - (interval '60 minute') AND max_timestamp ;	
	IF bufferpin_long IS NULL THEN bufferpin_long = 0 ; END IF ; 
	
	SELECT (percentile_cont(0.5) within group (order by curr_extension))::numeric
	INTO extension_long
	FROM cluster_stat
	WHERE curr_timestamp BETWEEN max_timestamp - (interval '60 minute') AND max_timestamp ;	
	IF extension_long IS NULL THEN extension_long = 0 ; END IF ; 

	SELECT (percentile_cont(0.5) within group (order by curr_io))::numeric
	INTO io_long
	FROM cluster_stat
	WHERE curr_timestamp BETWEEN max_timestamp - (interval '60 minute') AND max_timestamp ;	
	IF io_long IS NULL THEN io_long = 0 ; END IF ; 
		
	SELECT (percentile_cont(0.5) within group (order by curr_ipc))::numeric
	INTO ipc_long
	FROM cluster_stat
	WHERE curr_timestamp BETWEEN max_timestamp - (interval '60 minute') AND max_timestamp ;	
	IF ipc_long IS NULL THEN ipc_long = 0 ; END IF ; 

	SELECT (percentile_cont(0.5) within group (order by curr_lock))::numeric
	INTO lock_long
	FROM cluster_stat
	WHERE curr_timestamp BETWEEN max_timestamp - (interval '60 minute') AND max_timestamp ;	
	IF lock_long IS NULL THEN lock_long = 0 ; END IF ; 

	SELECT (percentile_cont(0.5) within group (order by curr_lwlock))::numeric
	INTO lwlock_long
	FROM cluster_stat
	WHERE curr_timestamp BETWEEN max_timestamp - (interval '60 minute') AND max_timestamp ;	
	IF lwlock_long IS NULL THEN lwlock_long = 0 ; END IF ; 
	
	SELECT (percentile_cont(0.5) within group (order by curr_timeout))::numeric
	INTO timeout_long
	FROM cluster_stat
	WHERE curr_timestamp BETWEEN max_timestamp - (interval '60 minute') AND max_timestamp ;	
	IF timeout_long IS NULL THEN timeout_long = 0 ; END IF ; 	
	
	-- Чтение/Запись разделяемых блоков
	SELECT (percentile_cont(0.5) within group (order by curr_shared_blks_hit))::numeric
	INTO shared_blks_hit_long
	FROM cluster_stat
	WHERE curr_timestamp BETWEEN max_timestamp - (interval '60 minute') AND max_timestamp ;	
	IF shared_blks_hit_long IS NULL THEN shared_blks_hit_long = 0 ; END IF ; 	
	
	SELECT (percentile_cont(0.5) within group (order by curr_shared_blks_read))::numeric
	INTO shared_blks_read_long
	FROM cluster_stat
	WHERE curr_timestamp BETWEEN max_timestamp - (interval '60 minute') AND max_timestamp ;	
	IF shared_blks_read_long IS NULL THEN shared_blks_read_long = 0 ; END IF ; 	
	
	SELECT (percentile_cont(0.5) within group (order by curr_shared_blks_dirtied))::numeric
	INTO shared_blks_dirtied_long
	FROM cluster_stat
	WHERE curr_timestamp BETWEEN max_timestamp - (interval '60 minute') AND max_timestamp ;	
	IF shared_blks_dirtied_long IS NULL THEN shared_blks_dirtied_long = 0 ; END IF ; 	
	
	SELECT (percentile_cont(0.5) within group (order by curr_shared_blks_written))::numeric
	INTO shared_blks_written_long
	FROM cluster_stat
	WHERE curr_timestamp BETWEEN max_timestamp - (interval '60 minute') AND max_timestamp ;	
	IF shared_blks_written_long IS NULL THEN shared_blks_written_long = 0 ; END IF ; 	
	
	SELECT (percentile_cont(0.5) within group (order by curr_shared_blk_read_time))::numeric
	INTO shared_blk_read_time_long
	FROM cluster_stat
	WHERE curr_timestamp BETWEEN max_timestamp - (interval '60 minute') AND max_timestamp ;	
	IF shared_blk_read_time_long IS NULL THEN shared_blk_read_time_long = 0 ; END IF ; 	
	
	SELECT (percentile_cont(0.5) within group (order by curr_shared_blk_write_time))::numeric
	INTO shared_blk_write_time_long
	FROM cluster_stat
	WHERE curr_timestamp BETWEEN max_timestamp - (interval '60 minute') AND max_timestamp ;	
	IF shared_blk_write_time_long IS NULL THEN shared_blk_write_time_long = 0 ; END IF ; 	
-- МЕДИАНЫ 
-----------------------------------------------------------------------------------

-------------------------------------------------------------------------------------------------------------------------
-- РАСЧЕТ МЕТРИК ПРОИЗВОДИТЕЛЬНОСТИ	
	-- ОПЕРАЦИОННАЯ СКОРОСТЬ 
		curr_operating_speed_long =  ( current_calls_long + current_rows_long  )  ;
	-- ОПЕРАЦИОННАЯ СКОРОСТЬ 
	
	-- ОЖИДАНИЯ  
		curr_waiting_events_long = bufferpin_long + extension_long +  io_long + ipc_long + lock_long + lwlock_long + timeout_long; 
	-- ОЖИДАНИЯ  
	
-- РАСЧЕТ МЕТРИК ПРОИЗВОДИТЕЛЬНОСТИ 	
-------------------------------------------------------------------------------------------------------------------------

-- СОХРАНИТЬ СТАТИСТИКУ
INSERT INTO cluster_stat_median 
	(
		curr_timestamp, 
		curr_op_speed ,		
		curr_waitings ,
		curr_bufferpin  ,
		curr_extension ,
		curr_io  ,
		curr_ipc  ,
		curr_lock  ,
		curr_lwlock ,  
		curr_timeout ,
		curr_shared_blks_hit ,
		curr_shared_blks_read ,
		curr_shared_blks_dirtied ,
		curr_shared_blks_written ,
		curr_shared_blk_read_time ,
		curr_shared_blk_write_time
	)
	VALUES 
	(
		max_timestamp , 
		curr_operating_speed_long , 		
		curr_waiting_events_long , 		
		bufferpin_long ,
		extension_long ,
		io_long ,
		ipc_long ,
		lock_long ,
		lwlock_long ,
		timeout_long ,
		shared_blks_hit_long ,
		shared_blks_read_long ,
		shared_blks_dirtied_long ,
		shared_blks_written_long ,
		shared_blk_read_time_long ,
		shared_blk_write_time_long 
	);
-- СОХРАНИТЬ СТАТИСТИКУ
----------------------------------------------------------------------------

return 0 ; 

END
$$ LANGUAGE plpgsql; 
COMMENT ON FUNCTION cluster_stat_median IS 'Очистка старых статистических данных.';
--Текущие метрики оценки производительности
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
--Расчитать метрики оценки производительности  
CREATE OR REPLACE FUNCTION performance_metrics() RETURNS text AS $$
DECLARE
 result_str text;
 timepoint timestamptz ;
 cluster_stat_median_rec record ;
 
 speed_waitings_correlation DOUBLE PRECISION ;

 regr_slope_value DOUBLE PRECISION;

 speed_degradation_indicator integer ;

 speed_regr_slope_value DOUBLE PRECISION;
 waitings_regr_slope_value DOUBLE PRECISION;

 speed_regr_rec record;
 waitings_regr_rec record;
 
 is_markov_chain_enabled_flag BOOLEAN;

BEGIN
	SELECT MAX(curr_timestamp)
	INTO timepoint 
	FROM cluster_stat_median ; 
	
	
	SELECT 	
		COALESCE ( curr_op_speed , 0 ) AS curr_op_speed , 			
		COALESCE ( curr_waitings , 0 ) AS curr_waitings	
	INTO 	
		cluster_stat_median_rec
	FROM 	
		cluster_stat_median 
	WHERE 	
		curr_timestamp = timepoint ; 
	
	
	-------------------------------------------------------------------
	--КОРРЕЛЯЦИЯ СКОРОСТЬ - ОЖИДАНИЯ
	SELECT COALESCE( corr( curr_op_speed ,  curr_waitings ) , 0 ) AS correlation_value 
	INTO speed_waitings_correlation
	FROM
		 cluster_stat_median
	WHERE 
		curr_timestamp BETWEEN timepoint - interval '1 hour' AND timepoint ; 
	--КОРРЕЛЯЦИЯ АКТИВНЫЕ СЕССИИ - СКОРОСТЬ 
	-------------------------------------------------------------------
	DROP TABLE IF EXISTS tmp_timepoints;
	CREATE TEMPORARY TABLE tmp_timepoints
	(
		curr_timestamp timestamptz  ,   
		curr_timepoint integer 
	);


	INSERT INTO tmp_timepoints
	(
		curr_timestamp ,	
		curr_timepoint 
	)
	SELECT 
		curr_timestamp , 
		row_number() over (order by curr_timestamp) AS x
	FROM
	cluster_stat_median
	WHERE 
		curr_timestamp BETWEEN timepoint - interval '1 hour' AND timepoint 
	ORDER BY curr_timestamp	;

	----------------------------------------------------------------------------------------------------
	-- ОПЕРАЦИОННАЯ СКОРОСТЬ
    -- 	линия регрессии  скорости  : Y = a + bX
	BEGIN
		WITH stats AS 
		(
		  SELECT 
			AVG(t.curr_timepoint::DOUBLE PRECISION) as avg1, 
			STDDEV(t.curr_timepoint::DOUBLE PRECISION) as std1,
			AVG(s.curr_op_speed::DOUBLE PRECISION) as avg2, 
			STDDEV(s.curr_op_speed::DOUBLE PRECISION) as std2
		  FROM
			cluster_stat_median s JOIN tmp_timepoints t ON ( s.curr_timestamp  = t.curr_timestamp )
		  WHERE 
			t.curr_timestamp BETWEEN timepoint - interval '1 hour' AND timepoint 
		),
		standardized_data AS 
		(
			SELECT 
				(t.curr_timepoint::DOUBLE PRECISION - avg1) / std1 as x_z,
				(s.curr_op_speed::DOUBLE PRECISION - avg2) / std2 as y_z
			FROM
				cluster_stat_median s JOIN tmp_timepoints t ON ( s.curr_timestamp  = t.curr_timestamp ) , stats
			WHERE 
				t.curr_timestamp BETWEEN timepoint - interval '1 hour' AND timepoint  
		)	
		SELECT
			REGR_SLOPE(y_z, x_z) as slope, --b
			ATAN(REGR_SLOPE(y_z, x_z)) * 180 / PI() as slope_angle_degrees, --угол наклона
			REGR_R2(y_z, x_z) as r_squared -- Коэффициент детерминации
		INTO 
			speed_regr_rec
		FROM standardized_data;
	EXCEPTION
	  --STDDEV(s.curr_op_speed::DOUBLE PRECISION) = 0  
	  WHEN division_by_zero THEN  -- Конкретное исключение для деления на ноль
	    SELECT 
			1.0 as slope, --b
			0.0  as slope_angle_degrees, --угол наклона
			0.0  as r_squared -- Коэффициент детерминации
		INTO 
		speed_regr_rec ;
	END;
	speed_regr_slope_value = speed_regr_rec.slope_angle_degrees ; 	
	-- 	линия регрессии  скорости  : Y = a + bX
	-- ОПЕРАЦИОННАЯ СКОРОСТЬ
	-------------------------------------------------------------------
	
	----------------------------------------------------------------------------------------------------
	-- ОЖИДАНИЯ
    -- 	линия регрессии  скорости  : Y = a + bX
	BEGIN 
		WITH stats AS 
		(
		  SELECT 
			AVG(t.curr_timepoint::DOUBLE PRECISION) as avg1, 
			STDDEV(t.curr_timepoint::DOUBLE PRECISION) as std1,
			AVG(s.curr_waitings::DOUBLE PRECISION) as avg2, 
			STDDEV(s.curr_waitings::DOUBLE PRECISION) as std2
		  FROM
			cluster_stat_median s JOIN tmp_timepoints t ON ( s.curr_timestamp  = t.curr_timestamp )
		  WHERE 
			t.curr_timestamp BETWEEN timepoint - interval '1 hour' AND timepoint  
		),
		standardized_data AS 
		(
			SELECT 
				(t.curr_timepoint::DOUBLE PRECISION - avg1) / std1 as x_z,
				(s.curr_waitings::DOUBLE PRECISION - avg2) / std2 as y_z
			FROM
				cluster_stat_median s JOIN tmp_timepoints t ON ( s.curr_timestamp  = t.curr_timestamp ) , stats
			WHERE 
				t.curr_timestamp BETWEEN timepoint - interval '1 hour' AND timepoint  
		)	
		SELECT
			REGR_SLOPE(y_z, x_z) as slope, --b
			ATAN(REGR_SLOPE(y_z, x_z)) * 180 / PI() as slope_angle_degrees, --угол наклона
			REGR_R2(y_z, x_z) as r_squared -- Коэффициент детерминации
		INTO 
			waitings_regr_rec
		FROM standardized_data;
	EXCEPTION
	  --STDDEV(s.curr_waitings::DOUBLE PRECISION) = 0  
	  WHEN division_by_zero THEN  -- Конкретное исключение для деления на ноль
	    SELECT 
			1.0 as slope, --b
			0.0  as slope_angle_degrees, --угол наклона
			0.0  as r_squared -- Коэффициент детерминации
		INTO 
		waitings_regr_rec ;
	END;
	waitings_regr_slope_value = waitings_regr_rec.slope_angle_degrees ; 	
	-- 	линия регрессии  скорости  : Y = a + bX
	-- ОЖИДАНИЯ
	-------------------------------------------------------------------
	
	-- ЕСЛИ 
	--  угол наклона линии скорости < 0 
	-- И 
	--  угол наклона линии ожиданий > 0 
	-- ТО деградация

	IF speed_regr_slope_value < 0 
	   AND 
	   waitings_regr_slope_value > 0 
	THEN		
		--Слабая и умеренная корреляция
		IF ABS(speed_waitings_correlation) < 0.7 AND SIGN(speed_waitings_correlation) = -1 
		THEN 
			speed_degradation_indicator = -50 ;
			CALL start_incident(4);
		END IF ;
		
		--Сильная корреляция
		IF ABS(speed_waitings_correlation) >= 0.7 AND SIGN(speed_waitings_correlation) = -1 
		THEN 
			speed_degradation_indicator = -100 ;
			CALL start_incident(3);
		END IF ;
	ELSE
		speed_degradation_indicator = 0 ;
		CALL stop_incidents();
	END IF ;
	--version 27.0
	-------------------------------------------------------------------
	
	
    -- операционная скорость | ожидания |  индикатор 
	result_str= ROUND( cluster_stat_median_rec.curr_op_speed::numeric , 2 )||'|'||  --1
				ROUND( cluster_stat_median_rec.curr_waitings::numeric , 2 )||'|'||  --2
				speed_degradation_indicator ||'|'  --3
				;
	
	
    --------------------------------------------------------------------------------------------------------
	--	ОБУЧЕНИЕ ЦЕПИ МАРКОВА
	SELECT is_markov_chain_enabled
	INTO is_markov_chain_enabled_flag
	FROM configuration
	LIMIT 1 ;
	
	IF is_markov_chain_enabled_flag
	THEN 
		PERFORM mchain_train_step();
	END IF;
	--	ОБУЧЕНИЕ ЦЕПИ МАРКОВА
	--------------------------------------------------------------------------------------------------------
	
	
	return result_str;
END
$$ LANGUAGE plpgsql  ;
COMMENT ON FUNCTION performance_metrics IS 'Расчитать метрики оценки производительности ';
-- Расчитать метрики оценки производительности 
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Завершить инциденты производительности 
CREATE OR REPLACE PROCEDURE stop_incidents() AS $$
DECLARE 
  timepoint timestamp with time zone ;   
BEGIN
	SELECT date_trunc( 'minute' , CURRENT_TIMESTAMP )
	INTO timepoint ;

	-------------------------------
	-- Закрыть инциденты 
	UPDATE performance_incident
	SET finish_timepoint = timepoint 
	WHERE finish_timepoint IS NULL  ; 
	-- Закрыть инциденты 
	-------------------------------	
	
	-------------------------------
	-- Закрыть инцидент цепи Маркова
	UPDATE markov_chain_performance_incident
	SET finish_timepoint = timepoint 
	WHERE finish_timepoint IS NULL  ; 
	-- Закрыть инцидент цепи Маркова
	-------------------------------	
END 
$$ LANGUAGE plpgsql ;
COMMENT ON PROCEDURE  stop_incidents IS 'Завершить инциденты производительности';
-- Завершить инциденты производительности 
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Начать инцидент производительности приоритет с заданным приоритетов 
CREATE OR REPLACE PROCEDURE start_incident( curr_priority integer ) 
AS $$
DECLARE 
  p_count integer ;
  p_count4chain integer ;
BEGIN
	SELECT 
		count(id)
	INTO 
		p_count
	FROM 
		performance_incident
	WHERE
		priority = curr_priority AND 
		finish_timepoint IS NULL ; 

	
	--Новый инцидент
	IF p_count = 0 
	THEN 
		INSERT INTO performance_incident
		(
			priority ,
			start_timepoint
		)
		VALUES 
		( 
			curr_priority , 
			date_trunc( 'minute' , CURRENT_TIMESTAMP )
		);	
	END IF ; 
	
	--------------------------------------------------
	--Новый инцидент цепи Маркова
	SELECT 
		count(id)
	INTO 
		p_count4chain
	FROM 
		markov_chain_performance_incident
	WHERE
		finish_timepoint IS NULL ; 

	
	--Новый инцидент
	IF p_count4chain = 0 
	THEN 
		INSERT INTO markov_chain_performance_incident
		(
			start_timepoint
		)
		VALUES 
		( 
			date_trunc( 'minute' , CURRENT_TIMESTAMP )
		);	
	END IF ; 

	--Новый инцидент цепи Маркова
	--------------------------------------------------
END 
$$ LANGUAGE plpgsql ;
COMMENT ON PROCEDURE  start_incident IS 'Начать инцидент производительности приоритет с заданным приоритетов';
-- Начать инцидент производительности приоритет с заданным приоритетов
--------------------------------------------------------------------------------




