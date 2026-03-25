#!/bin/bash

SCRIPT_REPO="https://github.com/webmproject/libvpx.git"
SCRIPT_COMMIT="53b5de7d75742b0b5dff237c7ea3d96577050e4f"

ffbuild_enabled() {
    [[ $TARGET == winarm64 ]] && return -1
    return 0
}

ffbuild_dockerbuild() {
    local myconf=(
        --disable-shared
        --enable-static
        --enable-pic
        --disable-examples
        --disable-tools
        --disable-docs
        --disable-unit-tests
        --enable-vp9-highbitdepth
        --prefix="$FFBUILD_PREFIX"
        --enable-realtime-only
        --enable-runtime-cpu-detect
        --enable-postproc
        --enable-multi-res-encoding
        --enable-multithread
        --enable-better-hw-compatibility
        --enable-webm-io
        --enable-postproc-visualizer
        --enable-vp9-temporal-denoising
    )

    if [[ $TARGET == win64 ]]; then
        myconf+=(
            --target=x86_64-win64-gcc
        )
        export CROSS="$FFBUILD_CROSS_PREFIX"
    elif [[ $TARGET == win32 ]]; then
        myconf+=(
            --target=x86-win32-gcc
        )
        export CROSS="$FFBUILD_CROSS_PREFIX"
    elif [[ $TARGET == winarm64 ]]; then
        myconf+=(
            --target=arm64-win64-gcc
        )
        export CROSS="$FFBUILD_CROSS_PREFIX"
    elif [[ $TARGET == linux64 ]]; then
        myconf+=(
            --target=x86_64-linux-gcc
        )
        export CROSS="$FFBUILD_CROSS_PREFIX"
    elif [[ $TARGET == linuxarm64 ]]; then
        myconf+=(
            --target=arm64-linux-gcc
        )
        export CROSS="$FFBUILD_CROSS_PREFIX"
    else
        echo "Unknown target"
        return -1
    fi

    export CPU_ARCH="broadwell"
    export CPU_TUNE="broadwell"

    CFLAGS="-march=${CPU_ARCH} -mtune=${CPU_TUNE} -O3 -pipe \
            -mms-bitfields -fstack-protector-strong" \
    CPPFLAGS="-I/opt/ffbuild/include \
              -D__USE_MINGW_ANSI_STDIO=1 -U_WIN32_WINNT \
              -D_WIN32_WINNT=0x0A00 -D_WIN32 -D_FORTIFY_SOURCE=2" \
    CXXFLAGS="-march=${CPU_ARCH} -mtune=${CPU_TUNE} -O3 -pipe \
              -D__USE_MINGW_ANSI_STDIO=1 -U_WIN32_WINNT \
              -D_WIN32_WINNT=0x0A00 -D_WIN32 -D_FORTIFY_SOURCE=2" \
    LDFLAGS="-Wl,-Bstatic -static -static-libgcc -static-libstdc++ \
             -L/opt/ffbuild/lib -pipe -Wl,--high-entropy-va -Wl,--nxcompat \
             -Wl,--dynamicbase -Wl,--reduce-memory-overheads -Wl,--stack,16777216" \
    LIBS="-lpthread" \
    ./configure "${myconf[@]}"
    make -j$(nproc)
    make install DESTDIR="$FFBUILD_DESTDIR"

    # Work around strip breaking LTO symbol index
    "$RANLIB" "$FFBUILD_DESTPREFIX"/lib/libvpx.a
}

ffbuild_configure() {
    echo --enable-libvpx
}

ffbuild_unconfigure() {
    echo --disable-libvpx
}
