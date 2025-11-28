#!/usr/bin/env bash

# Remove containers, then remove SR-IOV Docker networks.
# Defaults match those created by create_sriov_docker.sh.

set -o errexit
set -o nounset
set -o pipefail

if ! command -v docker >/dev/null 2>&1; then
  echo "docker CLI not found in PATH" >&2
  exit 1
fi

containers_default="yijun_testbed01,yijun_testbed23"
networks_default="sn0,sn2"

containers="$containers_default"
networks="$networks_default"

usage() {
  cat <<EOF
Usage: $(basename "$0") [-c name1,name2] [-n net1,net2]

Options:
  -c, --containers  Comma-separated container names (default: $containers_default)
  -n, --networks    Comma-separated network names (default: $networks_default)
  -h, --help        Show this help

Behavior:
  - Removes listed containers first (force), ignoring missing ones.
  - Then removes the listed Docker networks, ignoring missing ones.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -c|--containers)
      containers=${2:-}
      shift 2
      ;;
    -n|--networks)
      networks=${2:-}
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
IFS=',' read -r -a network_arr <<< "$networks"

remove_container() {
  local name=$1
  if docker ps -a --format '{{.Names}}' | grep -wq "${name}"; then
    echo "Removing container: ${name}"
    docker rm -f "${name}" >/dev/null 2>&1 || docker rm -f "${name}" || true
  else
    echo "Container ${name} not found; skip"
  fi
}

remove_network() {
  local name=$1
  if docker network ls --format '{{.Name}}' | grep -wq "${name}"; then
    echo "Removing network: ${name}"
    docker network rm "${name}" >/dev/null 2>&1 || docker network rm "${name}" || true
  else
    echo "Network ${name} not found; skip"
  fi
}

echo "==> Removing containers: ${container_arr[*]}"
for c in "${container_arr[@]}"; do
  [[ -z "$c" ]] && continue
  remove_container "$c"
done

echo "==> Removing networks: ${network_arr[*]}"
for n in "${network_arr[@]}"; do
  [[ -z "$n" ]] && continue
  remove_network "$n"
done

echo "Cleanup completed."