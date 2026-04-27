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
RAMDISK_PATH="/mnt/nfs_ramdisk"

echo "--- Resetting NFS Server (IPv6 RDMA Fix) ---"

# 1. Cleanup
sudo ./rpc.nfsd 0 2>/dev/null
sudo pkill -9 nfsd 2>/dev/null
sudo pkill -9 rpc.mountd 2>/dev/null
sudo pkill -9 rpcbind 2>/dev/null
sudo umount /proc/fs/nfsd 2>/dev/null
sudo umount -l "$RAMDISK_PATH" 2>/dev/null
sleep 1

# 2. Kernel Modules
sudo modprobe nfsd
sudo modprobe svcrdma
sudo modprobe irdma

# 3. Virtual FS & Network
sudo mkdir -p /proc/fs/nfsd
sudo mount -t nfsd nfsd /proc/fs/nfsd 2>/dev/null
sudo ip link set lo up
sudo ip addr add ::1/128 dev lo 2>/dev/null

# 4. Precision Netconfig (CRITICAL for rpcbind/mountd registration)
# Note: rdma must be 'tpi_cots_ord' (connection oriented)
cat << 'EOF' | sudo tee /etc/netconfig > /dev/null
rdma       tpi_cots_ord  v     inet6    rdma    -       -
tcp        tpi_cots_ord  v     inet6    tcp     -       -
udp        tpi_clts      v     inet6    udp     -       -
local      tpi_cots_ord  -     loopback  -      -       -
EOF

# 5. RAMDisk & Exports
sudo mkdir -p "$RAMDISK_PATH"
sudo mount -t tmpfs -o size=200G tmpfs "$RAMDISK_PATH"
sudo chmod 777 "$RAMDISK_PATH"
sudo sed -i "/$LOGICAL_NAME/d" /etc/hosts
echo "$CLIENT_IP $LOGICAL_NAME" | sudo tee -a /etc/hosts > /dev/null
echo "$EXPORT_PATH $LOGICAL_NAME(rw,sync,no_subtree_check,no_root_squash)" | sudo tee /etc/exports
sudo ./exportfs -arv

# 6. Start Stack in specific sequence
sudo ./rpcbind -i -w
sleep 1

# 7. Start threads and set ports
sudo ./rpc.nfsd $NFS_THREADS
sleep 1
# Clear and re-add to force rpcbind registration
echo "-tcp 2049" | sudo tee /proc/fs/nfsd/portlist 2>/dev/null
echo "tcp 2049" | sudo tee /proc/fs/nfsd/portlist
echo "-rdma $RDMA_PORT" | sudo tee /proc/fs/nfsd/portlist 2>/dev/null
echo "rdma $RDMA_PORT" | sudo tee /proc/fs/nfsd/portlist

# 8. Start Mountd
sudo ./rpc.mountd -n

echo -e "\n--- [DEBUG] Server Status ---"
echo "1. Portlist State:"
cat /proc/fs/nfsd/portlist
echo -e "\n2. RPC Registration (Look for rdma/100003):"
./rpcinfo | grep -E "100003|100005"
echo -e "\n3. RDMA Listeners:"
sudo rdma res show cm_id | grep LISTEN | grep "$RDMA_PORT"
