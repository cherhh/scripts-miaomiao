#!/usr/bin/env python3
"""
Modified version that uses env:// initialization for better control over TCPStore binding.
"""

import argparse
import os

import torch
import torch.distributed as dist

MI_B = 1024 * 1024


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser("Uniform all_to_all_single demo.")
    parser.add_argument(
        "--backend",
        default="nccl" if torch.cuda.is_available() else "gloo",
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
        return torch.device("cpu")
    local_rank = int(os.environ.get("LOCAL_RANK", 0))
    torch.cuda.set_device(local_rank)
    return torch.device("cuda", local_rank)


def main() -> None:
    args = parse_args()
    device = get_device(args.backend)

    # Print environment variables for debugging
    rank = int(os.environ.get("RANK", 0))
    world_size = int(os.environ.get("WORLD_SIZE", 1))
    master_addr = os.environ.get("MASTER_ADDR", "localhost")
    master_port = os.environ.get("MASTER_PORT", "29500")

    print(f"[Rank {rank}] Initializing with MASTER_ADDR={master_addr}, MASTER_PORT={master_port}, WORLD_SIZE={world_size}")

    dist.init_process_group(args.backend, init_method='env://')

    print(f"[Rank {rank}] Successfully initialized process group")

    rank = dist.get_rank()
    world_size = dist.get_world_size()

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

    dist.barrier()
    if rank == 0:
        print(
            "=== Uniform all_to_all_single ===\n"
            f"world_size={world_size}, msg_bytes_per_peer={args.msg_bytes}, "
            f"dtype={args.dtype}, elems_per_msg={elems_per_msg}"
        )
    dist.barrier()

    print(f"[Rank {rank}] Starting all_to_all_single...")
    dist.all_to_all_single(output, payload)

    dist.barrier()
    # Print short checksum to avoid huge dumps.
    print(
        f"Rank {rank}: output_numel={output.numel()} "
        f"first_vals={output[:4].tolist()} last_vals={output[-4:].tolist()}"
    )
    dist.barrier()

    if rank == 0:
        print("================================")
    dist.destroy_process_group()


if __name__ == "__main__":
    main()
