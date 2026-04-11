#!/bin/bash

SCRIPT_REPO="https://gitlab.com/libssh/libssh-mirror.git"
SCRIPT_COMMIT="34db488e4db8c66175c3ec4e31e724173b5263a3"

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

    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF)
        -DBUILD_SHARED_LIBS=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
        -DWITH_EXAMPLES=OFF
        -DWITH_SERVER=OFF
        -DWITH_SFTP=ON
        -DWITH_ZLIB=ON
    )

    export static_flags=""
    [[ "${PREFER_SHARED}" != "1" ]] && static_flags="-DLIBSSH_STATIC"

    CFLAGS="$CFLAGS $CPPFLAGS $static_flags -Dmd5=libssh_md5" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS $static_flags -Dmd5=libssh_md5" \
    LDFLAGS="$LDFLAGS" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    local PC_FILE="$PC_DIR/libssh.pc"
    if [[ -f "$PC_FILE" ]]; then
        sed -i '/^Cflags:/ s/$/ $static_flags -Dmd5=libssh_md5/' "$PC_FILE"
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
