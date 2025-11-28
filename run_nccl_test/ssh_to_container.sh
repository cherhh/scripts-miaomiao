#!/bin/bash
# SSH 包装脚本 - 让 MPI 能够 SSH 进入远程容器
#
# 工作原理：
# 1. MPI 调用此脚本而不是直接调用 ssh
# 2. 脚本 SSH 到远程主机
# 3. 在远程主机上执行 docker exec 进入容器
# 4. 在容器内执行 MPI 传递的命令

# SSH 私钥路径
SSH_KEY="${SSH_KEY:-/usr/wkspace/.ssh/id_rsa}"

# 容器名称
CONTAINER_NAME="${CONTAINER_NAME:-yijun_PDdisagg_test}"

# SSH 用户名
SSH_USER="${SSH_USER:-yijun}"

# 解析参数
# MPI 会传递类似这样的参数：
# ssh_to_container.sh -i /path/to/key -o Option=value hostname command args...

# 收集所有参数直到遇到主机名
SSH_ARGS=()
while [[ $# -gt 0 ]]; do
    case $1 in
        -i)
            # SSH 密钥参数
            SSH_ARGS+=("-i" "$2")
            shift 2
            ;;
        -p)
            # SSH 端口参数
            SSH_ARGS+=("-p" "$2")
            shift 2
            ;;
        -o)
            # SSH 选项参数
            SSH_ARGS+=("-o" "$2")
            shift 2
            ;;
        -*)
            # 其他 SSH 参数
            SSH_ARGS+=("$1")
            shift
            ;;
        *)
            # 第一个非选项参数是主机名
            REMOTE_HOST=$1
            shift
            # 剩余的都是要在远程执行的命令
            REMOTE_CMD="$@"
            break
            ;;
    esac
done

# 如果没有指定 SSH 密钥，添加默认的
if [[ ! " ${SSH_ARGS[@]} " =~ " -i " ]]; then
    SSH_ARGS+=("-i" "$SSH_KEY")
fi

# 添加禁用严格主机密钥检查
SSH_ARGS+=("-o" "StrictHostKeyChecking=no")

# 构建需要透传到容器内的环境变量（来自 mpirun -x 和 OpenMPI 注入的 OMPI_ 变量）
build_docker_env_str() {
    local names=(
        NCCL_DEBUG NCCL_DEBUG_SUBSYS NCCL_IB_HCA NCCL_IB_GID_INDEX NCCL_IB_DISABLE
        NCCL_NET_GDR_LEVEL NCCL_P2P_LEVEL NCCL_ALGO NCCL_PROTO NCCL_SOCKET_IFNAME NCCL_SHM_DISABLE NCCL_P2P_DISABLE NCCL_BUFFSIZE NCCL_NTHREADS
        NCCL_IB_TIMEOUT NCCL_MIN_NCHANNELS NCCL_MAX_NCHANNELS CUDA_VISIBLE_DEVICES CUDA_DEVICE_ORDER SSH_USER SSH_KEY CONTAINER_NAME
    )
    local env_str=""

    # 显式白名单（值中不应包含空白字符）
    for n in "${names[@]}"; do
        if [[ -n "${!n:-}" && ! "${!n}" =~ [[:space:]] ]]; then
            env_str+=" -e ${n}=${!n}"
        fi
    done

    # 精选注入与 rank 相关的 MPI/PMI 变量（避免含空格的 OMPI_MCA_* 等参数）
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

# 对 REMOTE_CMD 做单引号安全转义，避免 orted 命令中的引号被破坏
escape_for_single_quotes() {
    sed "s/'/'\\''/g"
}
REMOTE_CMD_ESCAPED="$(printf "%s" "$REMOTE_CMD" | escape_for_single_quotes)"

# 构建在远程容器内执行的命令（把必要环境变量通过 -e 传入）
# 使用 bash -c 而不是 bash -lc，避免容器内的 .bashrc 等配置文件覆盖环境变量
CONTAINER_CMD="docker exec -i${DOCKER_ENV_STR} ${CONTAINER_NAME} bash -c '${REMOTE_CMD_ESCAPED}'"

# 添加用户名到主机名
REMOTE_HOST_WITH_USER="${SSH_USER}@${REMOTE_HOST}"

# 调试输出（可选，取消注释以调试）
# echo "DEBUG: SSH to $REMOTE_HOST_WITH_USER" >&2
# echo "DEBUG: Container: $CONTAINER_NAME" >&2
# echo "DEBUG: Remote cmd: $REMOTE_CMD" >&2
# echo "DEBUG: Full cmd: ssh ${SSH_ARGS[@]} $REMOTE_HOST_WITH_USER \"$CONTAINER_CMD\"" >&2

# 执行 SSH 到远程主机，然后 docker exec 进入容器
exec ssh "${SSH_ARGS[@]}" "$REMOTE_HOST_WITH_USER" "$CONTAINER_CMD"
