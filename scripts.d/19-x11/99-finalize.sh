#!/bin/bash

SCRIPT_SKIP="1"

ffbuild_enabled() {
    [[ $TARGET != linux* ]] && return 1
    return 0
}

ffbuild_dockerlayer() {
    to_df "COPY --link --from=${SELFLAYER} \$INSTALL_ROOT/. \$FFBUILD_PREFIX"
    to_df "COPY --link --from=${SELFLAYER} \$INSTALL_ROOT/share/aclocal/. /usr/share/aclocal"
}

ffbuild_dockerdl() {
    return 0
}

ffbuild_dockerbuild() {
    if [[ "${PREFER_SHARED}" != "1" ]]; then
            rm "$INSTALL_ROOT"/lib/lib*.so* || true
            rm "$INSTALL_ROOT"/lib/*.la || true
    fi
}

ffbuild_libs() {
    echo -ldl
}
