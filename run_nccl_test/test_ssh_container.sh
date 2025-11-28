#!/bin/bash
# 测试 SSH 到容器的连接

echo "=========================================="
echo "测试 SSH 到远程容器的连接"
echo "=========================================="
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SSH_KEY="${SSH_KEY:-/usr/wkspace/.ssh/id_rsa}"
SSH_USER="${SSH_USER:-yijun}"
CONTAINER_NAME="yijun_PDdisagg_test"

# 测试节点列表
NODES=("gpu11" "gpu12")

echo "1. 测试主机 SSH 连接..."
echo "----------------------------------------"
for node in "${NODES[@]}"; do
    echo -n "  测试连接到 $SSH_USER@$node 主机: "
    if ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=5 "$SSH_USER@$node" "echo OK" 2>/dev/null; then
        echo "✓ 成功"
    else
        echo "✗ 失败"
        echo "    请检查: ssh -i $SSH_KEY $SSH_USER@$node"
    fi
done
echo ""

echo "2. 测试容器是否存在..."
echo "----------------------------------------"
for node in "${NODES[@]}"; do
    echo -n "  检查 $node 上的容器 $CONTAINER_NAME: "
    result=$(ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_USER@$node" \
        "docker ps --format '{{.Names}}' | grep -w $CONTAINER_NAME" 2>/dev/null)
    if [ -n "$result" ]; then
        echo "✓ 运行中"
    else
        echo "✗ 未找到或未运行"
        echo "    请检查: ssh -i $SSH_KEY $SSH_USER@$node 'docker ps | grep $CONTAINER_NAME'"
    fi
done
echo ""

echo "3. 测试 SSH 包装脚本..."
echo "----------------------------------------"
for node in "${NODES[@]}"; do
    echo -n "  使用 ssh_to_container.sh 连接 $node: "
    result=$(SSH_USER="$SSH_USER" "${SCRIPT_DIR}/ssh_to_container.sh" -i "$SSH_KEY" "$node" "hostname" 2>/dev/null)
    if [ $? -eq 0 ] && [ -n "$result" ]; then
        echo "✓ 成功 (容器主机名: $result)"
    else
        echo "✗ 失败"
        echo "    调试命令: SSH_USER=$SSH_USER ${SCRIPT_DIR}/ssh_to_container.sh -i $SSH_KEY $node 'hostname'"
    fi
done
echo ""

echo "4. 测试在远程容器中执行 GPU 命令..."
echo "----------------------------------------"
for node in "${NODES[@]}"; do
    echo "  节点 $node:"
    result=$(SSH_USER="$SSH_USER" "${SCRIPT_DIR}/ssh_to_container.sh" -i "$SSH_KEY" "$node" \
        "nvidia-smi --query-gpu=index,name --format=csv,noheader" 2>/dev/null)
    if [ $? -eq 0 ] && [ -n "$result" ]; then
        echo "$result" | awk '{print "    ✓ " $0}'
    else
        echo "    ✗ 无法获取 GPU 信息"
    fi
done
echo ""

echo "5. 测试 MPI 环境变量传递..."
echo "----------------------------------------"
for node in "${NODES[@]}"; do
    echo -n "  测试 $node 环境变量: "
    result=$(SSH_USER="$SSH_USER" "${SCRIPT_DIR}/ssh_to_container.sh" -i "$SSH_KEY" "$node" \
        'export TEST_VAR=HelloWorld && echo $TEST_VAR' 2>/dev/null)
    if [ "$result" = "HelloWorld" ]; then
        echo "✓ 成功"
    else
        echo "✗ 失败 (收到: '$result')"
    fi
done
echo ""

echo "=========================================="
echo "测试完成"
echo "=========================================="
echo ""
echo "如果所有测试都通过，可以运行:"
echo "  ./run_all_reduce.sh"
echo ""
