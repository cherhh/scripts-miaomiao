#!/bin/bash

# Node 1 启动脚本 - 从节点

# 加载共享配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

# Node 1 特定配置
# 注意：请根据实际情况修改 MASTER_ADDR 为 node0 的 IP 地址
export MASTER_ADDR=${MASTER_ADDR:-192.168.1.251}
export CUDA_VISIBLE_DEVICES=0
NODE_RANK=1

# 打印配置
print_config $NODE_RANK

# 启动训练
run_training $NODE_RANK
