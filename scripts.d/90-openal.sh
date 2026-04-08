#!/bin/bash

SCRIPT_REPO="https://github.com/kcat/openal-soft.git"
SCRIPT_COMMIT="266538011d2fc8ee875abed0be43a537d0e59743"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e
    mkdir cm_build && cd cm_build

    local myconf=(
        -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF )
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DLIBTYPE=$([ "${PREFER_SHARED}" == "1" ] && echo SHARED || echo STATIC)
        -DALSOFT_UTILS=OFF
        -DALSOFT_EXAMPLES=OFF
        -DALSOFT_TESTS=OFF
        -DALSOFT_EMBED_HRTF_DATA=ON
        -DALSOFT_CPUEXT_SSE4_1=ON
        -DALSOFT_REQUIRE_SSE4_1=ON
        -DALSOFT_DLOPEN=OFF
    )

    if [[ "${PREFER_SHARED}" == "1" ]]; then
        myconf+=(
        -DALSOFT_STATIC_STDCXX=OFF
        -DALSOFT_STATIC_LIBGCC=OFF
        -DLIBTYPE=SHARED
        )
    else
        myconf+=(
        -DALSOFT_STATIC_STDCXX=ON
        -DALSOFT_STATIC_LIBGCC=ON
        -DLIBTYPE=STATIC
        )
    fi
    if [[ $TARGET == linux* ]]; then
        myconf+=(
        -DALSOFT_BACKEND_ALSA=ON
        -DALSOFT_BACKEND_OSS=ON
        -DALSOFT_BACKEND_PULSEAUDIO=ON
        )
    else
        myconf+=(
        -DALSOFT_BACKEND_ALSA=OFF
        -DALSOFT_BACKEND_OSS=OFF
        -DALSOFT_BACKEND_PULSEAUDIO=OFF
        )
    fi

    CFLAGS="$CFLAGS $CPPFLAGS -include stdlib.h" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS -include cstdlib" \
    LDFLAGS="$LDFLAGS" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    echo "Libs.private: -lstdc++" >> "$PC_DIR/openal.pc"

    if [[ $TARGET == win* ]]; then
        echo "Libs.private: -lole32 -luuid -lwinmm" >> "$PC_DIR/openal.pc"
    fi

}

ffbuild_configure() {
    echo --enable-openal
}

ffbuild_unconfigure() {
    echo --disable-openal
}
