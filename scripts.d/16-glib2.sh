#!/bin/bash

SCRIPT_REPO="https://github.com/GNOME/glib.git"
SCRIPT_COMMIT="2.82.4" # Стабильная ветка
# SCRIPT_COMMIT="6b11cae1b3bf3e9cff9485481dd1c0f7e806c361"

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

    # Исправляем неверный инклуд sys/resource.h в cmph
    # В MinGW его нет, заменяем проверку или просто комментируем
    # Точный патч для cmph_time.h
    # sed -i '11,13s/^/\/\/ /' girepository/cmph/cmph_time.h
    # sed -i 's/#ifndef WIN32/#if 0/' girepository/cmph/cmph_time.h
    sed -i '/#include <sys\/resource.h>/d' girepository/cmph/cmph_time.h

    # Удаляем жесткое переопределение версии Windows из исходников GLib
    sed -i '/#define _WIN32_WINNT 0x/d' meson.build

    # Удаляем субпроекты, которые ломают сборку
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
    local DEP_LIBS="-lpcre2-posix -lpcre2-8 -lffi -lintl -liconv -lcharset -lz"
    local WIN_LIBS="-luserenv -liphlpapi -lwinmm -luuid -ldnsapi $LIBS"

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
        -Dglib_debug=disabled
        -Dman-pages=disabled
        -Dselinux=disabled
        -Dsysprof=disabled
    )

    [[ "$USE_LTO" == "1" ]] && myconf+=( -Db_lto=true )

    export static_flags=""
    export self_static_flags=""
    [[ "${PREFER_SHARED}" != "1" ]] && static_flags="-DFFI_STATIC_BUILD" && self_static_flags="-DGLIB_STATIC_COMPILATION"

# -Wno-error=missing-include-dirs -Wno-error=redundant-decls
    # Передаем линковочные флаги через meson, чтобы проверки (типа наличия функций) проходили успешно
    meson setup _build . \
        "${myconf[@]}" \
        -Dc_args="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C} $self_static_flags $static_flags -DG_WIN32_IS_STRICT_MINGW -fvisibility=default" \
        -Dcpp_args="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C} $self_static_flags $static_flags -DG_WIN32_IS_STRICT_MINGW -fvisibility=default" \
        -Dc_link_args="$LDFLAGS ${USELTO}" \
        -Dcpp_link_args="$LDFLAGS ${USELTO}" || return 1

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
