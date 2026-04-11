#!/bin/bash

SCRIPT_REPO="https://github.com/tukaani-project/xz.git"
SCRIPT_COMMIT="54147ad65af12d9e4f60a8ce59094a8a30ad5919"

export SKIP_CONF_FINDER=1  # Выключаем авто-поиск

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
    ./autogen.sh --no-po4a --no-doxygen || return 1

    local DEP_LIBS="-lintl -liconv -lcharset $LIBS"

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --disable-symbol-versions
        --with-pic
        --disable-scripts
        # --disable-nls # breaks if libicu present
        --disable-doc
    )

    [[ "${PREFER_SHARED}" == "1" ]] && \
        myconf+=( --disable-static --enable-shared ) || \
        myconf+=( --enable-static --disable-shared )

    export static_flags=""
    [[ "${PREFER_SHARED}" != "1" ]] && static_flags="-DLZMA_API_STATIC"

    CFLAGS="$CFLAGS -Wno-error=implicit-function-declaration ${USELTO}" \
    CPPFLAGS="$CPPFLAGS -D_GNU_SOURCE $static_flags" \
    CXXFLAGS="$CXXFLAGS $static_flags ${USELTO}" \
    LDFLAGS="$LDFLAGS ${USELTO}" \
    LIBS="$DEP_LIBS" \
    ./configure "${myconf[@]}" || return 1

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    local PC_FILE="$PC_DIR/liblzma.pc"
    if [[ -f "$PC_FILE" ]]; then
        sed -i "/^Cflags:/ s/$/ $static_flags/" "$PC_FILE"
    fi
}

ffbuild_cppflags() {
    echo "$static_flags"
}

ffbuild_configure() {
    echo --enable-lzma
}

ffbuild_unconfigure() {
    echo --disable-lzma
}
