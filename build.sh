#!/bin/bash
set -xe
shopt -s globstar
cd "$(dirname "$0")"
source util/vars.sh

source "variants/${TARGET}-${VARIANT}.sh"

for addin in ${ADDINS[*]}; do
    source "addins/${addin}.sh"
done

if docker info -f "{{println .SecurityOptions}}" | grep rootless >/dev/null 2>&1; then
    UIDARGS=()
else
    UIDARGS=( -u "$(id -u):$(id -g)" )
fi

rm -rf ffbuild
mkdir ffbuild

FFMPEG_REPO="${FFMPEG_REPO:-https://github.com/MartinEesmaa/FFmpeg.git}"
FFMPEG_REPO="${FFMPEG_REPO_OVERRIDE:-$FFMPEG_REPO}"
GIT_BRANCH="${GIT_BRANCH:-master}"
GIT_BRANCH="${GIT_BRANCH_OVERRIDE:-$GIT_BRANCH}"

BUILD_SCRIPT="$(mktemp)"
trap "rm -f -- '$BUILD_SCRIPT'" EXIT

cat <<EOF >"$BUILD_SCRIPT"
    set -xe
#    shopt -s nullglob

    # setting up ccache inside a container
    export CCACHE_DIR=/root/.cache/ccache
    export CCACHE_MAXSIZE=1248M

    # check that ccache is active
    # if which "$CC" prints /usr/local/bin/x86_64-w64-mingw32-gcc, then ccache is working
    which "$CC"
    ccache -s

    cd /ffbuild
    rm -rf ffmpeg prefix

    git clone --filter=blob:none --depth=1 --branch='$GIT_BRANCH' '$FFMPEG_REPO' ffmpeg
    cd ffmpeg

    git config user.email "builder@localhost"
    git config user.name "Builder"

    PATCHES=('/patches/$GIT_BRANCH'/*.patch)
    if [[ "${#PATCHES[@]}" = 0 ]]; then
        echo 'No patches found for $GIT_BRANCH'
    fi
    for patch in "${PATCHES[@]}"; do
        echo "Applying $patch"
        git apply --whitespace=fix --ignore-space-change --ignore-whitespace "$patch"
    done

    chmod +x configure

    # Optimized flags for cross-compilation to Windows x64
    # Target modern x86-64 with SSE4.2, AVX, AVX2 (Broadwell features)
    
    OPTIM_CFLAGS="-O3 -fno-strict-aliasing -fno-math-errno -fno-signed-zeros -fno-tree-vectorize"
    OPTIM_CFLAGS="$OPTIM_CFLAGS -msse4.2 -mavx -mavx2 -mfma -mbmi -mbmi2 -mlzcnt"
    OPTIM_CFLAGS="$OPTIM_CFLAGS -ffunction-sections -fdata-sections"
    OPTIM_LDFLAGS="-Wl,--gc-sections -Wl,--as-needed"

    ./configure \\
        --prefix=/ffbuild/prefix \\
        --pkg-config-flags="--static" \\
        $FFBUILD_TARGET_FLAGS \\
        $FF_CONFIGURE \\
        --enable-filter=vpp_amf \\
        --enable-filter=sr_amf \\
        --enable-runtime-cpudetect \\
        --enable-lto \\
        --h264-max-bit-depth=14 \\
        --h265-bit-depths=8,9,10,12 \\
        --extra-cflags="$FF_CFLAGS $OPTIM_CFLAGS" \\
        --extra-cxxflags="$FF_CXXFLAGS $OPTIM_CFLAGS" \\
        --extra-ldflags="$FF_LDFLAGS $OPTIM_LDFLAGS" \\
        --extra-ldexeflags="$FF_LDEXEFLAGS" \\
        --extra-libs="$FF_LIBS" \\
        --cc="$CC" \\
        --cxx="$CXX" \\
        --ar="$AR" \\
        --ranlib="$RANLIB" \\
        --nm="$NM" \\
        --extra-version="VVCEasy"

    make -j\$(nproc) V=1
    make install install-doc
    
    # summary cache statistics
    ccache -s
EOF

# Substitute variables in the script
sed -i "s|\$GIT_BRANCH|$GIT_BRANCH|g" "$BUILD_SCRIPT"
sed -i "s|\$FFMPEG_REPO|$FFMPEG_REPO|g" "$BUILD_SCRIPT"

# Log the build script contents
echo "=== Build Script ==="
cat "$BUILD_SCRIPT"
echo "===================="

[[ -t 1 ]] && TTY_ARG="-t" || TTY_ARG=""

# if inside Docker Build, use the global path, if not, use the local one.
if [ -d "/root/.cache/ccache" ]; then
    FINAL_DEST="/opt/ffdest"
else
    FINAL_DEST="$PWD/artifacts"
fi
mkdir -p "$FINAL_DEST"

# check if we are inside Docker Build (having a mounted cache)
if [ -d "/root/.cache/ccache" ]; then
    echo "Detected Docker Build mount, running script directly..."
    ccache -z # resetting statistics for the current build
    bash "$BUILD_SCRIPT"
    ccache -s
else
    echo "Running via docker run..."
    docker run --rm -i $TTY_ARG "${UIDARGS[@]}" \
        -v "$PWD/ffbuild":/ffbuild \
        -v "$PWD/patches/ffmpeg":/patches \
        -v "$BUILD_SCRIPT":/build.sh \
        "$IMAGE" bash /build.sh
fi

# Package artifacts
# mkdir -p artifacts
# ARTIFACTS_PATH="$PWD/artifacts"
# mkdir -p "$ARTIFACTS_PATH"
BUILD_NAME="ffmpeg_vvceasy-$(./ffbuild/ffmpeg/ffbuild/version.sh ffbuild/ffmpeg)-${TARGET}-${VARIANT}${ADDINS_STR:+-}${ADDINS_STR}"

mkdir -p "ffbuild/pkgroot/$BUILD_NAME"
package_variant ffbuild/prefix "ffbuild/pkgroot/$BUILD_NAME"

[[ -n "$LICENSE_FILE" ]] && cp "ffbuild/ffmpeg/$LICENSE_FILE" "ffbuild/pkgroot/$BUILD_NAME/LICENSE.txt"

# Strip binaries
pushd ffbuild/pkgroot
for bin in ffmpeg ffprobe ffplay; do
    if [[ -f ./$BUILD_NAME/bin/$bin.exe ]]; then
        ${FFBUILD_CROSS_PREFIX}strip --strip-unneeded ./$BUILD_NAME/bin/$bin.exe
    fi
    if [[ -f ./$BUILD_NAME/bin/$bin ]]; then
        strip --strip-unneeded ./$BUILD_NAME/bin/$bin
    fi
done

# Create archive
if [[ "${TARGET}" == win* ]]; then
    OUTPUT_FNAME="${BUILD_NAME}.7z"
    if [ -d "/root/.cache/ccache" ]; then
        # inside Docker: use the installed 7z and write it to FINAL_DEST
        7z a -mx9 -mmt=on "${FINAL_DEST}/${OUTPUT_FNAME}" "$BUILD_NAME"
    else
        # outside: use docker run for 7z
        docker run --rm -i $TTY_ARG "${UIDARGS[@]}" \
            -v "${FINAL_DEST}":/out \
            -v "${PWD}/${BUILD_NAME}":"/${BUILD_NAME}" \
            -w / "$IMAGE" \
            7z a -mx9 -mmt=on "/out/${OUTPUT_FNAME}" "$BUILD_NAME"
    fi
else
    OUTPUT_FNAME="${BUILD_NAME}.tar.xz"
    tar -I "xz -9 -T0" -cf "${FINAL_DEST}/${OUTPUT_FNAME}" "$BUILD_NAME"
fi
popd

# Preserving Metadata for GitHub Actions
if [[ -n "$GITHUB_ACTIONS" ]]; then
    # if we're using Docker build, the files are in /opt/ffdest; otherwise, they're in artifacts/
    # for GITHUB_OUTPUT need host paths
    echo "build_name=${BUILD_NAME}" >> "$GITHUB_OUTPUT"
    echo "${OUTPUT_FNAME}" > "${FINAL_DEST}/${TARGET}-${VARIANT}.txt"
fi

# cd - > /dev/null
rm -rf ffbuild
