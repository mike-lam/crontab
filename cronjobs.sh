#set -x

# these variables should be set in docker-compose.yml file as environment variables, however default values are provided here which makes testing easier to do.
DOCKER_ROOT_DIR=$(docker system info -f '{{.DockerRootDir}}')
TMPDIR=${TMPDIR:-/tmp}
FTP_SERVER=${FTP_SERVER:-ubuntu-gitlabstack05}
FTP_USER=${FTP_USER:-vmadmin}
FTP_PASSWD=${FTP_PASSWD:-Dc5k20a3}
SLEEP_INIT=${SLEEP_INIT:-1s}
SLEEP=${SLEEP:-10m}
NAMESPACE=${NAMESPACE:-gitlabstack}
GITLAB_SERVICE_NAME=${GITLAB_SERVICE_NAME:-$NAMESPACE_gitlab}
NODE_HOSTNAME=${NODE_HOSTNAME:-$(hostname)}
BACKUPDIR=""

backup_gitlab_data_volume() {
  #it is not needed to backup everything in the data volume, gitlab provide a function to perform this, so we just ftp what it produces
  gitlab_container_id=$(docker ps -f name=$GITLAB_SERVICE_NAME -q)
  docker exec -t $gitlab_container_id gitlab-rake gitlab:backup:create 2>&1 | tee -a /var/log/cron.log #the tee is to duplicate the outs to a file for loggin
  gitlab_data_volume=$DOCKER_ROOT_DIR/volumes/$GITLAB_SERVICE_NAME-data/_data
  tarfile=$(ls $gitlab_data_volume/backups/*)
  tarfileNew=$TMPDIR/$GITLAB_SERVICE_NAME-data.tar
  mv  $tarfile $tarfileNew 
  copy_file_to_ftp $tarfileNew
  rm $tarfileNew
} 
 
backup_volume() {
  #tar the content of the volume and ftp it
  tmpdir=$(mktemp -d $TMPDIR/$volume.XXXXXXXXXX)
  tarfile=$TMPDIR/$volume.tar
  echo "  $tarfile"  2>&1 | tee -a /var/log/cron.log 
  cp -r $DOCKER_ROOT_DIR/volumes/$volume/_data/* $tmpdir      
  tar -czf $tarfile $tmpdir
  copy_file_to_ftp $tarfile
  #cleanup
  rm -r $tmpdir      
  rm $tarfile 
} 

copy_file_to_ftp() { #dir_file_name
  dirN=$(dirname $1)
  fileN=$(basename $1)
  cd $dirN
  ftp -n -v $FTP_SERVER << EOT
  passive
  user $FTP_USER $FTP_PASSWD
  mkdir $BACKUPDIR
  cd $BACKUPDIR
  put $fileN
  close
EOT
}

create_backups() {
  #find all volumes for all running container in this stack on this node and then make a backup of it on the ftp server (which we assume is on a remote vm for safekeeping)
  BACKUPDIR=$(hostname).$(date +%Y-%m-%d_%H_%M_%S-%Z)
  echo "Started on $(hostname) at $(date)"  2>&1 | tee  /var/log/cron.log
  for volume in $(docker volume ls -q); do
    namespace=$(docker volume inspect $volume --format '{{index .Labels "com.docker.stack.namespace"}}')
    if [ "$namespace" == "$NAMESPACE" ]; then
      c=$(docker ps --filter volume=$volume -q|wc -l)    
      if [ $c -eq  1 ]; then
        if [ $volume == "$GITLAB_SERVICE_NAME-data" ]; then
          backup_gitlab_data_volume
        else 
          backup_volume
        fi
      fi
    fi
  done
  echo "DONE with backups at $(date)!"  2>&1 | tee -a /var/log/cron.log  #althought the backups are truly done when the ftp of the log is done, we need to log before we ftp or lose the echo
  copy_file_to_ftp /var/log/cron.log
  rm /var/log/cron.log
}

delete_old_backups() {
  find $DOCKER_ROOT_DIR/volumes/$NAMESPACE_ftp/_data/ -mtime +5 
}

sleep $SLEEP_INIT  #give other container some lead time to start running
while true; do  #loop infinitely to produce backups or delete old backups every $SLEEP time
  if [ "$NODE_HOSTNAME" == "$FTP_SERVER" ]; then
    delete_old_backups
  else
    create_backups
  fi
  sleep $SLEEP
done

