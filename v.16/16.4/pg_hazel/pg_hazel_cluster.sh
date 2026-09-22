#!/bin/sh
# pg_hazel_cluster.sh
# Уровень кластера(СУБД)
# mkdir /postgres/scripts/tester
# Tester
# */1 * * * * /postgres/scripts/tester/pg_hazel_cluster.sh


 
#Обработать код возврата 
function exit_code {
ecode=$1
if [[ $ecode != 0 ]];
then
	ecode=$1
	LOG_FILE=$2
	ERR_FILE=$3
	
	echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : ERROR : Details in '$ERR_FILE
	echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : ERROR : Details in '$ERR_FILE >> $LOG_FILE
	
	#################################################
	# Опустить флаг
	rm /postgres/scripts/tester/PG_HAZEL_CLUSTER_IN_PROGRESS
	#################################################
	
    exit $ecode
fi
}


#################################################
# Если флаг поднят - выход
if [ -f /postgres/scripts/tester/PG_HAZEL_CLUSTER_IN_PROGRESS ]; 
then
  exit 0
fi
#################################################


script=$(readlink -f $0)
current_path=`dirname $script`
timestamp_label=$(date "+%Y%m%d")'T'$(date "+%H%M")


performance_monitoring_db='performance_monitoring_db'
performance_monitoring_user='performance_monitoring_user'

LOG_FILE=$current_path'/pg_hazel_cluster.log'
ERR_FILE=$current_path'/pg_hazel_cluster.err'
REPORT_DIR='/tmp/bb'

#################################################
# Поднять флаг
touch /postgres/scripts/tester/PG_HAZEL_CLUSTER_IN_PROGRESS
#################################################

echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : START '
echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : START '> $LOG_FILE


#######################################################################
# Определить роль сервера СУБД
is_recovery=`psql -Aqtc 'SELECT pg_is_in_recovery()' 2>>$LOG_FILE`
echo "is_recovery="$is_recovery
echo "is_recovery="$is_recovery  >> $LOG_FILE
#if [ $? -ne 0 ]
#then
#  ##################################################################### 
#  #ОШИБКА СУБД  
#  echo 'ERROR : PostgreSQL ERROR : pg_is_in_recovery TERMINATED WITH ERROR '
#  echo 'ERROR : PostgreSQL ERROR : pg_is_in_recovery TERMINATED WITH ERROR ' >> $LOG_FILE
#  exit 1000
#  #####################################################################
#fi

if [ "$is_recovery" == 't' ]
then
  echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : REPLICATION NODE - reset performance metrics '
  echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : REPLICATION NODE - reset performance metrics '>> $LOG_FILE
  

  echo '0' >  /tmp/response_time.txt --not supported
  echo '0' >  /tmp/db_time.txt ----not found
  echo '0' >  /tmp/tps.txt -- Enabled 
  echo '0' >  /tmp/qps.txt
  echo '0' >  /tmp/rps.txt
  echo '0' >  /tmp/pages_wfs.txt
  echo '0' >  /tmp/pages_rfs.txt
  echo '0' >  /tmp/pages_dfs.txt
  echo '0' >  /tmp/pages_loc_wfs.txt
  echo '0' >  /tmp/pages_loc_rfs.txt
  echo '0' >  /tmp/pages_loc_dfs.txt
  echo '0' >  /tmp/pages_tmp_wfs.txt
  echo '0' >  /tmp/pages_tmp_rfs.txt  
  echo '0' >  /tmp/cpi.txt  

#####################################################
# PG_HAZEL METRICS 
	#SHORT SPEED
	echo '0' >  /tmp/cpi_ma_10m.txt 
	
	#LONG SPEED
	echo '0' >  /tmp/cpi_ma_1h.txt		
# PG_HAZEL METRICS 
#####################################################	
	

  
  echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : FINISHED '
  echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : FINISHED '>> $LOG_FILE

  #################################################
  # Опустить флаг
  rm /postgres/scripts/tester/PG_HAZEL_CLUSTER_IN_PROGRESS
  #################################################

  exit 0 
fi

#######################################################
# Первоначальный сброс значений файлов метрик
  echo '0' >  /tmp/response_time.txt --not supported
  echo '0' >  /tmp/db_time.txt ----not found
  echo '0' >  /tmp/tps.txt -- Enabled 
  echo '0' >  /tmp/qps.txt
  echo '0' >  /tmp/rps.txt
  echo '0' >  /tmp/pages_wfs.txt
  echo '0' >  /tmp/pages_rfs.txt
  echo '0' >  /tmp/pages_dfs.txt
  echo '0' >  /tmp/pages_loc_wfs.txt
  echo '0' >  /tmp/pages_loc_rfs.txt
  echo '0' >  /tmp/pages_loc_dfs.txt
  echo '0' >  /tmp/pages_tmp_wfs.txt
  echo '0' >  /tmp/pages_tmp_rfs.txt  
  echo '0' >  /tmp/cpi.txt
# Первоначальный сброс значений файлов метрик
#######################################################





#########################################################################################################
# СБОР СТАТИСТИЧЕСКОЙ ИНФОРМАЦИИ О ПРОИЗВОДИТЕЛЬНОСТИ 
echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : START - COLLECT STATS  '
echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : START - COLLECT STATS  '>> $LOG_FILE

########################################################################################################

