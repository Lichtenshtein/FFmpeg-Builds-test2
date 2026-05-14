#!/bin/bash

SCRIPT_REPO="https://gitlab.com/libssh/libssh-mirror.git"
SCRIPT_COMMIT="effc68f71bec97e397a5b31bea56d5eff0e3cac9"

ffbuild_depends() {
    echo base
    echo zlib
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

    mkdir -p build && cd build

    # Создаем файл реализации
    cat <<EOF > mingw_fix.c
#include <string.h>
#include <stdlib.h>

char *strndup(const char *s, size_t n) {
    size_t len = strnlen(s, n);
    char *new = (char *)malloc(len + 1);
    if (new == NULL) return NULL;
    new[len] = '\0';
    return (char *)memcpy(new, s, len);
}
EOF

    # Создаем заголовочный файл
    cat <<EOF > mingw_fix.h
#ifndef MINGW_FIX_H
#define MINGW_FIX_H
#include <stddef.h>
char *strndup(const char *s, size_t n);
#endif
EOF

    # Компилируем его в объектный файл
    $CC $CFLAGS -c mingw_fix.c -o mingw_fix.o

    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        # -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF)
        -DBUILD_SHARED_LIBS=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
        -DWITH_EXAMPLES=OFF
        -DWITH_SERVER=OFF
        -DWITH_SFTP=ON
        -DWITH_ZLIB=ON
        -DWITH_MBEDTLS=OFF
        -DWITH_FIDO2=OFF
        -DWITH_BLOWFISH_CIPHER=OFF
    )

    export static_flags=""
    [[ "${PREFER_SHARED}" != "1" ]] && static_flags="-DLIBSSH_STATIC"

    CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C} $static_flags -include $(pwd)/mingw_fix.h -Dmd5=libssh_md5" \
    LDFLAGS="$LDFLAGS ${USELTO} $(pwd)/mingw_fix.o" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    mkdir -p "$PC_DIR"
    local PC_FILE="$PC_DIR/libssh.pc"
    if [[ -f "$PC_FILE" ]]; then
        sed -i "s|^Cflags:.*|& -I\${includedir}/libssh|" "$PC_FILE"
        sed -i '/^Cflags:/ s/$/ -Dmd5=libssh_md5/' "$PC_FILE"
        if [[ -n "$static_flags" ]]; then
            if ! grep -qF -- "$static_flags" "$PC_FILE"; then
                sed -i "/^Cflags:/ s/$/ $static_flags/" "$PC_FILE"
            fi
        fi
        if grep -q "^Libs.private:" "$PC_FILE"; then
            sed -i "s|^Libs.private:.*|Libs.private: -lssl -lcrypto -lz -liphlpapi|" "$PC_FILE"
        else
            sed -i "/^Libs:/ a Libs.private: -lssl -lcrypto -lz -liphlpapi" "$PC_FILE"
        fi
        log_info "Updated Cflags in $(basename "$PC_FILE")"
    fi
}

ffbuild_cppflags() {
    echo "$static_flags"
}

ffbuild_configure() {
    echo --enable-libssh
}

ffbuild_unconfigure() {
    echo --disable-libssh
}
