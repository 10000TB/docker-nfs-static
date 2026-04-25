# 🚀 High-Performance Static NFS Toolchain

![Build Status](https://github.com/10000TB/docker-nfs-static/actions/workflows/build.yml/badge.svg)

A specialized Docker-based build system to generate **fully static, standalone binaries**... for NFS utilities. These binaries are designed for high-performance storage environments, supporting **NFSv4.2, pNFS, RDMA, and IPv6**.

By linking everything statically, these binaries run on any Linux distribution without needing `libtirpc`, `libevent`, or `keyutils` installed on the host. This is ideal for minimal environments like Alpine, Clear Linux, custom initramfs, or containers.

## ✨ Key Features

- **Fully Static:** Zero external dependencies. Copy the binary and run.
- **NFSv4.2 Support:** Includes latest protocol features like Server-Side Copy (SSC).
- **RDMA-Ready:** Built with `--enable-rdma` for low-latency NFS-over-RDMA.
- **Parallel NFS (pNFS):** Includes `blkmapd` for block-layout performance.
- **Forced IPv6:** Custom-built `libtirpc` and `rpcbind` with IPv6 forced on.
- **Multi-Arch:** Support for `amd64` and `arm64` (Apple Silicon, AWS Graviton, Raspberry Pi).

---

## 🛠 Prerequisites

- **Docker** installed on your build machine.
- **Docker Buildx** (standard with modern Docker Desktop/Engine) if you plan to cross-compile for other architectures.

---

## 🏗 How to Build

The build process happens entirely inside a container. The resulting binaries are exported directly to your host machine in a `./bin` folder.

### 1. Build for your current architecture (AMD64/x86_64)

```bash
docker build --build-arg ARCH=amd64 -t nfs-static .
```

### 2. ARM64

```
docker build --build-arg ARCH=arm64v8 -t nfs-static 
```

NOTE Qemu emulation need be registrated for cross-compilation, `docker run --rm --privileged multiarch/qemu-user-static --reset -p yes`
