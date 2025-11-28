#!/bin/bash
# 最简单的方案：直接在每个容器内运行 NCCL 测试
# 使用 MPI 但所有进程都在主机上启动，通过 docker exec 进入容器

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/env_config.sh"

# Default to locally built NCCL unless caller overrides NCCL_LIB_DIR.
NCCL_LIB_DIR=${NCCL_LIB_DIR:-/usr/wkspace/docker/testbed/nccl/build/lib}
export NCCL_LIB_DIR
if [[ -n "${LD_LIBRARY_PATH:-}" ]]; then
  export LD_LIBRARY_PATH="${NCCL_LIB_DIR}:${LD_LIBRARY_PATH}"
else
  export LD_LIBRARY_PATH="${NCCL_LIB_DIR}:/usr/local/cuda/lib64"
fi

echo "=========================================="
echo "NCCL Send/Recv 测试（直接模式）"
echo "=========================================="
echo "容器: yijun_testbed01 (2 GPU) + yijun_testbed23 (2 GPU)"
echo "总进程: 4"
echo "测试范围: ${TEST_MIN_BYTES} - ${TEST_MAX_BYTES}"
echo "=========================================="
echo ""

# 检查容器
for container in yijun_testbed01 yijun_testbed23; do
    if ! docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
        echo "错误: 容器 ${container} 未运行"
        exit 1
    fi
done

# 创建临时 hostfile（本地启动所有进程）
cat > /tmp/nccl_local_hostfile << EOF
localhost slots=4
EOF

echo "开始运行测试..."
echo ""

# 容器内的路径
CONTAINER_SCRIPT_DIR="/usr/wkspace/docker/testbed/script/run_nccl_test"
CONTAINER_NCCL_TESTS="/usr/wkspace/docker/testbed/nccl-tests"

# 创建 GPU 绑定和容器分配脚本
cat > /tmp/nccl_container_launcher.sh << 'LAUNCHER_EOF'
#!/bin/bash
# 根据 MPI rank 决定进入哪个容器并绑定 GPU

RANK=${OMPI_COMM_WORLD_RANK:-0}
LOCAL_RANK=${OMPI_COMM_WORLD_LOCAL_RANK:-0}

# Rank 0-1 进入 testbed01，Rank 2-3 进入 testbed23
if [ $RANK -lt 2 ]; then
    CONTAINER="yijun_testbed01"
    GPU_ID=$RANK
    export NCCL_IB_HCA=mlx5_49
else
    CONTAINER="yijun_testbed23"
    GPU_ID=$((RANK - 2))
    export NCCL_IB_HCA=mlx5_113
fi

export CUDA_VISIBLE_DEVICES=$GPU_ID

# 构建环境变量传递 - 包含所有 MPI/PMI 相关变量
ENV_VARS=""
for var in OMPI_COMM_WORLD_RANK OMPI_COMM_WORLD_SIZE OMPI_COMM_WORLD_LOCAL_RANK \
           OMPI_COMM_WORLD_LOCAL_SIZE OMPI_COMM_WORLD_NODE_RANK \
           PMIX_RANK PMIX_NAMESPACE PMIX_SERVER_URI PMIX_SERVER_URI2 \
           PMIX_SERVER_URI3 PMIX_SERVER_URI4 PMIX_GDS_MODULE \
           PMI_RANK PMI_SIZE PMI_FD PMIX_SECURITY_MODE \
           CUDA_VISIBLE_DEVICES \
           NCCL_DEBUG NCCL_DEBUG_SUBSYS NCCL_IB_HCA NCCL_IB_GID_INDEX \
           NCCL_IB_DISABLE NCCL_NET_GDR_LEVEL NCCL_P2P_LEVEL NCCL_ALGO \
           NCCL_SOCKET_IFNAME NCCL_BUFFSIZE NCCL_NTHREADS NCCL_IB_TIMEOUT \
           NCCL_MIN_NCHANNELS NCCL_MAX_NCHANNELS; do
    if [ -n "${!var}" ]; then
        ENV_VARS="$ENV_VARS -e $var=${!var}"
    fi
done

# 获取容器的 PID
CONTAINER_PID=$(docker inspect --format '{{.State.Pid}}' $CONTAINER)

# 使用 nsenter 进入容器的 mount 命名空间，但保留主机的 network/ipc/pid 命名空间
# 这样容器内的进程可以访问主机的 PMIx 服务器
exec sudo nsenter -t $CONTAINER_PID -m -u bash -c "
    $(for var in OMPI_COMM_WORLD_RANK OMPI_COMM_WORLD_SIZE OMPI_COMM_WORLD_LOCAL_RANK \
                 OMPI_COMM_WORLD_LOCAL_SIZE OMPI_COMM_WORLD_NODE_RANK \
                 PMIX_RANK PMIX_NAMESPACE PMIX_SERVER_URI PMIX_SERVER_URI2 \
                 PMIX_SERVER_URI3 PMIX_SERVER_URI4 PMIX_SERVER_URI21 \
                 PMIX_GDS_MODULE PMIX_SECURITY_MODE PMIX_SYSTEM_TMPDIR \
                 PMIX_DSTORE_21_BASE_PATH PMIX_DSTORE_ESH_BASE_PATH \
                 PMIX_SERVER_TMPDIR PMIX_ID \
                 PMI_RANK PMI_SIZE PMI_FD \
                 CUDA_VISIBLE_DEVICES \
                 NCCL_DEBUG NCCL_DEBUG_SUBSYS NCCL_IB_HCA NCCL_IB_GID_INDEX \
                 NCCL_IB_DISABLE NCCL_NET_GDR_LEVEL NCCL_P2P_LEVEL NCCL_ALGO \
                 NCCL_SOCKET_IFNAME NCCL_BUFFSIZE NCCL_NTHREADS NCCL_IB_TIMEOUT \
                 NCCL_MIN_NCHANNELS NCCL_MAX_NCHANNELS; do
        if [ -n \"${!var}\" ]; then
            echo \"export $var='${!var}'\";
        fi
    done)
    cd /usr/wkspace
    exec \"\$@\"
" -- "\$@"
LAUNCHER_EOF

chmod +x /tmp/nccl_container_launcher.sh

# 使用本地启动所有 MPI 进程，通过 launcher 脚本分配到容器
mpirun --allow-run-as-root \
    -np 4 \
    --hostfile /tmp/nccl_local_hostfile \
    --map-by slot \
    --mca btl ^openib \
    --mca btl_tcp_if_include eno0 \
    -x NCCL_DEBUG \
    -x NCCL_DEBUG_SUBSYS \
    -x NCCL_IB_GID_INDEX \
    -x NCCL_IB_DISABLE \
    -x NCCL_NET_GDR_LEVEL \
    -x NCCL_P2P_LEVEL \
    -x NCCL_ALGO \
    -x NCCL_SOCKET_IFNAME \
    -x NCCL_BUFFSIZE \
    -x NCCL_NTHREADS \
    -x NCCL_IB_TIMEOUT \
    -x NCCL_MIN_NCHANNELS \
    -x NCCL_MAX_NCHANNELS \
    /tmp/nccl_container_launcher.sh \
    ${CONTAINER_NCCL_TESTS}/build/sendrecv_perf \
    -b ${TEST_MIN_BYTES} \
    -e ${TEST_MAX_BYTES} \
    -f ${TEST_FACTOR} \
    -g 1

echo ""
echo "=========================================="
echo "测试完成!"
echo "=========================================="
