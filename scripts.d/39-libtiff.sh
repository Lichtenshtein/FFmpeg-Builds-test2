#!/bin/bash

SCRIPT_REPO="https://github.com/libsdl-org/libtiff.git"
SCRIPT_COMMIT="732665c2c8785cec3e1f46ba9908575f0f3a8059"

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
    )

    if has_library "z"; then
        log_info "Zlib library detected. Building with Zlib support..."
        myconf+=(
            -Dzlib=ON
        )
        local Z_LIB="-lz"
        local ZLIB_PC="zlib"
    fi
    if has_library "webp"; then
        log_info "WebP library detected. Building with WebP support..."
        myconf+=(
            -Dwebp=ON
            -DWebP_LIBRARY="$INSTALL_ROOT/lib/libwebp.${lib_ext};$INSTALL_ROOT/lib/libsharpyuv.${lib_ext}"
        )
        local WEBP_LIBS="-lwebpmux -lwebpdemux -lwebp -lwebpdecoder -lsharpyuv"
        local WEBP_PC="webp"
    fi
    if has_library "jpeg"; then
        log_info "JPEG library detected. Building with JPEG support..."
        myconf+=(
            -Djpeg=ON
        )
        local JPEG_LIBS="-lturbojpeg -ljpeg"
        local JPEG_PC="libjpeg libturbojpeg"
    fi
    if has_library "jbig"; then
        log_info "JBig library detected. Building with JBig support..."
        myconf+=(
            -Djbig=ON
        )
        local JBIG_LIB="-ljbig"
    fi
    if has_library "zstd"; then
        log_info "ZSTD library detected. Building with ZSTD support..."
        myconf+=(
            -Dzstd=ON
        )
        local ZSTD_LIB="-lzstd"
        local ZSTD_PC="zstd"
    fi
    if has_library "lzma"; then
        log_info "LZMA library detected. Building with lZMA support..."
        myconf+=(
            -Dlzma=ON
        )
        local LZMA_LIB="-llzma"
        local LZMA_PC="lzma"
    fi

    local DEP_LIBS="${WEBP_LIBS} ${JPEG_LIBS} ${JBIG_LIB} ${ZSTD_LIB} ${LZMA_LIB} ${Z_LIB}"

    export static_flags=""
    [[ "${PREFER_SHARED}" != "1" ]] && static_flags="-DLIBTIFF_STATIC"

    local FLAGS="-DTIFF_DO_NOT_USE_NON_EXT_ALLOC_FUNCTIONS -D_FILE_OFFSET_BITS=64 -Dtiff_EXPORTS -Wno-unknown-pragmas"

    CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C} $static_flags $FLAGS" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C} $static_flags $FLAGS" \
    cmake -G Ninja "${myconf[@]}" \
        -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS ${USELTO}${USELTO_L}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    local PC_FILE="$PC_DIR/libtiff-4.pc"
    if [[ -f "$PC_FILE" ]]; then
        sed -i 's/^Requires:.*/Requires: ${ZLIB_PC} ${JPEG_PC} ${LZMA_PC} ${ZSTD_PC} ${WEBP_PC}/' "$PC_FILE"
        if [[ -n "$static_flags" ]]; then
            if ! grep -qF -- "$static_flags" "$PC_FILE"; then
                sed -i "/^Cflags:/ s/$/ $static_flags/" "$PC_FILE"
            fi
        fi
    fi

    ln -sf "$PC_FILE" "$PC_DIR/tiff.pc"
}
