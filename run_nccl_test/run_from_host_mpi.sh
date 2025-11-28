#!/bin/bash
# 从主机运行 NCCL 测试脚本
# 此脚本在主机上执行，MPI 也在主机上运行
# 通过 docker exec 让 MPI 进程在容器内执行

set -e

# ============================================
# 1. 加载环境配置
# ============================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/env_config.sh"

# ============================================
# 2. 检查必要文件
# ============================================
NCCL_TESTS_DIR="${NCCL_TESTS_DIR:-/usr/wkspace/docker/testbed/nccl-tests}"
HOSTFILE="${HOSTFILE:-${SCRIPT_DIR}/hostfile}"

# 检查 hostfile
if [ ! -f "${HOSTFILE}" ]; then
    echo "错误: 找不到 hostfile: ${HOSTFILE}"
    exit 1
fi

# 检查容器是否运行
for container in yijun_testbed01 yijun_testbed23; do
    if ! docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
        echo "错误: 容器 ${container} 未运行"
        exit 1
    fi
done

# ============================================
# 3. 打印测试配置
# ============================================
echo ""
echo "=========================================="
echo "NCCL All-Reduce 测试配置（从主机运行）"
echo "=========================================="
echo "运行位置: 主机 (MPI 在主机，进程在容器)"
echo "容器1: yijun_testbed01 (localhost)"
echo "容器2: yijun_testbed23 (testbed23)"
echo ""
echo "MPI 配置:"
echo "  总进程数 (-np): ${TOTAL_PROCS}"
echo "  每节点进程数 (-N): ${PROCS_PER_NODE}"
echo "  节点数: ${TOTAL_NODES}"
echo "  SSH 代理: ssh_to_container_from_host.sh"
echo ""
echo "测试参数:"
echo "  最小数据大小 (-b): ${TEST_MIN_BYTES}"
echo "  最大数据大小 (-e): ${TEST_MAX_BYTES}"
echo "  增长因子 (-f): ${TEST_FACTOR}"
echo "  每进程 GPU 数 (-g): ${TEST_GPUS_PER_PROC}"
echo ""
echo "NCCL 配置:"
echo "  IB HCA: ${NCCL_IB_HCA}"
echo "  IB GID Index: ${NCCL_IB_GID_INDEX}"
echo "  调试级别: ${NCCL_DEBUG}"
echo "=========================================="
echo ""

# ============================================
# 4. 检查主机上是否有 MPI
# ============================================
if ! command -v mpirun &> /dev/null; then
    echo "错误: 主机上未找到 mpirun 命令"
    echo ""
    echo "请安装 OpenMPI:"
    echo "  sudo apt-get update"
    echo "  sudo apt-get install -y openmpi-bin openmpi-common libopenmpi-dev"
    echo ""
    echo "或者使用容器内的 MPI（需要挂载 docker socket）"
    exit 1
fi

echo "检测到 MPI 版本:"
mpirun --version | head -1
echo ""

# ============================================
# 5. 运行测试
# ============================================
echo "开始运行 NCCL All-Reduce 测试..."
echo ""

# 检测 MPI TCP 接口
detect_iface() {
    local hostfile="$1"
    local me1 me2 peer ip iface
    me1="$(hostname -s 2>/dev/null || hostname)"
    me2="$(hostname 2>/dev/null || echo "$me1")"

    while read -r h; do
        [[ -z "$h" || "$h" == \#* ]] && continue
        h="${h%% *}"
        [[ "$h" == "localhost" || "$h" == "$me1" || "$h" == "$me2" ]] && continue
        peer="$h"; break
    done < <(awk '!/^\s*#/ && NF {print $1}' "$hostfile")

    [[ -z "$peer" ]] && return 0

    ip="$(getent ahostsv4 "$peer" 2>/dev/null | awk '/STREAM/ {print $1; exit}')"
    [[ -z "$ip" ]] && ip="$(getent hosts "$peer" 2>/dev/null | awk '{print $1; exit}')"
    [[ -z "$ip" ]] && ip="$peer"

    iface="$(ip -o route get "$ip" 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="dev") {print $(i+1); exit}}')"
    if [[ -n "$iface" ]]; then
        echo "$iface"
        return 0
    fi
    return 1
}

MPI_XPORT_FLAGS=""
if [[ "${OMPI_USE_UCX:-0}" == "1" ]]; then
    MPI_XPORT_FLAGS="--mca pml ucx --mca btl ^openib --mca osc ucx"
fi

MPI_IFACE_FLAGS=""
# 对于本地双容器，不需要指定 MPI TCP 接口
# 因为都在同一主机上，MPI 可以自动选择

# 容器内的路径（用于执行的脚本和二进制文件）
CONTAINER_SCRIPT_DIR="/usr/wkspace/docker/testbed/script/run_nccl_test"
CONTAINER_NCCL_TESTS="/usr/wkspace/docker/testbed/nccl-tests"

# 构建 MPI 命令
MPI_CMD="mpirun \
    --allow-run-as-root \
    -np ${TOTAL_PROCS} \
    -N ${PROCS_PER_NODE} \
    --hostfile ${HOSTFILE} \
    --mca plm_rsh_agent ${SCRIPT_DIR}/ssh_to_container_from_host.sh \
    ${MPI_XPORT_FLAGS} \
    ${MPI_IFACE_FLAGS} \
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
    -g ${TEST_GPUS_PER_PROC}"

# 打印命令 (调试用)
echo "执行命令:"
echo "$MPI_CMD"
echo ""
echo "=========================================="
echo ""

# 执行测试
eval $MPI_CMD

# ============================================
# 6. 完成
# ============================================
echo ""
echo "=========================================="
echo "测试完成!"
echo "=========================================="
