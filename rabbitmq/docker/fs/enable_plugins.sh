#!/bin/sh

CONFD_LOGFILE="/var/log/rabbitmq/confd.log"

/usr/sbin/rabbitmq-plugins enable rabbitmq_management --offline &> $CONFD_LOGFILE
