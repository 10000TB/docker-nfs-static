# Statically Linked NFS Utils


## Install & Build

Simply checkout this repo, and run oneliner docker build.

```
$ git clone git@github.com:10000TB/docker-nfs-static.git
```

## Steps

1. within repo root, create a bin folder, `mkdir bin/`.

2. Build: simply run, `docker build --output type=local,dest=./bin .`

```
$ docker build --output type=local,dest=./bin .
[+] Building 1.5s (20/20) FINISHED                                                                                                      docker:default
 => [internal] load build definition from Dockerfile                                                                                              0.0s
 => => transferring dockerfile: 2.69kB                                                                                                            0.0s
 => resolve image config for docker-image://docker.io/docker/dockerfile:1                                                                         0.6s
 => CACHED docker-image://docker.io/docker/dockerfile:1@sha256:2780b5c3bab67f1f76c781860de469442999ed1a0d7992a5efdf2cffc0e3d769                   0.0s
 => [internal] load metadata for docker.io/amd64/alpine:3.19                                                                                      0.7s
 => [internal] load .dockerignore                                                                                                                 0.0s
 => => transferring context: 2B                                                                                                                   0.0s
 => [builder  1/13] FROM docker.io/amd64/alpine:3.19@sha256:96dabac40b2aacac21d3b6d36a635697b9867b0955aa4fb8e7f177f6e1df127a                      0.0s
 => CACHED [builder  2/13] RUN apk add --no-cache     build-base     autoconf     automake     libtool     pkgconf     util-linux-dev     util-l  0.0s
 => CACHED [builder  3/13] WORKDIR /src                                                                                                           0.0s
 => CACHED [builder  4/13] RUN curl -L https://git.kernel.org/pub/scm/linux/kernel/git/dhowells/keyutils.git/snapshot/keyutils-1.6.3.tar.gz | ta  0.0s
 => CACHED [builder  5/13] RUN curl -L https://downloads.sourceforge.net/project/libtirpc/libtirpc/1.3.4/libtirpc-1.3.4.tar.bz2 | tar -xj &&      0.0s
 => CACHED [builder  6/13] WORKDIR /src                                                                                                           0.0s
 => CACHED [builder  7/13] RUN curl -L https://www.kernel.org/pub/linux/utils/nfs-utils/2.6.4/nfs-utils-2.6.4.tar.xz | tar -xJ                    0.0s
 => CACHED [builder  8/13] WORKDIR /src/nfs-utils-2.6.4                                                                                           0.0s
 => CACHED [builder  9/13] RUN sed -i '1i #include <unistd.h>' support/reexport/reexport.c &&     sed -i '1i #include <unistd.h>' support/reexpo  0.0s
 => CACHED [builder 10/13] RUN ./configure     --prefix=/usr     --sysconfdir=/etc     --sbindir=/sbin     --disable-gss     --disable-nfsv41     0.0s
 => CACHED [builder 11/13] RUN make -j$(nproc)     LDFLAGS="-all-static"     CFLAGS="-static -Wno-error"     LIBS="-ltirpc -levent_core -levent   0.0s
 => CACHED [builder 12/13] RUN make install DESTDIR=/install                                                                                      0.0s
 => CACHED [builder 13/13] RUN mkdir -p /final &&     find /install -type f -executable -exec sh -c 'file "$1" | grep -q "ELF" && strip "$1" &&   0.0s
 => CACHED [stage-1 1/1] COPY --from=builder /final/ /                                                                                            0.0s
 => exporting to client directory                                                                                                                 0.0s
 => => copying files 4.58MB       
```

3. Statically linked NFS utils will be available under `./bin` folder.

```
xuehaohu@worldpeace10:~/BUILD-RDMA/docker-nfs$ ls bin
exportfs  fsidd  mount.nfs  nfsconf  nfsidmap  nfsrahead  nfsstat  rpcdebug  rpc.idmapd  rpc.mountd  rpc.nfsd  rpc.statd  showmount  sm-notify
xuehaohu@worldpeace10:~/BUILD-RDMA/docker-nfs$ file bin/*
bin/exportfs:   ELF 64-bit LSB executable, x86-64, version 1 (SYSV), statically linked, BuildID[sha1]=03ecc2d1f620ea74f511344de8566419911f545b, stripped
bin/fsidd:      ELF 64-bit LSB executable, x86-64, version 1 (SYSV), statically linked, BuildID[sha1]=27f26b676b6369002da83afc4ddeb838c36d9002, stripped
bin/mount.nfs:  setuid ELF 64-bit LSB executable, x86-64, version 1 (SYSV), statically linked, BuildID[sha1]=92932d54c7f07e9b5beae84ea144a5b9cfb59335, stripped
bin/nfsconf:    ELF 64-bit LSB executable, x86-64, version 1 (SYSV), statically linked, BuildID[sha1]=63bcc6efd744bc594fee0a46f9a54fb5cd0cb8d1, stripped
bin/nfsidmap:   ELF 64-bit LSB executable, x86-64, version 1 (SYSV), statically linked, BuildID[sha1]=310773211ccfbf4da8aa8a46a30605662f2dfd09, stripped
bin/nfsrahead:  ELF 64-bit LSB executable, x86-64, version 1 (SYSV), statically linked, BuildID[sha1]=01b09595c4547aa3acd392531ae774a240af05b1, stripped
bin/nfsstat:    ELF 64-bit LSB executable, x86-64, version 1 (SYSV), statically linked, BuildID[sha1]=a5f161c198f3d3b1be813303b2a601e65bc8cf7e, stripped
bin/rpcdebug:   ELF 64-bit LSB executable, x86-64, version 1 (SYSV), statically linked, BuildID[sha1]=7cb9bc1a394a7c2f7f6df797c7e670005249cc42, stripped
bin/rpc.idmapd: ELF 64-bit LSB executable, x86-64, version 1 (SYSV), statically linked, BuildID[sha1]=520fa02d4e80aae445920ebcfa4d1b83d1fdf23a, stripped
bin/rpc.mountd: ELF 64-bit LSB executable, x86-64, version 1 (SYSV), statically linked, BuildID[sha1]=7f46037c667bb2269c84ecebf5172bacc06a4a32, stripped
bin/rpc.nfsd:   ELF 64-bit LSB executable, x86-64, version 1 (SYSV), statically linked, BuildID[sha1]=0dce4cc36e8026fb496fd284311818c0c5f87ae5, stripped
bin/rpc.statd:  ELF 64-bit LSB executable, x86-64, version 1 (SYSV), statically linked, BuildID[sha1]=55eed3ae32857d8174a9e3548c081e58265ba502, stripped
bin/showmount:  ELF 64-bit LSB executable, x86-64, version 1 (SYSV), statically linked, BuildID[sha1]=77e5d0a10218590ca6bada23310d6dabbd91bfe7, stripped
bin/sm-notify:  ELF 64-bit LSB executable, x86-64, version 1 (SYSV), statically linked, BuildID[sha1]=221a6ea631cd3f18e793812ff5c7527bce45b1ce, stripped
xuehaohu@worldpeace10:~/BUILD-RDMA/docker-nfs$
```
