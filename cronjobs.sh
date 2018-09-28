
echo "Started at $(date)" >> /var/log/cron.log
echo "running containers are $(docker ps -q)" >> /var/log/cron.log
echo "running volumes are" >> /var/log/cron.log
for volume in $(docker volume ls -q); do
  c=$(docker ps --filter volume=$volume -q|wc -l)
  if [ $c -eq  1 ]; then
    echo $volume >> /var/log/cron.log
  fi
done

cat /var/log/cron.log

