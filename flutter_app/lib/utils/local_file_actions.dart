import 'dart:io';

import 'package:path/path.dart' as p;

class LocalFileActions {
  static Future<void> openPath(String rawPath) async {
    final resolvedPath = rawPath.trim();
    if (resolvedPath.isEmpty) {
      throw Exception('Path is empty');
    }

    final pathType = FileSystemEntity.typeSync(resolvedPath);
    if (pathType == FileSystemEntityType.notFound) {
      throw Exception('Path does not exist: $resolvedPath');
    }

    final result = await _runOpenCommand(resolvedPath, reveal: false);
    if (result.exitCode != 0) {
      throw Exception(_stderrOrDefault(result, 'Failed to open path'));
    }
  }

  static Future<void> revealInFolder(String rawPath) async {
    final resolvedPath = rawPath.trim();
    if (resolvedPath.isEmpty) {
      throw Exception('Path is empty');
    }

    final pathType = FileSystemEntity.typeSync(resolvedPath);
    if (pathType == FileSystemEntityType.notFound) {
      throw Exception('Path does not exist: $resolvedPath');
    }

    final result = await _runOpenCommand(resolvedPath, reveal: true);
    if (result.exitCode != 0) {
      throw Exception(_stderrOrDefault(result, 'Failed to reveal path'));
    }
  }

  static Future<ProcessResult> _runOpenCommand(
    String resolvedPath, {
    required bool reveal,
  }) {
    if (Platform.isMacOS) {
      return Process.run('open', reveal ? ['-R', resolvedPath] : [resolvedPath]);
    }
    if (Platform.isWindows) {
      return Process.run(
        'explorer',
        reveal ? ['/select,${p.windows.normalize(resolvedPath)}'] : [resolvedPath],
      );
    }
    if (Platform.isLinux) {
      final target = reveal ? p.dirname(resolvedPath) : resolvedPath;
      return Process.run('xdg-open', [target]);
    }
    throw Exception('File actions are not supported on this platform');
  }

  static String _stderrOrDefault(ProcessResult result, String fallback) {
    final stderr = result.stderr.toString().trim();
    if (stderr.isNotEmpty) {
      return stderr;
    }
    final stdout = result.stdout.toString().trim();
    if (stdout.isNotEmpty) {
      return stdout;
    }
    return fallback;
  }
}
