#!/bin/bash

SCRIPT_REPO="https://github.com/libarchive/libarchive.git"
SCRIPT_COMMIT="8d62a0512a4d75febec419205b62bc2e073e10c8"

ffbuild_depends() {
    echo zlib
    echo libiconv
    echo xz
    echo bzlib
    echo openssl
    echo libxml2
    echo zstd
    # echo mbedtls
    # echo nettle
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    mkdir -p build_dir && cd build_dir

    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        # -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF)
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DBUILD_SHARED_LIBS=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
        -DENABLE_TEST=OFF
        -DENABLE_COVERAGE=OFF
        -DENABLE_INSTALL=ON
        # Отключаем исполняемые файлы (bsdtar, bsdcpio), нам нужна только либа
        -DENABLE_TAR=OFF
        -DENABLE_CPIO=OFF
        -DENABLE_CAT=OFF
        -DENABLE_UNZIP=ON
    )

    if has_library "xml2"; then
        log_info "LibXML2 library detected. Building with LibXML2 support..."
        myconf+=(
            -DENABLE_LIBXML2=ON
            -DLIBXML2_LIBRARIES="-lxml2"
            -DLIBXML2_INCLUDE_DIR="$FFBUILD_PREFIX/include/libxml2"
            -DCMAKE_REQUIRED_INCLUDES="$FFBUILD_PREFIX/include/libxml2"
            -DCMAKE_REQUIRED_LIBRARIES="-lxml2"
        )
        local XML2_LIB="-lxml2"
        local XML2_C_FLAGS="-DLIBXML_STATIC -DXML_STATIC"
    else
        myconf+=(
            -DENABLE_LIBXML2=OFF
        )
    fi
    if has_library "z"; then
        log_info "Zlib library detected. Building with Zlib support..."
        myconf+=(
            -DENABLE_ZLIB=ON
        )
        local ZLIB_LIB="-lz"
    else
        myconf+=(
            -DENABLE_ZLIB=OFF
        )
    fi
    if has_library "zstd"; then
        log_info "ZSTD library detected. Building with ZSTD support..."
        myconf+=(
            -DENABLE_ZSTD=ON
        )
        local ZSTD_LIB="-lzstd"
    else
        myconf+=(
            -DENABLE_ZSTD=OFF
        )
    fi
    if has_library "lzma"; then
        log_info "LZMA library detected. Building with lZMA support..."
        myconf+=(
            -DENABLE_LZMA=ON
        )
        local LZMA_LIB="-llzma"
    else
        myconf+=(
            -DENABLE_LZMA=OFF
        )
    fi
    if has_library "bz2"; then
        log_info "BZ2 library detected. Building with BZ2 support..."
        myconf+=(
            -DENABLE_BZip2=ON
        )
        local BZ2_LIB="-lbz2"
    else
        myconf+=(
            -DENABLE_BZip2=OFF
        )
    fi
    if has_library "iconv"; then
        log_info "Iconv library detected. Building with iconv support..."
        myconf+=(
            -DENABLE_ICONV=ON
        )
        local ICONV_LIB="-liconv -lcharset"
    else
        myconf+=(
            -DENABLE_ICONV=OFF
        )
    fi
    if has_library "ssl"; then
        log_info "OpenSSL library detected. Building with OpenSSL support..."
        myconf+=(
            -DENABLE_OPENSSL=ON
            -DENABLE_MBEDTLS=OFF
            -DENABLE_NETTLE=OFF
        )
        local OPENSSL_LIB="-lssl -lcrypto"
    else
        myconf+=(
            -DENABLE_OPENSSL=OFF
        )
    fi

    if [[ $TARGET == win* ]]; then
        # Windows-специфичные опции
        myconf+=(
        -DENABLE_CNG=ON
        -DENABLE_ACL=ON
        -DENABLE_XATTR=ON
        )
    fi

    local DEP_LIBS="${OPENSSL_LIB} ${XML2_LIB} ${ZSTD_LIB} ${LZMA_LIB} ${BZ2_LIB} ${ZLIB_LIB} ${ICONV_LIB}"
    local WIN_LIBS="-lcrypt32 -luserenv $LIBS"

    export static_flags=""
    export self_static_flags=""
    [[ "${PREFER_SHARED}" != "1" ]] && static_flags="${XML2_C_FLAGS}" && self_static_flags="-DARCHIVE_STATIC"

    CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C} $self_static_flags $static_flags" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C} $self_static_flags $static_flags" \
    cmake -G Ninja "${myconf[@]}" \
        -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS ${USELTO}${USELTO_L} $DEP_LIBS $WIN_LIBS" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    local PC_FILE="$PC_DIR/libarchive.pc"
    if [[ -f "$PC_FILE" ]]; then
        if [[ -n "$self_static_flags" ]]; then
            if ! grep -qF -- "$self_static_flags" "$PC_FILE"; then
                sed -i "/^Cflags:/ s/$/ $self_static_flags/" "$PC_FILE"
            fi
        fi
        if grep -q "^Libs.private:" "$PC_FILE"; then
            sed -i "s|^Libs.private:.*|Libs.private: $DEP_LIBS $WIN_LIBS|" "$PC_FILE"
        else
            sed -i "/^Libs:/ a Libs.private: $DEP_LIBS $WIN_LIBS" "$PC_FILE"
        fi
    fi
}
