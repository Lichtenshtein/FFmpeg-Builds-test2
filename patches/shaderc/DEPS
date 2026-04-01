use_relative_paths = True

vars = {
  'abseil_git':  'https://github.com/abseil',
  'google_git':  'https://github.com/google',
  'khronos_git': 'https://github.com/KhronosGroup',

  'abseil_revision': '4ff7ff9ee91464682e2916af9ae0d62357001dc4',
  'effcee_revision': 'ae38e040cbb7e83efa8bfbb4967e5b8c8c89b55a',
  'glslang_revision': '2bb9da378bc55360253bed2cba11545929c1e8c4',
  'googletest_revision': 'd72f9c8aea6817cdf1ca0ac10887f328de7f3da2',
  're2_revision': '972a15cedd008d846f1a39b2e88ce48d7f166cbd',
  'spirv_headers_revision': '6dd7ba990830f7c15ac1345ff3b43ef6ffdad216',
  'spirv_tools_revision': 'd7ba8c9fc218830544008cb71e4618adb1c56e12',
}

deps = {
  'third_party/abseil_cpp':
      Var('abseil_git') + '/abseil-cpp.git@' + Var('abseil_revision'),

  'third_party/effcee': Var('google_git') + '/effcee.git@' +
      Var('effcee_revision'),

  'third_party/googletest': Var('google_git') + '/googletest.git@' +
      Var('googletest_revision'),

  'third_party/glslang': Var('khronos_git') + '/glslang.git@' +
      Var('glslang_revision'),

  'third_party/re2': Var('google_git') + '/re2.git@' +
      Var('re2_revision'),

  'third_party/spirv-headers': Var('khronos_git') + '/SPIRV-Headers.git@' +
      Var('spirv_headers_revision'),

  'third_party/spirv-tools': Var('khronos_git') + '/SPIRV-Tools.git@' +
      Var('spirv_tools_revision'),
}
