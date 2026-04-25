#!/bin/bash

# --- CONFIGURATION ---
EXPORT_PATH="/mnt/nfs_ramdisk"
CLIENT_IPV6="2002:a05:673e:80c8::1"
RDMA_PORT=20049
NFS_THREADS=8

echo "--- Starting NFS Server Reset Sequence ---"

# 1. Kill any existing processes
echo "[1/8] Killing old NFS processes..."
sudo pkill -9 nfsd 2>/dev/null
sudo pkill rpc.mountd 2>/dev/null
sudo pkill rpcbind 2>/dev/null

# 2. Load kernel modules
echo "[2/8] Loading kernel modules (nfsd, svcrdma)..."
sudo modprobe nfsd
sudo modprobe svcrdma

# 3. Ensure directory structure exists
echo "[3/8] Preparing /var/lib/nfs..."
sudo mkdir -p /var/lib/nfs/v4recovery
sudo mkdir -p /var/lib/nfs/rpc_pipefs
sudo touch /var/lib/nfs/etab /var/lib/nfs/rmtab

# 4. Mount pipefs (Communication link between kernel and user daemons)
if ! mountpoint -q /var/lib/nfs/rpc_pipefs; then
    echo "[4/8] Mounting rpc_pipefs..."
    sudo mount -t rpc_pipefs sunrpc /var/lib/nfs/rpc_pipefs
fi

# 5. Fix /etc/netconfig for TI-RPC static binaries
echo "[5/8] Updating /etc/netconfig..."
cat << 'EOF' | sudo tee /etc/netconfig > /dev/null
udp6       tpi_clts      v     inet6    udp     -       -
tcp6       tpi_cots_ord  v     inet6    tcp     -       -
udp        tpi_clts      v     inet     udp     -       -
tcp        tpi_cots_ord  v     inet     tcp     -       -
rawip      tpi_raw       -     inet      -      -       -
local      tpi_cots_ord  -     loopback  -      -       -
unix       tpi_cots_ord  -     loopback  -      -       -
EOF

# 6. Setup Exports
echo "[6/8] Configuring /etc/exports..."
echo "$EXPORT_PATH [$CLIENT_IPV6](rw,sync,no_subtree_check,no_root_squash)" | sudo tee /etc/exports
sudo ./exportfs -arv

# 7. Start Services in order
echo "[7/8] Starting rpcbind and rpc.mountd..."
sudo ./rpcbind -i -w
sudo ./rpc.mountd

# 8. Configure Kernel NFS Server ports and start threads
echo "[8/8] Enabling RDMA on port $RDMA_PORT and starting nfsd..."
echo "rdma $RDMA_PORT" | sudo tee /proc/fs/nfsd/portlist
sudo ./rpc.nfsd $NFS_THREADS

echo "--- Server Ready ---"
sudo rpcinfo -p localhost
echo "Portlist status:"
cat /proc/fs/nfsd/portlist
