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
    rm -rf "$FFBUILD_PREFIX/lib/cmake/OpenJPEG"* 

    # Собираем все либы зависимостей через pkg-config для проверки линковки
    local LEPT_DEP_LIBS=$(pkg-config --libs --static libwebp libwebpmux libsharpyuv libtiff-4 libpng libopenjp2 lcms2 zlib)

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
        -DWEBP_LIBRARY="$FFBUILD_PREFIX/lib/libwebp.a"
        -DWebP_INCLUDE_DIR="$FFBUILD_PREFIX/include"
    )

    # Добавляем LTO если включено в workflow
    [[ "$USE_LTO" == "1" ]] && myconf+=( -DENABLE_LTO=ON )

    # Принудительно устанавливаем C_FLAGS, чтобы избежать __imp_
    cmake "${myconf[@]}" \
        -DCMAKE_C_FLAGS="$CFLAGS -DIB_STATIC -DLIBTIFF_STATIC" \
        ..

    # Исправляем расширение в сгенерированных файлах сборки, если CMake сошел с ума
    find . -name "build.make" -exec sed -i 's/libleptonica-1.88.0.dll/libleptonica.a/g' {} +
    find . -name "link.txt" -exec sed -i 's/libleptonica-1.88.0.dll/libleptonica.a/g' {} +

    make -j$(nproc) $MAKE_V
    make install DESTDIR="$FFBUILD_DESTDIR"

    # Ищем либу (она могла остаться в папке build/src)
    find "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib" -name "libleptonica*.a" -exec mv {} "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/libleptonica.a" \;

    mkdir -p "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig"
    # Удаляем все автосгенерированные конфиги
    rm -f "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig"/lept*.pc

    # lept.pc
    # Порядок либ: leptonica -> [tiff, webp, openjp2] -> [jpeg, png, zlib] -> [системные]
    # добавляем -llcms2, так как Leptonica может использовать его через tiff или напрямую

    local FINAL_LIBS="-lwebp -lwebpmux -lsharpyuv -ltiff -ljpeg -lpng16 -lopenjp2 -llcms2 -lgif -llzma -lzstd -ljbig -lz"
    local WIN_SYS="-lshlwapi -lws2_32 -luser32 -lgdi32 -lm"

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
Libs.private: $FINAL_LIBS $WIN_SYS
Cflags: -I\${includedir} -I\${includedir}/leptonica
EOF

    # Создаем симлинк, если Tesseract ищет leptonica.pc вместо lept.pc
    ln -sf lept.pc "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/leptonica.pc"
    # Удаляем CMake-файлы Leptonica. Это заставит Tesseract использовать pkg-config (lept.pc).
    rm -rf "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/cmake/leptonica"

    # Вызываем отладку зависимостей
    get_deps_list
}

ffbuild_configure() {
    return 0
}

ffbuild_unconfigure() {
    return 0
}
