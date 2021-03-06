#set -x
#while true; do  #loop infinitely to produce backups or delete old backups every $SLEEP time
#  sleep 9999
#  echo "delete the loop DEBUG"
#done


# these GLOBAL variables should be set in docker-compose.yml file as environment variables, however default values are provided here which makes testing easier to do.
#DOCKER_ROOT_DIR=$(docker system info -f '{{.DockerRootDir}}')
TMPDIR=${TMPDIR:-/tmp}
#FTP_SERVER=${FTP_SERVER:-ubuntu-gitlabstack05}
#FTP_USER=${FTP_USER:-vmadmin}
#FTP_PASSWD=${FTP_PASSWD:-Dc5k20a3}
#SLEEP_INIT=${SLEEP_INIT:-1s}
#SLEEP=${SLEEP:-10m}
#DELETE_MTIME=${DELETE_MTIME:-5}
#DELETE_LOG_SIZE=${DELETE_LOG_SIZE:-10}
BACKUPDIR=""

#these GLOBAL variables are calculated
setNODE_HOSTNAME() {
  #assumes the container has volume "/etc:/usr/local/data"
  NODE_HOSTNAME=$(cat /usr/local/data/hostname 2> /dev/null)
#  NODE_HOSTNAME=${NODE_HOSTNAME:-$(hostname)} #running in test mode with no volume
}
setNODE_HOSTNAME

setNODE_IP() {
  NODE_IP=$(docker info --format '{{.Swarm.NodeAddr}}')
}
setNODE_IP

setSTACK_NAMESPACE() {
  STACK_NAMESPACE=$(docker inspect --format '{{index .Config.Labels "com.docker.stack.namespace"}}' $(hostname) 2> /dev/null)
  if [ "$?" != "0" ]; then
    STACK_NAMESPACE="gitlabstack" #for testing outside containers 
  fi
}
setSTACK_NAMESPACE

setGITLAB_SERVICE_NAME() {
  GITLAB_SERVICE_NAME=${GITLAB_SERVICE_NAME:-$STACK_NAMESPACE_gitlab} 
}
setGITLAB_SERVICE_NAME

#--------------------
setCONTAINERS(){
  #running containers for this namespace on this node
  CONTAINERS=($(docker ps --filter name="$STACK_NAMESPACE_" -q))
}

