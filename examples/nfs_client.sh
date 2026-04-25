#!/bin/bash

SERVER_IP=${1}
REMOTE_PATH=${2}
LOCAL_MOUNT=${3}
RDMA_PORT=${4:-20049}

if [[ -z "$SERVER_IP" || -z "$REMOTE_PATH" || -z "$LOCAL_MOUNT" ]]; then
    echo "Usage: $0 <SERVER_IP> <REMOTE_PATH> <LOCAL_MOUNT> [RDMA_PORT]"
    exit 1
fi

SERVER_TARGET="$SERVER_IP"
if [[ "$SERVER_IP" == *":"* ]]; then SERVER_TARGET="[$SERVER_IP]"; fi

echo "--- Resetting NFS Client ---"

# 1. Cleanup
sudo umount -l $LOCAL_MOUNT 2>/dev/null
sudo mkdir -p $LOCAL_MOUNT

# 2. Modules
sudo modprobe rpcrdma

# 3. Netconfig
cat << 'EOF' | sudo tee /etc/netconfig > /dev/null
udp6       tpi_clts      v     inet6    udp     -       -
tcp6       tpi_cots_ord  v     inet6    tcp     -       -
udp        tpi_clts      v     inet     udp     -       -
tcp        tpi_cots_ord  v     inet     tcp     -       -
rawip      tpi_raw       -     inet      -      -       -
local      tpi_cots_ord  -     loopback  -      -       -
unix       tpi_cots_ord  -     loopback  -      -       -
EOF

# 4. Mount
echo "Attempting RDMA mount on $SERVER_IP:$RDMA_PORT..."
# Note: Use proto=rdma (or rdma6 if using IPv6)
sudo ./mount.nfs -v -o rdma,port=$RDMA_PORT,vers=4.2,proto=rdma $SERVER_TARGET:$REMOTE_PATH $LOCAL_MOUNT

if mountpoint -q $LOCAL_MOUNT; then
    echo "SUCCESS"
else
    echo "RDMA FAILED, trying TCP..."
    sudo ./mount.nfs -v -o proto=tcp6,vers=4.2 $SERVER_TARGET:$REMOTE_PATH $LOCAL_MOUNT
fi
