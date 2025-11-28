#!/bin/bash
# 从宿主机启动 Mooncake Transfer Engine 双向 Benchmark
# 在两个容器中同时运行 target 和 initiator，测试双向传输

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/env_config.sh"

echo "=========================================="
echo "Mooncake Transfer Engine 双向 Benchmark"
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
if ! docker exec "$CONTAINER_01" test -f "$TRANSFER_ENGINE_BENCH"; then
    echo "错误: 在 $CONTAINER_01 中未找到 $TRANSFER_ENGINE_BENCH"
    exit 1
fi

if ! docker exec "$CONTAINER_23" test -f "$TRANSFER_ENGINE_BENCH"; then
    echo "错误: 在 $CONTAINER_23 中未找到 $TRANSFER_ENGINE_BENCH"
    exit 1
fi
echo "✓ 可执行文件检查通过"
echo ""

# 检查metadata server（仅当不使用auto_discovery时）
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

echo "双向测试配置:"
echo "  操作类型: $OPERATION"
echo "  传输协议: $PROTOCOL"
echo "  缓冲区大小: $BUFFER_SIZE 字节"
echo "  批次大小: $BATCH_SIZE"
echo "  块大小: $BLOCK_SIZE 字节"
echo "  持续时间: $DURATION 秒"
echo "  工作线程: $THREADS"
echo ""

echo "测试方向:"
echo "  方向1: $CONTAINER_01 ($IP_01, mlx5_49) -> $CONTAINER_23 ($IP_23, mlx5_113)"
echo "  方向2: $CONTAINER_23 ($IP_23, mlx5_113) -> $CONTAINER_01 ($IP_01, mlx5_49)"
echo ""

# 创建日志目录
LOG_DIR="${SCRIPT_DIR}/logs"
mkdir -p "$LOG_DIR"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

echo "=========================================="
echo ">>> 阶段 1: 启动两个 Target 服务器"
echo "=========================================="
echo ""

# 在testbed01启动target
echo "在 $CONTAINER_01 启动 target..."
docker exec -d "$CONTAINER_01" bash -c "
export AUTO_DISCOVERY='$AUTO_DISCOVERY'
export METADATA_SERVER='$METADATA_SERVER'
export PROTOCOL='$PROTOCOL'
export BUFFER_SIZE='$BUFFER_SIZE'
export USE_VRAM='$USE_VRAM'
export GPU_ID='$GPU_ID'
export REPORT_UNIT='$REPORT_UNIT'
export REPORT_PRECISION='$REPORT_PRECISION'
cd /usr/wkspace/docker/testbed/script/run_mooncake_transfer_engine
bash run_target_in_container.sh
" > "${LOG_DIR}/target_01_${TIMESTAMP}.log" 2>&1

# 在testbed23启动target
echo "在 $CONTAINER_23 启动 target..."
docker exec -d "$CONTAINER_23" bash -c "
export AUTO_DISCOVERY='$AUTO_DISCOVERY'
export METADATA_SERVER='$METADATA_SERVER'
export PROTOCOL='$PROTOCOL'
export BUFFER_SIZE='$BUFFER_SIZE'
export USE_VRAM='$USE_VRAM'
export GPU_ID='$GPU_ID'
export REPORT_UNIT='$REPORT_UNIT'
export REPORT_PRECISION='$REPORT_PRECISION'
cd /usr/wkspace/docker/testbed/script/run_mooncake_transfer_engine
bash run_target_in_container.sh
" > "${LOG_DIR}/target_23_${TIMESTAMP}.log" 2>&1

echo "两个 target 服务器已启动"
echo "等待 8 秒让 target 完成初始化和注册..."
sleep 8
echo ""

echo "=========================================="
echo ">>> 阶段 2: 方向1测试 ($CONTAINER_01 -> $CONTAINER_23)"
echo "=========================================="
echo ""

INITIATOR_01_LOG="${LOG_DIR}/initiator_01_to_23_${TIMESTAMP}.log"
echo "日志文件: $INITIATOR_01_LOG"
echo ""

# testbed01作为initiator访问testbed23的数据
docker exec "$CONTAINER_01" bash -c "
export AUTO_DISCOVERY='$AUTO_DISCOVERY'
export METADATA_SERVER='$METADATA_SERVER'
export OPERATION='$OPERATION'
export PROTOCOL='$PROTOCOL'
export BUFFER_SIZE='$BUFFER_SIZE'
export BATCH_SIZE='$BATCH_SIZE'
export BLOCK_SIZE='$BLOCK_SIZE'
export DURATION='$DURATION'
export THREADS='$THREADS'
export USE_VRAM='$USE_VRAM'
export GPU_ID='$GPU_ID'
export REPORT_UNIT='$REPORT_UNIT'
export REPORT_PRECISION='$REPORT_PRECISION'
cd /usr/wkspace/docker/testbed/script/run_mooncake_transfer_engine
bash run_initiator_in_container.sh
" 2>&1 | tee "$INITIATOR_01_LOG"

