#!/bin/bash

SERVER_IP=${1}
REMOTE_PATH=${2}
LOCAL_MOUNT=${3}
RDMA_PORT=${4:-20049}

if [[ -z "$SERVER_IP" || -z "$REMOTE_PATH" || -z "$LOCAL_MOUNT" ]]; then
    echo "Usage: $0 <SERVER_IP> <REMOTE_PATH> <LOCAL_MOUNT> [RDMA_PORT]"
    exit 1
fi

HOST_ALIAS="nfs-server-internal"

echo "--- Resetting NFS Client ---"

# 1. Cleanup
sudo umount -l $LOCAL_MOUNT 2>/dev/null
sudo mkdir -p $LOCAL_MOUNT

# 2. Modules
sudo modprobe rpcrdma

# 3. Add Host Mapping
sudo sed -i "/$HOST_ALIAS/d" /etc/hosts
echo "$SERVER_IP $HOST_ALIAS" | sudo tee -a /etc/hosts > /dev/null

# 4. TI-RPC Netconfig (CRITICAL: Must include RDMA entries)
cat << 'EOF' | sudo tee /etc/netconfig > /dev/null
rdma6      tpi_cots_ord  v     inet6    rdma    -       -
tcp6       tpi_cots_ord  v     inet6    tcp     -       -
udp6       tpi_clts      v     inet6    udp     -       -
rdma       tpi_cots_ord  v     inet     rdma    -       -
tcp        tpi_cots_ord  v     inet     tcp     -       -
udp        tpi_clts      v     inet     udp     -       -
rawip      tpi_raw       -     inet      -      -       -
local      tpi_cots_ord  -     loopback  -      -       -
EOF

# 5. Attempt Mount
echo "Attempting RDMA mount (NFSv4.2) to $HOST_ALIAS..."
# We use proto=rdma6 for IPv6 RDMA
sudo ./mount.nfs $HOST_ALIAS:$REMOTE_PATH $LOCAL_MOUNT -v \
    -o "rdma,port=$RDMA_PORT,vers=4.2,proto=rdma6"

if mountpoint -q $LOCAL_MOUNT; then
    echo "SUCCESS: Mounted via RDMA"
else
    echo "RDMA FAILED, trying TCP6 fallback..."
    sudo ./mount.nfs $HOST_ALIAS:$REMOTE_PATH $LOCAL_MOUNT -v \
        -o "proto=tcp6,vers=4.2"
fi
