#set -x
# set in docker file insetad as an ENV var SLEEP=15s  #can be in s, m, h, d

DOCKER_ROOT_DIR=$(docker system info -f '{{.DockerRootDir}}')
TMPDIR=${TMPDIR:-/tmp}
FTP_SERVER=${FTP_SERVER:-ubuntu-gitlabstack05}
FTP_USER=${FTP_USER:-vmadmin}
FTP_PASSWD=${FTP_PASSWD:-Dc5k20a3}
SLEEP_INIT=${SLEEP_INIT:-1s}
SLEEP=${SLEEP:-10m}
GITLAB_SERVICE_NAME=${GITLAB_SERVICE_NAME:-gitlabstack_gitlab}

backup_gitlab_data_volume() {
  #it is not needed to backup everything in the data volume, gitlab provide a function to perform this
  gitlab_container_id=$(docker ps -f name=$GITLAB_SERVICE_NAME -q)
  docker exec -t $gitlab_container_id gitlab-rake gitlab:backup:create 2>&1 | tee /var/log/cron.log #the tee is to duplicate the outs to a file for loggin
  gitlab_data_volume=$DOCKER_ROOT_DIR/volumes/$GITLAB_SERVICE_NAME-data/_data
  tarfile=$(ls $gitlab_data_volume/backups/*)
  datelabel=$(date +%Y-%m-%d_%H:%M:%S-%Z)
  tarfileNew=$TMPDIR/$GITLAB_SERVICE_NAME-data.$datelabel.$(hostname).tar
  mv  $tarfile $tarfileNew 
  FTP FROM HERE
  rm $tarfileNew
} 
 
backup_volume() {
  tmpdir=$(mktemp -d $TMPDIR/$volume.XXXXXXXXXX)
  datelabel=$(date +%Y-%m-%d_%H:%M:%S-%Z)
  tarfile=$TMPDIR/$volume.$datelabel.$(hostname).tar
  echo "  $tarfile" >> /var/log/cron.log
  cp -r $DOCKER_ROOT_DIR/volumes/$volume/_data/* $tmpdir      
  tar -czf $tarfile $tmpdir
  copy_tar_to_ftp $tarfile
  #cleanup
  rm -r $tmpdir      
  rm $tarfile 
} 

copy_tar_to_ftp() { #tarfile
  tarfileN=$(basename $1)
  cd $TMPDIR
  ftp -n -v $FTP_SERVER << EOT
  passive
  user $FTP_USER $FTP_PASSWD
  put $tarfileN
  close
EOT
}

create_backups() {
  echo "Started on $(hostname) at $(date)" >> /var/log/cron.log
  echo "running containers are:" >> /var/log/cron.log
  echo "$(docker ps --format '{{.Names}}')" >> /var/log/cron.log
  for volume in $(docker volume ls -q); do
    c=$(docker ps --filter volume=$volume -q|wc -l)
    if [ $c -eq  1 ]; then
      if [ $volume == "$GITLAB_SERVICE_NAME-data" ]; then
        backup_gitlab_data_volume
      else 
        backup_volume
      fi
    fi
  done
}

sleep $SLEEP_INIT
#while true; do
  create_backups
  sleep $SLEEP
#done