#DISABLED
#########################################################################################################
# СОБРАТЬ BENCHMARK SQL ДЛЯ КОТОРЫХ НАСТРОЕН МОНИТОРИНГ МЕДИАННОГО ВРЕМЕНИ ВЫПОЛНЕНИЯ 
#echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : BENCHMARKS MONITORING STARTED '
#echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : BENCHMARKS MONITORING STARTED '>> $LOG_FILE
#
#psql -d $performance_monitoring_db -U $performance_monitoring_user  -v ON_ERROR_STOP=on --echo-errors -Aqtc 'select benchmark_time_stats()'  >> $LOG_FILE 2>$ERR_FILE
#exit_code $? $LOG_FILE $ERR_FILE
#
#echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : BENCHMARKS MONITORING FINISHED'
#echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : BENCHMARKS MONITORING FINISHED'>> $LOG_FILE
# СОБРАТЬ BENCHMARK SQL ДЛЯ КОТОРЫХ НАСТРОЕН МОНИТОРИНГ МЕДИАННОГО ВРЕМЕНИ ВЫПОЛНЕНИЯ 
#########################################################################################################
#DISABLED

#########################################################################################################
current_minute=$(date "+%M")
echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : current_minute = '$current_minute
echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : current_minute = '$current_minute >> $LOG_FILE

pgpro_pwr_samples_count=`psql -d $performance_monitoring_db -U $performance_monitoring_user  -v ON_ERROR_STOP=on --echo-errors -Aqtc 'SELECT count(curr_timestamp) FROM pgpro_pwr_samples'` 2>$ERR_FILE
exit_code $? $LOG_FILE $ERR_FILE
echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : pgpro_pwr_samples_count = '$pgpro_pwr_samples_count
echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : pgpro_pwr_samples_count = '$pgpro_pwr_samples_count>> $LOG_FILE


#########################################################################################################
# СОБРАТЬ СТАТИСТИКУ ПО SQL 
if [ "$pgpro_pwr_samples_count" != "0" ]
then 
  echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : SQL PERFORMANCE MONITORING STARTED '
  echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : SQL PERFORMANCE MONITORING STARTED '>> $LOG_FILE
  psql -d $performance_monitoring_db -U $performance_monitoring_user  -v ON_ERROR_STOP=on --echo-errors -Aqtc "select save_source_stat_statement()" 2>$ERR_FILE
  exit_code $? $LOG_FILE $ERR_FILE
  echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : SQL PERFORMANCE MONITORING FINISHED'
  echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : SQL PERFORMANCE MONITORING FINISHED'>> $LOG_FILE
else
  echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : INFO : СНИМОК PGPRO_PWR - НЕ ПОДГОТОВЛЕН'
  echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : INFO : СНИМОК PGPRO_PWR - НЕ ПОДГОТОВЛЕН'>> $LOG_FILE 
fi
# СОБРАТЬ СТАТИСТИКУ ПО SQL 
#########################################################################################################


#########################################################################################################
# СОБРАТЬ СТАТИСТИКУ ПРОИЗВОДИТЕЛЬНОСТИ ПО КЛАСТЕРУ
if [ "$pgpro_pwr_samples_count" != "0" ]
then 
  echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : CLUSTER PERFORMANCE MONITORING STARTED '
  echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : CLUSTER PERFORMANCE MONITORING STARTED '>> $LOG_FILE
  
  check_pgpro_pwr_sample_for_current_timestamp=`psql -d $performance_monitoring_db -U $performance_monitoring_user  -v ON_ERROR_STOP=on --echo-errors -Aqtc 'select check_pgpro_pwr_sample_for_current_timestamp()' 2>$ERR_FILE`
  exit_code $? $LOG_FILE $ERR_FILE
  echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : check_pgpro_pwr_sample_for_current_timestamp = '$check_pgpro_pwr_sample_for_current_timestamp
  echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : check_pgpro_pwr_sample_for_current_timestamp = '$check_pgpro_pwr_sample_for_current_timestamp >> $LOG_FILE

  
  psql -d $performance_monitoring_db -U $performance_monitoring_user  -v ON_ERROR_STOP=on --echo-errors -Aqtc 'select pgh_stat_cluster()'  >> $LOG_FILE 2>$ERR_FILE
  exit_code $? $LOG_FILE $ERR_FILE
  echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : CLUSTER PERFORMANCE MONITORING FINISHED'
  echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : CLUSTER PERFORMANCE MONITORING FINISHED'>> $LOG_FILE
else
  echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : INFO : СНИМОК PGPRO_PWR - НЕ ПОДГОТОВЛЕН'
  echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : INFO : СНИМОК PGPRO_PWR - НЕ ПОДГОТОВЛЕН'>> $LOG_FILE 
fi
# СОБРАТЬ СТАТИСТИКУ ПРОИЗВОДИТЕЛЬНОСТИ ПО КЛАСТЕРУ
#########################################################################################################

