ARG GH_REPO=ghcr.io/lichtenshtein/ffmpeg-builds-test2
ARG CPU_ARCH=broadwell
ARG CPU_TUNE=broadwell
FROM ${GH_REPO}/base:latest
ARG GH_REPO
ARG CPU_ARCH
ARG CPU_TUNE

# Build the Toolchain
RUN --mount=src=ct-ng-config,dst=/.config \
    git clone --filter=blob:none --depth=1 https://github.com/crosstool-ng/crosstool-ng.git /ct-ng && \
    cd /ct-ng && \
    ./bootstrap && \
    ./configure --enable-local && \
    make -j$(nproc) && \
    cp /.config .config && \
    ./ct-ng build && \
    cd / && \
    rm -rf ct-ng

# Use login shell to ensure /etc/profile.d/toolchain.sh is sourced for every RUN
SHELL ["/bin/bash", "-l", "-c"]

# определяем жесткие пути тулчейна
ENV \
# Путь к общим бинарникам (x86_64-w64-mingw32-gcc)
    TOOLCHAIN_BIN="/opt/ct-ng/bin" \
# Внутренний путь, где лежат голые as/ld (ИХ НЕЛЬЗЯ В PATH!)
    TOOLCHAIN_INTERNAL="/opt/ct-ng/x86_64-w64-mingw32/bin" \
    \
    FFBUILD_TOOLCHAIN=x86_64-w64-mingw32 \
    FFBUILD_RUST_TARGET=x86_64-pc-windows-gnu \
    \
    CPU_ARCH="${CPU_ARCH}" \
    CPU_TUNE="${CPU_TUNE}"

RUN \
    echo "--- Setup Directories ---" && \
    mkdir -p /opt/ffbuild /opt/ffdest && \
    \
    echo "--- Toolchain Debug ---" && \
    find /opt/ct-ng -name "libwinpthread-*.dll" -o -name "kernel32.dll" || true && \
    \
# Настраиваем ccache маскарад вручную в /usr/local/bin
    echo "--- Configuring ccache masquerade symlinks ---" && \
    for tool in gcc g++ cpp c++ gcc-ar gcc-nm gcc-ranlib; do \
        echo "Linking /usr/local/bin/x86_64-w64-mingw32-$tool -> ccache"; \
        ln -sf /usr/bin/ccache "/usr/local/bin/x86_64-w64-mingw32-$tool"; \
    done
# done; \
# echo "--- Remove DLLs to force static linking ---" && \
# find /opt/ct-ng \( -name "*.dll" -or -name "*.dll.a" \) -delete

# System Paths
# /usr/local/bin contains the ccache symlinks (found first by scripts)
# /opt/ct-ng/... contains the real compilers (found by ccache via CCACHE_PATH)
# Потом системные пути (чтобы as/ld брались из Ubuntu для хоста)
# Потом TOOLCHAIN_BIN (где реальные x86_64-w64-mingw32-gcc)
ENV \
    PATH="/usr/local/bin:/usr/bin:/bin:${TOOLCHAIN_BIN}:/opt/cargo/bin" \
    \
    # ccache logic: explicitly search here for the REAL compiler to avoid loops
    CCACHE_PATH="${TOOLCHAIN_BIN}:/usr/bin" \
    CCACHE_DIR=/root/.cache/ccache \
    CCACHE_MAXSIZE=20G \
    CCACHE_SLOPPINESS="include_file_ctime,include_file_mtime,locale,time_macros,file_macro,pch_defines" \
    CCACHE_BASEDIR="/builder" \
    CCACHE_COMPILERCHECK="content" \
    CCACHE_DEPEND=1 \
    CCACHE_COMPRESS=1 \
    CCACHE_NOHASHDIR=1 \
    \
    # Build System Variables
    FFBUILD_TARGET_FLAGS="--pkg-config=pkg-config --cross-prefix=x86_64-w64-mingw32- --arch=x86_64 --target-os=mingw32" \
    FFBUILD_CROSS_PREFIX=x86_64-w64-mingw32- \
    FFBUILD_PREFIX=/opt/ffbuild \
    FFBUILD_DESTDIR=/opt/ffdest \
    FFBUILD_DESTPREFIX=/opt/ffdest/opt/ffbuild \
    FFBUILD_CMAKE_TOOLCHAIN=/toolchain.cmake \
    \
    PKG_CONFIG="pkg-config" \
    PKG_CONFIG_LIBDIR="/opt/ffbuild/lib/pkgconfig:/opt/ffbuild/share/pkgconfig" \
    PKG_CONFIG_SYSROOT_DIR="/" \
    PKG_CONFIG_ALLOW_SYSTEM_CFLAGS=0 \
    PKG_CONFIG_ALLOW_SYSTEM_LIBS=0 \
    \
    CFLAGS="-I/opt/ffbuild/include -march=${CPU_ARCH} -mtune=${CPU_TUNE} -O3 -pipe -D_FORTIFY_SOURCE=2 -fstack-protector-strong" \
    CXXFLAGS="-I/opt/ffbuild/include -march=${CPU_ARCH} -mtune=${CPU_TUNE} -O3 -pipe -D_FORTIFY_SOURCE=2 -fstack-protector-strong" \
    LDFLAGS="-static-libgcc -static-libstdc++ -L/opt/ffbuild/lib -pipe"

ENV \
    CHOST="x86_64-w64-mingw32" \
    # Эти переменные заставят почти любой билд-скрипт использовать 
    # ccache-ссылки из /usr/local/bin
    CC="x86_64-w64-mingw32-gcc" \
    CXX="x86_64-w64-mingw32-g++" \
    # Для AR/NM/RANLIB используем версии с префиксом gcc-
    AR="x86_64-w64-mingw32-gcc-ar" \
    NM="x86_64-w64-mingw32-gcc-nm" \
    RANLIB="x86_64-w64-mingw32-gcc-ranlib" \
    LD="x86_64-w64-mingw32-ld" \
    STRIP="x86_64-w64-mingw32-strip" \
    WINDRES="x86_64-w64-mingw32-windres" \
    DLLTOOL="x86_64-w64-mingw32-dlltool" \
    OBJDUMP="x86_64-w64-mingw32-objdump" \
    GENDEF="x86_64-w64-mingw32-gendef"

ADD toolchain.cmake /toolchain.cmake
ADD cross.meson /cross.meson

# Rust Toolchains
RUN rustup target add "$FFBUILD_RUST_TARGET" && \
    printf "[target.%s]\nlinker = \"%s-gcc\"\nar = \"%s-gcc-ar\"\n" "$FFBUILD_RUST_TARGET" "$FFBUILD_TOOLCHAIN" "$FFBUILD_TOOLCHAIN" > "$CARGO_HOME"/config.toml
