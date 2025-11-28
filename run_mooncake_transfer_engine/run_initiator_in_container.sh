#!/bin/bash
# 在容器内运行 Mooncake Transfer Engine Initiator
# 此脚本在 testbed01 容器内执行

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/env_config.sh"

echo "=========================================="
echo "Mooncake Transfer Engine Initiator（容器内运行）"
echo "=========================================="
echo ""

# 获取本地RDMA网络IP
LOCAL_IP=$(hostname -I | grep -o '10\.[0-9]\+\.11\.200' | head -1)
if [ -z "$LOCAL_IP" ]; then
    echo "警告: 无法自动获取RDMA IP，使用配置的IP"
    LOCAL_IP=$IP_01
fi

# 根据主机名/IP确定使用的RDMA网卡和目标segment
HOSTNAME=$(hostname)
if [ "$HOSTNAME" = "10-0-11-200" ] || [ "$LOCAL_IP" = "$IP_01" ]; then
    export DEVICE_NAME="mlx5_49"
    export LOCAL_SERVER_NAME="testbed01"
    export TARGET_SEGMENT_ID="testbed23"  # 访问testbed23的数据
else
    export DEVICE_NAME="mlx5_113"
    export LOCAL_SERVER_NAME="testbed23"
    export TARGET_SEGMENT_ID="testbed01"  # 访问testbed01的数据
fi

echo "容器配置:"
echo "  主机名: $HOSTNAME"
echo "  本地IP: $LOCAL_IP"
echo "  RDMA设备: $DEVICE_NAME"
echo "  服务器名称: $LOCAL_SERVER_NAME"
echo "  目标Segment ID: $TARGET_SEGMENT_ID"
echo ""

echo "Transfer Engine配置:"
echo "  模式: initiator"
echo "  操作: $OPERATION"
echo "  协议: $PROTOCOL"
echo "  自动发现: $AUTO_DISCOVERY"
if [ "$AUTO_DISCOVERY" = "false" ]; then
    echo "  元数据服务器: $METADATA_SERVER"
fi
echo "  缓冲区大小: $BUFFER_SIZE"
echo "  批次大小: $BATCH_SIZE"
echo "  块大小: $BLOCK_SIZE"
echo "  持续时间: $DURATION 秒"
echo "  工作线程: $THREADS"
echo "  使用VRAM: $USE_VRAM"
if [ "$USE_VRAM" = "true" ]; then
    echo "  GPU ID: $GPU_ID"
fi
echo ""

# 等待一下，确保target已经启动并注册
if [ "$AUTO_DISCOVERY" = "true" ]; then
    echo "等待5秒，确保target服务器已启动..."
    sleep 5
else
    echo "等待3秒，确保target服务器已注册到etcd..."
    sleep 3
fi
echo ""

# 构建命令行参数
CMD_ARGS=(
    --mode=initiator
    --operation="$OPERATION"
    --protocol="$PROTOCOL"
    --auto_discovery="$AUTO_DISCOVERY"
    --local_server_name="$LOCAL_SERVER_NAME"
    --segment_id="$TARGET_SEGMENT_ID"
    --buffer_size="$BUFFER_SIZE"
    --batch_size="$BATCH_SIZE"
    --block_size="$BLOCK_SIZE"
    --duration="$DURATION"
    --threads="$THREADS"
    --report_unit="$REPORT_UNIT"
    --report_precision="$REPORT_PRECISION"
)

# 仅当不使用自动发现时才添加metadata_server参数
if [ "$AUTO_DISCOVERY" = "false" ]; then
    CMD_ARGS+=(--metadata_server="$METADATA_SERVER")
fi

# 如果是RDMA协议，添加设备名称
if [ "$PROTOCOL" = "rdma" ]; then
    CMD_ARGS+=(--device_name="$DEVICE_NAME")
fi

# 如果使用VRAM
if [ "$USE_VRAM" = "true" ]; then
    CMD_ARGS+=(--use_vram=true)
    CMD_ARGS+=(--gpu_id="$GPU_ID")
fi

echo "=========================================="
echo "启动 Initiator 客户端..."
echo "=========================================="
echo ""

# 设置库路径（如果需要）
export LD_LIBRARY_PATH="/usr/local/lib:/usr/local/cuda/lib64:${LD_LIBRARY_PATH:-}"

# 运行 transfer_engine_bench
echo "执行命令: $TRANSFER_ENGINE_BENCH ${CMD_ARGS[@]}"
echo ""

exec "$TRANSFER_ENGINE_BENCH" "${CMD_ARGS[@]}"