#################################################
#Если тест не начат - формирование снимка каждые 10 минут 
# СБРОС СТАТИСТИКИ PGPRO_STATS
if [ ! -f /postgres/scripts/tester/stress_tester/TESTER_STARTED ]
then
 is_need_new_pgpro_pwr_snapshot=`psql -d $performance_monitoring_db -U $performance_monitoring_user  -v ON_ERROR_STOP=on --echo-errors -Aqtc 'select is_need_new_pgpro_pwr_snapshot()' 2>$ERR_FILE`
 exit_code $? $LOG_FILE $ERR_FILE
 
 echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : is_need_new_pgpro_pwr_snapshot = '$is_need_new_pgpro_pwr_snapshot
 echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : is_need_new_pgpro_pwr_snapshot = '$is_need_new_pgpro_pwr_snapshot >> $LOG_FILE

  if [ "$is_need_new_pgpro_pwr_snapshot" == "1" ]
  then
  	#################################################
	# NEW PGPRO_PWR SNAPSHOT
	echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : NEW PGPRO_PWR SAMPLE '
	echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : NEW PGPRO_PWR SAMPLE ' >> $LOG_FILE

	ERR_FILE_pgpro_pwr=$current_path'/pgpro_pwr_snapshot.err'
	$current_path'/'pgpro_pwr_snapshot.sh 2>$ERR_FILE_pgpro_pwr
	exit_code $? $LOG_FILE $ERR_FILE_pgpro_pwr	
	# NEW PGPRO_PWR SNAPSHOT
	#################################################
  fi 
fi
# СБРОС СТАТИСТИКИ PGPRO_STATS
#Если тест не начат - формирование снимка каждые 10 минут 
#########################################################################################################


#########################################################################################################
# СОБРАТЬ СТАТИСТИКУ VMSTAT
echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : VMSTAT PERFORMANCE MONITORING STARTED '
echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : VMSTAT PERFORMANCE MONITORING STARTED '>> $LOG_FILE

vmstat_string=`cat /postgres/scripts/tester/vmstat.log | tail -1 | sed -e "s/[[:space:]]\+/ /g" | sed 's/^[[:space:]]*//'`
echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : vmstat_string='$vmstat_string
echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : vmstat_string='$vmstat_string>> $LOG_FILE

#vmstat_string_length=${#vmstat_string}
#echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : vmstat_string_length='$vmstat_string_length
#echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : vmstat_string_length='$vmstat_string_length>> $LOG_FILE


#if [ "$vmstat_string_length" != "0" ]
#then 
  psql -d $performance_monitoring_db -U $performance_monitoring_user  -v ON_ERROR_STOP=on --echo-errors -Aqtc "select os_stat_vmstat( '$vmstat_string' )"  >> $LOG_FILE 2>$ERR_FILE
  exit_code $? $LOG_FILE $ERR_FILE
  
#  let line_count=`wc -l /postgres/scripts/tester/vmstat.log | awk -F " " '{print $1}'`
#  echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : vmstat_line_count='$line_count
#  echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : vmstat_line_count='$line_count>> $LOG_FILE
  
#fi

echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : VMSTAT PERFORMANCE MONITORING FINISHED'
echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : VMSTAT PERFORMANCE MONITORING FINISHED'>> $LOG_FILE
# СОБРАТЬ СТАТИСТИКУ VMSTAT
#########################################################################################################

#########################################################################################################
# СОБРАТЬ СТАТИСТИКУ IOSTAT
echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : IOSTAT PERFORMANCE MONITORING STARTED '
echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : IOSTAT PERFORMANCE MONITORING STARTED '>> $LOG_FILE

$current_path'/'get_iostat_info.sh
exit_code $? $LOG_FILE $ERR_FILE

echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : IOSTAT PERFORMANCE MONITORING FINISHED'
echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : IOSTAT PERFORMANCE MONITORING FINISHED'>> $LOG_FILE
# СОБРАТЬ СТАТИСТИКУ IOSTAT
########################################################################################################


echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : *** COLLECTING CLUSTER STATS STARTED '
echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : *** COLLECTING CLUSTER STATS STARTED'>> $LOG_FILE

psql -d $performance_monitoring_db -U $performance_monitoring_user -Aqtc 'select pg_hazel()' 2>$ERR_FILE
exit_code $? $LOG_FILE $ERR_FILE  


echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : *** COLLECTING CLUSTER STATS FINISHED '
echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : *** COLLECTING CLUSTER STATS FINISHED'>> $LOG_FILE


current_cpi=`psql -d $performance_monitoring_db -U $performance_monitoring_user -Aqtc 'select get_current_cpi()' 2>$ERR_FILE`
exit_code $? $LOG_FILE $ERR_FILE
echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK :  '$current_cpi
echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK :  '$current_cpi >> $LOG_FILE

speed_waitings=`echo $current_cpi |  awk -F "|" '{print $1}' `
speed_waitings="$(tr -d ' ' <<< "$speed_waitings")"

#speed_short=`echo $current_cpi |  awk -F "|" '{print $2}' `
#speed_short="$(tr -d ' ' <<< "$speed_short")"

speed_long=`echo $current_cpi |  awk -F "|" '{print $2}' `
speed_long="$(tr -d ' ' <<< "$speed_long")"

waitings_long=`echo $current_cpi |  awk -F "|" '{print $3}' `
waitings_long="$(tr -d ' ' <<< "$waitings_long")"

speed_regr_slope_value=`echo $current_cpi |  awk -F "|" '{print $4}' `
speed_regr_slope_value="$(tr -d ' ' <<< "$speed_regr_slope_value")"

