ARG GH_REPO
FROM $GH_REPO/base:latest

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

# Remove DLLs to force static linking
# RUN find /opt/ct-ng -name "*.dll" -or -name "*.dll.a" -delete && \
#    mkdir -p /opt/ffbuild
RUN mkdir -p /opt/ffbuild /opt/ffdest

RUN echo "--- Toolchain Search ---" && \
    find /opt/ct-ng -name "libwinpthread-*.dll" -o -name "kernel32.dll" || true && \
    echo "--- Search Finished ---"

RUN rm -rf /var/lib/apt/lists/*

ENV FFBUILD_TOOLCHAIN=x86_64-w64-mingw32 \
    FFBUILD_RUST_TARGET=x86_64-pc-windows-gnu

RUN rustup target add "$FFBUILD_RUST_TARGET" && \
    printf "[target.%s]\nlinker = \"%s-gcc\"\nar = \"%s-gcc-ar\"\n" "$FFBUILD_RUST_TARGET" "$FFBUILD_TOOLCHAIN" "$FFBUILD_TOOLCHAIN" > "$CARGO_HOME"/config.toml

ADD toolchain.cmake /toolchain.cmake
ADD cross.meson /cross.meson

# configuring ccache symlinks for Mingw compilers
RUN ln -s /usr/bin/ccache /usr/local/bin/${FFBUILD_TOOLCHAIN}-gcc && \
    ln -s /usr/bin/ccache /usr/local/bin/${FFBUILD_TOOLCHAIN}-g++ && \
    ln -s /usr/bin/ccache /usr/local/bin/${FFBUILD_TOOLCHAIN}-gcc-ar && \
    ln -s /usr/bin/ccache /usr/local/bin/${FFBUILD_TOOLCHAIN}-gcc-nm && \
    ln -s /usr/bin/ccache /usr/local/bin/${FFBUILD_TOOLCHAIN}-gcc-ranlib

# ccache settings
ENV CCACHE_DIR=/root/.cache/ccache \
    CCACHE_MAXSIZE=20G \
    CCACHE_SLOPPINESS="include_file_ctime,include_file_mtime,locale,time_macros,file_macro,pch_defines" \
    CCACHE_BASEDIR="/builder" \
    CCACHE_COMPILERCHECK="content" \
    CCACHE_DEPEND=1 \
    CCACHE_COMPRESS=1

# disable -fPIC, -ffast-math, -flto=auto if troubles occur
# add -D_FORTIFY_SOURCE=2 for security
# Stable for debugging:
# CFLAGS="-O2 -march=x86-64-v3 -mtune=generic -D_FORTIFY_SOURCE=2 -static-libgcc -static-libstdc++ -I/opt/ffbuild/include -pipe"
# LDFLAGS="-Wl,--gc-sections"

ENV PATH="/usr/local/bin:/opt/ct-ng/bin:${PATH}" \
    FFBUILD_TARGET_FLAGS="--pkg-config=pkg-config --cross-prefix=${FFBUILD_TOOLCHAIN}- --arch=x86_64 --target-os=mingw32" \
    FFBUILD_CROSS_PREFIX=${FFBUILD_TOOLCHAIN}- \
    FFBUILD_PREFIX=/opt/ffbuild \
    FFBUILD_DESTDIR=/opt/ffdest \
    FFBUILD_DESTPREFIX=/opt/ffdest/opt/ffbuild \
    FFBUILD_CMAKE_TOOLCHAIN=/toolchain.cmake \
    PKG_CONFIG=pkg-config \
    PKG_CONFIG_LIBDIR=/opt/ffbuild/lib/pkgconfig:/opt/ffbuild/share/pkgconfig \
    CC="${FFBUILD_TOOLCHAIN}-gcc" \
    CXX="${FFBUILD_TOOLCHAIN}-g++" \
    LD="${FFBUILD_TOOLCHAIN}-ld" \
    AR="${FFBUILD_TOOLCHAIN}-gcc-ar" \
    RANLIB="${FFBUILD_TOOLCHAIN}-gcc-ranlib" \
    NM="${FFBUILD_TOOLCHAIN}-gcc-nm" \
    DLLTOOL="${FFBUILD_TOOLCHAIN}-dlltool" \
    GENDEF="${FFBUILD_TOOLCHAIN}-gendef" \
    CFLAGS="-O3 -march=broadwell -mtune=broadwell -mfpmath=sse -ffast-math -D_FORTIFY_SOURCE=2 -static-libgcc -static-libstdc++ -I/opt/ffbuild/include -pipe -fstack-protector-strong" \
    CXXFLAGS="-O3 -march=broadwell -mtune=broadwell -mfpmath=sse -ffast-math -D_FORTIFY_SOURCE=2 -static-libgcc -static-libstdc++ -I/opt/ffbuild/include -pipe -fstack-protector-strong" \
    LDFLAGS="-O3 -static-libgcc -static-libstdc++ -L/opt/ffbuild/lib -Wl,--gc-sections -Wl,--as-needed -Wl,--high-entropy-va -Wl,--nxcompat -Wl,--dynamicbase -Wl,--reduce-memory-overheads -Wl,--stack,16777216" \
    STAGE_CFLAGS="-fno-semantic-interposition" \
    STAGE_CXXFLAGS="-fno-semantic-interposition"

# Инициализация Wine префикса
RUN Xvfb :99 -screen 0 1024x768x16 & \
    DISPLAY=:99 wine64 wineboot -u && \
    wineserver -w && \
    echo "Wine prefix pre-initialized successfully."
