#set -x


# these GLOBAL variables should be set in docker-compose.yml file as environment variables, however default values are provided here which makes testing easier to do.
DOCKER_ROOT_DIR=$(docker system info -f '{{.DockerRootDir}}')
TMPDIR=${TMPDIR:-/tmp}
FTP_SERVER=${FTP_SERVER:-ubuntu-gitlabstack05}
FTP_USER=${FTP_USER:-vmadmin}
FTP_PASSWD=${FTP_PASSWD:-Dc5k20a3}
SLEEP_INIT=${SLEEP_INIT:-1s}
SLEEP=${SLEEP:-10m}
DELETE_MTIME=${DELETE_MTIME:-5}
DELETE_LOG_SIZE=${DELETE_LOG_SIZE:-10}
BACKUPDIR=""
BACKUPDIR_EXIST=1;

#these GLOBAL variables are calculated
setNODE_HOSTNAME() {
  #assumes the container has volume "/etc:/usr/local/data"
  NODE_HOSTNAME=$(cat /usr/local/data/hostname 2> /dev/null)
  NODE_HOSTNAME=${node_hostname:-$(hostname)} #running in test mode with no volume
}
setNODE_HOSTNAME

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
  CONTAINERS=$(docker ps --filter name="$STACK_NAMESPACE_" -q)
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
      CONTAINER_VOLUMES_names+=($volumName)
    fi
    let c=$c+1 
  done
echo $CONTAINER_VOLUMES_destinations
echo $CONTAINER_VOLUMES_names
}

setCONTAINER_VOLUMES001() { #$1 
  local ps=$1
  local len=$(docker inspect $ps --format "{{(len .Mounts)}}")
  local c=0
  CONTAINER_VOLUMES_DESTINATION=""
  CONTAINER_VOLUMES_NAME=""
  while [ $c -lt $len ]; do
    inspect=$(docker inspect $ps --format "{{(index .Mounts $c).Type}} {{(index .Mounts $c).Destination}} {{(index .Mounts $c).Name}}") #map sequence not garanted over multiple calls
    inspect=($inspect)
    type=${inspect[0]}
    if [ "$type" == "volume" ]; then
set -x
      CONTAINER_VOLUMES_DESTINATION="${inspect[1]} $CONTAINER_VOLUMES_DESTINATION"
      CONTAINER_VOLUMES_NAME="${inspect[2]} $CONTAINER_VOLUMES_NAME"
set +x
    fi
    let c=$c+1
  done
echo $CONTAINER_VOLUMES_DESTINATION
echo $CONTAINER_VOLUMES_NAME

  CONTAINER_VOLUMES_DESTINATION=($CONTAINER_VOLUMES_DESTINATION)
  CONTAINER_VOLUMES_NAME=($CONTAINER_VOLUMES_NAME)
echo $CONTAINER_VOLUMES_DESTINATION
echo $CONTAINER_VOLUMES_NAME
echo "."
}

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
  tmpdir=$(mktemp -d $TMPDIR/$volumeName.XXXXXXXXX)
  tarfile=$TMPDIR/$volumeName.tar
  echo "  $tarfile"  2>&1 | tee -a /var/log/cron.log
echo "DEBUG $container:$volumeDest:$volumeName"
  docker cp $container:$volumeDest $tmpdir
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
  if [ $BACKUPDIR_EXIST == 0 ];then
    ftp -n -v $FTP_SERVER << EOT
      passive
      user $FTP_USER $FTP_PASSWD
      cd $BACKUPDIR
      put $fileN
      close  
EOF
  else 
    ftp -n -v $FTP_SERVER << EOT
      passive
      user $FTP_USER $FTP_PASSWD
      mkdir $BACKUPDIR
      cd $BACKUPDIR
      put $fileN
      close
EOT
  fi
 }
  
create_backups() {
  BACKUPDIR=$(hostname).$(date +%Y-%m-%d_%H_%M_%S-%Z)
  echo "Started create_backups on $(hostname) at $(date)"  2>&1 | tee  /var/log/cron.log
  setCONTAINERS
  for container in $CONTAINERS; do
    setCONTAINER_VOLUMES $container
echo  $CONTAINER_VOLUMES_NAME
    for volumeName in $CONTAINER_VOLUMES_NAME; do
      echo "$volumeName"
    done
  done



#  local c=0
#  ;mxfc;. volumeName
#  while [ $c -lt $len ]; do
#    inspect=($(docker inspect $ps --format " {{(index .Mounts $c).Type}} {{(index .Mounts $c).Destination}} {{(index .Mounts $c).Name}}  ")) #map sequence not garanted over multiple calls
#    type=${inspect[0]}
#    if [ "$type" == "volume" ]; then
#      CONTAINER_VOLUMES_DESTINATION="$CONTAINER_VOLUMES_DESTINATION ${inspect[1]}"
#      CONTAINER_VOLUMES_NAME="$CONTAINER_VOLUMES_NAME ${inspect[2]}"
#    fi
#    let c=$c+1
#      if [ $volumeDest == "/var/opt/dest" ]; then
#echo        backup_gitlab_data_volume
#      else
#echo "$volumeName:$volumeDest"
##        backup_volume
#      fi
#  done
  echo "DONE with backups at $(date)!"  2>&1 | tee -a /var/log/cron.log  #althought the backups are truly done when the ftp of the log is done, we need to log before we ftp or lose the echo
#  copy_file_to_ftp /var/log/cron.log
#  rm /var/log/cron.log
}

delete_old_backups() {
  #delete backup dirs older then $DELETE_MTIME, also keep only last $DELETE_LOG_SIZE lines of delete logs
  echo "Started delete_old_backups on $(hostname) at $(date)"  2>&1 | tee -a  $DOCKER_ROOT_DIR/volumes/"$STACK_NAMESPACE"_ftp/_data/$FTP_USER/crontmp.log
  find $DOCKER_ROOT_DIR/volumes/"$STACK_NAMESPACE"_ftp/_data/$FTP_USER -mtime +$DELETE_MTIME  2>&1 | tee -a $DOCKER_ROOT_DIR/volumes/"$STACK_NAMESPACE"_ftp/_data/$FTP_USER/crontmp.log
  find $DOCKER_ROOT_DIR/volumes/"$STACK_NAMESPACE"_ftp/_data/$FTP_USER -mtime +$DELETE_MTIME -exec rm -r {} \;
  echo "DONE with delete_old_backups at $(date)!"  2>&1 | tee -a $DOCKER_ROOT_DIR/volumes/"$STACK_NAMESPACE"_ftp/_data/$FTP_USER/crontmp.log
  tail -n $DELETE_LOG_SIZE  $DOCKER_ROOT_DIR/volumes/"$STACK_NAMESPACE"_ftp/_data/$FTP_USER/crontmp.log >  $DOCKER_ROOT_DIR/volumes/"$STACK_NAMESPACE"_ftp/_data/$FTP_USER/cron.log
  rm $DOCKER_ROOT_DIR/volumes/"$STACK_NAMESPACE"_ftp/_data/$FTP_USER/crontmp.log
}

while true; do
  sleep 9999s
done
 
sleep 1s #$SLEEP_INIT  #give other container some lead time to start running
while true; do  #loop infinitely to produce backups or delete old backups every $SLEEP time
  if [ "$NODE_HOSTNAME" == "$FTP_SERVER" ]; then
    delete_old_backups
  else
    create_backups
  fi
  sleep $SLEEP
done
