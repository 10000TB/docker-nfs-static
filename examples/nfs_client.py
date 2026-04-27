#!/usr/bin/env python3
import subprocess
import os
import sys
import socket

def run(cmd, shell=True):
    return subprocess.run(cmd, shell=shell, capture_output=True, text=True)

def print_debug(server_ip, phase):
    print(f"\n=== [DEBUG: {phase}] ===")
    print(f"1. RPC info from server {server_ip}:")
    print(run(f"./rpcinfo -p {server_ip} | grep 100003").stdout or "NFS NOT REGISTERED ON SERVER!")
    print("2. Local Dmesg (NFS/RPC/RDMA):")
    print(run("dmesg | grep -iE 'nfs|rpc|rdma' | tail -n 10").stdout)
    print("=========================")

def nfs_client():
    if len(sys.argv) < 5:
        print(f"Usage: {sys.argv[0]} <SERVER_IP> <REMOTE_PATH> <RDMA_LOCAL> <TCP_LOCAL> [RDMA_PORT]")
        sys.exit(1)

    server_ip = sys.argv[1].replace("[", "").replace("]", "")
    remote_path = sys.argv[2]
    rdma_mount = sys.argv[3]
    tcp_mount = sys.argv[4]
    rdma_port = sys.argv[5] if len(sys.argv) > 5 else "20049"
    
    host_alias = "nfs-server-internal"
    mount_helper = os.path.join(os.getcwd(), "mount.nfs")

    # Detect Local IPv6
    try:
        s = socket.socket(socket.AF_INET6, socket.SOCK_DGRAM)
        s.connect((server_ip, 1))
        local_ip = s.getsockname()[0]
        s.close()
    except Exception:
        local_ip = "::1"

    print(f"--- Initializing IPv6 Client (Local IP: {local_ip}) ---")

    # 1. Cleanup
    run(f"umount -l {rdma_mount}")
    run(f"umount -l {tcp_mount}")
    os.makedirs(rdma_mount, exist_ok=True)
    os.makedirs(tcp_mount, exist_ok=True)
    run("modprobe rpcrdma")
    run("modprobe xprtrdma")

    # 2. Host Mapping
    run(f"sed -i '/{host_alias}/d' /etc/hosts")
    with open("/etc/hosts", "a") as f:
        f.write(f"{server_ip} {host_alias}\n")

    # 3. Netconfig Precision (Shadowing)
    netconfig_content = """rdma       tpi_cots_ord  v     inet6    rdma    -       -
tcp6       tpi_cots_ord  v     inet6    tcp     -       -
udp6       tpi_clts      v     inet6    udp     -       -
local      tpi_cots_ord  -     loopback  -      -       -
"""
    with open("/etc/netconfig", "w") as f:
        f.write(netconfig_content)

    print("------------------------------------------------")

    # 4. RDMA Mount
    print(f"Attempting RDMA mount to {rdma_mount}...")
    rdma_opts = f"vers=4.2,port={rdma_port},proto=rdma,clientaddr={local_ip},addr={server_ip}"
    res = run(f"{mount_helper} {host_alias}:{remote_path} {rdma_mount} -v -o {rdma_opts}")

    if os.path.ismount(rdma_mount):
        print("SUCCESS: RDMA mount established.")
    else:
        print("ERROR: RDMA mount failed.")
        print_debug(server_ip, "RDMA_FAILURE")

    print("------------------------------------------------")

    # 5. TCP Mount
    print(f"Attempting TCP mount to {tcp_mount}...")
    tcp_opts = "vers=4.2,proto=tcp6"
    run(f"{mount_helper} {host_alias}:{remote_path} {tcp_mount} -v -o {tcp_opts}")

    if os.path.ismount(tcp_mount):
        print("SUCCESS: TCP mount established.")
    else:
        print("ERROR: TCP mount failed.")
        print_debug(server_ip, "TCP_FAILURE")

if __name__ == "__main__":
    if os.geteuid() != 0:
        print("Script must be run as root (sudo).")
        sys.exit(1)
    nfs_client()
