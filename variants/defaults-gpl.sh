FF_CONFIGURE="--enable-gpl --enable-version3 --disable-debug"
LICENSE_FILE="COPYING.GPLv3"
# Base extra flags for FFmpeg compilation
# These are IN ADDITION to what component scripts contribute
FF_CFLAGS="-D_WIN32_WINNT=0x0A00 -D_WIN32 -D__USE_MINGW_ANSI_STDIO=1 -mms-bitfields -I/opt/ffbuild/include"
FF_CXXFLAGS="-D_WIN32_WINNT=0x0A00 -D_WIN32 -D__USE_MINGW_ANSI_STDIO=1 -fexceptions"
FF_LDFLAGS="-L/opt/ffbuild/lib -static-libgcc -static-libstdc++ -pthread -lssp -Wl,--high-entropy-va -Wl,--nxcompat -Wl,--dynamicbase -Wl,--stack,16777216"
FF_LIBS="-lsetupapi -lole32 -lshlwapi -luser32 -ladvapi32 -ldbghelp -lws2_32 -lbcrypt -lm -lssp -pthread"
GIT_BRANCH="master"
