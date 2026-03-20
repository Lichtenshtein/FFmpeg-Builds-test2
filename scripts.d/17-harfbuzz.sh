#!/bin/bash

SCRIPT_REPO="https://github.com/harfbuzz/harfbuzz.git"
SCRIPT_COMMIT="3db272507d23e2335bdd2c30903f466452edd344"

ffbuild_depends() {
    echo freetype
    echo libicu
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

    local HARFBUZZ_DEPS="-lfreetype -lsicuin -lsicuuc -lsicudt"

    local myconf=(
        --cross-file=/cross.meson
        --prefix="$FFBUILD_PREFIX"
        --libdir=lib
        --buildtype=release
        --default-library=static
        -Dcpp_std=c++17
        -Dc_std=c11
        -Dfreetype=enabled
        -Draster=disabled
        -Dvector=disabled
        -Dsubset=enabled
        -Dglib=disabled
        -Dgobject=disabled
        -Dcairo=disabled
        -Dchafa=disabled
        -Dtests=disabled
        -Dintrospection=disabled
        -Ddocs=disabled
        -Ddoc_tests=false
        -Dutilities=disabled
        -Ddirectwrite=disabled
        -Dgdi=disabled
        -Dbenchmark=disabled
        -Dcpp_args="$(echo $CXXFLAGS | sed 's/-std=c++17//g') -DHARFBUZZ_STATIC -Wno-redundant-decls"
        -Dc_args="$(echo $CFLAGS | sed 's/-std=c11//g') -DHARFBUZZ_STATIC -Wno-redundant-decls"
    )

    [[ "$USE_LTO" == "1" ]] && myconf+=( -Db_lto=true )

    meson setup "${myconf[@]}" .. \
        -Dc_link_args="$LDFLAGS $HARFBUZZ_DEPS $LIBS" \
        -Dcpp_link_args="$LDFLAGS $HARFBUZZ_DEPS $LIBS" || return 1

    ninja -j$(nproc) $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    clean_la_files

    local PC_FILE="$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/harfbuzz.pc"
    if [[ -f "$PC_FILE" ]]; then
        sed -i "/^Cflags:/ s/$/ -DHARFBUZZ_STATIC/" "$PC_FILE"
        sed -i "s|^Libs.private:.*|Libs.private: $HARFBUZZ_DEPS $LIBS -lusp10 -lgdi32 -lrpcrt4|" "$PC_FILE"
    fi

    get_deps_list
}
