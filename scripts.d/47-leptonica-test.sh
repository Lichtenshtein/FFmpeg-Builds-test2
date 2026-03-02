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
    if [[ -d "/builder/patches/leptonica-test" ]]; then
        for patch in /builder/patches/leptonica-test/*.patch; do
            log_info "APPLYING PATCH: $patch"
            if patch -p1 -N -r - < "$patch"; then
                log_info "${GREEN}${CHECK_MARK} SUCCESS: Patch applied.${NC}"
            else
                log_error "${RED}${CROSS_MARK} ERROR: PATCH FAILED! ${CROSS_MARK}${NC}"
            fi
        done
    fi

    mkdir build && cd build

    # Удаляем "ядовитые" CMake-конфиги TIFF и других либ, 
    # которые заставляют линкер искать ZLIB::ZLIB
    rm -rf "$FFBUILD_PREFIX/lib/cmake/tiff"

    # Создаем фиктивные цели, чтобы удовлетворить TiffConfig.cmake
    # Прописываем пути к реальным файлам для этих целей
    # cat <<EOF > extra_targets.cmake
# foreach(tgt JBIG::JBIG ZLIB::ZLIB liblzma::liblzma ZSTD::ZSTD JPEG::JPEG)
    # if(NOT TARGET \${tgt})
        # add_library(\${tgt} STATIC IMPORTED)
    # endif()
# endforeach()

# set_target_properties(JBIG::JBIG PROPERTIES IMPORTED_LOCATION "$FFBUILD_PREFIX/lib/libjbig.a")
# set_target_properties(ZLIB::ZLIB PROPERTIES IMPORTED_LOCATION "$FFBUILD_PREFIX/lib/libz.a")
# set_target_properties(liblzma::liblzma PROPERTIES IMPORTED_LOCATION "$FFBUILD_PREFIX/lib/liblzma.a")
# set_target_properties(ZSTD::ZSTD PROPERTIES IMPORTED_LOCATION "$FFBUILD_PREFIX/lib/libzstd.a")
# set_target_properties(JPEG::JPEG PROPERTIES IMPORTED_LOCATION "$FFBUILD_PREFIX/lib/libjpeg.a")
# EOF

    local myconf=(
        # -DCMAKE_PROJECT_INCLUDE="${PWD}/extra_targets.cmake"
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DBUILD_SHARED_LIBS=OFF
        # -DCMAKE_LINK_SEARCH_START_STATIC=ON
        # -DCMAKE_LINK_SEARCH_END_STATIC=ON
        -DSW_BUILD=OFF
        -DBUILD_PROG=OFF
        -DINSTALL_CMAKE_CONFIG=OFF
        -DSYM_LINK=ON # Create symlink leptonica -> lept on UNIX
        -DENABLE_PNG=ON
        -DENABLE_JPEG=ON
        -DENABLE_TIFF=ON
        -DENABLE_GIF=ON
        -DENABLE_ZLIB=ON
        -DENABLE_OPENJPEG=ON
        -DENABLE_WEBP=ON
        # Явно помогаем найти WebP
        -DWebP_DIR=OFF
        -DWebP_INCLUDE_DIR="$FFBUILD_PREFIX/include"
        -DWebP_LIBRARY="$FFBUILD_PREFIX/lib/libwebp.a"
        # Явно помогаем найти TIFF (если он тоже капризничает)
        -DTIFF_INCLUDE_DIR="$FFBUILD_PREFIX/include"
        -DTIFF_LIBRARY="$FFBUILD_PREFIX/lib/libtiff.a"
        -DCMAKE_PREFIX_PATH="$FFBUILD_PREFIX"
        # -DPKG_CONFIG_EXECUTABLE=$(which pkg-config)
    )

    # Добавляем LTO если включено в workflow
    [[ "$USE_LTO" == "1" ]] && myconf+=( -DENABLE_LTO=ON )

    cmake "${myconf[@]}" \
        -DCMAKE_C_FLAGS="$CFLAGS -DIB_STATIC" \
        ..

    # Исправляем расширение в сгенерированных файлах сборки, если CMake сошел с ума
    find . -name "build.make" -exec sed -i 's/libleptonica-1.88.0.dll/libleptonica.a/g' {} +
    find . -name "link.txt" -exec sed -i 's/libleptonica-1.88.0.dll/libleptonica.a/g' {} +

    make -j$(nproc) $MAKE_V
    make install DESTDIR="$FFBUILD_DESTDIR"

    mkdir -p "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig"

    # Ищем либу (она могла остаться в папке build/src)
    find src -name "libleptonica*" -exec cp {} "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/libleptonica.a" \;

    # Удаляем все автосгенерированные конфиги
    rm -f "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig"/lept*.pc

    # Если pc файл не создался вообще - создаем его вручную (минимальный рабочий вариант)
    cat <<EOF > "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/lept.pc"
prefix=$FFBUILD_PREFIX
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: leptonica
Description: Leptonica image processing library
Version: 1.88.0
Libs: -L\${libdir} -lleptonica
Libs.private: -lwebp -lwebpmux -lsharpyuv -ltiff -ljpeg -lpng16 -lopenjp2 -lgif -llzma -lzstd -ljbig -lz -lshlwapi -lws2_32 -lm
Cflags: -I\${includedir} -I\${includedir}/leptonica
EOF

    # Создаем симлинк, если Tesseract ищет leptonica.pc вместо lept.pc
    ln -sf lept.pc "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/leptonica.pc"
    # Удаляем CMake-файлы Leptonica. Это заставит Tesseract использовать pkg-config (lept.pc).
    rm -rf "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/cmake/leptonica"

    log_info "################################################################"
    log_debug "Dependencies for $STAGENAME: ${0##*/}"
    # Показываем все сгенерированные .pc файлы и их зависимости
    find "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig" -name "*.pc" -exec echo "--- {} ---" \; -exec cat {} \;
    # Показываем внешние символы (Undefined) для каждой собранной .a библиотеки
    # фильтруем только те символы, которые реально ведут к другим библиотекам
    find "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib" -name "*.a" -print0 | xargs -0 -I{} sh -c "
        echo '--- Symbols in {} ---';
        ${FFBUILD_TOOLCHAIN}-nm {} | grep ' U ' | awk '{print \$2}' | sort -u | head -n 20
    "
    log_info "################################################################"
}

ffbuild_configure() {
    return 0
}

ffbuild_unconfigure() {
    return 0
}
