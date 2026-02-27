#!/bin/bash

SCRIPT_REPO="https://github.com/libarchive/libarchive.git"
SCRIPT_COMMIT="dd897a78c662a2c7a003e7ec158cea7909557bee"

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
    rm -rf build_dir
    mkdir build_dir

    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DBUILD_SHARED_LIBS=OFF
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
    )

    # Добавляем LTO если включено
    [[ "$USE_LTO" == "1" ]] && myconf+=( -DENABLE_LTO=ON )

    cmake "${myconf[@]}" \
        -DCMAKE_C_FLAGS="$CFLAGS" \
        -DCMAKE_CXX_FLAGS="$CXXFLAGS" \
        -S . -B build_dir

    make -C build_dir -j$(nproc) $MAKE_V
    make -C build_dir install DESTDIR="$FFBUILD_DESTDIR"

    # Исправляем .pc файл для статической линковки
    # Libarchive часто не прописывает зависимости от системных либ Windows
    local PC_FILE="$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/libarchive.pc"
    if [[ -f "$PC_FILE" ]]; then
        sed -i 's/Libs.private:/& -lbcrypt -lws2_32 -luser32 -ladvapi32 -lcrypt32 /' "$PC_FILE"
    fi
}

ffbuild_configure() {
    # Libarchive обычно не включается в FFmpeg напрямую, 
    # он нужен как зависимость для других библиотек (tesseract, и т.д.)
    return 0
}

ffbuild_unconfigure() {
    return 0
}
