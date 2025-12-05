#!/bin/bash
# 从宿主机启动容器内的 Ray + vLLM 集群 (LMCache 版本)
# 用法: ./run_ray_vllm_from_host_lmcache.sh -model Llama-3.1-8B-Instruct -port 2345 -tp 2 -cp 2

set -e

# ============================================================
# 关键：确保跨进程 hash 一致性
# 必须在所有进程中设置相同的值
# ============================================================
export PYTHONHASHSEED=0

# 容器名称配置
CONTAINER_NAME_01=${CONTAINER_NAME_01:-node2-nic0}
CONTAINER_NAME_23=${CONTAINER_NAME_23:-node2-nic2}

# 脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 默认值 - LMCache 配置
MODEL_NAME="Llama-3.1-8B-Instruct"
SERVE_PORT=2345
TENSOR_PARALLEL_SIZE=2
PIPELINE_PARALLEL_SIZE=1
CONTEXT_PARALLEL_SIZE=2  # 新增 context parallel
MODEL_DIR="/usr/data"  # 容器内的模型目录

# LMCache 配置文件路径 - 每个容器使用不同的配置（因为 RDMA 网卡不同）
LMCACHE_CONFIG_FILE_NIC0="${LMCACHE_CONFIG_FILE_NIC0:-/usr/wkspace/ch-testbed/config-lmcache-nic0.yaml}"
LMCACHE_CONFIG_FILE_NIC2="${LMCACHE_CONFIG_FILE_NIC2:-/usr/wkspace/ch-testbed/config-lmcache-nic2.yaml}"

# 如果设置了 VLLM_CUSTOM_CMD，则使用自定义命令启动 vLLM
VLLM_CUSTOM_CMD="${VLLM_CUSTOM_CMD:-}"

# 帮助信息
show_help() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -model MODEL_NAME  Model name (default: Llama-3.1-8B-Instruct)"
    echo "  -port PORT        Service port (default: 2345)"
    echo "  -tp TP_SIZE      Tensor parallel size (default: 2)"
    echo "  -pp PP_SIZE      Pipeline parallel size (default: 1)"
    echo "  -cp CP_SIZE      Context parallel size (default: 2)"
    echo "  -h               Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  LMCACHE_CONFIG_FILE_NIC0  LMCache config for node2-nic0 (mlx5_49)"
    echo "  LMCACHE_CONFIG_FILE_NIC2  LMCache config for node2-nic2 (mlx5_113)"
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
        -cp)
            CONTEXT_PARALLEL_SIZE="$2"
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
echo "Ray + vLLM + LMCache 集群启动脚本（从宿主机运行）"
echo "=========================================="
echo "容器配置:"
echo "  容器1 (HEAD): $CONTAINER_NAME_01 (mlx5_49)"
echo "  容器2 (WORKER): $CONTAINER_NAME_23 (mlx5_113)"
echo ""
echo "vLLM 配置:"
echo "  模型名称: $MODEL_NAME"
echo "  模型目录: $MODEL_DIR"
echo "  服务端口: $SERVE_PORT"
echo "  Tensor parallel: $TENSOR_PARALLEL_SIZE"
echo "  Pipeline parallel: $PIPELINE_PARALLEL_SIZE"
echo "  Context parallel: $CONTEXT_PARALLEL_SIZE"
if [ $CONTEXT_PARALLEL_SIZE -gt 1 ]; then
    echo "  Attention backend: RING_FLASH_ATTN (CP > 1 自动启用)"
