#!/bin/bash
SCRIPT_REPO="https://github.com/GNOME/glib.git"
SCRIPT_COMMIT="2.80.0"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerbuild() {
    # Функция для преобразования строки флагов в массив Meson ["flag1", "flag2"]
    to_meson_array() {
        echo "$1" | xargs -n1 | jq -R . | jq -s -c .
    }

    # Генерируем кросс-файл без лишних пробелов
    cat <<EOF > cross_file.txt
[host_machine]
system = 'windows'
cpu_family = 'x86_64'
cpu = 'x86_64'
endian = 'little'

[binaries]
c = '${FFBUILD_TOOLCHAIN}-gcc'
cpp = '${FFBUILD_TOOLCHAIN}-g++'
ar = '${FFBUILD_TOOLCHAIN}-gcc-ar'
pkg-config = 'pkg-config'
strip = '${FFBUILD_TOOLCHAIN}-strip'
windres = '${FFBUILD_TOOLCHAIN}-windres'
nm = '${FFBUILD_TOOLCHAIN}-gcc-nm'
ranlib = '${FFBUILD_TOOLCHAIN}-gcc-ranlib'

[built-in options]
c_args = $(to_meson_array "$CFLAGS")
cpp_args = $(to_meson_array "$CXXFLAGS")
c_link_args = $(to_meson_array "$LDFLAGS")
cpp_link_args = $(to_meson_array "$LDFLAGS")
EOF

    # Добавляем принудительные инклуды для libffi, если meson их не увидит
    export CPATH="$FFBUILD_PREFIX/include"
    export LIBRARY_PATH="$FFBUILD_PREFIX/lib"

    meson setup build \
        --prefix="$FFBUILD_PREFIX" \
        --cross-file cross_file.txt \
        --buildtype release \
        --default-library static \
        -Dtests=false \
        -Dintrospection=disabled \
        -Dlibmount=disabled \
        -Dnls=disabled \
        -Dforce_posix_threads=true

    ninja -C build -j$(nproc) $NINJA_V
    DESTDIR="$FFBUILD_DESTDIR" ninja -C build install

    # Очистка префикса (удаляем импортные библиотеки DLL, если они создались)
    find "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib" -name "*.dll.a" -delete
    find "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib" -name "*.a.p" -rmdir 2>/dev/null || true
}

ffbuild_configure() {
    # Для FFmpeg важно знать, что glib статическая
    echo "--enable-libglib"
}

ffbuild_cflags() {
    echo "-DGLIB_STATIC_COMPILATION"
}

ffbuild_ldflags() {
    # Glib требует системные библиотеки Windows при линковке
    echo "-lws2_32 -lole32 -lshlwapi -luserenv -lsetupapi -liphlpapi"
}
