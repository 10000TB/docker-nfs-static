#!/bin/bash

# --- CONFIGURATION ---
SERVER_IPV6="2002:a05:673e:80c2::"
REMOTE_EXPORT="/mnt/nfs_ramdisk"
LOCAL_MOUNT="/mnt/remote_rdma"
RDMA_PORT=20049

echo "--- Starting NFS Client Reset Sequence ---"

# 1. Cleanup old mount
echo "[1/5] Unmounting $LOCAL_MOUNT..."
sudo umount -f $LOCAL_MOUNT 2>/dev/null
sudo mkdir -p $LOCAL_MOUNT

# 2. Load kernel modules
echo "[2/5] Loading kernel modules (rpcrdma)..."
sudo modprobe rpcrdma

# 3. Fix /etc/netconfig (Required for static mount.nfs)
echo "[3/5] Updating /etc/netconfig..."
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
echo "[4/5] Attempting RDMA mount (NFSv4.2)..."
sudo ./mount.nfs -v -o rdma,port=$RDMA_PORT,vers=4.2 [$SERVER_IPV6]:$REMOTE_EXPORT $LOCAL_MOUNT

# 5. Fallback check
if mountpoint -q $LOCAL_MOUNT; then
    echo "SUCCESS: Mounted RDMA"
    df -h $LOCAL_MOUNT
else
    echo "FAILED: RDMA mount failed. Attempting TCP fallback..."
    sudo ./mount.nfs -v -o proto=tcp6,vers=4.2 [$SERVER_IPV6]:$REMOTE_EXPORT $LOCAL_MOUNT
fi
