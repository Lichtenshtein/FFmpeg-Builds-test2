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

    local DEP_LIBS="-lharfbuzz-cairo -lcairo -lcairo-gobject -lharfbuzz-subset -lharfbuzz-vector -lharfbuzz-raster -lfontconfig -lharfbuzz -lfreetype -lglib-2.0 -lgio-2.0 -lgobject-2.0 -lfribidi"
    local STATIC_DEPS="-DCAIRO_WIN32_STATIC_BUILD -DPANGO_STATIC_COMPILATION -DG_WIN32_IS_STRICT_MINGW -Dpixman_static"
    local WIN_LIBS="-lusp10 -lgdi32 -lmsimg32 -lruntimeobject -ldwrite -ld2d1 -lwindowscodecs -luuid $LIBS -lstdc++"
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
        -Dc_args="$CFLAGS $CPPFLAGS $STATIC_DEPS" \
        -Dcpp_args="$CXXFLAGS $CPPFLAGS $STATIC_DEPS" \
        -Dc_link_args="$LDFLAGS $DEP_LIBS $WIN_LIBS" \
        -Dcpp_link_args="$LDFLAGS $DEP_LIBS $WIN_LIBS" || return 1

    ninja -j$(nproc) $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    for pc in "$PC_DIR"/*pango*.pc; do
        [[ -e "$pc" ]] || continue
        if ! grep -q "\--DPANGO_STATIC_COMPILATION" "$PC_FILE"; then
            sed -i 's/Cflags:/& --DPANGO_STATIC_COMPILATION/' "$PC_FILE"
        fi
    done

}
