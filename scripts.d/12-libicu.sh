#!/bin/bash

SCRIPT_REPO="https://github.com/winlibs/icu4c.git"
SCRIPT_COMMIT="25b56cd344f49183b7c20909cb0558bf81d93673"

# SCRIPT_REPO="https://github.com/unicode-org/icu.git"
# SCRIPT_COMMIT="426cea1b85e82e632dc5c0b35c7d329c0eb4af7b"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e
    [[ -d "source" ]] && cd source

    unset CC CXX LD AR CPP LIBS CCAS
    unset CFLAGS CXXFLAGS LDFLAGS CPPFLAGS CCASFLAGS
    # Используем runConfigureICU для правильной инициализации под Linux
    mkdir -p host-build && cd host-build

    log_info "${BUILD_MARK} Building ICU Host tools..."
    # Нам НУЖНЫ tools на хосте, чтобы создать icupkg
    CC=gcc CXX=g++ AR=ar RANLIB=ranlib CFLAGS="" CXXFLAGS="" LDFLAGS="" \
    ../runConfigureICU Linux --prefix="$(pwd)/install" \
        --enable-tools \
        --disable-tests \
        --disable-samples \
        --disable-icuio \
        --disable-extras \
        --enable-static \
        --enable-shared || return 1
    
    # Собираем только самое необходимое для инструментов
    make -j$(nproc) $MAKE_V || return 1
    make install || return 1
    cd ..

    # Проверка: если icupkg не собрался, дальше идти нет смысла
    if [[ ! -f "host-build/bin/icupkg" ]]; then
        log_error "ERROR: icupkg not found in host-build/bin!"
        return 1
    fi

    log_info "${BUILD_MARK} Building ICU Target (Win64)..."
    # Теперь основная сборка под Windows (Target)
    mkdir -p target-build && cd target-build

    # ПРЕДВАРИТЕЛЬНО создаем структуру папок, чтобы install не падал
    mkdir -p "$FFBUILD_DESTDIR$FFBUILD_PREFIX/bin"
    mkdir -p "$PC_DIR"

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

    CFLAGS="$RAW_CFLAGS" \
    CPPLAGS="$RAW_CPPLAGS -DICU_STATIC" \
    CXXFLAGS="$RAW_CXXFLAGS -DICU_STATIC" \
    LDFLAGS="$RAW_LDFLAGS" \
    CC="$CC" \
    CXX="$CXX" \
    AR="$AR" \
    RANLIB="$RANLIB" \
    ../configure "${myconf[@]}" || return 1

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    # Исправление и перемещение библиотек
    # Если ICU собрался как libicuuc.a, а мы хотим sicuuc.a:
    cd "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib"
    for lib in libicu*.a; do
        if [[ -f "$lib" ]]; then
            # Переименовываем libicu... в libsicu...
            mv "$lib" "s${lib#lib}" 2>/dev/null || true
        fi
    done
    # Исправляем специфичный sicudt (иногда он без 'lib' вначале)
    [[ -f "icudt.a" ]] && mv "icudt.a" "libsicudt.a"
    [[ -f "sicudt.a" ]] && mv "sicudt.a" "libsicudt.a"

    local ICU_SYS_LIBS="-lstdc++ -lpthread -lm -ladvapi32 -lws2_32"
    for pc in "$PC_DIR"/icu-*.pc; do
        [[ -e "$pc" ]] || continue
        # Меняем имена библиотек (icu -> sicu)
        sed -i 's/-licu/-lsicu/g' "$pc"
        # Добавляем статический флаг
        if ! grep -q "DICU_STATIC" "$pc"; then
            sed -i '/^Cflags:/ s/$/ -DICU_STATIC/' "$pc"
        fi
        # Вычищаем системные либы из основной строки Libs
        # (Удаляем ${baselibs}, -lpthread, -lm, так как они пойдут в private)
        sed -i 's/\${baselibs}//g; s/-lpthread//g; s/-lm//g' "$pc"
        # обработка Libs.private (без дубликатов в конце файла)
        if grep -q "^Libs.private:" "$pc"; then
            sed -i "s|^Libs.private:.*|Libs.private: $ICU_SYS_LIBS|" "$pc"
        else
            # Вставляем ПОСЛЕ строки Libs, а не в конец файла
            sed -i "/^Libs:/ a Libs.private: $ICU_SYS_LIBS" "$pc"
        fi
        # наличие -lsicudt только ОДИН раз
        if ! grep -q -- "-lsicudt" "$pc"; then
            sed -i '/^Libs:/ s/$/ -lsicudt/' "$pc"
        fi
    done

}
