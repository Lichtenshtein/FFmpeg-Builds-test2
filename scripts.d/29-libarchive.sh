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
    rm -rf build_dir
    mkdir build_dir

    # Используем pkg-config, чтобы получить полный список либ для libxml2 (со всеми зависимостями)
    local XML2_LIBS=$(pkg-config --libs --static libxml-2.0)

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
        -DLIBXML2_LIBRARIES="$XML2_LIBS"
        -DLIBXML2_INCLUDE_DIR="$FFBUILD_PREFIX/include/libxml2"
        -DCMAKE_C_FLAGS="$CFLAGS -DLIBXML_STATIC -DXML_STATIC -DARCHIVE_STATIC"
    )

    # Добавляем LTO если включено
    [[ "$USE_LTO" == "1" ]] && myconf+=( -DENABLE_LTO=ON )

    cmake "${myconf[@]}" -S . -B build_dir

    make -C build_dir -j$(nproc) $MAKE_V
    make -C build_dir install DESTDIR="$FFBUILD_DESTDIR"

    # Исправляем .pc файл для статической линковки
    # Libarchive часто не прописывает зависимости от системных либ Windows
    local PC_FILE="$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/libarchive.pc"
    if [[ -f "$PC_FILE" ]]; then
        # В статической линковке порядок важен: высокоуровневые либы идут ПЕРЕД низкоуровневыми
        # libarchive -> libxml2 -> [lzma, zlib, iconv] -> [ws2_32, bcrypt]
        sed -i "s|^Libs.private:.*|Libs.private: $XML2_LIBS -llzma -lzstd -lbz2 -lz -lcrypt32 -lbcrypt -lws2_32 -luser32 -ladvapi32|" "$PC_FILE"
    fi

    # Вызываем отладку зависимостей
    get_deps_list
}

ffbuild_cppflags() {
    echo "-DARCHIVE_STATIC"
}

ffbuild_configure() {
    return 0
}

ffbuild_unconfigure() {
    return 0
}
