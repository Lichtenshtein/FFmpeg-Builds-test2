#!/bin/bash
export USE_VERS_FINDER=1
SCRIPT_REPO="https://github.com/AOMediaCodec/libavif.git"
SCRIPT_COMMIT="76fb86e4d569863da8df63e7327168cc23f35709"

ffbuild_depends() {
    echo libwebp # libsharpyuv
    echo libpng
    echo zlib
    echo dav1d
    echo rav1e # 1 of 3
    echo aom # 1 of 3
    echo svtav1 # 1 of 3
    echo libxml2
}

ffbuild_enabled() {
    return 0
    echo "rm -rf android_jni tests"
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    mkdir -p "include/sharpyuv"
    cp ${OP_VERB} "$FFBUILD_PREFIX/include/webp/sharpyuv/"*.h "include/sharpyuv/" 2>/dev/null || true

    local XML2_INC="$FFBUILD_PREFIX/include/libxml2"

    cat <<EOF > fix_targets.cmake
add_library(sharpyuv::sharpyuv STATIC IMPORTED GLOBAL)
set_target_properties(sharpyuv::sharpyuv PROPERTIES 
    IMPORTED_LOCATION "$FFBUILD_PREFIX/lib/libsharpyuv.a"
    INTERFACE_INCLUDE_DIRECTORIES "\${CMAKE_CURRENT_SOURCE_DIR}/include"
    AVIF_LOCAL OFF)

add_library(LibXml2 STATIC IMPORTED GLOBAL)
set_target_properties(LibXml2 PROPERTIES 
    IMPORTED_LOCATION "$FFBUILD_PREFIX/lib/libxml2.a"
    INTERFACE_INCLUDE_DIRECTORIES "$XML2_INC"
    AVIF_LOCAL OFF)
target_compile_definitions(LibXml2 INTERFACE LIBXML_STATIC)
target_link_libraries(LibXml2 INTERFACE bcrypt ws2_32)

add_library(LibXml2::LibXml2 ALIAS LibXml2)

include_directories(BEFORE "\${CMAKE_CURRENT_SOURCE_DIR}/include")
include_directories(SYSTEM "$XML2_INC")
EOF

    sed -i '1i include("${CMAKE_CURRENT_SOURCE_DIR}/fix_targets.cmake")' CMakeLists.txt
    sed -i 's/check_avif_option(AVIF_LIBSHARPYUV.*/set(AVIF_LIBSHARPYUV_ENABLED ON)/' CMakeLists.txt
    sed -i 's/check_avif_option(AVIF_LIBXML2.*/set(AVIF_LIBXML2_ENABLED ON)/' CMakeLists.txt
    sed -i 's/find_package(libsharpyuv/#/' CMakeLists.txt
    sed -i 's/find_package(LibXml2/#/' CMakeLists.txt

    mkdir -p build && cd build

    local myconf=(
        # -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF )
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_PREFIX_PATH="$FFBUILD_PREFIX"
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DBUILD_SHARED_LIBS=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
        -DAVIF_BUILD_TESTS=OFF
        -DAVIF_BUILD_APPS=OFF
        -DAVIF_BUILD_EXAMPLES=OFF
        # Включаем поддержку внешнего декодера dav1d
        -DAVIF_CODEC_DAV1D=SYSTEM # Декодер
        -DAVIF_CODEC_DAV1D_ENABLED=ON
        -DAVIF_LIBSHARPYUV=SYSTEM # stupidly fails if no .cmake files found
        -DAVIF_LIBXML2=SYSTEM # convert JPEG with gain maps to AVIF using avifenc
        -DAVIF_JPEG=SYSTEM
        -DAVIF_ZLIBPNG=SYSTEM
        # aom создаёт проблему курицы и яйца
        -DAVIF_CODEC_AOM=OFF
        -DAVIF_CODEC_SVT=SYSTEM # Используем SVT-AV1 как энкодер!
        -DAVIF_LIBYUV=LOCAL # Донор libyuv для aom
        # use rav1e instead of AOM or SVT
        #-DAVIF_CODEC_RAV1E=SYSYEM
        #-DAVIF_CODEC_RAV1E_ENABLED=ON
        -DAVIF_OPTIMIZE_RAV1E_FOR_SIZE=ON
    )

    CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
    LDFLAGS="$LDFLAGS ${USELTO}" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja -j$(nproc) $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    # Извлекаем libyuv.a для послудующих стадий (она лежит в _deps/libyuv-build/)
    cp ${OP_VERB} "_deps/libyuv-build/libyuv.a" "$INSTALL_ROOT/lib/"
    mkdir -p "$INSTALL_ROOT/include/libyuv"
    cp -r${OP_V} "_deps/libyuv-src/include/"* "$INSTALL_ROOT/include/"

    # Создаем pkg-config файл вручную, чтобы aom и avif-v2 его нашли
    mkdir -p "$PC_DIR"
    cat <<EOF > "$PC_DIR/libyuv.pc"
prefix=$FFBUILD_PREFIX
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: libyuv
Description: YUV conversion and scaling library
Version: ${VER_FULL}
Libs: -L\${libdir} -lyuv
Libs.private: -lstdc++
Cflags: -I\${includedir} -I\${includedir}/libyuv
EOF

    for PC_FILE in "$PC_DIR"/libavif.pc; do
        [[ -f "$PC_FILE" ]] || continue
        sed -i "s|^Cflags:.*|& -I\${includedir}/avif|" "$PC_FILE"
        log_info "Updated Cflags in $(basename "$PC_FILE")"
    done
}
