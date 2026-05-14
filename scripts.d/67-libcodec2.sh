#!/bin/bash

# SCRIPT_REPO="https://github.com/arancormonk/codec2.git"
# SCRIPT_COMMIT="6a787012632b8941aa24a4ea781440b61de40f57"

# SCRIPT_REPO1="https://github.com/rhythmcache/codec2.git"
# SCRIPT_COMMIT1="6e0a0e09c065aa5401eb9c30d724240fffe890f1"

# SCRIPT_REPO2="https://github.com/zups/codec2.git"
# SCRIPT_COMMIT2="371c82ae557f1b033cf4b625be435bb4b88ef70b"

SCRIPT_REPO3="https://github.com/Alex-Pennington/codec2.git"
SCRIPT_COMMIT3="19571e0a2b42340597fd762803f6eb9d030ee4c5"

# SCRIPT_REPO4="https://github.com/drowe67/codec2.git"
# SCRIPT_COMMIT4="96e8a19c2487fd83bd981ce570f257aef42618f9"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    # Отключаем сборку утилит и тестов прямо в корневом CMakeLists.txt
    sed -i 's|add_subdirectory(unittest)|# add_subdirectory(unittest)|g' CMakeLists.txt
    sed -i 's|add_subdirectory(demo)|# add_subdirectory(demo)|g' CMakeLists.txt
    sed -i 's|if(WIN32)|if(FALSE)|g' CMakeLists.txt

    # Отключаем сборку исполняемых файлов
    # но ОСТАВЛЯЕМ генерацию кодовых книг (generate_codebook) и саму библиотеку
    if [ -f "src/CMakeLists.txt" ]; then
        sed -i 's|add_executable(c2enc|# add_executable(c2enc|g' src/CMakeLists.txt
        sed -i 's|target_link_libraries(c2enc|# target_link_libraries(c2enc|g' src/CMakeLists.txt
        sed -i 's|add_executable(c2dec|# add_executable(c2dec|g' src/CMakeLists.txt
        sed -i 's|target_link_libraries(c2dec|# target_link_libraries(c2dec|g' src/CMakeLists.txt
        sed -i 's|add_executable(freedv_rx|# add_executable(freedv_rx|g' src/CMakeLists.txt
        sed -i 's|add_executable(freedv_tx|# add_executable(freedv_tx|g' src/CMakeLists.txt
        # Отключаем инструкции установки для несуществующих теперь бинарников
        sed -i 's|RUNTIME DESTINATION bin||g' src/CMakeLists.txt
        sed -i 's|bundle_gavl_deps||g' src/CMakeLists.txt
    fi

    mkdir build && cd build

    local myconf=(
        # -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF)
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_BUILD_TYPE=Release
        -DBUILD_SHARED_LIBS=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DUNITTEST=OFF
    )

    CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
    LDFLAGS="$LDFLAGS ${USELTO}" \
    cmake "${myconf[@]}" .. || return 1

    # Собираем и устанавливаем штатно через CMake/DESTDIR
    make -j$(nproc) || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    # Вручную генерируем правильный version.h, так как мы обошли штатный src/CMakeLists.txt
    log_info "Generating version.h manually..."
    mkdir -p "$INSTALL_ROOT/include/codec2"
    cat << 'EOF' > "$INSTALL_ROOT/include/codec2/version.h"
#ifndef CODEC2_HAVE_VERSION
#define CODEC2_HAVE_VERSION
#define CODEC2_VERSION_MAJOR 1
#define CODEC2_VERSION_MINOR 2
#define CODEC2_VERSION "1.2.0"
#endif
EOF

    mkdir -p "$PC_DIR"
    cat <<EOF > "$PC_DIR/codec2.pc"
prefix=$FFBUILD_PREFIX
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: codec2
Description: A speech codec for 2400 bit/s and below
Version: 1.2.0
Libs: -L\${libdir} -lcodec2
Libs.private: -lm
Cflags: -I\${includedir} -I\${includedir}/codec2
EOF

    # Финальная валидация артефактов перед выходом
    if [[ "${PREFER_SHARED}" != "1" ]]; then
        if [[ -f "$INSTALL_ROOT/lib/libcodec2.a" && -f "$INSTALL_ROOT/include/codec2/version.h" ]]; then
            log_info "${CHECK_MARK} SUCCESS: libcodec2.a and version.h are completely ready."
        else
            log_error "Critical files missing in $INSTALL_ROOT"
            return 1
        fi
    fi
}

ffbuild_configure() {
    echo --enable-libcodec2
}

ffbuild_unconfigure() {
    echo --disable-libcodec2
}
