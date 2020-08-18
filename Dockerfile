ADD devopsfiles.jar devopsfiles.jar
CMD bash $appd & java -Dspring.profiles.active=$spring_profile -Xmx3072m -XX:+HeapDumpOnOutOfMemoryError -jar devopsfiles.jar $run_time_param