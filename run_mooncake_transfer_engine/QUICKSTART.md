# Mooncake Transfer Engine 快速开始指南

## 🚀 最简单的运行方式（3步完成）

```bash
# 进入脚本目录
cd /home/yijun/docker/testbed/script/run_mooncake_transfer_engine

# 步骤1: 启动 HTTP Metadata Server（在宿主机运行）
./start_metadata_server.sh

# 步骤2: 运行双向测试
./run_bidirectional_bench.sh

# 完成！查看测试结果
```

## 📊 你会看到什么

### 步骤1输出：启动 Metadata Server
```
==========================================
启动 HTTP Metadata Server
==========================================

配置:
  监听地址: 0.0.0.0:8080
  日志文件: logs/metadata_server.log
  访问URL: http://10.0.11.1:8080/metadata

>>> 启动 Metadata Server...
等待服务启动...
✓ Metadata Server 启动成功 (PID: 12345)

>>> 测试服务...
✓ 服务响应正常

Metadata Server URL: http://10.0.11.1:8080/metadata

停止服务: ./stop_metadata_server.sh
查看日志: tail -f logs/metadata_server.log
```

### 步骤2输出：运行测试
```
==========================================
Mooncake Transfer Engine 双向 Benchmark
==========================================

>>> 检查容器状态...
✓ 容器 yijun_testbed01 运行中
✓ 容器 yijun_testbed23 运行中

>>> 检查 transfer_engine_bench 可执行文件...
✓ 可执行文件检查通过

>>> 检查 Metadata Server...
✓ Metadata Server 可访问 (http://10.0.11.1:8080/metadata)

==========================================
>>> 阶段 1: 启动两个 Target 服务器
==========================================

在 yijun_testbed01 启动 target...
在 yijun_testbed23 启动 target...
两个 target 服务器已启动
等待 8 秒让 target 完成初始化和注册...

==========================================
>>> 阶段 2: 方向1测试 (yijun_testbed01 -> yijun_testbed23)
==========================================

[实时测试输出...]
Test completed: duration 10.00, batch count 15234, throughput 12.34 GB/s

✓ 方向1测试完成

==========================================
>>> 阶段 3: 方向2测试 (yijun_testbed23 -> yijun_testbed01)
==========================================

[实时测试输出...]
Test completed: duration 10.00, batch count 15189, throughput 12.30 GB/s

✓ 方向2测试完成

==========================================
测试结果汇总
==========================================

✓ 双向测试全部成功

方向1 (yijun_testbed01 -> yijun_testbed23):
  throughput 12.34 GB/s

方向2 (yijun_testbed23 -> yijun_testbed01):
  throughput 12.30 GB/s
```

## 🎯 常用测试场景

### 基础测试（默认参数）
```bash
./run_bidirectional_bench.sh
```

### 高吞吐量测试（大块、高并发、长时间）
```bash
BLOCK_SIZE=1048576 BATCH_SIZE=256 THREADS=16 DURATION=30 ./run_bidirectional_bench.sh
```

### 低延迟测试（小块、低并发）
```bash
BLOCK_SIZE=4096 BATCH_SIZE=32 THREADS=4 DURATION=20 ./run_bidirectional_bench.sh
```

### GPU显存测试
```bash
USE_VRAM=true GPU_ID=0 ./run_bidirectional_bench.sh
```

### TCP协议测试（对比RDMA）
```bash
PROTOCOL=tcp ./run_bidirectional_bench.sh
```

## 🛠️ 调整参数

你可以通过环境变量调整任何参数：

```bash
# 示例：写操作、更大块、更长时间
OPERATION=write BLOCK_SIZE=2097152 DURATION=60 ./run_bidirectional_bench.sh
```

可用参数（见 `env_config.sh`）：
- `OPERATION`: read/write（默认read）
- `PROTOCOL`: rdma/tcp/nvlink（默认rdma）
- `BUFFER_SIZE`: 缓冲区大小（默认1GB）
- `BATCH_SIZE`: 批次大小（默认128）
- `BLOCK_SIZE`: 块大小（默认64KB）
- `DURATION`: 测试时长秒数（默认10）
- `THREADS`: 工作线程数（默认12）
- `USE_VRAM`: true/false（默认false）
- `GPU_ID`: GPU编号（默认0）

## 🧹 清理

### 停止 Metadata Server
```bash
./stop_metadata_server.sh
```

### 清理日志（可选）
```bash
rm -rf logs/*
```

## ❓ 常见问题

### Q: 测试失败了怎么办？
```bash
# 1. 检查 Metadata Server 是否运行
ps aux | grep http_metadata_server

# 2. 查看日志
tail -f logs/metadata_server.log
cat logs/target_*.log
cat logs/initiator_*.log

# 3. 重启 Metadata Server
./stop_metadata_server.sh
./start_metadata_server.sh
```

### Q: 容器无法连接 Metadata Server？
```bash
# 测试从容器访问宿主机
docker exec yijun_testbed01 curl http://10.0.11.1:8080/metadata

# 如果失败，可能是防火墙问题
sudo iptables -I INPUT -p tcp --dport 8080 -j ACCEPT
```

### Q: 想要单向测试（更快）？
```bash
./run_transfer_bench.sh  # 只测试 testbed01 -> testbed23
```

### Q: 不想用 Metadata Server？
```bash
# 使用自动发现模式（可能不稳定）
AUTO_DISCOVERY=true ./run_bidirectional_bench.sh
```

## 📝 更多信息

详细文档请查看 [README.md](README.md)

## 🎓 工作原理

```
宿主机 (10.0.11.1)
  └─ HTTP Metadata Server :8080
       ↓ (注册/发现)
       ↓
容器1: testbed01 (10.0.11.200)        容器2: testbed23 (10.2.11.200)
  ├─ Target Server (提供数据)    ←─ RDMA ─→  ├─ Target Server (提供数据)
  └─ Initiator (请求数据)                    └─ Initiator (请求数据)
       ↑                                            ↑
       └──────────── RDMA 网络传输 ─────────────────┘
              mlx5_49 ←───────→ mlx5_113
```

双向测试流程：
1. 两个容器都启动 Target（注册到Metadata Server）
2. 方向1：testbed01作为Initiator访问testbed23的Target
3. 方向2：testbed23作为Initiator访问testbed01的Target
4. 对比两个方向的性能
