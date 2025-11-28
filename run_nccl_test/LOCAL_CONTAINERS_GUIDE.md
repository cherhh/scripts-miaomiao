# 本地双容器 NCCL 测试指南

## 环境概述

- **节点**: gpu11 (单主机)
- **容器1**: yijun_testbed01 (2x RTX 3090)
- **容器2**: yijun_testbed23 (2x RTX 3090)
- **网络**: eno0 虚拟网卡互连
- **总 GPU**: 4 块
- **总进程**: 4 个 (每容器 2 个进程，每 GPU 1 进程)

## 网络配置

```
yijun_testbed01: 10.0.11.200 (eno0)
yijun_testbed23: 10.2.11.200 (eno0)
```

## 快速开始

### 方式 1: 从容器内部运行 (推荐)

```bash
# 1. 进入容器 yijun_testbed01
docker exec -it yijun_testbed01 bash

# 2. 进入脚本目录
cd /usr/wkspace/docker/testbed/script/run_nccl_test

# 3. 运行 NCCL all_reduce 测试
./run_all_reduce.sh
```

### 方式 2: 从主机运行

```bash
# 从主机直接执行
docker exec -it yijun_testbed01 bash -c "cd /usr/wkspace/docker/testbed/script/run_nccl_test && ./run_all_reduce.sh"
```

## 配置说明

### 1. hostfile 配置

文件: `hostfile`

```
localhost slots=2      # yijun_testbed01 (本地容器)
testbed23 slots=2      # yijun_testbed23 (通过 docker exec 连接)
```

### 2. 环境配置

文件: `env_config.sh`

关键配置：
- `TOTAL_NODES=2` - 2个容器
- `PROCS_PER_NODE=2` - 每容器2个进程
- `TOTAL_PROCS=4` - 总共4个进程
- `NCCL_IB_HCA=eno0` - 使用 eno0 网卡
- `TEST_MIN_BYTES=4M` - 测试起始数据大小
- `TEST_MAX_BYTES=1G` - 测试结束数据大小

### 3. SSH 包装脚本

文件: `ssh_to_local_container.sh`

工作原理：
- **localhost** → 直接在当前容器执行命令
- **testbed23** → 执行 `docker exec yijun_testbed23` 进入目标容器

## 测试参数说明

当前配置测试从 4MB 到 1GB 的 all_reduce 操作：

```bash
-b 4M          # 起始: 4MB
-e 1G          # 结束: 1GB
-f 2           # 每次翻倍
-g 1           # 每进程使用 1 个 GPU
```

## 修改测试参数

### 调整数据大小范围

编辑 `env_config.sh`:

```bash
export TEST_MIN_BYTES=8M    # 从 8MB 开始
export TEST_MAX_BYTES=2G    # 到 2GB 结束
```

### 调整 NCCL 通道数

编辑 `env_config.sh`:

```bash
export NCCL_MIN_NCHANNELS=4
export NCCL_MAX_NCHANNELS=16
```

### 启用详细调试日志

编辑 `env_config.sh`:

```bash
export NCCL_DEBUG=TRACE           # 最详细的日志
export NCCL_DEBUG_SUBSYS=ALL      # 所有子系统
```

## 预期输出

成功运行后，您应该看到类似输出：

```
==========================================
NCCL All-Reduce 测试配置
==========================================
...
开始运行 NCCL All-Reduce 测试...

# nThread 1 nGpus 1 minBytes 4194304 maxBytes 1073741824 step: 2(factor) warmup iters: 5 iters: 20
#
# Using devices
#  Rank  0 Pid xxxxx on localhost device  0 [0x00] NVIDIA GeForce RTX 3090
#  Rank  1 Pid xxxxx on localhost device  1 [0x00] NVIDIA GeForce RTX 3090
#  Rank  2 Pid xxxxx on testbed23 device  0 [0x00] NVIDIA GeForce RTX 3090
#  Rank  3 Pid xxxxx on testbed23 device  1 [0x00] NVIDIA GeForce RTX 3090
#
#       size         count      type   redop    root     time   algbw   busbw #wrong
#        (B)    (elements)                               (us)  (GB/s)  (GB/s)
   4194304       1048576     float     sum      -1   xxxx.x   xx.xx   xx.xx      0
   8388608       2097152     float     sum      -1   xxxx.x   xx.xx   xx.xx      0
  ...
```

