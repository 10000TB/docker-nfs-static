# syntax=docker/dockerfile:1
ARG ARCH=amd64
FROM ${ARCH}/alpine:3.19 AS builder

# 1. Install build tools and headers
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
RUN ./configure \
    --prefix=/usr \
    --sysconfdir=/etc \
    --sbindir=/sbin \
    --disable-gss \
    --disable-nfsv41 \
    --disable-ipv6 \
    --disable-reexport \
    --disable-nfsdcltrack \
    --disable-nfsdcld \
    --without-tcp-wrappers \
    --with-tirpcinclude=/usr/include/tirpc \
    --enable-static \
    --disable-shared

# 7. Build
RUN make -j$(nproc) \
    LDFLAGS="-all-static" \
    CFLAGS="-static -Wno-error" \
    LIBS="-ltirpc -levent_core -levent -lblkid -luuid -lsqlite3 -lattr -lz -lpthread /usr/lib/libkeyutils.a"

# 8. Install to a temporary directory
RUN make install DESTDIR=/install

# 9. CONSOLIDATION STEP: 
# Find actual ELF binaries, strip them, and move them to a flat /final folder.
# This avoids the "file format not recognized" errors on scripts.
RUN mkdir -p /final && \
    find /install -type f -executable -exec sh -c 'file "$1" | grep -q "ELF" && strip "$1" && cp "$1" /final/' _ {} \;

# FINAL STAGE: Export binaries
FROM scratch
COPY --from=builder /final/ /
