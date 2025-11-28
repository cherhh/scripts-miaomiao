# Mooncake Transfer Engine Benchmark 脚本

这些脚本用于在两个容器（yijun_testbed01 和 yijun_testbed23）中运行 Mooncake Transfer Engine 的性能测试。

## 文件说明

- **env_config.sh**: 环境配置文件，包含所有测试参数
- **run_target_in_container.sh**: 在容器内运行的 target 脚本（数据提供方）
- **run_initiator_in_container.sh**: 在容器内运行的 initiator 脚本（数据请求方）
- **run_transfer_bench.sh**: 从宿主机启动单向测试的主脚本（testbed01 -> testbed23）
- **run_bidirectional_bench.sh**: 从宿主机启动双向测试的主脚本（测试两个方向）
- **start_metadata_server.sh**: 启动 HTTP Metadata Server（在宿主机运行）
- **stop_metadata_server.sh**: 停止 Metadata Server
- **start_etcd.sh**: 启动 etcd 服务器（备选方案）
- **stop_etcd.sh**: 停止 etcd 服务

## 前置条件

1. **容器运行**: 确保 yijun_testbed01 和 yijun_testbed23 容器正在运行
2. **Mooncake 编译**: 确保 Mooncake transfer engine 已编译完成
   - 可执行文件路径: `/usr/wkspace/docker/testbed/Mooncake/build/mooncake-transfer-engine/example/transfer_engine_bench`
3. **元数据服务**:
   - **推荐**: 使用 HTTP Metadata Server（需要先启动）
   - **备选**: 使用自动发现 (`AUTO_DISCOVERY=true`)，不需要metadata server但可能不稳定

## 快速开始

### 1. 启动 Metadata Server（在宿主机）

```bash
cd /home/yijun/docker/testbed/script/run_mooncake_transfer_engine
./start_metadata_server.sh
```

这会在宿主机的 `10.0.11.1:8080` 启动 HTTP Metadata Server。

### 2. 单向测试（testbed01 -> testbed23）

```bash
./run_transfer_bench.sh
```

默认参数:
- **Metadata Server**: http://10.0.11.1:8080/metadata
- 操作类型: read
- 传输协议: rdma
- 缓冲区大小: 1GB
- 批次大小: 128
- 块大小: 64KB
- 持续时间: 10秒
- 工作线程: 12

### 3. 双向测试（推荐）

测试两个方向的传输性能：

```bash
./run_bidirectional_bench.sh
```

这个脚本会：
1. 检查 Metadata Server 是否运行
2. 在两个容器中同时启动 target 服务器
3. 测试方向1: testbed01 -> testbed23
4. 测试方向2: testbed23 -> testbed01
5. 汇总两个方向的测试结果

### 4. 自定义参数测试

可以通过环境变量覆盖默认配置:

```bash
# 测试写操作，持续30秒
OPERATION=write DURATION=30 ./run_bidirectional_bench.sh

# 使用TCP协议而不是RDMA
PROTOCOL=tcp ./run_bidirectional_bench.sh

# 使用更大的块和批次大小
BLOCK_SIZE=1048576 BATCH_SIZE=256 ./run_bidirectional_bench.sh

# 使用GPU内存
USE_VRAM=true GPU_ID=0 ./run_bidirectional_bench.sh
```

### 5. 使用自动发现模式（不推荐，可能不稳定）

如果不想使用 Metadata Server：

```bash
AUTO_DISCOVERY=true ./run_bidirectional_bench.sh
```

### 6. 在容器内直接运行

如果需要手动控制，可以分别在容器内运行：

```bash
# 在 testbed23 容器中启动 target
docker exec -it yijun_testbed23 bash
cd /usr/wkspace/docker/testbed/script/run_mooncake_transfer_engine
./run_target_in_container.sh

# 在另一个终端，在 testbed01 容器中启动 initiator
docker exec -it yijun_testbed01 bash
cd /usr/wkspace/docker/testbed/script/run_mooncake_transfer_engine
./run_initiator_in_container.sh
```

## 单向测试 vs 双向测试

### 单向测试 (run_transfer_bench.sh)
- 仅测试一个方向：testbed01 作为 initiator 访问 testbed23 的数据
- 适合快速验证连接和基本性能
- testbed23 运行 target，testbed01 运行 initiator

### 双向测试 (run_bidirectional_bench.sh)
- 测试两个方向的传输性能
- 更全面地评估网络性能（可能两个方向性能不对称）
- 两个容器都运行 target 和 initiator（分两个阶段）
- **推荐用于完整的性能测试**

## 配置参数说明

### 网络配置

