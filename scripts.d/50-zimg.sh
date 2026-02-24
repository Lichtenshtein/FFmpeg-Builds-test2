#!/bin/bash

SCRIPT_REPO="https://github.com/sekrit-twc/zimg.git"
SCRIPT_COMMIT="df9c1472b9541d0e79c8d02dae37fdf12f189ec2"

ffbuild_enabled() {
    return 0
}

ffbuild_depends() {
    return 0
}

ffbuild_dockerdl() {
    echo "git-mini-clone \"$SCRIPT_REPO\" \"$SCRIPT_COMMIT\" ."
    echo "git submodule --quiet update --init --recursive --depth=1"
}

ffbuild_dockerbuild() {
    if [[ -d "/builder/patches/zimg" ]]; then
        for patch in "/builder/patches/zimg"/*.patch; do
            log_info "\n-----------------------------------"
            log_info "~~~ APPLYING PATCH: $patch"
            if patch -p1 < "$patch"; then
                log_info "${GREEN}${CHECK_MARK} SUCCESS: Patch applied.${NC}"
                log_info "-----------------------------------"
            else
                log_error "${RED}${CROSS_MARK} ERROR: PATCH FAILED! ${CROSS_MARK}${NC}"
                log_error "-----------------------------------"
                # return 1 # если нужно прервать сборку при ошибке
            fi
        done
    fi

    ./autogen.sh

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --disable-shared
        --enable-static
        --with-pic
        --disable-avx512
        --enable-simd
        --disable-testapp
        --disable-example
    )

    # Добавляем -std=c++17 явно, если configure сам не справится.
    ./configure "${myconf[@]}" \
        CFLAGS="$CFLAGS" \
        CXXFLAGS="$CXXFLAGS -std=c++17" \
        LDFLAGS="$LDFLAGS" || { tail -n 200 config.log; exit 1; }

    make -j$(nproc) $MAKE_V
    make install DESTDIR="$FFBUILD_DESTDIR"

    # Исправляем .pc файл для статической линковки в FFmpeg
    local PC_FILE="$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/zimg.pc"
    if [[ -f "$PC_FILE" ]]; then
        # Гарантируем, что FFmpeg увидит необходимость линковки с libstdc++
        if ! grep -q "Libs.private" "$PC_FILE"; then
            echo "Libs.private: -lstdc++" >> "$PC_FILE"
        fi
    fi
}

ffbuild_configure() {
    echo --enable-libzimg
}

ffbuild_unconfigure() {
    echo --disable-libzimg
}
