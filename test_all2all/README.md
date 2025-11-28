# Uniform All-to-All Example

This folder contains a minimal script that runs
`torch.distributed.all_to_all_single` with equal traffic between every
pair of ranks. Each peer-to-peer message is 4 MiB by default so you can
stress-test a balanced all-to-all.

The script includes detailed logging with timestamps and performance measurements,
showing device initialization, tensor allocation, and all-to-all operation timing.

## Prerequisites

- PyTorch with distributed support (`pip install torch`) and CUDA if you
  plan to use GPUs.
- At least two ranks (processes) to participate in the all-to-all.

## Single-node launch

Basic usage (uses NCCL backend by default):

```bash
torchrun --standalone --nproc_per_node=2 test_all2all/imbalance_alltoall.py
```

Or with custom message size:

```bash
torchrun --standalone --nproc_per_node=2 \
  test_all2all/imbalance_alltoall.py \
  --msg-bytes=$((4 * 1024 * 1024))
```

Useful flags:

- `--msg-bytes`: bytes sent to every peer (default: 4 MiB).
- `--backend`: communication backend (`nccl`, `gloo`, `mpi`). **Default: nccl**
- `--dtype`: payload dtype (`int32`, `int64`, `float32`). Default: float32

Example with larger messages:

```bash
torchrun --standalone --nproc_per_node=2 \
  test_all2all/imbalance_alltoall.py \
  --msg-bytes=$((16 * 1024 * 1024))
```

Example using CPU (gloo backend):

```bash
torchrun --standalone --nproc_per_node=2 \
  test_all2all/imbalance_alltoall.py \
  --backend=gloo
```

## Two-node launch (1 process/node)

Run the same command on both nodes, changing only `--node_rank`. Export
`MASTER_ADDR`/`MASTER_PORT` so both processes know where to rendezvous
(`192.168.1.251:29500` in the example). Set both `NCCL_SOCKET_IFNAME`
*and* `GLOO_SOCKET_IFNAME` to the interface that can reach the other
node; otherwise Gloo (used internally by torchrun) may bind to loopback
and hang. Debug flags are optional but helpful when bringing up new
clusters.

Node 0:

```bash
export NCCL_DEBUG=INFO
export NCCL_IB_HCA=mlx5_0
export NCCL_IB_GID_INDEX=3
export NCCL_SHM_DISABLE=1
export NCCL_P2P_DISABLE=1
export MASTER_ADDR=localhost
export MASTER_PORT=12345
export CUDA_VISIBLE_DEVICES=0
TORCH_DISTRIBUTED_DEBUG=DETAIL NCCL_DEBUG=INFO NCCL_DEBUG_SUBSYS=INIT \
torchrun --nnodes=2 --nproc_per_node=1 --node_rank=0 \
  ./test_all2all/imbalance_alltoall.py \
  --msg-bytes=$((4 * 1024 * 1024))
```

Node 1:

```bash
export NCCL_DEBUG=INFO
export NCCL_IB_HCA=mlx5_0
export NCCL_IB_GID_INDEX=3 
export NCCL_SHM_DISABLE=1
export NCCL_P2P_DISABLE=1
export MASTER_ADDR=192.168.1.251
export MASTER_PORT=12345
export CUDA_VISIBLE_DEVICES=0
TORCH_DISTRIBUTED_DEBUG=DETAIL NCCL_DEBUG=INFO NCCL_DEBUG_SUBSYS=INIT \
torchrun --nnodes=2 --nproc_per_node=1 --node_rank=1 \
  ./test_all2all/imbalance_alltoall.py \
  --msg-bytes=$((4 * 1024 * 1024))
```

Need multiple NICs? Use `NCCL_SOCKET_IFNAME=rdma0,rdma1` (comma
separated) and match `GLOO_SOCKET_IFNAME` accordingly.

## Output

The script produces detailed logs including:

- **Device initialization**: Which device (CPU/CUDA) each rank is using
- **Process group setup**: Backend and world size information
- **Tensor allocation**: Size and memory usage details
- **Performance timing**: Duration of the all_to_all_single operation in milliseconds
- **Verification**: Checksum (first/last elements) to verify correct data transfer

Example output:
```
[2025-11-07 ...] Rank 0: Using CUDA device 0
[2025-11-07 ...] Rank 0/2: Process group initialized
[2025-11-07 ...] Rank 0: Creating payload tensor with 2097152 elements (8.00 MiB total, 1048576 elems/msg = 4.00 MiB/msg)
[2025-11-07 ...] Rank 0: Starting all_to_all_single operation...
[2025-11-07 ...] Rank 0: all_to_all_single completed in 2.45 ms
[2025-11-07 ...] Rank 0: Verification - output_numel=2097152 first_vals=[...] last_vals=[...]
```
