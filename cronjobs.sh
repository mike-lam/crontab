
# set in docker file insetad as an ENV var SLEEP=15s  #can be in s, m, h, d

create_backups() {
  echo "Started at $(date)" >> /var/log/cron.log
  echo "running containers are $(docker ps -q)" >> /var/log/cron.log
  echo "running volumes are" >> /var/log/cron.log
  for volume in $(docker volume ls -q); do
    c=$(docker ps --filter volume=$volume -q|wc -l)
    if [ $c -eq  1 ]; then
      echo $volume >> /var/log/cron.log
    fi
  done
  }

echo "sleep period is $SLEEP" > /var/log/cron.txt
while true; do
  create_backups
  cat /var/log/cron.log
  sleep $SLEEP
done

