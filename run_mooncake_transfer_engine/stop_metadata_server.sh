#!/bin/bash
# 停止 HTTP Metadata Server

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PID_FILE="${SCRIPT_DIR}/.metadata_server.pid"

echo "=========================================="
echo "停止 HTTP Metadata Server"
echo "=========================================="
echo ""

if [ ! -f "$PID_FILE" ]; then
    echo "未找到PID文件，尝试查找进程..."
    PIDS=$(pgrep -f "mooncake.http_metadata_server" || true)
    if [ -z "$PIDS" ]; then
        echo "未找到运行中的 Metadata Server"
        exit 0
    fi
    echo "找到进程: $PIDS"
    for PID in $PIDS; do
        echo "停止进程 $PID..."
        kill $PID 2>/dev/null || true
    done
else
    PID=$(cat "$PID_FILE")
    echo ">>> 停止 Metadata Server (PID: $PID)..."

    if ps -p $PID > /dev/null 2>&1; then
        kill $PID
        sleep 1

        # 确认已停止
        if ps -p $PID > /dev/null 2>&1; then
            echo "进程未停止，强制终止..."
            kill -9 $PID 2>/dev/null || true
        fi
        echo "✓ Metadata Server 已停止"
    else
        echo "进程已不存在"
    fi

    rm -f "$PID_FILE"
fi

echo ""
echo "清理完成"
