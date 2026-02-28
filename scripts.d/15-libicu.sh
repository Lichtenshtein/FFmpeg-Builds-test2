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
    [[ -d "source" ]] && cd source

    unset CC CXX LD AR CPP LIBS CCAS
    unset CFLAGS CXXFLAGS LDFLAGS CPPFLAGS CCASFLAGS
    # Используем runConfigureICU для правильной инициализации под Linux
    mkdir -p host-build && cd host-build
    
    # Нам НУЖНЫ tools на хосте, чтобы создать icupkg
    CC=gcc CXX=g++ AR=ar RANLIB=ranlib CFLAGS="" CXXFLAGS="" LDFLAGS="" \
    ../runConfigureICU Linux --prefix="$(pwd)/install" \
        --enable-tools \
        --disable-tests \
        --disable-samples \
        --disable-icuio \
        --disable-extras \
        --enable-static \
        --enable-shared
    
    # Собираем только самое необходимое для инструментов
    make -j$(nproc)
    make install
    cd ..

    # Проверка: если icupkg не собрался, дальше идти нет смысла
    if [[ ! -f "host-build/bin/icupkg" ]]; then
        echo "ERROR: icupkg not found in host-build/bin!"
        return 1
    fi

    # Теперь основная сборка под Windows (Target)
    mkdir -p target-build && cd target-build

    # ПРЕДВАРИТЕЛЬНО создаем структуру папок, чтобы install не падал
    mkdir -p "$FFBUILD_DESTDIR$FFBUILD_PREFIX/bin"
    mkdir -p "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig"

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

    # Исправление и перемещение библиотек
    # ICU иногда кидает sicudt.a в /bin, переместим её в /lib
    if [[ -f "$FFBUILD_DESTDIR$FFBUILD_PREFIX/bin/sicudt.a" ]]; then
        mv "$FFBUILD_DESTDIR$FFBUILD_PREFIX/bin/sicudt.a" "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/libsicudt.a"
    fi

    # Исправляем pkg-config файлы для статической линковки
    # ICU по умолчанию создает icu-uc.pc, icu-i18n.pc
    # Патчим .pc файлы для корректной работы с FFmpeg
    for pc in "$FFBUILD_DESTDIR$FFBUILD_PREFIX"/lib/pkgconfig/icu-*.pc; do
        if [[ -f "$pc" ]]; then
            log_info "Patching $(basename "$pc") for FFmpeg static linking..."
            # Заменяем стандартные имена на статические префиксы 's'
            sed -i 's/-licuin/-lsicuin/g' "$pc"
            sed -i 's/-licuuc/-lsicuuc/g' "$pc"
            sed -i 's/-licudata/-lsicudata/g' "$pc"
            # Если в файле упоминается icudt, меняем на sicudt
            sed -i 's/-licudt/-lsicudt/g' "$pc"
            
            # Добавляем системные либы и обеспечиваем наличие -lsicudt
            sed -i '/Libs.private:/ s/$/ -lpthread -lm -ladvapi32 -lws2_32/' "$pc"
            if ! grep -q -- "-lsicudt" "$pc"; then
                sed -i '/Libs:/ s/$/ -lsicudt/' "$pc"
            fi
        fi
    done
}
