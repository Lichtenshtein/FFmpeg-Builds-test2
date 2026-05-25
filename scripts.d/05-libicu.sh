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
    mkdir -p host-build target-build "$INSTALL_ROOT"/{include,bin,lib/pkgconfig} && cd host-build

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
    cd target-build

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

    CFLAGS="${RAW_CFLAGS:-$CFLAGS} ${NOLTO}" \
    CPPFLAGS="${RAW_CPPFLAGS:-$CPPFLAGS} $static_flags" \
    CXXFLAGS="${RAW_CXXFLAGS:-$CXXFLAGS} $static_flags ${NOLTO}" \
    LDFLAGS="${RAW_LDFLAGS:-$LDFLAGS} ${NOLTO}" \
    CC="$CC" \
    CXX="$CXX" \
    AR="$AR" \
    RANLIB="$RANLIB" \
    ../configure "${myconf[@]}" || return 1

    make -j$(nproc) $MAKE_V || return 1

    # Ensure both bin and lib directories exist in DESTDIR
    # This prevents "No such file or directory" if pkgdata tries to install to bin
    mkdir -p "$FFBUILD_DESTDIR$FFBUILD_PREFIX/bin" "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib"
    log_info "${BUILD_MARK} Installing ICU..."
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    if [[ "${PREFER_SHARED}" != "1" ]]; then
        # Переходим в директорию скомпилированных библиотек
        cd "$INSTALL_ROOT/lib" || return 1
        # Исправляем странное поведение ICU, когда данные улетают в bin
        if [[ -f "$INSTALL_ROOT/bin/sicudt.a" ]]; then
            log_info "Moving sicudt.a from bin to lib..."
            mv -v "$INSTALL_ROOT/bin/sicudt.a" "$INSTALL_ROOT/lib/libicudt.a"
        fi
        log_info "Renaming libraries in $(pwd)..."
        # Приводим все к стандарту libicu*.a
        for f in libsicu*.a; do
            if [[ -f "$f" ]]; then
                mv -v "$f" "libicu${f#libsicu}"
            fi
        done
        # обрабатываем файлы, которые могли создаться без lib (sicudt.a, sicuuc.a)
        for f in sicu*.a; do
            [[ -e "$f" ]] && mv -v "$f" "libicu${f#sicu}" 2>/dev/null || true
        done
        # проверка наличия критически важных компонентов
        if [[ ! -f "libicuuc.a" ]] || [[ ! -f "libicudt.a" ]]; then
            log_error "Critical ICU libraries (libicuuc.a or libicudt.a) missing!"
            ls -la .
            return 1
        fi
    fi

    local ICU_SYS_LIBS="-lstdc++ -pthread -lm -ladvapi32 -lws2_32"
    for PC_FILE in "$PC_DIR"/icu-*.pc; do
        [[ -e "$PC_FILE" ]] || continue
        # стандартные имена -licu
        sed -i 's/-lsicu/-licu/g' "$PC_FILE"
        # Добавляем макросы статики в Cflags
        if [[ -n "$static_flags" ]]; then
            if ! grep -qF -- "$static_flags" "$PC_FILE"; then
                sed -i "/^Cflags:/ s/$/ $static_flags/" "$PC_FILE"
            fi
        fi
        # Вычищаем мусор из основной строки Libs
        sed -i 's/\${baselibs}//g; s/-lpthread//g; s/-lm//g' "$PC_FILE"
        # прописываем системные зависимости Windows в Libs.private
        if grep -q "^Libs.private:" "$PC_FILE"; then
            sed -i "s|^Libs.private:.*|Libs.private: $ICU_SYS_LIBS|" "$PC_FILE"
        else
            sed -i "/^Libs:/ a Libs.private: $ICU_SYS_LIBS" "$PC_FILE"
        fi
        # Добавляем библиотеку данных (-licudt) в строку линковки, если её там нет
        if ! grep -q -- "-licudt" "$PC_FILE"; then
            sed -i '/^Libs:/ s/$/ -licudt/' "$PC_FILE"
        fi
    done
}
