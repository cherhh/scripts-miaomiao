#!/bin/bash
# 从宿主机启动容器内的 Ray + vLLM 集群
# 用法: ./run_ray_vllm_from_host.sh -model facebook/opt-6.7b -port 2345 -tp 2 -pp 1

set -e

# 容器名称配置
CONTAINER_NAME_01=${CONTAINER_NAME_01:-yijun_testbed01}
CONTAINER_NAME_23=${CONTAINER_NAME_23:-yijun_testbed23}

# 脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 默认值
MODEL_NAME="facebook/opt-6.7b"
SERVE_PORT=2345
TENSOR_PARALLEL_SIZE=4
PIPELINE_PARALLEL_SIZE=1
MODEL_DIR="/usr/data"  # 容器内的模型目录
# 如果设置了 VLLM_CUSTOM_CMD，则使用自定义命令启动 vLLM
VLLM_CUSTOM_CMD="${VLLM_CUSTOM_CMD:-}"

# 帮助信息
show_help() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -model MODEL_NAME  Model name (default: facebook/opt-6.7b)"
    echo "  -port PORT        Service port (default: 2345)"
    echo "  -tp TP_SIZE      Tensor parallel size (default: 2)"
    echo "  -pp PP_SIZE      Pipeline parallel size (default: 1)"
    echo "  -h               Show this help message"
    exit 1
}

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        -model)
            MODEL_NAME="$2"
            shift 2
            ;;
        -port)
            SERVE_PORT="$2"
            shift 2
            ;;
        -tp)
            TENSOR_PARALLEL_SIZE="$2"
            shift 2
            ;;
        -pp)
            PIPELINE_PARALLEL_SIZE="$2"
            shift 2
            ;;
        -h)
            show_help
            ;;
        *)
            echo "Unknown argument: $1"
            show_help
            ;;
    esac
done

# 打印配置信息
echo "=========================================="
echo "Ray + vLLM 集群启动脚本（从宿主机运行）"
echo "=========================================="
echo "容器配置:"
echo "  容器1 (HEAD): $CONTAINER_NAME_01"
echo "  容器2 (WORKER): $CONTAINER_NAME_23"
echo ""
echo "vLLM 配置:"
echo "  模型名称: $MODEL_NAME"
echo "  模型目录: $MODEL_DIR"
echo "  服务端口: $SERVE_PORT"
echo "  Tensor parallel: $TENSOR_PARALLEL_SIZE"
echo "  Pipeline parallel: $PIPELINE_PARALLEL_SIZE"
if [ -n "$VLLM_CUSTOM_CMD" ]; then
    echo "  自定义 vLLM 启动命令已设置 (VLLM_CUSTOM_CMD)"
fi
echo "=========================================="
echo ""

# 检查容器是否运行
echo ">>> 检查容器状态..."
if ! docker inspect $CONTAINER_NAME_01 >/dev/null 2>&1; then
    echo "✗ 容器 $CONTAINER_NAME_01 不存在或未运行！"
    exit 1
fi

if ! docker inspect $CONTAINER_NAME_23 >/dev/null 2>&1; then
    echo "✗ 容器 $CONTAINER_NAME_23 不存在或未运行！"
    exit 1
fi
echo "✓ 容器运行正常"
echo ""

# 获取容器的 RDMA 网络 IP
echo ">>> 获取容器 IP 地址..."
IP1=$(docker exec $CONTAINER_NAME_01 hostname -I | grep -o '172\.17\.[0-9]\+\.[0-9]\+' | head -1)
IP2=$(docker exec $CONTAINER_NAME_23 hostname -I | grep -o '172\.17\.[0-9]\+\.[0-9]\+' | head -1)

if [ -z "$IP1" ]; then
    echo "✗ 无法获取容器 $CONTAINER_NAME_01 的 RDMA IP！"
    exit 1
fi

if [ -z "$IP2" ]; then
    echo "✗ 无法获取容器 $CONTAINER_NAME_23 的 RDMA IP！"
    exit 1
fi

echo "  容器1 IP: $IP1"
echo "  容器2 IP: $IP2"
echo ""