关键指标：
- **algbw**: 算法带宽 (实际数据传输速度)
- **busbw**: 总线带宽 (有效通信带宽)
- **#wrong**: 验证错误 (应该为 0)

## 故障排查

### 问题 1: 容器间无法通信

```bash
# 检查网络连接
docker exec yijun_testbed01 ping -c 2 10.2.11.200

# 检查容器状态
docker ps | grep testbed
```

### 问题 2: GPU 不可见

```bash
# 在两个容器中检查 GPU
docker exec yijun_testbed01 nvidia-smi
docker exec yijun_testbed23 nvidia-smi
```

### 问题 3: NCCL 初始化失败

启用调试日志：

```bash
# 编辑 env_config.sh
export NCCL_DEBUG=INFO
export NCCL_DEBUG_SUBSYS=INIT,NET
```

### 问题 4: MPI 连接错误

检查 SSH 包装脚本权限：

```bash
ls -l /usr/wkspace/docker/testbed/script/run_nccl_test/ssh_to_local_container.sh
# 应该是可执行的 (-rwxr-xr-x)

# 如果不可执行
chmod +x /usr/wkspace/docker/testbed/script/run_nccl_test/ssh_to_local_container.sh
```

## 运行其他 NCCL 测试

### All-Gather

```bash
# 修改 run_all_reduce.sh 中的最后一行
${NCCL_TESTS_DIR}/build/all_gather_perf \
    -b ${TEST_MIN_BYTES} \
    -e ${TEST_MAX_BYTES} \
    -f ${TEST_FACTOR} \
    -g ${TEST_GPUS_PER_PROC}
```

### Broadcast

```bash
${NCCL_TESTS_DIR}/build/broadcast_perf \
    -b ${TEST_MIN_BYTES} \
    -e ${TEST_MAX_BYTES} \
    -f ${TEST_FACTOR} \
    -g ${TEST_GPUS_PER_PROC}
```

### Reduce-Scatter

```bash
${NCCL_TESTS_DIR}/build/reduce_scatter_perf \
    -b ${TEST_MIN_BYTES} \
    -e ${TEST_MAX_BYTES} \
    -f ${TEST_FACTOR} \
    -g ${TEST_GPUS_PER_PROC}
```

## 性能优化建议

### 1. 网络优化

```bash
# 确认使用 RDMA (RoCE)
export NCCL_IB_DISABLE=0
export NCCL_IB_GID_INDEX=3

# 如果 RTX 3090 不支持 GPUDirect RDMA
export NCCL_NET_GDR_LEVEL=0
```

### 2. 通道优化

```bash
# 增加并行通道数
export NCCL_MIN_NCHANNELS=8
export NCCL_MAX_NCHANNELS=16
```

### 3. 算法选择

```bash
# 强制使用 Ring 算法
export NCCL_ALGO=Ring

# 或让 NCCL 自动选择（推荐）
# unset NCCL_ALGO
```

## 文件清单

```
run_nccl_test/
├── LOCAL_CONTAINERS_GUIDE.md      # 本文件 - 本地容器使用指南
├── README.md                      # 详细的 NCCL 配置文档
├── QUICKSTART.md                  # 快速开始指南
├── hostfile                       # MPI 主机配置文件
├── env_config.sh                  # 环境变量配置
├── run_all_reduce.sh              # 主运行脚本
├── ssh_to_local_container.sh      # 本地容器 SSH 包装脚本 (新)
├── ssh_to_container.sh            # 远程主机 SSH 包装脚本 (原版)
├── container_env_wrapper.sh       # 容器环境包装
├── gpu_binding.sh                 # GPU 绑定脚本
├── test_local_containers.sh       # 本地环境测试脚本 (新)
└── check_env.sh                   # 环境检查脚本
```

## 下一步

1. **基准测试**: 收集性能数据作为基准
2. **参数调优**: 尝试不同的 NCCL 参数组合
3. **扩展到更多容器**: 如果需要测试更大规模的通信
4. **混合精度测试**: 测试不同数据类型的性能

## 参考资料

- NCCL 环境变量: https://docs.nvidia.com/deeplearning/nccl/user-guide/docs/env.html
- NCCL Tests: https://github.com/NVIDIA/nccl-tests
- OpenMPI 文档: https://www.open-mpi.org/doc/
