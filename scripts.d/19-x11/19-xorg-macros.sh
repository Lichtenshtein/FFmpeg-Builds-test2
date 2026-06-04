#!/bin/bash

SCRIPT_REPO="https://gitlab.freedesktop.org/xorg/util/macros.git"
SCRIPT_COMMIT="a9d71e3fd8e6758b70be31c586921bbbcd2a8449"

ffbuild_depends() {
    return 0
}

ffbuild_enabled() {
    [[ $TARGET != linux* ]] && return 1
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerlayer() {
    to_df "COPY --link --from=${SELFLAYER} \$INSTALL_ROOT/. \$FFBUILD_PREFIX"
    to_df "COPY --link --from=${SELFLAYER} \$INSTALL_ROOT/share/aclocal/. /usr/share/aclocal"
}

ffbuild_dockerbuild() {
    set -e

    autoreconf -i

    CFLAGS="$RAW_CFLAGS ${USELTO}${USELTO_C}" \
    CPPFLAGS="$CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS ${USELTO}${USELTO_C}" \
    LDFLAGS="$RAW_LDFLAGS ${USELTO}" \
    LIBS="$LIBS" \
    ./configure --prefix="$FFBUILD_PREFIX" || return 1

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1
}
