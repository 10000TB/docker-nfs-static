#!/bin/bash

SERVER_IP=$(echo "${1}" | tr -d '[]')
REMOTE_PATH=${2}
RDMA_MOUNT=${3}
TCP_MOUNT=${4}
RDMA_PORT=${5:-20049}

if [[ -z "$SERVER_IP" || -z "$REMOTE_PATH" || -z "$RDMA_MOUNT" || -z "$TCP_MOUNT" ]]; then
    echo "Usage: $0 <SERVER_IP> <REMOTE_PATH> <RDMA_LOCAL> <TCP_LOCAL> [RDMA_PORT]"
    exit 1
fi

HOST_ALIAS="nfs-server-internal"
MOUNT_HELPER="$(pwd)/mount.nfs"

# Detect local IPv6
LOCAL_IP=$(ip -6 addr show | grep 'scope global' | awk '{print $2}' | cut -d/ -f1 | head -n 1)

print_debug() {
    local phase=$1
    echo -e "\n=== [DEBUG: $phase] ==="
    echo "1. RPC info from server $SERVER_IP:"
    ./rpcinfo -p "$SERVER_IP" 2>/dev/null | grep 100003 || echo "NFS NOT REGISTERED ON SERVER!"
    echo "2. Local Dmesg (NFS/RPC/RDMA):"
    dmesg | grep -iE "nfs|rpc|rdma" | tail -n 10
    echo "========================="
}

echo "--- Resetting NFS Client ---"
sudo umount -l "$RDMA_MOUNT" "$TCP_MOUNT" 2>/dev/null
sudo mkdir -p "$RDMA_MOUNT" "$TCP_MOUNT"
sudo modprobe rpcrdma
sudo modprobe xprtrdma

# 1. Update /etc/hosts
sudo sed -i "/$HOST_ALIAS/d" /etc/hosts
echo "$SERVER_IP $HOST_ALIAS" | sudo tee -a /etc/hosts > /dev/null

# 2. Netconfig Precision (Crucial Fix)
# We define 'rdma' AS 'inet6' to trick libtirpc into allowing IPv6.
cat << 'EOF' | sudo tee /etc/netconfig > /dev/null
rdma       tpi_cots_ord  v     inet6    rdma    -       -
tcp6       tpi_cots_ord  v     inet6    tcp     -       -
udp6       tpi_clts      v     inet6    udp     -       -
local      tpi_cots_ord  -     loopback  -      -       -
EOF

echo "------------------------------------------------"

# 3. RDMA Mount
echo "Attempting RDMA mount (NFSv4.2) to $RDMA_MOUNT..."
# FIX: Use the Alias (prevents ::: mangling) but pass addr literal in options.
# Use clientaddr to fix Musl resolution bug.
sudo "$MOUNT_HELPER" "$HOST_ALIAS:$REMOTE_PATH" "$RDMA_MOUNT" -v \
    -o "vers=4.2,port=$RDMA_PORT,proto=rdma,clientaddr=$LOCAL_IP,addr=$SERVER_IP"

if mountpoint -q "$RDMA_MOUNT"; then
    echo "SUCCESS: RDMA mount established."
else
    echo "ERROR: RDMA mount failed completely."
    print_debug "RDMA_FAILURE"
fi

echo "------------------------------------------------"

# 4. TCP Mount
echo "Attempting TCP mount (NFSv4.2)..."
sudo "$MOUNT_HELPER" "$HOST_ALIAS:$REMOTE_PATH" "$TCP_MOUNT" -v \
    -o "vers=4.2,proto=tcp6"

if mountpoint -q "$TCP_MOUNT"; then
    echo "SUCCESS: TCP mount established."
else
    echo "ERROR: TCP mount failed."
    print_debug "TCP_FAILURE"
fi
