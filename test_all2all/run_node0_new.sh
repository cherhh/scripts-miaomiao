#!/bin/bash

# Node 0 启动脚本 - 主节点

# 加载共享配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

# Node 0 特定配置
export MASTER_ADDR=localhost
export CUDA_VISIBLE_DEVICES=0
NODE_RANK=0

# 打印配置
print_config $NODE_RANK

# 启动训练
run_training $NODE_RANK
