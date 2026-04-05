#!/bin/bash

SCRIPT_REPO="https://gitlab.freedesktop.org/cairo/cairo.git"
SCRIPT_COMMIT="d3a35678a2322046f6d034001f2970ed3f54a1b7"

ffbuild_depends() {
    echo zlib
    echo glib2
    echo fontconfig
    echo freetype
    echo bzlib # freetype
    echo brotli # freetype
    echo libxml2
    echo libpng
    echo pixman
    echo harfbuzz
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    # Зависимости из чит-листа в правильном порядке линковки
    local DEP_LIBS="-lfontconfig -lpixman-1 -lxml2 -lpng16 -lgio-2.0 -lgthread-2.0 -lglib-2.0 -lfreetype -lbz2 -lbrotlienc -lbrotlidec -lbrotlicommon -lz"
    # Набор системных библиотек Windows для Cairo
    local WIN_LIBS="-lgdi32 -lmsimg32 -ldwrite -ld2d1 -lwindowscodecs -lopengl32 -luuid $LIBS -lstdc++"

    # конфликт hypot в коде Cairo для MinGW
    # error: implicit declaration of function '_hypot'
    sed -i 's/#define hypot _hypot/\/\/#define hypot _hypot/' src/cairo-compiler-private.h

    mkdir _build && cd _build

    # Очищаем LDFLAGS от мусора POSIX (librt и libpthread здесь не нужны)
    # export LDFLAGS="$(echo $LDFLAGS | sed 's/-lrt//g; s/-lpthread//g')"
    export LDFLAGS=$(echo "$LDFLAGS" | sed 's/-lrt//g')

    # Remove standard flags from CFLAGS/CXXFLAGS meson sets these via options
    # export CFLAGS="$(echo $CFLAGS | sed 's/-std=gnu11//g; s/-std=c11//g')"
    # export CXXFLAGS="$(echo $CXXFLAGS | sed 's/-std=c++17//g')"

    # Ищем системный путь либ тулчейна
    # local GDI_PATH=$(${CC} -print-file-name=libgdi32.a)
    # local MINGW_SYS_LIBDIR=$(dirname "$GDI_PATH")
    # [[ "$MINGW_SYS_LIBDIR" == "." ]] && MINGW_SYS_LIBDIR="$(${CC} -print-sysroot)/lib"
    # log_debug "Looking for gdi32: $GDI_PATH"
    # log_debug "Looking for LIBDIR: $MINGW_SYS_LIBDIR"

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --cross-file=/cross.meson
        --buildtype=release
        --default-library=static
        --wrap-mode=nodownload
        -Dcpp_std=c++17
        # -Dc_std=c11
        -Dfontconfig=enabled
        -Dfreetype=enabled
        -Dglib=enabled
        -Dpng=enabled
        -Dsymbol-lookup=disabled
        -Dtee=enabled
        -Dtests=disabled
        -Dxcb=disabled
        -Dxlib=disabled
        -Dzlib=enabled
    )

    [[ "$USE_LTO" == "1" ]] && myconf+=( -Db_lto=true )

    meson setup . .. \
        "${myconf[@]}" \
        -Dc_args="$CFLAGS $CPPFLAGS -DCAIRO_WIN32_STATIC_BUILD -Dpixman_static" \
        -Dcpp_args="$CXXFLAGS $CPPFLAGS -DCAIRO_WIN32_STATIC_BUILD -Dpixman_static" \
        -Dc_link_args="$LDFLAGS $DEP_LIBS $WIN_LIBS" \
        -Dcpp_link_args="$LDFLAGS $DEP_LIBS $WIN_LIBS" || return 1

    ninja -j$(nproc) $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    for pc in cairo-dwrite-font.pc cairo.pc cairo-fc.pc cairo-ft.pc cairo-gobject.pc cairo-pdf.pc cairo-png.pc cairo-ps.pc cairo-script-interpreter.pc cairo-script.pc cairo-svg.pc cairo-tee.pc cairo-win32-font.pc cairo-win32.pc; do
    local TARGET_PC="$PC_DIR/$pc"
        if [[ -f "$TARGET_PC" ]]; then
            sed -i "s/-lrt//g" "$TARGET_PC"
            if ! grep -q "\-DCAIRO_WIN32_STATIC_BUILD" "$TARGET_PC"; then
                sed -i 's/Cflags:/& -DCAIRO_WIN32_STATIC_BUILD/' "$TARGET_PC"
            fi
        fi
    done
}

ffbuild_cppflags() {
    echo "-DCAIRO_WIN32_STATIC_BUILD"
}

ffbuild_libs() {
    echo "-lgdi32 -lmsimg32 -ldwrite -ld2d1 -lwindowscodecs -lopengl32 -luuid -lstdc++"
}

ffbuild_configure() {
    echo --enable-cairo
}

ffbuild_unconfigure() {
    echo --disable-cairo
}