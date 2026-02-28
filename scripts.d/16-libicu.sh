#!/bin/bash

SCRIPT_REPO="https://github.com/winlibs/icu4c.git"
SCRIPT_COMMIT="25b56cd344f49183b7c20909cb0558bf81d93673"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    cd source

    unset CC CXX LD AR CPP LIBS CCAS
    unset CFLAGS CXXFLAGS LDFLAGS CPPFLAGS CCASFLAGS
    # ICU требует сборку под хост-систему (Linux) для генерации данных
    mkdir -p host-build && cd host-build

    ../configure --prefix="$(pwd)/install" \
        --disable-tests \
        --disable-samples \
        --disable-icuio \
        --disable-extras \
        --disable-tools
    
    make -j$(nproc)
    make install
    cd ..
    # Теперь основная сборка под Windows (Target)
    mkdir -p target-build && cd target-build

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --with-cross-build="$(pwd)/../host-build"
        --enable-static
        --disable-shared
        --disable-extras
        --disable-icuio
        --disable-layoutex
        --disable-tests
        --disable-samples
        --disable-dyload
        --disable-tools
        --disable-icu-config
        --enable-release
        --with-data-packaging=static
    )

    ../configure "${myconf[@]}" CFLAGS="$CFLAGS" CXXFLAGS="$CXXFLAGS" LDFLAGS="$LDFLAGS"
    
    make -j$(nproc) $MAKE_V
    make install DESTDIR="$FFBUILD_DESTDIR"

    # Исправляем pkg-config файлы для статической линковки
    # ICU по умолчанию создает icu-uc.pc, icu-i18n.pc
    for pc in "$FFBUILD_DESTDIR$FFBUILD_PREFIX"/lib/pkgconfig/icu-*.pc; do
        if [[ -f "$pc" ]]; then
            log_info "Patching $(basename "$pc") for static Windows linking..."
            # Добавляем необходимые системные библиотеки Windows для статики
            sed -i '/Libs.private:/ s/$/ -lpthread -lm -ladvapi32 -lws2_32/' "$pc"
            # Иногда ICU не прописывает -licudt (данные) в Libs, добавим на всякий случай
            sed -i '/Libs:/ s/$/ -licudt/' "$pc"
        fi
    done
}
