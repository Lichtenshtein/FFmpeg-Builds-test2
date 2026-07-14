project('VapourSynth', 'c', 'cpp',
    default_options: ['buildtype=release', 'b_ndebug=if-release', 'c_std=c99', 'cpp_std=c++17'],
    license: 'LGPL-2.1-or-later',
    license_files: 'COPYING.LESSER',
    meson_version: '>=1.3.0',
    version: '${VER_FULL}',
)

enable_guard_pattern = get_option('enable_guard_pattern')
enable_x86_asm = get_option('enable_x86_asm')

cxx = meson.get_compiler('cpp')

if cxx.get_argument_syntax() == 'gcc'
    avx2_args = '-march=x86-64-v3'
elif cxx.get_id() == 'clang-cl'
    avx2_args = '/clang:-march=x86-64-v3'
else
    avx2_args = '/arch:AVX2'
endif

host_system = host_machine.system()
is_win = host_system in ['cygwin', 'windows']

if is_win
    dl_dep = dependency('', required: false)
    libp2p_dep = dependency('libp2p', static: true, required: false)
else
    dl_dep = dependency('dl')
endif

if not host_machine.cpu_family().startswith('x86')
    enable_x86_asm = false
endif

incdir = include_directories('include')

# We don't look for a Python installation via import('python'), since we're passing the headers manually.
# But we do need a dependency for linking vsscript.

py_dep = dependency('python3', method: 'pkg-config')

vs_current_release = '${VER_FULL}' 

add_project_arguments(
    cxx.get_supported_arguments(
        '-D_CRT_SECURE_NO_WARNINGS',
        '-DNOMINMAX',
        '-DVS_CURRENT_RELEASE=@0@'.format(vs_current_release),
        '-DVS_GRAPH_API',
        '-DVS_USE_LATEST_API',
        '-DVSSCRIPT_USE_LATEST_API',
        '-Wno-ignored-attributes',
    ),
    language: ['c', 'cpp'],
)

if is_win
    add_project_arguments('-DVS_TARGET_OS_WINDOWS', '-D_UNICODE', '-DUNICODE', language: ['c', 'cpp'])
elif host_system == 'darwin'
    add_project_arguments('-DVS_TARGET_OS_DARWIN', language: ['c', 'cpp'])
elif host_system in ['dragonfly', 'freebsd', 'gnu', 'linux', 'netbsd', 'openbsd']
    add_project_arguments('-DVS_TARGET_OS_LINUX', language: ['c', 'cpp'])
endif

if enable_guard_pattern
    add_project_arguments('-DVS_FRAME_GUARD', language: ['c', 'cpp'])
endif

deps = [
    dl_dep,
    dependency('threads'),
    dependency('zimg', static: true, version: '>=3.0.5'),
]

libs = []

if enable_x86_asm
    add_project_arguments('-DVS_TARGET_CPU_X86', language: ['c', 'cpp'])

    libs += static_library('core_sse2',
        files(
            'src/core/expr/jitcompiler_x86.cpp',
            'src/core/kernel/x86/average_sse2.c',
            'src/core/kernel/x86/convolution_sse2.cpp',
            'src/core/kernel/x86/generic_sse2.cpp',
            'src/core/kernel/x86/merge_sse2.c',
            'src/core/kernel/x86/planestats_sse2.c',
            'src/core/kernel/x86/transpose_sse2.c',
        ),
        gnu_symbol_visibility: 'hidden',
        include_directories: incdir,
    )

    libs += static_library('core_avx2',
        files(
            'src/core/kernel/x86/convolution_avx2.cpp',
            'src/core/kernel/x86/generic_avx2.cpp',
            'src/core/kernel/x86/merge_avx2.c',
            'src/core/kernel/x86/planestats_avx2.c',
        ),
        c_args: avx2_args,
        cpp_args: avx2_args,
        gnu_symbol_visibility: 'hidden',
        include_directories: incdir,
    )
endif

libvapoursynth = library('vapoursynth',
    files(
        'src/core/expr/expr.cpp',
        'src/core/expr/jitcompiler.cpp',
        'src/core/kernel/average.cpp',
        'src/core/kernel/cpulevel.cpp',
        'src/core/kernel/generic.cpp',
        'src/core/kernel/merge.c',
        'src/core/kernel/planestats.c',
        'src/core/kernel/transpose.c',
        'src/core/audiofilters.cpp',
        'src/core/averageframesfilter.cpp',
        'src/core/boxblurfilter.cpp',
        'src/core/cpufeatures.cpp',
        'src/core/exprfilter.cpp',
        'src/core/genericfilters.cpp',
        'src/core/lutfilters.cpp',
        'src/core/memoryuse.cpp',
        'src/core/mergefilters.cpp',
        'src/core/reorderfilters.cpp',
        'src/core/simplefilters.cpp',
        'src/core/textfilter.cpp',
        'src/core/vsapi.cpp',
        'src/core/vscore.cpp',
        'src/core/vslog.cpp',
        'src/core/vsresize.cpp',
        'src/core/vsthreadpool.cpp',
    ),
    c_args: '-DVS_CORE_EXPORTS',
    cpp_args: '-DVS_CORE_EXPORTS',
    dependencies: deps,
    gnu_symbol_visibility: 'hidden',
    include_directories: incdir,
    install: true,
    link_with: libs,
)

libvsscript = library('vsscript',
    files('src/vsscript/vsscript.cpp'),
    cpp_args: ['-DPy_NO_LINK_LIB', '-DVS_CORE_EXPORTS'],
    dependencies: [dl_dep, py_dep],
    gnu_symbol_visibility: 'hidden',
    include_directories: incdir,
    install: true,
)

libdir = get_option('libdir')
includedir = get_option('includedir')

pc_data = configuration_data()
pc_data.set('version', meson.project_version())
pc_data.set('prefix', get_option('prefix'))
pc_data.set('libdir', get_option('prefix') / libdir)
pc_data.set('includedir', get_option('prefix') / includedir)

configure_file(
    configuration: pc_data,
    input: 'vapoursynth.pc.in',
    install: true,
    install_dir: libdir / 'pkgconfig',
    output: 'vapoursynth.pc',
)