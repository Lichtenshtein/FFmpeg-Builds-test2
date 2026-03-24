#!/bin/bash

SCRIPT_REPO="https://github.com/libsdl-org/SDL.git"
SCRIPT_COMMIT="99eca2ca0d1386a0c6ab983a2fee5413a5cd081c"
SCRIPT_BRANCH="SDL2"

ffbuild_depends() {
    echo base
    echo libiconv
    echo x11
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
    mkdir build && cd build

    local mycmake=(
        -DSDL_SHARED=OFF
        -DSDL_STATIC=ON
        -DSDL_STATIC_PIC=ON
        -DSDL_TEST=OFF
        -DSDL_CCACHE=OFF
        -DSDL_LIBSAMPLERATE=ON
        -DSDL_LIBSAMPLERATE_SHARED=OFF
    )

    if [[ $TARGET == linux* ]]; then
        mycmake+=(
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
    cmake -GNinja \
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX" "${mycmake[@]}" .. || return 1

    ninja -j$(nproc) $NINJA_V || return 1
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
