#!/bin/bash

# --- PARAMETERS ---
EXPORT_PATH=${1}
CLIENT_IP=${2}
RDMA_PORT=${3:-20049}
NFS_THREADS=${4:-8}

if [[ -z "$EXPORT_PATH" || -z "$CLIENT_IP" ]]; then
    echo "Usage: $0 <EXPORT_PATH> <CLIENT_IP> [RDMA_PORT] [THREADS]"
    exit 1
fi

# Helper: Wrap IPv6 in brackets
CLIENT_TARGET="$CLIENT_IP"
if [[ "$CLIENT_IP" == *":"* ]]; then CLIENT_TARGET="[$CLIENT_IP]"; fi

echo "--- Resetting NFS Server ---"

# 1. Kill everything
echo "[1/7] Cleaning up existing processes..."
sudo pkill -9 nfsd 2>/dev/null
sudo pkill -9 rpc.mountd 2>/dev/null
sudo pkill -9 rpcbind 2>/dev/null
sleep 1

# 2. Kernel Modules
echo "[2/7] Loading modules..."
sudo modprobe nfsd
sudo modprobe svcrdma

# 3. Directories and PipeFS
echo "[3/7] Preparing state directories..."
sudo mkdir -p /var/lib/nfs/v4recovery
sudo mkdir -p /var/lib/nfs/rpc_pipefs
if ! mountpoint -q /var/lib/nfs/rpc_pipefs; then
    sudo mount -t rpc_pipefs sunrpc /var/lib/nfs/rpc_pipefs
fi

# 4. Fix /etc/netconfig (Removed RDMA from here to stop mountd complaining)
echo "[4/7] Updating /etc/netconfig..."
cat << 'EOF' | sudo tee /etc/netconfig > /dev/null
udp6       tpi_clts      v     inet6    udp     -       -
tcp6       tpi_cots_ord  v     inet6    tcp     -       -
udp        tpi_clts      v     inet     udp     -       -
tcp        tpi_cots_ord  v     inet     tcp     -       -
rawip      tpi_raw       -     inet      -      -       -
local      tpi_cots_ord  -     loopback  -      -       -
unix       tpi_cots_ord  -     loopback  -      -       -
EOF

# 5. Exports
echo "[5/7] Exporting $EXPORT_PATH..."
echo "$EXPORT_PATH $CLIENT_TARGET(rw,sync,no_subtree_check,no_root_squash)" | sudo tee /etc/exports
sudo ./exportfs -arv

# 6. Start RPC stack
echo "[6/7] Starting rpcbind and mountd..."
# Start rpcbind and wait a second for it to initialize the socket
sudo ./rpcbind -i -w
sleep 1
# Start mountd in foreground briefly to check for errors, then daemonize
sudo ./rpc.mountd

# 7. Start Kernel Threads
echo "[7/7] Configuring portlist and starting nfsd..."
# Only add to portlist if not already present to avoid "Cannot assign address"
if ! grep -q "rdma $RDMA_PORT" /proc/fs/nfsd/portlist; then
    echo "rdma $RDMA_PORT" | sudo tee /proc/fs/nfsd/portlist || echo "RDMA port failed (already set?)"
fi

sudo ./rpc.nfsd $NFS_THREADS

echo "--- Server Ready ---"
cat /proc/fs/nfsd/portlist
