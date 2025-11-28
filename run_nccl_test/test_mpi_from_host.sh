#!/bin/bash
# 快速测试 MPI 从主机连接到容器

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/env_config.sh"

echo "测试 MPI 从主机访问容器..."
echo ""

# 简单的 hostname 测试
mpirun --allow-run-as-root \
    -np 4 \
    -N 2 \
    --hostfile ${SCRIPT_DIR}/hostfile \
    --mca plm_rsh_agent ${SCRIPT_DIR}/ssh_to_container_from_host.sh \
    -x CONTAINER_NAME_01=yijun_testbed01 \
    -x CONTAINER_NAME_23=yijun_testbed23 \
    bash -c 'echo "Rank $OMPI_COMM_WORLD_RANK on $(hostname) with GPU: $(nvidia-smi -L | wc -l) GPUs"'

echo ""
echo "如果看到 4 行输出，说明 MPI 连接成功！"
