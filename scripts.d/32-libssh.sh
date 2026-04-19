#!/bin/bash

SCRIPT_REPO="https://gitlab.com/libssh/libssh-mirror.git"
SCRIPT_COMMIT="c853d86bb574420a2f24f99c7a400de25f122346"

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

    echo '#include <string.h>' > mingw_fix.h
    echo '#include <stdlib.h>' >> mingw_fix.h
    echo 'char *strndup(const char *s, size_t n);' >> mingw_fix.h

    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF)
        -DBUILD_SHARED_LIBS=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
        -DWITH_EXAMPLES=OFF
        -DWITH_SERVER=OFF
        -DHAVE_STRNDUP=ON
        -DWITH_SFTP=ON
        -DWITH_ZLIB=ON
        -DWITH_MBEDTLS=OFF
        -DWITH_FIDO2=OFF
        -DWITH_BLOWFISH_CIPHER=OFF
    )

    export static_flags=""
    [[ "${PREFER_SHARED}" != "1" ]] && static_flags="-DLIBSSH_STATIC"

    export MINGW_FIX_CFLAGS="-include $(pwd)/mingw_fix.h -D_GNU_SOURCE -Dmd5=libssh_md5"

    CFLAGS="$CFLAGS $CPPFLAGS $MINGW_FIX_CFLAGS $static_flags" \
    LDFLAGS="$LDFLAGS" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    mkdir -p "$PC_DIR"
    local PC_FILE="$PC_DIR/libssh.pc"
    if [[ -f "$PC_FILE" ]]; then
        sed -i '/^Cflags:/ s/$/ -Dmd5=libssh_md5/' "$PC_FILE"
        if [[ -n "$static_flags" ]]; then
            if ! grep -qF -- "$static_flags" "$PC_FILE"; then
                sed -i "/^Cflags:/ s/$/ $static_flags/" "$PC_FILE"
            fi
        fi
        if grep -q "^Libs.private:" "$PC_FILE"; then
            sed -i "s|^Libs.private:.*|Libs.private: -lssl -lz -liphlpapi|" "$PC_FILE"
        else
            sed -i "/^Libs:/ a Libs.private: -lssl -lz -liphlpapi" "$PC_FILE"
        fi
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
