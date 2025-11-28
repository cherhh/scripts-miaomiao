# NCCL 测试快速开始指南

## 快速上手（5 分钟）

### 1. 检查环境

```bash
cd /home/yijun/docker/testbed/script/run_nccl_test
./check_env.sh
```

这会检查：
- MPI 是否安装
- GPU 是否可用
- NCCL 库是否存在
- 网络接口
- NCCL tests 是否编译
- SSH 配置

### 2. 配置 Hostfile

```bash
# 复制示例文件
cp hostfile.example hostfile

# 编辑 hostfile，填入实际的节点信息
vim hostfile
```

示例配置（根据你的实际环境修改）:
```
192.168.1.101 slots=8
192.168.1.102 slots=8
192.168.1.103 slots=8
192.168.1.104 slots=8
192.168.1.105 slots=8
192.168.1.106 slots=8
192.168.1.107 slots=8
192.168.1.108 slots=8
```

### 3. 配置环境变量（可选）

编辑 `env_config.sh` 根据你的网络环境调整：

```bash
vim env_config.sh
```

主要配置项：
- `NCCL_IB_HCA`: InfiniBand 网卡名称（如果使用 IB）
- `NCCL_SOCKET_IFNAME`: 以太网网卡名称（如果使用以太网）
- `NCCL_IB_GID_INDEX`: GID 索引

### 4. 配置 SSH 免密登录

```bash
# 生成 SSH 密钥 (如果还没有)
ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa

# 将公钥复制到所有节点
for node in node1 node2 node3 node4 node5 node6 node7 node8; do
    ssh-copy-id $node
done

# 测试 SSH 连接
for node in node1 node2 node3 node4 node5 node6 node7 node8; do
    ssh $node hostname
done
```

### 5. 运行测试

```bash
./run_all_reduce.sh
```

## 文件说明

```
run_nccl_test/
├── README.md              # 详细配置文档
├── QUICKSTART.md          # 本文件 - 快速开始指南
├── check_env.sh           # 环境检查脚本
├── env_config.sh          # 环境变量配置
├── hostfile.example       # Hostfile 示例
├── hostfile               # 实际使用的 hostfile (需要创建)
├── gpu_binding.sh         # GPU 绑定脚本
└── run_all_reduce.sh      # 主运行脚本
```

## Docker 环境特殊配置

如果在 Docker 容器中运行，确保容器启动时包含以下参数：

```bash
docker run -d \
  --name yijun_PDdisagg_test \
  --gpus all \
  --network host \
  --ipc=host \
  --cap-add=IPC_LOCK \
  --ulimit memlock=-1:-1 \
  --device=/dev/infiniband \
  -v /dev/shm:/dev/shm \
  your_image:tag
```

## 自定义测试参数

可以通过环境变量自定义测试参数：

```bash
# 修改数据大小范围
export TEST_MIN_BYTES=1K
export TEST_MAX_BYTES=1G

# 修改进程配置
export TOTAL_PROCS=32
export PROCS_PER_NODE=4

# 运行测试
./run_all_reduce.sh
```

## 常见问题

### 问题 1: MPI 进程无法启动

**症状**: `mpirun` 报错 "Could not connect to remote host"

**解决**:
```bash
# 检查 SSH 连接
ssh node1 hostname

# 检查 /etc/hosts 配置
cat /etc/hosts

# 确保 hostfile 中的主机名可以解析
```

### 问题 2: NCCL 初始化失败

**症状**: "NCCL WARN NET/Socket : No usable listening interface found"

**解决**:
```bash
# 查看可用网络接口
ifconfig

# 在 env_config.sh 中设置正确的接口
export NCCL_SOCKET_IFNAME=eth0  # 替换为实际接口名
```

### 问题 3: GPU 访问错误

**症状**: "CUDA error: no CUDA-capable device is detected"

