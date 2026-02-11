#!/bin/bash
SCRIPT_REPO="https://github.com/GNOME/glib.git"
SCRIPT_COMMIT="2.80.0" # Стабильная версия

ffbuild_enabled() {
    return 0
}

ffbuild_dockerbuild() {
    # Создаем cross-file для meson на лету, если его нет
    # Хотя у вас в Dockerfile упоминается cross.meson, используем стандартные переменные
    
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
pkgconfig = 'pkg-config'
strip = '${FFBUILD_TOOLCHAIN}-strip'
windres = '${FFBUILD_TOOLCHAIN}-windres'

[built-in options]
c_args = $(echo $CFLAGS | jq -R -c 'split(" ")' | sed 's/\\//g')
cpp_args = $(echo $CXXFLAGS | jq -R -c 'split(" ")' | sed 's/\\//g')
c_link_args = $(echo $LDFLAGS | jq -R -c 'split(" ")' | sed 's/\\//g')
cpp_link_args = $(echo $LDFLAGS | jq -R -c 'split(" ")' | sed 's/\\//g')
EOF

    meson setup build \
        --prefix="$FFBUILD_PREFIX" \
        --cross-file cross_file.txt \
        --buildtype release \
        -DCMAKE_C_FLAGS="$CFLAGS" \
        -DCMAKE_CXX_FLAGS="$CXXFLAGS" \
        -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS" \
        --default-library static \
        -Dtests=false \
        -Dintrospection=disabled \
        -Dlibmount=disabled \
        -Dnls=enabled

    ninja -j$(nproc) $NINJA_V -C build
    DESTDIR="$FFBUILD_DESTDIR" ninja -C build install

    # Хак для статической линковки: удаляем .dll.a если пролезли
    find "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib" -name "*.dll.a" -delete
}

# Важно для всех, кто линкуется с glib
ffbuild_cflags() {
    echo "-DGLIB_STATIC_COMPILATION"
}
