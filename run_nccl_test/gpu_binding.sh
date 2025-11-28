#!/bin/bash
# GPU 绑定脚本
# 根据 MPI rank 自动分配 GPU 到进程
#
# 使用方式:
# mpirun -np 8 -N 4 ./gpu_binding.sh ./build/all_reduce_perf -b 8 -e 8G -f 2 -g 1

# 获取本地 rank (同一节点内的进程编号)
# OpenMPI 使用 OMPI_COMM_WORLD_LOCAL_RANK
# MPICH 使用 MPI_LOCALRANKID

if [ -n "$OMPI_COMM_WORLD_LOCAL_RANK" ]; then
    LOCAL_RANK=$OMPI_COMM_WORLD_LOCAL_RANK
elif [ -n "$MPI_LOCALRANKID" ]; then
    LOCAL_RANK=$MPI_LOCALRANKID
else
    echo "错误: 无法检测到 MPI local rank"
    exit 1
fi

# 每个节点有 4 块 GPU，每节点运行 4 个进程
# 策略: 每个进程独占一块 GPU (1:1 映射)
# Local rank 0 -> GPU 0
# Local rank 1 -> GPU 1
# Local rank 2 -> GPU 2
# Local rank 3 -> GPU 3

# 不限制 CUDA_VISIBLE_DEVICES，让所有进程都能看到所有 GPU
# nccl-tests 会根据 MPI rank 自动选择使用哪个 GPU
# 这里只设置所有 GPU 可见（如果未设置的话）
if [ -z "$CUDA_VISIBLE_DEVICES" ]; then
    export CUDA_VISIBLE_DEVICES=0,1,2,3
fi

# 打印绑定信息 (调试用)
echo "MPI Rank $OMPI_COMM_WORLD_RANK (Local Rank $LOCAL_RANK) on $(hostname)"
echo "  CUDA_VISIBLE_DEVICES=$CUDA_VISIBLE_DEVICES"
echo "  nccl-tests 将根据 rank 自动选择 GPU"

# 执行实际的测试程序
exec "$@"
