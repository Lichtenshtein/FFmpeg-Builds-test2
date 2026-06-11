#!/bin/bash

SCRIPT_REPO="https://github.com/KhronosGroup/OpenCL-Headers.git"
SCRIPT_COMMIT="a98488062f50c77c3e2edaf9c4f8dca7c41781ec"

SCRIPT_REPO2="https://github.com/KhronosGroup/OpenCL-ICD-Loader.git"
SCRIPT_COMMIT2="b7bd2803acc779c03d96588e9ca9e9568a18698a"

SCRIPT_REPO3="https://github.com/KhronosGroup/OpenCL-CLHPP.git"
SCRIPT_COMMIT3="5661a0efc215b1e05d3b90315c64f670101fdbde"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    echo "git-mini-clone \"$SCRIPT_REPO\" \"$SCRIPT_COMMIT\" headers"
    echo "git-mini-clone \"$SCRIPT_REPO2\" \"$SCRIPT_COMMIT2\" loader"
    echo "git-mini-clone \"$SCRIPT_REPO3\" \"$SCRIPT_COMMIT3\" CLHPP"
}

ffbuild_dockerbuild() {
    set -e

    # Возвращаемся в реальный корень этапа, если "умный поиск" зашел в /loader или /CLHPP
    if [[ "$(basename "$PWD")" == "loader" || "$(basename "$PWD")" == "CLHPP" ]]; then
        cd ..
    fi

    # 1. Установка базовых C-хедеров OpenCL
    log_info "Installing OpenCL C headers..."
    mkdir -p "$INSTALL_ROOT/include/CL"
    cp -r headers/CL/* "$INSTALL_ROOT/include/CL/."

    # 2. Сборка и установка OpenCL ICD Loader
    log_info "Building OpenCL ICD Loader..."
    cd loader
    # Удаляем старый build если остался, и создаем чистый
    rm -rf build && mkdir build && cd build

    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        # -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF)
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        # Указываем путь к только что скопированным хедерам
        -DOPENCL_ICD_LOADER_HEADERS_DIR="$INSTALL_ROOT/include"
        -DOPENCL_ICD_LOADER_BUILD_SHARED_LIBS=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
        -DENABLE_OPENCL_LAYERS=ON # support for OpenCL layers in the ICD loader
        -DOPENCL_ICD_LOADER_BUILD_TESTING=OFF
        -DOPENCL_HEADERS_BUILD_CXX_TESTS=OFF
        -DOPENCL_HEADERS_BUILD_TESTING=OFF
        -DBUILD_TESTING=OFF
    )

    CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
    LDFLAGS="$LDFLAGS ${USELTO}" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja -j$(nproc) $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    cd ../..

    # 3. Установка C++ хедеров OpenCL (CLHPP)
    log_info "Installing OpenCL C++ headers (CLHPP)..."
    cd CLHPP

    log_info "Patching CLHPP CMakeLists to support imported target style..."
    sed -i 's/add_library(OpenCLHeaders INTERFACE)/add_library(OpenCLHeaders INTERFACE IMPORTED)/g' CMakeLists.txt

    rm -rf build && mkdir build && cd build

    local myconf_hpp=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        # Указываем путь к C-хедерам, чтобы сработал внутренний IF в CMakeLists
        -DOPENCL_INCLUDE_DIR="$INSTALL_ROOT/include"
        # Отключаем сборку тестов, примеров и документации
        -DBUILD_DOCS=OFF
        -DBUILD_EXAMPLES=OFF
        -DOPENCL_CLHPP_BUILD_TESTING=OFF
        -DBUILD_TESTING=OFF
    )

    CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
    LDFLAGS="$LDFLAGS ${USELTO}" \
    cmake -G Ninja "${myconf_hpp[@]}" .. || return 1

    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1
    
    cd ../..

    log_info "Generating OpenCL.pc and final post-processing..."
    mkdir -p "$PC_DIR"
    cat <<EOF > "$PC_DIR/OpenCL.pc"
prefix=$FFBUILD_PREFIX
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: OpenCL
Description: OpenCL ICD Loader
Version: ${VER_FULL}
Libs: -L\${libdir} -lOpenCL
Cflags: -I\${includedir} -I\${includedir}/CL
EOF

    if [[ $TARGET == linux* ]]; then
        echo "Libs.private: -ldl" >> "$PC_DIR/OpenCL.pc"
    elif [[ $TARGET == win* ]]; then
        echo "Libs.private: -lole32 -lshlwapi -lcfgmgr32 -lruntimeobject" >> "$PC_DIR/OpenCL.pc"
    fi

    if [[ "${PREFER_SHARED}" != "1" ]]; then
        cp "${INSTALL_ROOT}/lib/OpenCL.a" "${INSTALL_ROOT}/lib/libOpenCL.a"
    fi
}

ffbuild_configure() {
    echo --enable-opencl
}

ffbuild_unconfigure() {
    echo --disable-opencl
}