setCONTAINER_VOLUMES() { #$1 
  CONTAINER_VOLUMES_destinations=()
  CONTAINER_VOLUMES_names=()
  local ps=$1
  local len=$(docker inspect $ps --format "{{(len .Mounts)}}")
  local c=0
  local fmt=""
  local inspect=""
  while [ $c -lt $len ]; do 
    fmt="{{(index .Mounts $c).Type}} {{(index .Mounts $c).Destination}} {{(index .Mounts $c).Name}} $fmt" #map sequence not garanted over multiple calls
    let c=$c+1
  done
  inspect=($(docker inspect $ps --format "$fmt"))
  len=${#inspect[@]}
  c=0
  while [ $c -lt $len ]; do
    local item=${inspect[$c]}    
    if [ "$item" == "volume" ]; then
      let c=$c+1
      local volumeDest=${inspect[$c]}
      let c=$c+1
      local volumeName=${inspect[$c]}
      CONTAINER_VOLUMES_destinations+=($volumeDest)
      CONTAINER_VOLUMES_names+=($volumeName)
    fi
    let c=$c+1 
  done
}

backup_gitlab_data_volume() {
  #it is not needed to backup everything in the data volume, gitlab provide a function to perform this, so we just ftp what it produces
  local container=$1
  local volumeName=$2
  local volumeDest=$3
  local tmpdir=$(mktemp -d $TMPDIR/$volumeName.XXXXXXXXX)
  local  tarfileNew=$TMPDIR/$volumeName.tar
  echo "  $volumeName.tar"  2>&1 | tee -a /var/log/cron.log  
  docker exec -t $container gitlab-rake gitlab:backup:create 2>&1 | tee -a /var/log/cron.log #the tee is to duplicate the outs to a file for loggin
  docker cp $container:$volumeDest/backups $tmpdir   
  local tmpNames=($(ls -1 $tmpdir/backups|sort -r))
  local tarfile="$tmpdir/backups/${tmpNames[0]}"
  mv  $tarfile $tarfileNew   
  copy_file_to_ftp $tarfileNew
  rm -rf $tmpdir
  rm $tarfileNew
} 
 
backup_volume() {
  #tar the content of the volume and ftp it
  local container=$1
  local volumeName=$2
  local volumeDest=$3
  local tmpdir=$(mktemp -d $TMPDIR/$volumeName.XXXXXXXXX)
  local tarfile=$TMPDIR/$volumeName.tgz
  echo "  $(basename $tarfile)"  2>&1 | tee -a /var/log/cron.log
  docker cp $container:$volumeDest $tmpdir
  pushd $tmpdir > /dev/null
  tar -czf $tarfile .
  copy_file_to_ftp $tarfile
  popd > /dev/null
  #cleanup
  rm -r $tmpdir
  rm $tarfile
}

make_dir_in_ftp() {
  lftp $FTP_SERVER -u $FTP_USER,$FTP_PASSWD << EOT
    mkdir $BACKUPDIR
    close
EOT
}

copy_file_to_ftp() { #dir_file_name
  dirN=$(dirname $1)
  fileN=$(basename $1)
  pushd $dirN > /dev/null
  lftp $FTP_SERVER -u $FTP_USER,$FTP_PASSWD << EOT
    user $FTP_USER $FTP_PASSWD
    cd $BACKUPDIR
    put $fileN
    close  
EOT
  popd > /dev/null
 }
  
create_backups() {
  BACKUPDIR=$NODE_HOSTNAME.$(date +%Y-%m-%d_%H_%M_%S-%Z)
  make_dir_in_ftp
  echo "Started create_backups on $(hostname) at $(date)"  2>&1 | tee  /var/log/cron.log
  setCONTAINERS
  for container in ${CONTAINERS[@]}; do
    setCONTAINER_VOLUMES $container
    local c=0
    for volumeDest in "${CONTAINER_VOLUMES_destinations[@]}"; do
      local  volumeName=${CONTAINER_VOLUMES_names[$c]}
      if [ $volumeDest == "/var/opt/gitlab" ]; then
        backup_gitlab_data_volume $container $volumeName $volumeDest
      else
        backup_volume $container $volumeName $volumeDest
      fi
      let c=$c+1
    done
  done
  echo "DONE with backups at $(date)!"  2>&1 | tee -a /var/log/cron.log  #althought the backups are truly done when the ftp of the log is done, we need to log before we ftp or lose the echo
  copy_file_to_ftp /var/log/cron.log
  rm /var/log/cron.log
}

delete_old_backups() {
  #delete backup dirs older then $DELETE_MTIME, also keep only last $DELETE_LOG_SIZE lines of delete logs
echo "delete_old_backups"
#  echo "Started delete_old_backups on $(hostname) at $(date)"  2>&1 | tee -a  $DOCKER_ROOT_DIR/volumes/"$STACK_NAMESPACE"_ftp/_data/$FTP_USER/crontmp.log
#  find $DOCKER_ROOT_DIR/volumes/"$STACK_NAMESPACE"_ftp/_data/$FTP_USER -mtime +$DELETE_MTIME  2>&1 | tee -a $DOCKER_ROOT_DIR/volumes/"$STACK_NAMESPACE"_ftp/_data/$FTP_USER/crontmp.log
#  find $DOCKER_ROOT_DIR/volumes/"$STACK_NAMESPACE"_ftp/_data/$FTP_USER -mtime +$DELETE_MTIME -exec rm -r {} \;
#  echo "DONE with delete_old_backups at $(date)!"  2>&1 | tee -a $DOCKER_ROOT_DIR/volumes/"$STACK_NAMESPACE"_ftp/_data/$FTP_USER/crontmp.log
#  tail -n $DELETE_LOG_SIZE  $DOCKER_ROOT_DIR/volumes/"$STACK_NAMESPACE"_ftp/_data/$FTP_USER/crontmp.log >  $DOCKER_ROOT_DIR/volumes/"$STACK_NAMESPACE"_ftp/_data/$FTP_USER/cron.log
#  rm $DOCKER_ROOT_DIR/volumes/"$STACK_NAMESPACE"_ftp/_data/$FTP_USER/crontmp.log
}

 
sleep 1s #$SLEEP_INIT  #give other container some lead time to start running
while true; do  #loop infinitely to produce backups or delete old backups every $SLEEP time
  if [ "$NODE_IP" == "$FTP_SERVER" ]; then
    delete_old_backups
  else
    create_backups
  fi
  sleep $SLEEP
done