waitings_regr_slope_value=`echo $current_cpi |  awk -F "|" '{print $5}' `
waitings_regr_slope_value="$(tr -d ' ' <<< "$waitings_regr_slope_value")"


last_sql_statistics_timestamp=`echo $current_cpi |  awk -F "|" '{print $6}' `

speed_degradation_indicator=`echo $current_cpi |  awk -F "|" '{print $7}' `
speed_degradation_indicator="$(tr -d ' ' <<< "$speed_degradation_indicator")"



#####################################################
# PG_HAZEL METRICS 
	#SHORT SPEED
	echo $speed_short >  /tmp/cpi_ma_10m.txt 
	
	#LONG SPEED
	echo $speed_long >  /tmp/cpi_ma_1h.txt		
	
	#CPI - индикатор производительности (ОК=0 , WARNING=-50 , AVERAGE = -100)
	echo $speed_degradation_indicator >  /tmp/qps.txt
####################################################
# !!!!!!!!!!!!!!!ВРЕМЕННОЕ РЕШЕНИЕ !!!!!!!!!!!!!!!!!
  #Ожидания
  echo $waitings_long >  /tmp/pages_rfs.txt
  #Корреляция скорость - ожидания
  #echo $speed_waitings >  /tmp/pages_wfs.txt
  
  #угол наклона скорость
  #echo $speed_regr_slope_value >  /tmp/cpi_ma_30m.txt 
	
  #угол наклона ожидания
  #echo $waitings_regr_slope_value >  /tmp/cpi_ma_4h.txt	

	
# !!!!!!!!!!!!!!!ВРЕМЕННОЕ РЕШЕНИЕ !!!!!!!!!!!!!!!!!
####################################################
# PG_HAZEL METRICS 
#####################################################	


echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : CLUSTER STATS ***'
echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : CLUSTER STATS ***' >> $LOG_FILE
  
#echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : LAST SQL STATISTICS TIMESTAMP = '$last_sql_statistics_timestamp
#echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : LAST SQL STATISTICS TIMESTAMP = '$last_sql_statistics_timestamp >> $LOG_FILE

#echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : SPEED SHORT = : '$speed_short
#echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : SPEED SHORT = : '$speed_short >> $LOG_FILE

echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : SPEED LONG = : '$speed_long
echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : SPEED LONG = : '$speed_long >> $LOG_FILE

echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : WAITINGS = : '$waitings_long
echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : WAITINGS = : '$waitings_long >> $LOG_FILE

echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : SPEED_WAITINGS = : '$speed_waitings
echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : SPEED_WAITINGS = : '$speed_waitings >> $LOG_FILE

echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : SPEED ANGLE = : '$speed_regr_slope_value
echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : SPEED ANGLE = : '$speed_regr_slope_value >> $LOG_FILE

echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : WAITINGS ANGLE = : '$waitings_regr_slope_value
echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : WAITINGS ANGLE = : '$waitings_regr_slope_value >> $LOG_FILE

echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : SPEED DEGRADATION INDICATOR = : '$speed_degradation_indicator
echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : SPEED DEGRADATION INDICATOR = : '$speed_degradation_indicator >> $LOG_FILE

echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : CLUSTER STATS ***'
echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : CLUSTER STATS ***' >> $LOG_FILE
# СБОР СТАТИСТИЧЕСКОЙ ИНФОРМЦИИ О ПРОИЗВОДИТЕЛЬНОСТИ 
#########################################################################################################

