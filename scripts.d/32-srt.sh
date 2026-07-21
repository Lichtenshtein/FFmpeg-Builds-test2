#!/bin/bash

SCRIPT_REPO="https://github.com/Haivision/srt.git"
SCRIPT_COMMIT="c39196c9a568ae4e3289dd65cf54ba4154deb4a1"

ffbuild_depends() {
    echo base
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
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DCMAKE_POLICY_DEFAULT_CMP0069=NEW
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DENABLE_CXX_DEPS=ON
        -DENABLE_ENCRYPTION=ON
        -DENABLE_LOGGING=OFF
        -DENABLE_APPS=OFF
    )

    [[ "${PREFER_SHARED}" == "1" ]] && \
        myconf+=( -DENABLE_STATIC=OFF -DENABLE_SHARED=ON -DUSE_STATIC_LIBSTDCXX=OFF ) || \
        myconf+=( -DENABLE_STATIC=ON -DENABLE_SHARED=OFF -DUSE_STATIC_LIBSTDCXX=ON )

    CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
    LDFLAGS="$LDFLAGS ${USELTO}${USELTO_L}" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    if [ -d "$PC_DIR" ]; then
        find "$PC_DIR" -name "*srt*.pc" | while read -r PC_FILE; do
            # Replace the absolute path to libstdc++.a
            sed -i 's|/opt/ct-ng/[^ ]*/libstdc++.a|-lstdc++|g' "$PC_FILE"
            # Just in case, remove any quotation marks
            sed -i 's|["'\'']||g' "$PC_FILE"
        done
    fi
}

ffbuild_configure() {
    echo --enable-libsrt
}

ffbuild_unconfigure() {
    echo --disable-libsrt
}
