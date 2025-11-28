#!/bin/bash
# 清理由 run_ray_vllm_from_host.sh 启动的 Ray + vLLM 进程

set -e

# 容器名称配置
CONTAINER_NAME_01=${CONTAINER_NAME_01:-yijun_testbed01}
CONTAINER_NAME_23=${CONTAINER_NAME_23:-yijun_testbed23}

echo "=========================================="
echo "清理 Ray + vLLM 进程"
echo "=========================================="
echo "容器配置:"
echo "  容器1: $CONTAINER_NAME_01"
echo "  容器2: $CONTAINER_NAME_23"
echo "=========================================="
echo ""

# 检查容器是否运行
echo ">>> 检查容器状态..."
CONTAINER1_RUNNING=false
CONTAINER2_RUNNING=false

if docker inspect $CONTAINER_NAME_01 >/dev/null 2>&1; then
    CONTAINER1_RUNNING=true
    echo "✓ 容器 $CONTAINER_NAME_01 正在运行"
else
    echo "⚠ 容器 $CONTAINER_NAME_01 不存在或未运行"
fi

if docker inspect $CONTAINER_NAME_23 >/dev/null 2>&1; then
    CONTAINER2_RUNNING=true
    echo "✓ 容器 $CONTAINER_NAME_23 正在运行"
else
    echo "⚠ 容器 $CONTAINER_NAME_23 不存在或未运行"
fi
echo ""

# 停止 vLLM 进程（查找并 kill）
echo ">>> 停止 vLLM 进程..."
if [ "$CONTAINER1_RUNNING" = true ]; then
    VLLM_PIDS=$(docker exec $CONTAINER_NAME_01 bash -c "ps aux | grep '[v]llm serve' | awk '{print \$2}'" 2>/dev/null || echo "")
    if [ -n "$VLLM_PIDS" ]; then
        echo "  发现 vLLM 进程: $VLLM_PIDS"
        docker exec $CONTAINER_NAME_01 bash -c "pkill -f 'vllm serve' || true" 2>/dev/null
        echo "✓ vLLM 进程已停止"
    else
        echo "  未发现 vLLM 进程"
    fi
else
    echo "  跳过（容器未运行）"
fi
echo ""

# 停止 Ray 集群
echo ">>> 停止 Ray 集群..."

if [ "$CONTAINER1_RUNNING" = true ]; then
    echo "  停止容器1的 Ray 进程..."
    docker exec $CONTAINER_NAME_01 bash -c "ray stop --force 2>/dev/null || true"
    echo "✓ 容器1的 Ray 进程已停止"
else
    echo "  跳过容器1（容器未运行）"
fi

if [ "$CONTAINER2_RUNNING" = true ]; then
    echo "  停止容器2的 Ray 进程..."
    docker exec $CONTAINER_NAME_23 bash -c "ray stop --force 2>/dev/null || true"
    echo "✓ 容器2的 Ray 进程已停止"
else
    echo "  跳过容器2（容器未运行）"
fi
echo ""

# 可选：清理 Ray 临时文件
echo ">>> 清理 Ray 临时文件 (可选)..."
if [ "$CONTAINER1_RUNNING" = true ]; then
    docker exec $CONTAINER_NAME_01 bash -c "rm -rf /tmp/ray/* 2>/dev/null || true"
    echo "✓ 容器1的临时文件已清理"
fi

if [ "$CONTAINER2_RUNNING" = true ]; then
    docker exec $CONTAINER_NAME_23 bash -c "rm -rf /tmp/ray/* 2>/dev/null || true"
    echo "✓ 容器2的临时文件已清理"
fi
echo ""

echo "=========================================="
echo "清理完成！"
echo "=========================================="
echo ""

# 验证清理结果
echo ">>> 验证清理结果..."
if [ "$CONTAINER1_RUNNING" = true ]; then
    RAY_PROCESSES_1=$(docker exec $CONTAINER_NAME_01 bash -c "ps aux | grep -E '[r]ay::' | wc -l" 2>/dev/null || echo "0")
    VLLM_PROCESSES_1=$(docker exec $CONTAINER_NAME_01 bash -c "ps aux | grep '[v]llm' | wc -l" 2>/dev/null || echo "0")
    echo "容器1:"
    echo "  Ray 进程数: $RAY_PROCESSES_1"
    echo "  vLLM 进程数: $VLLM_PROCESSES_1"
fi

if [ "$CONTAINER2_RUNNING" = true ]; then
    RAY_PROCESSES_2=$(docker exec $CONTAINER_NAME_23 bash -c "ps aux | grep -E '[r]ay::' | wc -l" 2>/dev/null || echo "0")
    echo "容器2:"
    echo "  Ray 进程数: $RAY_PROCESSES_2"
fi
echo ""

if [ "$CONTAINER1_RUNNING" = true ] && [ "$RAY_PROCESSES_1" -eq 0 ] && [ "$VLLM_PROCESSES_1" -eq 0 ]; then
    echo "✓ 所有进程已成功清理"
else
    echo "⚠ 可能还有残留进程，请手动检查"
fi
