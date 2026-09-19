import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import 'config.dart';

void main(List<String> rawArgs) async {
  final parser = ArgParser()
    ..addOption(
      'os',
      allowed: ['android', 'linux', 'macos', 'ios', 'windows', 'all'],
      defaultsTo: 'all',
    )
    ..addOption('arch', defaultsTo: 'all')
    ..addOption('sources-dir', defaultsTo: 'sources')
    ..addOption('output-dir', defaultsTo: 'output')
    ..addOption('ndk-path')
    ..addFlag('headers-only', defaultsTo: false);

  final args = parser.parse(rawArgs);
  final targetOs = args['os'] as String;
  final targetArch = args['arch'] as String;
  final sourcesDir = Directory(p.absolute(args['sources-dir'] as String));
  final outputDir = Directory(p.absolute(args['output-dir'] as String));
  final headersOnly = args['headers-only'] as bool;

  print('=== flutter_soloud_prebuilds Builder ===');
  print('Target OS: $targetOs');
  print('Target Arch: $targetArch');
  print('Sources dir: ${sourcesDir.path}');
  print('Output dir: ${outputDir.path}');

  await sourcesDir.create(recursive: true);
  await outputDir.create(recursive: true);

  // 1. Ensure Xiph git repositories are cloned at pinned commits
  await ensureSources(sourcesDir);

  if (headersOnly) {
    print('\nCopying universal headers only...');
    await copyHeaders(sourcesDir, Directory(p.join(outputDir.path, 'include')));
    print('Headers copied successfully.');
    return;
  }

  // Find Android NDK if needed
  String? androidNdk = args['ndk-path'] as String?;
  if (targetOs == 'android' || targetOs == 'all') {
    androidNdk ??=
        Platform.environment['ANDROID_NDK_HOME'] ??
        Platform.environment['ANDROID_NDK_ROOT'] ??
        Platform.environment['ANDROID_NDK'];
    if (androidNdk == null && Platform.environment['ANDROID_HOME'] != null) {
      final ndkDir = Directory(
        p.join(Platform.environment['ANDROID_HOME']!, 'ndk'),
      );
      if (ndkDir.existsSync()) {
        final versions = ndkDir.listSync().whereType<Directory>().toList()
          ..sort((a, b) => a.path.compareTo(b.path));
        if (versions.isNotEmpty) {
          androidNdk = versions.last.path;
        }
      }
    }
  }

  if (targetOs == 'android' || targetOs == 'all') {
    if (androidNdk == null || !Directory(androidNdk).existsSync()) {
      if (targetOs == 'android') {
        throw Exception('Android NDK not found. Set ANDROID_NDK_HOME.');
      } else {
        print('Skipping Android: Android NDK not found.');
      }
    } else {
      await buildAndroid(sourcesDir, outputDir, androidNdk, targetArch);
    }
  }

  if (targetOs == 'linux' || targetOs == 'all') {
    await buildLinux(sourcesDir, outputDir, targetArch);
  }

  if (targetOs == 'macos' || targetOs == 'all') {
    if (!Platform.isMacOS) {
      print('Skipping macOS: Host is not macOS.');
    } else {
      await buildMacOS(sourcesDir, outputDir);
    }
  }

  if (targetOs == 'ios' || targetOs == 'all') {
    if (!Platform.isMacOS) {
      print('Skipping iOS: Host is not macOS.');
    } else {
      await buildIOS(sourcesDir, outputDir);
    }
  }

  if (targetOs == 'windows' || targetOs == 'all') {
    if (!Platform.isWindows) {
      print('Skipping Windows: Host is not Windows.');
    } else {
      await buildWindows(sourcesDir, outputDir, targetArch);
    }
  }

  // Always copy headers to output/include
  await copyHeaders(sourcesDir, Directory(p.join(outputDir.path, 'include')));

  print('\n=== All requested builds completed successfully! ===');
}

Future<void> ensureSources(Directory sourcesDir) async {
  print('\nChecking Xiph Git repositories...');
  for (final repo in xiphRepos) {
    final repoDir = Directory(p.join(sourcesDir.path, repo.name));
    if (!repoDir.existsSync()) {
      print('Cloning ${repo.name} (${repo.commit})...');
      await runProcess('git', ['clone', repo.url, repoDir.path]);
      await runProcess('git', [
        'checkout',
        repo.commit,
      ], workingDirectory: repoDir.path);
    } else {
      print(
        'Repository ${repo.name} exists. Ensuring commit ${repo.commit}...',
      );
      await runProcess('git', [
        'checkout',
        repo.commit,
      ], workingDirectory: repoDir.path);
    }
  }
}

