# Example Instructions

Usage: `./nfs_server.sh <EXPORT_PATH> <CLIENT_IP> [RDMA_PORT] [THREADS]`    
Example: `./nfs_server.sh /mnt/nfs_ramdisk <ClientIPv6>`


Usage: `./nfs_client.sh <SERVER_IP> <REMOTE_PATH> <LOCAL_MOUNT> [RDMA_PORT]`
Example: `./nfs_client.sh <ServerIPv6> /mnt/nfs_ramdisk /mnt/remote_rdma`
