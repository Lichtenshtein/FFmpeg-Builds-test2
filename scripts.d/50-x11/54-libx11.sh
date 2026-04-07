#!/bin/bash

SCRIPT_REPO="https://gitlab.freedesktop.org/xorg/lib/libx11.git"
SCRIPT_COMMIT="c29b310531d47f910f48a1cb76a78a5264f7c1f8"

ffbuild_enabled() {
    [[ $TARGET != linux* ]] && return 1
    return 0
}

ffbuild_dockerbuild() {
    autoreconf -i

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --with-pic
        --without-xmlto
        --without-fop
        --without-xsltproc
        --without-lint
        --disable-specs
        --enable-ipv6
    )

    [[ "${PREFER_SHARED}" == "1" ]] && \
        myconf+=( --disable-static --enable-shared ) || \
        myconf+=( --enable-static --disable-shared )

    if [[ $TARGET == linuxarm64 ]]; then
        myconf+=(
            --disable-malloc0returnsnull
        )
    fi

    if [[ $TARGET == linux* ]]; then
        myconf+=(
            --host="$FFBUILD_TOOLCHAIN"
        )
    fi

    CFLAGS="$RAW_CFLAGS" \
    CPPFLAGS="$CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS" \
    LDFLAGS="$RAW_LDFLAGS" \
    LIBS="$LIBS" \
    ./configure "${myconf[@]}" || return 1

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    echo "Libs: -ldl" >> "$PC_DIR/x11.pc"

    gen-implib "$FFBUILD_DESTPREFIX"/lib/{libX11-xcb.so.1,libX11-xcb.a}
    gen-implib "$FFBUILD_DESTPREFIX"/lib/{libX11.so.6,libX11.a}
    rm "$FFBUILD_DESTPREFIX"/lib/libX11{,-xcb}{.so*,.la}
}
