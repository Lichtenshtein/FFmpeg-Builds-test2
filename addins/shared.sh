#!/bin/bash

log_info "${XCLAM_MARK} SHARED Addin: Shared library build enabled"

ffbuild_cflags() {
    echo "-fPIC"
}
ffbuild_cxxflags() {
    echo "-fPIC"
}

ffbuild_ldflags() {
    # Shared builds may need different linker flags
    # but we let build.sh handle --enable-shared vs --disable-shared
    return 0
}