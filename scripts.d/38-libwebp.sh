#!/bin/bash

SCRIPT_REPO="https://github.com/webmproject/libwebp.git"
SCRIPT_COMMIT="b43b2caa710c0c997c066cb32c7fea1391fad70a"

ffbuild_depends() {
    echo libpng
    echo libjpeg-turbo
    echo libtiff
    echo giflib
    echo zlib
    # echo zstd
    # echo xz
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    mkdir -p _build && cd _build

    export PKG_CONFIG_PATH="$FFBUILD_PREFIX/lib/pkgconfig:$PKG_CONFIG_PATH"

    local myconf=(
        # -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF)
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DWEBP_LINK_STATIC=$([ "${PREFER_SHARED}" == "1" ] && echo OFF || echo ON)
        -DWEBP_ENABLE_SIMD=ON
        -DWEBP_BUILD_ANIM_UTILS=OFF
        -DWEBP_BUILD_CWEBP=OFF
        -DWEBP_BUILD_DWEBP=OFF
        -DWEBP_BUILD_GIF2WEBP=OFF
        -DWEBP_BUILD_IMG2WEBP=OFF
        -DWEBP_BUILD_VWEBP=OFF
        -DWEBP_BUILD_WEBPINFO=OFF
        -DWEBP_BUILD_LIBWEBPMUX=ON
        -DWEBP_BUILD_WEBPMUX=OFF
        -DWEBP_BUILD_EXTRAS=ON
        -DWEBP_BUILD_WEBP_JS=OFF
        -DWEBP_BUILD_FUZZTEST=OFF
        -DWEBP_BUILD_WEBP_ANIM2PNG_DEFAULT=OFF # patch adds tool for decoding animated WebP
        -DWEBP_BUILD_WEBP_ANIM2PNG=OFF # patch adds tool for decoding animated WebP
        -DWEBP_USE_THREAD=ON
        -DWEBP_NEAR_LOSSLESS=ON
        -DWEBP_ENABLE_SWAP_16BIT_CSP=OFF # Enable byte swap for 16 bit colorspaces
        -DWEBP_UNICODE=ON
    )

    if has_library "z"; then
        local Z_LIB="-lz"
    fi
    if has_library "jpeg"; then
        local JPEG_LIBS="-lturbojpeg -ljpeg"
    fi
    if has_library "jbig"; then
        local JBIG_LIB="-ljbig"
    fi
    if has_library "zstd"; then
        local ZSTD_LIB="-lzstd"
    fi
    if has_library "lzma"; then
        local LZMA_LIB="-llzma"
    fi
    if has_library "gif"; then
        local GIF_LIB="-lgif"
    fi
    if has_library "tiff"; then
        local TIFF_LIB="-ltiffxx -ltiff"
    fi
    if has_library "png"; then
        local PNG_LIB="-lpng"
    fi

    local DEP_LIBS="${TIFF_LIB} ${JPEG_LIBS} ${PNG_LIB} ${GIF_LIB} ${JBIG_LIB} ${ZSTD_LIB} ${LZMA_LIB} ${Z_LIB}"
    local WIN_LIBS="-lgdi32 -lmsimg32 -ldwrite -ld2d1 -lwindowscodecs -lopengl32 $LIBS"

    export static_flags=""
    [[ "${PREFER_SHARED}" != "1" ]] && static_flags="-DWEBP_STATIC"

    CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C} $static_flags" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C} $static_flags" \
    LDFLAGS="$LDFLAGS ${USELTO}${USELTO_L}" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    mkdir -p "$PC_DIR"
    if [ -d "$PC_DIR" ]; then
        find "$PC_DIR" -name "*.pc" | while read -r PC_FILE; do
            sed -i "s|^Cflags:.*|& -I\${includedir}/webp|" "$PC_FILE"
            if [[ -n "$static_flags" ]]; then
                if ! grep -qF -- "$static_flags" "$PC_FILE"; then
                    sed -i "/^Cflags:/ s/$/ $static_flags/" "$PC_FILE"
                fi
            fi
        done
        log_info "Cflags paths have been updated."
    fi

    ln -sf libwebp.pc "$PC_DIR/webp.pc"
}

ffbuild_libs() {
    echo "-lwebpmux -lwebpdemux -lwebp -lwebpdecoder -lsharpyuv"
}

ffbuild_cppflags() {
    echo "$static_flags"
}

ffbuild_configure() {
    echo --enable-libwebp
}

ffbuild_unconfigure() {
    echo --disable-libwebp
}
