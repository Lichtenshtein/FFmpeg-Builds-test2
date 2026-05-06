#!/bin/bash
SCRIPT_REPO="https://github.com/lensfun/lensfun.git"
SCRIPT_COMMIT="a6d6fd5b95cbeb98479b62e9644a06b78b916bd8"

ffbuild_depends() {
    echo base
    echo glib2
    echo libpng
    echo libxml2
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    mkdir -p build && cd build

    # нужно передать ДВА пути к инклудам Glib
    local GLIB_INCLUDES="-I$FFBUILD_PREFIX/include/glib-2.0 -I$FFBUILD_PREFIX/lib/glib-2.0/include"

    local myconf=(
        -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF)
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_BUILD_TYPE=Release
        # Добавляем пути к glibconfig.h через C_FLAGS
        -DBUILD_STATIC=$([ "${PREFER_SHARED}" == "1" ] && echo OFF || echo ON)
        -DBUILD_TESTS=OFF
        -DBUILD_LENSTOOL=OFF
        -DBUILD_DOC=OFF
        -DBUILD_FOR_SSE=ON
        -DBUILD_FOR_SSE2=ON
        -DINSTALL_HELPER_SCRIPTS=ON # OFF
        # Отключаем Python принудительно
        -DINSTALL_PYTHON_MODULE=OFF # OFF; Install Python module for the helper scripts
        # -DPYTHON_EXECUTABLE=OFF
        # Уточняем пути для CMake-модуля поиска Glib
        -DGLIB2_LIBRARIES="$FFBUILD_PREFIX/lib/libglib-2.0.a"
    )

    CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C} $GLIB_INCLUDES" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C} $GLIB_INCLUDES" \
    LDFLAGS="$LDFLAGS ${USELTO}" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    local pc_file="$PC_DIR/lensfun.pc"
    if [[ -f "$pc_file" ]]; then
        log_info "Patching lensfun.pc for static MinGW build..."
        # Добавляем glib-2.0 в зависимости, чтобы пути -I подтянулись автоматически
        if ! grep -q "Requires:" "$pc_file"; then
            sed -i '/^Requires:/ s/$/ glib-2.0/' "$pc_file"
        fi
    fi
}

ffbuild_configure() { echo --enable-liblensfun; }
ffbuild_unconfigure() { echo --disable-liblensfun; }
