# NCCL 跨节点测试配置指南

本文档说明如何在 Docker 容器环境中运行跨节点的 NCCL 性能测试。

## 环境信息

- **容器名称**: `yijun_PDdisagg_test`
- **每节点 GPU 数量**: 4 块
- **每节点网卡数量**: 2 块
- **测试类型**: 跨节点 all_reduce 性能测试

## 测试命令说明

```bash
mpirun -np 64 -N 8 ./build/all_reduce_perf -b 8 -e 8G -f 2 -g 1
```

**参数解析**:
- `-np 64`: 总进程数为 64
- `-N 8`: 每个节点 8 个进程
- 因此需要 **8 个节点** (64 ÷ 8 = 8)
- `-b 8`: 起始数据大小 8 字节
- `-e 8G`: 结束数据大小 8GB
- `-f 2`: 每次数据大小翻倍（增长因子为 2）
- `-g 1`: 每个进程使用 1 个 GPU

## 必要配置清单

### 1. MPI 环境配置

#### 1.1 安装 OpenMPI 或 MPICH

在容器内确保已安装 MPI:

```bash
# 检查 MPI 版本
mpirun --version

# 如未安装，使用以下命令安装 (Ubuntu/Debian)
apt-get update
apt-get install -y openmpi-bin openmpi-common libopenmpi-dev
```

#### 1.2 SSH 免密登录配置

MPI 需要在节点间进行 SSH 通信，必须配置免密登录：

```bash
# 在容器内生成 SSH 密钥
ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa

# 将公钥添加到 authorized_keys
cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
chmod 700 ~/.ssh

# 将公钥复制到其他所有节点
# 对于 8 节点集群，需要在所有节点间建立互信
```

#### 1.3 创建 hostfile

创建 MPI hostfile 指定节点和进程分配：

```bash
# hostfile 示例 (假设有 8 个节点)
node0 slots=8
node1 slots=8
node2 slots=8
node3 slots=8
node4 slots=8
node5 slots=8
node6 slots=8
node7 slots=8
```

或使用 IP 地址:

```bash
192.168.1.1 slots=8
192.168.1.2 slots=8
192.168.1.3 slots=8
# ... 继续添加到第 8 个节点
```

### 2. NCCL 网络配置

#### 2.1 网卡配置 (双网卡环境)

查看可用网络接口:

```bash
# 查看网卡信息
ifconfig
# 或
ip addr show
```

设置 NCCL 使用的网络接口:

```bash
# 如果使用 InfiniBand/RoCE
export NCCL_IB_HCA=mlx5_0,mlx5_1  # 提供可用网卡列表

# 如果使用以太网
export NCCL_SOCKET_IFNAME=eth0,eth1  # 提供可用网卡列表

# GID Index (对于 InfiniBand/RoCE)
export NCCL_IB_GID_INDEX=3
```

#### 2.2 多网卡配置的正确理解

**重要说明**: 配置多个网卡时，需要理解 NCCL 的实际行为：

**每个 GPU 只使用一个 NIC**:
```bash
export NCCL_IB_HCA=mlx5_0,mlx5_1

# 这个配置的真实含义：
# - 告诉 NCCL 有哪些网卡可用（候选列表）
# - NCCL 根据 PCIe 拓扑为每个 GPU 选择一个最优的 NIC
# - 每个 GPU 绑定后只使用被分配的那一个 NIC

# 实际映射示例（4 GPU + 2 NIC）：
# GPU 0 → mlx5_0 (只用这一个)
# GPU 1 → mlx5_0 (只用这一个)
# GPU 2 → mlx5_1 (只用这一个)
# GPU 3 → mlx5_1 (只用这一个)
```

**多网卡的性能提升原理**:
```
单网卡配置 (NCCL_IB_HCA=mlx5_0):
  - 所有 4 个 GPU 共享 1 个 NIC (比如 100 Gbps)
  - 总可用带宽: 100 Gbps
  - 容易出现网络拥塞

双网卡配置 (NCCL_IB_HCA=mlx5_0,mlx5_1):
  - GPU 0,1 使用 mlx5_0 (100 Gbps)
  - GPU 2,3 使用 mlx5_1 (100 Gbps)
  - 总可用带宽: 200 Gbps
  - 减少网络拥塞

性能提升来源:
  ✓ 不同 GPU 的流量分散到不同 NIC
  ✗ 单个 GPU 同时使用多个 NIC (不支持)
```