- `NETWORK_IFNAME`: 网络接口名称（默认: eno0）
- `AUTO_DISCOVERY`: 是否启用自动发现（默认: false，推荐使用Metadata Server）
- `METADATA_SERVER`: Metadata Server地址（默认: http://10.0.11.1:8080/metadata）

### RDMA 设备

脚本会自动根据容器选择正确的 RDMA 设备：
- testbed01 (10.0.11.200): mlx5_49
- testbed23 (10.2.11.200): mlx5_113

### 测试参数

- `OPERATION`: 操作类型，read 或 write（默认: read）
- `PROTOCOL`: 传输协议，rdma、tcp 或 nvlink（默认: rdma）
- `BUFFER_SIZE`: 缓冲区大小，单位字节（默认: 1073741824 = 1GB）
- `BATCH_SIZE`: 批次大小（默认: 128）
- `BLOCK_SIZE`: 每次传输的块大小，单位字节（默认: 65536 = 64KB）
- `DURATION`: 测试持续时间，单位秒（默认: 10）
- `THREADS`: 工作线程数（默认: 12）

### GPU 配置

- `USE_VRAM`: 是否使用 GPU 显存（默认: false）
- `GPU_ID`: GPU ID，-1 表示使用所有 GPU（默认: 0）

### 报告配置

- `REPORT_UNIT`: 报告单位，GB|GiB|Gb|MB|MiB|Mb|KB|KiB|Kb（默认: GB）
- `REPORT_PRECISION`: 报告精度（默认: 2）

## 日志文件

测试日志保存在 `logs/` 目录下，文件名包含时间戳：
- `target_YYYYMMDD_HHMMSS.log`: Target 服务器日志
- `initiator_YYYYMMDD_HHMMSS.log`: Initiator 客户端日志

## 故障排查

### 1. Metadata Server 连接失败

确保 Metadata Server 正在运行：

```bash
# 检查服务状态
ps aux | grep http_metadata_server

# 测试访问
curl http://10.0.11.1:8080/metadata

# 如果没有运行，启动它
./start_metadata_server.sh

# 查看日志
tail -f logs/metadata_server.log
```

### 2. 容器无法访问 Metadata Server

容器通过 `10.0.11.1` 访问宿主机：

```bash
# 在容器内测试
docker exec yijun_testbed01 curl http://10.0.11.1:8080/metadata

# 应该返回 404（正常，因为没有数据）或200
```

如果无法访问，检查防火墙：

```bash
# 允许容器访问8080端口
sudo iptables -I INPUT -p tcp --dport 8080 -j ACCEPT
```

### 3. RDMA 设备不可用

检查 RDMA 设备是否可用：

```bash
docker exec yijun_testbed01 ibv_devices
docker exec yijun_testbed23 ibv_devices
```

### 4. 容器间网络不通

测试容器间的网络连接：

```bash
docker exec yijun_testbed01 ping -c 3 10.2.11.200
docker exec yijun_testbed23 ping -c 3 10.0.11.200
```

### 5. 查看详细日志

如果测试失败，查看日志文件以获取详细信息：

```bash
# 查看最新的日志
ls -lt logs/
cat logs/target_*.log
cat logs/initiator_*.log
```

## 性能调优建议

1. **块大小**: 对于大文件传输，增加 BLOCK_SIZE 可以提高吞吐量
2. **批次大小**: 增加 BATCH_SIZE 可以提高并发度
3. **线程数**: 根据 CPU 核心数调整 THREADS
4. **GPU 内存**: 如果有 GPU，使用 VRAM 可以测试 GPU Direct RDMA（如果硬件支持）

## 示例测试场景

### 完整流程（从头开始）

```bash
cd /home/yijun/docker/testbed/script/run_mooncake_transfer_engine

# 1. 启动 Metadata Server
./start_metadata_server.sh

# 2. 运行双向测试
./run_bidirectional_bench.sh

# 3. 测试完成后停止 Metadata Server（可选）
./stop_metadata_server.sh
```

### 高吞吐量测试（双向）
```bash
BLOCK_SIZE=1048576 BATCH_SIZE=256 THREADS=16 DURATION=30 ./run_bidirectional_bench.sh
```

### 低延迟测试（双向）
```bash
BLOCK_SIZE=4096 BATCH_SIZE=32 THREADS=4 DURATION=20 ./run_bidirectional_bench.sh
```

### GPU 显存测试（双向）
```bash
USE_VRAM=true GPU_ID=0 DURATION=15 ./run_bidirectional_bench.sh
```

### TCP 协议对比测试（双向）
```bash
PROTOCOL=tcp DURATION=20 ./run_bidirectional_bench.sh
```

### 单向测试（快速验证）
```bash
./run_transfer_bench.sh
```

### 使用自动发现（不需要Metadata Server）
```bash
AUTO_DISCOVERY=true ./run_bidirectional_bench.sh
```
