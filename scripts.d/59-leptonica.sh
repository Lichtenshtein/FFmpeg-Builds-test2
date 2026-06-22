#!/bin/bash
export USE_VERS_FINDER=1
SCRIPT_REPO="https://github.com/DanBloomberg/leptonica.git"
SCRIPT_COMMIT="19e4d64c62521d34b6ad9a100fcce1bc4dee5a73"

ffbuild_depends() {
    echo zlib
    echo libpng
    echo libjpeg-turbo
    echo openjpeg
    echo libtiff
    echo lcms2
    echo libwebp
    echo giflib
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
    echo "rm -rf prog"
}

ffbuild_dockerbuild() {
    set -e

    if [[ "${PREFER_SHARED}" != "1" ]]; then
        # Принудительно отключаем SHARED в самом коде Leptonica
        sed -i 's/SHARED/STATIC/g' src/CMakeLists.txt
    fi

    # Убеждаемся, что она не пытается выставлять суффиксы версий вроде libleptonica-1.88.0.a
    log_info "Forcing static library target properties in CMakeLists.txt..."
    sed -i 's/set_target_properties.*PROPERTIES.*OUTPUT_NAME.*//g' src/CMakeLists.txt

    # Временно перемещаем "ядовитые" CMake-конфиги TIFF и других либ,
    # которые заставляют линкер искать ZLIB::ZLIB
    local LEPT_BACKUP="/tmp/leptonica_deps_backup"
    mkdir -p "$LEPT_BACKUP"
    local TARGETS=(tiff OpenJPEG libwebp WebP lcms2 TIFF)

    log_info "Backing up CMAKE files for Leptonica..."
    for target in "${TARGETS[@]}"; do
        if [ -d "$FFBUILD_PREFIX/lib/cmake/$target" ]; then
            mv "$FFBUILD_PREFIX/lib/cmake/$target" "$LEPT_BACKUP/"
        fi
    done

    # Восстанавливаем cmake файлы
    trap '
        log_debug "Executing Leptonica backup restoration trap..."
        if [ -d "'"$LEPT_BACKUP"'" ] && [ "$(ls -A "'"$LEPT_BACKUP"'" 2>/dev/null)" ]; then
            mkdir -p "'"$FFBUILD_PREFIX"'/lib/cmake"
            log_info "Restoring CMAKE files from backup..."
            mv "'"$LEPT_BACKUP"'"/* "'"$FFBUILD_PREFIX"'/lib/cmake/" 2>/dev/null || true
        fi
        rm -rf "'"$LEPT_BACKUP"'"
    ' EXIT

    mkdir build && cd build

    # подставляем пути к библиотекам в зависимости от PREFER_SHARED
    local lib_ext=$([ "${PREFER_SHARED}" == "1" ] && echo "dll.a" || echo "a")

    local myconf=(
        # -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF)
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_PREFIX_PATH="$FFBUILD_PREFIX"
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DBUILD_SHARED_LIBS=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
        -DSW_BUILD=OFF
        -DBUILD_PROG=OFF # deleted prog folder
        -DINSTALL_CMAKE_CONFIG=OFF
        -DCMAKE_INSTALL_LIBDIR="lib"
        -DCMAKE_INSTALL_BINDIR="bin"
        -DCMAKE_INSTALL_INCLUDEDIR="include"
        -DSYM_LINK=ON # Create symlink leptonica -> lept on UNIX
    )

    if has_library "z"; then
        log_info "Zlib library detected. Building with Zlib support..."
        myconf+=(
            -DENABLE_ZLIB=ON
        )
        local ZLIB_PC="zlib"
    else
        myconf+=(
            -DENABLE_ZLIB=OFF
        )
    fi
    if has_library "gif"; then
        log_info "Gif library detected. Building with Gif support..."
        myconf+=(
            -DENABLE_GIF=ON
        )
        local GIF_PC="giflib"
    else
        myconf+=(
            -DENABLE_GIF=OFF
        )
    fi
    if has_library "openjp2"; then
        log_info "OpenJPEG library detected. Building with OpenJPEG support..."
        myconf+=(
            -DENABLE_OPENJPEG=ON
        )
        local OPENJPG_PC="libopenjp2"
    else
        myconf+=(
            -DENABLE_OPENJPEG=OFF
        )
    fi
    if has_library "webp"; then
        log_info "WebP library detected. Building with WebP support..."
        myconf+=(
            -DENABLE_WEBP=ON
            -DWebP_INCLUDE_DIR="$FFBUILD_PREFIX/include"
        )
        local WEBP_PC="webp"
    else
        myconf+=(
            -DENABLE_WEBP=OFF
        )
    fi
    if has_library "png"; then
        log_info "PNG library detected. Building with PNG support..."
        myconf+=(
            -DENABLE_PNG=ON
            -DPNG_LIBRARY="$FFBUILD_PREFIX/lib/libpng.${lib_ext}"
        )
        local PNG_PC="png"
    else
        myconf+=(
            -DENABLE_PNG=OFF
        )
    fi
    if has_library "jpeg"; then
        log_info "JPEG library detected. Building with JPEG support..."
        myconf+=(
            -DENABLE_JPEG=ON
            -DJPEG_LIBRARY="$FFBUILD_PREFIX/lib/libjpeg.${lib_ext}"
        )
        local JPEG_PC="libjpeg libturbojpeg"
    else
        myconf+=(
            -DENABLE_JPEG=OFF
        )
    fi
    if has_library "tiff"; then
        log_info "TIFF library detected. Building with TIFF support..."
        myconf+=(
            -DENABLE_TIFF=ON
            -DTIFF_LIBRARY="$FFBUILD_PREFIX/lib/libtiff.${lib_ext}"
            -DTIFF_INCLUDE_DIR="$FFBUILD_PREFIX/include"
        )
        local TIFF_PC="tiff"
    else
        myconf+=(
            -DENABLE_TIFF=OFF
        )
    fi

    local DEP_LIBS=$(get_pc_libs lcms2 ${TIFF_PC} ${WEBP_PC} ${OPENJPG_PC} ${PNG_PC} ${JPEG_PC} ${GIF_PC} ${ZLIB_PC})
    local LINKER_GROUP="-Wl,--start-group ${DEP_LIBS} ${LIBS} -Wl,--end-group"

    CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
    LDFLAGS="$LDFLAGS ${USELTO}" \
    cmake -G Ninja "${myconf[@]}" \
        -DCMAKE_C_STANDARD_LIBRARIES="${LINKER_GROUP}" \
        -DCMAKE_CXX_STANDARD_LIBRARIES="${LINKER_GROUP}" \
        .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    if [[ "${PREFER_SHARED}" != "1" ]]; then
        # Защита от багов MinGW, когда статические либы улетают в /bin
        if [ -f "$INSTALL_ROOT/bin/libleptonica.a" ]; then
            mv "$INSTALL_ROOT/bin/libleptonica.a" "$INSTALL_ROOT/lib/libleptonica.a"
        fi

        # Если при статической MinGW-сборке файл назвался liblept.a вместо libleptonica.a
        if [ -f "$INSTALL_ROOT/lib/liblept.a" ] && [ ! -f "$INSTALL_ROOT/lib/libleptonica.a" ]; then
            ln -sf liblept.a "$INSTALL_ROOT/lib/libleptonica.a"
        fi

        # Если файл сохранил суффикс версии (напр. libleptonica-1.88.0.a), нормализуем его
        find "$INSTALL_ROOT/lib" -name "libleptonica*.a" ! -name "libleptonica.a" -exec mv {} "$INSTALL_ROOT/lib/libleptonica.a" \; 2>/dev/null || true

        # Если файла libleptonica.a нет в целевой папке, ищем его везде в билде и копируем
        if [ ! -f "$INSTALL_ROOT/lib/libleptonica.a" ]; then
            log_warn "Leptonica lib missing after install. Manual recovery..."
            mkdir -p "$INSTALL_ROOT/lib"
            # Ищем любой .a файл в папке src (он может называться liblept.a или libleptonica-1.88.0.a)
            local BUILT_LIB=$(find src -name "*.a" | head -n 1)
            if [[ -n "$BUILT_LIB" ]]; then
                cp "$BUILT_LIB" "$INSTALL_ROOT/lib/libleptonica.a"
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
Version: ${VER_FULL}
Requires.private: lcms2 ${TIFF_PC} ${WEBP_PC} ${OPENJPG_PC} ${PNG_PC} ${JPEG_PC} ${GIF_PC} ${ZLIB_PC}
Libs: -L\${libdir} -lleptonica
Libs.private: ${LIBS} -lm
Cflags: -I\${includedir} -I\${includedir}/leptonica
EOF

    # Всё равно создаем симлинк, если Tesseract ищет leptonica.pc вместо lept.pc и флаг -DSYM_LINK=ON не сработал
    ln -sf lept.pc "$PC_DIR/leptonica.pc"
}
