#!/bin/bash
# NCCL All-Reduce 性能测试启动脚本

set -e  # 遇到错误立即退出

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
SSH_KEY="${SSH_KEY:-/usr/wkspace/.ssh/id_rsa}"
SSH_USER="${SSH_USER:-yijun}"

# 检查 NCCL tests 二进制文件
if [ ! -f "${NCCL_TESTS_DIR}/build/all_reduce_perf" ]; then
    echo "错误: 找不到 all_reduce_perf"
    echo "请先编译 NCCL tests: cd ${NCCL_TESTS_DIR} && make MPI=1"
    exit 1
fi

# 检查 hostfile
if [ ! -f "${HOSTFILE}" ]; then
    echo "错误: 找不到 hostfile: ${HOSTFILE}"
    echo "请创建 hostfile 或使用 hostfile.example 作为模板"
    echo "cp ${SCRIPT_DIR}/hostfile.example ${HOSTFILE}"
    exit 1
fi

# ============================================
# 3. 打印测试配置
# ============================================
echo ""
echo "=========================================="
echo "NCCL All-Reduce 测试配置"
echo "=========================================="
echo "NCCL Tests 目录: ${NCCL_TESTS_DIR}"
echo "Hostfile: ${HOSTFILE}"
echo "测试程序: all_reduce_perf"
echo ""
echo "MPI 配置:"
echo "  总进程数 (-np): ${TOTAL_PROCS}"
echo "  每节点进程数 (-N): ${PROCS_PER_NODE}"
echo "  节点数: ${TOTAL_NODES}"
echo "  SSH 代理: ssh_to_container.sh (容器环境)"
echo "  SSH 用户: ${SSH_USER}"
echo "  SSH 密钥: ${SSH_KEY}"
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
# 4. 运行测试
# ============================================
echo "开始运行 NCCL All-Reduce 测试..."
echo ""

# 构建 MPI 命令
# 使用自定义 SSH 包装脚本让 MPI 能够进入远程容器
# 可选：通过环境变量切换 MPI 传输层
# - OMPI_USE_UCX=1 时使用 UCX（需要 OpenMPI 编译了 UCX 支持）
# - 否则使用默认配置（允许 TCP，自适应选择，不强行禁用 TCP）
MPI_XPORT_FLAGS=""
if [[ "${OMPI_USE_UCX:-0}" == "1" ]]; then
    MPI_XPORT_FLAGS="--mca pml ucx --mca btl ^openib --mca osc ucx"
fi

# 可选：限制 TCP/OOB 使用的网卡接口，避免多网卡造成的进程错连
# 若未显式设置 MPI_TCP_IFNAME，则自动根据 hostfile 中的对端路由探测
detect_iface() {
    local hostfile="$1"
    local me1 me2 peer ip iface
    me1="$(hostname -s 2>/dev/null || hostname)"
    me2="$(hostname 2>/dev/null || echo "$me1")"
    # 取第一个非注释、非空行的主机名
    while read -r h; do
        [[ -z "$h" || "$h" == \#* ]] && continue
        h="${h%% *}"  # 去掉 slots= 等附加字段
        [[ "$h" == "localhost" || "$h" == "$me1" || "$h" == "$me2" ]] && continue
        peer="$h"; break
    done < <(awk '!/^\s*#/ && NF {print $1}' "$hostfile")

    # 若未找到对端（单机），直接返回
    [[ -z "$peer" ]] && return 0

    # 解析对端 IP
    ip="$(getent ahostsv4 "$peer" 2>/dev/null | awk '/STREAM/ {print $1; exit}')"
    [[ -z "$ip" ]] && ip="$(getent hosts "$peer" 2>/dev/null | awk '{print $1; exit}')"
    [[ -z "$ip" ]] && ip="$peer"

    # 根据路由推断本机到对端所用接口
    iface="$(ip -o route get "$ip" 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="dev") {print $(i+1); exit}}')"
    if [[ -n "$iface" ]]; then
        echo "$iface"
        return 0
    fi
    return 1
}

MPI_IFACE_FLAGS=""
if [[ -z "${MPI_TCP_IFNAME:-}" ]]; then
    auto_iface="$(detect_iface "${HOSTFILE}")"
    if [[ -n "$auto_iface" ]]; then
        export MPI_TCP_IFNAME="$auto_iface"
        echo "已自动选择 MPI 接口: $MPI_TCP_IFNAME"
    fi
fi
if [[ -n "${MPI_TCP_IFNAME:-}" ]]; then
    MPI_IFACE_FLAGS="--mca btl_tcp_if_include ${MPI_TCP_IFNAME} --mca oob_tcp_if_include ${MPI_TCP_IFNAME}"
fi

MPI_CMD="mpirun \
    --allow-run-as-root \
    -np ${TOTAL_PROCS} \
    -N ${PROCS_PER_NODE} \
    --hostfile ${HOSTFILE} \
    --mca plm_rsh_agent ${SCRIPT_DIR}/ssh_to_local_container.sh \
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
    ${SCRIPT_DIR}/container_env_wrapper.sh \
    ${SCRIPT_DIR}/gpu_binding.sh \
    ${NCCL_TESTS_DIR}/build/all_reduce_perf \
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
# 5. 完成
# ============================================
echo ""
echo "=========================================="
echo "测试完成!"
echo "=========================================="
