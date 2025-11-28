#!/bin/bash
# Mooncake Transfer Engine 测试环境配置文件

# ============================================
# Mooncake Transfer Engine 配置
# ============================================

# RDMA 网卡配置
# testbed01 使用 mlx5_49，testbed23 使用 mlx5_113
# 这些会在运行脚本中根据容器动态设置

# 网络接口名称（用于获取IP）
export NETWORK_IFNAME=eno0

# 是否启用自动发现（不需要metadata server）
# true: 不需要metadata server，直接通过网络发现
# false: 需要metadata server
export AUTO_DISCOVERY="${AUTO_DISCOVERY:-false}"

# Metadata Server地址（HTTP metadata server，仅当AUTO_DISCOVERY=false时需要）
# 默认使用宿主机上运行的HTTP metadata server
export METADATA_SERVER="${METADATA_SERVER:-http://10.0.11.1:8080/metadata}"

# ============================================
# Transfer Engine Benchmark 参数
# ============================================

# 测试模式：read 或 write
export OPERATION="${OPERATION:-read}"

# 传输协议：rdma, tcp, nvlink
export PROTOCOL="${PROTOCOL:-rdma}"

# 缓冲区大小（默认1GB）
export BUFFER_SIZE="${BUFFER_SIZE:-1073741824}"

# 批次大小
export BATCH_SIZE="${BATCH_SIZE:-128}"

# 每次传输的块大小
export BLOCK_SIZE="${BLOCK_SIZE:-65536}"

# 测试持续时间（秒）
export DURATION="${DURATION:-10}"

# 工作线程数
export THREADS="${THREADS:-12}"

# 是否使用GPU VRAM（需要编译支持CUDA）
export USE_VRAM="${USE_VRAM:-false}"

# GPU ID（-1表示使用所有GPU）
export GPU_ID="${GPU_ID:-0}"

# 报告单位：GB|GiB|Gb|MB|MiB|Mb|KB|KiB|Kb
export REPORT_UNIT="${REPORT_UNIT:-GB}"

# 报告精度
export REPORT_PRECISION="${REPORT_PRECISION:-2}"

# ============================================
# 容器配置
# ============================================
export CONTAINER_01="${CONTAINER_01:-yijun_testbed01}"
export CONTAINER_23="${CONTAINER_23:-yijun_testbed23}"

# 容器内的IP地址（RDMA网络）
export IP_01="${IP_01:-10.0.11.200}"
export IP_23="${IP_23:-10.2.11.200}"

# 容器内部通信的IP（Docker网络）
export DOCKER_IP_01="${DOCKER_IP_01:-172.17.0.2}"
export DOCKER_IP_23="${DOCKER_IP_23:-172.17.0.3}"

# Transfer Engine Bench 可执行文件路径
export TRANSFER_ENGINE_BENCH="${TRANSFER_ENGINE_BENCH:-/usr/wkspace/docker/testbed/Mooncake/build/mooncake-transfer-engine/example/transfer_engine_bench}"

echo "=========================================="
echo "Mooncake Transfer Engine 测试环境配置已加载"
echo "=========================================="
echo "网络配置:"
echo "  网络接口: $NETWORK_IFNAME"
echo "  自动发现: $AUTO_DISCOVERY"
if [ "$AUTO_DISCOVERY" = "false" ]; then
    echo "  Metadata Server: $METADATA_SERVER"
fi
echo ""
echo "传输配置:"
echo "  操作类型: $OPERATION"
echo "  传输协议: $PROTOCOL"
echo "  缓冲区大小: $BUFFER_SIZE"
echo "  批次大小: $BATCH_SIZE"
echo "  块大小: $BLOCK_SIZE"
echo "  持续时间: $DURATION 秒"
echo "  工作线程: $THREADS"
echo "  使用VRAM: $USE_VRAM"
echo ""
echo "容器配置:"
echo "  容器01: $CONTAINER_01 ($IP_01)"
echo "  容器23: $CONTAINER_23 ($IP_23)"
echo "=========================================="
