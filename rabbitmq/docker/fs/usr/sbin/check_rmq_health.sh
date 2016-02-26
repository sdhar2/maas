#!/bin/bash
####################################################################################
#Copyright 2015 ARRIS Enterprises, Inc. All rights reserved.
#This program is confidential and proprietary to ARRIS Enterprises, Inc. (ARRIS),
#and may not be copied, reproduced, modified, disclosed to others, published or used,
#in whole or in part, without the express prior written permission of ARRIS.
####################################################################################
## rmq Health Checker
initialSleep=$1
periodicity=$2
if [ -z "$initialSleep" ]
then
        initialSleep=60
fi

if [ -z "$periodicity" ]
then
        periodicity=60
fi

ETCD_HOST=`host etcdCluster | cut -d " " -f4`:4001
etcdctl -no-sync -peers $ETCD_HOST set /health/maas/rabbitmq/$HOST_NAME $HOST_IP -ttl `expr $initialSleep + 5`
sleep $initialSleep
while :
do
  #result=`ps -ef | grep -v grep | grep nginx: | wc -l`
  #if [ "$result" -gt "0" ] 
  #then
    etcdctl -no-sync -peers $ETCD_HOST set /health/maas/rabbitmq/$HOST_NAME $HOST_IP -ttl `expr $periodicity + 5`
  #fi
  sleep $periodicity
done
