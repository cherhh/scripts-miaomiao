#!/bin/bash
# 从宿主机启动 Mooncake Transfer Engine Benchmark
# 在两个容器中分别启动 target 和 initiator

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/env_config.sh"

echo "=========================================="
echo "Mooncake Transfer Engine Benchmark"
echo "=========================================="
echo ""

# 检查容器是否运行
echo ">>> 检查容器状态..."
if ! docker ps | grep -q "$CONTAINER_01"; then
    echo "错误: 容器 $CONTAINER_01 未运行"
    exit 1
fi

if ! docker ps | grep -q "$CONTAINER_23"; then
    echo "错误: 容器 $CONTAINER_23 未运行"
    exit 1
fi

echo "✓ 容器 $CONTAINER_01 运行中"
echo "✓ 容器 $CONTAINER_23 运行中"
echo ""

# 检查可执行文件是否存在
echo ">>> 检查 transfer_engine_bench 可执行文件..."
if docker exec "$CONTAINER_01" test -f "$TRANSFER_ENGINE_BENCH"; then
    echo "✓ 在 $CONTAINER_01 中找到 $TRANSFER_ENGINE_BENCH"
else
    echo "错误: 在 $CONTAINER_01 中未找到 $TRANSFER_ENGINE_BENCH"
    echo "请先编译 Mooncake transfer engine"
    exit 1
fi

if docker exec "$CONTAINER_23" test -f "$TRANSFER_ENGINE_BENCH"; then
    echo "✓ 在 $CONTAINER_23 中找到 $TRANSFER_ENGINE_BENCH"
else
    echo "错误: 在 $CONTAINER_23 中未找到 $TRANSFER_ENGINE_BENCH"
    echo "请先编译 Mooncake transfer engine"
    exit 1
fi
echo ""

# 检查metadata server是否运行（仅当不使用auto_discovery时）
if [ "$AUTO_DISCOVERY" = "false" ]; then
    echo ">>> 检查 Metadata Server..."
    # 尝试访问metadata server（从容器内）
    if docker exec "$CONTAINER_01" bash -c "curl -s -o /dev/null -w '%{http_code}' '${METADATA_SERVER}'" 2>/dev/null | grep -q "200\|404"; then
        echo "✓ Metadata Server 可访问 ($METADATA_SERVER)"
    else
        echo "✗ 警告: Metadata Server 可能未运行 ($METADATA_SERVER)"
        echo "如果测试失败，请确保metadata server正在运行"
        echo "或者使用 AUTO_DISCOVERY=true"
    fi
    echo ""
else
    echo ">>> 使用自动发现模式（不需要 metadata server）"
    echo ""
fi

echo "测试配置:"
echo "  操作类型: $OPERATION"
echo "  传输协议: $PROTOCOL"
echo "  缓冲区大小: $BUFFER_SIZE 字节"
echo "  批次大小: $BATCH_SIZE"
echo "  块大小: $BLOCK_SIZE 字节"
echo "  持续时间: $DURATION 秒"
echo "  工作线程: $THREADS"
echo ""

echo "容器配置:"
echo "  Target:     $CONTAINER_23 ($IP_23) - RDMA设备: mlx5_113"
echo "  Initiator:  $CONTAINER_01 ($IP_01) - RDMA设备: mlx5_49"
echo ""

# 创建日志目录
LOG_DIR="${SCRIPT_DIR}/logs"
mkdir -p "$LOG_DIR"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
TARGET_LOG="${LOG_DIR}/target_${TIMESTAMP}.log"
INITIATOR_LOG="${LOG_DIR}/initiator_${TIMESTAMP}.log"

echo "日志文件:"
echo "  Target:     $TARGET_LOG"
echo "  Initiator:  $INITIATOR_LOG"
echo ""

echo "=========================================="
echo ">>> 步骤 1: 在 $CONTAINER_23 启动 Target 服务器"
echo "=========================================="

# 在后台启动target
docker exec -d "$CONTAINER_23" bash -c "cd /usr/wkspace/docker/testbed/script/run_mooncake_transfer_engine && bash run_target_in_container.sh" > "$TARGET_LOG" 2>&1

echo "Target 服务器已在后台启动"
echo "等待 5 秒让 target 完成初始化..."
sleep 5
echo ""

echo "=========================================="
echo ">>> 步骤 2: 在 $CONTAINER_01 启动 Initiator 客户端"
echo "=========================================="
echo ""

# 启动initiator（前台运行，显示输出）
docker exec "$CONTAINER_01" bash -c "cd /usr/wkspace/docker/testbed/script/run_mooncake_transfer_engine && bash run_initiator_in_container.sh" 2>&1 | tee "$INITIATOR_LOG"

INITIATOR_EXIT_CODE=$?

echo ""
echo "=========================================="
echo ">>> 步骤 3: 停止 Target 服务器"
echo "=========================================="

# 查找并停止target进程
docker exec "$CONTAINER_23" bash -c "pkill -f 'transfer_engine_bench.*--mode=target' || true"
echo "Target 服务器已停止"
echo ""

echo "=========================================="
echo "测试完成"
echo "=========================================="
echo ""

if [ $INITIATOR_EXIT_CODE -eq 0 ]; then
    echo "✓ 测试成功完成"
    echo ""
    echo "查看完整日志:"
    echo "  Target:     cat $TARGET_LOG"
    echo "  Initiator:  cat $INITIATOR_LOG"
else
    echo "✗ 测试失败 (退出码: $INITIATOR_EXIT_CODE)"
    echo ""
    echo "请检查日志文件以了解详情:"
    echo "  Target:     cat $TARGET_LOG"
    echo "  Initiator:  cat $INITIATOR_LOG"
    exit $INITIATOR_EXIT_CODE
fi
