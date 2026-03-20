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
    mkdir build_dir && cd build_dir

    local XML2_DEPS="-lxml2 -lzstd -llzma -lbz2 -lz -lintl -liconv -lcharset -lsicuin -lsicuuc -lsicudt"
    local ARCHIVE_DEPS="-lcrypto -lssl $XML2_DEPS $LIBS"

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
        -DLIBXML2_LIBRARIES="$XML2_DEPS"
        -DLIBXML2_INCLUDE_DIR="$FFBUILD_PREFIX/include/libxml2"
        -DCMAKE_REQUIRED_INCLUDES="$FFBUILD_PREFIX/include/libxml2"
        -DCMAKE_REQUIRED_LIBRARIES="$XML2_DEPS"
    )

    [[ "$USE_LTO" == "1" ]] && myconf+=( -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=ON )

    cmake "${myconf[@]}" \
        -DCMAKE_C_FLAGS="$CFLAGS -DARCHIVE_STATIC -DLIBXML_STATIC -DXML_STATIC" \
        -DCMAKE_CXX_FLAGS="$CXXFLAGS -DARCHIVE_STATIC -DLIBXML_STATIC -DXML_STATIC" \
        -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS $ARCHIVE_DEPS" .. || return 1

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    clean_la_files

    local PC_FILE="$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/libarchive.pc"
    if [[ -f "$PC_FILE" ]]; then
        log_info "${SYNC_MARK} Patching libarchive.pc..."
        # Гарантируем макрос статики (некоторые ищут его в Cflags, а не в Cflags.private)
        sed -i "/^Cflags:/ s/$/ -DARCHIVE_STATIC/" "$PC_FILE"
        # Собираем чистую строку зависимостей без дубликатов
        # Мы берем ваш ARCHIVE_DEPS и добавляем системные либы Windows
        local CLEAN_LIBS=$(echo "$ARCHIVE_DEPS -lcrypt32 -luserenv" | xargs -n1 | sort -u | xargs)
        sed -i "s|^Libs.private:.*|Libs.private: $CLEAN_LIBS|" "$PC_FILE"
    fi

    get_deps_list
}
