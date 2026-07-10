#!/bin/bash

SCRIPT_REPO="https://github.com/alanxz/rabbitmq-c.git"
SCRIPT_COMMIT="df773fde0177fcd135bbcda4160950ae3ee19477"

ffbuild_depends() {
    echo openssl
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    # Исправляем регистр для WinSock2.h -> winsock2.h
    grep -rli "winsock2.h" . | xargs sed -i 's/[Ww][Ii][Nn][Ss][Oo][Cc][Kk]2\.h/winsock2.h/g'

    mkdir -p build && cd build

    local myconf=(
        # -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF )
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DBUILD_API_DOCS=OFF
        -DBUILD_EXAMPLES=OFF
        -DBUILD_OSSFUZZ=OFF
        -DBUILD_TOOLS=OFF
        -DCMAKE_BUILD_TYPE=Release
        -DENABLE_SSL_SUPPORT=ON
        -DRUN_SYSTEM_TESTS=OFF
        )

    [[ "${PREFER_SHARED}" == "1" ]] && \
        myconf+=( -DBUILD_SHARED_LIBS=ON -DBUILD_STATIC_LIBS=OFF ) || \
        myconf+=( -DBUILD_SHARED_LIBS=OFF -DBUILD_STATIC_LIBS=ON -DINSTALL_STATIC_LIBS=ON )

    CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
    LDFLAGS="$LDFLAGS ${USELTO}${USELTO_L}" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    local DEST_LIB="${INSTALL_ROOT}/lib"
    if [[ "${PREFER_SHARED}" != "1" ]]; then
        # исправление имен liblib -> lib
        pushd "${DEST_LIB}"
        for f in liblib*.a; do
            if [ -f "$f" ]; then
                newname=$(echo "$f" | sed 's/^liblib/lib/')
                log_info "Renaming double prefix: $f to $newname"
                mv -f "$f" "$newname"
            fi
        done
        # Удаляем мажорную версию из имени файла (.4.a -> .a)
        for f in librabbitmq.*.a; do
            if [ -f "$f" ]; then
                log_info "Fixing versioned static library name: $f to librabbitmq.a"
                mv -f "$f" "librabbitmq.a"
            fi
        done
        popd
    fi

    mkdir -p "$PC_DIR"
    if [ -d "$PC_DIR" ]; then
        find "$PC_DIR" -name "*.pc" | while read -r PC_FILE; do
            sed -i "s|^Cflags:.*|& -I\${includedir}/rabbitmq-c|" "$PC_FILE"
        done
        log_info "Cflags paths have been updated."
    fi
}

ffbuild_configure() {
    echo --enable-librabbitmq
}

ffbuild_unconfigure() {
    echo --disable-librabbitmq
}
