#!/bin/bash

SCRIPT_REPO="https://github.com/sekrit-twc/zimg.git"
SCRIPT_COMMIT="fa52dee9ebd2d5bedb5a4068f72a4311ae88a419"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
    echo "git-submodule-clone"
    echo "rm -rf graphengine/testapp graphengine/test graphengine/_msvc _msvc"
}

ffbuild_dockerbuild() {
    set -e

    # Вырезаем макрос скрытия видимости -fvisibility=hidden из configure.ac
    sed -i '/-fvisibility=hidden/,/\])/d' configure.ac

    # Remove Skylake/Cascadelake flag checks
    if [ "${USE_AVX512:-0}" == "0" ]; then
        log_info "Patching zimg configure.ac to enforce disabling AVX-512..."
        # Заменяем жесткие флаги -mavx512* на безопасные -mavx2 -mfma -mf16c
        sed -i 's/-mavx512f -mavx512cd -mavx512vl -mavx512bw -mavx512dq -mavx512vnni/-mavx2 -mfma -mf16c/g' Makefile.am || true
        sed -i 's/-mavx512f -mavx512cd -mavx512vl -mavx512bw -mavx512dq/-mavx2 -mfma -mf16c/g' Makefile.am || true
        # Сбрасываем подстановку макросов настройки, если они остались пустыми
        sed -i 's/\$(SKX_CFLAGS)/$(HSW_CFLAGS)/g' Makefile.am || true
        sed -i 's/\$(CLX_CFLAGS)/$(HSW_CFLAGS)/g' Makefile.am || true
        sed -i 's/-march=skylake-avx512/-march=haswell/g' Makefile.am || true
        sed -i 's/-mtune=skylake-avx512/-mtune=haswell/g' Makefile.am || true
        sed -i 's/-mtune=cascadelake/-mtune=haswell/g' Makefile.am || true
        # Удаляем регистрацию библиотек libavx512.la и libavx512_vnni.la
        sed -i 's/libavx512.la libavx512_vnni.la//g' Makefile.am || true
        # На всякий случай зачищаем строку связей, если они были объявлены в конце списка
        sed -i 's/+= libavx512.la/+= /g' Makefile.am || true
        sed -i 's/+= libavx512_vnni.la/+= /g' Makefile.am || true
        # Принудительно отключаем условный макрос сборщика для AVX512, чтобы защитить логику
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

    CFLAGS="$CFLAGS ${USELTO}${USELTO_C} -fno-fast-math -ffp-contract=off" \
    CPPFLAGS="$CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS ${USELTO}${USELTO_C} -fno-fast-math -ffp-contract=off" \
    LDFLAGS="$LDFLAGS ${USELTO}" \
    LIBS="$LIBS" \
    ./configure "${myconf[@]}" || return 1

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    local PC_FILE="$PC_DIR/zimg.pc"
    if [[ -f "$PC_FILE" ]]; then
        if ! grep -q "Libs.private" "$PC_FILE"; then
            echo "Libs.private: -lstdc++" >> "$PC_FILE"
        else
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
