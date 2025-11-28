#!/bin/bash
# 共享配置文件 - All-to-All 测试

# NCCL 配置
export NCCL_DEBUG=INFO
export NCCL_IB_HCA=mlx5_0
export NCCL_IB_GID_INDEX=3
export NCCL_SHM_DISABLE=1
export NCCL_P2P_DISABLE=1

# 分布式训练配置
export MASTER_PORT=12345
export NNODES=2
export NPROC_PER_NODE=1

# 默认消息大小 (4 MiB)
export MSG_BYTES=${MSG_BYTES:-$((4 * 1024 * 1024))}

# 函数：打印配置信息
print_config() {
    local node_rank=$1
    echo "=========================================="
    echo "Node ${node_rank} 启动配置"
    echo "=========================================="
    echo "MASTER_ADDR: $MASTER_ADDR"
    echo "MASTER_PORT: $MASTER_PORT"
    echo "NODE_RANK: $node_rank"
    echo "NNODES: $NNODES"
    echo "NPROC_PER_NODE: $NPROC_PER_NODE"
    echo "MSG_BYTES: $MSG_BYTES"
    echo "CUDA_VISIBLE_DEVICES: $CUDA_VISIBLE_DEVICES"
    echo "=========================================="
}

# 函数：启动训练
run_training() {
    local node_rank=$1
    torchrun \
        --nnodes=$NNODES \
        --nproc_per_node=$NPROC_PER_NODE \
        --node_rank=$node_rank \
        --master_addr=$MASTER_ADDR \
        --master_port=$MASTER_PORT \
        ./test_all2all/imbalance_alltoall.py \
        --msg-bytes=$MSG_BYTES
}
