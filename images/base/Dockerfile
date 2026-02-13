FROM ubuntu:24.04

ARG TARGETPLATFORM

ENV DEBIAN_FRONTEND=noninteractive
RUN \
    apt-get -y update && \
    apt-get -y dist-upgrade && \
    apt-get -y install --no-install-recommends \
        $([ "$TARGETPLATFORM" != "linux/amd64" ] || echo gcc-multilib g++-multilib) \
        build-essential yasm nasm ccache \
        xxd pkgconf curl wget unzip zip git subversion mercurial rsync jq \
        autoconf automake libtool libtool-bin autopoint gettext cmake meson ninja-build \
        clang llvm lcov lld qemu-user \
        texinfo texi2html help2man flex bison groff \
        gperf itstool ragel libc6-dev zlib1g-dev libssl-dev \
        gtk-doc-tools gobject-introspection gawk \
        ocaml ocaml-findlib ocamlbuild libnum-ocaml-dev indent p7zip-full zstd \
        python3-setuptools python3-pip python3-venv python3-jinja2 python3-jsonschema python3-apt python3-dev python-is-python3 \
        gcc-14 g++-14 && \
    update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-14 100 --slave /usr/bin/cc cc /usr/bin/gcc-14 && \
    update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-14 100 --slave /usr/bin/c++ c++ /usr/bin/g++-14 && \
    curl -fsSL https://deb.nodesource.com/setup_24.x | bash - && \
    apt-get -y install nodejs && \
    apt-get -y clean && \
    git config --global user.email "builder@localhost" && \
    git config --global user.name "Builder" && \
    git config --global advice.detachedHead false

ENV CARGO_HOME="/opt/cargo" RUSTUP_HOME="/opt/rustup" PATH="/opt/cargo/bin:${PATH}"
RUN curl https://sh.rustup.rs -sSf | bash -s -- -y --no-modify-path && \
    # Динамическое получение последней версии через GitHub API
    export CARGO_C_URL=$(curl -fsSL https://api.github.com/repos/lu-zero/cargo-c/releases/latest | \
    jq -r '.assets[] | select(.name | test("x86_64-unknown-linux-musl\\.tar\\.gz$")) | .browser_download_url') && \
    curl -fsSL "$CARGO_C_URL" | tar -xz -C /opt/cargo/bin && \
    # Очистка кэша Rust
    rm -rf "${CARGO_HOME}"/registry "${CARGO_HOME}"/git

RUN --mount=src=.,dst=/input \
    for s in /input/*.sh; do cp $s /usr/bin/$(echo $s | sed -e 's|.*/||' -e 's/\.sh$//'); done

ENV HOST_CC="gcc-14" \
    HOST_CXX="g++-14" \
    HOST_CFLAGS="-O2 -pipe" \
    HOST_CXXFLAGS="-O2 -pipe"
