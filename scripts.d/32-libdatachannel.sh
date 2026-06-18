#!/bin/bash

SCRIPT_REPO="https://github.com/paullouisageneau/libdatachannel.git"
SCRIPT_COMMIT="a542d8703bfab42a5533852e18d6d1879e01080a" 

ffbuild_depends() {
    echo openssl # 1 of 2
    echo gnutls
    echo nettle
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
    echo "git-submodule-clone"
    echo "rm -rf \
deps/json \
examples \
test"
}

ffbuild_dockerbuild() {
    set -e

    mkdir build && cd build

    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DCMAKE_POLICY_DEFAULT_CMP0069=NEW
        -DBUILD_SHARED_LIBS=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
        -DBUILD_SHARED_DEPS_LIBS=OFF
        -DUSE_GNUTLS=OFF
        -DUSE_MBEDTLS=OFF
        -DPREFER_SYSTEM_LIB=OFF
        -DUSE_SYSTEM_SRTP=OFF
        -DUSE_SYSTEM_JUICE=OFF
        -DUSE_SYSTEM_USRSCTP=OFF
        -DUSE_SYSTEM_PLOG=OFF
        -DUSE_SYSTEM_JSON=OFF
        -DNO_EXAMPLES=ON
        -DNO_TESTS=ON
        -DWARNINGS_AS_ERRORS=OFF
        -DCAPI_STDCALL=OFF
    )

    CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
    LDFLAGS="$LDFLAGS ${USELTO}" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja -j$(nproc) $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    local PC_FILE="$PC_DIR/datachannel.pc"
    if [[ -f "$PC_FILE" ]]; then
        if grep -q "Libs.private:" "$PC_FILE"; then
            sed -i '/^Libs.private:/ s/$/ -lssl -lcrypto -lws2_32 -lbcrypt -lcrypt32 -liphlpapi/' "$PC_FILE"
        else
            echo "Libs.private: -lssl -lcrypto -lws2_32 -lbcrypt -lcrypt32 -liphlpapi" >> "$PC_FILE"
        fi
    fi
}

ffbuild_configure() {
    echo --enable-libdatachannel
}

ffbuild_unconfigure() {
    echo --disable-libdatachannel
}
