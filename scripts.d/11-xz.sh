#!/bin/bash

SCRIPT_REPO="https://github.com/tukaani-project/xz.git"
SCRIPT_COMMIT="f3b5688159c60495f48db3942a36509671dfce89"

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

    ./autogen.sh --no-po4a --no-doxygen || return 1

    local DEP_LIBS="-lintl -liconv -lcharset $LIBS"

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --with-pic
        --disable-scripts
        # --disable-nls # breaks if libicu present
        --disable-doc
        --disable-debug
        # --enable-small # if small size is preferred over speed
        --disable-xz # do not build the xz tool
        --disable-xzdec # do not build xzdec
        --disable-lzmadec # do not build lzmadec
        --disable-lzmainfo # do not build lzmainfo
        --disable-lzma-links # do not create symlinks for LZMA Utils
        --disable-doxygen 
    )

    if [[ $TARGET == win64 ]]; then
        myconf+=( --disable-symbol-versions )
    elif [[ $TARGET == linux64 ]]; then
        myconf+=( --enable-symbol-versions )
    fi

    [[ "${PREFER_SHARED}" == "1" ]] && \
        myconf+=( --disable-static --enable-shared ) || \
        myconf+=( --enable-static --disable-shared )

    export static_flags=""
    [[ "${PREFER_SHARED}" != "1" ]] && static_flags="-DLZMA_API_STATIC"

    CFLAGS="$CFLAGS -Wno-error=implicit-function-declaration ${USELTO}${USELTO_C}" \
    CPPFLAGS="$CPPFLAGS -D_GNU_SOURCE $static_flags" \
    CXXFLAGS="$CXXFLAGS $static_flags ${USELTO}${USELTO_C}" \
    LDFLAGS="$LDFLAGS ${USELTO}${USELTO_L}" \
    LIBS="$DEP_LIBS" \
    ./configure "${myconf[@]}" || return 1

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    local PC_FILE="$PC_DIR/liblzma.pc"
    sed -i "s|^Cflags:.*|& -I\${includedir}/lzma|" "$PC_FILE"
    if [[ -n "$static_flags" ]]; then
        if ! grep -qF -- "$static_flags" "$PC_FILE"; then
            sed -i "/^Cflags:/ s/$/ $static_flags/" "$PC_FILE"
        fi
    fi

    ln -sf liblzma.pc "$PC_DIR/lzma.pc"
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
