#!/bin/bash

SCRIPT_REPO="https://github.com/kcat/openal-soft.git"
SCRIPT_COMMIT="dc98bfbe6064d851e32428db83b06732a448810b"

ffbuild_depends() {
    echo sdl
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    mkdir -p cm_build && cd cm_build

    local myconf=(
        # -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF )
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DALSOFT_UTILS=OFF
        -DALSOFT_NO_CONFIG_UTIL=ON # Disable building the alsoft-config utility
        -DALSOFT_INSTALL=ON
        -DALSOFT_EXAMPLES=OFF
        -DALSOFT_TESTS=OFF
        -DALSOFT_EMBED_HRTF_DATA=ON
        -DALSOFT_CPUEXT_SSE4_1=ON
        -DALSOFT_REQUIRE_SSE4_1=ON
        -DALSOFT_DLOPEN=OFF
        # -DALSOFT_BUILD_MODULES=OFF
    )

    if [[ "${PREFER_SHARED}" == "1" ]]; then
        myconf+=(
        -DALSOFT_STATIC_STDCXX=OFF
        -DALSOFT_STATIC_LIBGCC=OFF
        -DLIBTYPE=SHARED
        -DALSOFT_BUILD_ROUTER=ON
        -DALSOFT_BUILD_IMPORT_LIB=ON
        )
    else
        myconf+=(
        -DALSOFT_STATIC_STDCXX=ON
        -DALSOFT_STATIC_LIBGCC=ON
        -DALSOFT_STATIC_WINPTHREAD=ON
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
        -DALSOFT_EAX=ON
        -DALSOFT_BACKEND_WASAPI=ON
        -DALSOFT_BACKEND_DSOUND=ON
        -DALSOFT_BACKEND_WINMM=ON
        # -DALSOFT_BACKEND_SDL2=ON
        -DALSOFT_BACKEND_ALSA=OFF
        -DALSOFT_BACKEND_OSS=OFF
        -DALSOFT_BACKEND_PULSEAUDIO=OFF
        )
    fi

    CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
    LDFLAGS="$LDFLAGS ${USELTO}" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    local PRIVATE_LIBS="-lwinpthread -lavrt -latomic -lm -luuid -lwinmm -lz -lstdc++"
    local PC_FILE="$PC_DIR/openal.pc"
    if [[ -f "$PC_FILE" ]]; then
        # Удаляем существующую строку Libs.private целиком
        sed -i '/^Libs.private:/d' "$PC_FILE"
        # Записываем новую чистую строку
        echo "Libs.private: $PRIVATE_LIBS" >> "$PC_FILE"
    fi
}

ffbuild_configure() {
    echo --enable-openal
}

ffbuild_unconfigure() {
    echo --disable-openal
}
