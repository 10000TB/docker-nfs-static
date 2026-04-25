# syntax=docker/dockerfile:1
ARG ARCH=amd64
FROM ${ARCH}/alpine:3.19 AS builder

# 1. Install build tools and headers
# FIX: eudev-dev contains libudev.a; lvm2-dev + device-mapper-static provide libdevmapper.a
RUN apk add --no-cache \
    build-base \
    autoconf \
    automake \
    libtool \
    pkgconf \
    util-linux-dev \
    util-linux-static \
    libtirpc-dev \
    libtirpc-static \
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
RUN curl -L https://git.kernel.org/pub/scm/linux/kernel/git/dhowells/keyutils.git/snapshot/keyutils-1.6.3.tar.gz | tar -xz && \
    cd keyutils-1.6.3 && \
    make libkeyutils.a CFLAGS="-static -fPIC" && \
    cp libkeyutils.a /usr/lib/ && \
    cp keyutils.h /usr/include/

# 3. Build LIBTIRPC from source (WITHOUT GSS support)
RUN curl -L https://downloads.sourceforge.net/project/libtirpc/libtirpc/1.3.4/libtirpc-1.3.4.tar.bz2 | tar -xj && \
    cd libtirpc-1.3.4 && \
    ./configure --prefix=/usr --disable-gssapi --enable-static --disable-shared && \
    make -j$(nproc) && \
    make install

# 4. Download nfs-utils 2.6.4
WORKDIR /src
RUN curl -L https://www.kernel.org/pub/linux/utils/nfs-utils/2.6.4/nfs-utils-2.6.4.tar.xz | tar -xJ

WORKDIR /src/nfs-utils-2.6.4

# 5. FIX SOURCE CODE BUGS
RUN sed -i '1i #include <unistd.h>' support/reexport/reexport.c && \
    sed -i '1i #include <unistd.h>' support/reexport/fsidd.c

# 6. Configure nfs-utils
# - Enabled nfsv4/nfsv41 (supports 4.2)
# - Enabled pnfs/blkmapd explicitly
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
    --disable-nfsdcltrack \
    --disable-nfsdcld \
    --without-tcp-wrappers \
    --with-tirpcinclude=/usr/include/tirpc \
    --enable-static \
    --disable-shared

# 7. Build nfs-utils
# FIX: Using absolute paths for static libraries ensures the linker finds them 
# and avoids "cannot find -ldevmapper" errors during sub-component linking.
RUN make -j$(nproc) \
    LDFLAGS="-all-static" \
    CFLAGS="-static -Wno-error" \
    LIBS="-ltirpc -levent_core -levent -lmount -lblkid -luuid /usr/lib/libdevmapper.a /usr/lib/libudev.a /usr/lib/libaio.a -lsqlite3 -lattr -lz -lpthread /usr/lib/libkeyutils.a"

# 8. Install to a temporary directory
RUN make install DESTDIR=/install

# 8b. Download and Build RPCBIND statically
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
    --with-tirpcinclude=/usr/include/tirpc \
    --without-systemdsystemunitdir

# Build rpcbind with -static
RUN make -j$(nproc) \
    LDFLAGS="-static" \
    CFLAGS="-static -Wno-error" \
    LIBS="-ltirpc -lpthread"

# Install rpcbind to the same temporary directory
RUN make install DESTDIR=/install

# 9. CONSOLIDATION STEP: 
# Find ELF binaries, strip them, and move them to a flat /final folder.
RUN mkdir -p /final && \
    find /install -type f -executable -exec sh -c 'file "$1" | grep -q "ELF" && strip "$1" && cp "$1" /final/' _ {} \;

# FINAL STAGE: Export binaries
FROM scratch
COPY --from=builder /final/ /
