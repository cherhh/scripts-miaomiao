#!/bin/bash
# 测试环境变量传递

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/env_config.sh"

HOSTFILE="${HOSTFILE:-${SCRIPT_DIR}/hostfile}"
SSH_KEY="${SSH_KEY:-/usr/wkspace/.ssh/id_rsa}"
SSH_USER="${SSH_USER:-yijun}"

echo "=========================================="
echo "环境变量传递测试"
echo "=========================================="
echo ""
echo "本地环境变量值："
echo "  NCCL_NET_GDR_LEVEL = '${NCCL_NET_GDR_LEVEL}'"
echo ""
echo "开始通过 MPI 测试环境变量传递..."
echo "=========================================="
echo ""

mpirun \
    --allow-run-as-root \
    -np ${TOTAL_PROCS} \
    -N ${PROCS_PER_NODE} \
    --hostfile ${HOSTFILE} \
    --mca plm_rsh_agent ${SCRIPT_DIR}/ssh_to_container.sh \
    -x SSH_KEY=${SSH_KEY} \
    -x SSH_USER=${SSH_USER} \
    -x CONTAINER_NAME=yijun_PDdisagg_test \
    -x NCCL_NET_GDR_LEVEL \
    -x NCCL_IB_HCA \
    -x NCCL_IB_GID_INDEX \
    -x NCCL_IB_DISABLE \
    -x NCCL_DEBUG \
    ${SCRIPT_DIR}/debug_env.sh

echo ""
echo "=========================================="
echo "测试完成"
echo "=========================================="
echo ""
echo "请检查上面的输出，确认每个进程都看到了正确的 NCCL_NET_GDR_LEVEL=0"
