#!/usr/bin/env bash

# Remove the SR-IOV testbed containers without touching the Docker networks.
# Defaults match the containers from create_sriov_docker.sh.

set -o errexit
set -o nounset
set -o pipefail

if ! command -v docker >/dev/null 2>&1; then
  echo "docker CLI not found in PATH" >&2
  exit 1
fi

containers_default="yijun_testbed01,yijun_testbed23"
containers="$containers_default"

usage() {
  cat <<EOF
Usage: $(basename "$0") [-c name1,name2]

Options:
  -c, --containers  Comma-separated container names (default: $containers_default)
  -h, --help        Show this help

Behavior:
  - Removes the listed containers (force), ignoring missing ones.
  - Docker networks are left intact so they can be reused.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -c|--containers)
      containers=${2:-}
      shift 2
      ;;
    -h|--help)
      usage; exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage; exit 1
      ;;
  esac
done

IFS=',' read -r -a container_arr <<< "$containers"

remove_container() {
  local name=$1
  if docker ps -a --format '{{.Names}}' | grep -wq "${name}"; then
    echo "Removing container: ${name}"
    docker rm -f "${name}" >/dev/null 2>&1 || docker rm -f "${name}" || true
  else
    echo "Container ${name} not found; skip"
  fi
}

echo "==> Removing containers: ${container_arr[*]}"
for c in "${container_arr[@]}"; do
  [[ -z "$c" ]] && continue
  remove_container "$c"
done

echo "Containers removed. Docker networks left untouched for reuse."
