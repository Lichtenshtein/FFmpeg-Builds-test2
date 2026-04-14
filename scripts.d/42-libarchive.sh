#!/bin/bash

SCRIPT_REPO="https://github.com/libarchive/libarchive.git"
SCRIPT_COMMIT="0a35627ec8bb2d755b8a9a340543a37eb6b97ade"

ffbuild_depends() {
    echo zlib
    echo xz
    echo bzlib
    echo openssl
    echo libxml2
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

    mkdir -p build_dir && cd build_dir

    local DEP_LIBS="-lssl -lcrypto -lxml2 -lzstd -llzma -lbz2 -lz -liconv -lcharset"
    local WIN_LIBS="-lcrypt32 -luserenv $LIBS"

    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF)
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DBUILD_SHARED_LIBS=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
        # Отключаем исполняемые файлы (bsdtar, bsdcpio), нам нужна только либа
        -DENABLE_TAR=OFF
        -DENABLE_CPIO=OFF
        -DENABLE_CAT=OFF
        -DENABLE_UNZIP=OFF
        -DENABLE_TEST=OFF
        # Включаем зависимости
        -DENABLE_ZLIB=ON
        -DENABLE_LZMA=ON
        -DENABLE_BZip2=ON
        -DENABLE_OPENSSL=ON
        -DENABLE_LIBXML2=ON
        -DENABLE_ZSTD=ON
        # Windows-специфичные опции
        -DENABLE_CNG=ON
        -DENABLE_ACL=ON
        -DENABLE_XATTR=ON
        -DLIBXML2_LIBRARIES="-lxml2"
        -DLIBXML2_INCLUDE_DIR="$FFBUILD_PREFIX/include/libxml2"
        -DCMAKE_REQUIRED_INCLUDES="$FFBUILD_PREFIX/include/libxml2"
        -DCMAKE_REQUIRED_LIBRARIES="-lxml2"
    )

    export static_flags=""
    export self_static_flags=""
    [[ "${PREFER_SHARED}" != "1" ]] && static_flags="-DLIBXML_STATIC -DXML_STATIC" && self_static_flags="-DARCHIVE_STATIC"

    CFLAGS="$CFLAGS $CPPFLAGS $self_static_flags $static_flags" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS $self_static_flags $static_flags" \
    cmake -G Ninja "${myconf[@]}" \
        -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS $DEP_LIBS $WIN_LIBS" .. || return 1

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
