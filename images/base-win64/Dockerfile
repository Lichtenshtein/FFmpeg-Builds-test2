ARG GH_REPO=ghcr.io/lichtenshtein/ffmpeg-builds-test2
FROM ${GH_REPO}/base:latest
ARG GH_REPO

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
# RUN find /opt/ct-ng \( -name "*.dll" -or -name "*.dll.a" \) -delete && \
#    mkdir -p /opt/ffbuild
RUN mkdir -p /opt/ffbuild /opt/ffdest

ENV  \
    FFBUILD_TOOLCHAIN=x86_64-w64-mingw32 \
    FFBUILD_RUST_TARGET=x86_64-pc-windows-gnu

RUN rustup target add "$FFBUILD_RUST_TARGET" && \
    printf "[target.%s]\nlinker = \"%s-gcc\"\nar = \"%s-gcc-ar\"\n" "$FFBUILD_RUST_TARGET" "$FFBUILD_TOOLCHAIN" "$FFBUILD_TOOLCHAIN" > "$CARGO_HOME"/config.toml

ADD toolchain.cmake /toolchain.cmake
ADD cross.meson /cross.meson

# configuring ccache symlinks for Mingw compilers
RUN  \
    ln -s /usr/bin/ccache /usr/local/bin/${FFBUILD_TOOLCHAIN}-gcc && \
    ln -s /usr/bin/ccache /usr/local/bin/${FFBUILD_TOOLCHAIN}-g++ && \
    ln -s /usr/bin/ccache /usr/local/bin/${FFBUILD_TOOLCHAIN}-gcc-ar && \
    ln -s /usr/bin/ccache /usr/local/bin/${FFBUILD_TOOLCHAIN}-gcc-nm && \
    ln -s /usr/bin/ccache /usr/local/bin/${FFBUILD_TOOLCHAIN}-gcc-ranlib

RUN echo "--- Toolchain Search ---" && \
    find /opt/ct-ng -name "libwinpthread-*.dll" -o -name "kernel32.dll" || true && \
    /opt/ct-ng/${FFBUILD_TOOLCHAIN}/${FFBUILD_TOOLCHAIN}/bin/gcc -print-sysroot || true && \
    /opt/ct-ng/bin/${FFBUILD_TOOLCHAIN}-gcc -print-sysroot || true && \
    find /opt/ct-ng -name "*gcc" && \
    echo "--- Search Finished ---"

# ccache settings
ENV  \
    CCACHE_DIR=/root/.cache/ccache \
    CCACHE_MAXSIZE=20G \
    CCACHE_SLOPPINESS="include_file_ctime,include_file_mtime,locale,time_macros,file_macro,pch_defines" \
    CCACHE_BASEDIR="/builder" \
    CCACHE_COMPILERCHECK="content" \
    CCACHE_DEPEND=1 \
    CCACHE_COMPRESS=1 \
    CCACHE_NOHASHDIR=1
