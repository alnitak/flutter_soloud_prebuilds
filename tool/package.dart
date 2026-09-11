import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

void main(List<String> args) async {
  final outputDir = Directory(p.absolute(args.isNotEmpty ? args[0] : 'output'));
  final distDir = Directory(p.absolute(args.length > 1 ? args[1] : 'dist'));

  print('=== Packaging Xiph Prebuilds ===');
  print('Input Output Dir: ${outputDir.path}');
  print('Distribution Dir: ${distDir.path}');

  if (!outputDir.existsSync()) {
    throw Exception('Output directory does not exist: ${outputDir.path}');
  }
  await distDir.create(recursive: true);

  // 1. Android
  final androidDir = Directory(p.join(outputDir.path, 'android'));
  if (androidDir.existsSync()) {
    print('Packaging Android...');
    await makeTarGz(androidDir, p.join(distDir.path, 'xiph-android.tar.gz'));
  }

  // 2. Linux x64 & arm64
  final linuxDir = Directory(p.join(outputDir.path, 'linux'));
  if (linuxDir.existsSync()) {
    for (final archDir in linuxDir.listSync().whereType<Directory>()) {
      final arch = p.basename(archDir.path);
      print('Packaging Linux $arch...');
      await makeTarGz(archDir, p.join(distDir.path, 'xiph-linux-$arch.tar.gz'));
    }
  }

  // 3. macOS
  final macosDir = Directory(p.join(outputDir.path, 'macos'));
  if (macosDir.existsSync()) {
    print('Packaging macOS...');
    await makeTarGz(macosDir, p.join(distDir.path, 'xiph-macos.tar.gz'));
  }

  // 4. iOS
  final iosDir = Directory(p.join(outputDir.path, 'ios'));
  if (iosDir.existsSync()) {
    print('Packaging iOS...');
    await makeTarGz(iosDir, p.join(distDir.path, 'xiph-ios.tar.gz'));
  }

  // 5. Windows
  final windowsDir = Directory(p.join(outputDir.path, 'windows'));
  if (windowsDir.existsSync()) {
    for (final archDir in windowsDir.listSync().whereType<Directory>()) {
      final arch = p.basename(archDir.path);
      print('Packaging Windows $arch...');
      await makeZip(archDir, p.join(distDir.path, 'xiph-windows-$arch.zip'));
    }
  }

  // 6. Include headers
  final includeDir = Directory(p.join(outputDir.path, 'include'));
  if (includeDir.existsSync()) {
    print('Packaging Include Headers...');
    await makeTarGz(includeDir, p.join(distDir.path, 'xiph-include.tar.gz'));
  }

  // 7. Calculate SHA256 sums
  print('\nCalculating SHA256 checksums...');
  final sumsFile = File(p.join(distDir.path, 'SHA256SUMS.txt'));
  final lines = <String>[];
  for (final file in distDir.listSync().whereType<File>()) {
    if (p.basename(file.path) == 'SHA256SUMS.txt') continue;
    final bytes = await file.readAsBytes();
    final digest = sha256.convert(bytes);
    lines.add('$digest  ${p.basename(file.path)}');
  }
  lines.sort();
  await sumsFile.writeAsString('${lines.join('\n')}\n');
  print('Generated SHA256SUMS.txt:\n${lines.join('\n')}');

  print('\n=== Packaging completed successfully! ===');
}

Future<void> makeTarGz(Directory srcDir, String tarGzPath) async {
  final target = File(tarGzPath);
  if (target.existsSync()) target.deleteSync();

  final result = await Process.run('tar', [
    '-czf',
    tarGzPath,
    '-C',
    srcDir.path,
    '.',
  ]);
  if (result.exitCode != 0) {
    stderr.write(result.stderr);
    throw ProcessException('tar', ['-czf', tarGzPath], 'Failed to create tar.gz', result.exitCode);
  }
  print('Created: $tarGzPath');
}

Future<void> makeZip(Directory srcDir, String zipPath) async {
  final target = File(zipPath);
  if (target.existsSync()) target.deleteSync();

  ProcessResult result;
  if (Platform.isWindows) {
    result = await Process.run('powershell', [
      '-NoProfile',
      '-Command',
      'Compress-Archive -Path "${srcDir.path}\\*" -DestinationPath "$zipPath" -Force',
    ]);
  } else {
    result = await Process.run('zip', [
      '-r',
      zipPath,
      '.',
    ], workingDirectory: srcDir.path);
  }

  if (result.exitCode != 0) {
    stderr.write(result.stderr);
    throw ProcessException('zip', [zipPath], 'Failed to create zip', result.exitCode);
  }
  print('Created: $zipPath');
}
