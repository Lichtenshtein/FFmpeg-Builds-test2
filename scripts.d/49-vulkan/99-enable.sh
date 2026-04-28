#!/bin/bash

SCRIPT_SKIP="1"

ffbuild_depends() {
    echo vulkan-headers
    echo vulkan-loader
    echo glslang-test
    echo shaderc
    echo spirv-cross
    echo spirv-headers
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerlayer() {
    to_df "COPY --link --from=${SELFLAYER} \$FFBUILD_DESTPREFIX/. \$FFBUILD_PREFIX"
    to_df "COPY --link --from=${SELFLAYER} /opt/glslc /usr/bin/glslc"
}

ffbuild_dockerfinal() {
    to_df "COPY --link --from=${PREVLAYER} \$FFBUILD_PREFIX/. \$FFBUILD_PREFIX"
    to_df "COPY --link --from=${SELFLAYER} /opt/glslc /usr/bin/glslc"
}

ffbuild_dockerdl() {
    true
}

ffbuild_dockerbuild() {
    return 0
}
