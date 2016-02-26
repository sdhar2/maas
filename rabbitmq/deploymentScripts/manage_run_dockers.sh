#!/bin/bash
####################################################################################
#Copyright 2014 ARRIS Enterprises, Inc. All rights reserved.
#This program is confidential and proprietary to ARRIS Enterprises, Inc. (ARRIS),
#and may not be copied, reproduced, modified, disclosed to others, published or used,
#in whole or in part, without the express prior written permission of ARRIS.
####################################################################################

#Consts
DOCKER_REPO="dockerrepo:5000"

#ACP_PRODUCT="ACP-RABBITMQ"
LSF_DOCKER_RUN_SCRIPT_FILE="lsf_run_docker.sh"
RABBITMQ_DOCKER_RUN_SCRIPT_FILE="rabbitmq_run_docker.sh"
APP_OBSERVER_DOCKER_RUN_SCRIPT_FILE="app_observer_run_docker.sh"
APP_MONITOR_DOCKER_RUN_SCRIPT_FILE="rabbitmq_app_monitor_run_docker.sh"

RABBITMQ_DOCKER_IMAGE="arrs/arrs-cloud-base-rabbitmq"
RABBITMQ_DOCKER_VERSION=`grep DOCKER_VERSION= /etc/init.d/$RABBITMQ_DOCKER_RUN_SCRIPT_FILE | cut -d "=" -f2`

LSF_DOCKER_IMAGE="ccadllc/baseos-java-supervisor-logstash-forwarder"
LSF_DOCKER_VERSION=`grep DOCKER_VERSION= /etc/init.d/$LSF_DOCKER_RUN_SCRIPT_FILE | cut -d "=" -f2`

RABBITMQ_APP_MONITOR_DOCKER_IMAGE="arrs/arrs-cloud-base-rabbitmq-app-monitor"
RABBITMQ_APP_MONITOR_DOCKER_VERSION=`grep DOCKER_VERSION= /etc/init.d/$RABBITMQ_APP_MONITOR_DOCKER_RUN_SCRIPT_FILE | cut -d "=" -f2`

APP_OBSERVER_DOCKER_IMAGE="arrs/arrs-cloud-base-app-observer"
APP_OBSERVER_DOCKER_VERSION=`grep DOCKER_VERSION= /etc/init.d/$APP_OBSERVER_DOCKER_RUN_SCRIPT_FILE | cut -d "=" -f2`

DOCKERRUN_LOGFILE=/var/log/run_docker.log

MAX_RETRY_CNT=720

#Functions
waitForContainerUp() {
  docker ps | grep "$1"
  status=$?
  cnt=0

  while [ $status -ne 0 ] && [ $cnt -lt $MAX_RETRY_CNT ] 
  do
    echo "$(timestamp) - Waiting for docker container \"$1\" to come up, status=$status" >> "$2"
    sleep 5
    docker ps | grep "$1" 
    status=$?
    cnt=$((cnt + 1))
  done

  if [[ $cnt -ge MAX_RETRY_CNT ]]; then
    echo "$(timestamp) - Maximum retries have reached while the docker container \"$1\" is still not up" >> "$2"
    return 1
  else
    echo "$(timestamp) - Docker container \"$1\" is up" >> "$2"
    return 0
  fi 
}

timestamp() {
  date --rfc-3339=seconds
}

cleanContainer() {
  containerId=`docker ps | grep "$1:" | awk '{ print $1}'`

  if [[ ! -z $containerId ]]; then
    echo "$(timestamp) - containerId for \"$1\"=$containerId is running, stopping and removing it" >> "$2"
    docker stop $containerId

    if [[ "$3" == "true" ]]; then
      docker rm -v $containerId
    else
      docker rm $containerId
    fi

  else
    containerId=`docker ps -a | grep "$1:" | awk '{ print $1}'`

    if [[ ! -z $containerId ]]; then
      echo "$(timestamp) - containerId for \"$1\"=$containerId is not running but needs to be removed, removing it" >> "$2"

      if [[ "$3" == "true" ]]; then
        docker rm -v $containerId
      else
        docker rm $containerId
      fi
    fi
  fi
}

#Main body
echo "$(timestamp) - Start manage_run_dockers.sh =================" >> $DOCKERRUN_LOGFILE
echo "$(timestamp) - Cleaning old docker containers..." >> $DOCKERRUN_LOGFILE

cleanContainer $LSF_DOCKER_IMAGE $DOCKERRUN_LOGFILE false
cleanContainer $RABBITMQ_DOCKER_IMAGE $DOCKERRUN_LOGFILE true
cleanContainer $RABBITMQ_APP_MONITOR_DOCKER_IMAGE $DOCKERRUN_LOGFILE false
cleanContainer $APP_OBSERVER_DOCKER_IMAGE $DOCKERRUN_LOGFILE false

echo "$(timestamp) - Start docker containers..." >> $DOCKERRUN_LOGFILE

# Start rabbitmq first
/etc/init.d/$RABBITMQ_DOCKER_RUN_SCRIPT_FILE &

# Wait until rabbitmq container is up, exit if exceeds max retries (amounts for 60 minutes)
waitForContainerUp $RABBITMQ_DOCKER_IMAGE $DOCKERRUN_LOGFILE
retValue=$?
if [[ retValue -ne 0 ]]; then
  echo "$(timestamp) - Exiting" >> $DOCKERRUN_LOGFILE
  exit 1
fi

# Start rabbitmq_app_monitor
/etc/init.d/$APP_MONITOR_DOCKER_RUN_SCRIPT_FILE &

# Wait until rabbitmq_app_monitor is up, exit if exceeds max retries (amounts for 60 minutes)
waitForContainerUp $RABBITMQ_APP_MONITOR_DOCKER_IMAGE $DOCKERRUN_LOGFILE
retValue=$?
if [[ retValue -ne 0 ]]; then
  echo "$(timestamp) - Exiting" >> $DOCKERRUN_LOGFILE
  exit 1
fi

#Sleep extra buffer time and then start app_observer
echo "$(timestamp) - Wait 10 seconds before starting app_observer docker container..." >> $DOCKERRUN_LOGFILE
sleep 10  
#sed -i s/\$PRODUCT_NAME/$ACP_PRODUCT/ /var/opt/app-observer/config/app.conf
/etc/init.d/$APP_OBSERVER_DOCKER_RUN_SCRIPT_FILE &

echo "$(timestamp) - starting app monitor docker container..." >> $DOCKERRUN_LOGFILE
/etc/init.d/$APP_MONITOR_DOCKER_RUN_SCRIPT_FILE &

#/usr/sbin/status_checker.sh &
/usr/sbin/check_running_rabbitmq.sh &

#Sleep extra buffer time and start lsf
echo "$(timestamp) - Wait 10 seconds before starting logstash forwarder docker container..." >> $DOCKERRUN_LOGFILE
sleep 10

/etc/init.d/$LSF_DOCKER_RUN_SCRIPT_FILE &

echo "$(timestamp) - Complete" >> $DOCKERRUN_LOGFILE
