#!/bin/bash

SCRIPT_REPO="https://ftp.gnu.org/pub/gnu/libiconv/libiconv-1.19.tar.gz"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    echo "download_file \"$SCRIPT_REPO\" \"libiconv.tar.gz\""
    echo "tar -xaf libiconv.tar.gz --strip-components=1"
    echo "rm libiconv.tar.gz"
    echo "rm -rf tests install-tests"
}

ffbuild_dockerbuild() {
    set -e

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --enable-extra-encodings
        --with-pic
        # --disable-nls
    )

    export static_flags=""
    [[ "${PREFER_SHARED}" != "1" ]] && static_flags="-DICONV_STATIC"
    [[ "${PREFER_SHARED}" == "1" ]] && \
        myconf+=( --disable-static --enable-shared ) || \
        myconf+=( --enable-static --disable-shared )

    local C_FLAGS="-Wno-pointer-to-int-cast"

    CFLAGS="$CFLAGS ${USELTO}${USELTO_C} ${C_FLAGS}" \
    CPPFLAGS="$CPPFLAGS $static_flags" \
    CXXFLAGS="$CXXFLAGS $static_flags ${USELTO}${USELTO_C} ${C_FLAGS}" \
    LDFLAGS="$LDFLAGS ${USELTO}${USELTO_L}" \
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
Version: ${VER_FULL}
Libs: -L\${libdir} -liconv
Libs.private: -lcharset
Cflags: -I\${includedir} $static_flags
EOF
}

ffbuild_cppflags() {
    echo "$static_flags"
}

ffbuild_configure() {
    echo --enable-iconv
}

ffbuild_unconfigure() {
    echo --disable-iconv
}
