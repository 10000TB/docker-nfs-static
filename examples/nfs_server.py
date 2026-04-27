#!/usr/bin/env python3
import subprocess
import os
import sys
import time
import shutil

def run(cmd, shell=True, check=False):
    """Utility to run shell commands."""
    try:
        result = subprocess.run(cmd, shell=shell, check=check, capture_output=True, text=True)
        return result
    except subprocess.CalledProcessError as e:
        return e

def nfs_server():
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <EXPORT_PATH> <CLIENT_IP> [RDMA_PORT] [THREADS]")
        sys.exit(1)

    export_path = sys.argv[1]
    client_ip = sys.argv[2]
    rdma_port = sys.argv[3] if len(sys.argv) > 3 else "20049"
    nfs_threads = sys.argv[4] if len(sys.argv) > 4 else "8"
    
    logical_name = "nfs-client-node"
    ramdisk_path = "/mnt/nfs_ramdisk"

    print("--- Resetting NFS Server (IPv6 RDMA Fix) ---")

    # 1. Cleanup
    run("./rpc.nfsd 0")
    run("pkill -9 nfsd")
    run("pkill -9 rpc.mountd")
    run("pkill -9 rpcbind")
    run("umount /proc/fs/nfsd")
    run(f"umount -l {ramdisk_path}")
    time.sleep(1)

    # 2. Kernel Modules
    for mod in ["nfsd", "svcrdma", "irdma"]:
        run(f"modprobe {mod}")

    # 3. Virtual FS & Network
    os.makedirs("/proc/fs/nfsd", exist_ok=True)
    run("mount -t nfsd nfsd /proc/fs/nfsd")
    run("ip link set lo up")
    run("ip addr add ::1/128 dev lo")

    # 4. Precision Netconfig
    netconfig_content = """rdma       tpi_cots_ord  v     inet6    rdma    -       -
tcp        tpi_cots_ord  v     inet6    tcp     -       -
udp        tpi_clts      v     inet6    udp     -       -
local      tpi_cots_ord  -     loopback  -      -       -
"""
    with open("/etc/netconfig", "w") as f:
        f.write(netconfig_content)

    # 5. RAMDisk & Exports
    os.makedirs(ramdisk_path, exist_ok=True)
    run(f"mount -t tmpfs -o size=200G tmpfs {ramdisk_path}")
    run(f"chmod 777 {ramdisk_path}")
    
    # Update hosts
    run(f"sed -i '/{logical_name}/d' /etc/hosts")
    with open("/etc/hosts", "a") as f:
        f.write(f"{client_ip} {logical_name}\n")

    with open("/etc/exports", "w") as f:
        f.write(f"{export_path} {logical_name}(rw,sync,no_subtree_check,no_root_squash)\n")
    run("./exportfs -arv")

    # 6. Start RPC Stack
    run("./rpcbind -i -w")
    time.sleep(1)

    # 7. Start NFSD threads FIRST
    run(f"./rpc.nfsd {nfs_threads}")
    time.sleep(1)

    # 8. Set Portlist (Direct string binding)
    # Using the clear and add pattern to ensure registration
    with open("/proc/fs/nfsd/portlist", "w") as f:
        run('echo "-tcp 2049" > /proc/fs/nfsd/portlist')
        run('echo "tcp 2049" > /proc/fs/nfsd/portlist')
        run(f'echo "-rdma {rdma_port}" > /proc/fs/nfsd/portlist')
        run(f'echo "rdma {rdma_port}" > /proc/fs/nfsd/portlist')

    # 9. Start Mountd
    run("./rpc.mountd -n")

    print("\n--- [DEBUG] Server Status ---")
    print("1. Portlist State:")
    print(run("cat /proc/fs/nfsd/portlist").stdout)
    
    print("2. RPC Registration:")
    print(run("./rpcinfo | grep -E '100003|100005'").stdout)
    
    print("3. RDMA Listeners:")
    print(run(f"rdma res show cm_id | grep LISTEN | grep {rdma_port}").stdout)

if __name__ == "__main__":
    if os.geteuid() != 0:
        print("Script must be run as root (sudo).")
        sys.exit(1)
    nfs_server()