Future<void> runProcess(
  String executable,
  List<String> args, {
  String? workingDirectory,
}) async {
  print('> $executable ${args.join(" ")}');
  final result = await Process.run(
    executable,
    args,
    workingDirectory: workingDirectory,
  );
  if (result.exitCode != 0) {
    stdout.write(result.stdout);
    stderr.write(result.stderr);
    throw ProcessException(
      executable,
      args,
      'Command failed with code ${result.exitCode}',
      result.exitCode,
    );
  }
}

Future<void> runCmake(List<String> args) async {
  await runProcess('cmake', args);
}

Future<void> runCmakeBuild(Directory buildDir) async {
  await runCmake([
    '--build',
    buildDir.path,
    '--config',
    'Release',
    '--target',
    'install',
  ]);
}

void cleanDir(Directory dir) {
  if (dir.existsSync()) {
    dir.deleteSync(recursive: true);
  }
  dir.createSync(recursive: true);
}

String findInstalledOggLib(
  Directory installDir, {
  bool isApple = false,
  bool isWindows = false,
}) {
  if (isApple) {
    return p.join(installDir.path, 'lib', 'libogg.a');
  }
  if (isWindows) {
    return p.join(installDir.path, 'lib', 'ogg.lib');
  }
  final lib64 = File(p.join(installDir.path, 'lib64', 'libogg.so'));
  if (lib64.existsSync()) return lib64.path;
  return p.join(installDir.path, 'lib', 'libogg.so');
}

String? findNdkStrip(String ndkPath) {
  final prebuiltDir = Directory(
    p.join(ndkPath, 'toolchains', 'llvm', 'prebuilt'),
  );
  if (!prebuiltDir.existsSync()) return null;
  final exe = Platform.isWindows ? 'llvm-strip.exe' : 'llvm-strip';
  for (final host in prebuiltDir.listSync()) {
    if (host is Directory) {
      final stripBin = p.join(host.path, 'bin', exe);
      if (File(stripBin).existsSync()) {
        return stripBin;
      }
    }
  }
  return null;
}

