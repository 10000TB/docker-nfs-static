# syntax=docker/dockerfile:1
# This Dockerfile is now Multi-Arch (amd64/arm64) compatible.
# Default to amd64, but can be overridden via --build-arg ARCH=arm64v8
ARG ARCH=amd64
FROM ${ARCH}/alpine:3.19 AS builder

# 1. Install build tools and headers
# All these packages are available in the official Alpine repositories for both amd64 and arm64.
RUN apk add --no-cache \
    build-base \
    autoconf \
    automake \
    libtool \
    pkgconf \
    util-linux-dev \
    util-linux-static \
    libcap-dev \
    libcap-static \
    libevent-dev \
    libevent-static \
    sqlite-dev \
    sqlite-static \
    keyutils-dev \
    rpcsvc-proto \
    xz \
    curl \
    zlib-static \
    attr-dev \
    attr-static \
    libnsl-dev \
    linux-headers \
    bsd-compat-headers \
    lvm2-dev \
    device-mapper-static \
    libaio-dev \
    eudev-dev \
    file

WORKDIR /src

# 2. Build KEYUTILS from source (Ensures we have a clean libkeyutils.a)
# CFLAGS are neutral; -fPIC is safe for both x86 and ARM.
RUN curl -L https://git.kernel.org/pub/scm/linux/kernel/git/dhowells/keyutils.git/snapshot/keyutils-1.6.3.tar.gz | tar -xz && \
    cd keyutils-1.6.3 && \
    make libkeyutils.a CFLAGS="-static -fPIC" && \
    cp libkeyutils.a /usr/lib/ && \
    cp keyutils.h /usr/include/

# 3. Build CUSTOM LIBTIRPC (Forced IPv6)
# Building from source ensures we have consistent IPv6 behavior regardless of architecture.
RUN curl -L https://downloads.sourceforge.net/project/libtirpc/libtirpc/1.3.4/libtirpc-1.3.4.tar.bz2 | tar -xj && \
    cd libtirpc-1.3.4 && \
    ./configure \
        --prefix=/usr \
        --disable-gssapi \
        --enable-ipv6 \
        --enable-static \
        --disable-shared && \
    make -j$(nproc) && \
    make install

# 4. Download nfs-utils 2.6.4
WORKDIR /src
RUN curl -L https://www.kernel.org/pub/linux/utils/nfs-utils/2.6.4/nfs-utils-2.6.4.tar.xz | tar -xJ

WORKDIR /src/nfs-utils-2.6.4

# 5. FIX SOURCE CODE BUGS (musl/arch neutral)
RUN sed -i '1i #include <unistd.h>' support/reexport/reexport.c && \
    sed -i '1i #include <unistd.h>' support/reexport/fsidd.c

# 6. Configure nfs-utils (IPv6 + RDMA Enabled)
# --enable-rdma will pull in the architecture-specific kernel headers automatically.
RUN ./configure \
    --prefix=/usr \
    --sysconfdir=/etc \
    --sbindir=/sbin \
    --disable-gss \
    --enable-nfsv4 \
    --enable-nfsv41 \
    --enable-pnfs \
    --enable-blkmapd \
    --enable-ipv6 \
    --enable-rdma \
    --disable-nfsdcltrack \
    --disable-nfsdcld \
    --without-tcp-wrappers \
    --with-tirpcinclude=/usr/include/tirpc \
    --enable-static \
    --disable-shared

# 7. Build nfs-utils
# The linking paths for .a files are consistent across Alpine architectures.
RUN make -j$(nproc) \
    LDFLAGS="-all-static" \
    CFLAGS="-static -Wno-error" \
    LIBS="-ltirpc -levent_core -levent -lmount -lblkid -luuid /usr/lib/libdevmapper.a /usr/lib/libudev.a /usr/lib/libaio.a -lsqlite3 -lattr -lz -lpthread /usr/lib/libkeyutils.a"

# 8. Install to a temporary directory
RUN make install DESTDIR=/install

# 8b. Download and Build RPCBIND statically (IPv6 Enabled)
WORKDIR /src
RUN curl -L https://downloads.sourceforge.net/project/rpcbind/rpcbind/1.2.6/rpcbind-1.2.6.tar.bz2 | tar -xj

WORKDIR /src/rpcbind-1.2.6

# Fix service name mapping
RUN sed -i "/servname/s:rpcbind:sunrpc:" src/rpcbind.c

# Configure rpcbind
RUN ./configure \
    --prefix=/usr \
    --bindir=/sbin \
    --with-rpcuser=root \
    --enable-warmstarts \
    --enable-ipv6 \
    --with-tirpcinclude=/usr/include/tirpc \
    --without-systemdsystemunitdir

# Build rpcbind with -static (arch-neutral linker flag)
RUN make -j$(nproc) \
    LDFLAGS="-static" \
    CFLAGS="-static -Wno-error" \
    LIBS="-ltirpc -lpthread"

# Install rpcbind to the same temporary directory
RUN make install DESTDIR=/install

# 9. CONSOLIDATION STEP: 
# The 'file' and 'strip' commands are architecture-aware and will process 
# ARM64 or x86_64 ELFs correctly.
RUN mkdir -p /final && \
    find /install -type f -executable -exec sh -c 'file "$1" | grep -q "ELF" && strip "$1" && cp "$1" /final/' _ {} \;

# FINAL STAGE: Export binaries
FROM scratch
COPY --from=builder /final/ /
