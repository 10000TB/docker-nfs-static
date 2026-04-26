#!/bin/bash

EXPORT_PATH=${1}
CLIENT_IP=${2}
RDMA_PORT=${3:-20049}
NFS_THREADS=${4:-8}

if [[ -z "$EXPORT_PATH" || -z "$CLIENT_IP" ]]; then
    echo "Usage: $0 <EXPORT_PATH> <CLIENT_IP> [RDMA_PORT] [THREADS]"
    exit 1
fi

LOGICAL_NAME="nfs-client-node"

echo "--- Resetting NFS Server ---"

# 1. Kill existing processes
# Stop nfsd threads first (official way)
sudo ./rpc.nfsd 0 2>/dev/null
sudo pkill -9 nfsd 2>/dev/null
sudo pkill -9 rpc.mountd 2>/dev/null
sudo pkill -9 rpcbind 2>/dev/null
# Unmount nfsd filesystem to ensure a clean state
sudo umount /proc/fs/nfsd 2>/dev/null
sleep 1

# 2. Kernel Modules
sudo modprobe nfsd
sudo modprobe svcrdma
sudo modprobe rpcrdma

# 3. Mount nfsd virtual filesystem (CRITICAL for /proc/fs/nfsd/portlist)
sudo mkdir -p /proc/fs/nfsd
if ! mountpoint -q /proc/fs/nfsd; then
    sudo mount -t nfsd nfsd /proc/fs/nfsd
fi

# 4. Ramdisk and Directories
sudo mkdir -p /mnt/nfs_ramdisk
if ! mountpoint -q /mnt/nfs_ramdisk; then
    sudo mount -t tmpfs -o size=200G tmpfs /mnt/nfs_ramdisk
fi
sudo chmod 777 /mnt/nfs_ramdisk
# Only chmod cnssd if it exists
[ -d "/mnt/nfs_cnssd" ] && sudo chmod 777 /mnt/nfs_cnssd

# 5. Network Prep
sudo ip link set lo up
sudo ip addr add ::1/128 dev lo 2>/dev/null

# 6. Host Mapping
sudo sed -i "/$LOGICAL_NAME/d" /etc/hosts
echo "$CLIENT_IP $LOGICAL_NAME" | sudo tee -a /etc/hosts > /dev/null

# 7. Netconfig (Must be done before starting RPC services)
cat << 'EOF' | sudo tee /etc/netconfig > /dev/null
rdma6      tpi_cots_ord  v     inet6    rdma    -       -
tcp6       tpi_cots_ord  v     inet6    tcp     -       -
udp6       tpi_clts      v     inet6    udp     -       -
rdma       tpi_cots_ord  v     inet     rdma    -       -
tcp        tpi_cots_ord  v     inet     tcp     -       -
udp        tpi_clts      v     inet     udp     -       -
local      tpi_cots_ord  -     loopback  -      -       -
EOF

# 8. Directories for NFS state
sudo mkdir -p /var/lib/nfs/v4recovery /var/lib/nfs/rpc_pipefs
sudo touch /var/lib/nfs/etab /var/lib/nfs/rmtab
if ! mountpoint -q /var/lib/nfs/rpc_pipefs; then
    sudo mount -t rpc_pipefs sunrpc /var/lib/nfs/rpc_pipefs
fi

# 9. Setup Exports
echo "$EXPORT_PATH $LOGICAL_NAME(rw,sync,no_subtree_check,no_root_squash)" | sudo tee /etc/exports
sudo ./exportfs -arv

# 10. Start RPC stack
sudo ./rpcbind -i -w
sleep 1

# 11. Configure RDMA/TCP ports BEFORE starting nfsd threads
# Note: Writing to portlist requires nfsd filesystem to be mounted (Step 3)
echo "tcp 2049" | sudo tee /proc/fs/nfsd/portlist
echo "rdma $RDMA_PORT" | sudo tee /proc/fs/nfsd/portlist

# 12. Start mountd and nfsd
sudo ./rpc.mountd -n
sudo ./rpc.nfsd $NFS_THREADS

echo "--- Server Ready ---"
echo "Active Portlist:"
cat /proc/fs/nfsd/portlist
