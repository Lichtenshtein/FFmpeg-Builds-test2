#!/bin/bash
FF_CONFIGURE="--enable-gpl --enable-version3 --disable-debug"
# Base extra flags for FFmpeg compilation
# These are IN ADDITION to what component scripts contribute
# FF_CFLAGS="-I/opt/ffbuild/include -D_WIN32_WINNT=0x0A00 -D_WIN32 -D__USE_MINGW_ANSI_STDIO=1 -mms-bitfields"
# FF_CXXFLAGS="-I/opt/ffbuild/include -D_WIN32_WINNT=0x0A00 -D_WIN32 -D__USE_MINGW_ANSI_STDIO=1 -fexceptions"
# FF_LDFLAGS="-L/opt/ffbuild/lib -static-libgcc -static-libstdc++ -pthread -lssp -lm -Wl,--high-entropy-va -Wl,--nxcompat -Wl,--dynamicbase -Wl,--stack,16777216"
# FF_LIBS="-lsetupapi -lole32 -lshlwapi -luser32 -ladvapi32 -ldbghelp -lws2_32 -lbcrypt -lm -lssp -pthread"
GIT_BRANCH="${FFMPEG_BRANCH}"
LICENSE_FILE="COPYING.GPLv3"