// ---------------------------------------------------------------------------
// Android Build
// ---------------------------------------------------------------------------
Future<void> buildAndroid(
  Directory sourcesDir,
  Directory outputDir,
  String ndkPath,
  String targetArch,
) async {
  print('\n--- Building Android libraries ---');
  final abis = <String, String>{
    'arm64-v8a': 'arm64-v8a',
    'armeabi-v7a': 'armeabi-v7a',
    'x86': 'x86',
    'x86_64': 'x86_64',
  };

  final targetAbis = targetArch == 'all'
      ? abis.keys.toList()
      : abis.keys
            .where(
              (k) =>
                  k == targetArch ||
                  (targetArch == 'arm64' && k == 'arm64-v8a') ||
                  (targetArch == 'arm' && k == 'armeabi-v7a') ||
                  (targetArch == 'x64' && k == 'x86_64') ||
                  (targetArch == 'ia32' && k == 'x86'),
            )
            .toList();

  for (final abi in targetAbis) {
    print('\n>>> Building Android ABI: $abi <<<');
    final tempBuild = Directory(
      p.join(Directory.systemTemp.path, 'soloud_build_android', abi),
    );
    final tempInstall = Directory(
      p.join(Directory.systemTemp.path, 'soloud_install_android', abi),
    );
    cleanDir(tempBuild);
    cleanDir(tempInstall);

    final ndkToolchain = p.join(
      ndkPath,
      'build',
      'cmake',
      'android.toolchain.cmake',
    );
    final commonFlags = [
      '-DCMAKE_TOOLCHAIN_FILE=$ndkToolchain',
      '-DANDROID_ABI=$abi',
      '-DANDROID_PLATFORM=android-21',
      '-DCMAKE_BUILD_TYPE=Release',
      '-DCMAKE_POLICY_VERSION_MINIMUM=3.5',
      '-DBUILD_SHARED_LIBS=ON',
      '-DCMAKE_C_FLAGS=-Os -flto -ffunction-sections -fdata-sections',
      '-DCMAKE_SHARED_LINKER_FLAGS=-Wl,-z,max-page-size=16384,--gc-sections -flto',
      '-DCMAKE_INSTALL_PREFIX=${tempInstall.path}',
    ];

    // 1. ogg
    await runCmake([
      '-S',
      p.join(sourcesDir.path, 'ogg'),
      '-B',
      p.join(tempBuild.path, 'ogg'),
      ...commonFlags,
      '-DINSTALL_DOCS=OFF',
      '-DBUILD_TESTING=OFF',
    ]);
    await runCmakeBuild(Directory(p.join(tempBuild.path, 'ogg')));

    // 2. opus
    await runCmake([
      '-S',
      p.join(sourcesDir.path, 'opus'),
      '-B',
      p.join(tempBuild.path, 'opus'),
      ...commonFlags,
      '-DOPUS_BUILD_PROGRAMS=OFF',
      '-DOPUS_BUILD_TESTING=OFF',
      '-DOPUS_STACK_PROTECTOR=OFF',
      '-DOPUS_CUSTOM_MODES=ON',
    ]);
    await runCmakeBuild(Directory(p.join(tempBuild.path, 'opus')));

    // 3. vorbis
    final oggLib = findInstalledOggLib(tempInstall);
    await runCmake([
      '-S',
      p.join(sourcesDir.path, 'vorbis'),
      '-B',
      p.join(tempBuild.path, 'vorbis'),
      ...commonFlags,
      '-DOGG_ROOT=${tempInstall.path}',
      '-DOGG_INCLUDE_DIR=${tempInstall.path}/include',
      '-DOGG_LIBRARY=$oggLib',
      '-DBUILD_TESTING=OFF',
    ]);
    await runCmakeBuild(Directory(p.join(tempBuild.path, 'vorbis')));

    // 4. flac
    await runCmake([
      '-S',
      p.join(sourcesDir.path, 'flac'),
      '-B',
      p.join(tempBuild.path, 'flac'),
      ...commonFlags,
      '-DOGG_ROOT=${tempInstall.path}',
      '-DOGG_INCLUDE_DIR=${tempInstall.path}/include',
      '-DOGG_LIBRARY=$oggLib',
      '-DBUILD_CXXLIBS=OFF',
      '-DBUILD_DOCS=OFF',
      '-DBUILD_EXAMPLES=OFF',
      '-DBUILD_PROGRAMS=OFF',
      '-DBUILD_TESTING=OFF',
      '-DINSTALL_MANPAGES=OFF',
      '-DWITH_STACK_PROTECTOR=OFF',
    ]);
    await runCmakeBuild(Directory(p.join(tempBuild.path, 'flac')));

    // Copy built .so files to output/android/<abi>/
    final destAbiDir = Directory(p.join(outputDir.path, 'android', abi));
    cleanDir(destAbiDir);
    for (final folder in ['lib', 'lib64']) {
      final libDir = Directory(p.join(tempInstall.path, folder));
      if (!libDir.existsSync()) continue;
      for (final file in libDir.listSync()) {
        if (file is File && file.path.endsWith('.so')) {
          final fileName = p.basename(file.path);
          if (fileName.contains('libFLAC++')) continue;
          await file.copy(p.join(destAbiDir.path, fileName));
        }
      }
    }

    // Strip debug symbols
    final llvmStrip = findNdkStrip(ndkPath);
    if (llvmStrip != null) {
      print('Stripping Android $abi symbols with llvm-strip...');
      for (final file in destAbiDir.listSync()) {
        if (file is File && file.path.endsWith('.so')) {
          await runProcess(llvmStrip, [file.path]);
        }
      }
    } else {
      print('Warning: llvm-strip not found in NDK, skipping stripping.');
    }
    print('Android $abi libraries copied to ${destAbiDir.path}');
  }
}

