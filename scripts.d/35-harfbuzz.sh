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
    local DEP_LIBS="-lcairo -lpixman-1 -lfontconfig -lfreetype -lpng16 -lbrotlidec -lbrotlicommon -lz -lbz2 -lglib-2.0 -lintl -liconv -lshlwapi -lsicuin -lsicuuc -lsicudt"
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
        -Dcpp_args="$(echo $CXXFLAGS | sed 's/-std=c++17//g') -DHARFBUZZ_STATIC -Wno-redundant-decls"
        -Dc_args="$(echo $CFLAGS | sed 's/-std=c11//g') -DHARFBUZZ_STATIC -Wno-redundant-decls"
    )

    [[ "$USE_LTO" == "1" ]] && myconf+=( -Db_lto=true )

    meson setup "${myconf[@]}" .. \
        -Dc_link_args="$LDFLAGS $DEP_LIBS $WIN_LIBS" \
        -Dcpp_link_args="$LDFLAGS $DEP_LIBS $WIN_LIBS" || return 1

    ninja -j$(nproc) $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    clean_la_files

    # log_info "Patching Harfbuzz .pc files..."
    # for pc in harfbuzz.pc harfbuzz-icu.pc harfbuzz-cairo.pc; do
        # local PC_PATH="$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/$pc"
        # [[ -f "$PC_PATH" ]] || continue
        # sed -i "s|^Cflags:.*|& -DHARFBUZZ_STATIC|" "$PC_PATH"
        # sed -i "s|^Libs.private:.*|Libs.private: $DEP_LIBS $WIN_LIBS|" "$PC_PATH"
    # done

    get_deps_list
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
