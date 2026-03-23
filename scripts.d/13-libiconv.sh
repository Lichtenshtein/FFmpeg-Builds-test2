#!/bin/bash

SCRIPT_REPO="https://ftp.gnu.org/pub/gnu/libiconv/libiconv-1.18.tar.gz"

# SCRIPT_REPO2="https://git.savannah.gnu.org/git/libiconv.git"
# SCRIPT_MIRROR2="git://git.git.savannah.gnu.org/libiconv.git"
# SCRIPT_COMMIT2="30fc26493e4c6457000172d49b526be0919e34c6"

# SCRIPT_REPO3="https://git.savannah.gnu.org/git/gnulib.git"
# SCRIPT_MIRROR3="https://github.com/coreutils/gnulib.git"
# SCRIPT_COMMIT3="06f06019b66cd443e715014e4c49f64ceb61edfe"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    # default_dl .
    # echo "git-mini-clone \"$SCRIPT_MIRROR\" \"$SCRIPT_COMMIT\" ."
    # echo "git-mini-clone \"$SCRIPT_MIRROR2\" \"$SCRIPT_COMMIT2\" gnulib"
    # Качаем архив напрямую через curl
    echo "download_file \"$SCRIPT_REPO\" \"libiconv.tar.gz\""
    echo "tar -xaf libiconv.tar.gz --strip-components=1"
    echo "rm libiconv.tar.gz"
}

ffbuild_dockerbuild() {
    set -e

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --enable-extra-encodings
        --disable-shared
        --enable-static
        --with-pic
        # --disable-nls
    )

    CFLAGS="$CFLAGS" \
    CPPFLAGS="$CPPFLAGS -DICONV_STATIC" \
    LDFLAGS="$LDFLAGS" \
    CXXFLAGS="$CXXFLAGS -DICONV_STATIC" \
    LIBS="$LIBS" \
    ./configure "${myconf[@]}" || return 1

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    mkdir -p "$PC_DIR"
    cat <<EOF > "$PC_DIR/iconv.pc"
prefix=$FFBUILD_PREFIX
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: iconv
Description: Character set conversion library
Version: 1.18
Libs: -L\${libdir} -liconv
Libs.private: -lcharset $LIBS
Cflags: -I\${includedir} -DICONV_STATIC
EOF

}

ffbuild_cppflags() {
    echo "-DICONV_STATIC"
}

ffbuild_configure() {
    echo --enable-iconv
}

ffbuild_unconfigure() {
    echo --disable-iconv
}
