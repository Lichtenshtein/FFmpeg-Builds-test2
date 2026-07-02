#!/bin/bash

SCRIPT_REPO="https://github.com/xiph/opus.git"
SCRIPT_COMMIT="f8f99516092f4311a9b0784f190ff982df8eb2e6"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
    # This is where they decided to put downloads for external dependencies
    # https://github.com/xiph/opus/blob/main/autogen.sh
    # This highly pollutes the download log, we'll try to shut it up
    cat <<EOF
sed -i -e 's/wget /wget -q /g' \
       -e 's/tar xvzomf/tar xzomf/g' \
       -e '/tar xzomf/a rm -f \$model' dnn/download_model.sh
EOF
    echo "./autogen.sh"

    # local OPUS_DATA_URL="https://media.xiph.org/opus/models/opus_data-a5177ec6fb7d15058e99e57029746100121f68e4890b1467d4094aa336b6013e.tar.gz"
    # local OPUS_DATA_HASH="a5177ec6fb7d15058e99e57029746100121f68e4890b1467d4094aa336b6013e"
    # cat <<EOF
# mkdir -p dnn
# curl -sL --retry 10 --retry-delay 5 --connect-timeout 30 "$OPUS_DATA_URL" -o "dnn/opus_data-${OPUS_DATA_HASH}.tar.gz"
# echo "$OPUS_DATA_HASH  dnn/opus_data-${OPUS_DATA_HASH}.tar.gz" | sha256sum -c -
# tar -xzomf "dnn/opus_data-${OPUS_DATA_HASH}.tar.gz"
# rm -f "dnn/opus_data-${OPUS_DATA_HASH}.tar.gz"
# EOF

    if [[ -d ".git" ]]; then
        git add .
    fi
}

ffbuild_dockerbuild() {
    set -e

    mkdir -p build && cd build

    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DOPUS_BUILD_SHARED_LIBRARY=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
        # -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF)
        -DOPUS_BUILD_PROGRAMS=OFF
        -DOPUS_BUILD_TESTING=OFF
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DOPUS_CUSTOM_MODES=ON
        -DOPUS_FLOAT_APPROX=ON
        -DOPUS_X86_PRESUME_AVX2=ON
        -DOPUS_INSTALL_CMAKE_CONFIG_MODULE=ON
        -DOPUS_DRED=ON # neural scan and restoring for loss packets on low bitrates
        -DOPUS_OSCE=ON # AI-based speech enhancement feature
        -DOPUS_BUILD_FRAMEWORK=OFF # bundle for Apple systems
        # -DOPUS_STATIC_RUNTIME=OFF # MSVC; build with static runtime library
        -DOPUS_ENABLE_FLOAT_API=ON
        -DOPUS_HARDENING=ON
        -DOPUS_INSTALL_PKG_CONFIG_MODULE=ON
    )

    if [[ $TARGET == winarm* ]]; then
        myconf+=( -DOPUS_DISABLE_INTRINSICS=ON )
    elif [[ $TARGET == win* ]]; then
        myconf+=( -DCMAKE_SYSTEM_NAME=Windows )
    fi

    CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
    LDFLAGS="$LDFLAGS ${USELTO}${USELTO_L}" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja -j$(nproc) $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1
}

ffbuild_configure() {
    echo --enable-libopus
}

ffbuild_unconfigure() {
    echo --disable-libopus
}
