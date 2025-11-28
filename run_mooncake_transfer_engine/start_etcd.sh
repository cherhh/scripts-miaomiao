#!/bin/bash
# 在容器中启动 etcd 元数据服务器

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/env_config.sh"

echo "=========================================="
echo "启动 etcd 元数据服务器"
echo "=========================================="
echo ""

# 检查 etcd 是否已在运行
if docker exec "$CONTAINER_01" pgrep -f "etcd" > /dev/null 2>&1; then
    echo "etcd 已在 $CONTAINER_01 中运行"
    docker exec "$CONTAINER_01" bash -c "ps aux | grep etcd | grep -v grep"
    echo ""
    echo "如需重启，请先停止: docker exec $CONTAINER_01 pkill etcd"
    exit 0
fi

echo ">>> 在 $CONTAINER_01 启动 etcd..."
echo "监听地址: http://0.0.0.0:2379"
echo "广播地址: http://${IP_01}:2379"
echo ""

# 启动 etcd
docker exec -d "$CONTAINER_01" bash -c "etcd \
    --listen-client-urls http://0.0.0.0:2379 \
    --advertise-client-urls http://${IP_01}:2379 \
    --listen-peer-urls http://0.0.0.0:2380 \
    --data-dir /tmp/etcd-data \
    > /tmp/etcd.log 2>&1"

# 等待 etcd 启动
echo "等待 etcd 启动..."
sleep 2

# 检查 etcd 是否正常运行
MAX_RETRIES=10
RETRY=0
while [ $RETRY -lt $MAX_RETRIES ]; do
    if docker exec "$CONTAINER_01" curl -s http://localhost:2379/health | grep -q "true"; then
        echo "✓ etcd 启动成功"
        echo ""
        echo "健康检查:"
        docker exec "$CONTAINER_01" curl -s http://localhost:2379/health
        echo ""
        echo ""
        echo "etcd 版本:"
        docker exec "$CONTAINER_01" curl -s http://localhost:2379/version
        echo ""
        exit 0
    fi
    RETRY=$((RETRY+1))
    echo "等待中... ($RETRY/$MAX_RETRIES)"
    sleep 1
done

echo "✗ etcd 启动失败或超时"
echo ""
echo "查看 etcd 日志:"
echo "  docker exec $CONTAINER_01 cat /tmp/etcd.log"
exit 1
