#!/bin/bash

SCRIPT_REPO="https://github.com/AcademySoftwareFoundation/openapv.git"
SCRIPT_COMMIT="dd4f9d5dc0fc522abd2c8dcab8bdfe9a832d6baf"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
    echo "rm -rf test"
}

ffbuild_dockerbuild() {
    set -e

    # Очищаем CMakeLists для приложений, чтобы не собирать лишний мусор
    echo > app/CMakeLists.txt

    mkdir -p build && cd build

    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        # -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF)
        -DENABLE_TESTS=OFF
        -DOAPV_BUILD_APPS=OFF
        -DENABLE_COVERAGE=OFF
    )

    if [[ "${PREFER_SHARED}" == "1" ]]; then
        myconf+=(
            -DOAPV_BUILD_STATIC_LIB=OFF
            -DOAPV_BUILD_SHARED_LIB=ON
        )
    else
        myconf+=(
            -DOAPV_BUILD_STATIC_LIB=ON
            -DOAPV_BUILD_SHARED_LIB=OFF
            # oapv_app will be statically linked against static oapv library
            #-DOAPV_APP_STATIC_BUILD=ON
        )
    fi

    export static_flags=""
    [[ "${PREFER_SHARED}" != "1" ]] && static_flags="-DOAPV_STATIC_DEFINE"

    CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C} $static_flags" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C} $static_flags" \
    LDFLAGS="$LDFLAGS ${USELTO}" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    if [[ "${PREFER_SHARED}" != "1" ]]; then
        # Перемещаем статику из подпапки в корень lib
        if [[ -f "$INSTALL_ROOT/lib/oapv/liboapv.a" ]]; then
            mv "$INSTALL_ROOT/lib/oapv/liboapv.a" "$INSTALL_ROOT/lib/liboapv.a"
        fi
        # Удаляем мусор только при статической сборке
        rm -rf "$INSTALL_ROOT"/bin "$INSTALL_ROOT"/lib/oapv
    fi

    local PC_FILE="$PC_DIR/oapv.pc"
    if [[ -f "$PC_FILE" ]]; then
        sed -i "s|^Cflags:.*|& -I\${includedir}/oapv|" "$PC_FILE"
        sed -i '/^Libs.private:/d' "$PC_FILE"
        sed -i "/^Libs:/i Libs.private: -lm" "$PC_FILE"
        if [[ "${PREFER_SHARED}" != "1" ]]; then
            sed -i 's|-L${libdir}/oapv|-L${libdir}|g' "$PC_FILE"
        fi
        if [[ -n "$static_flags" ]]; then
            if ! grep -qF -- "$static_flags" "$PC_FILE"; then
                sed -i "/^Cflags:/ s/$/ $static_flags/" "$PC_FILE"
            fi
        fi
    fi
}

ffbuild_cflags() {
    echo "$static_flags"
}

ffbuild_configure() {
    echo --enable-liboapv
}

ffbuild_unconfigure() {
    echo --disable-liboapv
}
