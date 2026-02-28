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
    # ICU требует сборку под хост-систему (Linux) для генерации данных
    mkdir host-build && cd host-build
    ../source/configure --prefix=$(pwd)/install
    make -j$(nproc) $MAKE_V
    make install
    cd ..

    # Теперь основная сборка под Windows (Target)
    mkdir target-build && cd target-build

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

    # Применяем флаги компилятора
    export CFLAGS="$CFLAGS"
    export CXXFLAGS="$CXXFLAGS"

    ../source/configure "${myconf[@]}"
    
    make -j$(nproc) $MAKE_V
    make install DESTDIR="$FFBUILD_DESTDIR"

    # Исправляем pkg-config файлы для статической линковки
    # ICU генерирует несколько файлов: icu-i18n.pc, icu-uc.pc и т.д.
    for pc in "$FFBUILD_DESTDIR$FFBUILD_PREFIX"/lib/pkgconfig/icu-*.pc; do
        if [[ -f "$pc" ]]; then
            log_info "Patching $(basename "$pc") for static linking..."
            # В Windows статической ICU часто нужны либы advapi32 и т.д.
            sed -i '/Libs.private:/ s/$/ -ladvapi32 -lws2_32/' "$pc"
        fi
    done
}
