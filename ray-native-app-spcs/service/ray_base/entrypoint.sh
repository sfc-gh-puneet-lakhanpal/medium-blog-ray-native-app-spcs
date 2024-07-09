#!/bin/bash
set -e  # Exit on command errors
set -x  # Print each command before execution, useful for debugging

WORKLOAD=$1
eth0Ip=$(ifconfig eth0 | sed -En -e 's/.*inet ([0-9.]+).*/\1/p')
echo "WORKLOAD: $WORKLOAD"
if [ "$WORKLOAD" == "rayhead" ];
then
    if [ -z "${ENV_RAY_GRAFANA_HOST}" ]; then
            echo "Error: ENV_RAY_GRAFANA_HOST not set"
            exit 1
    fi
    if [ -z "${ENV_RAY_PROMETHEUS_HOST}" ]; then
        echo "Error: ENV_RAY_PROMETHEUS_HOST not set"
        exit 1
    fi
    export RAY_GRAFANA_HOST=$ENV_RAY_GRAFANA_HOST
    export RAY_PROMETHEUS_HOST=$ENV_RAY_PROMETHEUS_HOST
    export log_dir="/raylogs/ray"
    echo "Making log directory $log_dir..."
    mkdir -p $log_dir
    export RAY_ENABLE_RECORD_ACTOR_TASK_LOGGING=1
    export RAY_BACKEND_LOG_LEVEL=debug
    export HOST_IP="$eth0Ip"
    export NCCL_DEBUG=INFO
    export NCCL_SOCKET_IFNAME=eth0
    jupyter lab --generate-config
    nohup jupyter lab --ip='*' --port=8888 --no-browser --allow-root --NotebookApp.password='' --NotebookApp.token='' & 
    #nohup jupyter notebook --allow-root --ip=0.0.0.0 --port=8888 --no-browser --NotebookApp.token='' --NotebookApp.password='' &
    ray start --node-ip-address="$eth0Ip" --head --disable-usage-stats --port=6379 --dashboard-host=0.0.0.0 --object-manager-port=8076 --node-manager-port=8077 --dashboard-agent-grpc-port=8079 --dashboard-agent-listen-port=8081 --metrics-export-port=8082 --ray-client-server-port=10001 --dashboard-port=8265 --temp-dir=$log_dir --block
elif [ "$WORKLOAD" == "rayworker" ];
then
    if [ -z "${RAY_HEAD_ADDRESS}" ]; then
        echo "Error: RAY_HEAD_ADDRESS not set"
        exit 1
    fi
    export RAY_ENABLE_RECORD_ACTOR_TASK_LOGGING=1
    export RAY_BACKEND_LOG_LEVEL=debug
    export HOST_IP="$eth0Ip"
    export NCCL_DEBUG=INFO
    export NCCL_SOCKET_IFNAME=eth0
    ray start --node-ip-address="$eth0Ip" --disable-usage-stats --address=${RAY_HEAD_ADDRESS} --object-manager-port=8076 --node-manager-port=8077 --dashboard-agent-grpc-port=8079 --dashboard-agent-listen-port=8081 --metrics-export-port=8082 --block
elif [ "$WORKLOAD" == "raycustomworker" ];
then
    if [ -z "${RAY_HEAD_ADDRESS}" ]; then
        echo "Error: RAY_HEAD_ADDRESS not set"
        exit 1
    fi
    export RAY_ENABLE_RECORD_ACTOR_TASK_LOGGING=1
    export RAY_BACKEND_LOG_LEVEL=debug
    export HOST_IP="$eth0Ip"
    export NCCL_DEBUG=INFO
    export NCCL_SOCKET_IFNAME=eth0
    ray start --node-ip-address="$eth0Ip" --disable-usage-stats --address=${RAY_HEAD_ADDRESS} --resources='{"custom_worker": 1}' --object-manager-port=8076 --node-manager-port=8077 --dashboard-agent-grpc-port=8079 --dashboard-agent-listen-port=8081 --metrics-export-port=8082 --block
fi