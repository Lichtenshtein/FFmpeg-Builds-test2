#!/bin/bash
SCRIPT_REPO="https://gitlab.gnome.org/GNOME/pango.git"
SCRIPT_COMMIT="748d1adc10abc917bd27e12ac9e013409c7f58f8"

ffbuild_depends() {
    echo fontconfig
    echo freetype
    echo glib2
    echo cairo
    echo fribidi
    echo harfbuzz
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
    echo "git-submodule-clone"
}

ffbuild_dockerbuild() {
    set -e
    mkdir build && cd build

    local PANGO_DEPS="-lcairo -lharfbuzz-subset -lharfbuzz-vector -lharfbuzz-raster -lharfbuzz -lharfbuzz-cairo -lfreetype -lpixman-1 -lfontconfig -lpng16 -lglib-2.0 -lgobject-2.0 -lxml2 -lfribidi -lbrotlidec -lbrotlicommon -lz -lbz2 -lintl -liconv -lcharset -lsicuin -lsicuuc -lsicudt"
    local STATIC_DEPS="-DCAIRO_WIN32_STATIC_BUILD -DPANGO_STATIC_COMPILATION -DG_WIN32_IS_STRICT_MINGW -Dpixman_static"
    local WIN_SYS="-lusp10 -lgdi32 -lmsimg32 -lruntimeobject -ldwrite -ld2d1 -lwindowscodecs -luuid -lstdc++ $LIBS"
    export CC="x86_64-w64-mingw32-g++"

    local LDFLAGS=$(echo "$LDFLAGS" | sed 's/-lssp//g')

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --cross-file=/cross.meson
        --buildtype=release
        --default-library=static
        --wrap-mode=nodownload
        # -Dcpp_std=c++17
        # -Dc_std=c11
        -Dintrospection=disabled
        -Dfontconfig=enabled
        -Dfreetype=enabled
        -Dsysprof=disabled
        -Ddocumentation=false
        -Dbuild-testsuite=false
        -Dbuild-examples=false
        -Dman-pages=false
    )

    [[ "$USE_LTO" == "1" ]] && myconf+=( -Db_lto=true )

    meson setup "${myconf[@]}" .. \
        -Dc_args="$CFLAGS $STATIC_DEPS" \
        -Dcpp_args="$CXXFLAGS $STATIC_DEPS" \
        -Dc_link_args="$LDFLAGS $PANGO_DEPS $WIN_SYS" \
        -Dcpp_link_args="$LDFLAGS $PANGO_DEPS $WIN_SYS" || return 1

    ninja -j$(nproc) $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    clean_la_files

    log_info "${SYNC_MARK} Patching Pango .pc files for static link..."
    for pc in pango.pc pangocairo.pc pangoft2.pc pangowin32.pc; do
        local PC_PATH="$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/$pc"
        [[ -f "$PC_PATH" ]] || continue
        sed -i "/^Cflags:/ s/$/ -DPANGO_STATIC_COMPILATION/" "$PC_PATH"
        sed -i "s|^Libs.private:.*|Libs.private: $PANGO_DEPS $WIN_SYS|" "$PC_PATH"
    done

    get_deps_list
}

ffbuild_cppflags() {
    echo "-DPANGO_STATIC_COMPILATION"
}
