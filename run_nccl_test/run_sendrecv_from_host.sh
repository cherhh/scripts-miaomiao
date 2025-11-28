#!/bin/bash
# Send/Recv 测试脚本 - 基于 run_from_host_mpi.sh 修改

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/env_config.sh"

NCCL_TESTS_DIR="${NCCL_TESTS_DIR:-/usr/wkspace/docker/testbed/nccl-tests}"
HOSTFILE="${HOSTFILE:-${SCRIPT_DIR}/hostfile}"

# 检查容器
for container in yijun_testbed01 yijun_testbed23; do
    if ! docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
        echo "错误: 容器 ${container} 未运行"
        exit 1
    fi
done

echo ""
echo "=========================================="
echo "NCCL Send/Recv 测试（从主机运行）"
echo "=========================================="
echo "容器: yijun_testbed01 (2 GPU) + yijun_testbed23 (2 GPU)"
echo "总进程: 4"
echo "测试范围: ${TEST_MIN_BYTES} - ${TEST_MAX_BYTES}"
echo "=========================================="
echo ""

# 容器内的路径
CONTAINER_SCRIPT_DIR="/usr/wkspace/docker/testbed/script/run_nccl_test"
CONTAINER_NCCL_TESTS="/usr/wkspace/docker/testbed/nccl-tests"

# 运行测试
mpirun --allow-run-as-root \
    -np ${TOTAL_PROCS} \
    -N ${PROCS_PER_NODE} \
    --hostfile ${HOSTFILE} \
    --mca plm_rsh_agent ${SCRIPT_DIR}/ssh_to_container_from_host.sh \
    -x CONTAINER_NAME_01=yijun_testbed01 \
    -x CONTAINER_NAME_23=yijun_testbed23 \
    -x CUDA_DEVICE_ORDER \
    -x NCCL_DEBUG \
    -x NCCL_DEBUG_SUBSYS \
    -x NCCL_IB_GID_INDEX \
    -x NCCL_IB_DISABLE \
    -x NCCL_NET_GDR_LEVEL \
    -x NCCL_P2P_LEVEL \
    -x NCCL_ALGO \
    -x NCCL_SOCKET_IFNAME \
    -x NCCL_BUFFSIZE \
    -x NCCL_NTHREADS \
    -x NCCL_IB_TIMEOUT \
    -x NCCL_MIN_NCHANNELS \
    -x NCCL_MAX_NCHANNELS \
    ${CONTAINER_SCRIPT_DIR}/gpu_binding.sh \
    ${CONTAINER_NCCL_TESTS}/build/sendrecv_perf \
    -b ${TEST_MIN_BYTES} \
    -e ${TEST_MAX_BYTES} \
    -f ${TEST_FACTOR} \
    -g ${TEST_GPUS_PER_PROC}

echo ""
echo "=========================================="
echo "测试完成!"
echo "=========================================="
