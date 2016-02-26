#
# Dockerfile to create a docker image for RabbitMQ server 3.3.1 
#

# Pull base image
FROM arrs/arrs-cloud-base-centos6-6:2.0.0.1
MAINTAINER ARRIS

# Install Erlang 
RUN yum -y install erlang

# Install RabbitMQ server 
RUN yum -y install rabbitmq-server

# Enable RabbitMQ management plugin
#RUN /usr/sbin/rabbitmq-plugins enable rabbitmq_management

# Add binaries, configuration files and scripts
ADD fs /
WORKDIR /
RUN chmod +x /usr/local/sbin/*
RUN chmod +x /etc/confd/update_config.sh
RUN chmod +x /start_confd.sh
RUN chmod +x /enable_plugins.sh
RUN chmod +x /usr/sbin/check_rmq_health.sh

# Handle etcd json file
#RUN mkdir -p /opt/etcd/config/
#RUN mv /etcd/config/*.json /opt/etcd/config/ 

# Distribute Erlang cookie, which is needed for clustering
RUN mv /etc/rabbitmq/erlang.cookie /var/lib/rabbitmq/.erlang.cookie
RUN chmod 400 /var/lib/rabbitmq/.erlang.cookie
RUN chown rabbitmq:rabbitmq /var/lib/rabbitmq/.erlang.cookie

# Expose amqp, management, cluster, epmd ports
EXPOSE 5672 15672 25672 4369

CMD /enable_plugins.sh && /start_confd.sh
