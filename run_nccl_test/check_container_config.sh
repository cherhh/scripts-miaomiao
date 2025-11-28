#!/bin/bash
# 检查容器内是否有配置文件覆盖 NCCL 环境变量

CONTAINER_NAME="${1:-yijun_PDdisagg_test}"

echo "=========================================="
echo "检查容器内的 Shell 配置文件"
echo "容器名称: ${CONTAINER_NAME}"
echo "=========================================="
echo ""

echo "1. 检查 ~/.bashrc 中是否设置了 NCCL 变量："
echo "----------------------------------------"
docker exec -i ${CONTAINER_NAME} bash -c "grep -n 'NCCL' ~/.bashrc 2>/dev/null || echo '未找到 NCCL 相关配置'"
echo ""

echo "2. 检查 ~/.bash_profile 中是否设置了 NCCL 变量："
echo "----------------------------------------"
docker exec -i ${CONTAINER_NAME} bash -c "grep -n 'NCCL' ~/.bash_profile 2>/dev/null || echo '未找到 NCCL 相关配置'"
echo ""

echo "3. 检查 /etc/profile 中是否设置了 NCCL 变量："
echo "----------------------------------------"
docker exec -i ${CONTAINER_NAME} bash -c "grep -n 'NCCL' /etc/profile 2>/dev/null || echo '未找到 NCCL 相关配置'"
echo ""

echo "4. 检查 /etc/bash.bashrc 中是否设置了 NCCL 变量："
echo "----------------------------------------"
docker exec -i ${CONTAINER_NAME} bash -c "grep -n 'NCCL' /etc/bash.bashrc 2>/dev/null || echo '未找到 NCCL 相关配置'"
echo ""

echo "5. 测试环境变量传递 (使用 bash -lc)："
echo "----------------------------------------"
docker exec -i -e NCCL_NET_GDR_LEVEL=0 ${CONTAINER_NAME} bash -lc 'echo "NCCL_NET_GDR_LEVEL = ${NCCL_NET_GDR_LEVEL}"'
echo ""

echo "6. 测试环境变量传递 (使用 bash -c，不加载登录配置)："
echo "----------------------------------------"
docker exec -i -e NCCL_NET_GDR_LEVEL=0 ${CONTAINER_NAME} bash -c 'echo "NCCL_NET_GDR_LEVEL = ${NCCL_NET_GDR_LEVEL}"'
echo ""

echo "=========================================="
echo "诊断建议："
echo "=========================================="
echo "如果步骤5显示的值不是0，但步骤6显示正确，"
echo "说明容器内的登录shell配置文件覆盖了环境变量。"
echo ""
echo "解决方案："
echo "1. 检查并修改容器内的 ~/.bashrc 或 ~/.bash_profile"
echo "2. 或者修改 ssh_to_container.sh 使用 'bash -c' 而不是 'bash -lc'"
echo "=========================================="
