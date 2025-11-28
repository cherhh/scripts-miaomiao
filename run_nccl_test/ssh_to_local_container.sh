#!/bin/bash
# 本地容器 SSH 包装脚本 - 用于同一主机上的多容器 MPI
#
# 工作原理：
# 1. MPI 调用此脚本而不是直接调用 ssh
# 2. 对于 localhost，直接在当前容器执行
# 3. 对于其他主机名（容器名），执行 docker exec 进入目标容器
# 4. 在容器内执行 MPI 传递的命令

# 容器名称映射
CONTAINER_NAME_01="${CONTAINER_NAME_01:-yijun_testbed01}"
CONTAINER_NAME_23="${CONTAINER_NAME_23:-yijun_testbed23}"

# 解析参数
# MPI 会传递类似这样的参数：
# ssh_to_local_container.sh hostname command args...

# 跳过所有 SSH 选项参数
while [[ $# -gt 0 ]]; do
    case $1 in
        -i|-p|-o)
            # SSH 参数，跳过参数和值
            shift 2
            ;;
        -*)
            # 其他 SSH 参数，只跳过参数本身
            shift
            ;;
        *)
            # 第一个非选项参数是主机名
            TARGET_HOST=$1
            shift
            # 剩余的都是要执行的命令
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

    # 显式白名单（值中不应包含空白字符）
    for n in "${names[@]}"; do
        if [[ -n "${!n:-}" && ! "${!n}" =~ [[:space:]] ]]; then
            env_str+=" -e ${n}=${!n}"
        fi
    done

    # 精选注入与 rank 相关的 MPI/PMI 变量
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

# 判断目标主机
if [[ "$TARGET_HOST" == "localhost" || "$TARGET_HOST" == "127.0.0.1" ]]; then
    # localhost - 直接在当前容器执行
    exec bash -c "$REMOTE_CMD"
else
    # 其他主机名 - 假设是容器名，执行 docker exec
    # 根据主机名确定容器名
    if [[ "$TARGET_HOST" == "testbed23" || "$TARGET_HOST" == *"testbed23"* || "$TARGET_HOST" == "yijun_testbed23" ]]; then
        CONTAINER_NAME="$CONTAINER_NAME_23"
    elif [[ "$TARGET_HOST" == "testbed01" || "$TARGET_HOST" == *"testbed01"* || "$TARGET_HOST" == "yijun_testbed01" ]]; then
        CONTAINER_NAME="$CONTAINER_NAME_01"
    else
        # 默认使用主机名作为容器名
        CONTAINER_NAME="$TARGET_HOST"
    fi

    # 对 REMOTE_CMD 做单引号安全转义
    REMOTE_CMD_ESCAPED="$(printf "%s" "$REMOTE_CMD" | sed "s/'/'\\''/g")"

    # 在目标容器内执行命令
    exec docker exec -i${DOCKER_ENV_STR} "${CONTAINER_NAME}" bash -c "${REMOTE_CMD_ESCAPED}"
fi
