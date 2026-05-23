#!/bin/bash

SCRIPT_REPO="https://github.com/libsdl-org/libtiff.git"
SCRIPT_COMMIT="4225987ff183952a29f58322ec4792039c3a8e0c"

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
    
    # local DEP_LIBS="-lwebpmux -lwebpdemux -lwebp -lwebpdecoder -lsharpyuv -lturbojpeg -ljpeg -ljbig -lzstd -llzma -lz"

    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        # -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF)
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DBUILD_SHARED_LIBS=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
        -Dtiff-static=$([ "${PREFER_SHARED}" == "1" ] && echo OFF || echo ON)
        -Dtiff-tools=OFF
        -Dtiff-tests=OFF
        -Dtiff-contrib=OFF
        -Dtiff-docs=OFF
        -Dtiff-opengl=ON
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

    local FLAGS="-DTIFF_DO_NOT_USE_NON_EXT_ALLOC_FUNCTIONS -D_FILE_OFFSET_BITS=64 -Dtiff_EXPORTS -Wall -Winline -Wformat-security -Wpointer-arith -Wdisabled-optimization -Wno-unknown-pragmas -fstrict-aliasing"

    CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C} $static_flags $FLAGS" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C} $static_flags $FLAGS" \
    cmake -G Ninja "${myconf[@]}" \
        -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS ${USELTO}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    local PC_FILE="$PC_DIR/libtiff-4.pc"
    if [[ -f "$PC_FILE" ]]; then
        sed -i 's/^Requires.private:.*/Requires.private: zlib libjpeg liblzma libzstd libwebp/' "$PC_FILE"
        if [[ -n "$static_flags" ]]; then
            if ! grep -qF -- "$static_flags" "$PC_FILE"; then
                sed -i "/^Cflags:/ s/$/ $static_flags/" "$PC_FILE"
            fi
        fi
    fi

    ln -sf "$PC_FILE" "$PC_DIR/tiff.pc"
}
