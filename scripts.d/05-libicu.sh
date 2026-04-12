#!/bin/bash

# SCRIPT_REPO="https://github.com/winlibs/icu4c.git"
# SCRIPT_COMMIT="25b56cd344f49183b7c20909cb0558bf81d93673"

SCRIPT_REPO="https://github.com/unicode-org/icu.git"
SCRIPT_COMMIT="3377fe3dc221b9eb090ac407a996bb5d764e0b6b"

export USE_CONF_FINDER=0

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e
    # [[ -d "source" ]] && cd source
    cd icu4c/source

    unset CC CXX LD AR CPP LIBS CCAS
    unset CFLAGS CXXFLAGS LDFLAGS CPPFLAGS CCASFLAGS
    # Используем runConfigureICU для правильной инициализации под Linux
    mkdir -p host-build && cd host-build

    log_info "${BUILD_MARK} Building ICU Host tools..."
    # Нам НУЖНЫ tools на хосте, чтобы создать icupkg
    CC=gcc CXX=g++ AR=ar RANLIB=ranlib CFLAGS="" CXXFLAGS="" LDFLAGS="" \
    ../runConfigureICU Linux --prefix="$(pwd)/install" \
        --enable-tools \
        --disable-release \
        --disable-tests \
        --disable-samples \
        --disable-icuio \
        --disable-extras \
        --disable-layoutex \
        --disable-dyload \
        --disable-strict \
        --disable-icu-config \
        --disable-plugins \
        --with-data-packaging=$([ "${PREFER_SHARED}" == "1" ] && echo library || echo static) \
        --enable-$([ "${PREFER_SHARED}" == "1" ] && echo shared || echo static) \
        --disable-$([ "${PREFER_SHARED}" == "1" ] && echo static || echo shared) \
        || return 1
    
    # Собираем только самое необходимое для инструментов
    make -j$(nproc) $MAKE_V || return 1
    make install || return 1
    cd ..

    # Проверка: если icupkg не собрался, дальше идти нет смысла
    if [[ ! -f "host-build/bin/icupkg" ]]; then
        log_error "icupkg not found in host-build/bin!"
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
        --disable-extras
        --disable-icuio
        --disable-layoutex
        --disable-tests
        --disable-plugins
        --disable-samples
        --disable-strict # supress warnings
        --disable-dyload
        --disable-tools
        --disable-icu-config
        --enable-release
        --with-data-packaging=$([ "${PREFER_SHARED}" == "1" ] && echo library || echo static)
    )

    [[ "${PREFER_SHARED}" == "1" ]] && \
        myconf+=( --disable-static --enable-shared ) || \
        myconf+=( --enable-static --disable-shared )

    export static_flags=""
    [[ "${PREFER_SHARED}" != "1" ]] && static_flags="-DICU_STATIC -DU_STATIC_IMPLEMENTATION"

    CFLAGS="${RAW_CFLAGS:-$CFLAGS} ${USELTO}" \
    CPPFLAGS="${RAW_CPPFLAGS:-$CPPFLAGS} $static_flags" \
    CXXFLAGS="${RAW_CXXFLAGS:-$CXXFLAGS} $static_flags ${USELTO}" \
    LDFLAGS="${RAW_LDFLAGS:-$LDFLAGS} ${USELTO}" \
    CC="$CC" \
    CXX="$CXX" \
    AR="$AR" \
    RANLIB="$RANLIB" \
    ../configure "${myconf[@]}" || return 1

    # ICU cross-build bug: target Makefile inherits ENABLE_SHARED from host build.
    # Force it off in every generated Makefile before building.
    # log_info "Patching ICU Makefiles to force disable shared..."
    # find . -name "Makefile" -exec sed -i \
        # -e 's/^ENABLE_SHARED\s*=.*/ENABLE_SHARED = NO/' \
        # -e 's/^SHARED_LIBRARY_SUFFIX\s*=.*/SHARED_LIBRARY_SUFFIX =/' \
        # {} \;
    
    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    # Verify data library was created
    if [[ ! -f "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/libicudt.a" ]] && \
       [[ ! -f "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/libsicudt.a" ]]; then
        log_error "ICU data library not found!"
        ls -la "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/" | grep -i icu || true
        return 1
    fi

    # Rename libraries (libicu* → libsicu*)
    cd "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib"
    for lib in libicu*.a; do
        [[ -f "$lib" ]] && mv "$lib" "s${lib#lib}" 2>/dev/null || true
    done
    # Исправляем специфичный sicudt (иногда он без 'lib' вначале)
    [[ -f "icudt.a" ]] && mv "icudt.a" "libsicudt.a"
    [[ -f "sicudt.a" ]] && mv "sicudt.a" "libsicudt.a"

    # Update .pc files
    local ICU_SYS_LIBS="-pthread -lm -ladvapi32 -lws2_32"
    for pc in "$PC_DIR"/icu-*.pc; do
        [[ -e "$pc" ]] || continue
        # Меняем имена библиотек (icu -> sicu)
        sed -i 's/-licu/-lsicu/g' "$pc"
        # Добавляем статический флаг
        if [[ -n "$static_flags" ]]; then
            if ! grep -qF -- "$static_flags" "$pc"; then
                sed -i "/^Cflags:/ s/$/ $static_flags/" "$pc"
            fi
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
