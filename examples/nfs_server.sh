#!/bin/bash

# --- PARAMETERS ---
EXPORT_PATH=${1}
CLIENT_IP=${2}
RDMA_PORT=${3:-20049}
NFS_THREADS=${4:-8}

if [[ -z "$EXPORT_PATH" || -z "$CLIENT_IP" ]]; then
    echo "Usage: $0 <EXPORT_PATH> <CLIENT_IP> [RDMA_PORT] [THREADS]"
    echo "Example: $0 /mnt/nfs_ramdisk 2002:a05:673e:80c8::1"
    exit 1
fi

# Helper: Wrap IPv6 in brackets if colons are present
CLIENT_TARGET="$CLIENT_IP"
if [[ "$CLIENT_IP" == *":"* ]]; then CLIENT_TARGET="[$CLIENT_IP]"; fi

echo "--- Resetting NFS Server: Exporting $EXPORT_PATH to $CLIENT_IP ---"

# 1. Kill any existing processes
sudo pkill -9 nfsd 2>/dev/null
sudo pkill rpc.mountd 2>/dev/null
sudo pkill rpcbind 2>/dev/null

# 2. Load kernel modules
sudo modprobe nfsd
sudo modprobe svcrdma

# 3. Ensure directory structure exists
sudo mkdir -p /var/lib/nfs/v4recovery
sudo mkdir -p /var/lib/nfs/rpc_pipefs
sudo touch /var/lib/nfs/etab /var/lib/nfs/rmtab

# 4. Mount pipefs
if ! mountpoint -q /var/lib/nfs/rpc_pipefs; then
    sudo mount -t rpc_pipefs sunrpc /var/lib/nfs/rpc_pipefs
fi

# 5. Fix /etc/netconfig
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
echo "$EXPORT_PATH $CLIENT_TARGET(rw,sync,no_subtree_check,no_root_squash)" | sudo tee /etc/exports
sudo ./exportfs -arv

# 7. Start Services
sudo ./rpcbind -i -w
sudo ./rpc.mountd

# 8. Enable RDMA and start threads
echo "rdma $RDMA_PORT" | sudo tee /proc/fs/nfsd/portlist
sudo ./rpc.nfsd $NFS_THREADS

echo "--- Server Ready ---"
cat /proc/fs/nfsd/portlist
