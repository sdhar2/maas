#!/bin/bash

####################################################################################
#Copyright 2014 ARRIS Enterprises, Inc. All rights reserved.
#This program is confidential and proprietary to ARRIS Enterprises, Inc. (ARRIS),
#and may not be copied, reproduced, modified, disclosed to others, published or used,
#in whole or in part, without the express prior written permission of ARRIS.
####################################################################################

#const
DOCKER_IMAGE="ccadllc/baseos-java-supervisor-logstash-forwarder"
DOCKER_VERSION=1.0.2
DOCKER_REPO="dockerrepo:5000"

DOCKERRUN_LOGFILE=/var/log/run_docker.log
RABBITMQ_CONTAINER_NAME="arrs-rabbitmq"

#functions
timestamp() {
  date --rfc-3339=seconds
}

echo "$(timestamp) - Start lsf_run_docker.sh =================" >> $DOCKERRUN_LOGFILE

# Test DNS
MAX_RETRIES=20
cnt=0

while [ $cnt -lt $MAX_RETRIES ] && [ -z "$elk_ip" ]
do

echo "$(timestamp) - Looping to get elk_ip" >> $DOCKERRUN_LOGFILE
response=`host elk`
status=$?
echo "$(timestamp) - response is: $response" >> $DOCKERRUN_LOGFILE 
echo "$(timestamp) - status is: $status" >> $DOCKERRUN_LOGFILE

if [ $status -ne 0 ]
then
        elk_ip=""
else
        elk_ip=`echo $response | cut -d " " -f4`
fi

cnt=$((cnt+1))
sleep 1


done

if [ $cnt -ge $MAX_RETRIES ]
  then
        echo "$(timestamp) - Exiting...Unable to resolve DNS" >> $DOCKERRUN_LOGFILE
        exit
fi

# Get the host IP
#hostIP=`/sbin/ifconfig eth0 | grep 'inet addr:' | cut -d: -f2 | awk '{ print $1}'`
hostIP=`ip -f inet add list dev eth0 | grep brd | cut -f1 -d"/" |awk '{print $2}'`
echo "$(timestamp) - Retrieved Host IP: $hostIP" >> $DOCKERRUN_LOGFILE

domain=`hostname -d`
status=$?
if [[ $status -ne 0 ]]; then
  echo "$(timestamp) - Unable to retrieved domain from the host, aborting" >> $DOCKERRUN_LOGFILE
  exit 1
else
  host="elk."
  esHost=$host$domain
  echo "$(timestamp) - Retrieved ELK FQDN: $esHost" >> $DOCKERRUN_LOGFILE
fi

mkdir /var/log/supervisor >/dev/null 2>&1
chmod 777 /var/log/supervisor >/dev/null 2>&1

#update mount permissions due to --selinux bug
chcon -Rt svirt_sandbox_file_t /var/opt/logstash-forwarder/conf > /dev/null 2>&1
chcon -Rt svirt_sandbox_file_t /var/opt/logstash-forwarder/keys > /dev/null 2>&1
chcon -Rt svirt_sandbox_file_t /var/opt/logstash-forwarder/log > /dev/null 2>&1

docker run -d \
-e LS_HEAP_SIZE=1g \
-e CA_CERT_LOCATION=/etc/elk-keys/ca.pem \
-e ES_HOST=$esHost \
-e NODE_NAME="$hostIP" \
--volumes-from $RABBITMQ_CONTAINER_NAME \
-v /var/opt/logstash-forwarder/conf:/etc/logstash-forwarder \
-v /var/opt/logstash-forwarder/keys:/etc/elk-keys \
-v /var/opt/logstash-forwarder/log:/var/log/supervisor \
${DOCKER_REPO}/${DOCKER_IMAGE}:${DOCKER_VERSION}

echo "$(timestamp) - Logstash forwarder in Docker container started." >> $DOCKERRUN_LOGFILE
