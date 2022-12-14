#!/bin/bash

#      _            _               _
#     | |          | |             (_)
#   __| | ___   ___| | _____  _ __  _  __ _
#  / _` |/ _ \ / __| |/ / _ \| '_ \| |/ _` |
# | (_| | (_) | (__|   < (_) | |_) | | (_| |
#  \__,_|\___/ \___|_|\_\___/| .__/|_|\__,_|
#                            | |
#                            |_|
#
# DOCKOPIA (C) 2022 Nosiu.pl

# hide ^C
stty -echoctl

# get user id
callUID=$( id -u );
export callUID;
callGID=$( id -g );
export callGID;

# check for sudo access
prompt=$(sudo -nv 2>&1)
if [ $? -eq 0 ]; then
  :
  # exit code of sudo-command is 0
  # echo "has_sudo__pass_set"
elif echo $prompt | grep -q '^sudo:'; then
  :
  # echo "has_sudo__needs_pass"
else
  #echo "no_sudo"
  echo "this version needs sudo privileges"
  exit $?
fi

# ask for sudo
#if [ $EUID != 0 ]; then
#    sudo "$0" "$@"
#    exit $?
#fi

# set variables
DOCKER_DIR="$( pwd )";
source_dir="";

TARGET_DIR="$( pwd )/.backups/";
target_dir="$( pwd )/.backups/";

LOG_DIR="$( pwd )/.logs/";
log_dir="$( pwd )/.logs/";

LOG_DATE="$(date +%Y_%m_%d_%H_%M)";
cur_date="$(date +%Y_%m_%d_%H_%M)";

export LOG_DATE;
export cur_date;


while getopts ":a:s:t:i:l:v:" opt;
do
    case "$opt" in
        a) echo all;
           save_all=true;
           export save_all;
        ;;
        s) DOCKER_DIR="$( realpath $OPTARG )";
           source_dir="$( realpath $OPTARG )";
        ;;
        t) TARGET_DIR="$( realpath $OPTARG )";
           target_dir="$( realpath $OPTARG )";
        ;;
        i) SAVE_IMAGES="$OPTARG";
           save_img=true;
        ;;
        l) LOG_DIR="$( realpath $OPTARG )";
           log_dir="$( realpath $OPTARG )"
        ;;
        v) VERBOSE=1;
        ;;
        \?) echo "Invalid option -$OPTARG" >&2;
        exit 1;
        ;;
    esac

    #case $OPTARG in
    #    -*) echo "Option $opt needs a valid argument"
    #    exit 1;
    #    ;;
    #esac
done

export DOCKER_DIR;
export TARGET_DIR;
export LOG_DIR;

mkdir -p "$LOG_DIR/docker-logs";
mkdir -p "$LOG_DIR/kopia-logs";
mkdir -p "$TARGET_DIR";

# check if docker compose is running in a given directory
check_compose() {

    #compose_file="$1/docker-compose.yml";
    compose_file="$1"

    if [ -f "$compose_file" ] && [ "$( docker compose -f $compose_file ps -q 2>/dev/null | wc -c )" -gt "0" ];
        then
            return 0;
        else
            return 1;
        fi

}
export -f check_compose

log_timestamp() {
    while IFS= read -r line;
    do
        printf '%s %s\n' "$(date +[%H:%M])" "$line";
    done
}
export -f log_timestamp

backup_images() {

    files_location="$1"
    target_location="$2"
    backup_name=$( basename -- $files_location );

    pushd $files_location 2>&1 > /dev/null;

    for img in $(docker compose config | awk '{if ($1 == "image:") print $2;}');
    do
        images="$images $img";
    done

    if [ -f "$target_location/images-$backup_name.tar.gz;" ]; then
        echo "backup containing images exists, overwriting...";
    fi
    #docker save $images | gzip -f > $target_location/images-$backup_name.tar.gz;
    if docker save $images -o $target_location/images-$backup_name.img >> $LOG_DIR/docker-logs/docker-save-$LOG_DATE-$backup_name.log 2>&1;
    then
        sudo chown $callUID:$callGID $target_location/images-$backup_name.img;
        echo "images backed up successfully"
    else
        #rm $target_location/images-$backup_name.img;
        echo "image backup failed, are they available?"
    fi;

    popd 2>&1 > /dev/null;
}
export -f backup_images;

backup_data() {

    files_location="$1"
    target_location="$2"
    backup_name=$( basename -- $files_location );

    pushd $files_location 2>&1 > /dev/null;

    if sudo tar -czvf $target_location/backup-$backup_name-$LOG_DATE.tar.gz .;
    then
        sudo chown $callUID:$callGID $target_location/backup-$backup_name-$LOG_DATE.tar.gz;
        popd  2>&1 > /dev/null;
        return 0;
    else
        popd 2>&1 > /dev/null;
        return 1;
    fi

}
export -f backup_data;

# main
app() {

    if [ "$save_all" = true ];
    then
        echo "save all active";
        exit;
    fi;

    compose_file=$( realpath -- $1 );
    compose_location=$( dirname -- $compose_file );
    #compose_name=${1#*/};
    #compose_name=${compose_name_pre%*/}
    #${1##*/};
    compose_name=$( basename -- $compose_location );

#    echo -e "\n====== BACKUP ${iter} of ${count} ======\n";

    if check_compose $compose_file;
    then
        echo -e "\n====== BACKUP for ${compose_name^^} ======\n";

        echo "backing up latest images without shutting down containers...";
        if backup_images $compose_location $TARGET_DIR; then
            #echo "image saved"
            :
        fi

        echo "$compose_name is a running compose service, shutting down...";
        docker compose -f $compose_file stop 2>&1 | log_timestamp >> $LOG_DIR/docker-logs/compose-down-$LOG_DATE-$compose_name.log;

        echo "$compose_name down, beginning backup...";
        if backup_data $compose_location $TARGET_DIR 2>&1 | log_timestamp >> $LOG_DIR/kopia-logs/backup-$LOG_DATE-$compose_name.log;
        then
#            iter=$((iter+1));
            echo "backup done, restoring...";
        else
            echo "backup failed, check logs. restoring..."
        fi

        docker compose -f $compose_file start 2>&1 | log_timestamp >> $LOG_DIR/docker-logs/compose-up-$LOG_DATE-$compose_name.log;
        echo "service up";
    else
        echo -e "\n====== BACKUP for ${compose_name^^} ======\n";

        echo "backing up latest images...";
        if backup_images $compose_location $TARGET_DIR; then
            #echo "image saved";
            :
        fi

        echo "$compose_name is not running, backing up...";

        if backup_data $compose_location $TARGET_DIR 2>&1 | log_timestamp >> $LOG_DIR/kopia-logs/backup-$LOG_DATE-$compose_name.log;
        then
#            iter=$((iter+1));
            echo "backup done";
        else
            echo "backup failed, check logs"
        fi
    fi

}
export -f app



#find $DOCKER_DIR -mindepth 1 -maxdepth 2 -type d \



count=$( find $DOCKER_DIR -mindepth 1 -maxdepth 2 -name "docker-compose.y*ml" | wc -l );
iter=1;

export count;
export iter;

echo "found ${count} compose project(s)";

find $DOCKER_DIR -mindepth 1 -maxdepth 2 -name "docker-compose.y*ml" \
    -execdir bash -c \
    'app "$@"' bash {} \;


