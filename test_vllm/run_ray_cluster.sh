#!/bin/bash
# ./run_ray_cluster.sh -model facebook/opt-6.7b -port 2345 -tp 2 -pp 1
# Function to display help information

show_help() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -model MODEL_NAME  Model name (default: Qwen/Qwen2-7B-Instruct)"
    echo "  -port PORT        Service port (default: 2345)"
    echo "  -tp TP_SIZE      Tensor parallel size (default: 2)"
    echo "  -pp PP_SIZE      Pipeline parallel size (default: 1)"
    echo "  -h               Show this help message"
    exit 1
}

# Set environment variables
export VLLM_HOST_IP=$(hostname -i)
export NCCL_SOCKET_IFNAME=eth0
export GLOO_SOCKET_IFNAME=eth0
export TP_SOCKET_IFNAME=eth0

# Default values
MODEL_NAME="facebook/opt-6.7b"
SERVE_PORT=2345
TENSOR_PARALLEL_SIZE=2
PIPELINE_PARALLEL_SIZE=1

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -model)
            MODEL_NAME="$2"
            shift 2
            ;;
        -port)
            SERVE_PORT="$2"
            shift 2
            ;;
        -tp)
            TENSOR_PARALLEL_SIZE="$2"
            shift 2
            ;;
        -pp)
            PIPELINE_PARALLEL_SIZE="$2"
            shift 2
            ;;
        -h)
            show_help
            ;;
        *)
            echo "Unknown argument: $1"
            show_help
            ;;
    esac
done

# Print current configuration
echo "Current configuration:"
echo "Model: $MODEL_NAME"
echo "Port: $SERVE_PORT"
echo "Tensor parallel size: $TENSOR_PARALLEL_SIZE"
echo "Pipeline parallel size: $PIPELINE_PARALLEL_SIZE"

if [ "$SING_RANK" = "0" ]; then
    export SELF_IP=$(hostname -i)
    echo "[INFO] Launching Ray HEAD node on IP: $SELF_IP"
    ray start --head --port=6379 --redis-password=123456 --node-ip-address=$SELF_IP
    
    echo "[INFO] Waiting for Ray to be ready..."
    while ! ray status --address=$SELF_IP:6379 >/dev/null 2>&1; do
        sleep 1
    done
    echo "[INFO] Ray is ready!"
    
    # Wait until enough GPUs are available
    EXPECTED_GPU_COUNT=$((TENSOR_PARALLEL_SIZE * PIPELINE_PARALLEL_SIZE))
    echo "[INFO] Waiting for $EXPECTED_GPU_COUNT GPUs to be available..."
    
    while true; do
        ACTUAL_GPU_COUNT=$(ray status --address=$SELF_IP:6379 2>/dev/null | grep "GPU" | awk -F'/' '{print $2}' | awk '{print int($1)}')
        if [ "$ACTUAL_GPU_COUNT" -ge "$EXPECTED_GPU_COUNT" ]; then
            echo "[INFO] GPU count check passed. Found $ACTUAL_GPU_COUNT GPUs."
            break
        fi
        echo "[INFO] Current GPU count: $ACTUAL_GPU_COUNT, waiting for more GPUs..."
        sleep 5
    done
    
    if [ -f /etc/profile ]; then
        source /etc/profile
    fi
    if [ -f ~/.bashrc ]; then
        source ~/.bashrc
    fi
    
    vllm serve $MODEL_NAME --trust-remote-code --port $SERVE_PORT \
        --tensor-parallel-size $TENSOR_PARALLEL_SIZE \
        --pipeline-parallel-size $PIPELINE_PARALLEL_SIZE
    wait
else
    sleep 10
    export MASTER_IP=$(getent hosts "$SING_MASTER_ADDR" | awk 'NR==1 {print $1}')
    export SELF_IP=$(hostname -i)
    echo "[INFO] Launching Ray WORKER node. Master IP: $MASTER_IP, Self IP: $SELF_IP"
    ray start --address=$MASTER_IP:6379 --redis-password=123456 --node-ip-address=$SELF_IP --block
fi