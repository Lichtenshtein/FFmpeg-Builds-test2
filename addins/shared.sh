#!/bin/bash

# actually a 'shared' as an addin is useless

log_info "${XCLAM_MARK} SHARED Addin: Enabling shared library build..."

# Add PIC flags for shared libraries
# -fPICs do already exist in flags by now, but will be deduped

# ffbuild_cflags() {
    # echo "-fPIC"
# }

# ffbuild_cxxflags() {
    # echo "-fPIC"
# }

# there must be a 'static.sh' addin, but there won't
# ffbuild_configure() {
    # echo "--pkg-config-flags=''"
# }
