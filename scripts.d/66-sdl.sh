#!/bin/bash

SCRIPT_REPO="https://github.com/libsdl-org/SDL.git"
SCRIPT_COMMIT="0e802c12c01ae0879424a13050591d7aa8304691"
SCRIPT_BRANCH="SDL2"

ffbuild_depends() {
    echo base
    echo libiconv
    echo mingw
    echo x11
    # echo fribidi
    echo vulkan-headers
    echo shaderc
    echo pulseaudio
    echo libsamplerate
    echo freeglut
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
    echo "rm -rf test"
}

ffbuild_dockerbuild() {
    set -e

    mkdir -p build && cd build

    local myconf=(
        # -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF )
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DSDL_TESTS=OFF
        -DSDL_TEST=OFF
        -DSDL_CCACHE=ON
        -DSDL_OPENGL=ON
        -DSDL_WASAPI=ON
        # force pthreads; windows threads used anyway...
        -DSDL_PTHREADS=ON
        -DSDL_THREADS=ON
        # SDL3
        # -DSDL_INSTALL_DOCS=OFF
        # -DSDL_RENDER_VULKAN=ON
        # -DSDL_AVX512F=$([ "${USE_AVX512}" == "1" ] && echo ON || echo OFF )
        # -DSDL_EXAMPLES=OFF
        # -DSDL_FRIBIDI=ON
    )

    if has_library "iconv"; then
        log_info "Iconv library detected. Building libxml2 with Iconv support..."
        myconf+=(
            -DSDL_LIBICONV=ON
            -DSDL_SYSTEM_ICONV=ON
        )
        local ICONV_LIBS="-liconv -lcharset"
    else
        log_warn "Iconv library not found. Building libxml2 without Iconv..."
        myconf+=(
            -DSDL_LIBICONV=OFF
            -DSDL_SYSTEM_ICONV=OFF
        )
    fi
    if has_library "vulkan-1"; then
        log_info "Vulkan library detected. Building with Vulkan support..."
        myconf+=(
            -DSDL_VULKAN=ON
        )
    fi
    if has_library "samplerate"; then
        log_info "Samplerate library detected. Building with Samplerate support..."
        myconf+=( -DSDL_LIBSAMPLERATE=ON )
        if [[ "${PREFER_SHARED}" == "1" ]]; then
            myconf+=( -DSDL_LIBSAMPLERATE_SHARED=ON )
        else
            myconf+=( -DSDL_LIBSAMPLERATE_SHARED=OFF )
        fi
    fi

    if [[ "${PREFER_SHARED}" == "1" ]]; then
        myconf+=(
            -DSDL_SHARED=ON
            -DSDL_STATIC=OFF
            -DSDL_FRIBIDI_SHARED=ON
        )
    else
        myconf+=(
            -DSDL_SHARED=OFF
            -DSDL_STATIC=ON
            -DSDL_STATIC_PIC=ON
        )
    fi

    if [[ $TARGET == linux* ]]; then
        myconf+=(
            -DSDL_X11=ON
            -DSDL_X11_SHARED=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
            -DHAVE_XGENERICEVENT=TRUE
            -DSDL_VIDEO_DRIVER_X11_HAS_XKBKEYCODETOKEYSYM=1
            -DSDL_PULSEAUDIO=ON
            -DSDL_PULSEAUDIO_SHARED=OFF
        )
    elif [[ $TARGET == win* ]]; then
        myconf+=(
            -DCMAKE_WIN32_EXECUTABLE=OFF
        )
    fi

    export static_flags=""
    [[ "${PREFER_SHARED}" != "1" ]] && static_flags="-DSDL_STATIC_LIB"
    local SDL_C_FLAGS="-D_REENTRANT -DSDL_MAIN_HANDLED"

    CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C} $static_flags ${SDL_C_FLAGS}" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C} $static_flags ${SDL_C_FLAGS}" \
    LDFLAGS="$LDFLAGS ${USELTO}${USELTO_L}" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    local PC_FILE="$PC_DIR/sdl2.pc"
    if [[ -f "$PC_FILE" ]]; then
        log_info "Processing sdl2.pc using precise sed automation..."
        sed -i 's/-lSDL2//g' "$PC_FILE"
        sed -i 's/-lSDL2main//g' "$PC_FILE"
        sed -i "s|^Libs:.*|Libs: -L\${libdir} -lSDL2|" "$PC_FILE"

        if [[ "${myconf[@]}" =~ "-DSDL_LIBSAMPLERATE=ON" ]]; then
            if ! grep -q "Requires:" "$PC_FILE"; then
                sed -i '/^Libs:/i Requires: samplerate' "$PC_FILE"
            else
                sed -i '/^Requires:/ s/$/ samplerate/' "$PC_FILE"
            fi
        fi

        if [[ $TARGET == linux* ]]; then
            sed -ri -e 's/\-Wl,\-\-no\-undefined.*//' -e 's/ \-l\/.+?\.a//g' "$PC_FILE"
            sed -i '/^Requires:/ s/$/ libpulse-simple xxf86vm xscrnsaver xrandr xfixes xi xinerama xcursor/' "$PC_FILE"

            if ! grep -q "Libs.private:" "$PC_FILE"; then
                sed -i '/^Libs:/a Libs.private: -lSDL2main' "$PC_FILE"
            else
                sed -i "/^Libs.private:/ s|.*|Libs.private: -lSDL2main|" "$PC_FILE"
            fi
        elif [[ $TARGET == win* ]]; then
            sed -ri -e 's/\-Wl,\-\-no\-undefined*//' \
                    -e 's/ \-mwindows//g' \
                    -e 's/ \-Dmain=SDL_main//g' \
                    "$PC_FILE"

            if ! grep -q "Libs.private:" "$PC_FILE"; then
                sed -i '/^Libs:/a Libs.private:' "$PC_FILE"
            fi

            # sed -i 's|^Libs.private:[[:space:]]*|Libs.private: -lmingw32 |' "$PC_FILE"
            sed -i 's|^Libs.private:.*|& -lkernel32 -luser32 -lgdi32 -lwinmm -limm32 -lole32 -loleaut32 -lversion -luuid -ladvapi32 -lsetupapi -lshell32 -ldinput8 -lbcrypt -lm -lshlwapi -ldbghelp -lws2_32|' "$PC_FILE"
        fi

        if [[ "${myconf[@]}" =~ "-DSDL_LIBICONV=ON" ]]; then
            sed -i "s|^Libs.private:.*|& ${ICONV_LIBS}|" "$PC_FILE"
        fi

        if [[ "${myconf[@]}" =~ "-DSDL_PTHREADS=ON" ]]; then
            sed -i "s|^Libs.private:.*|& -pthread|" "$PC_FILE"
        fi

        if [[ -n "$static_flags" ]]; then
            if ! grep -qF -- "$static_flags" "$PC_FILE"; then
                sed -i "/^Cflags:/ s/$/ ${SDL_C_FLAGS} $static_flags/" "$PC_FILE"
            fi
        else
            sed -i "/^Cflags:/ s/$/ ${SDL_C_FLAGS}/" "$PC_FILE"
        fi
        sed -i 's/  */ /g' "$PC_FILE"
        log_info "${CHECK_MARK} sdl2.pc processed successfully."
    fi
}

ffbuild_cppflags() {
    echo "$static_flags"
}

ffbuild_configure() {
    echo --enable-sdl2
}

ffbuild_unconfigure() {
    echo --disable-sdl2
}
