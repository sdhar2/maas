#!/bin/bash

# consts
RMQ_SERVER_EXEC="/usr/sbin/rabbitmq-server"
RMQ_SERVER_PIDFILE="/var/lib/rabbitmq/mnesia/*.pid"
RMQ_SERVER_CONFIGFILE="/etc/rabbitmq/rabbitmq.config"
RMQ_SERVER_TEMP_CONFIGFILE="/etc/rabbitmq/rabbitmq_tmpl.config"

RMQ_SERVER_START_LOGFILE="/var/log/rabbitmq/startup.log"
RMQ_SERVER_START_ERROR_LOGFILE="/var/log/rabbitmq/startup_error.log"
CONFD_LOGFILE="/var/log/rabbitmq/confd.log"

RMQ_CLUSTER_NODES_PATTERN="RMQ_CLUSTER_NODES"

NODE_UP_POLLING_TIMEOUT=1800
NODE_UP_POLLING_INTERVAL=5
NODE_UP_LOGGING_INTERVAL=5

RMQ_USER=arris
RMQ_PASS=arris
ANALYTICS_USER=spring-xd
ANALYTICS_PASS=mystic-spring-xd

#functions
timestamp() {
  date --rfc-3339=seconds
}

echo "$(timestamp) - confd detected configuration changes in etcd, performing updates for RabbitMQ." >> $CONFD_LOGFILE 

# Retrieve cluster node IPs and hostnames from confd
clusterIPs=`cat /etc/confd/rabbitmq.conf | grep -oP '(?<=maas/rabbitmq/).*?(?=}|$)' | cut -d" " -f2`
clusterHostnames=`cat /etc/confd/rabbitmq.conf | grep -oP '(?<=maas/rabbitmq/).*?(?=}|$)' | cut -d" " -f1` 	

if [[ -n "$clusterIPs" ]] && [[ -n "$clusterHostnames" ]]; then
# Update /etc/hosts

  IPNum=1
  for clusterIP in $clusterIPs; do

    hostnameNum=1 
    for clusterHostname in $clusterHostnames; do

      if [[ $IPNum -eq $hostnameNum ]]; then
        if [[ $IPNum -eq 1 ]]; then
          echo "$clusterIP $clusterHostname" > /etc/hosts
          echo "$(timestamp) - Adding line to /etc/hosts: $clusterIP $clusterHostname." >> $CONFD_LOGFILE
        else
          echo "$clusterIP $clusterHostname" >> /etc/hosts
          echo "$(timestamp) - Adding line to /etc/hosts: $clusterIP $clusterHostname." >> $CONFD_LOGFILE
        fi
      fi
    
      hostnameNum=$((hostnameNum+1))
    done

    IPNum=$((IPNum+1))
  done

# Update /etc/rabbitmq/rabbitmq.config
  clusterNodesStr=""

  for clusterHostname in $clusterHostnames; do
    clusterNode="rabbit@$clusterHostname"
    clusterNodesStr="\'$clusterNode\',$clusterNodesStr"
  done

  clusterNodesStr=`echo "${clusterNodesStr%?}"`
  echo "$(timestamp) - Adding cluster nodes to /etc/rabbitmq/rabbitmq.config: $clusterNodesStr" >> $CONFD_LOGFILE

  if [[ -f $RMQ_SERVER_CONFIGFILE ]]; then
    rm -rf $RMQ_SERVER_CONFIGFILE
  fi
  cp $RMQ_SERVER_TEMP_CONFIGFILE $RMQ_SERVER_CONFIGFILE
  sed -i "s/$RMQ_CLUSTER_NODES_PATTERN/$clusterNodesStr/g" $RMQ_SERVER_CONFIGFILE

# Start/Re-start Rabbitmq Server
  echo "$(timestamp) - Rabbitmq configuration files updated, starting/re-starting Rabbitmq Server" >> $CONFD_LOGFILE 

  if ls $RMQ_SERVER_PIDFILE > /dev/null 2>&1; then
    echo "$(timestamp) - Rabbitmq Server is already running, re-starting is not supported at this time. Nothing is done." >> $CONFD_LOGFILE
  else
    echo "$(timestamp) - Rabbitmq Server is not running, starting." >> $CONFD_LOGFILE

    # If IS_MASTER node, start right away, otherwise wait until the MASTER node is up
    if [[ $IS_MASTER = true ]]; then
      echo "$(timestamp) - This is the MASTER node, start immediately." >> $CONFD_LOGFILE
    else

      echo "$(timestamp) - This is the SLAVE node, wait to start until the MASTER node is up." >> $CONFD_LOGFILE

      # Find out the master node by excluding the HOST_IP from the IP pools in etcd cluster
      # Note this algorithm assumes RabbitMQ cluster only contains 2 nodes
     
      masterIP="" 
      for clusterIP in $clusterIPs; do
        if [[ $clusterIP != $HOST_IP ]]; then
          masterIP=$clusterIP
          echo "$(timestamp) - MASTER node IP: $masterIP" >> $CONFD_LOGFILE
          break
        fi
      done

      # Poll master IP to see if RabbitMQ service is up
      nodeUpStatus=1
      nodeUpNumOfPolls=0
 
      while [ $nodeUpStatus -ne 0 ] && [ $nodeUpNumOfPolls -le $NODE_UP_POLLING_TIMEOUT ]
      do
        curl -i -s -u $RMQ_USER:$RMQ_PASS -H "Content-type:application/json" \
              http://$masterIP:15672/api/overview &> /dev/null
        nodeUpStatus=$?
        nodeUpNumOfPolls=$((nodeUpNumOfPolls + 1))
        echo "$(timestamp) - Polling MASTER node and it is not up" >> $CONFD_LOGFILE
        sleep $NODE_UP_POLLING_INTERVAL
      done

      if [[ $nodeUpStatus -ne 0 ]]; then
        echo "$(timestamp) - MASTER node is not up after the timeout period, abort startup of the SLAVE node" >> $CONFD_LOGFILE
        exit 1
      else
        echo "$(timestamp) - MASTER node is up, configure the cluster for queue HA and Analytics user, and then start the SLAVE node" >> $CONFD_LOGFILE
      fi
 
      # Add HA policy and Analytics user/pass 
      curl -i -u $RMQ_USER:$RMQ_PASS -H "Content-type:application/json" \
           -XPUT -d "{\"pattern\":\"^.\", \"definition\":{\"ha-mode\":\"all\"}}" \
           http://$masterIP:15672/api/policies/%2f/ha-all &> /dev/null

      curl -i -u $RMQ_USER:$RMQ_PASS -H "Content-type:application/json" \
           -XPUT -d "{\"password\":\"$ANALYTICS_PASS\",\"tags\":\"administrator\"}" \
           http://$masterIP:15672/api/users/$ANALYTICS_USER &> /dev/null

      curl -i -u $RMQ_USER:$RMQ_PASS -H "Content-type:application/json" \
           -XPUT -d "{\"configure\":\".*\",\"write\":\".*\",\"read\":\".*\"}" \
           http://$masterIP:15672/api/permissions/%2f/$ANALYTICS_USER &> /dev/null
    fi

    $RMQ_SERVER_EXEC >> $RMQ_SERVER_START_LOGFILE 2>> $RMQ_SERVER_START_ERROR_LOGFILE &

    if [[ $? -eq 0 ]]; then
      echo "$(timestamp) - Starting/re-starting completed successfully" >> $CONFD_LOGFILE
    else
      echo "$(timestamp) - Starting/re-starting failed" >> $CONFD_LOGFILE
    fi
  fi
fi
