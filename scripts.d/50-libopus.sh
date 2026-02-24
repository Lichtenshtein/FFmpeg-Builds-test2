#!/bin/bash

SCRIPT_REPO="https://github.com/xiph/opus.git"
SCRIPT_COMMIT="475cbc5d0d13ac81d66f4ba884a7fa0702521b06"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .

    # Ссылка и хэш для проверки
    local OPUS_DATA_URL="https://media.xiph.org/opus/models/opus_data-a5177ec6fb7d15058e99e57029746100121f68e4890b1467d4094aa336b6013e.tar.gz"
    local OPUS_DATA_HASH="a5177ec6fb7d15058e99e57029746100121f68e4890b1467d4094aa336b6013e"

    # Команда для download.sh: создаем папку, качаем с повторами и проверяем хэш
    cat <<EOF
mkdir -p dnn
curl -sL --retry 10 --retry-delay 5 --connect-timeout 30 "$OPUS_DATA_URL" -o dnn/opus_data.tar.gz
echo "$OPUS_DATA_HASH  dnn/opus_data.tar.gz" | sha256sum -c -
mv dnn/opus_data.tar.gz dnn/opus_data-${OPUS_DATA_HASH}.tar.gz
EOF
}

ffbuild_dockerbuild() {
    if [[ -d "/builder/patches/libopus" ]]; then
        for patch in /builder/patches/libopus/*.patch; do
            log_info "-----------------------------------"
            log_info "APPLYING PATCH: $patch"
            if patch -p1 < "$patch"; then
                log_info "${GREEN}${CHECK_MARK} SUCCESS: Patch applied.${NC}"
                log_info "-----------------------------------"
            else
                log_error "${RED}${CROSS_MARK} ERROR: PATCH FAILED! ${CROSS_MARK}${NC}"
                log_info "-----------------------------------"
                # exit 1 # если нужно прервать сборку при ошибке
            fi
        done
    fi

    # re-run autoreconf explicitly because tools versions might have changed since it generared the dl cache
    autoreconf -isf

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --disable-shared
        --enable-static
        --disable-extra-programs
    )

    if [[ $TARGET == winarm* ]]; then
        myconf+=(
            --disable-rtcd
        )
    fi

    ./configure "${myconf[@]}"
    make -j$(nproc) $MAKE_V
    make install DESTDIR="$FFBUILD_DESTDIR"
}

ffbuild_configure() {
    echo --enable-libopus
}

ffbuild_unconfigure() {
    echo --disable-libopus
}
