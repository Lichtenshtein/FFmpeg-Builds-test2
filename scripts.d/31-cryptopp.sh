#!/bin/bash

SCRIPT_REPO="https://github.com/abdes/cryptopp-cmake.git"
SCRIPT_COMMIT="866aceb8b13b6427a3c4541288ff412ad54f11ea"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    mkdir -p build && cd build

    local myconf=(
        # -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF)
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCRYPTOPP_BUILD_SHARED=OFF
        -DCRYPTOPP_BUILD_TESTING=OFF
        -DCRYPTOPP_BUILD_DOCUMENTATION=OFF
        -DCRYPTOPP_USE_OPENMP=$([ "$USE_OPENMP" == "1" ] && echo ON || echo OFF)
        # Отключаем промежуточный таргет объектов
        -DCRYPTOPP_USE_INTERMEDIATE_OBJECTS_TARGET=OFF
    )

    CFLAGS="$CFLAGS $CPPFLAGS $static_flags ${USELTO}${USELTO_C}" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS $static_flags ${USELTO}${USELTO_C}" \
    LDFLAGS="$LDFLAGS ${USELTO}" \
    LIBS="$LIBS" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    # принудительно вырезаем dll.cpp из объектных файлов
    if [[ "${PREFER_SHARED}" != "1" ]]; then
        local TARGET_LIB="${INSTALL_ROOT}/lib/libcryptopp.a"
        if [ -f "$TARGET_LIB" ]; then
            log_info "${SEARCH_MARK} Checking for duplicate dll.cpp in the created archive..."
            # Проверяем, содержит ли архив этот объектный файл
            if "${AR}" t "$TARGET_LIB" | grep -q "dll.cpp"; then
                log_warn "Detected dll.cpp.obj inside libcryptopp.a! Forcefully removing..."
                "${AR}" d "$TARGET_LIB" dll.cpp.obj
                # Проверяем успешность удаления
                if "${AR}" t "$TARGET_LIB" | grep -q "dll.cpp"; then
                    log_error "Failed to remove dll.cpp.obj from archive!"
                    return 1
                else
                    log_info "${CHECK_MARK} Duplicate dll.cpp.obj successfully extracted from static archive."
                fi
            else
                log_info "${CHECK_MARK} The archive is clean, there are no thunk duplicates."
            fi
        fi
    fi

    mkdir -p "$PC_DIR"
    cat <<EOF > "$PC_DIR/cryptopp.pc"
prefix=$FFBUILD_PREFIX
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: Crypto++
Description: A modern CMake build project for Crypto++
Version: 8.9.0
Libs: -L\${libdir} -lcryptopp
Libs.private: -lstdc++
Cflags: -I\${includedir} -I\${includedir}/cryptopp
EOF

    ln -sf cryptopp.pc "$PC_DIR/libcryptopp.pc"
}
