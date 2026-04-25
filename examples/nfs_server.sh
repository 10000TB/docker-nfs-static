#!/bin/bash

EXPORT_PATH=${1}
CLIENT_IP=${2}
RDMA_PORT=${3:-20049}
NFS_THREADS=${4:-8}

if [[ -z "$EXPORT_PATH" || -z "$CLIENT_IP" ]]; then
    echo "Usage: $0 <EXPORT_PATH> <CLIENT_IP> [RDMA_PORT]"
    exit 1
fi

LOGICAL_NAME="nfs-client-node"

echo "--- Resetting NFS Server ---"

# 1. Cleanup
sudo ./rpc.nfsd 0 2>/dev/null
sudo pkill -9 nfsd 2>/dev/null
sudo pkill -9 rpc.mountd 2>/dev/null
sudo pkill -9 rpcbind 2>/dev/null
sleep 1

# 2. Kernel Modules
sudo modprobe nfsd
sudo modprobe svcrdma

# 3. Network Prep
sudo ip addr add ::1/128 dev lo 2>/dev/null

# 4. Host Mapping
sudo sed -i "/$LOGICAL_NAME/d" /etc/hosts
echo "$CLIENT_IP $LOGICAL_NAME" | sudo tee -a /etc/hosts > /dev/null

# 5. Directories
sudo mkdir -p /var/lib/nfs/v4recovery /var/lib/nfs/rpc_pipefs
sudo touch /var/lib/nfs/etab /var/lib/nfs/rmtab
if ! mountpoint -q /var/lib/nfs/rpc_pipefs; then
    sudo mount -t rpc_pipefs sunrpc /var/lib/nfs/rpc_pipefs
fi

# 6. Netconfig (Including RDMA)
cat << 'EOF' | sudo tee /etc/netconfig > /dev/null
rdma6      tpi_cots_ord  v     inet6    rdma    -       -
tcp6       tpi_cots_ord  v     inet6    tcp     -       -
udp6       tpi_clts      v     inet6    udp     -       -
rdma       tpi_cots_ord  v     inet     rdma    -       -
tcp        tpi_cots_ord  v     inet     tcp     -       -
udp        tpi_clts      v     inet     udp     -       -
local      tpi_cots_ord  -     loopback  -      -       -
EOF

# 7. Setup Exports
echo "$EXPORT_PATH $LOGICAL_NAME(rw,sync,no_subtree_check,no_root_squash)" | sudo tee /etc/exports
sudo ./exportfs -arv

# 8. Start RPC stack
sudo ./rpcbind -i -w
sleep 1
sudo ./rpc.mountd -n

# 9. Set Portlist and start threads
echo "tcp 2049" | sudo tee /proc/fs/nfsd/portlist
echo "rdma $RDMA_PORT" | sudo tee /proc/fs/nfsd/portlist
sudo ./rpc.nfsd $NFS_THREADS

echo "--- Server Ready ---"
cat /proc/fs/nfsd/portlist
