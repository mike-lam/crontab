#set -x
# set in docker file insetad as an ENV var SLEEP=15s  #can be in s, m, h, d

DOCKER_ROOT_DIR=$(docker system info -f '{{.DockerRootDir}}')
TMPDIR=${TMPDIR:-/tmp}
FTP_SERVER=${FTP_SERVER:-ubuntu-gitlabstack05}
FTP_USER=${FTP_USER:-vmadmin}
FTP_PASSWD=${FTP_PASSWD:-Dc5k20a3}
SLEEP=${SLEEP:-10m}

backup_gitlab_volume() {
  echo "DEBUG skip gitlab data for now"
  #needs special treatment because gitlab has it own backup process
  
} 

backup_other_volume() {
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
      if [ $volume == "gitlabstack_gitlab-config" ] || [ $volume == "gitlabstack_gitlab-data" ] || [ $volume == "gitlabstack_gitlab-log" ]; then
        backup_gitlab_volume
      else 
        backup_other_volume
      fi
    fi
  done
}

while true; do
  create_backups
  sleep $SLEEP
done

