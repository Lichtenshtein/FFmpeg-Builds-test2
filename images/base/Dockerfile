FROM ubuntu:24.04

ARG CARGO_C_VERSION=0.10.20
ARG TARGETPLATFORM

ENV DEBIAN_FRONTEND=noninteractive
RUN \
    apt-get -y update && \
    apt-get -y dist-upgrade && \
    apt-get -y install --no-install-recommends \
        $([ "$TARGETPLATFORM" != "linux/amd64" ] || echo gcc-multilib g++-multilib) \
        build-essential yasm nasm ccache \
        xxd pkgconf curl wget unzip zip git subversion mercurial rsync jq \
        autoconf automake libtool libtool-bin autopoint gettext parallel cmake meson ninja-build \
        clang llvm lcov lld qemu-user libunwind-dev \
        texinfo texi2html help2man flex bison groff \
        gperf itstool ragel libc6-dev zlib1g-dev libssl-dev \
        gtk-doc-tools gobject-introspection gawk \
        ocaml ocaml-findlib ocamlbuild libnum-ocaml-dev indent p7zip-full zstd \
        python3-setuptools python3-pip python3-venv python3-jinja2 python3-jsonschema python3-apt python3-dev python-is-python3 \
        gcc-14 g++-14 dos2unix re2c && \
    pip3 install --break-system-packages --upgrade meson  && \
    update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-14 100 && \
    update-alternatives --install /usr/bin/cc cc /usr/bin/gcc-14 100 && \
    update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-14 100 && \
    update-alternatives --install /usr/bin/c++ c++ /usr/bin/g++-14 100 && \
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    apt-get -y install nodejs && \
    npm cache clean --force && \
    npm install -g @napi-ffi/ffi-napi --unsafe-perm --build-from-source --CXXFLAGS="-fpermissive" && \
    apt-get -y clean && \
    git config --global user.email "builder@localhost" && \
    git config --global user.name "Builder" && \
    git config --global advice.detachedHead false && \
    git config --global core.autocrlf false && \
    git config --global --add safe.directory "*"

ENV CARGO_HOME="/opt/cargo" RUSTUP_HOME="/opt/rustup" PATH="/opt/cargo/bin:${PATH}"
RUN curl https://sh.rustup.rs -sSf | bash -s -- -y --no-modify-path && \
    curl -fsSL "https://github.com/lu-zero/cargo-c/releases/download/v${CARGO_C_VERSION}/cargo-c-x86_64-unknown-linux-musl.tar.gz" | tar -xz -C /opt/cargo/bin

RUN --mount=src=.,dst=/input \
    for s in /input/*.sh; do \
        dest="/usr/bin/$(basename $s .sh)"; \
        cp "$s" "$dest" && chmod +x "$dest" && dos2unix "$dest"; \
    done

ENV HOST_CC="gcc-14" \
    HOST_CXX="g++-14" \
    HOST_CFLAGS="-O2 -pipe" \
    HOST_CXXFLAGS="-O2 -pipe"

RUN \
    dpkg --add-architecture i386 && \
    mkdir -pm755 /etc/apt/keyrings && \
    curl -fsSL "https://dl.winehq.org/wine-builds/winehq.key" -o /etc/apt/keyrings/winehq-archive.key && \
    curl -fsSL "https://dl.winehq.org/wine-builds/ubuntu/dists/noble/winehq-noble.sources" -o /etc/apt/sources.list.d/winehq-noble.sources && \
    apt-get -y update && \
    apt-get -y install --no-install-recommends \
        wine-stable \
        xvfb

ENV PATH="/opt/wine-stable/bin:${PATH}" \
    WINEARCH=win64 \
    WINEPREFIX=/root/.wine \
    DISPLAY=:99 \
    WINEDEBUG=-all

# Создаем ссылки на то, что РЕАЛЬНО есть в системе (судя по вашему dpkg -L)
RUN ln -sf /opt/wine-stable/bin/wine /usr/bin/wine64 && \
    ln -sf /opt/wine-stable/bin/wine /usr/bin/wine && \
    ln -sf /opt/wine-stable/bin/wineboot /usr/bin/wineboot && \
    ln -sf /opt/wine-stable/bin/wineserver /usr/bin/wineserver && \
    # Проверка: используем wine вместо wine64, если его нет
    wine --version && \
    echo "Wine binaries linked successfully."

# Инициализация Wine префикса
# RUN Xvfb :99 -screen 0 1024x768x16 & \
#    DISPLAY=:99 wineboot -u && \
#    # Ожидаем завершения настройки (wineserver может работать в фоне)
#    wineserver -w && \
#    echo "Wine prefix initialized"

# Предварительная инициализация префикса, чтобы не тратить время при билде
RUN xvfb-run sh -c "wine64 wineboot -i && wineserver -w"
