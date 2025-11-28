#!/bin/bash
# 简化的 NCCL 测试脚本 - 不使用 hostfile，直接运行本地双容器测试

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/env_config.sh"

CONTAINER_SCRIPT_DIR="/usr/wkspace/docker/testbed/script/run_nccl_test"
CONTAINER_NCCL_TESTS="/usr/wkspace/docker/testbed/nccl-tests"

echo "=========================================="
echo "NCCL All-Reduce 简化测试（从主机运行）"
echo "=========================================="
echo "容器: yijun_testbed01 (2 GPU) + yijun_testbed23 (2 GPU)"
echo "总进程: 4 (每容器 2 进程)"
echo "测试范围: ${TEST_MIN_BYTES} - ${TEST_MAX_BYTES}"
echo "=========================================="
echo ""

# 检查容器
for container in yijun_testbed01 yijun_testbed23; do
    if ! docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
        echo "错误: 容器 ${container} 未运行"
        exit 1
    fi
done

echo "开始运行测试..."
echo ""

# 直接运行，不使用 hostfile
# Rank 0,1 会在本地（testbed01），Rank 2,3 需要手动指定到 testbed23
# 使用简单模式：先在 testbed01 测试 2 GPU，再扩展到跨容器

# 方案：使用 --host 参数明确指定主机
mpirun --allow-run-as-root \
    -np 4 \
    --host localhost:2,testbed23:2 \
    --mca plm_rsh_agent ${SCRIPT_DIR}/ssh_to_container_from_host.sh \
    -x CONTAINER_NAME_01=yijun_testbed01 \
    -x CONTAINER_NAME_23=yijun_testbed23 \
    -x CUDA_DEVICE_ORDER \
    -x NCCL_DEBUG \
    -x NCCL_DEBUG_SUBSYS \
    -x NCCL_IB_HCA \
    -x NCCL_IB_GID_INDEX \
    -x NCCL_IB_DISABLE \
    -x NCCL_NET_GDR_LEVEL \
    -x NCCL_P2P_LEVEL \
    -x NCCL_ALGO \
    -x NCCL_PROTO \
    -x NCCL_SOCKET_IFNAME \
    -x NCCL_SHM_DISABLE \
    -x NCCL_P2P_DISABLE \
    -x NCCL_BUFFSIZE \
    -x NCCL_NTHREADS \
    -x NCCL_IB_TIMEOUT \
    -x NCCL_MIN_NCHANNELS \
    -x NCCL_MAX_NCHANNELS \
    ${CONTAINER_SCRIPT_DIR}/gpu_binding.sh \
    ${CONTAINER_NCCL_TESTS}/build/all_reduce_perf \
    -b ${TEST_MIN_BYTES} \
    -e ${TEST_MAX_BYTES} \
    -f ${TEST_FACTOR} \
    -g ${TEST_GPUS_PER_PROC}

echo ""
echo "=========================================="
echo "测试完成!"
echo "=========================================="