########################################################################################################
#
# ТОЛЬКО ДЛЯ 1atsp-s-pg08n1
	echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : АНАЛИЗ ЦЕПИ МАРКОВА - НАЧАТ '
	echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : АНАЛИЗ ЦЕПИ МАРКОВА - НАЧАТ '>> $LOG_FILE

	MARKOV_CHAIN_LOG=$current_path'/markov_chain.log'
	psql -d $performance_monitoring_db -U $performance_monitoring_user  -v ON_ERROR_STOP=on --echo-errors -Aqtc 'select mchain_reliability_report()'  > $MARKOV_CHAIN_LOG 2>$ERR_FILE
	exit_code $? $LOG_FILE $ERR_FILE

	echo 'INFO : ПОСЛЕДНИЕ 3 ОШИБКИ '>> $LOG_FILE	
	echo 'INFO : ПОСЛЕДНИЕ 3 ОШИБКИ '>> $MARKOV_CHAIN_LOG

	psql -d $performance_monitoring_db -U $performance_monitoring_user  -v ON_ERROR_STOP=on --echo-errors -Aqtc 'select * from mchain_error_log order by ts desc LIMIT 3 '  >> $LOG_FILE 2>$ERR_FILE
	exit_code $? $LOG_FILE $ERR_FILE
	psql -d $performance_monitoring_db -U $performance_monitoring_user  -v ON_ERROR_STOP=on --echo-errors -Aqtc 'select * from mchain_error_log order by ts desc LIMIT 3 '  >> $MARKOV_CHAIN_LOG 2>$ERR_FILE
	exit_code $? $LOG_FILE $ERR_FILE

	mchain_forecast_reliability=`psql -d $performance_monitoring_db -U $performance_monitoring_user  -v ON_ERROR_STOP=on --echo-errors -Aqtc 'select mchain_forecast_reliability()'`
	
	
	

	if [[ $mchain_forecast_reliability -ge 3 ]]
	then 
	  echo 'INFO : ДОСТАТОЧНО ДАННЫХ ДЛЯ ПРОГНОЗА(ОБУЧЕНИЕ ЦЕПИ ЗАКОНЧЕНО).' >> $MARKOV_CHAIN_LOG
 	  echo 'INFO : ДОСТАТОЧНО ДАННЫХ ДЛЯ ПРОГНОЗА(ОБУЧЕНИЕ ЦЕПИ ЗАКОНЧЕНО).' >> $LOG_FILE

	  echo ' ' >> $MARKOV_CHAIN_LOG
	  mchain_predict_risk_current_horizon=`psql -d $performance_monitoring_db -U $performance_monitoring_user  -v ON_ERROR_STOP=on --echo-errors -Aqtc 'select * from mchain_predict_risk_current_horizon()'`
	  exit_code $? $LOG_FILE $ERR_FILE

	  forecast_horizon_minutes=`psql -d $performance_monitoring_db -U $performance_monitoring_user  -v ON_ERROR_STOP=on --echo-errors -Aqtc 'select forecast_horizon_minutes from markov_config'`
	  exit_code $? $LOG_FILE $ERR_FILE
	  
	  profile_comparison_log=`psql -d $performance_monitoring_db -U $performance_monitoring_user  -Aqtc "select date_trunc('minute',baseline_window_start ) AS baseline_window_start , date_trunc('minute',baseline_window_end ) AS baseline_window_end , date_trunc('minute',current_window_start ) AS current_window_start , date_trunc('minute',current_window_end ) AS current_window_end , substring(status FROM 0 FOR 11) AS status , js_divergence  , pre_alert_flag , pre_alert_flag_advanced from profile_comparison_log order by current_window_end desc limit 1 "`
	  
	  profile_comparison_log_status=`echo $profile_comparison_log |  awk -F "|" '{print $5}' `
	  profile_comparison_log_js_divergence=`echo $profile_comparison_log |  awk -F "|" '{print $6}' `
	  baseline_start=`echo $profile_comparison_log |  awk -F "|" '{print $1}' `
	  baseline_finish=`echo $profile_comparison_log |  awk -F "|" '{print $2}' `
	  current_start=`echo $profile_comparison_log |  awk -F "|" '{print $3}' `
	  current_finish=`echo $profile_comparison_log |  awk -F "|" '{print $4}' `
	  #pre_alert_flag=`echo $profile_comparison_log |  awk -F "|" '{print $7}' `
	  #pre_alert_flag_advanced=`echo $profile_comparison_log |  awk -F "|" '{print $8}' `

	  ##################################################
	  # МЕТРИКА JS-ДИВЕРГЕНЦИЯ
	    echo $profile_comparison_log_js_divergence > /tmp/pages_dfs.txt
	  # МЕТРИКА JS-ДИВЕРГЕНЦИЯ
	  ##################################################
	  
	  ##################################################
	  # ПРОГНОЗ РИСКА
	    echo $mchain_predict_risk_current_horizon > /tmp/pages_wfs.txt
	  # ПРОГНОЗ РИСКА
	  ##################################################
	  
	  ##################################################
	  # ИНДИКАТОР JS-ДИВЕРГЕНЦИЯ+ПРОГНОЗ РИСКА
	  #	echo $pre_alert_flag > /tmp/cpi_ma_30m.txt 
	  # ИНДИКАТОР JS-ДИВЕРГЕНЦИЯ+ПРОГНОЗ РИСКА
	  ##################################################
	  
	  
	  ##################################################
	  # Новый флаг предаварийного состояния (100/0) по комплексному критерию
	  #	echo $pre_alert_flag_advanced > /tmp/tps.txt
	  # Новый флаг предаварийного состояния (100/0) по комплексному критерию
	  ##################################################
  
	  
	  
	  if [[ "$profile_comparison_log_status" == "INCIDENT" ]]
	  then 
		echo 'INCIDENT : ПРОФИЛЬ ПРОИЗВОДИТЕЛЬНОСТИ НЕ РАСЧИТЫВАЕТСЯ : ИНЦИДЕНТ ИЛИ ВОССТАНОВЛЕНИЕ ПОСЛЕ ИНЦИДЕНТА' >> $MARKOV_CHAIN_LOG 
		echo 'INCIDENT : ПРОФИЛЬ ПРОИЗВОДИТЕЛЬНОСТИ НЕ РАСЧИТЫВАЕТСЯ : ИНЦИДЕНТ ИЛИ ВОССТАНОВЛЕНИЕ ПОСЛЕ ИНЦИДЕНТА' >> $LOG_FILE 
		incident_timepoint=`psql -d $performance_monitoring_db -U $performance_monitoring_user  -Aqtc "select start_timepoint , finish_timepoint from performance_incident where start_timepoint = (select max(start_timepoint) from performance_incident )"`
		start_timepoint=`echo $incident_timepoint |  awk -F "|" '{print $1}' `
		finish_timepoint=`echo $incident_timepoint |  awk -F "|" '{print $2}' `
		echo 'INCIDENT : НАЧАЛО ИНЦИДЕНТА : '$start_timepoint' ОКОНЧАНИЕ ИНЦИДЕНТА : '$finish_timepoint >> $MARKOV_CHAIN_LOG 
		echo 'INCIDENT : НАЧАЛО ИНЦИДЕНТА : '$start_timepoint' ОКОНЧАНИЕ ИНЦИДЕНТА : '$finish_timepoint >> $LOG_FILE 	
	  elif [[ "$profile_comparison_log_status" == "CRITICAL" ]]
	  then 
	    echo 'CRITICAL :  JS-ДИВЕРГЕНЦИЯ = '$profile_comparison_log_js_divergence >> $MARKOV_CHAIN_LOG 			  
		echo 'CRITICAL :  JS-ДИВЕРГЕНЦИЯ = '$profile_comparison_log_js_divergence >> $LOG_FILE 		
		echo 'INFO :  ЭТАЛОННОЕ ОКНО = '$baseline_start' - '$baseline_finish >> $MARKOV_CHAIN_LOG 		
		echo 'INFO :  ЭТАЛОННОЕ ОКНО = '$baseline_start' - '$baseline_finish >> $LOG_FILE 		
		echo 'INFO :  ТЕКУЩЕЕ ОКНО = '$current_start' - '$current_finish >> $MARKOV_CHAIN_LOG 		
		echo 'INFO :  ТЕКУЩЕЕ ОКНО = '$current_start' - '$current_finish >> $LOG_FILE 		
		
		echo 'INFO : ВЕРОЯТНОСТЬ ИНЦИДЕНТА В ТЕЧЕНИИ '$forecast_horizon_minutes' МИНУТ = '$mchain_predict_risk_current_horizon >> $MARKOV_CHAIN_LOG 2>$ERR_FILE
		echo 'INFO : ВЕРОЯТНОСТЬ ИНЦИДЕНТА В ТЕЧЕНИИ '$forecast_horizon_minutes' МИНУТ = '$mchain_predict_risk_current_horizon >> $LOG_FILE 2>$ERR_FILE
	  elif [[ "$profile_comparison_log_status" == "WARNING" ]]
	  then 
	    echo 'WARNING :  JS-ДИВЕРГЕНЦИЯ = '$profile_comparison_log_js_divergence >> $MARKOV_CHAIN_LOG 			  	  
		echo 'WARNING :  JS-ДИВЕРГЕНЦИЯ = '$profile_comparison_log_js_divergence >> $LOG_FILE 			  	  
		echo 'INFO :  ЭТАЛОННОЕ ОКНО = '$baseline_start' - '$baseline_finish >> $MARKOV_CHAIN_LOG 		
		echo 'INFO :  ЭТАЛОННОЕ ОКНО = '$baseline_start' - '$baseline_finish >> $LOG_FILE 		
		echo 'INFO :  ТЕКУЩЕЕ ОКНО = '$current_start' - '$current_finish >> $MARKOV_CHAIN_LOG 		
		echo 'INFO :  ТЕКУЩЕЕ ОКНО = '$current_start' - '$current_finish >> $LOG_FILE 		
		
		echo 'INFO : ВЕРОЯТНОСТЬ ИНЦИДЕНТА В ТЕЧЕНИИ '$forecast_horizon_minutes' МИНУТ = '$mchain_predict_risk_current_horizon >> $MARKOV_CHAIN_LOG 2>$ERR_FILE
		echo 'INFO : ВЕРОЯТНОСТЬ ИНЦИДЕНТА В ТЕЧЕНИИ '$forecast_horizon_minutes' МИНУТ = '$mchain_predict_risk_current_horizon >> $LOG_FILE 2>$ERR_FILE
	  else	  
	    echo 'INFO :  JS-ДИВЕРГЕНЦИЯ = '$profile_comparison_log_js_divergence >> $MARKOV_CHAIN_LOG 		
		echo 'INFO :  JS-ДИВЕРГЕНЦИЯ = '$profile_comparison_log_js_divergence >> $LOG_FILE 		
		echo 'INFO :  ЭТАЛОННОЕ ОКНО = '$baseline_start' - '$baseline_finish >> $MARKOV_CHAIN_LOG 		
		echo 'INFO :  ЭТАЛОННОЕ ОКНО = '$baseline_start' - '$baseline_finish >> $LOG_FILE 		
		echo 'INFO :  ТЕКУЩЕЕ ОКНО = '$current_start' - '$current_finish >> $MARKOV_CHAIN_LOG 		
		echo 'INFO :  ТЕКУЩЕЕ ОКНО = '$current_start' - '$current_finish >> $LOG_FILE 		
		
		echo 'INFO : ВЕРОЯТНОСТЬ ИНЦИДЕНТА В ТЕЧЕНИИ '$forecast_horizon_minutes' МИНУТ = '$mchain_predict_risk_current_horizon >> $MARKOV_CHAIN_LOG 2>$ERR_FILE
		echo 'INFO : ВЕРОЯТНОСТЬ ИНЦИДЕНТА В ТЕЧЕНИИ '$forecast_horizon_minutes' МИНУТ = '$mchain_predict_risk_current_horizon >> $LOG_FILE 2>$ERR_FILE
	  fi 
	  

	  mchain_health_check=`psql -d $performance_monitoring_db -U $performance_monitoring_user  -v ON_ERROR_STOP=on --echo-errors -Aqtc 'select status , message from mchain_health_check()'`
	  exit_code $? $LOG_FILE $ERR_FILE

	  echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : '$mchain_health_check >> $MARKOV_CHAIN_LOG  

	  psql -d $performance_monitoring_db -U $performance_monitoring_user  -v ON_ERROR_STOP=on --echo-errors -Aqtc 'select unnest(description) from mchain_health_check()' >> $MARKOV_CHAIN_LOG    
	  else
		echo 'ALARM: НЕДОСТАТОЧНО ДАННЫХ ДЛЯ ПРОГНОЗА(ОБУЧЕНИЕ ЦЕПИ НЕ ЗАКОНЧЕНО).' >> $MARKOV_CHAIN_LOG
		echo 'ALARM: НЕДОСТАТОЧНО ДАННЫХ ДЛЯ ПРОГНОЗА(ОБУЧЕНИЕ ЦЕПИ НЕ ЗАКОНЧЕНО).' >> $LOG_FILE
	  fi

	  indicator_value=`psql -d $performance_monitoring_db -U $performance_monitoring_user  -Aqtc "select indicator_value from profile_change_indicator where changed_at = (select max(changed_at) from profile_change_indicator)"`
	  		
	  if [[ "$indicator_value" == "t" ]];
	  then
		echo 'ALARM : ИНДИКАТОР ИЗМЕНЕНИЯ ПРОФИЛЯ ПРОИЗВОДИТЕЛЬНОСТИ = TRUE'>> $MARKOV_CHAIN_LOG 2>$ERR_FILE
		echo 'ALARM : ИНДИКАТОР ИЗМЕНЕНИЯ ПРОФИЛЯ ПРОИЗВОДИТЕЛЬНОСТИ = TRUE' >> $LOG_FILE 2>$ERR_FILE				
		##################################################
		# ИНДИКАТОР ИЗМЕНЕНИЯ ПРОФИЛЯ ПРОИЗВОДИТЕЛЬНОСТИ
		echo '100' > /tmp/cpi_ma_30m.txt 
		# ИНДИКАТОР ИЗМЕНЕНИЯ ПРОФИЛЯ ПРОИЗВОДИТЕЛЬНОСТИ
		##################################################
	  
	  else
		echo 'INFO : ИНДИКАТОР ИЗМЕНЕНИЯ ПРОФИЛЯ ПРОИЗВОДИТЕЛЬНОСТИ = FALSE'>> $MARKOV_CHAIN_LOG 2>$ERR_FILE
		echo 'INFO : ИНДИКАТОР ИЗМЕНЕНИЯ ПРОФИЛЯ ПРОИЗВОДИТЕЛЬНОСТИ = FALSE' >> $LOG_FILE 2>$ERR_FILE	
		
		##################################################
		# ИНДИКАТОР ИЗМЕНЕНИЯ ПРОФИЛЯ ПРОИЗВОДИТЕЛЬНОСТИ
		echo '0' > /tmp/cpi_ma_30m.txt 
		# ИНДИКАТОР ИЗМЕНЕНИЯ ПРОФИЛЯ ПРОИЗВОДИТЕЛЬНОСТИ
		##################################################		
	  fi
    
	echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : АНАЛИЗ ЦЕПИ МАРКОВА - ЗАКОНЧЕН '
	echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : АНАЛИЗ ЦЕПИ МАРКОВА - ЗАКОНЧЕН '>> $LOG_FILE
