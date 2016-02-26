#!/bin/bash
####################################################################################
#Copyright 2014 ARRIS Enterprises, Inc. All rights reserved.
#This program is confidential and proprietary to ARRIS Enterprises, Inc. (ARRIS),
#and may not be copied, reproduced, modified, disclosed to others, published or used,
#in whole or in part, without the express prior written permission of ARRIS.
####################################################################################
UPGRADE_LOGFILE=/tmp/upgraded.log
status=1
while [ $status -ne 0 ]  
  do
    status=`/usr/sbin/check_rmq_health.sh`
    if [ $status -gt 0 ]
    then
		touch $UPGRADE_LOGFILE
		status=0
    else
        sleep 60
    fi
done