# 停止已存在的 Ray 进程
echo ">>> 清理已存在的 Ray 进程..."
docker exec $CONTAINER_NAME_01 bash -c "ray stop --force 2>/dev/null || true"
docker exec $CONTAINER_NAME_23 bash -c "ray stop --force 2>/dev/null || true"
sleep 2
echo "✓ Ray 进程清理完成"
echo ""

# 启动 Ray HEAD 节点（容器1）
echo ">>> 启动 Ray HEAD 节点 (容器 $CONTAINER_NAME_01)..."
# 创建并执行启动脚本
docker exec $CONTAINER_NAME_01 bash -c "
cat > /tmp/start_ray_head.sh << EOF
#!/bin/bash
# 禁用 torch.compile / dynamo / inductor，避免 Ray worker 上触发 Triton 编译崩溃
export TORCH_COMPILE_DISABLE=1
export TORCHDYNAMO_DISABLE=1
export TORCHINDUCTOR_DISABLE=1

export VLLM_HOST_IP=$IP1
export NCCL_SOCKET_IFNAME=eno0
export GLOO_SOCKET_IFNAME=eno0
export TP_SOCKET_IFNAME=eno0
export NCCL_IB_HCA=mlx5_49
export NCCL_IB_GID_INDEX=3
export NCCL_IB_DISABLE=0
export NCCL_NET_GDR_LEVEL=0
export NCCL_P2P_LEVEL=SYS
export NCCL_P2P_DISABLE=0
export NCCL_SHM_DISABLE=0
export RAY_DEDUP_LOGS=0

nohup ray start --head --port=6379 --redis-password='123456' --node-ip-address=$IP1 --num-gpus=2 > /tmp/ray_head.log 2>&1 &
EOF
chmod +x /tmp/start_ray_head.sh
/tmp/start_ray_head.sh
"

echo "  等待 Ray HEAD 节点启动..."
sleep 5

# 检查 Ray HEAD 节点状态
if docker exec $CONTAINER_NAME_01 bash -c "ray status --address=$IP1:6379 2>/dev/null" | grep -q "ray is running"; then
    echo "✓ Ray HEAD 节点启动成功"
else
    echo "  Ray HEAD 节点正在初始化..."
    sleep 5
fi
echo ""

# 启动 Ray WORKER 节点（容器2）
echo ">>> 启动 Ray WORKER 节点 (容器 $CONTAINER_NAME_23)..."
# 创建并执行启动脚本
docker exec $CONTAINER_NAME_23 bash -c "
cat > /tmp/start_ray_worker.sh << EOF
#!/bin/bash
# 禁用 torch.compile / dynamo / inductor, 避免 Ray worker 上触发 Triton 编译崩溃
export TORCH_COMPILE_DISABLE=1
export TORCHDYNAMO_DISABLE=1
export TORCHINDUCTOR_DISABLE=1

export VLLM_HOST_IP=$IP2
export NCCL_SOCKET_IFNAME=eno0
export GLOO_SOCKET_IFNAME=eno0
export TP_SOCKET_IFNAME=eno0
export NCCL_IB_HCA=mlx5_113
export NCCL_IB_GID_INDEX=3
export NCCL_IB_DISABLE=0
export NCCL_NET_GDR_LEVEL=0
export NCCL_P2P_LEVEL=SYS
export NCCL_P2P_DISABLE=0
export NCCL_SHM_DISABLE=0
export RAY_DEDUP_LOGS=0

nohup ray start --address=$IP1:6379 --redis-password='123456' --node-ip-address=$IP2 --num-gpus=2 > /tmp/ray_worker.log 2>&1 &
EOF
chmod +x /tmp/start_ray_worker.sh
/tmp/start_ray_worker.sh
"

echo "  等待 Ray WORKER 节点加入集群..."
sleep 5
echo "✓ Ray WORKER 节点启动成功"
echo ""

# 等待足够的 GPU 可用
EXPECTED_GPU_COUNT=$((TENSOR_PARALLEL_SIZE * PIPELINE_PARALLEL_SIZE))
echo ">>> 等待 $EXPECTED_GPU_COUNT 个 GPU 可用..."