fi
echo ""
echo "LMCache 配置:"
echo "  NIC0 配置: $LMCACHE_CONFIG_FILE_NIC0"
echo "  NIC2 配置: $LMCACHE_CONFIG_FILE_NIC2"
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
# 使用 -w / 避免因 WORKDIR 不存在而失败
IP1=$(docker exec -w / $CONTAINER_NAME_01 hostname -I | grep -o '172\.17\.[0-9]\+\.[0-9]\+' | head -1)
IP2=$(docker exec -w / $CONTAINER_NAME_23 hostname -I | grep -o '172\.17\.[0-9]\+\.[0-9]\+' | head -1)

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
docker exec -w / $CONTAINER_NAME_01 bash -c "ray stop --force 2>/dev/null || true"
docker exec -w / $CONTAINER_NAME_23 bash -c "ray stop --force 2>/dev/null || true"
sleep 2
echo "✓ Ray 进程清理完成"
echo ""

# # 移动 /opt/vllm 目录以避免与可编辑安装冲突
# echo ">>> 检查并处理 /opt/vllm 目录..."
# docker exec -w / $CONTAINER_NAME_01 bash -c "
#     if [ -d /opt/vllm ] && [ ! -L /opt/vllm ]; then
#         echo '  容器1: 移动 /opt/vllm 到 /opt/vllm.bak.$(date +%s)'
#         mv /opt/vllm /opt/vllm.bak.\$(date +%s)
#     else
#         echo '  容器1: /opt/vllm 不存在或已是符号链接'
#     fi
# "
# docker exec -w / $CONTAINER_NAME_23 bash -c "
#     if [ -d /opt/vllm ] && [ ! -L /opt/vllm ]; then
#         echo '  容器2: 移动 /opt/vllm 到 /opt/vllm.bak.$(date +%s)'
#         mv /opt/vllm /opt/vllm.bak.\$(date +%s)
#     else
#         echo '  容器2: /opt/vllm 不存在或已是符号链接'
#     fi
# "
# echo "✓ /opt/vllm 目录处理完成"
# echo ""

# 清理 Ray 缓存和旧的 Python 模块缓存
echo ">>> 清理 Ray 缓存..."
docker exec -w / $CONTAINER_NAME_01 bash -c "rm -rf /tmp/ray/* 2>/dev/null || true"
docker exec -w / $CONTAINER_NAME_23 bash -c "rm -rf /tmp/ray/* 2>/dev/null || true"
echo "✓ Ray 缓存清理完成"
echo ""

# 启动 Ray HEAD 节点（容器1 - node2-nic0）- 使用 NIC0 的 LMCache 配置
echo ">>> 启动 Ray HEAD 节点 (容器 $CONTAINER_NAME_01, RDMA: mlx5_49)..."
# 创建并执行启动脚本
docker exec -w / $CONTAINER_NAME_01 bash -c "
cat > /tmp/start_ray_head.sh << EOF
#!/bin/bash
# 禁用 torch.compile / dynamo / inductor，避免 Ray worker 上触发 Triton 编译崩溃
export TORCH_COMPILE_DISABLE=1
export TORCHDYNAMO_DISABLE=1
export TORCHINDUCTOR_DISABLE=1

# LMCache 和 vLLM 相关环境变量
# export NCCL_DEBUG=INFO
export NCCL_DEBUG=WARN
export VLLM_LOG_LEVEL=WARNING
export VLLM_COMPILE=None
export VLLM_CUDAGRAPH_DISABLED=1
export TORCH_DISTRIBUTED_DEBUG=DETAIL
export VLLM_DISABLE_COMPILE_CACHE=1
export PYTHONHASHSEED=0
export VLLM_ENABLE_V1_MULTIPROCESSING=1
export VLLM_WORKER_MULTIPROC_METHOD=spawn
export LMCACHE_CONFIG_FILE=\"$LMCACHE_CONFIG_FILE_NIC0\"
export LMCACHE_USE_EXPERIMENTAL=True

# Context Parallelism 需要 Ring FlashAttention
if [ $CONTEXT_PARALLEL_SIZE -gt 1 ]; then
    export VLLM_ATTENTION_BACKEND=RING_FLASH_ATTN