RESULT_01=$?
echo ""
if [ $RESULT_01 -eq 0 ]; then
    echo "✓ 方向1测试完成"
else
    echo "✗ 方向1测试失败"
fi
echo ""

# 等待一下再开始下一个方向
echo "等待 3 秒后开始方向2测试..."
sleep 3
echo ""

echo "=========================================="
echo ">>> 阶段 3: 方向2测试 ($CONTAINER_23 -> $CONTAINER_01)"
echo "=========================================="
echo ""

INITIATOR_23_LOG="${LOG_DIR}/initiator_23_to_01_${TIMESTAMP}.log"
echo "日志文件: $INITIATOR_23_LOG"
echo ""

# testbed23作为initiator访问testbed01的数据
docker exec "$CONTAINER_23" bash -c "
export AUTO_DISCOVERY='$AUTO_DISCOVERY'
export METADATA_SERVER='$METADATA_SERVER'
export OPERATION='$OPERATION'
export PROTOCOL='$PROTOCOL'
export BUFFER_SIZE='$BUFFER_SIZE'
export BATCH_SIZE='$BATCH_SIZE'
export BLOCK_SIZE='$BLOCK_SIZE'
export DURATION='$DURATION'
export THREADS='$THREADS'
export USE_VRAM='$USE_VRAM'
export GPU_ID='$GPU_ID'
export REPORT_UNIT='$REPORT_UNIT'
export REPORT_PRECISION='$REPORT_PRECISION'
cd /usr/wkspace/docker/testbed/script/run_mooncake_transfer_engine
bash run_initiator_in_container.sh
" 2>&1 | tee "$INITIATOR_23_LOG"

RESULT_23=$?
echo ""
if [ $RESULT_23 -eq 0 ]; then
    echo "✓ 方向2测试完成"
else
    echo "✗ 方向2测试失败"
fi
echo ""

echo "=========================================="
echo ">>> 阶段 4: 停止所有 Target 服务器"
echo "=========================================="

# 停止所有target进程
echo "停止 $CONTAINER_01 的 target..."
docker exec "$CONTAINER_01" bash -c "pkill -f 'transfer_engine_bench.*--mode=target' || true"

echo "停止 $CONTAINER_23 的 target..."
docker exec "$CONTAINER_23" bash -c "pkill -f 'transfer_engine_bench.*--mode=target' || true"

echo "所有 target 服务器已停止"
echo ""

echo "=========================================="
echo "测试结果汇总"
echo "=========================================="
echo ""

if [ $RESULT_01 -eq 0 ] && [ $RESULT_23 -eq 0 ]; then
    echo "✓ 双向测试全部成功"
    echo ""
    echo "方向1 ($CONTAINER_01 -> $CONTAINER_23):"
    echo "  查看详情: cat $INITIATOR_01_LOG"
    if grep -q "throughput" "$INITIATOR_01_LOG"; then
        grep "throughput" "$INITIATOR_01_LOG" | tail -1
    fi
    echo ""
    echo "方向2 ($CONTAINER_23 -> $CONTAINER_01):"
    echo "  查看详情: cat $INITIATOR_23_LOG"
    if grep -q "throughput" "$INITIATOR_23_LOG"; then
        grep "throughput" "$INITIATOR_23_LOG" | tail -1
    fi
    echo ""
    echo "Target 日志:"
    echo "  $CONTAINER_01: cat ${LOG_DIR}/target_01_${TIMESTAMP}.log"
    echo "  $CONTAINER_23: cat ${LOG_DIR}/target_23_${TIMESTAMP}.log"
    exit 0
else
    echo "✗ 部分测试失败"
    if [ $RESULT_01 -ne 0 ]; then
        echo "  方向1失败: 查看 $INITIATOR_01_LOG"
    fi
    if [ $RESULT_23 -ne 0 ]; then
        echo "  方向2失败: 查看 $INITIATOR_23_LOG"
    fi
    echo ""
    echo "Target 日志:"
    echo "  $CONTAINER_01: cat ${LOG_DIR}/target_01_${TIMESTAMP}.log"
    echo "  $CONTAINER_23: cat ${LOG_DIR}/target_23_${TIMESTAMP}.log"
    exit 1
fi