# #
# ########################################################################################################



echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : CLEANING STARTED '
echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : CLEANING STARTED '>> $LOG_FILE

psql -d $performance_monitoring_db -U $performance_monitoring_user  -v ON_ERROR_STOP=on --echo-errors -Aqtc 'select cleaning()'  >> $LOG_FILE 2>$ERR_FILE
exit_code $? $LOG_FILE $ERR_FILE

echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : CLEAR VMSTAT/IOSTAT HISTORY FILE '
echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : CLEAR VMSTAT/IOSTAT HISTORY FILE '>> $LOG_FILE
#Если тест не начат
if [ ! -f /postgres/scripts/tester/stress_tester/TESTER_STARTED ]; 
then
  echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : STRESS TEST NOT STARTED '
  echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : STRESS TEST NOT STARTED '>> $LOG_FILE

  let current_minute=`echo $(date "+%M")`
  let mod=current_minute%10

  echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : current_minute='$current_minute
  echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : current_minute='$current_minute>> $LOG_FILE
  
  echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : mod='$mod
  echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : mod='$mod>> $LOG_FILE
  
  if [ "$mod" == "0" ]
  then 
	echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : kill vmstat'
    echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : kill vmstat'>> $LOG_FILE

	pkill -u postgres -x "vmstat"

	echo 'start vmstat'
	vmstat 60 -S M -t >/postgres/scripts/tester/vmstat.log 2>&1 &
	echo 'vmstat started'

	echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : kill iostat'
    echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : kill iostat'>> $LOG_FILE
	
	echo 'kill iostat'

    pkill -u postgres -x "iostat"

    echo 'start iostat'
    iostat 60 -d -x -m -t >/postgres/scripts/tester/iostat.log 2>&1 &
    echo 'iostat started '
  fi  
