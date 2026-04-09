#!/bin/bash

SCRIPT_REPO="https://github.com/libsdl-org/SDL.git"
SCRIPT_COMMIT="99eca2ca0d1386a0c6ab983a2fee5413a5cd081c"
SCRIPT_BRANCH="SDL2"

ffbuild_depends() {
    echo base
    echo libiconv
    echo x11
    echo fribidi
    echo vulkan-headers
    echo shaderc
    echo pulseaudio
    echo libsamplerate
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
        -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF )
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DSDL_TESTS=OFF
        -DSDL_EXAMPLES=OFF
        -DSDL_CCACHE=ON
        -DSDL_LIBSAMPLERATE=ON
        -DSDL_INSTALL_DOCS=OFF
        -DSDL_LIBICONV=ON
        -DSDL_OPENGL=ON
        -DSDL_PTHREADS=ON
        -DSDL_FRIBIDI=ON
        -DSDL_WASAPI=ON
        -DSDL_VULKAN=ON
        -DSDL_RENDER_VULKAN=ON
        -DSDL_AVX512F=$([ "${USE_AVX512}" == "1" ] && echo ON || echo OFF )
    )

    if [[ "${PREFER_SHARED}" == "1" ]]; then
        myconf+=(
            -DSDL_SHARED=ON
            -DSDL_STATIC=OFF
            -DSDL_FRIBIDI_SHARED=ON
            -DSDL_LIBSAMPLERATE_SHARED=ON
        )
    else
        myconf+=(
            -DSDL_SHARED=OFF
            -DSDL_STATIC=ON
            -DSDL_STATIC_PIC=ON
            -DSDL_LIBSAMPLERATE_SHARED=OFF
        )
    fi

    if [[ $TARGET == linux* ]]; then
        myconf+=(
            -DSDL_X11=ON
            -DSDL_X11_SHARED=OFF
            -DHAVE_XGENERICEVENT=TRUE
            -DSDL_VIDEO_DRIVER_X11_HAS_XKBKEYCODETOKEYSYM=1
            -DSDL_PULSEAUDIO=ON
            -DSDL_PULSEAUDIO_SHARED=OFF
        )
    fi

    CFLAGS="$CFLAGS $CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS" \
    LDFLAGS="$LDFLAGS" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    if [[ $TARGET == linux* ]]; then
        sed -ri -e 's/\-Wl,\-\-no\-undefined.*//' \
            -e 's/ \-l\/.+?\.a//g' \
            "$PC_DIR/sdl2.pc"
        echo 'Requires: libpulse-simple xxf86vm xscrnsaver xrandr xfixes xi xinerama xcursor' >> "$PC_DIR/sdl2.pc"
    elif [[ $TARGET == win* ]]; then
        sed -ri -e 's/\-Wl,\-\-no\-undefined.*//' \
            -e 's/ \-mwindows//g' \
            -e 's/ \-lSDL2main//g' \
            -e 's/ \-Dmain=SDL_main//g' \
            "$PC_DIR/sdl2.pc"
    fi

    sed -ri -e 's/ -lSDL2//g' \
        -e 's/Libs: /Libs: -lSDL2 /'\
        "$PC_DIR/sdl2.pc"

    echo 'Requires: samplerate' >> "$PC_DIR/sdl2.pc"
}

ffbuild_configure() {
    echo --enable-sdl2
}

ffbuild_unconfigure() {
    echo --disable-sdl2
}