// ---------------------------------------------------------------------------
// Linux Build (x86_64 and arm64)
// ---------------------------------------------------------------------------
Future<void> buildLinux(
  Directory sourcesDir,
  Directory outputDir,
  String targetArch,
) async {
  print('\n--- Building Linux libraries ---');
  final arches = targetArch == 'all'
      ? ['x64', 'arm64']
      : (targetArch == 'x86_64' || targetArch == 'x64')
      ? ['x64']
      : ['arm64'];

  for (final arch in arches) {
    print('\n>>> Building Linux $arch <<<');
    final tempBuild = Directory(
      p.join(Directory.systemTemp.path, 'soloud_build_linux', arch),
    );
    final tempInstall = Directory(
      p.join(Directory.systemTemp.path, 'soloud_install_linux', arch),
    );
    cleanDir(tempBuild);
    cleanDir(tempInstall);

    final isCrossArm64 = arch == 'arm64' && Platform.version.contains('x64');
    final commonFlags = [
      '-DCMAKE_BUILD_TYPE=Release',
      '-DCMAKE_POLICY_VERSION_MINIMUM=3.5',
      '-DBUILD_SHARED_LIBS=ON',
      '-DCMAKE_POSITION_INDEPENDENT_CODE=ON',
      '-DCMAKE_C_FLAGS=-O2 -flto -ffunction-sections -fdata-sections',
      '-DCMAKE_SHARED_LINKER_FLAGS=-Wl,--gc-sections -flto',
      '-DCMAKE_INSTALL_PREFIX=${tempInstall.path}',
      if (isCrossArm64) ...[
        '-DCMAKE_SYSTEM_NAME=Linux',
        '-DCMAKE_SYSTEM_PROCESSOR=aarch64',
        '-DCMAKE_C_COMPILER=aarch64-linux-gnu-gcc',
        '-DCMAKE_CXX_COMPILER=aarch64-linux-gnu-g++',
      ],
    ];

    // 1. ogg
    await runCmake([
      '-S',
      p.join(sourcesDir.path, 'ogg'),
      '-B',
      p.join(tempBuild.path, 'ogg'),
      ...commonFlags,
      '-DINSTALL_DOCS=OFF',
      '-DBUILD_TESTING=OFF',
    ]);
    await runCmakeBuild(Directory(p.join(tempBuild.path, 'ogg')));

    // 2. opus
    await runCmake([
      '-S',
      p.join(sourcesDir.path, 'opus'),
      '-B',
      p.join(tempBuild.path, 'opus'),
      ...commonFlags,
      '-DOPUS_BUILD_PROGRAMS=OFF',
      '-DOPUS_BUILD_TESTING=OFF',
      '-DOPUS_STACK_PROTECTOR=OFF',
      '-DOPUS_CUSTOM_MODES=ON',
    ]);
    await runCmakeBuild(Directory(p.join(tempBuild.path, 'opus')));

    // 3. vorbis
    final oggLib = findInstalledOggLib(tempInstall);
    await runCmake([
      '-S',
      p.join(sourcesDir.path, 'vorbis'),
      '-B',
      p.join(tempBuild.path, 'vorbis'),
      ...commonFlags,
      '-DOGG_ROOT=${tempInstall.path}',
      '-DOGG_INCLUDE_DIR=${tempInstall.path}/include',
      '-DOGG_LIBRARY=$oggLib',
      '-DBUILD_TESTING=OFF',
    ]);
    await runCmakeBuild(Directory(p.join(tempBuild.path, 'vorbis')));

    // 4. flac
    await runCmake([
      '-S',
      p.join(sourcesDir.path, 'flac'),
      '-B',
      p.join(tempBuild.path, 'flac'),
      ...commonFlags,
      '-DOGG_ROOT=${tempInstall.path}',
      '-DOGG_INCLUDE_DIR=${tempInstall.path}/include',
      '-DOGG_LIBRARY=$oggLib',
      '-DBUILD_CXXLIBS=OFF',
      '-DBUILD_DOCS=OFF',
      '-DBUILD_EXAMPLES=OFF',
      '-DBUILD_PROGRAMS=OFF',
      '-DBUILD_TESTING=OFF',
      '-DINSTALL_MANPAGES=OFF',
      '-DWITH_STACK_PROTECTOR=OFF',
    ]);
    await runCmakeBuild(Directory(p.join(tempBuild.path, 'flac')));

    // Copy .so files to output/linux/<arch>/
    final destDir = Directory(p.join(outputDir.path, 'linux', arch));
    cleanDir(destDir);
    for (final libFolder in ['lib', 'lib64']) {
      final dir = Directory(p.join(tempInstall.path, libFolder));
      if (!dir.existsSync()) continue;

      // By default followLinks is true, so Dart resolved symlinks to Files!
      // Changing to followLinks: false enables the `entity is Link` block:
      for (final entity in dir.listSync(followLinks: false)) {
        final name = p.basename(entity.path);
        if (name.contains('libFLAC++')) continue;
        if (entity is Link) {
          final target = entity.targetSync();
          final link = Link(p.join(destDir.path, name));
          if (link.existsSync()) link.deleteSync();
          link.createSync(target);
        } else if (entity is File && name.contains('.so')) {
          await entity.copy(p.join(destDir.path, name));
        }
      }
    }

    // Strip symbols from non-symlink .so files
    final stripTool = isCrossArm64 ? 'aarch64-linux-gnu-strip' : 'strip';
    print('Stripping Linux $arch symbols with $stripTool...');
    // Add followLinks: false so strip only runs on the real files, not symlinks:
    for (final entity in destDir.listSync(followLinks: false)) {
      if (entity is File && entity.path.contains('.so')) {
        await runProcess(stripTool, ['--strip-unneeded', entity.path]);
      }
    }
    print('Linux $arch libraries copied to ${destDir.path}');
  }
}

