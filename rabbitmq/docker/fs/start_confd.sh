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
NODE_DISCOVERY_POLLING_TIMEOUT=600
NODE_DISCOVERY_POLLING_INTERVAL=1
NODE_DISCOVERY_LOGGING_INTERVAL=5

timestamp() {
  date --rfc-3339=seconds 
}

ETCD=$HOST_IP:4001

cp /etcd/config/*.json /opt/etcd/config/

echo "$(timestamp) - Start the health check background script." >> $CONFD_LOGFILE
/usr/sbin/check_rmq_health.sh 60 60 &

# if starting mode is noHA, RabbitMQ will run in a single VM with no clustering 
if [[ $MODE == noHA ]]; then

  echo "$(timestamp) - RabbitMQ runs in non-HA mode" >> $CONFD_LOGFILE

  #Setting my own etcd key for advisor registration
#  etcdctl -no-sync -peers ${ETCD} set /config/advisor/rabbitmq $HOST_IP:$MONITOR_PORT
#  etcdctl -no-sync -peers ${ETCD} set /productGroups/maas/rabbitmq $HOST_IP
  echo "$(timestamp)  setting my etcdKey /config/advisor/rabbitmq to $HOST_IP." >> $CONFD_LOGFILE

  echo "$HOST_IP $HOST_NAME" > /etc/hosts
  echo "$(timestamp) - Adding line to /etc/hosts: $HOST_IP $HOST_NAME." >> $CONFD_LOGFILE

  clusterNodesStr="\'rabbit@$HOST_NAME\'"
  echo "$(timestamp) - Adding cluster nodes to /etc/rabbitmq/rabbitmq.config: $clusterNodesStr" >> $CONFD_LOGFILE

  if [[ -f $RMQ_SERVER_CONFIGFILE ]]; then
    rm -rf $RMQ_SERVER_CONFIGFILE
  fi
  cp $RMQ_SERVER_TEMP_CONFIGFILE $RMQ_SERVER_CONFIGFILE
  sed -i "s/$RMQ_CLUSTER_NODES_PATTERN/$clusterNodesStr/g" $RMQ_SERVER_CONFIGFILE
 
  if ls $RMQ_SERVER_PIDFILE > /dev/null 2>&1; then
    echo "$(timestamp) - Rabbitmq Server is already running. Nothing to do." >> $CONFD_LOGFILE
  else
    echo "$(timestamp) - Rabbitmq Server is not running, starting." >> $CONFD_LOGFILE
    $RMQ_SERVER_EXEC >> $RMQ_SERVER_START_LOGFILE 2>> $RMQ_SERVER_START_ERROR_LOGFILE 

    if [[ $? -eq 0 ]]; then
      echo "$(timestamp) - Starting completed successfully" >> $CONFD_LOGFILE
    else
      echo "$(timestamp) - Starting failed" >> $CONFD_LOGFILE
    fi
  fi

else

  echo "$(timestamp) - RabbitMQ runs in HA mode" >> $CONFD_LOGFILE

  etcd_vip=`host etcdCluster | cut -d " " -f4`
  echo "$(timestamp) - ETCD VIP is: $etcd_vip" >> $CONFD_LOGFILE

  ETCD=$etcd_vip:4001
 
# Using etcdclt to check whether all RabbitMQ nodes in cluster have been registered
  numOfRabbitMQNodes=0
  numOfPolls=0

  while [ $numOfRabbitMQNodes -ne $NUM_NODES_IN_CLUSTER ] && [ $numOfPolls -le $NODE_DISCOVERY_POLLING_TIMEOUT ]
  do
    numOfRabbitMQNodes=`etcdctl --no-sync -peers $ETCD ls /maas/rabbitmq | wc -l`
    sleep $NODE_DISCOVERY_POLLING_INTERVAL
    numOfPolls=$((numOfPolls + 1))

    if [[ $(($numOfPolls % $NODE_DISCOVERY_LOGGING_INTERVAL )) -eq 0 ]]; then
      echo "$(timestamp) - Polling etcdCluster, number of RabbitMQ nodes: $numOfRabbitMQNodes" >> $CONFD_LOGFILE
    fi
  done

  if [[ $numOfRabbitMQNodes -ne $NUM_NODES_IN_CLUSTER ]]; then
    echo "$(timestamp) - Number of RabbitMQ nodes: $numOfRabbitMQNodes discovered to form RabbitMQ cluster is incorrect after the timeout period, aborting" >> $CONFD_LOGFILE
    exit 1
  else
    echo "$(timestamp) - Number of RabbitMQ nodes: $numOfRabbitMQNodes, all nodes in the cluster are discovered" >> $CONFD_LOGFILE
  fi

# Loop until confd has updated the config
  until confd -onetime -node $ETCD -config-file /etc/confd/conf.d/rabbitmq.toml; do
    echo "$(timestamp) - one time update, waiting for confd to refresh rabbitmq.config." >> $CONFD_LOGFILE 
    sleep 5
  done

  echo "$(timestamp) - completed one time update." >> $CONFD_LOGFILE

# Run confd in the background to watch the nodes in etcd
  confd -interval 10 -node $ETCD -config-file /etc/confd/conf.d/rabbitmq.toml >> $CONFD_LOGFILE

  echo "$(timestamp) - confd is listening for changes on etcd..." >> $CONFD_LOGFILE
fi
