#!/bin/bash

SCRIPT_SKIP="1"

ffbuild_enabled() {
    [[ $TARGET == win64 ]] || return 1
    return 0
}

ffbuild_dockerfinal() {
    return 0
}

ffbuild_dockerdl() {
    true
}

ffbuild_dockerlayer() {
    return 0
}

ffbuild_dockerstage() {
    return 0
}

ffbuild_dockerbuild() {
    return 0
}

ffbuild_ldexeflags() {
    echo '-pie'

    if [[ $VARIANT == *shared* ]]; then
        # Can't escape escape hell
        echo -Wl,-rpath='\\\\\\\$\\\$ORIGIN'
        echo -Wl,-rpath='\\\\\\\$\\\$ORIGIN/../lib'
    fi
}
