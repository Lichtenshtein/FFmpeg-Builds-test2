#!/bin/bash

SCRIPT_REPO="https://github.com/harfbuzz/harfbuzz.git"
SCRIPT_COMMIT="381b5d7cd42bb41f6d2395c8ef239cb71749ce0b"

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
    local DEP_LIBS="-lcairo -lpixman-1 -lfontconfig -lexpat -lfreetype -lpng16 -lbrotlidec -lbrotlicommon -lz -lbz2 -lglib-2.0 -lintl -liconv -lshlwapi -lsicuin -lsicuuc -lsicudt"
    local WIN_LIBS="-lusp10 -lgdi32 -lrpcrt4 -lsetupapi -lws2_32"

    local myconf=(
        --cross-file=/cross.meson
        --prefix="$FFBUILD_PREFIX"
        --libdir=lib
        --buildtype=release
        --default-library=static
        -Dfreetype=enabled
        -Dicu=enabled
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
        -Dcpp_args="$CXXFLAGS -DHARFBUZZ_STATIC"
        -Dc_args="$CFLAGS -DHARFBUZZ_STATIC"
    )

    [[ "$USE_LTO" == "1" ]] && myconf+=( -Db_lto=true )

    meson setup "${myconf[@]}" .. \
        -Dc_link_args="$LDFLAGS $DEP_LIBS $WIN_LIBS $LIBS" \
        -Dcpp_link_args="$LDFLAGS $DEP_LIBS $WIN_LIBS $LIBS"

    ninja -j$(nproc) $NINJA_V
    DESTDIR="$FFBUILD_DESTDIR" ninja install

    # Массовый патч .pc файлов
    log_info "Patching Harfbuzz .pc files..."
    for pc in harfbuzz.pc harfbuzz-icu.pc harfbuzz-cairo.pc; do
        local PC_PATH="$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/$pc"
        [[ -f "$PC_PATH" ]] || continue
        # Форсируем статику и полный хвост зависимостей
        sed -i "s|^Cflags:.*|& -DHARFBUZZ_STATIC|" "$PC_PATH"
        sed -i "s|^Libs.private:.*|Libs.private: $DEP_LIBS $WIN_LIBS $LIBS|" "$PC_PATH"
    done

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
