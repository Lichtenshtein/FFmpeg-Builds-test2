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
    # Собираем только из подпапки gettext-runtime, чтобы не собирать тяжелые Java/C# компоненты
    cd gettext-runtime

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --disable-shared
        --enable-static
        --disable-java
        --disable-native-java
        --disable-csharp
        --disable-libasprintf
        --disable-openmp
        --with-libiconv-prefix="$FFBUILD_PREFIX"
        --with-pic
    )

    ./configure "${myconf[@]}"
    
    # Нам нужна только библиотека intl
    cd intl
    make -j$(nproc) $MAKE_V
    make install DESTDIR="$FFBUILD_DESTDIR"

    # Gettext тоже плохо дружит с pkg-config, создадим его вручную
    mkdir -p "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig"
    cat <<EOF > "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/intl.pc"
prefix=$FFBUILD_PREFIX
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: intl
Description: GNU gettext runtime library
Version: 1.0
Libs: -L\${libdir} -lintl
Libs.private: -liconv
Cflags: -I\${includedir}
EOF
}
