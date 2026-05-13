#!/bin/bash

SCRIPT_REPO="https://github.com/stoth68000/libklvanc.git"
SCRIPT_COMMIT="d2bec177f68fe807a8c12d3b8d18ee8208bbdc32"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    if [[ $TARGET == win64 ]]; then
        # Исправляем errno и сокеты для MinGW
        grep -rl "sys/errno.h" . | xargs sed -i 's|sys/errno.h|errno.h|g'
        grep -rl "sys/socket.h" . | xargs sed -i 's|sys/socket.h|winsock2.h|g'
        grep -rl "netinet/in.h" . | xargs sed -i 's|netinet/in.h|ws2tcpip.h|g'
        grep -rl "arpa/inet.h" . | xargs sed -i 's|arpa/inet.h|ws2tcpip.h|g'
        # отключаем сборку инструментов (tools), так как они требуют POSIX-сокеты
        sed -i 's/SUBDIRS = src tools/SUBDIRS = src/g' Makefile.am
    fi

    ./autogen.sh --build

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
    )

    [[ "${PREFER_SHARED}" == "1" ]] && \
        myconf+=( --disable-static --enable-shared ) || \
        myconf+=( --enable-static --disable-shared )

    CFLAGS="$CFLAGS ${USELTO}${USELTO_C}" \
    CPPFLAGS="$CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS ${USELTO}${USELTO_C}" \
    LDFLAGS="$LDFLAGS ${USELTO}" \
    LIBS="$LIBS" \
    ./configure "${myconf[@]}" || return 1

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    local PC_FILE="$PC_DIR/libklvanc.pc"
    if [[ -f "$PC_FILE" ]]; then
        sed -i 's/-lc //g' "$PC_FILE"
    fi
}

ffbuild_configure() {
    echo --enable-libklvanc
}

ffbuild_unconfigure() {
    echo --disable-libklvanc
}
