#!/bin/bash

SERVER_IP=${1}
REMOTE_PATH=${2}
RDMA_MOUNT=${3}
TCP_MOUNT=${4}
RDMA_PORT=${5:-20049}

if [[ -z "$SERVER_IP" || -z "$REMOTE_PATH" || -z "$RDMA_MOUNT" || -z "$TCP_MOUNT" ]]; then
    echo "Usage: $0 <SERVER_IP> <REMOTE_PATH> <RDMA_MOUNT_POINT> <TCP_MOUNT_POINT> [RDMA_PORT]"
    exit 1
fi

HOST_ALIAS="nfs-server-internal"

echo "--- Resetting NFS Client Setup ---"

# 1. Cleanup both mount points
sudo umount -l $RDMA_MOUNT 2>/dev/null
sudo umount -l $TCP_MOUNT 2>/dev/null
sudo mkdir -p $RDMA_MOUNT
sudo mkdir -p $TCP_MOUNT

# 2. Modules
sudo modprobe rpcrdma
sudo modprobe xprtrdma

# 3. Add Host Mapping
sudo sed -i "/$HOST_ALIAS/d" /etc/hosts
echo "$SERVER_IP $HOST_ALIAS" | sudo tee -a /etc/hosts > /dev/null

# 4. TI-RPC Netconfig (Kept for internal library resolution)
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

echo "------------------------------------------------"

# 5. Attempt RDMA Mount
echo "Attempting RDMA mount (NFSv4.2) to $RDMA_MOUNT..."
# Using 'proto=rdma'. The kernel will use IPv6 because $HOST_ALIAS resolves to an IPv6 addr.
sudo ./mount.nfs $HOST_ALIAS:$REMOTE_PATH $RDMA_MOUNT -v \
    -o "vers=4.2,port=$RDMA_PORT,proto=rdma"

if mountpoint -q $RDMA_MOUNT; then
    echo "SUCCESS: RDMA mount established at $RDMA_MOUNT"
else
    echo "RDMA proto=rdma failed. Trying legacy 'rdma' flag..."
    # Fallback: Some versions of mount.nfs prefer the standalone 'rdma' keyword
    sudo ./mount.nfs $HOST_ALIAS:$REMOTE_PATH $RDMA_MOUNT -v \
        -o "rdma,vers=4.2,port=$RDMA_PORT"
    
    if mountpoint -q $RDMA_MOUNT; then
        echo "SUCCESS: RDMA mount established (via legacy flag)"
    else
        echo "ERROR: RDMA mount failed completely."
    fi
fi

echo "------------------------------------------------"

# 6. Attempt TCP Mount
echo "Attempting TCP mount (NFSv4.2/IPv6) to $TCP_MOUNT..."
sudo ./mount.nfs $HOST_ALIAS:$REMOTE_PATH $TCP_MOUNT -v \
    -o "vers=4.2,proto=tcp6"

if mountpoint -q $TCP_MOUNT; then
    echo "SUCCESS: TCP mount established at $TCP_MOUNT"
else
    echo "ERROR: TCP mount failed."
fi

echo "--- Script Finished ---"
