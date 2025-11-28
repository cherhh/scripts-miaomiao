#!/bin/bash
# 验证 PYTHONHASHSEED 是否在所有进程中正确设置

CONTAINER_NAME_01=${CONTAINER_NAME_01:-node2-nic0}
CONTAINER_NAME_23=${CONTAINER_NAME_23:-node2-nic2}

echo "========================================"
echo "验证 PYTHONHASHSEED=0 设置"
echo "========================================"
echo ""

# 1. 检查容器是否运行
echo ">>> 1. 检查容器状态..."
if ! docker inspect $CONTAINER_NAME_01 >/dev/null 2>&1; then
    echo "✗ 容器 $CONTAINER_NAME_01 未运行"
    exit 1
fi
if ! docker inspect $CONTAINER_NAME_23 >/dev/null 2>&1; then
    echo "✗ 容器 $CONTAINER_NAME_23 未运行"
    exit 1
fi
echo "✓ 容器运行正常"
echo ""

# 2. 检查 Ray daemon 进程
echo ">>> 2. 检查 Ray daemon 的 PYTHONHASHSEED..."
echo "容器1 (HEAD):"
docker exec $CONTAINER_NAME_01 bash -c "
RAY_PID=\$(pgrep -f 'ray::IDLE' | head -1)
if [ -n \"\$RAY_PID\" ]; then
    grep -a PYTHONHASHSEED /proc/\$RAY_PID/environ | tr '\0' '\n' || echo '未找到 PYTHONHASHSEED'
else
    echo '未找到 Ray 进程'
fi
" 2>/dev/null

echo ""
echo "容器2 (WORKER):"
docker exec $CONTAINER_NAME_23 bash -c "
RAY_PID=\$(pgrep -f 'ray::IDLE' | head -1)
if [ -n \"\$RAY_PID\" ]; then
    grep -a PYTHONHASHSEED /proc/\$RAY_PID/environ | tr '\0' '\n' || echo '未找到 PYTHONHASHSEED'
else
    echo '未找到 Ray 进程'
fi
" 2>/dev/null
echo ""

# 3. 测试 Python hash 一致性
echo ">>> 3. 测试 Python hash 一致性..."
TEST_STRING="lmcache_test_hash_consistency_12345"

echo "容器1 hash 值:"
HASH1=$(docker exec $CONTAINER_NAME_01 python3 -c "
import os
print(f'PYTHONHASHSEED={os.environ.get(\"PYTHONHASHSEED\", \"NOT_SET\")}')
print(f'hash={hash(\"$TEST_STRING\")}')
" 2>/dev/null)
echo "$HASH1"

echo ""
echo "容器2 hash 值:"
HASH2=$(docker exec $CONTAINER_NAME_23 python3 -c "
import os
print(f'PYTHONHASHSEED={os.environ.get(\"PYTHONHASHSEED\", \"NOT_SET\")}')
print(f'hash={hash(\"$TEST_STRING\")}')
" 2>/dev/null)
echo "$HASH2"

echo ""
# 提取 hash 值进行比较
HASH_VAL1=$(echo "$HASH1" | grep 'hash=' | cut -d'=' -f2)
HASH_VAL2=$(echo "$HASH2" | grep 'hash=' | cut -d'=' -f2)

if [ "$HASH_VAL1" == "$HASH_VAL2" ] && [ -n "$HASH_VAL1" ]; then
    echo "✓ Hash 值一致！PYTHONHASHSEED 设置成功"
    echo "  两个容器的 hash('$TEST_STRING') = $HASH_VAL1"
else
    echo "✗ Hash 值不一致！PYTHONHASHSEED 设置可能有问题"
    echo "  容器1: $HASH_VAL1"
    echo "  容器2: $HASH_VAL2"
fi
echo ""

# 4. 检查 vLLM 进程（如果正在运行）
echo ">>> 4. 检查 vLLM 进程的 PYTHONHASHSEED..."
VLLM_PID=$(docker exec $CONTAINER_NAME_01 pgrep -f 'vllm serve' | head -1 2>/dev/null)
if [ -n "$VLLM_PID" ]; then
    echo "vLLM 进程 PID: $VLLM_PID"
    docker exec $CONTAINER_NAME_01 bash -c "
        grep -a PYTHONHASHSEED /proc/$VLLM_PID/environ | tr '\0' '\n'
    " 2>/dev/null || echo "未找到 PYTHONHASHSEED"
else
    echo "vLLM 未运行（正常，可能还未启动）"
fi
echo ""

echo "========================================"
echo "验证完成"
echo "========================================"
