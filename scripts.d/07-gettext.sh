#!/bin/bash

SCRIPT_REPO="https://ftp.gnu.org/pub/gnu/gettext/gettext-1.0.tar.gz"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    echo "download_file \"$SCRIPT_REPO\" \"gettext.tar.gz\""
    echo "tar -xaf gettext.tar.gz --strip-components=1"
}

ffbuild_dockerbuild() {
    set -e
    # Собираем только из подпапки gettext-runtime, чтобы не собирать тяжелые Java/C# компоненты
    cd gettext-runtime

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --disable-java
        --disable-native-java
        --disable-csharp
        --disable-libasprintf
        # --disable-nls
        --with-libiconv-prefix="$FFBUILD_PREFIX"
        --with-pic
        --with-included-gettext
        --enable-relocatable
    )

    [[ "${PREFER_SHARED}" == "1" ]] && \
        myconf+=( --disable-static --enable-shared ) || \
        myconf+=( --enable-static --disable-shared )
    [[ "${USE_OPENMP}" == "1" ]] && \
        myconf+=( --enable-openmp ) || \
        myconf+=( --disable-openmp )

    CFLAGS="$CFLAGS -Dasm=__asm__" \
    CPPFLAGS="$CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS" \
    LDFLAGS="$LDFLAGS" \
    LIBS="$LIBS" \
    ./configure "${myconf[@]}" || return 1

    # Нам нужна только библиотека intl
    cd intl
    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    mkdir -p "$PC_DIR"
    cat <<EOF > "$PC_DIR/intl.pc"
prefix=$FFBUILD_PREFIX
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: intl
Description: GNU gettext runtime library
Version: 0.26
Libs: -L\${libdir} -lintl
Libs.private: -liconv -lcharset
Cflags: -I\${includedir}
EOF

}
