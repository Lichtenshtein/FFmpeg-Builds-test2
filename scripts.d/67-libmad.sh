#!/bin/bash
export USE_VERS_FINDER=1
# SCRIPT_REPO="https://github.com/sezero/libmad.git"
# SCRIPT_COMMIT="486f902c6c686eafced3450851849527e29bc7f6"

SCRIPT_REPO="https://github.com/dpw13/libmad.git"
SCRIPT_COMMIT="7d04821ae3580d994664a8eb98dda873609578ed"
SCRIPT_BRANCH="dev/dwagner"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    autoreconf -if

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --enable-fpm=intel # 64bit
        # --enable-speed # optimize for speed over accuracy
        --enable-accuracy # optimize for accuracy over speed
        --enable-sso
        --disable-debugging
        --enable-experimental
    )

    [[ "${PREFER_SHARED}" == "1" ]] && \
        myconf+=( --disable-static --enable-shared ) || \
        myconf+=( --enable-static --disable-shared )

    # Удаляем флаг -fforce-mem, который GCC 14 не поддерживает
    sed -i 's/-fforce-mem//g' configure

    CFLAGS="$CFLAGS ${USELTO}${USELTO_C}" \
    CPPFLAGS="$CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS ${USELTO}${USELTO_C}" \
    LDFLAGS="$LDFLAGS ${USELTO}" \
    LIBS="$LIBS" \
    ./configure "${myconf[@]}" || return 1

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    mkdir -p "${PC_DIR}"
    cat <<EOF > "${PC_DIR}/mad.pc"
prefix=${FFBUILD_PREFIX}
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: mad
Description: MPEG Audio Decoder
Version: ${VER_FULL}
Libs: -L\${libdir} -lmad
Libs.private: -lm
Cflags: -I\${includedir}
EOF
}

ffbuild_configure() {
    echo --enable-libmad
}

ffbuild_unconfigure() {
    echo --disable-libmad
}
