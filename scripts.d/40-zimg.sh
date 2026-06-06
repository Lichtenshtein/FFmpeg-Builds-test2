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
    default_dl .
    echo "git-submodule-clone"
}

ffbuild_dockerbuild() {
    set -e

    # Remove Skylake/Cascadelake flag checks
    if [ "${USE_AVX512:-0}" == "0" ]; then
        log_info "Patching zimg configure.ac to enforce disabling AVX-512..."
        # Resetting tuning flag substitution for AVX-512 architectures
        sed -i 's/AX_CHECK_COMPILE_FLAG(\[-mtune=skylake-avx512\],.*/AC_SUBST([SKX_CFLAGS], [])/g' configure.ac
        sed -i 's/AX_CHECK_COMPILE_FLAG(\[-mtune=cascadelake\],.*/AC_SUBST([CLX_CFLAGS], [])/g' configure.ac
        # Force the X86SIMD_AVX512 condition to false (stub)
        sed -i 's/AM_CONDITIONAL(\[X86SIMD_AVX512\],.*/AM_CONDITIONAL([X86SIMD_AVX512], [false])/g' configure.ac
    fi

    ./autogen.sh

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --with-pic
        --enable-simd
        --disable-testapp
        --disable-unit-test
        --disable-example
    )

    [[ "${PREFER_SHARED}" == "1" ]] && \
        myconf+=( --disable-static --enable-shared ) || \
        myconf+=( --enable-static --disable-shared )

    CFLAGS="$CFLAGS ${USELTO}${USELTO_C}" \
    CPPFLAGS="$CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS ${USELTO}${USELTO_C}" \
    LDFLAGS="$LDFLAGS ${USELTO}" \
    LIBS="$LIBS" \
    ./configure "${myconf[@]}" || return 1

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    local PC_FILE="$PC_DIR/zimg.pc"
    if [[ -f "$PC_FILE" ]]; then
        if ! grep -q "Libs.private" "$PC_FILE"; then
            sed -i '/^Libs.private:/ s/$/ -lstdc++/' "$PC_FILE"
        fi
    fi
}

ffbuild_configure() {
    echo --enable-libzimg
}

ffbuild_unconfigure() {
    echo --disable-libzimg
}
