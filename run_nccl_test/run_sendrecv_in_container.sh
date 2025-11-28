#!/bin/bash
# 在容器内运行 NCCL Send/Recv 测试
# 此脚本在 testbed01 容器内执行

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/env_config.sh"

# 配置 NCCL 库路径（优先使用本地编译版本）
NCCL_LIB_DIR=${NCCL_LIB_DIR:-/usr/wkspace/docker/testbed/nccl/build/lib}
export NCCL_LIB_DIR

# 设置 LD_LIBRARY_PATH
if [[ -n "${LD_LIBRARY_PATH:-}" ]]; then
  export LD_LIBRARY_PATH="${NCCL_LIB_DIR}:${LD_LIBRARY_PATH}"
else
  export LD_LIBRARY_PATH="${NCCL_LIB_DIR}:/usr/local/cuda/lib64"
fi

echo "=========================================="
echo "NCCL Send/Recv 测试（容器内运行）"
echo "=========================================="
echo ""

# 获取两个容器的 RDMA 网络 IP（10.x.11.200）
IP1=$(hostname -I | grep -o '10\.[0-9]\+\.11\.200' | head -1)
IP2=$(ssh -o StrictHostKeyChecking=no 172.17.0.3 "hostname -I" | grep -o '10\.[0-9]\+\.11\.200' | head -1)

# 如果无法获取 IP，使用默认值
if [ -z "$IP1" ]; then
    IP1="10.0.11.200"
fi
if [ -z "$IP2" ]; then
    IP2="10.2.11.200"
fi

# 强制使用 RDMA 网络接口（eno0）
export NCCL_SOCKET_IFNAME=eno0

# 统一调度器 Unix socket
export NCCL_UNIFIED_SCHED_SOCKET=/tmp/usched.sock

# 设置 NCCL 日志级别（如果未设置）
# NCCL_DEBUG: WARN, INFO, TRACE
# NCCL_DEBUG_SUBSYS: INIT, COLL, P2P, SHM, NET, GRAPH, TUNING, ENV, ALLOC, ALL
export NCCL_DEBUG=${NCCL_DEBUG:-INFO}
export NCCL_DEBUG_SUBSYS=${NCCL_DEBUG_SUBSYS:-NET}

echo "容器配置:"
echo "  testbed01 (本地): $IP1 - 2 GPU"
echo "  testbed23 (远程): $IP2 - 2 GPU"
echo "  总进程数: 4 (每容器 2 个)"
echo ""

echo "NCCL 配置:"
echo "  NCCL 库路径: ${NCCL_LIB_DIR}"
echo "  网络接口: ${NCCL_SOCKET_IFNAME}"
echo "  日志级别: ${NCCL_DEBUG}"
echo "  日志子系统: ${NCCL_DEBUG_SUBSYS}"
echo ""

# 创建临时 hostfile
HOSTFILE="/tmp/nccl_hostfile_in_container"
cat > $HOSTFILE << EOF
$IP1 slots=2
$IP2 slots=2
EOF

echo "Hostfile 内容:"
cat $HOSTFILE
echo ""

echo "测试参数:"
echo "  数据大小范围: ${TEST_MIN_BYTES} - ${TEST_MAX_BYTES}"
echo "  增长因子: ${TEST_FACTOR}"
echo "=========================================="
echo ""

# 检查 SSH 连接
echo ">>> 检查 SSH 连接..."
if ssh -o StrictHostKeyChecking=no $IP2 "echo 'SSH OK'" 2>/dev/null | grep -q "SSH OK"; then
    echo "✓ SSH 连接正常"
else
    echo "✗ SSH 连接失败！请先运行 setup_ssh_between_containers.sh"
    exit 1
fi
echo ""

echo ">>> 开始运行 NCCL Send/Recv 测试..."
echo ""

# 创建一个包装脚本，根据主机名设置 NCCL_IB_HCA
cat > /tmp/nccl_ib_wrapper.sh << 'WRAPPER_EOF'
#!/bin/bash
# 根据主机名设置 NCCL_IB_HCA
HOSTNAME=$(hostname)
if [ "$HOSTNAME" = "10-0-11-200" ]; then
    export NCCL_IB_HCA=mlx5_49
else
    export NCCL_IB_HCA=mlx5_113
fi
exec "$@"
WRAPPER_EOF
chmod +x /tmp/nccl_ib_wrapper.sh

# 将包装脚本复制到远程容器
scp -q /tmp/nccl_ib_wrapper.sh $IP2:/tmp/

# 运行 MPI 测试
mpirun --allow-run-as-root \
    -np 4 \
    -N 2 \
    --hostfile $HOSTFILE \
    --map-by ppr:2:node \
    --bind-to none \
    --mca btl_tcp_if_exclude lo,docker0 \
    --mca btl ^openib,ofi \
    --mca pml ob1 \
    -x LD_LIBRARY_PATH \
    -x NCCL_LIB_DIR \
    -x NCCL_DEBUG \
    -x NCCL_DEBUG_SUBSYS \
    -x NCCL_IB_GID_INDEX \
    -x NCCL_IB_DISABLE \
    -x NCCL_NET_GDR_LEVEL \
    -x NCCL_P2P_LEVEL \
    -x NCCL_ALGO \
    -x NCCL_SOCKET_IFNAME \
    -x NCCL_UNIFIED_SCHED_SOCKET \
    -x NCCL_BUFFSIZE \
    -x NCCL_NTHREADS \
    -x NCCL_IB_TIMEOUT \
    -x NCCL_MIN_NCHANNELS \
    -x NCCL_MAX_NCHANNELS \
    /tmp/nccl_ib_wrapper.sh \
    ${SCRIPT_DIR}/gpu_binding.sh \
    /usr/wkspace/docker/testbed/nccl-tests/build/sendrecv_perf \
    -b ${TEST_MIN_BYTES} \
    -e ${TEST_MAX_BYTES} \
    -f ${TEST_FACTOR} \
    -g 1

echo ""
echo "=========================================="
echo "测试完成！"
echo "=========================================="
