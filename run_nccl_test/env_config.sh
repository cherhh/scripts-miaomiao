#!/bin/bash
# NCCL 测试环境配置文件

# ============================================
# NCCL 网络配置 (根据实际环境调整)
# ============================================

# 网络配置 - RDMA 模式
# NCCL_IB_HCA 会在运行脚本中根据容器动态设置
# testbed01 使用 mlx5_49，testbed23 使用 mlx5_113
export NCCL_IB_GID_INDEX=3                 # GID Index（RoCEv2 常用 3）
export NCCL_IB_DISABLE=0                   # 启用 IB/RDMA
export NCCL_NET_GDR_LEVEL=0                # 禁用 GPU Direct RDMA (RTX 3090 不支持)
export NCCL_P2P_LEVEL=SYS                  # P2P 级别：NVL/PIX/PHB/SYS

# 算法选择 (强制使用 Ring AllReduce)
export NCCL_ALGO=Ring                      # 算法: Ring/Tree/CollNetDirect/CollNetChain
# export NCCL_PROTO=Simple                 # 协议: Simple/LL/LL128 (可选，让 NCCL 自动选择)

# ============================================

# ============================================
# NCCL 性能优化
# ============================================
export NCCL_BUFFSIZE=2097152               # 2MB 缓冲区
export NCCL_NTHREADS=512                   # NCCL 线程数
export NCCL_IB_TIMEOUT=22                  # IB 超时

# ============================================
# NCCL 调试信息 (生产环境可以关闭)
# ============================================
export NCCL_DEBUG=INFO                     # 调试级别: VERSION/WARN/INFO/TRACE
export NCCL_DEBUG_SUBSYS=INIT,NET          # 子系统: INIT/GRAPH/ENV/TUNING/NET/ALL

# ============================================
# MPI/SSH 配置
# ============================================
export SSH_USER="${SSH_USER:-yijun}"       # SSH 登录用户名
export OMPI_MCA_plm_rsh_args="-o StrictHostKeyChecking=no"  # SSH 配置

# ============================================
# Open MPI 网络接口选择（建议设置）
# 多网卡环境下显式限制 TCP/OOB 使用的接口，避免错连
export MPI_TCP_IFNAME=${MPI_TCP_IFNAME:-eno0}

# 可选：是否使用 UCX（需 Open MPI 编译了 UCX）
export OMPI_USE_UCX=${OMPI_USE_UCX:-0}

# ============================================
# GPU 可见性
# ============================================
# 固定设备顺序，确保 CUDA_VISIBLE_DEVICES 按索引而非 PCI 总线 ID
export CUDA_DEVICE_ORDER=FASTEST_FIRST
# 不在这里设置 CUDA_VISIBLE_DEVICES，让 gpu_binding.sh 为每个进程单独设置

# ============================================
# 测试参数配置
# ============================================
export TEST_MIN_BYTES=4M                   # 最小测试数据大小（从 4MB 开始）
export TEST_MAX_BYTES=1G                     # 最大测试数据大小
export TEST_FACTOR=2                       # 数据增长因子
export TEST_GPUS_PER_PROC=1                # 每个进程使用的 GPU 数

# 增加 NCCL 通道数量（提高并行度）
export NCCL_MIN_NCHANNELS=${NCCL_MIN_NCHANNELS:-8}
export NCCL_MAX_NCHANNELS=${NCCL_MAX_NCHANNELS:-8}

# ============================================
# 集群配置 (本地双容器模式)
# ============================================
export TOTAL_NODES=2                       # 总容器数
export PROCS_PER_NODE=2                    # 每容器进程数 (每 GPU 1 进程 × 2 GPU)
export TOTAL_PROCS=$((TOTAL_NODES * PROCS_PER_NODE))  # 总进程数 = 4

echo "=========================================="
echo "NCCL 测试环境配置已加载"
echo "=========================================="
echo "网络配置:"
echo "  NCCL_IB_HCA: $NCCL_IB_HCA"
echo "  NCCL_IB_GID_INDEX: $NCCL_IB_GID_INDEX"
echo "  NCCL_IB_DISABLE: $NCCL_IB_DISABLE"
echo "  MPI_TCP_IFNAME: $MPI_TCP_IFNAME"
echo "  OMPI_USE_UCX: $OMPI_USE_UCX"
echo ""
echo "GPU 配置:"
echo "  每个进程由 gpu_binding.sh 自动绑定到单独的 GPU"
echo ""
echo "集群配置:"
echo "  总节点数: $TOTAL_NODES"
echo "  每节点进程数: $PROCS_PER_NODE"
echo "  总进程数: $TOTAL_PROCS"
echo ""
echo "测试参数:"
echo "  数据大小范围: $TEST_MIN_BYTES - $TEST_MAX_BYTES"
echo "  增长因子: $TEST_FACTOR"
echo "=========================================="
