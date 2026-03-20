#!/bin/bash

SCRIPT_REPO="https://github.com/tukaani-project/xz.git"
SCRIPT_COMMIT="54147ad65af12d9e4f60a8ce59094a8a30ad5919"

ffbuild_depends() {
    echo base
    echo libiconv
    echo gettext
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e
    # Удаляем старые вспомогательные файлы, чтобы libtoolize и autoconf пересоздали их
    # rm -rf build-aux
    # mkdir -p build-aux

    # В xz autogen.sh сам вызывает все нужные инструменты в правильном порядке
    # Мы пропускаем генерацию документации и переводов для скорости
    ./autogen.sh --no-po4a --no-doxygen

    local DEP_LIBS="-lcharset -liconv -lintl $LIBS"

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --disable-symbol-versions
        --disable-shared
        --enable-static
        --with-pic
        --disable-scripts
        # --disable-nls
        --disable-doc
    )

    ./configure "${myconf[@]}" \
        CFLAGS="$CFLAGS" \
        LDFLAGS="$LDFLAGS $DEP_LIBS" \
        CPPFLAGS="$CPPFLAGS" \
        CXXFLAGS="$CXXFLAGS" \
        LIBS="$LIBS"|| return 1
    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    log_info "${SYNC_MARK} Patching LZMA .pc file..."
    for pc in "$FFBUILD_DESTDIR$FFBUILD_PREFIX"/lib/pkgconfig/liblzma.pc; do
        [[ -e "$pc" ]] || continue
        sed -i '/^Cflags:/ s/$/ -DLZMA_API_STATIC/' "$pc"
    done

    clean_la_files

    get_deps_list
}

ffbuild_cppflags() {
    echo "-DLZMA_API_STATIC"
}

ffbuild_configure() {
    echo --enable-lzma
}

ffbuild_unconfigure() {
    echo --disable-lzma
}
