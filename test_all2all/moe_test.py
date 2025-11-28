#!/usr/bin/env python3
"""Two-GPU MoE all_to_all_single micro-benchmark."""

import argparse
import os
import time
from datetime import datetime

import torch
import torch.distributed as dist

MI_B = 1024 * 1024


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        "Minimal MoE all_to_all_single test (2 GPUs / world size = 2)."
    )
    parser.add_argument(
        "--msg-bytes",
        type=int,
        default=4 * MI_B,
        help="Payload size sent to each peer (default: 4 MiB).",
    )
    parser.add_argument(
        "--dtype",
        default="float32",
        choices=["float32", "int32", "int64"],
        help="Tensor dtype used for the payload.",
    )
    parser.add_argument(
        "--iters",
        type=int,
        default=5,
        help="Number of all_to_all_single iterations to run.",
    )
    return parser.parse_args()


def get_device() -> torch.device:
    local_rank = int(os.environ.get("LOCAL_RANK", 0))
    if torch.cuda.is_available():
        torch.cuda.set_device(local_rank)
        device = torch.device("cuda", local_rank)
        print(f"[{datetime.now()}] Rank {local_rank}: Using CUDA device {local_rank}")
        return device
    device = torch.device("cpu")
    print(f"[{datetime.now()}] CUDA unavailable, falling back to CPU")
    return device


def main() -> None:
    args = parse_args()
    dtype_map = {
        "float32": torch.float32,
        "int32": torch.int32,
        "int64": torch.int64,
    }
    payload_dtype = dtype_map[args.dtype]

    device = get_device()

    print(f"[{datetime.now()}] Initializing process group (backend=nccl)")
    dist.init_process_group(backend="nccl", init_method="env://")
    world_size = dist.get_world_size()
    rank = dist.get_rank()

    if world_size != 2:
        raise ValueError(f"This script expects world_size=2, but got {world_size}.")

    element_size = torch.tensor([], dtype=payload_dtype).element_size()
    if args.msg_bytes % element_size != 0:
        raise ValueError(
            f"msg_bytes ({args.msg_bytes}) must be divisible by dtype size ({element_size})."
        )

    elems_per_peer = args.msg_bytes // element_size
    total_elems = elems_per_peer * world_size

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

    print(
        f"[{datetime.now()}] Rank {rank}: world_size={world_size}, msg_bytes_per_peer={args.msg_bytes}, "
        f"dtype={args.dtype}, total_elems={total_elems}, elems_per_peer={elems_per_peer}"
    )

    # Warmup barrier to make sure both ranks are ready.
    dist.barrier()

    for iteration in range(1, args.iters + 1):
        dist.barrier()
        start = time.time()
        dist.all_to_all_single(output, payload)
        if device.type == "cuda":
            torch.cuda.synchronize()
        end = time.time()
        elapsed_ms = (end - start) * 1000

        print(
            f"[{datetime.now()}] Rank {rank}: iteration {iteration}/{args.iters} "
            f"all_to_all_single took {elapsed_ms:.2f} ms"
        )
        dist.barrier()
        print(
            f"[{datetime.now()}] Rank {rank}: checksum first_vals={output[:4].tolist()} "
            f"last_vals={output[-4:].tolist()}"
        )

    dist.barrier()
    print(f"[{datetime.now()}] Rank {rank}: Completed all iterations, destroying process group.")
    dist.destroy_process_group()


if __name__ == "__main__":
    main()
