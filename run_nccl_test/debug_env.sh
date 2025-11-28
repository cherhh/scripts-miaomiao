#!/bin/bash
# 环境变量传递诊断脚本

echo "=========================================="
echo "环境变量诊断 - Rank $OMPI_COMM_WORLD_RANK"
echo "=========================================="
echo "主机名: $(hostname)"
echo ""
echo "NCCL 关键环境变量："
echo "  NCCL_NET_GDR_LEVEL = '${NCCL_NET_GDR_LEVEL}'"
echo "  NCCL_IB_HCA = '${NCCL_IB_HCA}'"
echo "  NCCL_IB_GID_INDEX = '${NCCL_IB_GID_INDEX}'"
echo "  NCCL_IB_DISABLE = '${NCCL_IB_DISABLE}'"
echo "  NCCL_DEBUG = '${NCCL_DEBUG}'"
echo ""
echo "MPI 环境变量："
echo "  OMPI_COMM_WORLD_RANK = '${OMPI_COMM_WORLD_RANK}'"
echo "  OMPI_COMM_WORLD_LOCAL_RANK = '${OMPI_COMM_WORLD_LOCAL_RANK}'"
echo ""
echo "所有 NCCL_ 开头的环境变量："
env | grep '^NCCL_' | sort
echo ""
echo "=========================================="
