#!/bin/bash
# 从主机运行 NCCL 测试的包装脚本
# 此脚本在主机上执行，通过 docker exec 在 testbed01 容器中启动 MPI

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTAINER_NAME="yijun_testbed01"

echo "=========================================="
echo "从主机启动 NCCL 测试"
echo "=========================================="
echo "主容器: ${CONTAINER_NAME}"
echo "脚本目录: ${SCRIPT_DIR}"
echo ""

# 检查容器是否运行
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "错误: 容器 ${CONTAINER_NAME} 未运行"
    exit 1
fi

# 在容器内执行测试脚本
# 设置环境变量让容器知道从主机运行
docker exec -it \
    -e RUN_FROM_HOST=1 \
    ${CONTAINER_NAME} \
    bash -c "cd /usr/wkspace/docker/testbed/script/run_nccl_test && ./run_all_reduce.sh"
