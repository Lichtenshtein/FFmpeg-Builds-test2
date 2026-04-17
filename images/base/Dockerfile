FROM ubuntu:24.04

ARG CARGO_C_VERSION=0.10.20
ARG TARGETPLATFORM
ARG SHFMT_VERSION="v3.9.0"

ENV DEBIAN_FRONTEND=noninteractive

RUN \
    --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    --mount=type=cache,target=/root/.cache/pip \
    apt-get -y update && \
    apt-get -y dist-upgrade && \
    apt-get -y install --no-install-recommends \
        $([ "$TARGETPLATFORM" != "linux/amd64" ] || echo gcc-multilib g++-multilib) \
        ca-certificates curl gnupg build-essential pkg-config binutils pax-utils file yasm nasm pv ccache \
        xxd pkgconf wget unzip zip git subversion mercurial rsync jq bc \
        autoconf automake libtool libtool-bin autopoint parallel gettext cmake meson ninja-build \
        clang llvm lcov lld qemu-user libunwind-dev \
        clang-tidy clang-format cppcheck \
        texinfo texi2html help2man flex bison groff \
        gperf itstool ragel libc6-dev zlib1g-dev libssl-dev \
        gtk-doc-tools gobject-introspection gawk procps \
        ocaml ocaml-findlib ocamlbuild libnum-ocaml-dev indent p7zip-full zstd \
        python3-setuptools python3-pip python3-venv python3-jinja2 python3-jsonschema python3-apt python3-dev python-is-python3 \
        python3-numpy libdlpack-dev \
        gcc-14 g++-14 dos2unix re2c bsdmainutils tree \
        doxygen shellcheck \
        libavcodec-dev libavformat-dev libavutil-dev libswscale-dev libavfilter-dev \
        nvidia-cuda-dev nvidia-cuda-toolkit && \
    \
    curl -fsSL -o /usr/local/bin/shfmt \
      "https://github.com/mvdan/sh/releases/download/${SHFMT_VERSION}/shfmt_${SHFMT_VERSION}_linux_amd64" && \
    chmod +x /usr/local/bin/shfmt && \
    \
    pip3 install --break-system-packages --upgrade --ignore-installed \
        meson cmake ninja Cython pytest build numpy \
        pre-commit ruff black isort mypy semgrep && \
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
    git config --global --add safe.directory "*"

ENV \
    CARGO_HOME="/opt/cargo" \
    RUSTUP_HOME="/opt/rustup" \
    PATH="/opt/cargo/bin:${PATH}" \
    HOST_CC="gcc-14" \
    HOST_CXX="g++-14"

RUN curl https://sh.rustup.rs -sSf | bash -s -- -y --no-modify-path && \
    curl -fsSL "https://github.com/lu-zero/cargo-c/releases/download/v${CARGO_C_VERSION}/cargo-c-x86_64-unknown-linux-musl.tar.gz" | tar -xz -C /opt/cargo/bin && \
    \
    apt-get -y clean && \
    npm cache clean --force && \
    rm -rf /opt/cargo/registry /opt/cargo/git && \
    rm -rf /usr/share/doc/* /usr/share/man/* /usr/share/info/* && \
    rm -rf /var/lib/apt/lists/*

RUN --mount=src=.,dst=/input \
    for s in /input/*.sh; do \
        dest="/usr/bin/$(basename $s .sh)"; \
        cp "$s" "$dest" && chmod +x "$dest" && dos2unix "$dest"; \
    done

# Создаем ссылки на то, что РЕАЛЬНО есть в системе (судя по dpkg -L)
