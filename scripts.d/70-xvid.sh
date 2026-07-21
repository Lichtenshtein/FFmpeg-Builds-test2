#!/bin/bash

SCRIPT_REPO="https://github.com/m-ab-s/xvid.git"
SCRIPT_COMMIT="04bccf378d628d78efe28e39b0a94f0c206664a9"
SCRIPT_BRANCH="mabs"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    cd xvidcore/build/generic

    # The original code fails on a two-digit major
    sed -i 's/GCC_MAJOR=.*/GCC_MAJOR=4/' configure.in
    sed -i 's/GCC_MINOR=.*/GCC_MINOR=0/' configure.in

    ./bootstrap.sh

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        # other existing options
        #--enable-idebug
        #--enable-iprofile
        #--enable-gnuprofile
        #--disable-assembly
        #--disable-pthread
    )

    # Xvid crashes with LTO
    CFLAGS="$CFLAGS ${NOLTO} -fcommon -fomit-frame-pointer" \
    CPPFLAGS="$CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS ${NOLTO}" \
    LDFLAGS="$LDFLAGS ${NOLTO}" \
    LIBS="$LIBS" \
    ./configure "${myconf[@]}" || return 1

    [[ "${PREFER_SHARED}" != "1" ]] && sed -i 's/SHARED_LIB =.*/SHARED_LIB =/' Makefile

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    local PC_FILE="$PC_DIR/xvidcore.pc"
    mkdir -p "$PC_DIR"
    cat <<EOF > "$PC_FILE"
prefix=$FFBUILD_PREFIX
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: xvidcore
Description: Xvid MPEG-4 open-source video codec library
Version: ${VER_FULL}
Libs: -L\${libdir} -lxvidcore
Libs.private: -pthread
Cflags: -I\${includedir}
EOF
}

ffbuild_configure() {
    echo --enable-libxvid
}

ffbuild_unconfigure() {
    echo --disable-libxvid
}
