#!/bin/bash

SCRIPT_REPO="https://github.com/paullouisageneau/libdatachannel.git"
SCRIPT_COMMIT="188ec93f6a0b01c2032ddb4c8c013118f7f30232" 

ffbuild_depends() {
    echo openssl # 1 of 2
    echo gnutls # 1 of 2
    echo nettle
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
    echo "git-submodule-clone"
    echo "rm -rf deps/json examples test"
}

ffbuild_dockerbuild() {
    set -e

    mkdir build && cd build

    local myconf=(
        # -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF)
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DBUILD_SHARED_LIBS=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
        -DBUILD_SHARED_DEPS_LIBS=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
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

    export static_flags=""
    [[ "${PREFER_SHARED}" != "1" ]] && static_flags="-DRTC_STATIC -DJUICE_STATIC"

    CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C} $static_flags" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C} $static_flags" \
    LDFLAGS="$LDFLAGS ${USELTO}${USELTO_L}" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja -j$(nproc) $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    local PC_FILE="$PC_DIR/libdatachannel.pc"
    if [[ ! -f "$PC_FILE" ]]; then
        log_info "Generating custom libdatachannel.pc for linking..."
        mkdir -p "$(dirname "$PC_FILE")"
        cat <<EOF > "$PC_FILE"
prefix=${FFBUILD_PREFIX}
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: datachannel
Description: WebRTC Data Channels and Media Transport library (C/C++)
Version: ${VER_FULL}
Libs: -L\${libdir} -ldatachannel -ljuice -lsrtp2 -lusrsctp -lws2_32 -liphlpapi
Requires: openssl
Libs.private: -lbcrypt -lcrypt32 -luserenv -lstdc++ -lsetupapi -lm -lole32 -lshlwapi -luser32 -ladvapi32 -ldbghelp -pthread
Cflags: -I\${includedir} -I\${includedir}/rtc $static_flags
EOF
    fi
}

ffbuild_cppflags() {
    echo "$static_flags"
}

ffbuild_libs() {
    echo "-ldatachannel -ljuice -lsrtp2 -lusrsctp"
}

ffbuild_configure() {
    echo --enable-libdatachannel
}

ffbuild_unconfigure() {
    echo --disable-libdatachannel
}
