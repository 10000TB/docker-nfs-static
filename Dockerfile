# syntax=docker/dockerfile:1
ARG ARCH=amd64
FROM ${ARCH}/alpine:3.19 AS builder

# 1. Install build tools and RDMA development headers
RUN apk add --no-cache \
    build-base autoconf automake libtool pkgconf util-linux-dev util-linux-static \
    libtirpc-dev libtirpc-static libcap-dev libcap-static libevent-dev libevent-static \
    sqlite-dev sqlite-static keyutils-dev rpcsvc-proto xz curl zlib-static attr-dev \
    attr-static libnsl-dev linux-headers bsd-compat-headers file \
    rdma-core-dev lvm2-dev device-mapper-static libaio-dev eudev-dev

WORKDIR /src

# 2. Build KEYUTILS from source (Ensure libkeyutils.a exists)
RUN curl -L https://git.kernel.org/pub/scm/linux/kernel/git/dhowells/keyutils.git/snapshot/keyutils-1.6.3.tar.gz | tar -xz && \
    cd keyutils-1.6.3 && \
    make libkeyutils.a CFLAGS="-static -fPIC" && \
    cp libkeyutils.a /usr/lib/ && cp keyutils.h /usr/include/

# 3. Build CUSTOM LIBTIRPC (Forced IPv6, No GSS)
RUN curl -L https://downloads.sourceforge.net/project/libtirpc/libtirpc/1.3.4/libtirpc-1.3.4.tar.bz2 | tar -xj && \
    cd libtirpc-1.3.4 && \
    ./configure --prefix=/usr --disable-gssapi --enable-ipv6 --enable-static --disable-shared && \
    make -j$(nproc) && make install

# 4. Download and Build NFS-UTILS 2.6.4
RUN curl -L https://www.kernel.org/pub/linux/utils/nfs-utils/2.6.4/nfs-utils-2.6.4.tar.xz | tar -xJ
WORKDIR /src/nfs-utils-2.6.4

# Patch for Musl/Alpine
RUN sed -i '1i #include <unistd.h>' support/reexport/reexport.c && \
    sed -i '1i #include <unistd.h>' support/reexport/fsidd.c

# 5. Configure with IPv6 and RDMA enabled
RUN ./configure \
    --prefix=/usr --sysconfdir=/etc --sbindir=/sbin \
    --disable-gss --enable-nfsv4 --enable-nfsv41 --enable-ipv6 --enable-rdma \
    --disable-reexport --disable-nfsdcltrack --disable-nfsdcld \
    --with-tirpcinclude=/usr/include/tirpc --enable-static --disable-shared

# 6. Build nfs-utils
RUN make -j$(nproc) \
    LDFLAGS="-all-static" \
    CFLAGS="-static -Wno-error" \
    LIBS="-ltirpc -levent_core -levent -lmount -lblkid -luuid /usr/lib/libdevmapper.a /usr/lib/libudev.a /usr/lib/libaio.a -lsqlite3 -lattr -lz -lpthread /usr/lib/libkeyutils.a"

RUN make install DESTDIR=/install

# 7. Build RPCBIND statically (Required for mountd to register)
WORKDIR /src
RUN curl -L https://downloads.sourceforge.net/project/rpcbind/rpcbind/1.2.6/rpcbind-1.2.6.tar.bz2 | tar -xj && \
    cd rpcbind-1.2.6 && \
    ./configure --prefix=/usr --bindir=/sbin --with-rpcuser=root --enable-warmstarts --enable-ipv6 --with-tirpcinclude=/usr/include/tirpc --without-systemdsystemunitdir && \
    make LDFLAGS="-static" LIBS="-ltirpc -lpthread" && \
    make install DESTDIR=/install

# 8. Consolidation
RUN mkdir -p /final && \
    find /install -type f -executable -exec sh -c 'file "$1" | grep -q "ELF" && strip "$1" && cp "$1" /final/' _ {} \;

FROM scratch
COPY --from=builder /final/ /