fi

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
if docker exec -w / $CONTAINER_NAME_01 bash -c "ray status --address=$IP1:6379 2>/dev/null" | grep -q "ray is running"; then
    echo "✓ Ray HEAD 节点启动成功"
else
    echo "  Ray HEAD 节点正在初始化..."
    sleep 5
fi
echo ""

# 启动 Ray WORKER 节点（容器2 - node2-nic2）- 使用 NIC2 的 LMCache 配置
echo ">>> 启动 Ray WORKER 节点 (容器 $CONTAINER_NAME_23, RDMA: mlx5_113)..."
# 创建并执行启动脚本
docker exec -w / $CONTAINER_NAME_23 bash -c "
cat > /tmp/start_ray_worker.sh << EOF
#!/bin/bash
# 禁用 torch.compile / dynamo / inductor，避免 Ray worker 上触发 Triton 编译崩溃
export TORCH_COMPILE_DISABLE=1
export TORCHDYNAMO_DISABLE=1
export TORCHINDUCTOR_DISABLE=1

# LMCache 和 vLLM 相关环境变量
# export NCCL_DEBUG=INFO
export NCCL_DEBUG=WARN
export VLLM_LOG_LEVEL=WARNING
export VLLM_COMPILE=None
export VLLM_CUDAGRAPH_DISABLED=1
export TORCH_DISTRIBUTED_DEBUG=DETAIL
export VLLM_DISABLE_COMPILE_CACHE=1
export PYTHONHASHSEED=0
export VLLM_ENABLE_V1_MULTIPROCESSING=1
export VLLM_WORKER_MULTIPROC_METHOD=spawn
export LMCACHE_CONFIG_FILE=\"$LMCACHE_CONFIG_FILE_NIC2\"
export LMCACHE_USE_EXPERIMENTAL=True

# Context Parallelism 需要 Ring FlashAttention
if [ $CONTEXT_PARALLEL_SIZE -gt 1 ]; then
    export VLLM_ATTENTION_BACKEND=RING_FLASH_ATTN
fi

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
EXPECTED_GPU_COUNT=$((TENSOR_PARALLEL_SIZE * PIPELINE_PARALLEL_SIZE * CONTEXT_PARALLEL_SIZE))
echo ">>> 等待 $EXPECTED_GPU_COUNT 个 GPU 可用..."

MAX_WAIT=60
WAIT_COUNT=0
while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
    ACTUAL_GPU_COUNT=$(docker exec -w / $CONTAINER_NAME_01 bash -c "ray status --address=$IP1:6379 2>/dev/null | grep 'GPU' | awk -F'/' '{print \$2}' | awk '{print int(\$1)}'" 2>/dev/null || echo "0")

    # 确保 ACTUAL_GPU_COUNT 不为空，默认为 0
    ACTUAL_GPU_COUNT=${ACTUAL_GPU_COUNT:-0}

    if [ "$ACTUAL_GPU_COUNT" -ge "$EXPECTED_GPU_COUNT" ] 2>/dev/null; then
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
    docker exec -w / $CONTAINER_NAME_01 bash -c "ray status --address=$IP1:6379"
    exit 1
fi
echo ""

# 显示 Ray 集群状态
echo ">>> Ray 集群状态:"
docker exec -w / $CONTAINER_NAME_01 bash -c "ray status --address=$IP1:6379"
echo ""

# 启动 vLLM 服务（在 HEAD 节点上）- 使用 LMCache 配置
echo "=========================================="
echo ">>> 启动 vLLM 服务 (LMCache 模式)..."
echo "=========================================="
if [ -n "$VLLM_CUSTOM_CMD" ]; then
    echo "命令: $VLLM_CUSTOM_CMD"