**查看实际映射关系**:
```bash
# 方法 1: 查看 PCIe 拓扑
nvidia-smi topo -m

# 方法 2: 运行测试时查看 NCCL 日志
export NCCL_DEBUG=INFO
export NCCL_DEBUG_SUBSYS=INIT,NET
# 日志会显示: "GPU X using NIC Y"

# 方法 3: 使用提供的拓扑检查脚本
./check_gpu_nic_topology.sh
```

**典型拓扑示例**:
```
双路服务器 (4 GPU + 2 NIC):

CPU 0 (NUMA 0)          CPU 1 (NUMA 1)
├── GPU 0               ├── GPU 2
├── GPU 1               ├── GPU 3
└── NIC 0 (mlx5_0)      └── NIC 1 (mlx5_1)

NCCL 自动映射:
GPU 0,1 → NIC 0 (本地，延迟低)
GPU 2,3 → NIC 1 (本地，延迟低)

如果 GPU 0 强制用 NIC 1 → 需要跨 NUMA，延迟高
```

#### 2.3 NCCL 环境变量

```bash
# 调试信息（可选，用于排查问题）
export NCCL_DEBUG=INFO
export NCCL_DEBUG_SUBSYS=INIT,NET

# 跨节点通信配置
export NCCL_IB_DISABLE=0          # 启用 InfiniBand (如果可用)
export NCCL_NET_GDR_LEVEL=5       # GPU Direct RDMA 级别
export NCCL_IB_TIMEOUT=22         # IB 超时设置

# 禁用共享内存和 P2P (跨节点测试)
export NCCL_SHM_DISABLE=1         # 禁用共享内存 (跨节点不需要)
export NCCL_P2P_DISABLE=1         # 禁用 P2P (跨节点使用网络)

# 性能优化
export NCCL_BUFFSIZE=2097152      # 缓冲区大小
export NCCL_NTHREADS=512          # NCCL 线程数
```

### 3. Docker 容器配置

#### 3.1 容器启动参数

确保容器启动时包含以下配置:

```bash
docker run -d \
  --name yijun_PDdisagg_test \
  --gpus all \                     # 访问所有 GPU
  --network host \                 # 使用主机网络 (推荐)
  --ipc=host \                     # 共享 IPC 命名空间
  --cap-add=IPC_LOCK \            # 允许锁定内存
  --ulimit memlock=-1:-1 \        # 无限制内存锁定
  --device=/dev/infiniband \      # InfiniBand 设备 (如果使用)
  -v /dev/shm:/dev/shm \          # 共享内存
  your_image:tag
```

#### 3.2 容器内环境检查

```bash
# 进入容器
docker exec -it yijun_PDdisagg_test bash

# 检查 GPU
nvidia-smi

# 检查网络
ifconfig

# 检查 NCCL
ls /usr/lib/x86_64-linux-gnu/libnccl* || ls /usr/local/lib/libnccl*
```

### 4. GPU 分配策略

由于每个节点有 4 块 GPU，每个节点运行 8 个进程，有两种分配方式：

#### 方式 1: 每个 GPU 运行 2 个进程

```bash
# 在 MPI 命令中设置
mpirun -np 64 -N 8 \
  -x CUDA_VISIBLE_DEVICES \
  ./build/all_reduce_perf -b 8 -e 8G -f 2 -g 1
```

需要使用脚本为每个进程设置不同的 `CUDA_VISIBLE_DEVICES`。

#### 方式 2: 使用 GPU 绑定脚本 (推荐)

创建启动脚本 `run_with_gpu_binding.sh`:

