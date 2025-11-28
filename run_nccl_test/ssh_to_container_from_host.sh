#!/bin/bash
# 从主机运行的 SSH 包装脚本 - 用于主机上的 MPI 访问容器
#
# 工作原理：
# 1. MPI 在主机上运行
# 2. MPI 调用此脚本连接到容器
# 3. 脚本执行 docker exec 进入目标容器
# 4. 在容器内执行 MPI 传递的命令

# 容器名称映射
CONTAINER_NAME_01="${CONTAINER_NAME_01:-yijun_testbed01}"
CONTAINER_NAME_23="${CONTAINER_NAME_23:-yijun_testbed23}"

# 解析参数
while [[ $# -gt 0 ]]; do
    case $1 in
        -i|-p|-o)
            shift 2
            ;;
        -*)
            shift
            ;;
        *)
            TARGET_HOST=$1
            shift
            REMOTE_CMD="$@"
            break
            ;;
    esac
done

# 构建需要透传到容器内的环境变量
build_docker_env_str() {
    local names=(
        NCCL_DEBUG NCCL_DEBUG_SUBSYS NCCL_IB_HCA NCCL_IB_GID_INDEX NCCL_IB_DISABLE
        NCCL_NET_GDR_LEVEL NCCL_P2P_LEVEL NCCL_ALGO NCCL_PROTO NCCL_SOCKET_IFNAME
        NCCL_SHM_DISABLE NCCL_P2P_DISABLE NCCL_BUFFSIZE NCCL_NTHREADS
        NCCL_IB_TIMEOUT NCCL_MIN_NCHANNELS NCCL_MAX_NCHANNELS
        CUDA_VISIBLE_DEVICES CUDA_DEVICE_ORDER
    )
    local env_str=""

    for n in "${names[@]}"; do
        if [[ -n "${!n:-}" && ! "${!n}" =~ [[:space:]] ]]; then
            env_str+=" -e ${n}=${!n}"
        fi
    done

    local mpi_vars=(
        OMPI_COMM_WORLD_RANK OMPI_COMM_WORLD_SIZE OMPI_COMM_WORLD_LOCAL_RANK
        OMPI_COMM_WORLD_LOCAL_SIZE OMPI_COMM_WORLD_NODE_RANK
        PMIX_RANK PMI_RANK PMI_SIZE MPI_LOCALRANKID
    )
    for n in "${mpi_vars[@]}"; do
        if [[ -n "${!n:-}" && ! "${!n}" =~ [[:space:]] ]]; then
            env_str+=" -e ${n}=${!n}"
        fi
    done

    printf '%s' "$env_str"
}

DOCKER_ENV_STR="$(build_docker_env_str)"

# 判断目标主机，确定容器名
if [[ "$TARGET_HOST" == "localhost" || "$TARGET_HOST" == "127.0.0.1" ]]; then
    CONTAINER_NAME="$CONTAINER_NAME_01"
elif [[ "$TARGET_HOST" == "testbed23" || "$TARGET_HOST" == *"testbed23"* ]]; then
    CONTAINER_NAME="$CONTAINER_NAME_23"
elif [[ "$TARGET_HOST" == "testbed01" || "$TARGET_HOST" == *"testbed01"* ]]; then
    CONTAINER_NAME="$CONTAINER_NAME_01"
else
    CONTAINER_NAME="$TARGET_HOST"
fi

# 对 REMOTE_CMD 做单引号安全转义
REMOTE_CMD_ESCAPED="$(printf "%s" "$REMOTE_CMD" | sed "s/'/'\\''/g")"

# 在目标容器内执行命令
exec docker exec -i${DOCKER_ENV_STR} "${CONTAINER_NAME}" bash -c "${REMOTE_CMD_ESCAPED}"
