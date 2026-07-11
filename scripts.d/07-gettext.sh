#!/bin/bash

SCRIPT_REPO="https://ftp.gnu.org/pub/gnu/gettext/gettext-1.0.tar.gz"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    echo "download_file \"$SCRIPT_REPO\" \"gettext.tar.gz\""
    echo "tar -xaf gettext.tar.gz --strip-components=1"
    echo "rm -f gettext.tar.gz"
    # Агрессивная очистка неиспользуемых тяжелых компонентов
    echo "rm -rf gnulib-local libtextstyle"
    # Очищаем gettext-tools, но подменяем Makefile, чтобы верхний configure не падал
    echo "rm -rf gettext-tools/*"
    echo "mkdir -p gettext-tools"
    echo "echo 'all: ;' > gettext-tools/Makefile.in"
    echo "echo 'install: ;' >> gettext-tools/Makefile.in"
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
        --enable-pic
        --enable-year2038
        --with-included-gettext
        --enable-relocatable
        --enable-threads=posix
    )

    [[ "${PREFER_SHARED}" == "1" ]] && \
        myconf+=( --disable-static --enable-shared ) || \
        myconf+=( --enable-static --disable-shared )
    [[ "${USE_OPENMP}" == "1" ]] && \
        myconf+=( --enable-openmp ) || \
        myconf+=( --disable-openmp )

    CFLAGS="$CFLAGS -Dasm=__asm__ ${OPENMP_C}${USELTO}${USELTO_C}" \
    CPPFLAGS="$CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS -Dasm=__asm__ ${OPENMP_C}${USELTO}${USELTO_C}" \
    LDFLAGS="$LDFLAGS ${USELTO}${USELTO_L}" \
    LIBS="${OPENMP_LIB}$LIBS" \
    ./configure "${myconf[@]}" || return 1

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
Version: ${VER_FULL}
Libs: -L\${libdir} -lintl
Libs.private: -liconv -lcharset ${OPENMP_LIB} -pthread
Cflags: -I\${includedir}
EOF
}