```bash
#!/bin/bash
# 根据 MPI rank 自动分配 GPU
LOCAL_RANK=$((OMPI_COMM_WORLD_LOCAL_RANK % 4))
export CUDA_VISIBLE_DEVICES=$LOCAL_RANK
exec "$@"
```

然后使用:

```bash
chmod +x run_with_gpu_binding.sh
mpirun -np 64 -N 8 \
  ./run_with_gpu_binding.sh ./build/all_reduce_perf -b 8 -e 8G -f 2 -g 1
```

### 5. 完整启动示例

#### 5.1 准备工作

```bash
# 1. 编译 NCCL tests (如果还未编译)
cd /path/to/nccl-tests
make MPI=1 MPI_HOME=/usr/lib/x86_64-linux-gnu/openmpi

# 2. 创建 hostfile
cat > hostfile << EOF
node0 slots=8
node1 slots=8
node2 slots=8
node3 slots=8
node4 slots=8
node5 slots=8
node6 slots=8
node7 slots=8
EOF

# 3. 设置环境变量 (创建 env_config.sh)
cat > env_config.sh << 'EOF'
export NCCL_DEBUG=INFO
export NCCL_IB_HCA=mlx5_0,mlx5_1
export NCCL_IB_GID_INDEX=3
export NCCL_SOCKET_IFNAME=eth0,eth1
export NCCL_SHM_DISABLE=1
export NCCL_P2P_DISABLE=1
export NCCL_IB_DISABLE=0
export NCCL_NET_GDR_LEVEL=5
EOF

source env_config.sh
```

#### 5.2 运行测试

```bash
# 基础运行命令
mpirun -np 64 -N 8 \
  --hostfile hostfile \
  -x NCCL_DEBUG \
  -x NCCL_IB_HCA \
  -x NCCL_IB_GID_INDEX \
  -x NCCL_SOCKET_IFNAME \
  -x NCCL_SHM_DISABLE \
  -x NCCL_P2P_DISABLE \
  ./build/all_reduce_perf -b 8 -e 8G -f 2 -g 1
```

### 6. 常见问题排查

#### 6.1 网络连接问题

```bash
# 测试节点间网络连通性
ping node1
ping node2
# ...

# 测试 RDMA (如果使用 InfiniBand)
ibv_devinfo
ibstatus
```

#### 6.2 NCCL 初始化失败

```bash
# 启用详细调试
export NCCL_DEBUG=TRACE
export NCCL_DEBUG_SUBSYS=ALL

# 检查是否正确检测到网络设备
export NCCL_DEBUG_SUBSYS=NET
```

#### 6.3 GPU 访问问题

```bash
# 检查每个节点的 GPU 可见性
mpirun -np 64 -N 8 --hostfile hostfile \
  bash -c 'echo "Rank $OMPI_COMM_WORLD_RANK: $(nvidia-smi -L)"'
```

#### 6.4 SSH 连接问题

```bash
# 测试 SSH 免密登录
ssh node1 hostname
ssh node2 hostname

# 禁用 SSH 严格主机密钥检查 (测试环境)
export OMPI_MCA_plm_rsh_args="-o StrictHostKeyChecking=no"
```

### 7. 性能优化建议

1. **网络优化**:
   - 确保使用高速网络 (InfiniBand/100GbE)
   - 启用 GPU Direct RDMA (`NCCL_NET_GDR_LEVEL=5`)
   - 配置多个网卡让 NCCL 自动分配（`NCCL_IB_HCA=mlx5_0,mlx5_1`）
   - 确保网卡和 GPU 的 NUMA 亲和性正确（避免跨 socket 流量）

2. **GPU 优化**:
   - 使用 GPU 亲和性绑定（提供的 `gpu_binding.sh` 脚本）
   - 设置正确的 CUDA_VISIBLE_DEVICES
   - 启用 GPU Persistence Mode (`nvidia-smi -pm 1`)

3. **MPI 优化**:
   - 使用 `--bind-to core` 进行 CPU 绑定
   - 调整 `--map-by` 参数优化进程映射
   - 确保进程和 GPU 在同一 NUMA 节点

### 8. 预期输出

成功运行后，应该看到类似输出:

