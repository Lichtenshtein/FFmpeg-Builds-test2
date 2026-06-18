#!/bin/bash

[[ "${SEC_PROTO}" != "schannel" ]] && SCRIPT_SKIP="1"

ffbuild_enabled() {
    [[ $TARGET == win* ]] && return 0
}

ffbuild_dockerdl() {
    true
}

ffbuild_dockerstage() {
    return 0
}

ffbuild_dockerlayer() {
    return 0
}

ffbuild_dockerfinal() {
    return 0
}

ffbuild_dockerbuild() {
    return 0
}

ffbuild_configure() {
    [[ "${SEC_PROTO}" != "schannel" ]] && echo --disable-schannel || echo --enable-schannel
}

ffbuild_unconfigure() {
    echo --disable-schannel
}
