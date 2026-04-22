#!/bin/bash

# SCRIPT_REPO="https://github.com/TimothyGu/libilbc.git"
# SCRIPT_COMMIT="6adb26d4a4e159cd66d4b4c5e411cd3de0ab6b5e"

SCRIPT_REPO="https://github.com/mal359/libilbc.git"
SCRIPT_COMMIT="92453650e3dc53c0ca209dbf04d3153a5517a91d"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
    echo "git-submodule-clone"
}

ffbuild_dockerbuild() {
    set -e

cat <<EOF >> modules/audio_coding/codecs/ilbc/defines.h

static inline int32_t WebRtcSpl_DotProductWithScale(const int16_t* v1, const int16_t* v2, size_t len, int s) {
    int32_t sum = 0;
    for (size_t i = 0; i < len; i++) sum += (v1[i] * v2[i]) >> s;
    return sum;
}

static inline int16_t WebRtcSpl_NormW32(int32_t a) {
    if (a == 0) return 0;
    if (a < 0) a = ~a;
    int16_t count = 0;
    while (a < 0x40000000) { a <<= 1; count++; }
    return count;
}
EOF

    mkdir -p build && cd build

    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DBUILD_SHARED_LIBS=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
        -DBUILD_TESTING=OFF
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DWITH_NEON=OFF # Enable NEON optimization
        -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF)
    )

    # local EXTRA_CFLAGS="-Wno-error=implicit-function-declaration"

    CFLAGS="$CFLAGS $CPPFLAGS $EXTRA_CFLAGS" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS $EXTRA_CFLAGS" \
    LDFLAGS="$LDFLAGS" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1
}

ffbuild_configure() {
    echo --enable-libilbc
}

ffbuild_unconfigure() {
    echo --disable-libilbc
}
