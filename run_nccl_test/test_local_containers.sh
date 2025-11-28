#!/bin/bash
# 本地双容器环境测试脚本

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/env_config.sh"

echo ""
echo "=========================================="
echo "本地双容器环境测试"
echo "=========================================="

# 测试 1: 检查容器是否运行
echo ""
echo "测试 1: 检查容器状态..."
for container in yijun_testbed01 yijun_testbed23; do
    if docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
        echo "  ✓ 容器 ${container} 正在运行"
    else
        echo "  ✗ 容器 ${container} 未运行"
        exit 1
    fi
done

# 测试 2: 检查 GPU
echo ""
echo "测试 2: 检查 GPU 可用性..."
for container in yijun_testbed01 yijun_testbed23; do
    gpu_count=$(docker exec ${container} nvidia-smi -L 2>/dev/null | wc -l)
    echo "  容器 ${container}: ${gpu_count} 个 GPU"
done

# 测试 3: 检查网络连接
echo ""
echo "测试 3: 检查容器间网络连接..."
testbed01_ip=$(docker exec yijun_testbed01 ip -4 addr show eno0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || echo "")
testbed23_ip=$(docker exec yijun_testbed23 ip -4 addr show eno0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || echo "")

echo "  yijun_testbed01 IP (eno0): ${testbed01_ip}"
echo "  yijun_testbed23 IP (eno0): ${testbed23_ip}"

if [ -n "$testbed23_ip" ]; then
    if docker exec yijun_testbed01 ping -c 2 -W 2 ${testbed23_ip} >/dev/null 2>&1; then
        echo "  ✓ testbed01 可以 ping 通 testbed23"
    else
        echo "  ✗ testbed01 无法 ping 通 testbed23"
        exit 1
    fi
fi

# 测试 4: 检查 NCCL tests 二进制
echo ""
echo "测试 4: 检查 NCCL tests 二进制文件..."
for container in yijun_testbed01 yijun_testbed23; do
    if docker exec ${container} test -f /usr/wkspace/docker/testbed/nccl-tests/build/all_reduce_perf; then
        echo "  ✓ 容器 ${container} 有 all_reduce_perf"
    else
        echo "  ✗ 容器 ${container} 缺少 all_reduce_perf"
        exit 1
    fi
done

# 测试 5: 测试本地容器 SSH 包装脚本
echo ""
echo "测试 5: 测试容器间命令执行..."

# 测试 localhost
result=$(${SCRIPT_DIR}/ssh_to_local_container.sh localhost "echo 'Hello from localhost'")
if [[ "$result" == *"Hello from localhost"* ]]; then
    echo "  ✓ localhost 命令执行成功"
else
    echo "  ✗ localhost 命令执行失败"
fi

# 测试远程容器
result=$(${SCRIPT_DIR}/ssh_to_local_container.sh yijun_testbed23 "echo 'Hello from testbed23'")
if [[ "$result" == *"Hello from testbed23"* ]]; then
    echo "  ✓ yijun_testbed23 命令执行成功"
else
    echo "  ✗ yijun_testbed23 命令执行失败"
fi

# 测试 6: 简单的 MPI 测试
echo ""
echo "测试 6: 简单的 MPI hostname 测试..."
mpirun --allow-run-as-root \
    -np 4 \
    -N 2 \
    --hostfile ${SCRIPT_DIR}/hostfile \
    --mca plm_rsh_agent ${SCRIPT_DIR}/ssh_to_local_container.sh \
    -x CONTAINER_NAME_01=yijun_testbed01 \
    -x CONTAINER_NAME_23=yijun_testbed23 \
    hostname || echo "  警告: MPI hostname 测试失败，但这可能是正常的"

echo ""
echo "=========================================="
echo "环境测试完成！"
echo "=========================================="
echo ""
echo "现在可以运行 NCCL 测试："
echo "  cd ${SCRIPT_DIR}"
echo "  docker exec -it yijun_testbed01 bash"
echo "  cd /usr/wkspace/docker/testbed/script/run_nccl_test"
echo "  ./run_all_reduce.sh"
echo ""
