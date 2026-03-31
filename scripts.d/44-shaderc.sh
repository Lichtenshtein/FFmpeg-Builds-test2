#!/bin/bash

# SCRIPT_REPO="https://github.com/stenzek/shaderc.git"
# SCRIPT_COMMIT="d72697bfc353b547efc58421ad54ac0345441bf4"

SCRIPT_REPO="https://github.com/google/shaderc.git"
SCRIPT_COMMIT="42c364eb27982ecfc9e00e384df205730e65b90c"

# export SKIP_PRE_PATCH=1

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
    apply_patches
    echo "./utils/git-sync-deps || exit $?"
}

ffbuild_dockerbuild() {
    set -e

    mkdir build && cd build

    local myconf=(
        -DCMAKE_BUILD_TYPE=Release
        # -DSHADERC_GLSLANG_DIR="$(realpath ../third_party/glslang)"
        # -DSHADERC_SPIRV_TOOLS_DIR="$(realpath ../third_party/spirv-tools)"
        # -DSHADERC_SPIRV_HEADERS_DIR="$(realpath ../third_party/spirv-headers)"
        -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF )
        # -DALLOW_EXTERNAL_SPIRV_TOOLS=ON
        -DBUILD_SHARED_LIBS=OFF
        -DENABLE_EXCEPTIONS=ON
        -DENABLE_GLSLANG_BINARIES=OFF
        -DENABLE_GLSLANG_JS=OFF
        -DENABLE_HLSL=ON
        -DENABLE_OPT=ON
        -DENABLE_PCH=OFF
        -DENABLE_RTTI=ON
        -DENABLE_SPIRV=ON
        -DGLSLANG_ENABLE_INSTALL=ON
        -DGLSLANG_TESTS=OFF
        -DSHADERC_ENABLE_SHARED_CRT=OFF
        -DSHADERC_SKIP_COPYRIGHT_CHECK=ON
        -DSHADERC_SKIP_EXAMPLES=ON
        -DSHADERC_SKIP_TESTS=ON
        -DSKIP_SPIRV_TOOLS_INSTALL=OFF
        -DSPIRV_CHECK_CONTEXT=OFF
        -DSPIRV_HEADERS_ENABLE_INSTALL=ON
        -DSPIRV_HEADERS_ENABLE_TESTS=OFF
        -DSPIRV_SKIP_EXECUTABLES=ON
        -DSPIRV_SKIP_TESTS=ON
        -DSPIRV_TOOLS_BUILD_SHARED=OFF
        -DSPIRV_TOOLS_BUILD_STATIC=ON
        -DSPIRV_TOOLS_LIBRARY_TYPE=STATIC
        -DSPIRV_WARN_EVERYTHING=OFF
        -DSPIRV_WERROR=OFF
    )

    CFLAGS="$CFLAGS $CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS" \
    LDFLAGS="$LDFLAGS" \
    cmake -GNinja "${myconf[@]}" \
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX" \
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN" .. || return 1

    export DESTDIR="/tmp/staging$FFBUILD_DESTDIR"
    ninja install || return 1

    if [[ $TARGET == win* ]]; then
        rm -r "${DESTDIR}${FFBUILD_PREFIX}"/bin "${DESTDIR}${FFBUILD_PREFIX}"/lib/*.dll.a
    elif [[ $TARGET == linux* ]]; then
        rm -r "${DESTDIR}${FFBUILD_PREFIX}"/bin "${DESTDIR}${FFBUILD_PREFIX}"/lib/*.so*
    else
        echo "Unknown target"
        return 1
    fi

    # Создаем эталонный shaderc.pc, который реально будет работать при статической линковке FFmpeg
    mkdir -p "${DESTDIR}${FFBUILD_PREFIX}/lib/pkgconfig"
    cat <<EOF > "${DESTDIR}${FFBUILD_PREFIX}/lib/pkgconfig/shaderc.pc"
prefix=${FFBUILD_PREFIX}
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: shaderc
Description: Tools and libraries for Vulkan shader compilation (Static Combined)
Version: 2026.2.0
Libs: -L\${libdir} -lshaderc_combined -lshaderc_util -lglslang -lMachineIndependent -lGenericCodeGen -lOSDependent -lSPIRV -lSPIRV-Tools-opt -lSPIRV-Tools-link -lSPIRV-Tools
Libs.private: -lstdc++ -lgomp -lsetupapi -lm -lole32 -lshlwapi -luser32 -ladvapi32 -ldbghelp -lws2_32 -lbcrypt -pthread
Cflags: -I\${includedir}
EOF

    # Дублируем его в shaderc_combined.pc и shaderc_static.pc для совместимости
    cp "${DESTDIR}${FFBUILD_PREFIX}/lib/pkgconfig/shaderc.pc" "${DESTDIR}${FFBUILD_PREFIX}/lib/pkgconfig/shaderc_combined.pc"
    cp "${DESTDIR}${FFBUILD_PREFIX}/lib/pkgconfig/shaderc.pc" "${DESTDIR}${FFBUILD_PREFIX}/lib/pkgconfig/shaderc_static.pc"

    cp -a "$DESTDIR"/. "$FFBUILD_DESTDIR"

    rm -rf "$DESTDIR"
    unset DESTDIR

    # for some reason, this does not get installed...
    cp libshaderc_util/libshaderc_util.a "$FFBUILD_DESTPREFIX"/lib

    echo "Libs: -lstdc++" >> "$PC_DIR/shaderc_combined.pc"
    echo "Libs: -lstdc++" >> "$PC_DIR/shaderc_static.pc"

    # cp "$PC_DIR"/{shaderc_combined,shaderc}.pc

    mkdir ../native_build && cd ../native_build

    unset CC CXX CFLAGS CXXFLAGS LD LDFLAGS AR RANLIB NM DLLTOOL PKG_CONFIG_LIBDIR

    log_info "Building native glslc..."
    cmake -GNinja "${myconf[@]}" .. || return 1

    ninja $NINJA_V -j$(nproc) glslc/glslc || return 1

    # Пробуем собрать таргет glslc. Если не выходит по точному имени, собираем всё в этой поддиректории
    # ninja glslc || ninja glslc/all || return 1

    # Копируем нативный бинарник туда, где он может понадобиться (например, vulkan-loader)
    # Ищем его через find, так как путь может быть glslc/glslc или просто glslc
    # find . -type f -name "glslc" -executable -exec cp -v {} /opt/glslc \;

    cp glslc/glslc /opt/glslc

}

ffbuild_configure() {
    echo --enable-libshaderc
}

ffbuild_unconfigure() {
    echo --disable-libshaderc
}
