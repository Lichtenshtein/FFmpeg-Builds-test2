#!/bin/bash

SCRIPT_REPO="https://github.com/DanBloomberg/leptonica.git"
SCRIPT_COMMIT="64a1de9a9cb788385e434576336d0b34dba51074"

ffbuild_depends() {
    echo zlib
    echo libpng
    echo libjpeg-turbo
    echo openjpeg
    echo libtiff
    echo brotli
    echo lcms2
    echo libwebp
    echo giflib
    echo libarchive
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

if [[ "${PREFER_SHARED}" != "1" ]]; then
    # Принудительно отключаем SHARED в самом коде Leptonica
    sed -i 's/SHARED/STATIC/g' src/CMakeLists.txt
fi
    # Убеждаемся, что она не пытается выставлять суффиксы версий вроде libleptonica-1.88.0.a
    sed -i 's/set_target_properties.*PROPERTIES.*OUTPUT_NAME.*//g' src/CMakeLists.txt

    mkdir build && cd build

    # Удаляем "ядовитые" CMake-конфиги TIFF и других либ,
    # которые заставляют линкер искать ZLIB::ZLIB
    # rm -rf "$FFBUILD_PREFIX/lib/cmake/"{tiff,OpenJPEG,libwebp,WebP,lcms2}

    # Временная папка для хранения "ядовитых" конфигов
    local LEPT_BACKUP="/tmp/leptonica_deps_backup"
    mkdir -p "$LEPT_BACKUP"
    local TARGETS=(tiff OpenJPEG libwebp WebP lcms2 TIFF)

    log_info "Backing up CMAKE files for Leptonica..."
    for target in "${TARGETS[@]}"; do
        if [ -d "$FFBUILD_PREFIX/lib/cmake/$target" ]; then
            mv "$FFBUILD_PREFIX/lib/cmake/$target" "$LEPT_BACKUP/"
        fi
    done

    # финальный список для линковки
    local DEP_LIBS="-llcms2_fast_float -llcms2_threaded -llcms2 -lwebpmux -lwebpdemux -lwebp -lwebpdecoder -lsharpyuv -ltiffxx -ltiff -lopenjp2 -lturbojpeg -ljpeg -lpng16 -lgif -lzstd -llzma -lbz2 -lbrotlienc -lbrotlidec -lbrotlicommon -lz -lintl -liconv -lcharset -lsicuin -lsicuuc -lsicudt"
    local WIN_LIBS="-lgdi32 $LIBS"

    # There is NO -DSTATIC=ON flag exist
    local myconf=(
        -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF)
        # -DCMAKE_PROJECT_INCLUDE="${PWD}/extra_targets.cmake"
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_PREFIX_PATH="$FFBUILD_PREFIX"
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DBUILD_SHARED_LIBS=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
        -DSW_BUILD=OFF
        -DBUILD_PROG=OFF
        -DINSTALL_CMAKE_CONFIG=OFF
        -DCMAKE_INSTALL_LIBDIR="lib"
        -DCMAKE_INSTALL_BINDIR="bin"
        -DCMAKE_INSTALL_INCLUDEDIR="include"
        -DSYM_LINK=ON # Create symlink leptonica -> lept on UNIX
        -DENABLE_PNG=ON
        -DENABLE_JPEG=ON
        -DENABLE_TIFF=ON
        -DENABLE_GIF=ON
        -DENABLE_ZLIB=ON
        -DENABLE_OPENJPEG=ON
        -DENABLE_WEBP=ON
        # Помогаем CMake найти наши статические либы
        -DTIFF_LIBRARY="$FFBUILD_PREFIX/lib/libtiff.a"
        -DTIFF_INCLUDE_DIR="$FFBUILD_PREFIX/include"
        -DPNG_LIBRARY="$FFBUILD_PREFIX/lib/libpng.a"
        -DJPEG_LIBRARY="$FFBUILD_PREFIX/lib/libjpeg.a"
        -DWebP_INCLUDE_DIR="$FFBUILD_PREFIX/include"
    )

    # Принудительно устанавливаем C_FLAGS, чтобы избежать __imp_
    CFLAGS="$CFLAGS $CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS" \
    cmake -G Ninja "${myconf[@]}" \
        -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS $DEP_LIBS $WIN_LIBS" .. || return 1

