#!/bin/bash

SCRIPT_REPO="https://gitlab.freedesktop.org/cairo/cairo.git"
SCRIPT_COMMIT="d3a35678a2322046f6d034001f2970ed3f54a1b7"

ffbuild_depends() {
    echo zlib
    echo glib2
    echo fontconfig
    echo freetype
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

    # Определяем путь к sysroot тулчейна для поиска gdi32, opengl32 и т.д.
    local MINGW_SYSROOT=$($CC -print-sysroot)
    local MINGW_LIBDIR="${MINGW_SYSROOT}/lib"
    local MINGW_INCDIR="${MINGW_SYSROOT}/include"

    cat <<EOF > cairo_cross.txt
[include]
'/cross.meson'

[host_machine]
system = 'windows'
cpu_family = 'x86_64'
cpu = 'x86_64'
endian = 'little'

[binaries]
c = '${FFBUILD_TOOLCHAIN}-gcc'
cpp = '${FFBUILD_TOOLCHAIN}-g++'
ar = '${FFBUILD_TOOLCHAIN}-gcc-ar'
pkg-config = 'pkg-config'
strip = '${FFBUILD_TOOLCHAIN}-strip'
windres = '${FFBUILD_TOOLCHAIN}-windres'
nm = '${FFBUILD_TOOLCHAIN}-gcc-nm'
ranlib = '${FFBUILD_TOOLCHAIN}-gcc-ranlib'
nasm = '/usr/bin/nasm'

[properties]
sys_root = '${MINGW_SYSROOT}'
pkg_config_libdir = '${FFBUILD_PREFIX}/lib/pkgconfig:${MINGW_LIBDIR}/pkgconfig'
c_args = ['-I${FFBUILD_PREFIX}/include', '-I${MINGW_INCDIR}', '-DCAIRO_WIN32_STATIC_BUILD']
cpp_args = ['-I${FFBUILD_PREFIX}/include', '-I${MINGW_INCDIR}', '-DCAIRO_WIN32_STATIC_BUILD']
c_link_args = ['-L${FFBUILD_PREFIX}/lib', '-L${MINGW_LIBDIR}', '-static-libgcc', '-static-libstdc++']
cpp_link_args = ['-L${FFBUILD_PREFIX}/lib', '-L${MINGW_LIBDIR}', '-static-libgcc', '-static-libstdc++']
EOF

find "${MINGW_SYSROOT}" -name "gdi32*" || true

    # Набор системных библиотек Windows для Cairo
    local WIN_LIBS="-lgdi32 -lmsimg32 -ldwrite -ld2d1 -lwindowscodecs -lopengl32 -lole32 -luuid"
    # Зависимости из чит-листа в правильном порядке линковки
    local DEP_LIBS="-lfontconfig -lexpat -lfreetype -lharfbuzz -lharfbuzz-icu -lsicuin -lsicuuc -lsicudt -lpixman-1 -lpng16 -lz -lbz2 -lbrotlidec -lbrotlicommon -lglib-2.0 -lintl -liconv -lcharset"

    mkdir build && cd build

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        # --cross-file=/cross.meson
        --cross-file ../cairo_cross.txt
        --buildtype=release
        --default-library=static
        --wrap-mode=nodownload
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

    # meson setup "${myconf[@]}" ..
        # -Dc_args="$CFLAGS -DCAIRO_WIN32_STATIC_BUILD -I${MINGW_INCDIR}"
        # -Dcpp_args="$CXXFLAGS -DCAIRO_WIN32_STATIC_BUILD -I${MINGW_INCDIR}"

    meson setup . .. \
        "${myconf[@]}" \
        -Dc_link_args="$LDFLAGS -L${MINGW_LIBDIR} $DEP_LIBS $WIN_LIBS $LIBS" \
        -Dcpp_link_args="$LDFLAGS -L${MINGW_LIBDIR} $DEP_LIBS $WIN_LIBS $LIBS"

    ninja -j$(nproc) $NINJA_V
    DESTDIR="$FFBUILD_DESTDIR" ninja install

    clean_la_files

    # Патчинг .pc файлов
    local PC_FILE="$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/cairo.pc"
    if [[ -f "$PC_FILE" ]]; then
        log_info "${SYNC_MARK} Patching cairo.pc for static linking..."
        # Форсируем макрос статики в Cflags
        sed -i "/^Cflags:/ s/$/ -DCAIRO_WIN32_STATIC_BUILD/" "$PC_FILE"
        # Прописываем полный хвост зависимостей в Libs.private
        # Порядок: cairo -> pixman -> fontconfig -> freetype -> harfbuzz -> [icu/glib/zlib/iconv]
        sed -i "s|^Libs.private:.*|Libs.private: $DEP_LIBS $WIN_LIBS $LIBS|" "$PC_FILE"
    fi

    # Дополнительно патчим cairo-win32.pc и cairo-gobject.pc если они есть
    for pc in cairo-win32.pc cairo-gobject.pc cairo-ft.pc; do
        local TARGET_PC="$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/$pc"
        [[ -f "$TARGET_PC" ]] && sed -i "/^Cflags:/ s/$/ -DCAIRO_WIN32_STATIC_BUILD/" "$TARGET_PC"
    done

    get_deps_list
}

ffbuild_cppflags() {
    echo "-DCAIRO_WIN32_STATIC_BUILD"
}
