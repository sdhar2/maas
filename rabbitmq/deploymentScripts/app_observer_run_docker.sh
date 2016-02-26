#!/bin/bash

####################################################################################
#Copyright 2014 ARRIS Enterprises, Inc. All rights reserved.
#This program is confidential and proprietary to ARRIS Enterprises, Inc. (ARRIS),
#and may not be copied, reproduced, modified, disclosed to others, published or used,
#in whole or in part, without the express prior written permission of ARRIS.
####################################################################################
SERVICE_NAME="monaas"
source acpVersion.sh

DOCKER_VERSION=2.0.0.2
DOCKERRUN_LOGFILE=/var/log/run_docker.log
DOCKER_REPO="dockerrepo:5000"
APP_OBSERVER_CONTAINER_NAME="appObserverRabbitMQ"
DOCKER_IMAGE="arrs/arrs-cloud-base-app-observer"

ADVISOR_PORT=8375
STATUS_POLL_PORT=8377
PERF_POLL_PORT=7503

ACP_PRODUCT="ACP-RABBITMQ"

timestamp() 
{
  date --rfc-3339=seconds
}

cleanContainer() {
  containerId=`docker ps | grep "$1" | awk '{ print $1}'`

  if [[ ! -z $containerId ]]; then
    echo "$(timestamp) - containerId for \"$1\"=$containerId is running, stopping and removing it" >> "$2"
    docker stop $containerId
    docker rm $containerId
  else
    containerId=`docker ps -a | grep "$1" | awk '{ print $1}'`

    if [[ ! -z $containerId ]]; then
      echo "$(timestamp) - containerId for \"$1\"=$containerId is not running but needs to be removed, removing it" >> "$2"
      docker rm $containerId
    fi
  fi
}

echo "$(timestamp) - Start app_observer_run_docker.sh =================" >> $DOCKERRUN_LOGFILE

cleanContainer $DOCKER_IMAGE $DOCKERRUN_LOGFILE

# Open up ports and protocols for app observer
setFirewall=0
iptables -L INPUT -n | grep "tcp dpt:$ADVISOR_PORT"
if [[ $? -ne 0 ]]; then
  iptables -I INPUT -p tcp --dport $ADVISOR_PORT -j ACCEPT
  setFirewall=1 
fi

iptables -L INPUT -n | grep "tcp dpt:$STATUS_POLL_PORT "
if [[ $? -ne 0 ]]; then
  iptables -I INPUT -p tcp --dport $STATUS_POLL_PORT -j ACCEPT
  setFirewall=1
fi

if [[ $setFirewall -eq 1 ]]; then
  service iptables save >> /dev/null
fi

#hostIP=`/sbin/ifconfig eth0 | grep 'inet addr:' | cut -d: -f2 | awk '{ print $1}'`
hostIP=`ip -f inet add list dev eth0 | grep brd | cut -f1 -d"/" |awk '{print $2}'`
echo "$(timestamp) - Retrieved Host IP: $hostIP" >> $DOCKERRUN_LOGFILE

# The passwords in app.conf must be obfuscated using the following command
#update mount permissions due to --selinux bug
mkdir /var/opt/app-observer-rabbitmq/config >/dev/null 2>&1
chmod 777 /var/opt/app-observer-rabbitmq/config >/dev/null 2>&1
chcon -Rt svirt_sandbox_file_t /var/opt/app-observer-rabbitmq/config  > /dev/null 2>&1
mkdir /var/opt/app-observer-rabbitmq/logs >/dev/null 2>&1
chmod 777 /var/opt/app-observer-rabbitmq/logs >/dev/null 2>&1
chcon -Rt svirt_sandbox_file_t /var/opt/app-observer-rabbitmq/logs  > /dev/null 2>&1

# docker run
docker run -d --name $APP_OBSERVER_CONTAINER_NAME \
  -p $ADVISOR_PORT:$ADVISOR_PORT \
  -p $STATUS_POLL_PORT:$STATUS_POLL_PORT \
  -e SERVICE_VERSION=$SERVICE_VERSION \
  -e SECURE_PORT=$ADVISOR_PORT \
  -e NON_SECURE_PORT=$STATUS_POLL_PORT \
  -e PRODUCT_NAME=$ACP_PRODUCT \
  -e APP_WEBSERVICE_FQDN=$hostIP \
  -e APP_WEBSERVICE_PORT=$PERF_POLL_PORT \
  -v /var/opt/app-observer-rabbitmq/config:/opt/app-observer/conf/external \
  -v /var/opt/app-observer-rabbitmq/logs:/opt/app-observer/logs \
  $DOCKER_REPO/$DOCKER_IMAGE:$DOCKER_VERSION

echo "$(timestamp) - App Observer in Docker container started." >> $DOCKERRUN_LOGFILE