// ---------------------------------------------------------------------------
// macOS Build (Universal: arm64 + x86_64)
// ---------------------------------------------------------------------------
Future<void> buildMacOS(Directory sourcesDir, Directory outputDir) async {
  print('\n--- Building macOS universal static libraries ---');
  final arches = ['arm64', 'x86_64'];
  final archInstalls = <String, Directory>{};

  for (final arch in arches) {
    print('\n>>> Building macOS $arch <<<');
    final tempBuild = Directory(
      p.join(Directory.systemTemp.path, 'soloud_build_macos', arch),
    );
    final tempInstall = Directory(
      p.join(Directory.systemTemp.path, 'soloud_install_macos', arch),
    );
    cleanDir(tempBuild);
    cleanDir(tempInstall);
    archInstalls[arch] = tempInstall;

    final commonFlags = [
      '-DCMAKE_BUILD_TYPE=Release',
      '-DCMAKE_POLICY_VERSION_MINIMUM=3.5',
      '-DBUILD_SHARED_LIBS=OFF',
      '-DCMAKE_OSX_ARCHITECTURES=$arch',
      '-DCMAKE_OSX_DEPLOYMENT_TARGET=10.13',
      '-DCMAKE_INSTALL_PREFIX=${tempInstall.path}',
    ];

    // ogg
    await runCmake([
      '-S',
      p.join(sourcesDir.path, 'ogg'),
      '-B',
      p.join(tempBuild.path, 'ogg'),
      ...commonFlags,
      '-DINSTALL_DOCS=OFF',
      '-DBUILD_TESTING=OFF',
    ]);
    await runCmakeBuild(Directory(p.join(tempBuild.path, 'ogg')));

    // opus
    const opusAppleFlags =
        '-Os -fno-exceptions -fno-unwind-tables '
        '-fno-asynchronous-unwind-tables';
    await runCmake([
      '-S',
      p.join(sourcesDir.path, 'opus'),
      '-B',
      p.join(tempBuild.path, 'opus'),
      ...commonFlags,
      '-DOPUS_BUILD_PROGRAMS=OFF',
      '-DOPUS_BUILD_TESTING=OFF',
      '-DOPUS_BUILD_SHARED_LIBRARY=OFF',
      '-DCMAKE_C_FLAGS=$opusAppleFlags',
      '-DOPUS_STACK_PROTECTOR=OFF',
      '-DOPUS_CUSTOM_MODES=ON',
    ]);
    await runCmakeBuild(Directory(p.join(tempBuild.path, 'opus')));

    // vorbis
    final oggLib = findInstalledOggLib(tempInstall, isApple: true);
    await runCmake([
      '-S',
      p.join(sourcesDir.path, 'vorbis'),
      '-B',
      p.join(tempBuild.path, 'vorbis'),
      ...commonFlags,
      '-DOGG_ROOT=${tempInstall.path}',
      '-DOGG_INCLUDE_DIR=${tempInstall.path}/include',
      '-DOGG_LIBRARY=$oggLib',
      '-DBUILD_TESTING=OFF',
    ]);
    await runCmakeBuild(Directory(p.join(tempBuild.path, 'vorbis')));

    // flac
    await runCmake([
      '-S',
      p.join(sourcesDir.path, 'flac'),
      '-B',
      p.join(tempBuild.path, 'flac'),
      ...commonFlags,
      '-DOGG_ROOT=${tempInstall.path}',
      '-DOGG_INCLUDE_DIR=${tempInstall.path}/include',
      '-DOGG_LIBRARY=$oggLib',
      '-DWITH_OGG=ON',
      '-DBUILD_CXXLIBS=OFF',
      '-DBUILD_DOCS=OFF',
      '-DBUILD_EXAMPLES=OFF',
      '-DBUILD_PROGRAMS=OFF',
      '-DBUILD_TESTING=OFF',
      '-DINSTALL_MANPAGES=OFF',
      '-DWITH_STACK_PROTECTOR=OFF',
    ]);
    await runCmakeBuild(Directory(p.join(tempBuild.path, 'flac')));
  }

  // Combine arm64 and x86_64 with lipo into output/macos/
  final destDir = Directory(p.join(outputDir.path, 'macos'));
  cleanDir(destDir);
  for (final libName in xiphLibNames) {
    final fileName = 'lib$libName.a';
    final arm64Path = p.join(archInstalls['arm64']!.path, 'lib', fileName);
    final x86Path = p.join(archInstalls['x86_64']!.path, 'lib', fileName);
    final destPath = p.join(destDir.path, fileName);
    await runProcess('lipo', [
      '-create',
      arm64Path,
      x86Path,
      '-output',
      destPath,
    ]);
    // Strip non-global symbols
    await runProcess('strip', ['-x', destPath]);
  }
  print('Universal macOS libraries created in ${destDir.path}');
}

