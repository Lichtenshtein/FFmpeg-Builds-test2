20-libiconv.sh

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
    # echo "git-mini-clone \"$SCRIPT_MIRROR\" \"$SCRIPT_COMMIT\" ."
    # echo "git-mini-clone \"$SCRIPT_MIRROR2\" \"$SCRIPT_COMMIT2\" gnulib"
    # Качаем архив напрямую через curl
    echo "download_file \"$SCRIPT_REPO\" \"libiconv.tar.gz\""
    echo "tar -xaf libiconv.tar.gz --strip-components=1"
    echo "rm libiconv.tar.gz"
}

ffbuild_dockerbuild() {
    # No automake 1.18 packaged anywhere yet.
    # sed -i 's/-1.18/-1.17/' Makefile.devel libcharset/Makefile.devel

    # Для релизного тарбола autogen НЕ НУЖЕН
    # (unset CC CFLAGS GMAKE && ./autogen.sh)

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --enable-extra-encodings
        --disable-shared
        --enable-static
        --with-pic
    )

    ./configure "${myconf[@]}"
    make -j$(nproc) $MAKE_V
    make install DESTDIR="$FFBUILD_DESTDIR"

    # создаем pkg-config файл, так как libiconv этого не делает
    mkdir -p "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig"
    cat <<EOF > "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/iconv.pc"
prefix=$FFBUILD_PREFIX
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: iconv
Description: Character set conversion library
Version: 1.18
Libs: -L\${libdir} -liconv
Libs.private: -liconv
Cflags: -I\${includedir}
EOF
}

ffbuild_configure() {
    echo --enable-iconv
}

ffbuild_unconfigure() {
    echo --disable-iconv
}
