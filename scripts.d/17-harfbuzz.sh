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
    local WIN_LIBS="-lusp10 -lgdi32 -lrpcrt4 $LIBS"

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
    )

    [[ "$USE_LTO" == "1" ]] && myconf+=( -Db_lto=true )

    meson setup "${myconf[@]}" .. \
        -Dcpp_args="$(echo $CXXFLAGS | sed 's/-std=c++17//g') -DHARFBUZZ_STATIC -Wno-redundant-decls" \
        -Dc_args="$(echo $CFLAGS | sed 's/-std=c11//g') -DHARFBUZZ_STATIC -Wno-redundant-decls" \
        -Dc_link_args="$LDFLAGS $HARFBUZZ_DEPS $WIN_LIBS" \
        -Dcpp_link_args="$LDFLAGS $HARFBUZZ_DEPS $WIN_LIBS" || return 1

    ninja -j$(nproc) $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    clean_la_files

    for pc in "$FFBUILD_DESTDIR$FFBUILD_PREFIX"/lib/pkgconfig/*harfbuzz*.pc; do
        [[ -e "$pc" ]] || continue
        log_info "${SYNC_MARK} Patching HARFBUZZ .pc files..."
        if ! grep -q "\-DHARFBUZZ_STATIC" "$PC_FILE"; then
            sed -i 's/Cflags:/& -DHARFBUZZ_STATIC/' "$PC_FILE"
        fi
        sed -i "s|^Libs.private:.*|Libs.private: $HARFBUZZ_DEPS $WIN_LIBS|" "$PC_FILE"
    done

    get_deps_list
}