// ---------------------------------------------------------------------------
// iOS Build (Device arm64, Simulator Universal arm64 + x86_64)
// ---------------------------------------------------------------------------
Future<void> buildIOS(Directory sourcesDir, Directory outputDir) async {
  print('\n--- Building iOS static libraries ---');
  final targets = <String, Map<String, String>>{
    'device-arm64': {'sdk': 'iphoneos', 'arch': 'arm64'},
    'sim-arm64': {'sdk': 'iphonesimulator', 'arch': 'arm64'},
    'sim-x86_64': {'sdk': 'iphonesimulator', 'arch': 'x86_64'},
  };

  final targetInstalls = <String, Directory>{};

  for (final entry in targets.entries) {
    final key = entry.key;
    final sdk = entry.value['sdk']!;
    final arch = entry.value['arch']!;
    print('\n>>> Building iOS $sdk ($arch) <<<');

    final tempBuild = Directory(
      p.join(Directory.systemTemp.path, 'soloud_build_ios', key),
    );
    final tempInstall = Directory(
      p.join(Directory.systemTemp.path, 'soloud_install_ios', key),
    );
    cleanDir(tempBuild);
    cleanDir(tempInstall);
    targetInstalls[key] = tempInstall;

    final commonFlags = [
      '-DCMAKE_BUILD_TYPE=Release',
      '-DCMAKE_POLICY_VERSION_MINIMUM=3.5',
      '-DBUILD_SHARED_LIBS=OFF',
      '-DCMAKE_SYSTEM_NAME=iOS',
      '-DCMAKE_OSX_SYSROOT=$sdk',
      '-DCMAKE_OSX_ARCHITECTURES=$arch',
      '-DCMAKE_OSX_DEPLOYMENT_TARGET=12.0',
      '-DCMAKE_INSTALL_PREFIX=${tempInstall.path}',
    ];

    // ogg
    await runCmake([
      '-S',
      p.join(sourcesDir.path, 'ogg'),
      '-B',
      p.join(tempBuild.path, 'ogg'),
      ...commonFlags,
      '-DINSTALL_DOCS=OFF',
      '-DBUILD_TESTING=OFF',
    ]);
    await runCmakeBuild(Directory(p.join(tempBuild.path, 'ogg')));

    // opus
    const opusAppleFlags =
        '-Os -fno-exceptions -fno-unwind-tables '
        '-fno-asynchronous-unwind-tables';
    await runCmake([
      '-S',
      p.join(sourcesDir.path, 'opus'),
      '-B',
      p.join(tempBuild.path, 'opus'),
      ...commonFlags,
      '-DOPUS_BUILD_PROGRAMS=OFF',
      '-DOPUS_BUILD_TESTING=OFF',
      '-DOPUS_BUILD_SHARED_LIBRARY=OFF',
      '-DCMAKE_C_FLAGS=$opusAppleFlags',
      '-DOPUS_STACK_PROTECTOR=OFF',
      '-DOPUS_CUSTOM_MODES=ON',
    ]);
    await runCmakeBuild(Directory(p.join(tempBuild.path, 'opus')));

    // vorbis
    final oggLib = findInstalledOggLib(tempInstall, isApple: true);
    await runCmake([
      '-S',
      p.join(sourcesDir.path, 'vorbis'),
      '-B',
      p.join(tempBuild.path, 'vorbis'),
      ...commonFlags,
      '-DOGG_ROOT=${tempInstall.path}',
      '-DOGG_INCLUDE_DIR=${tempInstall.path}/include',
      '-DOGG_LIBRARY=$oggLib',
      '-DBUILD_TESTING=OFF',
    ]);
    await runCmakeBuild(Directory(p.join(tempBuild.path, 'vorbis')));

    // flac
    await runCmake([
      '-S',
      p.join(sourcesDir.path, 'flac'),
      '-B',
      p.join(tempBuild.path, 'flac'),
      ...commonFlags,
      '-DOGG_ROOT=${tempInstall.path}',
      '-DOGG_INCLUDE_DIR=${tempInstall.path}/include',
      '-DOGG_LIBRARY=$oggLib',
      '-DWITH_OGG=ON',
      '-DIconv_FOUND=OFF',
      '-DIntl_FOUND=OFF',
      '-DBUILD_CXXLIBS=OFF',
      '-DBUILD_DOCS=OFF',
      '-DBUILD_EXAMPLES=OFF',
      '-DBUILD_PROGRAMS=OFF',
      '-DBUILD_TESTING=OFF',
      '-DINSTALL_MANPAGES=OFF',
      '-DWITH_STACK_PROTECTOR=OFF',
    ]);
    await runCmakeBuild(Directory(p.join(tempBuild.path, 'flac')));
  }

  // Copy to output/ios/
  final destDir = Directory(p.join(outputDir.path, 'ios'));
  cleanDir(destDir);

  for (final libName in xiphLibNames) {
    // 1. Device arm64: lib<Name>_iOS-device.a
    final devSrc = File(
      p.join(targetInstalls['device-arm64']!.path, 'lib', 'lib$libName.a'),
    );
    final devDst = p.join(destDir.path, 'lib${libName}_iOS-device.a');
    await devSrc.copy(devDst);
    await runProcess('strip', ['-x', devDst]);

    // 2. Simulator universal (arm64 + x86_64): lib<Name>_iOS-simulator.a
    final simArm64 = p.join(
      targetInstalls['sim-arm64']!.path,
      'lib',
      'lib$libName.a',
    );
    final simX86 = p.join(
      targetInstalls['sim-x86_64']!.path,
      'lib',
      'lib$libName.a',
    );
    final simDst = p.join(destDir.path, 'lib${libName}_iOS-simulator.a');
    await runProcess('lipo', ['-create', simArm64, simX86, '-output', simDst]);
    await runProcess('strip', ['-x', simDst]);
  }
  print('iOS static libraries copied to ${destDir.path}');
}

