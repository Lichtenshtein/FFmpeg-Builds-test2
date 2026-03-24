#!/bin/bash

SCRIPT_REPO="https://github.com/harfbuzz/harfbuzz.git"
SCRIPT_COMMIT="3db272507d23e2335bdd2c30903f466452edd344"

ffbuild_depends() {
    echo freetype
    echo libicu
    echo glib2
    echo cairo
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

    # порядок линковки критичен для статики
    local DEP_LIBS="-lcairo-gobject -lcairo -lgio-2.0 -lgthread-2.0 -lglib-2.0 -lz -lfreetype -lsicuin -lsicuuc -lsicudt"
    local WIN_LIBS="-lusp10 -lgdi32 -lrpcrt4 $LIBS"

    local myconf=(
        --cross-file=/cross.meson
        --prefix="$FFBUILD_PREFIX"
        --libdir=lib
        --buildtype=release
        --default-library=static
        -Dfreetype=enabled
        -Dicu=enabled
        -Dcpp_std=c++17
        -Dc_std=c11
        -Dwith_libstdcxx=true
        -Draster=enabled
        -Dvector=enabled
        -Dsubset=enabled
        -Dglib=enabled
        -Dgobject=disabled
        -Dcairo=enabled
        -Dchafa=disabled
        -Dtests=disabled
        -Dintrospection=disabled
        -Ddocs=disabled
        -Ddoc_tests=false
        -Dutilities=disabled
        -Ddirectwrite=enabled
        -Dgdi=enabled
        -Dbenchmark=disabled
    )

    [[ "$USE_LTO" == "1" ]] && myconf+=( -Db_lto=true )

    meson setup "${myconf[@]}" .. \
        -Dc_args="$CFLAGS $CPPFLAGS -DHARFBUZZ_STATIC -DCAIRO_WIN32_STATIC_BUILD -Wno-redundant-decls" \
        -Dcpp_args="$CXXFLAGS $CPPFLAGS -DHARFBUZZ_STATIC -DCAIRO_WIN32_STATIC_BUILD -Wno-redundant-decls" \
        -Dc_link_args="$LDFLAGS $DEP_LIBS $WIN_LIBS" \
        -Dcpp_link_args="$LDFLAGS $DEP_LIBS $WIN_LIBS" || return 1

    ninja -j$(nproc) $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    if ls "$PC_DIR"/*harfbuzz*.pc >/dev/null 2>&1; then
        for pc in "$PC_DIR"/*harfbuzz*.pc; do
            [[ -e "$pc" ]] || continue
            if ! grep -q "HARFBUZZ_STATIC" "$pc"; then
                sed -i '/^Cflags:/ s/$/ -DHARFBUZZ_STATIC/' "$pc"
            fi
        done
    fi

}

ffbuild_cppflags() {
    echo "-DHARFBUZZ_STATIC"
}

ffbuild_configure() {
    echo --enable-libharfbuzz
}

ffbuild_unconfigure() {
    echo --disable-libharfbuzz
}
