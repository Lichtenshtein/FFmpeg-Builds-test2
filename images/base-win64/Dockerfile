# ==========================================
# STAGE 1: OS Dependencies & Host Utilities
# ==========================================
FROM ubuntu:26.04 AS stage-os-base

ARG CARGO_C_VERSION=0.10.24
ARG DEBUG_MODE=0
ARG USE_WINE=0

ENV DEBIAN_FRONTEND=noninteractive \
    CARGO_HOME="/opt/cargo" \
    RUSTUP_HOME="/opt/rustup" \
    PATH="/opt/cargo/bin:${PATH}" \
    HOST_CC="gcc-15" \
    HOST_CXX="g++-15"

RUN \
    apt-get -y update && \
    apt-get -y dist-upgrade && \
    echo "✅ Updating completed successfully" && \
    echo "🔧 Installing dependencies" && \
    apt-get -y install --no-install-recommends \
        ca-certificates curl gnupg build-essential yasm nasm pv \
        xxd pkgconf wget unzip zip git subversion rsync jq bc \
        autoconf automake libtool libtool-bin gettext qemu-user \
        texinfo texi2html help2man flex bison groff pkg-config \
        gperf itstool ragel autopoint parallel binutils pax-utils file \
        gtk-doc-tools gobject-introspection gawk procps \
        ocaml ocaml-findlib ocamlbuild libnum-ocaml-dev indent zstd \
        python3-setuptools python3-pip python3-venv python3-jinja2 python3-jsonschema python3-apt python3-dev python-is-python3 \
        dos2unix re2c bsdmainutils p7zip-full tree \
        patchutils ed osslsigncode python3-fonttools python3-mako \
        python3-wheel iputils-ping dnsutils libtasn1-bin \
        $([ "$DEBUG_MODE" = "1" ] || [ "$USE_WINE" = "1" ] && echo wine) >/dev/null 2>&1 && \
    \
    rm -f /etc/apt/sources.list.d/llvm-trunk.list && \
    DOMAIN_LLVM="apt.llvm.org" && \
    curl -fsSL https://${DOMAIN_LLVM}/llvm-snapshot.gpg.key | tee /etc/apt/trusted.gpg.d/apt.llvm.org.asc && \
    echo "Types: deb" > /etc/apt/sources.list.d/llvm-trunk.sources && \
    echo "URIs: https://${DOMAIN_LLVM}/resolute/" >> /etc/apt/sources.list.d/llvm-trunk.sources && \
    echo "Suites: llvm-toolchain-resolute" >> /etc/apt/sources.list.d/llvm-trunk.sources && \
    echo "Components: main" >> /etc/apt/sources.list.d/llvm-trunk.sources && \
    echo "Signed-By: /etc/apt/trusted.gpg.d/apt.llvm.org.asc" >> /etc/apt/sources.list.d/llvm-trunk.sources && \
    apt-get -y update >/dev/null 2>&1 && \
    \
    echo "🔧 Installing latest LLD, Clang, Flang, and LLVM packages" && \
    apt-get -y install --no-install-recommends lld-23 clang-23 llvm-23 flang-23 && \
    ln -sf /usr/bin/ld.lld-23 /usr/bin/ld.lld && \
    ln -sf /usr/bin/clang-23 /usr/bin/clang && \
    ln -sf /usr/bin/clang++-23 /usr/bin/clang++ && \
    ln -sf /usr/bin/llvm-config-23 /usr/bin/llvm-config && \
    ln -sf /usr/bin/flang-23 /usr/bin/flang && \
    \
    MOLD_VERSION=$(curl -fL "https://api.github.com/repos/rui314/mold/releases/latest" | jq -r .tag_name | sed 's/^v//') && \
    echo "=== Mold version found: ${MOLD_VERSION} ===" && \
    curl -fL -o mold.tar.gz "https://github.com/rui314/mold/releases/latest/download/mold-${MOLD_VERSION}-x86_64-linux.tar.gz" && \
    echo "✅ Download complete. Creating directory..." && \
    mkdir -p /opt/mold && \
    echo "=== Unpacking archive (file list): ===" && \
    tar -x -f mold.tar.gz --strip-components=1 -C /opt/mold && \
    echo "🧹 Removing archive:" && \
    rm mold.tar.gz && \
    echo "✅ Version check:" && \
    /opt/mold/bin/mold --version && \
    \
    echo "🔄 Downloading latest Ccache static binary (x86_64)..." && \
    DOMAIN_CC="github.com" && \
    CCACHE_LATEST_TAG=$(curl -sIL -o /dev/null -w '%{url_effective}' "https://${DOMAIN_CC}/ccache/ccache/releases/latest" | awk -F'/' '{print $NF}') && \
    echo "=== Ccache version found: ${CCACHE_LATEST_TAG} ===" && \
    curl -fL -o ccache.tar.xz "https://${DOMAIN_CC}/ccache/ccache/releases/download/${CCACHE_LATEST_TAG}/ccache-${CCACHE_LATEST_TAG#v}-linux-x86_64-glibc.tar.xz" && \
    mkdir -p /tmp/ccache_unpack && \
    tar -xJf ccache.tar.xz -C /tmp/ccache_unpack --strip-components=1 && \
    mv /tmp/ccache_unpack/ccache /usr/local/bin/ccache && \
    chmod +x /usr/local/bin/ccache && \
    rm -rf ccache.tar.xz /tmp/ccache_unpack && \
    echo "✅ Ccache upgraded successfully:" && \
    /usr/local/bin/ccache --version && \
    \
    echo "🔄 Installing Meson & Ninja via pip" && \
    pip3 install --break-system-packages --no-cache-dir --upgrade --ignore-installed \
        meson cmake ninja Cython pytest build && \
    \
    curl -fsSL https://deb.nodesource.com/setup_24.x | bash - && \
    apt-get -y install nodejs && \
    npm install -g @napi-ffi/ffi-napi && \
    \
    echo "🔄 Configuring Git" && \
    git config --global user.email "builder@localhost" && \
    git config --global user.name "Builder" && \
    git config --global advice.detachedHead false && \
    git config --global core.autocrlf false && \
    git config --global --add safe.directory "*" && \
    \
    echo "🔄 Start downloading and installing Rust and Cargo" && \
    curl https://sh.rustup.rs -sSf | bash -s -- -y --no-modify-path && \
    curl -fsSL "https://github.com/lu-zero/cargo-c/releases/download/v${CARGO_C_VERSION}/cargo-c-x86_64-unknown-linux-musl.tar.gz" | tar -xz -C /opt/cargo/bin && \
    echo "✅ Installations completed successfully" && \
    \
    echo "🧹 Cleaning up..." && \
    apt-get autoremove -y >/dev/null 2>&1 && \
    apt-get autoclean -y >/dev/null 2>&1 && \
    apt-get clean -y >/dev/null 2>&1 && \
    npm cache clean --force && \
    rm -rf \
        /opt/cargo/registry \
        /opt/cargo/git \
        /opt/rustup/downloads \
        /opt/rustup/tmp \
        \
        /usr/share/doc/* \
        /usr/share/man/* \
        /usr/share/info/* \
        /usr/share/groff/* \
        /usr/share/lintian/* \
        /usr/share/locale/* \
        /var/cache/debconf/*-old \
        /var/cache/apk/* \
        /root/.cache/* \
        /var/lib/apt/lists/* \
        /var/cache/apt/archives/* \
        /tmp/* \
        /var/tmp/* \
        /var/log/apt/* \
        /var/log/dpkg.log \
        /var/log/alternatives.log \
        /var/tmp/* \
        /root/.npm/_cacache

# ==========================================
# STAGE 2: Toolchain Compilation (Isolating Waste)
# ==========================================
FROM ubuntu:26.04 AS stage-toolchain-builder

COPY images/base-win64/ct-ng-config /.config

RUN \
    apt-get -y update && apt-get -y install --no-install-recommends git ca-certificates build-essential bison flex texinfo help2man gawk libtool-bin libtool automake autoconf libncurses-dev python3-dev unzip && \
    git clone --filter=blob:none --depth=1 https://github.com/crosstool-ng/crosstool-ng.git /ct-ng && \
    cd /ct-ng && \
    ./bootstrap && \
    ./configure --enable-local && \
    make -j$(nproc) && \
    cp /.config .config && \
    \
    ./ct-ng build && \
    \
    echo "🧹 Cleaning up toolchain artifacts..." && \
    # Remove documentation, manuals, and locales from the finished toolchain
    rm -rf /ct-ng/.obj /ct-ng/.build /ct-ng/src /ct-ng/build && \
    rm -rf /opt/ct-ng/share/doc /opt/ct-ng/share/info /opt/ct-ng/share/man /opt/ct-ng/share/locale

# ==========================================
# STAGE 3: Final Clean Image
# ==========================================
FROM stage-os-base AS stage-final

ARG CPU_ARCH=${CPU_TUNE:-broadwell}
ARG CPU_TUNE=${CPU_ARCH:-broadwell}

# Copy ONLY the finalized toolchain binary tree, leaving all ct-ng sources behind
COPY --from=stage-toolchain-builder /opt/ct-ng /opt/ct-ng

RUN mkdir -p /opt/ffbuild /opt/ffdest

# Install custom scripts from the repo addins root
COPY addins/ /opt/addins/
RUN for s in /opt/addins/*.sh; do \
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
    PATH="/opt/mold/bin:/opt/ct-ng/bin:/opt/cargo/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    FFBUILD_CROSS_PREFIX=x86_64-w64-mingw32-

RUN rustup target add "$FFBUILD_RUST_TARGET" && \
    printf "[target.%s]\nlinker = \"%s-gcc\"\nar = \"%s-gcc-ar\"\n" "$FFBUILD_RUST_TARGET" "$FFBUILD_TOOLCHAIN" "$FFBUILD_TOOLCHAIN" > "$CARGO_HOME"/config.toml && \
    \
    mkdir -p /opt/ccache-links && \
    for tool in gcc g++ cpp c++ gcc-ar gcc-nm gcc-ranlib ranlib clang clang++ flang; do \
        ln -sf /usr/local/bin/ccache "/opt/ccache-links/x86_64-w64-mingw32-${tool}"; \
        ln -sf /usr/local/bin/ccache "/opt/ccache-links/${tool}"; \
    done && \
    \
    ln -sf /usr/bin/llvm-config /opt/ccache-links/llvm-config && \
    \
    printf '#!/bin/bash\nexec /usr/local/bin/ccache /usr/bin/flang-23 --target=x86_64-w64-mingw32 "$@"\n' > /opt/ccache-links/x86_64-w64-mingw32-gfortran && \
    chmod +x /opt/ccache-links/x86_64-w64-mingw32-gfortran && \
    \
    ln -sfn /opt/ccache-links/x86_64-w64-mingw32-gfortran /opt/ccache-links/gfortran
