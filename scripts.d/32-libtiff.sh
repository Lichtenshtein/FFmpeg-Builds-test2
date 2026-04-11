#!/bin/bash

SCRIPT_REPO="https://github.com/libsdl-org/libtiff.git"
SCRIPT_COMMIT="f324415f50cb5c90f7712e9dfe69831f5d2ea88d"

ffbuild_depends() {
    echo zlib
    echo xz
    echo libjpeg-turbo
    echo jbigkit
    echo zstd
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    mkdir -p tiff_build && cd tiff_build

    export WebP_LIBRARY="$FFBUILD_DESTPREFIX/lib/libwebp.a;$FFBUILD_DESTPREFIX/lib/libsharpyuv.a"
    
    local DEP_LIBS="-lwebpmux -lwebpdemux -lwebp -lwebpdecoder -lsharpyuv -lturbojpeg -ljpeg -ljbig -lzstd -llzma -lz -lstdc++"

    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF)
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DBUILD_SHARED_LIBS=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
        -Dtiff-static=$([ "${PREFER_SHARED}" == "1" ] && echo OFF || echo ON)
        -Dtiff-tools=OFF
        -Dtiff-tests=OFF
        -Dtiff-contrib=OFF
        -Dtiff-docs=OFF
        -Dtiff-opengl=OFF
        -Djpeg=ON
        -Dzstd=ON
        -Dzlib=ON
        -Dlzma=ON
        -Dwebp=ON
        -Djbig=ON
        -DWebP_LIBRARY="$WebP_LIBRARY"
    )

    export static_flags=""
    [[ "${PREFER_SHARED}" != "1" ]] && static_flags="-DLIBTIFF_STATIC"

    CFLAGS="$CFLAGS $CPPFLAGS $static_flags" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS $static_flags" \
    cmake -G Ninja "${myconf[@]}" \
        -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    local PC_FILE="$PC_DIR/libtiff-4.pc"
    local LINK_FILE="$PC_DIR/tiff.pc"
    if [[ -f "$PC_FILE" ]]; then
        if ! grep -q "$static_flags" "$PC_FILE"; then
            sed -i "/^Cflags:/ s/$/ $static_flags/" "$PC_FILE"
        fi
    fi

    # проверить, как называется созданный .pc файл (обычно libtiff-4.pc). Если lcms2 или leptonica его не видят придется сделать симлинк:
    ln -sf libtiff-4.pc "$LINK_FILE"
}
