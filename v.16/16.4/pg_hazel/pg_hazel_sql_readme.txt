cd  /postgres/scripts/tester/
-------------------------------------------------------------------------------------------
-- !!!!!! ПЕРВОНАЧАЛЬНОЕ СОЗДАНИЕ ТАБЛИЦ 
psql -d performance_monitoring_db -U performance_monitoring_user -f markov_chain_tables.sql
psql -d performance_monitoring_db -U performance_monitoring_user -f markov_chain_profile_tables.sql 
-- !!!!!! ПЕРВОНАЧАЛЬНОЕ СОЗДАНИЕ ТАБЛИЦ  
-------------------------------------------------------------------------------------------

psql -d performance_monitoring_db -U performance_monitoring_user -f markov_chain_functions.sql
psql -d performance_monitoring_db -U performance_monitoring_user -f markov_chain_profile_functions.sql
psql -d performance_monitoring_db -U performance_monitoring_user -f pg_hazel_performance_metrics_for_markov_chain.sql
psql -d performance_monitoring_db -U performance_monitoring_user -f pg_hazel_markov_chain_functions.sql


--!!! ПЕРВОНАЧАЛЬНОЕ ОБУЧЕНИЕ НА ИСТОРИЧЕСКИХ ДАННЫХ 
vi pg_hazel_train_markov_chain2.sh
chmod 750 pg_hazel_train_markov_chain2.sh
./pg_hazel_train_markov_chain2.sh >train_markov_chain2.log 2>pg_hazel_train_markov_chain2.log

--!!! ПЕРВОНАЧАЛЬНОЕ ЗАПОЛНЕНИЕ ПРОФИЛЕЙ
vi historical_profile_comparison.sh
chmod 750 historical_profile_comparison.sh
./historical_profile_comparison.sh


crontab -e
pg_hazel_markov_chain_cron.txt



