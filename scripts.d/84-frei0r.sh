#!/bin/bash

SCRIPT_REPO="https://github.com/dyne/frei0r.git"
SCRIPT_COMMIT="dfc89ab1f40fc32d5609218ebc3dd0b3cc545dd8"

# export SKIP_PRE_PATCH=1

ffbuild_depends() {
    echo opencv
    echo cairo
    echo gavl
    # echo nettle # from gavl
    # echo gnutls # from gavl
}

ffbuild_enabled() {
    [[ $VARIANT == lgpl* ]] && return 1
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

# ffbuild_dockerfinal() {
    # to_df "COPY --link --from=${PREVLAYER} \$FFBUILD_PREFIX/. \$FFBUILD_PREFIX"
    # to_df "ENV FREI0R_PATH=\$FFBUILD_PREFIX/lib/frei0r-1"
# }

ffbuild_dockerbuild() {
    set -e

    # Патчим CMakeLists.txt, чтобы он искал OpenCV через pkg-config вместо cmake find_package
    sed -i '1i find_package(PkgConfig REQUIRED)' CMakeLists.txt
    sed -i 's/find_package (OpenCV REQUIRED)/pkg_check_modules(OpenCV REQUIRED opencv4)/g' CMakeLists.txt
    # Исправляем переменные (pkg_check_modules наполняет OpenCV_LIBRARIES, а не OpenCV_LIBS)
    find . -name "CMakeLists.txt" -exec sed -i 's/${OpenCV_LIBS}/${OpenCV_LIBRARIES}/g' {} +
    # Вырезаем тесты because no dlfcn exist
    sed -i '/add_subdirectory (test)/d' CMakeLists.txt

# -lgavl -lhogweed -lgmp -lnettle -lgnutls 
    # Формируем список либ через pkg-config (так надежнее)
    local DEP_LIBS=$(pkgconf --static --libs opencv4 cairo)
    # Системные либы Windows, которые часто теряются
    local WIN_SYS_LIBS="-lshell32 -loleaut32 -lcomctl32"
    local RAW_LDFLAGS=$(echo "$LDFLAGS" | sed 's/-Wl,-Bstatic\b//g')

    mkdir build && cd build

    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        # -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF)
        -DWITHOUT_FACERECOGNITION=OFF # facedetect and facebl0r plugins
        -DWITHOUT_OPENCV=OFF # required for facebl0r filter
        -DWITHOUT_CAIRO=OFF  # required for cairo- filters and mixers
        -DWITHOUT_GAVL=ON   # required for scale0tilt and vectorscope filters
        # -DOPENCV_DIR="$FFBUILD_PREFIX/lib/cmake/opencv4"
        -DCMAKE_C_STANDARD_LIBRARIES="${DEP_LIBS} ${WIN_SYS_LIBS} ${LIBS} ${ADDITIONAL_LIBS}"
        -DCMAKE_CXX_STANDARD_LIBRARIES="${DEP_LIBS} -lstdc++ ${WIN_SYS_LIBS} ${LIBS} ${ADDITIONAL_LIBS}"
    )

    export static_flags=""
    [[ "${PREFER_SHARED}" != "1" ]] && static_flags="-DCAIRO_WIN32_STATIC_BUILD -Dpixman_static -DHARFBUZZ_STATIC -DFT2_BUILD_LIBRARY -DLIBXML_STATIC -DXML_STATIC"

# -Wl,--unresolved-symbols=ignore-all
    CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C} -fcommon $static_flags" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C} -fcommon $static_flags" \
    LDFLAGS="$RAW_LDFLAGS ${USELTO} -Wl,--allow-multiple-definition" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1
}

ffbuild_configure() {
    echo --enable-frei0r
}

ffbuild_unconfigure() {
    echo --disable-frei0r
}
