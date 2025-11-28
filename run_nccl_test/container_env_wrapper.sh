#!/bin/bash
# 容器内环境变量包装脚本
# 在执行实际命令前，先加载环境配置

# 查找 env_config.sh 的位置（容器内）
ENV_CONFIG="/usr/wkspace/docker/testbed/script/run_nccl_test/env_config.sh"

if [ -f "$ENV_CONFIG" ]; then
    # source env_config.sh 以确保所有环境变量都设置正确
    source "$ENV_CONFIG"
    echo "已加载环境配置: $ENV_CONFIG (Rank: $OMPI_COMM_WORLD_RANK)"
else
    echo "警告: 未找到 $ENV_CONFIG，使用传入的环境变量"
fi

# 打印关键环境变量（调试用）
if [ "${NCCL_DEBUG}" = "INFO" ] || [ "${NCCL_DEBUG}" = "TRACE" ]; then
    echo "容器内环境变量 (Rank $OMPI_COMM_WORLD_RANK):"
    echo "  NCCL_NET_GDR_LEVEL = ${NCCL_NET_GDR_LEVEL}"
    echo "  NCCL_IB_HCA = ${NCCL_IB_HCA}"
fi

# 执行传入的实际命令
exec "$@"