```
# nThread 1 nGpus 1 minBytes 8 maxBytes 8589934592 step: 2(factor) warmup iters: 5 iters: 20 agg iters: 1 validation: 1 graph: 0
#
# Using devices
#  Rank  0 Group  0 Pid    xxx on   node0 device  0 [0x00] NVIDIA A100-SXM4-40GB
#  Rank  1 Group  0 Pid    xxx on   node0 device  1 [0x00] NVIDIA A100-SXM4-40GB
#  ...
#
#                                                              out-of-place                       in-place
#       size         count      type   redop    root     time   algbw   busbw #wrong     time   algbw   busbw #wrong
#        (B)    (elements)                               (us)  (GB/s)  (GB/s)            (us)  (GB/s)  (GB/s)
           8             2     float     sum      -1    xx.xx   xx.xx   xx.xx      0    xx.xx   xx.xx   xx.xx      0
          16             4     float     sum      -1    xx.xx   xx.xx   xx.xx      0    xx.xx   xx.xx   xx.xx      0
          32             8     float     sum      -1    xx.xx   xx.xx   xx.xx      0    xx.xx   xx.xx   xx.xx      0
# ...
```

关注以下指标:
- **algbw**: 算法带宽 (实际数据传输带宽)
- **busbw**: 总线带宽 (考虑通信拓扑的有效带宽)
- **#wrong**: 验证错误数量 (应该为 0)

## 9. 常见误解澄清

### ❌ 误解 1: "配置多个网卡后，每个 GPU 会同时使用所有网卡"

**现实**: 每个 GPU 只使用一个 NIC

```bash
export NCCL_IB_HCA=mlx5_0,mlx5_1

# 错误理解: GPU 0 同时使用 mlx5_0 和 mlx5_1 ❌
# 正确理解: GPU 0 只使用 mlx5_0 或 mlx5_1 其中一个 ✓
```

### ❌ 误解 2: "增加通道数可以让 GPU 使用多个网卡"

**现实**: 通道只是在同一个 NIC 上的并行路径

```bash
export NCCL_MIN_NCHANNELS=4

# 错误理解: 4 个通道分配到 4 个不同的 NIC 上 ❌
# 正确理解: 4 个通道都在同一个 NIC 上并行工作 ✓
```

### ❌ 误解 3: "多网卡配置会让单 GPU 带宽翻倍"

**现实**: 多网卡的带宽是在不同 GPU 之间分配的

```bash
# 4 GPU + 2 NIC (每个 100 Gbps)

单网卡:
  每个 GPU 可用带宽: ~25 Gbps (100/4)

双网卡:
  每个 GPU 可用带宽: ~50 Gbps (200/4)
  但每个 GPU 仍然只用一个 NIC

注意: 单个 GPU 无法获得 200 Gbps（2个网卡的总和）
```

### ✓ 正确理解: 多网卡的作用

1. **分散流量**: 不同 GPU 使用不同 NIC，避免单 NIC 拥塞
2. **增加总带宽**: 系统总带宽增加（所有 GPU 共享）
3. **NUMA 优化**: GPU 使用本地 NIC，减少跨 socket 延迟
4. **不是**: 单个 GPU 同时使用多个 NIC

### 验证你的理解

运行以下命令验证实际映射：

```bash
# 查看拓扑
nvidia-smi topo -m

# 查看 NCCL 的选择
export NCCL_DEBUG=INFO
export NCCL_DEBUG_SUBSYS=NET

# 运行测试，日志会显示每个 GPU 使用的 NIC
./run_all_reduce.sh 2>&1 | grep "using NIC"
```

## 参考资料

- [NCCL Tests GitHub](https://github.com/NVIDIA/nccl-tests)
- [NCCL 环境变量文档](https://docs.nvidia.com/deeplearning/nccl/user-guide/docs/env.html)
- [OpenMPI 文档](https://www.open-mpi.org/doc/)
- [NVIDIA GPU 拓扑文档](https://docs.nvidia.com/cuda/cuda-c-programming-guide/index.html#numa-best-practices)