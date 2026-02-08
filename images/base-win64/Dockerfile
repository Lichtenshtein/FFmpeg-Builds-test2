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
RUN find /opt/ct-ng -name "*.dll" -or -name "*.dll.a" -delete && \
    mkdir -p /opt/ffbuild

RUN apt-get -y update && \
    apt-get -y install --no-install-recommends wine-stable && \
    apt-get -y clean && \
    rm -rf /var/lib/apt/lists/*

ENV FFBUILD_TOOLCHAIN=x86_64-w64-mingw32 \
    FFBUILD_RUST_TARGET=x86_64-pc-windows-gnu

RUN rustup target add "$FFBUILD_RUST_TARGET" && \
    echo "[target.$FFBUILD_RUST_TARGET]\nlinker = \"${FFBUILD_TOOLCHAIN}-gcc\"\nar = \"${FFBUILD_TOOLCHAIN}-gcc-ar\"\n" > "$CARGO_HOME"/config.toml

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
    CCACHE_MAXSIZE=2G \
    CCACHE_COMPRESS=1

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
    CFLAGS="-O3 -march=broadwell -mtune=broadwell -mfpmath=sse -ffast-math -flto=auto -static-libgcc -static-libstdc++ -I/opt/ffbuild/include -pipe -fstack-protector-strong" \
    CXXFLAGS="-O3 -march=broadwell -mtune=broadwell -mfpmath=sse -ffast-math -flto=auto -static-libgcc -static-libstdc++ -I/opt/ffbuild/include -pipe -fstack-protector-strong" \
    LDFLAGS="-O3 -march=broadwell -flto=auto -static-libgcc -static-libstdc++ -L/opt/ffbuild/lib -Wl,--gc-sections -Wl,--as-needed" \
    STAGE_CFLAGS="-fno-semantic-interposition" \
    STAGE_CXXFLAGS="-fno-semantic-interposition"
