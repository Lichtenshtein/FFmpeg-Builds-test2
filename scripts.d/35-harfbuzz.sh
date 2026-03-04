#!/bin/bash

SCRIPT_REPO="https://github.com/harfbuzz/harfbuzz.git"
SCRIPT_COMMIT="81ce4813c1d2ba1cf2f06aa2d2892aae7156bcaf"

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

    local DEP_LIBS=$(pkg-config --libs --static freetype2 glib-2.0 icu-uc cairo)
    local CFLAGS="$CFLAGS -DHARFBUZZ_STATIC"
    local CXXFLAGS="$CXXFLAGS -DHARFBUZZ_STATIC"

    local myconf=(
        --cross-file=/cross.meson
        --prefix="$FFBUILD_PREFIX"
        --libdir=lib
        --buildtype=release
        --default-library=static
        -Dfreetype=enabled
        -Dcpp_std=c++17
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
        # Передаем либы через link_args, чтобы тесты Cairo не падали
        -Dcpp_args="$CXXFLAGS"
        -Dc_args="$CFLAGS"
        -Dc_link_args="$LDFLAGS $DEP_LIBS $LIBS"
        -Dcpp_link_args="$LDFLAGS $DEP_LIBS $LIBS"
    )

    meson setup "${myconf[@]}" ..

    ninja -j$(nproc) $NINJA_V
    DESTDIR="$FFBUILD_DESTDIR" ninja install

    log_info "Patching Harfbuzz .pc files..."
    for pc in harfbuzz.pc harfbuzz-icu.pc harfbuzz-cairo.pc; do
        local PC_PATH="$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/$pc"
        if [[ -f "$PC_PATH" ]]; then
            # Гарантируем наличие флага статики и системных либ
            sed -i "/^Cflags:/ s/$/ -DHARFBUZZ_STATIC/" "$PC_PATH"
            sed -i "/^Libs.private:/ s/$/ $DEP_LIBS -lusp10 -lgdi32 -lrpcrt4 -lstdc++/" "$PC_PATH"
        fi
    done

    get_deps_list
}

ffbuild_cppflags() {
    echo "-DHARFBUZZ_STATIC"
}

ffbuild_configure() {
    (( $(ffbuild_ffver) > 600 )) || return 0
    echo --enable-libharfbuzz
}

ffbuild_unconfigure() {
    (( $(ffbuild_ffver) > 600 )) || return 0
    echo --disable-libharfbuzz
}
