#!/bin/bash
# 配置容器间的 SSH 访问，用于 MPI 多容器测试
# 此脚本在主机上运行，会在两个容器内安装和配置 SSH

set -e

echo "=========================================="
echo "配置容器间 SSH 访问"
echo "=========================================="
echo ""

CONTAINER1="yijun_testbed01"
CONTAINER2="yijun_testbed23"

# 获取容器 RDMA 网络 IP（10.x.11.200），若失败则回退到第一个地址
get_container_ip() {
    local container=$1
    local ips
    ips=$(docker exec "$container" hostname -I)

    # 先尝试匹配 RDMA 网络段
    local rdma_ip
    rdma_ip=$(echo "$ips" | tr ' ' '\n' | grep -E -m1 '10\.[0-9]+\.11\.200')

    if [[ -n $rdma_ip ]]; then
        echo "$rdma_ip"
    else
        # 退回第一个 IP
        echo "$ips" | awk '{print $1}'
    fi
}

IP1=$(get_container_ip $CONTAINER1)
IP2=$(get_container_ip $CONTAINER2)

echo "容器 IP 地址:"
echo "  $CONTAINER1: $IP1"
echo "  $CONTAINER2: $IP2"
echo ""

# 函数：在容器内安装和配置 SSH
setup_ssh_in_container() {
    local container=$1
    local container_ip=$2

    echo ">>> 在容器 $container 中配置 SSH..."

    docker exec $container bash -c '
        # 安装 SSH server
        if ! command -v sshd &> /dev/null; then
            echo "  安装 openssh-server..."
            apt-get update -qq
            DEBIAN_FRONTEND=noninteractive apt-get install -y -qq openssh-server > /dev/null
        fi

        # 创建 SSH 目录
        mkdir -p /root/.ssh /var/run/sshd
        chmod 700 /root/.ssh

        # 生成 SSH 密钥（如果不存在）
        if [ ! -f /root/.ssh/id_rsa ]; then
            echo "  生成 SSH 密钥..."
            ssh-keygen -t rsa -N "" -f /root/.ssh/id_rsa -q
        fi

        # 配置 SSH daemon
        echo "  配置 sshd..."
        cat > /etc/ssh/sshd_config << EOF
Port 22
PermitRootLogin yes
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
PasswordAuthentication no
ChallengeResponseAuthentication no
UsePAM yes
X11Forwarding no
PrintMotd no
AcceptEnv LANG LC_* NCCL_* CUDA_* OMPI_* PMIX_* PMI_*
Subsystem sftp /usr/lib/openssh/sftp-server
EOF

        # 启动 SSH daemon
        echo "  启动 sshd..."
        /usr/sbin/sshd

        echo "  SSH 配置完成！"
    '
}

# 在两个容器中安装和配置 SSH
setup_ssh_in_container $CONTAINER1 $IP1
echo ""
setup_ssh_in_container $CONTAINER2 $IP2
echo ""

# 交换公钥
echo ">>> 交换 SSH 公钥..."

# 从 container1 获取公钥
PUBKEY1=$(docker exec $CONTAINER1 cat /root/.ssh/id_rsa.pub)

# 从 container2 获取公钥
PUBKEY2=$(docker exec $CONTAINER2 cat /root/.ssh/id_rsa.pub)

# 将 container2 的公钥添加到 container1
docker exec $CONTAINER1 bash -c "echo '$PUBKEY2' >> /root/.ssh/authorized_keys"
docker exec $CONTAINER1 bash -c "chmod 600 /root/.ssh/authorized_keys"

# 将 container1 的公钥添加到 container2
docker exec $CONTAINER2 bash -c "echo '$PUBKEY1' >> /root/.ssh/authorized_keys"
docker exec $CONTAINER2 bash -c "chmod 600 /root/.ssh/authorized_keys"

echo "  公钥交换完成！"
echo ""

# 配置 known_hosts
echo ">>> 配置 SSH known_hosts..."

docker exec $CONTAINER1 bash -c "ssh-keyscan -H $IP2 >> /root/.ssh/known_hosts 2>/dev/null"
docker exec $CONTAINER2 bash -c "ssh-keyscan -H $IP1 >> /root/.ssh/known_hosts 2>/dev/null"

echo "  known_hosts 配置完成！"
echo ""

# 测试 SSH 连接
echo ">>> 测试 SSH 连接..."

echo "  测试 $CONTAINER1 -> $CONTAINER2..."
if docker exec $CONTAINER1 ssh -o StrictHostKeyChecking=no $IP2 "echo 'SSH OK'" 2>/dev/null | grep -q "SSH OK"; then
    echo "  ✓ 连接成功！"
else
    echo "  ✗ 连接失败！"
fi

echo "  测试 $CONTAINER2 -> $CONTAINER1..."
if docker exec $CONTAINER2 ssh -o StrictHostKeyChecking=no $IP1 "echo 'SSH OK'" 2>/dev/null | grep -q "SSH OK"; then
    echo "  ✓ 连接成功！"
else
    echo "  ✗ 连接失败！"
fi

echo ""
echo "=========================================="
echo "SSH 配置完成！"
echo "=========================================="
echo ""
echo "容器 hostfile 配置："
echo "  $IP1 slots=2  # $CONTAINER1"
echo "  $IP2 slots=2  # $CONTAINER2"
echo ""
echo "现在可以在容器内运行 MPI 测试了！"
