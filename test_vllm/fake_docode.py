from mooncake.store import MooncakeDistributedStore
import time
import signal
import sys
import threading

# 创建 store 实例
store = MooncakeDistributedStore()

# 连接到 master
store.setup(
    "10.2.10.200",                         # 本节点地址
    "http://10.0.10.200:8080/metadata",    # HTTP metadata server 端点
    21474836480,                           # segment size: 20GB
    0,                                     # local buffer: 0
    "rdma",                                # 协议
    "mlx5_113",                            # RDMA 设备
    "10.0.10.200:50051"                    # master 地址
)

# 打印实际的segment host:port
print("\033[1;32mdecode segment:\033[0m", store.get_hostname())  # 绿色


running = True

def signal_handler(signum, frame):
    global running
    print("\n收到退出信号，正在关闭...")
    running = False

signal.signal(signal.SIGINT, signal_handler)
signal.signal(signal.SIGTERM, signal_handler)

# 后台清理 p2d 键的线程
def cleanup_p2d_keys():
    """后台线程：持续删除匹配 p2d 的键"""
    cleanup_interval = 1.0  # 每秒清理一次
    regex_pattern = ".*p2d.*"  # 匹配所有包含 p2d 的键
    
    print(f"[清理线程] 已启动，正则表达式: {regex_pattern}, 间隔: {cleanup_interval}s")
    
    while running:
        try:
            count = store.remove_by_regex(regex_pattern)
            if count > 0:
                print(f"[清理线程] 删除了 {count} 个 p2d 键")
            elif count < 0:
                print(f"[清理线程] 删除出错，返回值: {count}")

        except Exception as e:
            print(f"[清理线程] 异常: {e}")
        
        time.sleep(cleanup_interval)
    
    print("[清理线程] 已退出")

# 启动清理线程
cleanup_thread = threading.Thread(target=cleanup_p2d_keys, daemon=True)
cleanup_thread.start()

print("Mooncake Store client 已启动，按 Ctrl+C 退出")

# dummy test
store.put("my_key", b"hello world")
data = store.get("my_key")
print(f"测试数据: {data.decode()}")

store.remove("my_key")
data = store.get("my_key")
if data:
    print(f"测试数据: {data.decode()}")
else:
    print("测试数据已删除")

# client一直挂着
while running:
    try:
        time.sleep(1)
    except InterruptedError:
        break

# 等待清理线程结束
cleanup_thread.join(timeout=2.0)

# 关闭连接
store.close()
print("已关闭连接")
