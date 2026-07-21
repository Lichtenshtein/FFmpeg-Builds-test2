#!/bin/bash

SCRIPT_REPO="https://github.com/cacalabs/libcaca.git"
SCRIPT_COMMIT="7c8e3338a1bda8a34297d16ac546c43548e4864d"

ffbuild_depends() {
    echo freeglut
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    ./bootstrap

    # Disable the attempt to build plugins that require native X11/GL during cross-compilation
    export ac_cv_header_x11_xlib_h=no
    # export ac_cv_header_gl_gl_h=no

    # Fixing hard-coded lib names in MinGW configure
    sed -i 's/-lGL -lGLU/-lopengl32 -lglu32/g' configure

    # Eliminate conflicts between secure string functions and MinGW
    # Rename ALL internal libcaca implementations so they don't interfere with system functions
    log_info "Renaming conflicting safe string functions in libcaca source..."
    find . -type f -name "*.c" -exec sed -i 's/\bsprintf_s\b/caca_sprintf_s/g' {} +
    find . -type f -name "*.c" -exec sed -i 's/\bvsnprintf_s\b/caca_vsnprintf_s/g' {} +
    sed -i 's/defined __KERNEL__/1/' caca/caca_types.h

    # Match and clean multi-line SUBDIRS block in root Makefile.am
    sed -i '/^SUBDIRS =/ { :loop; /\\$/ { N; b loop }; s/SUBDIRS =.*/SUBDIRS = kernel caca/ }' Makefile.am

    # Strip tests out of the sub-makefile
    sed -i 's/^SUBDIRS =.*/SUBDIRS = ./' caca/Makefile.am

    # To avoid wasting time on errors in tests, simply reset the Makefile in the tests folder
    echo "all:" > caca/t/Makefile.am
    echo "install:" >> caca/t/Makefile.am

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --disable-doc
        --disable-csharp
        --disable-java
        --disable-python
        --disable-ruby
        --disable-imlib2
        --enable-gl
        --disable-ncurses
        --disable-slang
        --disable-conio
    )

    if [[ $TARGET == linux64 ]]; then
        myconf+=(
        --enable-x11
        )
    elif [[ $TARGET == win* ]]; then
        myconf+=(
        --disable-x11
        --enable-win32
        )
    fi

    [[ "${PREFER_SHARED}" == "1" ]] && \
        myconf+=( --disable-static --enable-shared ) || \
        myconf+=( --enable-static --disable-shared )

    export GL_LIBS="-lglut -lglu32 -lopengl32 -lgdi32 -lwinmm"
    export GL_CFLAGS=""
    export self_static_flags=""
    [[ "${PREFER_SHARED}" != "1" ]] && GL_CFLAGS="-DFREEGLUT_STATIC" && self_static_flags="-DCACA_STATIC"

    CC="${FFBUILD_CROSS_PREFIX}gcc" \
    CXX="${FFBUILD_CROSS_PREFIX}g++" \
    CFLAGS="$CFLAGS -Wno-implicit-function-declaration ${USELTO}${USELTO_C} $self_static_flags" \
    CPPFLAGS="$CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS -Wno-implicit-function-declaration ${USELTO}${USELTO_C} $self_static_flags" \
    LDFLAGS="$LDFLAGS ${USELTO}${USELTO_L}" \
    LIBS="$LIBS" \
    ./configure "${myconf[@]}" || return 1

    # Run full build and installation safely
    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    # Installing header files from the root
    mkdir -p "$INSTALL_ROOT/include"
    cp caca/caca.h caca/caca0.h caca/caca_conio.h caca/caca_types.h "$INSTALL_ROOT/include/"

    # Force __declspec(dllimport) out of headers when FFmpeg links statically
    if [[ "${PREFER_SHARED}" != "1" ]]; then
        echo "#ifndef CACA_STATIC" >> "$INSTALL_ROOT/include/caca_types.h"
        echo "#define CACA_STATIC 1" >> "$INSTALL_ROOT/include/caca_types.h"
        echo "#endif" >> "$INSTALL_ROOT/include/caca_types.h"
    fi

    local PC_FILE="$PC_DIR/caca.pc"
    if [[ -f "$PC_FILE" ]]; then
        sed -i "s|^prefix=.*|prefix=$FFBUILD_PREFIX|" "$PC_FILE"
        sed -i '/^Libs.private:/ s/$/ -lgdi32 -lwinmm/' "$PC_FILE"
        if [[ -n "$self_static_flags" ]]; then
            if ! grep -qF -- "$self_static_flags" "$PC_FILE"; then
                sed -i "/^Cflags:/ s/$/ $self_static_flags/" "$PC_FILE"
            fi
        fi
    fi
}

ffbuild_cppflags() {
    echo "$self_static_flags"
}

ffbuild_configure() {
    echo --enable-libcaca
}

ffbuild_unconfigure() {
    echo --disable-libcaca
}
