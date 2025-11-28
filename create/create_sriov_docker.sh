#!/bin/bash

#set -eu -o pipefail
IF_PREFIX="eno"

if [ $UID -ne 0 ]; then
	echo "please execute this script as root"; exit 1
fi

function create_docker_network() {
	DEV=$1
	NAME=$2

	docker network ls | grep $NAME >/dev/null 2>&1
	if [ $? -eq 0 ]; then
		echo $NAME network has been created
		return 0
	fi

	echo "This may take several seconds, please wait..."

    # Use connected route to get the network prefix (e.g., 10.0.11.0/24)
    SUBNET=$(ip r | awk -v dev="$DEV" '$3==dev && $1 ~ "/" {print $1; exit}')
    # Fallback: derive from address if route not found (rare)
    if [ -z "$SUBNET" ]; then
        CIDR=$(ip -o -f inet addr show "$DEV" | awk '{print $4}' | head -n1)
        # If ipcalc exists, use it to normalize network address
        if command -v ipcalc >/dev/null 2>&1; then
            SUBNET=$(ipcalc -n "$CIDR" | awk -F= '/Network/ {print $2}')
        else
            # Best-effort fallback: keep CIDR (may be host IP/prefix; docker may reject)
            SUBNET=$CIDR
        fi
    fi
    GW=$(ip r | grep "$DEV" | grep -m1 ' via ' | awk '{print $3}')

	echo $DEV, $NAME, $SUBNET, $GW

    docker network create -d sriov --subnet=$SUBNET -o netdevice=$DEV -o prefix=$IF_PREFIX $NAME
    if [ $? -ne 0 ]; then
        echo "failed to create docker network $NAME on $DEV with subnet $SUBNET" >&2
        return 1
    fi
	num_vfs=$(cat /sys/class/net/$DEV/device/sriov_numvfs)
	if [ "$num_vfs" -eq 0 ]; then
		total_vfs=$(cat /sys/class/net/$DEV/device/sriov_totalvfs 2>/dev/null || echo 0)
		desired_vfs=4
		if [ "$total_vfs" -gt 0 ] && [ "$desired_vfs" -gt "$total_vfs" ]; then
			desired_vfs=$total_vfs
		fi
		echo $desired_vfs > /sys/class/net/$DEV/device/sriov_numvfs
		num_vfs=$desired_vfs
		echo "Enabled $num_vfs VFs on $DEV"
	fi
	for ((i = 0; i < $num_vfs; i++)); do
		# set speed to 100Gbps
		ip link set $DEV vf $i trust on
		ip link set $DEV vf $i max_tx_rate 100000 min_tx_rate 100000
	done
}

# Base image for the SR-IOV testbed containers
IMAGE=cher03/testbed-sp:cuda12.8-torch2.9-dev1
# DIR_MAPPING collects all host<->container volume mappings
DIR_MAPPING=" --volume /home/chenhao/:/usr/wkspace --volume /mnt/nfs/chenhao:/usr/data"
SSH_PORT=22
# Optional: set platform to match host image arch, e.g. linux/amd64 or linux/arm64
# Leave empty to let Docker choose default
PLATFORM_OPT=""
# default start command; auto-switch to sshd if available in image
START_CMD="sleep infinity"

function create_container() {
	DEV=$1
	NET_NAME=$2
	CONTAINER_NAME=$3
	GPU_ID=$4
	POST_FIX=$5
	GW=$(ip r | grep $DEV | grep via | awk '{print $3}')
	IP=$(echo $GW | awk 'BEGIN{FS="."}{print $1 "." $2 "." $3}')
	IP="$IP.$POST_FIX"
	HOST=$(echo $GW | awk 'BEGIN{FS="."}{print $1 "-" $2 "-" $3}')
	HOST="$HOST-$POST_FIX"

	echo "container: $CONTAINER_NAME, IP: $IP"

    # Run container with keep-alive: --entrypoint sleep ... infinity
    docker run -d --name=$CONTAINER_NAME $DIR_MAPPING --hostname=$HOST --network=$NET_NAME --ip=$IP --runtime=nvidia -e NVIDIA_VISIBLE_DEVICES=$GPU_ID --ulimit memlock=-1 --shm-size=65536m --cap-add=IPC_LOCK --cap-add=SYS_NICE --cap-add=NET_ADMIN --cap-add=SYS_PTRACE --device=/dev/infiniband $PLATFORM_OPT --entrypoint sleep $IMAGE infinity
    if ! docker inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
        echo "container $CONTAINER_NAME failed to start" >&2
        return 1
    fi
    if [ "$(docker inspect -f '{{.State.Running}}' $CONTAINER_NAME)" = "true" ]; then
        pid=$(docker inspect -f '{{.State.Pid}}' $CONTAINER_NAME)
        if [ -n "$pid" ] && [ "$pid" -gt 0 ] 2>/dev/null; then
            nsenter -t $pid -n ip route add 10.0.0.0/8 dev "${IF_PREFIX}0" via $GW || true
            nsenter -t $pid -n ip link set "${IF_PREFIX}0" mtu 1500 || true
        fi
    fi

	#mkdir -p /var/run/netns
	#ln -s /proc/$pid/ns/net /var/run/netns/$pid
	#ip netns exec $pid ip route add 10.0.0.0/8 dev eth0 via $GW

	#docker exec -it $CONTAINER_NAME ip route add 10.0.0.0/8 dev eth0 via $GW

    if [ "$(docker inspect -f '{{.State.Running}}' $CONTAINER_NAME)" = "true" ]; then
        docker network connect bridge $CONTAINER_NAME || true
    fi

	# inspect
    if [ "$(docker inspect -f '{{.State.Running}}' $CONTAINER_NAME)" = "true" ]; then
        docker exec -it "$CONTAINER_NAME" ip addr
        docker exec -it $CONTAINER_NAME ip route
    else
        echo "container $CONTAINER_NAME is not running; showing last logs:" >&2
        docker logs --tail=200 "$CONTAINER_NAME" || true
    fi
}

# Create SR-IOV networks and two testbed containers
create_docker_network rdma0 sn0
create_docker_network rdma2 sn2
create_container rdma0 sn0 node2-nic0 0,1 200
create_container rdma2 sn2 node2-nic2 4,5 200