if [[ "${PREFER_SHARED}" != "1" ]]; then
    log_debug "Fixing static library names and locations..."
    # где лежит файл?
    log_debug "Searching for compiled lib..."
    find . -name "*.a"
    # смотрим, что реально собралось в папке src
    log_debug "Content of build/src:"
    ls -lh src/*.a src/*.dll* 2>/dev/null || echo "No libs found in src"

    # Исправляем расширение в сгенерированных файлах сборки, если CMake сошел с ума
    find . -name "build.make" -exec sed -i 's/libleptonica-1.88.0.dll/libleptonica.a/g' {} +
    find . -name "link.txt" -exec sed -i 's/libleptonica-1.88.0.dll/libleptonica.a/g' {} +
fi

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

if [[ "${PREFER_SHARED}" != "1" ]]; then

    # Ищем либу (она могла остаться в папке build/src). Если CMake создал файл с версией libleptonica-1.88.0.a, переименовываем
    find "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib" -name "libleptonica*.a" -exec mv {} "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/libleptonica.a" \; 2>/dev/null || true

    # Если вдруг либа оказалась в /bin (бывает в MinGW), переносим в /lib
    if [ -f "$FFBUILD_DESTDIR$FFBUILD_PREFIX/bin/libleptonica.a" ]; then
        mv "$FFBUILD_DESTDIR$FFBUILD_PREFIX/bin/libleptonica.a" "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/libleptonica.a"
    fi

    # Если файла libleptonica.a нет в целевой папке, ищем его везде в билде и копируем
    if [ ! -f "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/libleptonica.a" ]; then
        log_warn "Leptonica lib missing after install. Manual recovery..."
        mkdir -p "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib"
        # Ищем любой .a файл в папке src (он может называться liblept.a или libleptonica-1.88.0.a)
        local BUILT_LIB=$(find src -name "*.a" | head -n 1)
        if [[ -n "$BUILT_LIB" ]]; then
            cp "$BUILT_LIB" "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/libleptonica.a"
            log_info "${CHECK_MARK} Recovered: $BUILT_LIB -> libleptonica.a"
        else
            log_error "No static library was built!"
            return 1
        fi
    fi
fi

    # Удаляем все автосгенерированные конфиги
    rm -f "$PC_DIR"/lept*.pc

    # Генерируем "чистый" pkg-config файл
    mkdir -p "$PC_DIR"
    cat <<EOF > "$PC_DIR/lept.pc"
prefix=$FFBUILD_PREFIX
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: leptonica
Description: Leptonica image processing library
Version: 1.88.0
Libs: -L\${libdir} -lleptonica
Libs.private: $WIN_LIBS
Cflags: -I\${includedir} -I\${includedir}/leptonica
EOF

    # Всё равно создаем симлинк, если Tesseract ищет leptonica.pc вместо lept.pc и флаг -DSYM_LINK=ON не сработал
    ln -sf lept.pc "$PC_DIR/leptonica.pc"

    # Удаляем CMake-файлы Leptonica. Это заставит Tesseract использовать pkg-config (lept.pc).
    # rm -rf "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/cmake/leptonica"

    # Возвращаем папки на место, чтобы они были доступны для Tesseract или FFmpeg
    # Возвращаем всё обратно в основную директорию
    if [ -d "$LEPT_BACKUP" ] && [ "$(ls -A "$LEPT_BACKUP")" ]; then
        mkdir -p "$FFBUILD_PREFIX/lib/cmake"
        log_info "Restoring CMAKE files from backup..."
        mv "$LEPT_BACKUP"/* "$FFBUILD_PREFIX/lib/cmake/" 2>/dev/null || true
    fi
    rm -rf "$LEPT_BACKUP"
}
