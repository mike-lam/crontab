echo " " >> /var/log/cron.log
echo "Started at $(date)" >> /var/log/cron.log
echo "backups for volumes for running containers on $(hostname)" >> /var/log/cron.log
for volume in $(docker volume ls -q); do
  c=$(docker ps --filter volume=$volume -q|wc -l)
  if [ $c -eq  1 ]; then
    echo $volume >> /var/log/cron.log
  fi
done

cat /var/log/cron.log

