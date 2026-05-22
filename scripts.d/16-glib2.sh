#!/bin/bash

SCRIPT_REPO="https://github.com/GNOME/glib.git"
# SCRIPT_COMMIT="2.82.4"
SCRIPT_COMMIT="94d297fe6bd1348f0d761b8adf4634663620091b"

ffbuild_depends() {
    echo zlib
    echo pcre2
    echo libffi
    echo gettext
    echo libiconv
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
    echo "git-submodule-clone"
}

ffbuild_dockerbuild() {
    set -e

    # Создаем пустой си-файл в корне и в gio
    echo "int main() { return 0; }" > dummy.c
    echo "int main() { return 0; }" > gio/dummy.c

    # Меняем исходники на 'dummy.c', а install на false

    # gio_tool
    sed -i "s/executable('gio', gio_tool_sources/executable('gio', 'dummy.c', install : false, #/g" gio/meson.build

    # gresource
    sed -i "s/executable('gresource', 'gresource-tool.c'/executable('gresource', 'dummy.c', install : false/g" gio/meson.build

    # gio-querymodules
    sed -i "s/executable('gio-querymodules', 'gio-querymodules.c', 'giomodule-priv.c'/gio_querymodules = executable('gio-querymodules', 'dummy.c', install : false/g" gio/meson.build

    # glib-compile-schemas
    sed -i "s/executable('glib-compile-schemas',/glib_compile_schemas = executable('glib-compile-schemas', 'dummy.c', install : false, #/g" gio/meson.build

    # glib-compile-resources
    sed -i "s/executable('glib-compile-resources',/glib_compile_resources = executable('glib-compile-resources', 'dummy.c', install : false, #/g" gio/meson.build

    # gsettings
    sed -i "s/executable('gsettings', 'gsettings-tool.c'/executable('gsettings', 'dummy.c', install : false/g" gio/meson.build

    # gdbus
    sed -i "s/executable('gdbus', 'gdbus-tool.c'/gdbus_tool = executable('gdbus', 'dummy.c', install : false/g" gio/meson.build

    # gapplication
    sed -i "s/executable('gapplication', 'gapplication-tool.c'/executable('gapplication', 'dummy.c', install : false/g" gio/meson.build

    # Отключаем создание симлинков для многоархитектурных бинарников, так как они нам не нужны
    sed -i "s/if multiarch_bindir != get_option('bindir')/if false/g" gio/meson.build

    if [[ "${PREFER_SHARED}" != "1" ]]; then
        # fix visibility attribute compatibility for windows static
        sed -i '1i #define GLIB_STATIC_COMPILATION 1' glib/glibconfig.h.in 2>/dev/null || true
    fi

    # Clean legacy windows definitions
    sed -i '/#define _WIN32_WINNT 0x/d' meson.build
    sed -i '/#include <sys\/resource.h>/d' girepository/cmph/cmph_time.h 2>/dev/null || true

    # disable tests
    if [ -f "gio/tests/meson.build" ]; then
        echo "" > gio/tests/meson.build
    fi
    if [ -f "tests/meson.build" ]; then
        echo "" > tests/meson.build
    fi
    # disable unnecessary executables
    if [ -f "gio/meson.build" ]; then
        sed -i "s/subdir('tests')/# subdir('tests')/g" gio/meson.build
    fi

    # Clean up sysprof and third-party fallbacks
    rm -rf subprojects/sysprof subprojects/pcre2 subprojects/libffi

    cat <<EOF > glib_cross.txt
[host_machine]
system = 'windows'
cpu_family = 'x86_64'
cpu = 'x86_64'
endian = 'little'

[binaries]
# exe_wrapper = ['wine']
c = '${FFBUILD_TOOLCHAIN}-gcc'
cpp = '${FFBUILD_TOOLCHAIN}-g++'
ar = '${FFBUILD_TOOLCHAIN}-gcc-ar'
pkg-config = 'pkgconf'
strip = '${FFBUILD_TOOLCHAIN}-strip'
windres = '${FFBUILD_TOOLCHAIN}-windres'
nm = '${FFBUILD_TOOLCHAIN}-gcc-nm'
ranlib = '${FFBUILD_TOOLCHAIN}-gcc-ranlib'
nasm = '/usr/bin/nasm'

[properties]
have_c99_snprintf = true
have_c99_vsnprintf = true
has_function_printf = true
va_val_copy = true
int_res_1 = 4
int_res_2 = 8
needs_exe_wrapper = true
printf_has_glibc_res1 = true
printf_has_glibc_res2 = true
EOF

    mkdir -p _build

    # Формируем список зависимостей из вашего чит-листа
    # pcre2 требует zlib/bz2 в некоторых конфигах
    # local DEP_LIBS="-lpcre2-posix -lpcre2-8 -lffi -lintl -liconv -lcharset -lz"
    # local WIN_LIBS="-luserenv -liphlpapi -lwinmm -luuid -ldnsapi $LIBS"

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --cross-file glib_cross.txt
        --buildtype=release
        --default-library=$([ "${PREFER_SHARED}" == "1" ] && echo shared || echo static)
        --wrap-mode=nodownload
        -Dtests=false
        -Dcpp_std=gnu++20
        -Dc_std=gnu17
        -Dinstalled_tests=false
        -Dintrospection=disabled
        -Dlibmount=disabled
        # -Dnls=disabled
        -Dnls=enabled
        -Dforce_posix_threads=true
        -Dglib_debug=disabled
        -Dman-pages=disabled
        -Dselinux=disabled
        -Dsysprof=disabled
    )

    # Mitigate LTO compiler engine bugs inside GLib compilation 
    local lto_cflags=""
    local lto_ldflags=""
    if [[ "$USE_LTO" == "1" ]]; then
        myconf+=( -Db_lto=false ) # Keep internal meson lto safe
        lto_cflags="${USELTO}${USELTO_C} -fno-use-linker-plugin"
        lto_ldflags="${USELTO} -fno-use-linker-plugin"
    fi

    export static_flags=""
    export self_static_flags=""
    [[ "${PREFER_SHARED}" != "1" ]] && static_flags="-DFFI_STATIC_BUILD" && self_static_flags="-DGLIB_STATIC_COMPILATION"

    meson setup _build . \
        "${myconf[@]}" \
        -Dc_args="$CFLAGS $CPPFLAGS ${lto_cflags} $self_static_flags $static_flags -DG_WIN32_IS_STRICT_MINGW -Wno-attributes -Wno-stringop-overflow" \
        -Dcpp_args="$CXXFLAGS $CPPFLAGS ${lto_cflags} $self_static_flags $static_flags -DG_WIN32_IS_STRICT_MINGW -Wno-attributes -Wno-stringop-overflow" \
        -Dc_link_args="$LDFLAGS ${lto_ldflags}" \
        -Dcpp_link_args="$LDFLAGS ${lto_ldflags}" || return 1

    ninja -C _build $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja -C _build install || return 1

    local ALL_GLIB_PCS=(
        "glib-2.0.pc" "gio-2.0.pc" "gthread-2.0.pc" 
        "gobject-2.0.pc" "gmodule-2.0.pc" "gio-windows-2.0.pc" 
        "girepository-2.0.pc" "gmodule-no-export-2.0.pc" "gmodule-export-2.0.pc"
    )
    for pc_name in "${ALL_GLIB_PCS[@]}"; do
        local pc="$PC_DIR/$pc_name"
        [[ -f "$pc" ]] || continue
        if [[ -n "$self_static_flags" ]]; then
            if ! grep -qF -- "$self_static_flags" "$pc"; then
                sed -i "/^Cflags:/ s/$/ $self_static_flags/" "$pc"
            fi
        fi
    done
}
