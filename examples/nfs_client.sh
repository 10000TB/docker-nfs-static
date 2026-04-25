#!/bin/bash

# --- PARAMETERS ---
SERVER_IP=${1}
REMOTE_PATH=${2}
LOCAL_MOUNT=${3}
RDMA_PORT=${4:-20049}

if [[ -z "$SERVER_IP" || -z "$REMOTE_PATH" || -z "$LOCAL_MOUNT" ]]; then
    echo "Usage: $0 <SERVER_IP> <REMOTE_PATH> <LOCAL_MOUNT> [RDMA_PORT]"
    echo "Example: $0 <ServerIP>  /mnt/nfs_ramdisk /mnt/remote_rdma"
    exit 1
fi

# Helper: Wrap IPv6 in brackets if colons are present
SERVER_TARGET="$SERVER_IP"
if [[ "$SERVER_IP" == *":"* ]]; then SERVER_TARGET="[$SERVER_IP]"; fi

echo "--- Resetting NFS Client: Mounting $SERVER_IP:$REMOTE_PATH to $LOCAL_MOUNT ---"

# 1. Cleanup old mount
sudo umount -f $LOCAL_MOUNT 2>/dev/null
sudo mkdir -p $LOCAL_MOUNT

# 2. Load kernel modules
sudo modprobe rpcrdma

# 3. Fix /etc/netconfig
cat << 'EOF' | sudo tee /etc/netconfig > /dev/null
udp6       tpi_clts      v     inet6    udp     -       -
tcp6       tpi_cots_ord  v     inet6    tcp     -       -
udp        tpi_clts      v     inet     udp     -       -
tcp        tpi_cots_ord  v     inet     tcp     -       -
rawip      tpi_raw       -     inet      -      -       -
local      tpi_cots_ord  -     loopback  -      -       -
unix       tpi_cots_ord  -     loopback  -      -       -
EOF

# 4. Attempt RDMA Mount
echo "Attempting RDMA mount..."
sudo ./mount.nfs -v -o rdma,port=$RDMA_PORT,vers=4.2 $SERVER_TARGET:$REMOTE_PATH $LOCAL_MOUNT

# 5. Fallback check
if mountpoint -q $LOCAL_MOUNT; then
    echo "SUCCESS: Mounted via RDMA"
else
    echo "FAILED: RDMA failed. Attempting TCP fallback..."
    sudo ./mount.nfs -v -o proto=tcp6,vers=4.2 $SERVER_TARGET:$REMOTE_PATH $LOCAL_MOUNT
fi