else
    echo "命令: vllm serve $MODEL_DIR/$MODEL_NAME"
    echo "  --max-model-len 3200"
    echo "  --enforce-eager"
    echo "  --tensor-parallel-size $TENSOR_PARALLEL_SIZE"
    echo "  --pipeline-parallel-size $PIPELINE_PARALLEL_SIZE"
    echo "  --context-parallel-size $CONTEXT_PARALLEL_SIZE"
    echo "  --distributed-executor-backend ray"
    echo "  --no-enable-prefix-caching"
    echo "  --max-num-batched-tokens 1024"
    echo "  --kv-transfer-config ..."
fi
echo ""
echo "LMCache 配置:"
echo "  HEAD (mlx5_49):   $LMCACHE_CONFIG_FILE_NIC0"
echo "  WORKER (mlx5_113): $LMCACHE_CONFIG_FILE_NIC2"
echo "  LMCACHE_USE_EXPERIMENTAL=True"
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

# 在前台运行 vLLM 服务 - 添加所有 LMCache 和 vLLM 环境变量
# 注意：HEAD 节点使用 NIC0 的配置
# PYTHONHASHSEED=0 确保 Scheduler 和所有 Workers 使用一致的 hash
docker exec -w / -e PYTHONHASHSEED=0 -e VLLM_CUSTOM_CMD="$VLLM_CUSTOM_CMD" -it $CONTAINER_NAME_01 bash -c "
    # NCCL 和网络配置
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
    
    # LMCache 和 vLLM 调试环境变量
    # export NCCL_DEBUG=INFO
    export NCCL_DEBUG=WARN
    export VLLM_LOG_LEVEL=WARNING
    export VLLM_COMPILE=None
    export VLLM_CUDAGRAPH_DISABLED=1
    export TORCH_DISTRIBUTED_DEBUG=DETAIL
    export VLLM_DISABLE_COMPILE_CACHE=1
    export PYTHONHASHSEED=0
    export TORCHDYNAMO_DISABLE=1
    export VLLM_ENABLE_V1_MULTIPROCESSING=1
    export VLLM_WORKER_MULTIPROC_METHOD=spawn
    export LMCACHE_CONFIG_FILE=\"$LMCACHE_CONFIG_FILE_NIC0\"
    export LMCACHE_USE_EXPERIMENTAL=True

    # GLOG 日志配置
    export GLOG_logtostderr=1
    export GLOG_v=1

    # Context Parallelism 需要 Ring FlashAttention
    if [ $CONTEXT_PARALLEL_SIZE -gt 1 ]; then
        export VLLM_ATTENTION_BACKEND=RING_FLASH_ATTN
        echo '>>> Context Parallelism 已启用，使用 RING_FLASH_ATTN 后端'
    fi

    # 加载用户环境
    if [ -f /etc/profile ]; then
        source /etc/profile
    fi
    if [ -f ~/.bashrc ]; then
        source ~/.bashrc
    fi

    # 启动 vLLM 服务
    if [ -n \"\$VLLM_CUSTOM_CMD\" ]; then
        echo \"使用自定义 vLLM 启动命令: \$VLLM_CUSTOM_CMD\"
        eval \"\$VLLM_CUSTOM_CMD\"
    else
        vllm serve $MODEL_DIR/$MODEL_NAME \\
            --max-model-len 32000 \\
            --enforce-eager \\
            --tensor-parallel-size $TENSOR_PARALLEL_SIZE \\
            --pipeline-parallel-size $PIPELINE_PARALLEL_SIZE \\
            --context-parallel-size $CONTEXT_PARALLEL_SIZE \\
            --distributed-executor-backend ray \\
            --no-enable-prefix-caching \\
            --max-num-batched-tokens 4096 \\
            --gpu-memory-utilization 0.90 \\
            --block-size 128 \\
            --port $SERVE_PORT \\
            --kv-transfer-config '{\"kv_connector\":\"LMCacheConnectorV1\",\"kv_role\":\"kv_producer\",\"kv_connector_extra_config\":{\"use_native\":true}}'
    fi
"

echo ""
echo "=========================================="
echo "vLLM 服务已停止"
echo "=========================================="
