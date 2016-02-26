#!/bin/bash

######################################################################################
# Copyright 2009-2014 ARRIS Enterprises, Inc. All rights reserved.
# This program is confidential and proprietary to ARRIS Enterprises, Inc. (ARRIS), 
# and may not be copied, reproduced, modified, disclosed to others, published 
# or used, in whole or in part, without the express prior written permission of ARRIS.
######################################################################################'

# consts
DOCKER_VERSION=1.3.0.16
DOCKER_IMAGE="arrs/arrs-cloud-base-rabbitmq"
DOCKER_REPO="dockerrepo:5000"
DOCKERRUN_LOGFILE=/var/log/rabbitmq_run_docker.log
ETCDCTL_EXEC=/usr/sbin/etcdctl
RABBITMQ_CONTAINER_NAME="arrs-rabbitmq"

#functions
timestamp() {
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

echo "$(timestamp) - Start rabbitmq_run_docker.sh =================" >> $DOCKERRUN_LOGFILE

cleanContainer $DOCKER_IMAGE $DOCKERRUN_LOGFILE

# If run as non-HA mode
# mode=0: HA, mode=1: noHA
mode=0 
if [[ -n $1 ]] && [[ $1 == noHA ]]; then
  mode=1
fi 

if [[ mode -eq 0 ]]; then
  echo "$(timestamp) - RabbitMQ runs in HA mode" >> $DOCKERRUN_LOGFILE
else
  echo "$(timestamp) - RabbitMQ runs in non-HA mode" >> $DOCKERRUN_LOGFILE
fi

if [[ mode -eq 0 ]]; then
# Resolve all DNS needed, abort if not resolved
  host etcdCluster
  statusEtcd=$?

  host dockerrepo
  statusRepo=$?

  if [[ $statusEtcd -ne 0 ]] || [[ $statusRepo -ne 0 ]]; then
    echo "$(timestamp) - Unable to resolve DNS for dockerrepo or etcd cluster, aborting" >> $DOCKERRUN_LOGFILE
    exit 1
  else
    etcd_vip=`host etcdCluster | cut -d " " -f4`
    repo_ip=`host dockerrepo | cut -d " " -f4`
    echo "$(timestamp) - Resolving all DNS needed, dockerrepo=$repo_ip, etcdCluster virtual IP=$etcd_vip" >> $DOCKERRUN_LOGFILE
  fi
fi

# Pull the docker image
docker pull $DOCKER_REPO/$DOCKER_IMAGE:$DOCKER_VERSION

# Get the host IP and host name
#hostIP=`/sbin/ifconfig eth0 | grep 'inet addr:' | cut -d: -f2 | awk '{ print $1}'`
hostIP=`ip -f inet add list dev eth0 | grep brd | cut -f1 -d"/" |awk '{print $2}'`
hostName=`uname -n`
echo "$(timestamp) - Retrieved host IP: $hostIP, hostname: $hostName" >> $DOCKERRUN_LOGFILE

if [[  mode -eq 0 ]]; then
# Set etcdctl for this VM IP
 #nohup /usr/sbin/etcdKeepAlive.bash service maas rabbitmq-server rabbitmq $hostIP 0 300 $hostName 2>&1> /var/log/etcdKeepAlive.log &
  nohup /usr/sbin/etcdKeepAlive.bash  2>&1 >/var/log/etcdKeepAlive.log &
fi

# Open up ports for rabbitmq 
setFirewall=0
iptables -L INPUT -n | grep "tcp dpt:5672"
if [[ $? -ne 0 ]]; then
  iptables -I INPUT -p tcp --dport 5672 -j ACCEPT
  setFirewall=1 
fi

iptables -L INPUT -n | grep "tcp dpt:15672"
if [[ $? -ne 0 ]]; then
  iptables -I INPUT -p tcp --dport 15672 -j ACCEPT
  setFirewall=1
fi

iptables -L INPUT -n | grep "tcp dpt:25672"
if [[ $? -ne 0 ]]; then
  iptables -I INPUT -p tcp --dport 25672 -j ACCEPT
  setFirewall=1
fi

iptables -L INPUT -n | grep "tcp dpt:4369"
if [[ $? -ne 0 ]]; then
  iptables -I INPUT -p tcp --dport 4369 -j ACCEPT
  setFirewall=1
fi

if [[ $setFirewall -eq 1 ]]; then
  service iptables save >> /dev/null
fi

#update mount permissions due to --selinux bug
chcon -Rt svirt_sandbox_file_t /var/opt/rabbitmq/log > /dev/null 2>&1

is_master=false;
host_ip=$hostIP;
master_host=RabbitMQMaster;
ha_mode=noHA;

if [[ mode -eq 0 ]]; then
  ha_mode=HA;
  if [[ $hostName == *Master ]]; then
    is_master=true
  fi
fi 

echo "Passing envs to docker run: hostName=$hostName, MODE=$ha_mode, HOST_IP=$host_ip, IS_MASTER=$is_master, MASTER_HOST_NAME=$master_host, HOST_NAME=$hostName" >> $DOCKERRUN_LOGFILE 

docker run -d --name $RABBITMQ_CONTAINER_NAME \
    -p 5672:5672 \
    -p 15672:15672 \
    -p 25672:25672 \
    -p 4369:4369 \
    -h $hostName \
    -e MODE=$ha_mode \
    -e MONITOR_PORT=8375 \
    -e HOST_IP=$host_ip \
    -e IS_MASTER=$is_master \
    -e HOST_NAME=$hostName \
    -e NUM_NODES_IN_CLUSTER=2 \
    -v /var/opt/rabbitmq/log:/var/log/rabbitmq \
    $DOCKER_REPO/$DOCKER_IMAGE:$DOCKER_VERSION

echo "$(timestamp) - RabbitMQ in Docker container started" >> $DOCKERRUN_LOGFILE
