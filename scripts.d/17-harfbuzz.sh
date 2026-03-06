#!/bin/bash

SCRIPT_REPO="https://github.com/harfbuzz/harfbuzz.git"
SCRIPT_COMMIT="381b5d7cd42bb41f6d2395c8ef239cb71749ce0b"

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
        -Dcpp_args="$CXXFLAGS -DHARFBUZZ_STATIC -Wno-redundant-decls"
        -Dc_args="$CFLAGS -DHARFBUZZ_STATIC -Wno-redundant-decls"
    )

    [[ "$USE_LTO" == "1" ]] && myconf+=( -Db_lto=true )

    meson setup "${myconf[@]}" .. \
        -Dc_link_args="$LDFLAGS $HARFBUZZ_DEPS $LIBS" \
        -Dcpp_link_args="$LDFLAGS $HARFBUZZ_DEPS $LIBS"

    ninja -j$(nproc) $NINJA_V
    DESTDIR="$FFBUILD_DESTDIR" ninja install

    clean_la_files

    # Патчим .pc для последующих этапов
    sed -i "s|^Libs.private:.*|Libs.private: $HARFBUZZ_DEPS $LIBS -lusp10 -lgdi32 -lrpcrt4|" "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/harfbuzz.pc"

    get_deps_list
}