// ---------------------------------------------------------------------------
// Windows Build (x64 and arm64)
// ---------------------------------------------------------------------------
Future<void> buildWindows(
  Directory sourcesDir,
  Directory outputDir,
  String targetArch,
) async {
  print('\n--- Building Windows libraries ---');
  final arches = targetArch == 'all'
      ? ['x64', 'arm64']
      : (targetArch == 'arm64' ? ['arm64'] : ['x64']);

  for (final arch in arches) {
    print('\n>>> Building Windows $arch <<<');
    final tempBuild = Directory(
      p.join(Directory.systemTemp.path, 'soloud_build_windows', arch),
    );
    final tempInstall = Directory(
      p.join(Directory.systemTemp.path, 'soloud_install_windows', arch),
    );
    cleanDir(tempBuild);
    cleanDir(tempInstall);

    final isArm64 = arch == 'arm64';
    final commonFlags = [
      '-DCMAKE_BUILD_TYPE=Release',
      '-DCMAKE_POLICY_VERSION_MINIMUM=3.5',
      '-DBUILD_SHARED_LIBS=ON',
      '-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded',
      '-DCMAKE_INSTALL_PREFIX=${tempInstall.path}',
      if (isArm64) ...['-A', 'ARM64'],
    ];

    // ogg
    await runCmake([
      '-S',
      p.join(sourcesDir.path, 'ogg'),
      '-B',
      p.join(tempBuild.path, 'ogg'),
      ...commonFlags,
      '-DINSTALL_DOCS=OFF',
      '-DBUILD_TESTING=OFF',
    ]);
    await runCmakeBuild(Directory(p.join(tempBuild.path, 'ogg')));

    // opus
    await runCmake([
      '-S',
      p.join(sourcesDir.path, 'opus'),
      '-B',
      p.join(tempBuild.path, 'opus'),
      ...commonFlags,
      '-DOPUS_BUILD_PROGRAMS=OFF',
      '-DOPUS_BUILD_TESTING=OFF',
      '-DOPUS_STACK_PROTECTOR=OFF',
      '-DOPUS_CUSTOM_MODES=ON',
    ]);
    await runCmakeBuild(Directory(p.join(tempBuild.path, 'opus')));

    // vorbis
    final oggLib = findInstalledOggLib(tempInstall, isWindows: true);
    await runCmake([
      '-S',
      p.join(sourcesDir.path, 'vorbis'),
      '-B',
      p.join(tempBuild.path, 'vorbis'),
      ...commonFlags,
      '-DOGG_ROOT=${tempInstall.path}',
      '-DOGG_INCLUDE_DIR=${tempInstall.path}/include',
      '-DOGG_LIBRARY=$oggLib',
      '-DBUILD_TESTING=OFF',
    ]);
    await runCmakeBuild(Directory(p.join(tempBuild.path, 'vorbis')));

    // flac
    await runCmake([
      '-S',
      p.join(sourcesDir.path, 'flac'),
      '-B',
      p.join(tempBuild.path, 'flac'),
      ...commonFlags,
      '-DOGG_ROOT=${tempInstall.path}',
      '-DOGG_INCLUDE_DIR=${tempInstall.path}/include',
      '-DOGG_LIBRARY=$oggLib',
      '-DBUILD_CXXLIBS=OFF',
      '-DBUILD_DOCS=OFF',
      '-DBUILD_EXAMPLES=OFF',
      '-DBUILD_PROGRAMS=OFF',
      '-DBUILD_TESTING=OFF',
      '-DINSTALL_MANPAGES=OFF',
      '-DWITH_STACK_PROTECTOR=OFF',
      '-DINSTALL_CMAKE_CONFIG_DIR=${tempInstall.path}/cmake',
      '-DENABLE_64_BIT_WORDS=ON',
    ]);
    await runCmakeBuild(Directory(p.join(tempBuild.path, 'flac')));

    // Copy .dll and .lib to output/windows/<arch>/
    final destDir = Directory(p.join(outputDir.path, 'windows', arch));
    cleanDir(destDir);
    for (final folder in ['bin', 'lib']) {
      final dir = Directory(p.join(tempInstall.path, folder));
      if (!dir.existsSync()) continue;
      for (final file in dir.listSync().whereType<File>()) {
        final ext = p.extension(file.path).toLowerCase();
        if (ext == '.dll' || ext == '.lib') {
          await file.copy(p.join(destDir.path, p.basename(file.path)));
        }
      }
    }
    print('Windows $arch libraries copied to ${destDir.path}');
  }
}

