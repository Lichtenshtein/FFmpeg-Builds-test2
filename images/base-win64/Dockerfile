ARG GH_REPO=ghcr.io/lichtenshtein/ffmpeg-builds-test2
FROM ${GH_REPO}/base:latest
ARG GH_REPO

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

# Runtime Check & Path Automation
RUN set -e; \
    echo "--- Runtime check for CPU instructions support ---" && \
    if ! grep -q "avx2" /proc/cpuinfo || ! grep -q "fma" /proc/cpuinfo || \
       ! grep -q "bmi1" /proc/cpuinfo || ! grep -q "bmi2" /proc/cpuinfo; then \
         echo "ERROR: Host CPU does not support x86-64-v3"; exit 1; \
    fi; \
    \
    echo "--- Setup Directories ---" && \
    mkdir -p /opt/ffbuild /opt/ffdest && \
    \
    echo "--- Toolchain Debug ---" && \
    find /opt/ct-ng -name "libwinpthread-*.dll" -o -name "kernel32.dll" || true && \
    \
    echo "--- Automating Toolchain Path Discovery ---" && \
    # Find the main compiler binary
    REAL_GCC=$(find /opt/ct-ng -name "x86_64-w64-mingw32-gcc" -type f | head -n 1) && \
    if [ -z "$REAL_GCC" ]; then echo "ERROR: x86_64-w64-mingw32-gcc not found!"; exit 1; fi; \
    REAL_BIN_DIR=$(dirname "$REAL_GCC") && \
    \
    # Find the internal/triplet-specific bin directory
    INTERNAL_BIN_DIR=$(find /opt/ct-ng -type d -path "*/x86_64-w64-mingw32/bin" | head -n 1) && \
    echo "SUCCESS: Found Real Bin Dir: $REAL_BIN_DIR" && \
    echo "SUCCESS: Found Internal Bin Dir: $INTERNAL_BIN_DIR" && \
    \
    # Write to profile
    { \
        echo "export PATH=\"/usr/local/bin:$REAL_BIN_DIR:$INTERNAL_BIN_DIR:\${WINE_BIN_DIR}:\$PATH\""; \
        echo "export CCACHE_PATH=\"$REAL_BIN_DIR:$INTERNAL_BIN_DIR:/usr/bin\""; \
    } > /etc/profile.d/toolchain.sh && \
    chmod +x /etc/profile.d/toolchain.sh && \
    echo "--- Final Profile Content ---" && \
    cat /etc/profile.d/toolchain.sh && \
    \
    echo "--- Configuring ccache masquerade symlinks ---" && \
    for tool in gcc g++ gcc-ar gcc-nm gcc-ranlib; do \
        echo "Linking /usr/local/bin/x86_64-w64-mingw32-$tool -> ccache"; \
        ln -sf /usr/bin/ccache "/usr/local/bin/x86_64-w64-mingw32-$tool"; \
    done; \
    \
    # echo "--- Remove DLLs to force static linking ---" && \
    # find /opt/ct-ng \( -name "*.dll" -or -name "*.dll.a" \) -delete

# Environment Variables
ENV \
    # Toolchain Identifiers
    FFBUILD_TOOLCHAIN=x86_64-w64-mingw32 \
    FFBUILD_RUST_TARGET=x86_64-pc-windows-gnu \
    \
    # System Paths
    # /usr/local/bin contains the ccache symlinks (found first by scripts)
    # /opt/ct-ng/... contains the real compilers (found by ccache via CCACHE_PATH)
    PATH="/usr/local/bin:/opt/ct-ng/bin:/opt/ct-ng/x86_64-w64-mingw32/bin:/opt/wine-stable/bin:${PATH}" \
    \
    # ccache logic: explicitly search here for the REAL compiler to avoid loops
    CCACHE_PATH="/opt/ct-ng/bin:/opt/ct-ng/x86_64-w64-mingw32/bin:/usr/bin" \
    \
    # ccache performance settings
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
    \
    # Compiler Flags
    CHOST="x86_64-w64-mingw32" \
    CC="x86_64-w64-mingw32-gcc" \
    CXX="x86_64-w64-mingw32-g++" \
    LD="x86_64-w64-mingw32-ld" \
    AR="x86_64-w64-mingw32-gcc-ar" \
    RANLIB="x86_64-w64-mingw32-gcc-ranlib" \
    NM="x86_64-w64-mingw32-gcc-nm" \
    DLLTOOL="x86_64-w64-mingw32-dlltool" \
    WINDRES="x86_64-w64-mingw32-windres" \
    OBJDUMP="x86_64-w64-mingw32-objdump" \
    GENDEF="x86_64-w64-mingw32-gendef" \
    STRIP="x86_64-w64-mingw32-strip" \
    \
    CFLAGS="-I/opt/ffbuild/include -march=broadwell -mtune=broadwell -O3 -pipe -D_FORTIFY_SOURCE=2 -fstack-protector-strong" \
    CXXFLAGS="-I/opt/ffbuild/include -march=broadwell -mtune=broadwell -O3 -pipe -D_FORTIFY_SOURCE=2 -fstack-protector-strong" \
    LDFLAGS="-static-libgcc -static-libstdc++ -L/opt/ffbuild/lib -pipe" \
    STAGE_CFLAGS="-fno-semantic-interposition" \
    STAGE_CXXFLAGS="-fno-semantic-interposition"

# Use login shell to ensure /etc/profile.d/toolchain.sh is sourced for every RUN
SHELL ["/bin/bash", "-l", "-c"]

ADD toolchain.cmake /toolchain.cmake
ADD cross.meson /cross.meson

# Rust Toolchains
RUN rustup target add "$FFBUILD_RUST_TARGET" && \
    printf "[target.%s]\nlinker = \"%s-gcc\"\nar = \"%s-gcc-ar\"\n" "$FFBUILD_RUST_TARGET" "$FFBUILD_TOOLCHAIN" "$FFBUILD_TOOLCHAIN" > "$CARGO_HOME"/config.toml
