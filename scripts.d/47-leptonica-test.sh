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
    apply_patches

    # Принудительно отключаем SHARED в самом коде Leptonica
    sed -i 's/SHARED/STATIC/g' src/CMakeLists.txt

    # Убеждаемся, что она не пытается выставлять суффиксы версий вроде libleptonica-1.88.0.a
    sed -i 's/set_target_properties.*PROPERTIES.*OUTPUT_NAME.*//g' src/CMakeLists.txt

    mkdir build && cd build

    # Удаляем "ядовитые" CMake-конфиги TIFF и других либ,
    # которые заставляют линкер искать ZLIB::ZLIB
    rm -rf "$FFBUILD_PREFIX/lib/cmake/"{tiff,OpenJPEG,libwebp,WebP,lcms2}

    # финальный список для линковки
    local LEPT_DEPS="-larchive -lxml2 -lwebp -lwebpmux -lsharpyuv -ltiff -lopenjp2 -llcms2 -ljpeg -lturbojpeg -lpng16 -lgif -lzstd -llzma -lbz2 -ljbig -ljbig85 -lz"
    local WIN_SYS="-lgdi32 -lstdc++ $LIBS"

    # There is NO -DSTATIC=ON flag exist
    local myconf=(
        # -DCMAKE_PROJECT_INCLUDE="${PWD}/extra_targets.cmake"
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_PREFIX_PATH="$FFBUILD_PREFIX"
        -DBUILD_SHARED_LIBS=OFF
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

    # Добавляем LTO если включено в workflow
    [[ "$USE_LTO" == "1" ]] && myconf+=( -DENABLE_LTO=ON )

    # Принудительно устанавливаем C_FLAGS, чтобы избежать __imp_
    cmake "${myconf[@]}" \
        -DCMAKE_C_FLAGS="$CFLAGS" \
        -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS $LEPT_DEPS $WIN_SYS" .. || return 1

    # где лежит файл?
    log_debug "Searching for compiled lib..."
    find . -name "*.a"
    # смотрим, что реально собралось в папке src
    log_debug "Content of build/src:"
    ls -lh src/*.a src/*.dll* 2>/dev/null || echo "No libs found in src"

    # Исправляем расширение в сгенерированных файлах сборки, если CMake сошел с ума
    find . -name "build.make" -exec sed -i 's/libleptonica-1.88.0.dll/libleptonica.a/g' {} +
    find . -name "link.txt" -exec sed -i 's/libleptonica-1.88.0.dll/libleptonica.a/g' {} +

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    clean_la_files

    # Ищем либу (она могла остаться в папке build/src). Если CMake создал файл с версией libleptonica-1.88.0.a, переименовываем
    find "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib" -name "libleptonica*.a" -exec mv {} "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/libleptonica.a" \;

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
            log_error "${CROSS_MARK} No static library was built!"
            exit 1
        fi
    fi

    # Удаляем все автосгенерированные конфиги
    rm -f "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig"/lept*.pc

    # Генерируем "чистый" pkg-config файл
    mkdir -p "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig"
    cat <<EOF > "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/lept.pc"
prefix=$FFBUILD_PREFIX
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: leptonica
Description: Leptonica image processing library
Version: 1.88.0
Libs: -L\${libdir} -lleptonica
Libs.private: $LEPT_DEPS $WIN_SYS
Cflags: -I\${includedir} -I\${includedir}/leptonica
EOF

    # Всё равно создаем симлинк, если Tesseract ищет leptonica.pc вместо lept.pc и флаг -DSYM_LINK=ON не сработал
    ln -sf lept.pc "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/leptonica.pc"
    # Удаляем CMake-файлы Leptonica. Это заставит Tesseract использовать pkg-config (lept.pc).
    rm -rf "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/cmake/leptonica"

    get_deps_list
}
