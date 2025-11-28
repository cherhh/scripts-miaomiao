#!/bin/bash

# Node 0 启动脚本 - All-to-All 测试
# 这是主节点，使用localhost作为MASTER_ADDR

# NCCL配置
export NCCL_DEBUG=INFO
export NCCL_IB_HCA=mlx5_0
export NCCL_IB_GID_INDEX=3
export NCCL_SHM_DISABLE=1
export NCCL_P2P_DISABLE=1

# 分布式训练配置
export MASTER_ADDR=localhost
export MASTER_PORT=12345
export CUDA_VISIBLE_DEVICES=0

# 消息大小 (默认4 MiB)
MSG_BYTES=${MSG_BYTES:-$((4 * 1024 * 1024))}

echo "=========================================="
echo "Node 0 启动配置"
echo "=========================================="
echo "MASTER_ADDR: $MASTER_ADDR"
echo "MASTER_PORT: $MASTER_PORT"
echo "MSG_BYTES: $MSG_BYTES"
echo "CUDA_VISIBLE_DEVICES: $CUDA_VISIBLE_DEVICES"
echo "=========================================="

# 启动torchrun（MoE all_to_all_single 测试）
torchrun --nnodes=2 --nproc_per_node=1 --node_rank=0 \
  --master_addr=$MASTER_ADDR --master_port=$MASTER_PORT \
  ./test_all2all/imbalance_alltoall.py \
  --msg-bytes=$MSG_BYTES