MAX_WAIT=60
WAIT_COUNT=0
while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
    ACTUAL_GPU_COUNT=$(docker exec $CONTAINER_NAME_01 bash -c "ray status --address=$IP1:6379 2>/dev/null | grep 'GPU' | awk -F'/' '{print \$2}' | awk '{print int(\$1)}'" 2>/dev/null || echo "0")

    if [ "$ACTUAL_GPU_COUNT" -ge "$EXPECTED_GPU_COUNT" ]; then
        echo "✓ GPU 检查通过。发现 $ACTUAL_GPU_COUNT 个 GPU"
        break
    fi

    echo "  当前 GPU 数量: $ACTUAL_GPU_COUNT，等待更多 GPU..."
    sleep 2
    WAIT_COUNT=$((WAIT_COUNT + 1))
done

if [ $WAIT_COUNT -ge $MAX_WAIT ]; then
    echo "✗ 超时等待 GPU。当前可用: $ACTUAL_GPU_COUNT，需要: $EXPECTED_GPU_COUNT"
    echo ""
    echo "Ray 集群状态:"
    docker exec $CONTAINER_NAME_01 bash -c "ray status --address=$IP1:6379"
    exit 1
fi
echo ""

# 显示 Ray 集群状态
echo ">>> Ray 集群状态:"
docker exec $CONTAINER_NAME_01 bash -c "ray status --address=$IP1:6379"
echo ""

# 启动 vLLM 服务（在 HEAD 节点上）
echo "=========================================="
echo ">>> 启动 vLLM 服务..."
echo "=========================================="
if [ -n "$VLLM_CUSTOM_CMD" ]; then
    echo "命令: $VLLM_CUSTOM_CMD"
else
    echo "命令: vllm serve $MODEL_NAME"
    echo "  --trust-remote-code"
    echo "  --port $SERVE_PORT"
    echo "  --tensor-parallel-size $TENSOR_PARALLEL_SIZE"
    echo "  --pipeline-parallel-size $PIPELINE_PARALLEL_SIZE"
fi
echo ""
echo "NCCL 配置:"
echo "  NCCL_P2P_DISABLE=0  (允许机内 PCIe/NVLink 通信)"
echo "  NCCL_IB_DISABLE=0   (允许机间 InfiniBand 通信)"
echo "  NCCL_SHM_DISABLE=0  (允许共享内存)"
echo "  → NCCL 将自动选择最优通信路径"
echo ""
echo "注意: vLLM 服务将在容器 $CONTAINER_NAME_01 中运行"
echo "      模型将从 $MODEL_DIR 目录加载（确保已挂载 /mnt/nfs/yijun:/usr/data）"
echo "      服务地址: http://${IP1}:${SERVE_PORT}"
echo ""
echo "按 Ctrl+C 停止服务"
echo "=========================================="
echo ""

# 在前台运行 vLLM 服务
docker exec -it $CONTAINER_NAME_01 bash -c "
    export VLLM_HOST_IP=$IP1
    export NCCL_SOCKET_IFNAME=eno0
    export GLOO_SOCKET_IFNAME=eno0
    export TP_SOCKET_IFNAME=eno0
    export RAY_DEDUP_LOGS=0
    export NCCL_IB_HCA=mlx5_49
    export NCCL_P2P_DISABLE=0
    export NCCL_SHM_DISABLE=0
    export NCCL_IB_GID_INDEX=3
    export NCCL_IB_DISABLE=0
    export NCCL_NET_GDR_LEVEL=0
    export NCCL_P2P_LEVEL=SYS
    export RAY_ADDRESS=$IP1:6379

    # 加载用户环境
    if [ -f /etc/profile ]; then
        source /etc/profile
    fi
    if [ -f ~/.bashrc ]; then
        source ~/.bashrc
    fi

    # 启动 vLLM 服务
    if [ -n \"$VLLM_CUSTOM_CMD\" ]; then
        echo \"使用自定义 vLLM 启动命令: $VLLM_CUSTOM_CMD\"
        eval \"$VLLM_CUSTOM_CMD\"
    else
        vllm serve $MODEL_NAME \
            --trust-remote-code \
            --port $SERVE_PORT \
            --tensor-parallel-size $TENSOR_PARALLEL_SIZE \
            --pipeline-parallel-size $PIPELINE_PARALLEL_SIZE
    fi
"

echo ""
echo "=========================================="
echo "vLLM 服务已停止"
echo "=========================================="
