#!/bin/bash

# Start SR-IOV testbed containers by reusing pre-created Docker networks.
# Run create_sriov_docker.sh once to set up the SR-IOV networks, then use this
# script for fast container recreation without touching the networks.

set -o errexit
set -o nounset
set -o pipefail

IF_PREFIX="eno"

if ! command -v docker >/dev/null 2>&1; then
	echo "docker CLI not found in PATH" >&2
	exit 1
fi

if [ "$UID" -ne 0 ]; then
	echo "please execute this script as root" >&2
	exit 1
fi

# IMAGE=xudongliao/herald:v2
# IMAGE=xudongliao/herald:v0
IMAGE=sunhehe/servingtestbed-vllm:v0
# IMAGE=xudongliao/herald:v1
# DIR_MAPPING collects all host<->container volume mappings
DIR_MAPPING=" --volume /home/yijun/:/usr/wkspace --volume /mnt/nfs/yijun:/usr/data"
# Optional: set platform to match host image arch, e.g. linux/amd64 or linux/arm64
# Leave empty to let Docker choose default
PLATFORM_OPT=""

ensure_network_exists() {
	local name=$1
	if ! docker network ls --format '{{.Name}}' | grep -wq "$name"; then
		echo "network $name not found; please run create_sriov_docker.sh first" >&2
		exit 1
	fi
}

ensure_container_absent() {
	local name=$1
	if docker ps -a --format '{{.Names}}' | grep -wq "$name"; then
		echo "container $name already exists; run cleanup first if you need to recreate it" >&2
		exit 1
	fi
}

create_container() {
	local DEV=$1
	local NET_NAME=$2
	local CONTAINER_NAME=$3
	local GPU_ID=$4
	local POST_FIX=$5

	create_gateway_route "$DEV" "$NET_NAME" "$CONTAINER_NAME" "$GPU_ID" "$POST_FIX"
}

create_gateway_route() {
	local DEV=$1
	local NET_NAME=$2
	local CONTAINER_NAME=$3
	local GPU_ID=$4
	local POST_FIX=$5

	local GW
	GW=$(ip r | grep "$DEV" | grep via | awk '{print $3}' | head -n1)
	if [[ -z "$GW" ]]; then
		echo "failed to find gateway via $DEV" >&2
		exit 1
	fi

	local IP_PREFIX
	IP_PREFIX=$(echo "$GW" | awk 'BEGIN{FS="."}{print $1 "." $2 "." $3}')
	local IP="${IP_PREFIX}.${POST_FIX}"
	local HOST=$(echo "$GW" | awk 'BEGIN{FS="."}{print $1 "-" $2 "-" $3}')
	HOST="${HOST}-${POST_FIX}"

	echo "container: $CONTAINER_NAME, IP: $IP, network: $NET_NAME"

	docker run -d --name="$CONTAINER_NAME" $DIR_MAPPING --hostname="$HOST" \
		--network="$NET_NAME" --ip="$IP" --runtime=nvidia \
		-e NVIDIA_VISIBLE_DEVICES="$GPU_ID" --ulimit memlock=-1 --shm-size=65536m \
		--cap-add=IPC_LOCK --cap-add=SYS_NICE --cap-add=NET_ADMIN --cap-add=SYS_PTRACE --device=/dev/infiniband \
		$PLATFORM_OPT --entrypoint sleep "$IMAGE" infinity

	if [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME")" = "true" ]; then
		local pid
		pid=$(docker inspect -f '{{.State.Pid}}' "$CONTAINER_NAME")
		if [ -n "$pid" ] && [ "$pid" -gt 0 ] 2>/dev/null; then
			nsenter -t "$pid" -n ip route add 10.0.0.0/8 dev "${IF_PREFIX}0" via "$GW" || true
			nsenter -t "$pid" -n ip link set "${IF_PREFIX}0" mtu 1500 || true
		fi
		docker network connect bridge "$CONTAINER_NAME" || true
		docker exec -it "$CONTAINER_NAME" ip addr
		docker exec -it "$CONTAINER_NAME" ip route
	else
		echo "container $CONTAINER_NAME is not running; showing last logs:" >&2
		docker logs --tail=200 "$CONTAINER_NAME" || true
	fi
}

# Each line: DEV NET_NAME CONTAINER_NAME GPU_ID POSTFIX
CONFIGS=(
	"rdma0 sn0 yijun_testbed01 0,1 200"
	"rdma2 sn2 yijun_testbed23 2,3 200"
)

for cfg in "${CONFIGS[@]}"; do
	read -r DEV NET_NAME CONTAINER_NAME GPU_ID POST_FIX <<< "$cfg"
	ensure_network_exists "$NET_NAME"
	ensure_container_absent "$CONTAINER_NAME"
	create_container "$DEV" "$NET_NAME" "$CONTAINER_NAME" "$GPU_ID" "$POST_FIX"
done

echo "Containers started using existing SR-IOV networks."
