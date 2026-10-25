--------------------------------------------------------------------------------
-- core_cluster_tables.sql
-- version 19.1
--------------------------------------------------------------------------------
--Статистика уровня кластера 
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
--Текущая статистика
DROP TABLE IF EXISTS cluster_stat;
CREATE UNLOGGED TABLE cluster_stat 
(
  	id SERIAL , 	
	curr_timestamp timestamp with time zone , 

	curr_calls bigint,
	curr_rows bigint,
	
	curr_bufferpin  bigint,
	curr_extension  bigint,
	curr_io  bigint,
	curr_ipc  bigint,
	curr_lock  bigint,
	curr_lwlock bigint,
	curr_timeout bigint , 
	
	curr_shared_blks_hit  bigint , 
	curr_shared_blks_read  bigint , 
	curr_shared_blks_dirtied bigint , 
	curr_shared_blks_written bigint , 
	--если включён track_io_timing, иначе ноль
	curr_shared_blk_read_time double precision ,
	curr_shared_blk_write_time double precision
	--если включён track_io_timing, иначе ноль
);
ALTER TABLE cluster_stat ADD CONSTRAINT cluster_stat_pk PRIMARY KEY (id);
CREATE INDEX cluster_stat_idx ON cluster_stat ( curr_timestamp );

COMMENT ON TABLE cluster_stat IS 'Исходные данные для расчетов метрик оценки производительности и ожиданий';
COMMENT ON COLUMN cluster_stat.curr_timestamp IS 'Точка времени сбора данных ';
COMMENT ON COLUMN cluster_stat.curr_calls IS 'Число выполнений';
COMMENT ON COLUMN cluster_stat.curr_rows IS 'Общее число строк, полученных или затронутых оператором';
COMMENT ON COLUMN cluster_stat.curr_bufferpin IS 'Количество ожиданий типа BufferPin';
COMMENT ON COLUMN cluster_stat.curr_extension IS 'Количество ожиданий типа Extension';
COMMENT ON COLUMN cluster_stat.curr_io IS 'Количество ожиданий типа IO';
COMMENT ON COLUMN cluster_stat.curr_ipc IS 'Количество ожиданий типа IPC';
COMMENT ON COLUMN cluster_stat.curr_lock IS 'Количество ожиданий типа Lock';
COMMENT ON COLUMN cluster_stat.curr_lwlock IS 'Количество ожиданий типа LWLock';
COMMENT ON COLUMN cluster_stat.curr_timeout IS 'Количество ожиданий типа Timeout';
COMMENT ON COLUMN cluster_stat.curr_shared_blks_hit IS 'Общее число попаданий разделяемых блоков в кеш';
COMMENT ON COLUMN cluster_stat.curr_shared_blks_read IS 'Общее число прочитанных разделяемых блоков';
COMMENT ON COLUMN cluster_stat.curr_shared_blks_dirtied IS 'Общее число загрязнённых разделяемых блоков';
COMMENT ON COLUMN cluster_stat.curr_shared_blks_written IS 'Общее число записанных разделяемых блоков';
COMMENT ON COLUMN cluster_stat.curr_shared_blk_read_time IS 'Общее время на чтение разделяемых блоков';
COMMENT ON COLUMN cluster_stat.curr_shared_blk_write_time IS 'Общее время на запись разделяемых блоков';
--Текущая статистика
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
--Скользящие медианы
DROP TABLE IF EXISTS cluster_stat_median;
CREATE TABLE cluster_stat_median 
(
	id SERIAL , 
	curr_timestamp timestamp with time zone , 
	
	curr_op_speed numeric ,
	curr_waitings numeric ,		

	curr_bufferpin  numeric,
	curr_extension  numeric,
	curr_io  numeric,
	curr_ipc  numeric,
	curr_lock  numeric,
	curr_lwlock numeric , 
	curr_timeout numeric , 
	
	curr_shared_blks_hit numeric , 
	curr_shared_blks_read numeric , 
	curr_shared_blks_dirtied numeric , 
	curr_shared_blks_written numeric , 
	--если включён track_io_timing, иначе ноль
	curr_shared_blk_read_time double precision ,
	curr_shared_blk_write_time double precision
	--если включён track_io_timing, иначе ноль
);
ALTER TABLE cluster_stat_median ADD CONSTRAINT cluster_stat_median_pk PRIMARY KEY (id);
CREATE INDEX cluster_stat_median_idx ON cluster_stat_median ( curr_timestamp );

COMMENT ON TABLE cluster_stat_median IS 'Скользящие медианы метрик оценки производительности и ожиданий';
COMMENT ON COLUMN cluster_stat_median.curr_timestamp IS 'Точка времени сбора данных ';
COMMENT ON COLUMN cluster_stat_median.curr_op_speed IS 'Медиана операционной скорости';
COMMENT ON COLUMN cluster_stat_median.curr_waitings IS 'Медиана ожиданий';
COMMENT ON COLUMN cluster_stat_median.curr_bufferpin IS 'Медиана количества  ожиданий типа BufferPin';
COMMENT ON COLUMN cluster_stat_median.curr_extension IS 'Медиана количества  ожиданий типа Extension';
COMMENT ON COLUMN cluster_stat_median.curr_io IS 'Медиана количества  ожиданий типа IO';
COMMENT ON COLUMN cluster_stat_median.curr_ipc IS 'Медиана количества  ожиданий типа IPC';
COMMENT ON COLUMN cluster_stat_median.curr_lock IS 'Медиана количества  ожиданий типа Lock';
COMMENT ON COLUMN cluster_stat_median.curr_lwlock IS 'Медиана количества  ожиданий типа LWLock';
COMMENT ON COLUMN cluster_stat_median.curr_timeout IS 'Медиана количества  ожиданий типа Timeout';
COMMENT ON COLUMN cluster_stat_median.curr_shared_blks_hit IS 'Общее число попаданий разделяемых блоков в кеш';
COMMENT ON COLUMN cluster_stat_median.curr_shared_blks_read IS 'Общее число прочитанных разделяемых блоков';
COMMENT ON COLUMN cluster_stat_median.curr_shared_blks_dirtied IS 'Общее число загрязнённых разделяемых блоков';
COMMENT ON COLUMN cluster_stat_median.curr_shared_blks_written IS 'Общее число записанных разделяемых блоков';
COMMENT ON COLUMN cluster_stat_median.curr_shared_blk_read_time IS 'Общее время на чтение разделяемых блоков';
COMMENT ON COLUMN cluster_stat_median.curr_shared_blk_write_time IS 'Общее время на запись разделяемых блоков';
--Скользящие медианы
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Инциденты производительности
DROP TABLE IF EXISTS performance_incident ;
CREATE TABLE performance_incident 
(
	id BIGSERIAL ,
	priority smallint , 
	
	start_timepoint timestamptz , 
	finish_timepoint timestamptz 
);
--------------------------------------------------------------------------------
ALTER TABLE performance_incident ADD CONSTRAINT performance_incident_pk PRIMARY KEY (id);
CREATE INDEX performance_incident_idx1 ON performance_incident ( start_timepoint );
CREATE INDEX performance_incident_idx_priority ON performance_incident (id) WHERE finish_timepoint IS NULL;

-- Инциденты производительности
--------------------------------------------------------------------------------