else
  echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : INFO : STRESS TEST STARTED - CLEAR VMSTAT HISTORY FILE DISABLED  '
  echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : INFO : STRESS TEST STARTED - CLEAR VMSTAT HISTORY FILE DISABLED  '>> $LOG_FILE
fi

#Если тест не начат

echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : CLEANING FINISHED '
echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : CLEANING FINISHED '>> $LOG_FILE

#DISABLED
#echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : INFO : SQL STATS ' >> $LOG_FILE
#pg_hazel_sql=`ls -rth /postgres/scripts/tester/pg_hazel_sql*.log | tail -1`
#cat $pg_hazel_sql >> $LOG_FILE
#echo ' ' >> $LOG_FILE
#
#echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : INFO : STAT OF LAST SQL PERIOD ' >> $LOG_FILE
#last_pg_hazel_sql=`ls -rth /postgres/scripts/tester/pg_hazel_sql*.log | tail -2 | head -1`
#cat $last_pg_hazel_sql >> $LOG_FILE
#echo ' ' >> $LOG_FILE
#echo 'TIMESTAMP : '$(
#date "+%d-%m-%Y %H:%M:%S") ' : OK : FINISH '
#echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : FINISH '>> $LOG_FILE
#########################################################################################################
#ФОРМИРОВАНИЕ ЗАПИСЕЙ В ЧЕРНЫЙ ЯЩИК
#timestamp_label=$(date "+%Y%m%d")'T'$(date "+%H%M")
#echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : START - BLACK_BOX  '
#echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : START - BLACK_BOX  ' >> $LOG_FILE
#
#REPORT_FILE=$REPORT_DIR'/activity_'$timestamp_label'.txt'
#psql  -d $performance_monitoring_db -U $performance_monitoring_user -f $current_path'/smart_black_box_activity.sql' > $REPORT_FILE 2>$ERR_FILE 
#if [ $? -ne 0 ]
#then
#	echo 'ERROR : smart_black_box_activity TERMINATED WITH ERROR '
#	echo 'ERROR : smart_black_box_activity TERMINATED WITH ERROR ' >> $LOG_FILE
#	exit 200
#fi
#echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : smart_black_box_activity :'$REPORT_FILE
#echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : smart_black_box_activity :'$REPORT_FILE >> $LOG_FILE
#
#
#REPORT_FILE=$REPORT_DIR'/locks_'$timestamp_label'.txt'
#psql  -d $performance_monitoring_db -U $performance_monitoring_user -f $current_path'/smart_black_box_locks.sql' > $REPORT_FILE 2>$ERR_FILE
#if [ $? -ne 0 ]
#then
#	echo 'ERROR : smart_black_box_locks TERMINATED WITH ERROR '
#	echo 'ERROR : smart_black_box_locks TERMINATED WITH ERROR ' >> $LOG_FILE
#	exit 300
#fi
#echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : smart_black_box_locks :'$REPORT_FILE
#echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : smart_black_box_locks :'$REPORT_FILE >> $LOG_FILE
#78.1 - DISABLED
#REPORT_FILE=$REPORT_DIR'/ram_'$timestamp_label'.txt'
#echo "pid | user | rss " > $REPORT_FILE 2>$ERR_FILE
#ps -e -o  pid,user,rss --sort=-%mem | grep postgres | awk '{print $1" | "$2" | "$3}' >> $REPORT_FILE 2>$ERR_FILE
#if [ $? -ne 0 ]
#then
#	echo 'ERROR : ram TERMINATED WITH ERROR '
#	echo 'ERROR : ram TERMINATED WITH ERROR ' >> $LOG_FILE
#	exit 700
#fi
#echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : smart_black_box_ram :'$REPORT_FILE
#echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : smart_black_box_ram :'$REPORT_FILE >> $LOG_FILE
#78.1 - DISABLED
#
#find $REPORT_DIR -type f -mmin +59 -delete >> $LOG_FILE 2>$ERR_FILE	
#echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : DELETED OLD SMART_BLACK_BOX FILES '
#echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : DELETED OLD SMART_BLACK_BOX FILES ' >> $LOG_FILE
#
#if [ "$current_minute" == "00" ]
#then 
#  echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : ARCHIVING SMART_BLACK_BOX FILES '
#  echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : ARCHIVING SMART_BLACK_BOX FILES ' >> $LOG_FILE
#  
#  arc_timestamp_label=$(date "+%u%H")
#  ARCHIVE_FILE=$ARCHIVE_DIR$'/bb_'$arc_timestamp_label
#  ARCHIVE_DIR='/log/pg_log'
#  BB_REPORTS='/tmp/bb/*.txt'
#
#  find $ARCHIVE_FILE'.zip' -delete
#
#  zip -1 -r $ARCHIVE_FILE $REPORT_DIR
#  if [ $? -ne 0 ]
#  then
#    echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : WARNING : ZIP - ERROR  '
#    echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : WARNING : ZIP - ERROR  ' >> $LOG_FILE
#   fi  
#fi 

echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : FINISH - BLACK_BOX  '
echo 'TIMESTAMP : '$(date "+%d-%m-%Y %H:%M:%S") ' : OK : FINISH - BLACK_BOX  ' >> $LOG_FILE
#ФОРМИРОВАНИЕ ЗАПИСЕЙ В ЧЕРНЫЙ ЯЩИК
#########################################################################################################



#################################################
# Опустить флаг
rm /postgres/scripts/tester/PG_HAZEL_CLUSTER_IN_PROGRESS
#################################################

exit 0 