// ---------------------------------------------------------------------------
// Copy Universal Headers
// ---------------------------------------------------------------------------
Future<void> copyHeaders(Directory sourcesDir, Directory destIncludeDir) async {
  cleanDir(destIncludeDir);

  // 1. ogg: configure with CMake to generate config_types.h
  final tempOggBuild = Directory(
    p.join(Directory.systemTemp.path, 'soloud_ogg_headers_build'),
  );
  cleanDir(tempOggBuild);
  await runCmake([
    '-S',
    p.join(sourcesDir.path, 'ogg'),
    '-B',
    tempOggBuild.path,
    '-DCMAKE_POLICY_VERSION_MINIMUM=3.5',
    '-DINSTALL_DOCS=OFF',
    '-DBUILD_TESTING=OFF',
  ]);

  await copyDirectory(
    Directory(p.join(sourcesDir.path, 'ogg', 'include', 'ogg')),
    Directory(p.join(destIncludeDir.path, 'ogg')),
  );
  final genConfigTypes = File(
    p.join(tempOggBuild.path, 'include', 'ogg', 'config_types.h'),
  );
  if (genConfigTypes.existsSync()) {
    await genConfigTypes.copy(
      p.join(destIncludeDir.path, 'ogg', 'config_types.h'),
    );
  }
  final makefileAm = File(p.join(destIncludeDir.path, 'ogg', 'Makefile.am'));
  if (makefileAm.existsSync()) makefileAm.deleteSync();
  final configTypesIn = File(
    p.join(destIncludeDir.path, 'ogg', 'config_types.h.in'),
  );
  if (configTypesIn.existsSync()) configTypesIn.deleteSync();

  // 2. opus
  await copyDirectory(
    Directory(p.join(sourcesDir.path, 'opus', 'include')),
    Directory(p.join(destIncludeDir.path, 'opus')),
  );

  // 3. vorbis
  await copyDirectory(
    Directory(p.join(sourcesDir.path, 'vorbis', 'include', 'vorbis')),
    Directory(p.join(destIncludeDir.path, 'vorbis')),
  );

  // 4. flac
  await copyDirectory(
    Directory(p.join(sourcesDir.path, 'flac', 'include', 'FLAC')),
    Directory(p.join(destIncludeDir.path, 'FLAC')),
  );
  await copyDirectory(
    Directory(p.join(sourcesDir.path, 'flac', 'include', 'share')),
    Directory(p.join(destIncludeDir.path, 'share')),
  );
}

Future<void> copyDirectory(Directory src, Directory dst) async {
  if (!src.existsSync()) return;
  await dst.create(recursive: true);
  for (final entity in src.listSync(recursive: true)) {
    final relPath = p.relative(entity.path, from: src.path);
    final targetPath = p.join(dst.path, relPath);
    if (entity is Directory) {
      await Directory(targetPath).create(recursive: true);
    } else if (entity is File) {
      await Directory(p.dirname(targetPath)).create(recursive: true);
      await entity.copy(targetPath);
    }
  }
}
