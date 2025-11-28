#!/bin/bash
# 启动 HTTP Metadata Server（在宿主机运行）

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=========================================="
echo "启动 HTTP Metadata Server"
echo "=========================================="
echo ""

# 默认端口
PORT="${PORT:-8080}"
HOST="${HOST:-0.0.0.0}"

# 检查端口是否已被占用
if lsof -Pi :${PORT} -sTCP:LISTEN -t >/dev/null 2>&1; then
    echo "端口 $PORT 已被占用，检查进程："
    lsof -Pi :${PORT} -sTCP:LISTEN
    echo ""
    echo "如果是旧的metadata server，请先停止："
    echo "  ./stop_metadata_server.sh"
    exit 1
fi

# 日志文件
LOG_DIR="${SCRIPT_DIR}/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/metadata_server.log"

echo "配置:"
echo "  监听地址: ${HOST}:${PORT}"
echo "  日志文件: ${LOG_FILE}"
echo "  访问URL: http://10.0.11.1:${PORT}/metadata"
echo ""

# 启动metadata server（后台运行）
echo ">>> 启动 Metadata Server..."
nohup python3 -m mooncake.http_metadata_server \
    --host "$HOST" \
    --port "$PORT" \
    --log-level INFO \
    > "$LOG_FILE" 2>&1 &

SERVER_PID=$!
echo $SERVER_PID > "${SCRIPT_DIR}/.metadata_server.pid"

# 等待服务启动
echo "等待服务启动..."
sleep 2

# 检查进程是否还在运行
if ps -p $SERVER_PID > /dev/null 2>&1; then
    echo "✓ Metadata Server 启动成功 (PID: $SERVER_PID)"
    echo ""

    # 测试访问
    echo ">>> 测试服务..."
    if curl -s -o /dev/null -w "%{http_code}" "http://localhost:${PORT}/metadata" | grep -q "404\|200"; then
        echo "✓ 服务响应正常"
        echo ""
        echo "Metadata Server URL: http://10.0.11.1:${PORT}/metadata"
        echo ""
        echo "停止服务: ./stop_metadata_server.sh"
        echo "查看日志: tail -f ${LOG_FILE}"
    else
        echo "✗ 服务未响应"
        echo "查看日志: cat ${LOG_FILE}"
        exit 1
    fi
else
    echo "✗ Metadata Server 启动失败"
    echo "查看日志: cat ${LOG_FILE}"
    exit 1
fi
