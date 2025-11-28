#!/bin/bash
# 停止 etcd 元数据服务器

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/env_config.sh"

echo "=========================================="
echo "停止 etcd 元数据服务器"
echo "=========================================="
echo ""

if docker exec "$CONTAINER_01" pgrep -f "etcd" > /dev/null 2>&1; then
    echo ">>> 停止 $CONTAINER_01 中的 etcd..."
    docker exec "$CONTAINER_01" pkill -f "etcd"
    sleep 1

    # 确认已停止
    if ! docker exec "$CONTAINER_01" pgrep -f "etcd" > /dev/null 2>&1; then
        echo "✓ etcd 已停止"
    else
        echo "✗ etcd 停止失败，尝试强制终止..."
        docker exec "$CONTAINER_01" pkill -9 -f "etcd"
        sleep 1
        echo "✓ etcd 已强制停止"
    fi
else
    echo "etcd 未在运行"
fi

echo ""
echo "清理 etcd 数据目录（可选）"
echo "如需清理，运行: docker exec $CONTAINER_01 rm -rf /tmp/etcd-data /tmp/etcd.log"
