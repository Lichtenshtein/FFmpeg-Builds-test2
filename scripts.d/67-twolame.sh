#!/bin/bash

SCRIPT_REPO="https://github.com/njh/twolame.git"
SCRIPT_COMMIT="6fced852d4d5cfad58cf9dbe3ea619b08e87d398"

# SCRIPT_REPO="https://github.com/IObundle/twolame.git"
# SCRIPT_COMMIT="b995218213887a57a702334730ed86f82749348e"

export SKIP_CONF_FINDER=1

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    # libtoolize version detection is broken, disable it, we got the right versions
    printf 'print "999999\\n"\n' > autogen-get-version-mock.pl
    sed -i -e 's|/autogen-get-version.pl|/autogen-get-version-mock.pl|g' ./autogen.sh

    NOCONFIGURE=1 ./autogen.sh

    mkdir -p doc
    touch doc/twolame.1

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --with-pic
        --disable-sndfile
        --disable-maintainer-mode
    )

    export static_flags=""
    [[ "${PREFER_SHARED}" != "1" ]] && static_flags="-DLIBTWOLAME_STATIC"
    [[ "${PREFER_SHARED}" == "1" ]] && \
        myconf+=( --disable-static --enable-shared ) || \
        myconf+=( --enable-static --disable-shared )

    CFLAGS="$CFLAGS ${USELTO}" \
    CPPFLAGS="$CPPFLAGS $static_flags" \
    CXXFLAGS="$CXXFLAGS $static_flags ${USELTO}" \
    LDFLAGS="$LDFLAGS ${USELTO}" \
    LIBS="$LIBS" \
    ./configure "${myconf[@]}" || return 1

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    local PC_FILE="$PC_DIR/twolame.pc"
    if [[ -f "$PC_FILE" ]]; then
        if [[ -n "$static_flags" ]]; then
            if ! grep -qF -- "$static_flags" "$PC_FILE"; then
                sed -i "/^Cflags:/ s/$/ $static_flags/" "$PC_FILE"
            fi
        fi
    fi
}

ffbuild_cppflags() {
    echo "$static_flags"
}

ffbuild_configure() {
    echo --enable-libtwolame
}

ffbuild_unconfigure() {
    echo --disable-libtwolame
}
