#!/bin/bash

SCRIPT_REPO="https://https.git.savannah.gnu.org/git/libiconv.git"
SCRIPT_MIRROR="git://git.git.savannah.gnu.org/libiconv.git"
SCRIPT_COMMIT="30fc26493e4c6457000172d49b526be0919e34c6"

SCRIPT_REPO2="https://https.git.savannah.gnu.org/git/gnulib.git"
SCRIPT_MIRROR2="https://github.com/coreutils/gnulib.git"
SCRIPT_COMMIT2="075df63ae24e351535a5f2c7b6b3b3acb2ed9a1a"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    echo "git-mini-clone \"$SCRIPT_MIRROR\" \"$SCRIPT_COMMIT\" ."
    echo "git-mini-clone \"$SCRIPT_MIRROR2\" \"$SCRIPT_COMMIT2\" gnulib"
}

ffbuild_dockerbuild() {
    # No automake 1.18 packaged anywhere yet.
    sed -i 's/-1.18/-1.16/' Makefile.devel libcharset/Makefile.devel

    (unset CC CFLAGS GMAKE && ./autogen.sh)

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --enable-extra-encodings
        --disable-shared
        --enable-static
        --with-pic
    )

    if [[ $TARGET == win* || $TARGET == linux* ]]; then
        myconf+=(
            --host="$FFBUILD_TOOLCHAIN"
        )
    else
        echo "Unknown target"
        return -1
    fi

    ./configure "${myconf[@]}"
    make -j$(nproc)
    make install DESTDIR="$FFBUILD_DESTDIR"

    # создаем pkg-config файл, так как libiconv этого не делает
    mkdir -p "$FFBUILD_DESTPREFIX/lib/pkgconfig"
    cat <<EOF > "$FFBUILD_DESTPREFIX/lib/pkgconfig/iconv.pc"
prefix=$FFBUILD_PREFIX
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: iconv
Description: Character set conversion library
Version: 1.17
Libs: -L\${libdir} -liconv
Cflags: -I\${includedir}
EOF
}

ffbuild_configure() {
    echo --enable-iconv
}

ffbuild_unconfigure() {
    echo --disable-iconv
}
