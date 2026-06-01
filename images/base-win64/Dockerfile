# ==========================================
# STAGE 1: OS Dependencies & Host Utilities
# ==========================================
FROM ubuntu:26.04 AS stage-os-base

ARG CARGO_C_VERSION=0.10.22
ARG SHFMT_VERSION="v3.9.0"
ENV DEBIAN_FRONTEND=noninteractive \
    CARGO_HOME="/opt/cargo" \
    RUSTUP_HOME="/opt/rustup" \
    PATH="/opt/cargo/bin:${PATH}" \
    HOST_CC="gcc-14" \
    HOST_CXX="g++-14"

RUN \
    --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    --mount=type=cache,target=/root/.cache/pip \
    apt-get -y update && \
    apt-get -y dist-upgrade && \
    apt-get -y install --no-install-recommends \
        ca-certificates curl gnupg build-essential yasm nasm pv ccache \
        xxd pkgconf wget unzip zip git subversion rsync jq bc \
        autoconf automake libtool libtool-bin gettext qemu-user \
        texinfo texi2html help2man flex bison groff pkg-config \
        gperf itstool ragel autopoint parallel binutils pax-utils file \
        gtk-doc-tools gobject-introspection gawk procps \
        ocaml ocaml-findlib ocamlbuild libnum-ocaml-dev indent zstd \
        python3-setuptools python3-pip python3-venv python3-jinja2 python3-jsonschema python3-apt python3-dev python-is-python3 \
        gcc-14 g++-14 dos2unix re2c bsdmainutils p7zip-full tree \
        patchutils ed osslsigncode python3-fonttools python3-mako \
        python3-wheel iputils-ping dnsutils && \
    \
    pip3 install --break-system-packages --upgrade --ignore-installed \
        meson cmake ninja Cython pytest build PythonLibs && \
    \
    update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-14 100 && \
    update-alternatives --install /usr/bin/cc cc /usr/bin/gcc-14 100 && \
    update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-14 100 && \
    update-alternatives --install /usr/bin/c++ c++ /usr/bin/g++-14 100 && \
    \
    curl -fsSL https://deb.nodesource.com/setup_24.x | bash - && \
    apt-get -y install nodejs && \
    npm install -g @napi-ffi/ffi-napi && \
    \
    git config --global user.email "builder@localhost" && \
    git config --global user.name "Builder" && \
    git config --global advice.detachedHead false && \
    git config --global core.autocrlf false && \
    git config --global --add safe.directory "*" && \
    \
    curl https://sh.rustup.rs -sSf | bash -s -- -y --no-modify-path && \
    curl -fsSL "https://github.com/lu-zero/cargo-c/releases/download/v${CARGO_C_VERSION}/cargo-c-x86_64-unknown-linux-musl.tar.gz" | tar -xz -C /opt/cargo/bin && \
    \
    apt-get -y clean && \
    npm cache clean --force && \
    rm -rf /opt/cargo/registry /opt/cargo/git /opt/rustup/downloads /opt/rustup/tmp && \
    rm -rf /usr/share/doc/* /usr/share/man/* /usr/share/info/* && \
    rm -rf /var/lib/apt/lists/*

# ==========================================
# STAGE 2: Toolchain Compilation (Isolating Waste)
# ==========================================
FROM stage-os-base AS stage-toolchain-builder

RUN --mount=src=images/base-win64/ct-ng-config,dst=/.config \
    git clone --filter=blob:none --depth=1 https://github.com/crosstool-ng/crosstool-ng.git /ct-ng && \
    cd /ct-ng && \
    ./bootstrap && \
    ./configure --enable-local && \
    make -j$(nproc) && \
    cp /.config .config && \
    ./ct-ng build && \
    \
    echo "Cleaning up toolchain artifacts..." && \
    # Удаляем документацию, мануалы и локали из готового тулчейна
    rm -rf /opt/ct-ng/share/doc /opt/ct-ng/share/info /opt/ct-ng/share/man /opt/ct-ng/share/locale && \
    # Вырезаем отладочную информацию (strip) из всех бинарников компилятора
    find /opt/ct-ng/bin /opt/ct-ng/libexec /opt/ct-ng/x86_64-w64-mingw32/bin -type f -executable -exec strip --strip-all {} + 2>/dev/null || true

# ==========================================
# STAGE 3: Final Clean Image
# ==========================================
FROM stage-os-base AS stage-final

ARG CPU_ARCH=broadwell
ARG CPU_TUNE=broadwell

# Copy ONLY the finalized toolchain binary tree, leaving all ct-ng sources behind
COPY --from=stage-toolchain-builder /opt/ct-ng /opt/ct-ng

RUN mkdir -p /opt/ffbuild /opt/ffdest

# Install custom scripts from the repo addins root
RUN --mount=src=addins,dst=/input \
    for s in /input/*.sh; do \
        dest="/usr/bin/$(basename $s .sh)"; \
        cp "$s" "$dest" && chmod +x "$dest" && dos2unix "$dest"; \
    done

SHELL ["/bin/bash", "-l", "-c"]

ENV \
    TOOLCHAIN_BIN="/opt/ct-ng/bin" \
    TOOLCHAIN_INTERNAL="/opt/ct-ng/x86_64-w64-mingw32/bin" \
    FFBUILD_TOOLCHAIN=x86_64-w64-mingw32 \
    FFBUILD_RUST_TARGET=x86_64-pc-windows-gnu \
    CPU_ARCH="${CPU_ARCH}" \
    CPU_TUNE="${CPU_TUNE}" \
    PATH="/opt/ct-ng/bin:/opt/cargo/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    CCACHE_PATH="/opt/ct-ng/bin:/usr/bin" \
    CCACHE_DIR=/root/.cache/ccache \
    CCACHE_MAXSIZE=4G \
    CCACHE_SLOPPINESS="include_file_ctime,include_file_mtime,locale,time_macros,file_macro,pch_defines" \
    CCACHE_BASEDIR="/builder" \
    CCACHE_COMPILERCHECK="content" \
    CCACHE_DEPEND=1 \
    CCACHE_COMPRESS=1 \
    CCACHE_NOHASHDIR=1 \
    FFBUILD_TARGET_FLAGS="--pkg-config=pkgconf --cross-prefix=x86_64-w64-mingw32- --arch=x86_64 --target-os=mingw32" \
    FFBUILD_CROSS_PREFIX=x86_64-w64-mingw32- \
    FFBUILD_PREFIX=/opt/ffbuild \
    FFBUILD_DESTDIR=/opt/ffdest \
    FFBUILD_DESTPREFIX=/opt/ffdest/opt/ffbuild \
    FFBUILD_CMAKE_TOOLCHAIN=/toolchain.cmake \
    PKG_CONFIG="pkgconf" \
    PKG_CONFIG_LIBDIR="/opt/ffbuild/lib/pkgconfig:/opt/ffbuild/share/pkgconfig" \
    PKG_CONFIG_SYSROOT_DIR="/" \
    PKG_CONFIG_ALLOW_SYSTEM_CFLAGS=0 \
    PKG_CONFIG_ALLOW_SYSTEM_LIBS=0 \
    CHOST="x86_64-w64-mingw32" \
    CC="ccache x86_64-w64-mingw32-gcc" \
    CXX="ccache x86_64-w64-mingw32-g++" \
    AR="x86_64-w64-mingw32-gcc-ar" \
    NM="x86_64-w64-mingw32-gcc-nm" \
    RANLIB="x86_64-w64-mingw32-gcc-ranlib" \
    LD="x86_64-w64-mingw32-ld" \
    STRIP="x86_64-w64-mingw32-strip" \
    WINDRES="x86_64-w64-mingw32-windres" \
    DLLTOOL="x86_64-w64-mingw32-dlltool" \
    OBJDUMP="x86_64-w64-mingw32-objdump" \
    GENDEF="x86_64-w64-mingw32-gendef"

# Inject toolchain configuration profiles
COPY images/base-win64/toolchain.cmake /toolchain.cmake
COPY images/base-win64/cross.meson /cross.meson

RUN rustup target add "$FFBUILD_RUST_TARGET" && \
    printf "[target.%s]\nlinker = \"%s-gcc\"\nar = \"%s-gcc-ar\"\n" "$FFBUILD_RUST_TARGET" "$FFBUILD_TOOLCHAIN" "$FFBUILD_TOOLCHAIN" > "$CARGO_HOME"/config.toml
