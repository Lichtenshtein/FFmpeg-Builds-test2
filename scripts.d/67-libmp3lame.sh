#!/bin/bash

SCRIPT_REPO="https://github.com/Luiz-Monad/liblame.git"
SCRIPT_COMMIT="fe309eb331421ee6534ba795dbc298e19093f96f"

ffbuild_depends() {
    echo base
    echo libiconv
    echo libmpg123
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    # Forced config repair for modern systems
    if [ -f configure.ac ]; then
        sed -i 's/AC_PREREQ(2.69)/AC_PREREQ(2.71)/' configure.ac || true
    fi

    # Avoid building unnecessary stuff
    # It's important to keep libmp3lame and include
    # mpglib is needed if you don't use an external library for decoding
    sed -i '/SUBDIRS = mpglib/,/vc_solution/c\SUBDIRS = mpglib libmp3lame include' Makefile.am

    autoreconf -fi

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --with-pic
        --enable-nasm
        --enable-expopt=no # full/norm/no; Whether to enable experimental optimizations
        --disable-gtktest
        # --disable-decoder # Exclude mpg123 decoder
        --disable-frontend # Do not build the lame executable
        # --enable-mp3x # Build GTK frame analyzer
    )

    [[ "${PREFER_SHARED}" == "1" ]] && \
        myconf+=( --disable-static --enable-shared ) || \
        myconf+=( --enable-static --disable-shared )

    local FLAGS="-ffast-math -Wno-implicit-function-declaration -Wno-int-conversion -Wno-error=incompatible-pointer-types"

    CFLAGS="$CFLAGS $FLAGS ${USELTO}${USELTO_C}" \
    CPPFLAGS="$CPPFLAGS -DNDEBUG -D_ALLOW_INTERNAL_OPTIONS" \
    CXXFLAGS="$CXXFLAGS $FLAGS ${USELTO}${USELTO_C}" \
    LDFLAGS="$LDFLAGS ${USELTO}${USELTO_L}" \
    ac_cv_sizeof_short=2 \
    ac_cv_sizeof_int=4 \
    ac_cv_sizeof_long=4 \
    ac_cv_sizeof_long_long=8 \
    ac_cv_sizeof_float=4 \
    ac_cv_sizeof_double=8 \
    LIBS="$LIBS" \
    ./configure "${myconf[@]}" || return 1

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    mkdir -p "$PC_DIR"
    if [[ ! -f "${PC_DIR}/mp3lame.pc" ]]; then
        cat <<EOF > "${PC_DIR}/mp3lame.pc"
prefix=${FFBUILD_PREFIX}
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: lame
Description: High quality MPEG Audio Layer III (MP3) open-source encoder
Version: ${VER_FULL}
Libs: -L\${libdir} -lmp3lame
Libs.private: -lm
Cflags: -I\${includedir} -I\${includedir}/lame
EOF
    else
        sed -i "s|^Cflags:.*|& -I\${includedir}/lame|" "$PC_DIR/mp3lame.pc"
    fi
}

ffbuild_configure() {
    echo --enable-libmp3lame
}

ffbuild_unconfigure() {
    echo --disable-libmp3lame
}
