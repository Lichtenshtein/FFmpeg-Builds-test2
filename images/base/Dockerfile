FROM ubuntu:24.04

ARG CARGO_C_VERSION=0.10.20
ARG TARGETPLATFORM

ENV DEBIAN_FRONTEND=noninteractive

RUN \
    --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    --mount=type=cache,target=/root/.cache/pip \
    apt-get -y update && \
    apt-get -y dist-upgrade && \
    \
    apt-get -y install --no-install-recommends \
        $([ "$TARGETPLATFORM" != "linux/amd64" ] || echo gcc-multilib g++-multilib) \
        build-essential pkg-config binutils pax-utils ca-certificates curl gnupg file yasm nasm pv ccache \
        xxd pkgconf wget unzip zip git subversion mercurial rsync jq bc \
        autoconf automake libtool libtool-bin autopoint parallel gettext cmake meson ninja-build \
        clang llvm lcov lld qemu-user libunwind-dev \
        texinfo texi2html help2man flex bison groff \
        gperf itstool ragel libc6-dev zlib1g-dev libssl-dev \
        gtk-doc-tools gobject-introspection gawk procps \
        ocaml ocaml-findlib ocamlbuild libnum-ocaml-dev indent p7zip-full zstd \
        python3-setuptools python3-pip python3-venv python3-jinja2 python3-jsonschema python3-apt python3-dev python-is-python3 \
        python3-numpy libdlpack-dev \
        gcc-14 g++-14 dos2unix re2c bsdmainutils tree \
        freeglut3-dev libglu1-mesa-dev mesa-common-dev \
        wine64 wine-binfmt xvfb && \
    \
    pip3 install --break-system-packages --upgrade meson cmake ninja && \
    pip3 install Cython pytest build tbb-devel --break-system-packages && \
    update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-14 100 && \
    update-alternatives --install /usr/bin/cc cc /usr/bin/gcc-14 100 && \
    update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-14 100 && \
    update-alternatives --install /usr/bin/c++ c++ /usr/bin/g++-14 100 && \
    \
    curl -fsSL https://deb.nodesource.com/setup_24.x | bash - && \
    apt-get -y install nodejs && \
    npm install -g @napi-ffi/ffi-napi && \
    \
    apt-get -y clean && rm -rf /var/lib/apt/lists/* && \
    \
    git config --global user.email "builder@localhost" && \
    git config --global user.name "Builder" && \
    git config --global advice.detachedHead false && \
    git config --global core.autocrlf false && \
    git config --global --add safe.directory "*"

# Настройки среды
ENV \
    CARGO_HOME="/opt/cargo" RUSTUP_HOME="/opt/rustup" PATH="/opt/cargo/bin:${PATH}" \
    HOST_CC="gcc-14" \
    HOST_CXX="g++-14" \
    # Базовые настройки Wine
    WINEARCH=win64 \
    WINEPREFIX="/root/.wine" \
    DISPLAY=:99 \
    WINEDEBUG=-all \
    WINEDLLOVERRIDES="mscoree,mshtml=" \
    WINE_BIN_DIR="/usr/bin"

RUN curl https://sh.rustup.rs -sSf | bash -s -- -y --no-modify-path && \
    curl -fsSL "https://github.com/lu-zero/cargo-c/releases/download/v${CARGO_C_VERSION}/cargo-c-x86_64-unknown-linux-musl.tar.gz" | tar -xz -C /opt/cargo/bin

RUN --mount=src=.,dst=/input \
    for s in /input/*.sh; do \
        dest="/usr/bin/$(basename $s .sh)"; \
        cp "$s" "$dest" && chmod +x "$dest" && dos2unix "$dest"; \
    done

# Создаем ссылки на то, что РЕАЛЬНО есть в системе (судя по dpkg -L)
RUN set -e; \
    mkdir -p "$WINEPREFIX"; \
    ln -sf /usr/bin/wine64 /usr/bin/wine; \
    ln -sf /usr/lib/x86_64-linux-gnu/libglut.so.3.12.0 /usr/lib/x86_64-linux-gnu/libglut.so.3; \
    \
    echo "Checking Wine version:"; \
    wine64 --version; \
    \
    echo "Initializing Wine Win64 prefix in $WINEPREFIX..."; \
    xvfb-run -n 99 -s "-screen 0 1024x768x16" \
        sh -c "wine64 wineboot --init && wineserver -w"; \
    \
    rm -rf /tmp/.X11-unix/X99
