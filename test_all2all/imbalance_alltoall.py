#!/usr/bin/env python3
"""
Toy example that runs torch.distributed.all_to_all_single where every rank sends
and receives the same amount of data. Each peer-to-peer message is 4 MiB (by
default) so you can stress-test uniform all-to-all behavior.

Launch:
    torchrun --standalone --nproc_per_node=2 test_all2all/imbalance_alltoall.py
"""

import argparse
import os
import time
from datetime import datetime

import torch
import torch.distributed as dist

MI_B = 1024 * 1024


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser("Uniform all_to_all_single demo.")
    parser.add_argument(
        "--backend",
        default="nccl",
        choices=["nccl", "gloo", "mpi"],
    )
    parser.add_argument(
        "--msg-bytes",
        type=int,
        default=4 * MI_B,
        help="Payload size per peer in bytes (default 4 MiB).",
    )
    parser.add_argument(
        "--dtype",
        default="float32",
        choices=["int32", "int64", "float32"],
    )
    return parser.parse_args()


def get_device(backend: str) -> torch.device:
    if backend != "nccl" or not torch.cuda.is_available():
        print(f"[{datetime.now()}] Using CPU device (backend={backend}, cuda_available={torch.cuda.is_available()})")
        return torch.device("cpu")
    local_rank = int(os.environ.get("LOCAL_RANK", 0))
    torch.cuda.set_device(local_rank)
    device = torch.device("cuda", local_rank)
    print(f"[{datetime.now()}] Rank {local_rank}: Using CUDA device {local_rank}")
    return device


def main() -> None:
    args = parse_args()
    device = get_device(args.backend)

    print(f"[{datetime.now()}] Initializing process group with backend={args.backend}")
    dist.init_process_group(backend=args.backend, init_method='env://')
    rank = dist.get_rank()
    world_size = dist.get_world_size()
    print(f"[{datetime.now()}] Rank {rank}/{world_size}: Process group initialized")

    dtype_map = {
        "int32": torch.int32,
        "int64": torch.int64,
        "float32": torch.float32,
    }
    payload_dtype = dtype_map[args.dtype]
    element_size = torch.tensor([], dtype=payload_dtype).element_size()
    if args.msg_bytes % element_size != 0:
        raise ValueError(
            f"msg_bytes ({args.msg_bytes}) must be divisible by dtype size ({element_size})."
        )

    elems_per_msg = args.msg_bytes // element_size
    total_elems = elems_per_msg * world_size

    print(f"[{datetime.now()}] Rank {rank}: Creating payload tensor with {total_elems} elements "
          f"({total_elems * element_size / MI_B:.2f} MiB total, "
          f"{elems_per_msg} elems/msg = {args.msg_bytes / MI_B:.2f} MiB/msg)")

    payload = (
        torch.arange(
            rank * total_elems,
            rank * total_elems + total_elems,
            dtype=payload_dtype,
            device=device,
        )
        .contiguous()
    )

    output = torch.empty_like(payload)
    print(f"[{datetime.now()}] Rank {rank}: Payload and output tensors allocated on {device}")

    dist.barrier()
    if rank == 0:
        print(
            f"\n[{datetime.now()}] === Uniform all_to_all_single ===\n"
            f"world_size={world_size}, msg_bytes_per_peer={args.msg_bytes}, "
            f"dtype={args.dtype}, elems_per_msg={elems_per_msg}, backend={args.backend}, device={device}"
        )
    dist.barrier()

    print(f"[{datetime.now()}] Rank {rank}: Starting all_to_all_single operation...")
    start_time = time.time()

    dist.all_to_all_single(output, payload)

    if device.type == "cuda":
        torch.cuda.synchronize()

    end_time = time.time()
    elapsed_ms = (end_time - start_time) * 1000

    print(f"[{datetime.now()}] Rank {rank}: all_to_all_single completed in {elapsed_ms:.2f} ms")

    dist.barrier()
    # Print short checksum to avoid huge dumps.
    print(
        f"[{datetime.now()}] Rank {rank}: Verification - output_numel={output.numel()} "
        f"first_vals={output[:4].tolist()} last_vals={output[-4:].tolist()}"
    )
    dist.barrier()

    if rank == 0:
        print(f"[{datetime.now()}] ================================")

    print(f"[{datetime.now()}] Rank {rank}: Destroying process group")
    dist.destroy_process_group()


if __name__ == "__main__":
    main()