**解决**:
```bash
# 检查 GPU 可见性
nvidia-smi

# 检查容器是否有 GPU 访问权限
docker exec yijun_PDdisagg_test nvidia-smi

# 确保 --gpus all 参数已设置
```

### 问题 4: InfiniBand 未检测到

**症状**: "NCCL WARN No InfiniBand device found"

**解决**:
```bash
# 检查 IB 设备
ibv_devinfo

# 检查设备名称是否正确
export NCCL_IB_HCA=mlx5_0  # 使用 ibv_devinfo 显示的设备名

# 如果使用以太网，禁用 IB
export NCCL_IB_DISABLE=1
export NCCL_SOCKET_IFNAME=eth0
```

## 手动运行命令

如果脚本无法满足需求，可以手动运行：

```bash
# 加载环境
source env_config.sh

# 手动运行 all_reduce 测试
mpirun -np 64 -N 8 \
  --hostfile hostfile \
  -x NCCL_DEBUG \
  -x NCCL_IB_HCA \
  -x NCCL_IB_GID_INDEX \
  -x NCCL_SOCKET_IFNAME \
  -x NCCL_SHM_DISABLE \
  -x NCCL_P2P_DISABLE \
  ./gpu_binding.sh \
  /home/yijun/docker/testbed/nccl-tests/build/all_reduce_perf \
  -b 8 -e 8G -f 2 -g 1
```

## 其他 NCCL 测试

除了 `all_reduce_perf`，还可以测试其他操作：

```bash
# All-Gather 测试
mpirun -np 64 -N 8 --hostfile hostfile \
  ./gpu_binding.sh \
  /home/yijun/docker/testbed/nccl-tests/build/all_gather_perf \
  -b 8 -e 8G -f 2 -g 1

# Broadcast 测试
mpirun -np 64 -N 8 --hostfile hostfile \
  ./gpu_binding.sh \
  /home/yijun/docker/testbed/nccl-tests/build/broadcast_perf \
  -b 8 -e 8G -f 2 -g 1

# Reduce-Scatter 测试
mpirun -np 64 -N 8 --hostfile hostfile \
  ./gpu_binding.sh \
  /home/yijun/docker/testbed/nccl-tests/build/reduce_scatter_perf \
  -b 8 -e 8G -f 2 -g 1

# All-to-All 测试
mpirun -np 64 -N 8 --hostfile hostfile \
  ./gpu_binding.sh \
  /home/yijun/docker/testbed/nccl-tests/build/alltoall_perf \
  -b 8 -e 8G -f 2 -g 1
```

## 性能调优提示

1. **网络带宽优化**
   - 确保使用高速网络 (InfiniBand/100GbE)
   - 启用 GPU Direct RDMA: `export NCCL_NET_GDR_LEVEL=5`
   - 配置多网卡让 NCCL 自动分配: `export NCCL_IB_HCA=mlx5_0,mlx5_1`
   - 注意：每个 GPU 只使用一个 NIC，多网卡的作用是让不同 GPU 使用不同 NIC

2. **减少延迟**
   - 增加 NCCL 线程数: `export NCCL_NTHREADS=512`
   - 调整缓冲区大小: `export NCCL_BUFFSIZE=2097152`
   - 确保 GPU 和 NIC 的 NUMA 亲和性正确

3. **GPU 绑定**
   - 使用 `gpu_binding.sh` 确保进程正确绑定到 GPU
   - 避免多个进程竞争同一 GPU
   - 确保进程和 GPU 在同一 NUMA 节点

4. **监控和调试**
   - 启用详细日志: `export NCCL_DEBUG=TRACE`
   - 监控网络使用: `iftop`, `ibstat`
   - 监控 GPU 使用: `nvidia-smi dmon`
   - 查看 GPU-NIC 映射: `./check_gpu_nic_topology.sh`

## 下一步

- 详细配置说明请查看 `README.md`
- 遇到问题请检查环境: `./check_env.sh`
- 调整参数请编辑 `env_config.sh`
