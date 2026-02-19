import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

class PortConflictDetails {
  final int pid;
  final String command;

  const PortConflictDetails({required this.pid, required this.command});

  String get summary => '$command (PID $pid)';
}

/// Service to manage the bundled Python backend lifecycle.
class BackendService {
  static final BackendService _instance = BackendService._internal();
  factory BackendService() => _instance;
  BackendService._internal();
  static const String backendHost = '127.0.0.1';
  static const int backendPort = 7693;

  Process? _backendProcess;
  bool _isStarting = false;
  String _setupStatus = '';
  PortConflictDetails? _portConflict;
  final _statusController = StreamController<String>.broadcast();

  Stream<String> get statusStream => _statusController.stream;
  String get currentStatus => _setupStatus;
  bool get isStarting => _isStarting;
  bool get hasPortConflict => _portConflict != null;
  PortConflictDetails? get portConflict => _portConflict;

  /// Get the path to the bundled backend directory.
  /// Returns null if not running from an app bundle (dev mode).
  String? get bundledBackendPath {
    if (!Platform.isMacOS) return null;

    // Get the executable path
    final execPath = Platform.resolvedExecutable;
    // In a macOS app bundle: /path/to/App.app/Contents/MacOS/AppName
    // Resources are at: /path/to/App.app/Contents/Resources/

    final macosDir = path.dirname(execPath);
    final contentsDir = path.dirname(macosDir);
    final resourcesDir = path.join(contentsDir, 'Resources');
    final backendDir = path.join(resourcesDir, 'backend');

    if (Directory(backendDir).existsSync()) {
      return backendDir;
    }
    return null;
  }

  /// Check if we're running from an app bundle with bundled backend.
  bool get hasBundledBackend => bundledBackendPath != null;

  /// Check if the venv is ready (dependencies pre-installed during build).
  bool get isVenvReady {
    final backendPath = bundledBackendPath;
    if (backendPath == null) return false;
    final bundledPython = _resolveBundledPython(backendPath);
    return bundledPython != null;
  }

  String? _resolveBundledPython(String backendPath) {
    final resourcesDir = path.dirname(backendPath);
    final candidates = <String>[
      path.join(resourcesDir, 'python', 'bin', 'python3'),
      path.join(resourcesDir, 'python', 'bin', 'python'),
      path.join(backendPath, 'venv', 'bin', 'python3'),
      path.join(backendPath, 'venv', 'bin', 'python'),
    ];
    for (final candidate in candidates) {
      if (File(candidate).existsSync()) {
        return candidate;
      }
    }
    return null;
  }

  String? _resolveBundledSitePackages(String backendPath) {
    final libDir = Directory(path.join(backendPath, 'venv', 'lib'));
    if (!libDir.existsSync()) return null;

    try {
      final children = libDir.listSync();
      for (final child in children) {
        if (child is! Directory) continue;
        final name = path.basename(child.path);
        if (!name.startsWith('python')) continue;
        final sitePackages = path.join(child.path, 'site-packages');
        if (Directory(sitePackages).existsSync()) {
          return sitePackages;
        }
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  String _primaryBackendLogPath() {
    final home = Platform.environment['HOME'] ?? '';
    if (home.isNotEmpty) {
      return path.join(home, 'Library', 'Logs', 'MimikaStudio', 'backend.log');
    }
    return '/tmp/mimikastudio-backend.log';
  }

  Future<String?> _readBackendFailureHint({
    Duration maxAge = const Duration(minutes: 2),
  }) async {
    final candidates = <String>[
      _primaryBackendLogPath(),
      '/tmp/mimikastudio-backend.log',
    ];

    for (final candidate in candidates) {
      final file = File(candidate);
      if (!file.existsSync()) continue;
      try {
        final modified = await file.lastModified();
        if (DateTime.now().difference(modified) > maxAge) {
          continue;
        }
        final lines = await file.readAsLines();
        for (int i = lines.length - 1; i >= 0; i--) {
          final raw = lines[i].trim();
          if (raw.isEmpty) continue;
          final lower = raw.toLowerCase();
          if (lower.contains('uvicorn running')) continue;
          if (lower.contains('application startup complete')) continue;
          if (lower.contains('error') ||
              lower.contains('exception') ||
              lower.contains('traceback') ||
              lower.contains('failed') ||
              lower.contains('no module named') ||
              lower.contains('permission denied') ||
              lower.contains('address already in use')) {
            return raw;
          }
        }

        // Fallback: surface the last non-empty log line.
        for (int i = lines.length - 1; i >= 0; i--) {
          final raw = lines[i].trim();
          if (raw.isNotEmpty) {
            return raw;
          }
        }
      } catch (_) {
        // Ignore unreadable logs and continue to the next candidate.
      }
    }

    return null;
  }

  Map<String, String> _buildBackendEnvironment(
    String backendPath, {
    String? sitePackagesDir,
  }) {
    final home = Platform.environment['HOME'] ?? '';
    final appSupportDir = home.isNotEmpty
        ? path.join(home, 'Library', 'Application Support', 'MimikaStudio')
        : '/tmp/MimikaStudio';
    final appCacheDir = home.isNotEmpty
        ? path.join(home, 'Library', 'Caches', 'MimikaStudio')
        : '/tmp/MimikaStudio/cache';
    final appLogDir = home.isNotEmpty
        ? path.join(home, 'Library', 'Logs', 'MimikaStudio')
        : '/tmp/MimikaStudio/logs';
    final hfHome = path.join(appSupportDir, 'huggingface');
    final hfHub = path.join(hfHome, 'hub');

    for (final dir in [
      appSupportDir,
      appCacheDir,
      appLogDir,
      path.join(appSupportDir, 'data'),
      path.join(appSupportDir, 'outputs'),
      hfHub,
    ]) {
      try {
        Directory(dir).createSync(recursive: true);
      } catch (_) {
        // Ignore and let backend fallback if a path is unavailable.
      }
    }

    final existingPythonPath = Platform.environment['PYTHONPATH'] ?? '';
    final pythonPathParts = <String>[backendPath];
    if (sitePackagesDir != null && sitePackagesDir.isNotEmpty) {
      pythonPathParts.add(sitePackagesDir);
    }
    if (existingPythonPath.isNotEmpty) {
      pythonPathParts.add(existingPythonPath);
    }

    return {
      ...Platform.environment,
      'PYTHONUNBUFFERED': '1',
      'PYTHONPATH': pythonPathParts.join(':'),
      'PYTHONPYCACHEPREFIX': path.join(appCacheDir, 'pycache'),
      'XDG_CACHE_HOME': appCacheDir,
      'MIMIKA_RUNTIME_HOME': appSupportDir,
      'MIMIKA_DATA_DIR': path.join(appSupportDir, 'data'),
      'MIMIKA_LOG_DIR': appLogDir,
      'MIMIKA_OUTPUT_DIR': path.join(appSupportDir, 'outputs'),
      'HF_HOME': hfHome,
      'HUGGINGFACE_HUB_CACHE': hfHub,
      'TRANSFORMERS_CACHE': hfHub,
    };
  }

  /// Check if the backend is already running.
  Future<bool> isBackendRunning() async {
    return _checkBackendHealth();
  }

  Future<bool> _checkBackendHealth() async {
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 1);
      final request = await client
          .getUrl(Uri.parse('http://$backendHost:$backendPort/api/health'))
          .timeout(const Duration(seconds: 1));
      final response = await request.close().timeout(
        const Duration(seconds: 1),
      );
      await response.drain<void>();
      return response.statusCode == 200;
    } catch (_) {
      return false;
    } finally {
      client?.close(force: true);
    }
  }

  Future<PortConflictDetails?> _findPortOwner() async {
    final args = <String>['-nP', '-iTCP:$backendPort', '-sTCP:LISTEN', '-Fpc'];
    for (final executable in const ['/usr/sbin/lsof', 'lsof']) {
      try {
        final result = await Process.run(
          executable,
          args,
        ).timeout(const Duration(seconds: 2));
        final stdout = '${result.stdout}'.trim();
        if (result.exitCode == 1 && stdout.isEmpty) {
          return null;
        }
        if (result.exitCode != 0 || stdout.isEmpty) {
          continue;
        }

        int? pid;
        String? command;
        for (final rawLine in stdout.split('\n')) {
          final line = rawLine.trim();
          if (line.isEmpty) continue;
          if (line.startsWith('p') && pid == null) {
            pid = int.tryParse(line.substring(1).trim());
          } else if (line.startsWith('c') && command == null) {
            command = line.substring(1).trim();
          }
          if (pid != null && command != null) {
            break;
          }
        }
        if (pid != null) {
          return PortConflictDetails(
            pid: pid,
            command: (command == null || command.isEmpty)
                ? 'unknown process'
                : command,
          );
        }
      } catch (_) {
        // Try next lsof path.
      }
    }
    return null;
  }

  String _portConflictStatusText(PortConflictDetails conflict) {
    return 'Backend port $backendPort is in use by ${conflict.summary}';
  }

  Future<PortConflictDetails?> detectPortConflict() async {
    final conflict = await _findPortOwner();
    _portConflict = conflict;
    if (conflict != null) {
      _updateStatus(_portConflictStatusText(conflict));
    }
    return conflict;
  }

  Future<bool> stopPortConflictProcess() async {
    final conflict = _portConflict ?? await _findPortOwner();
    if (conflict == null) {
      _portConflict = null;
      _updateStatus('Backend port $backendPort is already free');
      return true;
    }

    _updateStatus('Stopping ${conflict.summary} on port $backendPort...');

    final term = await Process.run('/bin/kill', [
      '-TERM',
      conflict.pid.toString(),
    ]);
    if (term.exitCode != 0) {
      final err = '${term.stderr}'.trim();
      _updateStatus(
        'Failed to stop ${conflict.summary}: ${err.isEmpty ? 'kill -TERM failed' : err}',
      );
      _portConflict = conflict;
      return false;
    }

    await Future.delayed(const Duration(milliseconds: 900));
    var remaining = await _findPortOwner();
    if (remaining != null && remaining.pid == conflict.pid) {
      await Process.run('/bin/kill', ['-KILL', conflict.pid.toString()]);
      await Future.delayed(const Duration(milliseconds: 500));
      remaining = await _findPortOwner();
    }

    if (remaining != null && remaining.pid == conflict.pid) {
      _portConflict = remaining;
      _updateStatus('Could not free backend port $backendPort');
      return false;
    }

    _portConflict = remaining;
    _updateStatus('Backend port $backendPort is free');
    return true;
  }

  /// Start the bundled backend if available.
  /// Returns true if backend is running (either started or already running).
  Future<bool> startBackend() async {
    _portConflict = null;

    // Check if already running
    if (await isBackendRunning()) {
      _updateStatus('Backend already running');
      return true;
    }

    final existingPortOwner = await _findPortOwner();
    if (existingPortOwner != null) {
      _portConflict = existingPortOwner;
      _updateStatus(_portConflictStatusText(existingPortOwner));
      return false;
    }

    // Check if we have a bundled backend
    final backendPath = bundledBackendPath;
    if (backendPath == null) {
      _updateStatus('No bundled backend (dev mode)');
      return false;
    }

    if (_isStarting) {
      _updateStatus('Backend is already starting...');
      return false;
    }

    _isStarting = true;
    _updateStatus('Starting backend...');

    try {
      final pythonBin = _resolveBundledPython(backendPath);
      if (pythonBin == null) {
        _updateStatus('Bundled Python runtime not found');
        _isStarting = false;
        return false;
      }

      final sitePackagesDir = _resolveBundledSitePackages(backendPath);
      final env = _buildBackendEnvironment(
        backendPath,
        sitePackagesDir: sitePackagesDir,
      );
      env['MIMIKA_BACKEND_PORT'] = backendPort.toString();
      env['MIMIKA_BACKEND_HOST'] = backendHost;

      _updateStatus('Launching backend on $backendHost:$backendPort...');
      String? startupFailure;
      final stderrLines = <String>[];
      final stdoutLines = <String>[];
      final launcherScript = path.join(backendPath, 'run_backend.sh');
      final useLauncherScript = File(launcherScript).existsSync();
      final process = await Process.start(
        useLauncherScript ? '/bin/bash' : pythonBin,
        useLauncherScript
            ? [launcherScript]
            : [
                '-m',
                'uvicorn',
                'main:app',
                '--host',
                backendHost,
                '--port',
                backendPort.toString(),
              ],
        workingDirectory: backendPath,
        environment: env,
      );
      _backendProcess = process;

      // Capture output for startup diagnostics.
      process.stdout.transform(const SystemEncoding().decoder).listen((data) {
        debugPrint('[Backend] $data');
        for (final raw in data.split('\n')) {
          final line = raw.trim();
          if (line.isEmpty) continue;
          stdoutLines.add(line);
          if (stdoutLines.length > 80) {
            stdoutLines.removeAt(0);
          }
        }
        // Check for startup indicators
        if (data.contains('Uvicorn running') ||
            data.contains('Application startup complete')) {
          _updateStatus('Backend ready');
        } else if (data.contains('Installing')) {
          _updateStatus('Installing dependencies...');
        }
      });

      process.stderr.transform(const SystemEncoding().decoder).listen((data) {
        debugPrint('[Backend Error] $data');
        for (final raw in data.split('\n')) {
          final line = raw.trim();
          if (line.isEmpty) continue;
          stderrLines.add(line);
          if (stderrLines.length > 80) {
            stderrLines.removeAt(0);
          }
        }
        final lower = data.toLowerCase();
        if (lower.contains('address already in use') ||
            data.contains('Errno 48')) {
          startupFailure = 'Backend port $backendPort is already in use';
          unawaited(
            detectPortConflict().then((conflict) {
              if (conflict == null) {
                _updateStatus(startupFailure!);
              }
            }),
          );
        }
      });

      // Wait for backend to become available
      _updateStatus('Waiting for backend at $backendHost:$backendPort...');
      final started = await _waitForBackend(
        timeout: const Duration(minutes: 5),
        process: process,
      );

      if (started) {
        _portConflict = null;
        _updateStatus('Backend started successfully');
        _isStarting = false;
        return true;
      } else {
        // If startup helper exited but a healthy backend is already serving,
        // keep UI connected instead of reporting a false negative.
        if (await _checkBackendHealth()) {
          _portConflict = null;
          _updateStatus('Backend connected');
          _isStarting = false;
          return true;
        }

        await Future.delayed(const Duration(milliseconds: 250));
        int? exitCode;
        try {
          exitCode = await process.exitCode.timeout(
            const Duration(milliseconds: 300),
          );
        } catch (_) {
          exitCode = null;
        }

        if (startupFailure == null && stderrLines.isNotEmpty) {
          startupFailure = stderrLines.last;
        }
        if (startupFailure == null && stdoutLines.isNotEmpty) {
          startupFailure = stdoutLines.last;
        }
        if (startupFailure == null && exitCode != null) {
          if (exitCode == 137 || exitCode == 9) {
            startupFailure =
                'Bundled backend was terminated by macOS (exit $exitCode). '
                'Move MimikaStudio to /Applications, open it once via right-click > Open, then press Restart Server.';
          } else {
            startupFailure = 'Backend exited with code $exitCode';
          }
        }
        startupFailure ??= await _readBackendFailureHint();
        if ((startupFailure?.trim().isEmpty ?? true)) {
          startupFailure = 'Backend failed to start';
        }

        _updateStatus(startupFailure ?? 'Backend failed to start');
        _isStarting = false;
        return false;
      }
    } catch (e) {
      _updateStatus('Error starting backend: $e');
      _isStarting = false;
      return false;
    }
  }

  /// Wait for backend to become available.
  Future<bool> _waitForBackend({
    Duration timeout = const Duration(seconds: 30),
    Process? process,
  }) async {
    final stopwatch = Stopwatch()..start();
    int attempts = 0;

    while (stopwatch.elapsed < timeout) {
      attempts++;
      if (process != null && !(await _isProcessRunning(process))) {
        debugPrint('Backend process exited before becoming healthy');
        return false;
      }
      if (await isBackendRunning()) {
        debugPrint(
          'Backend ready after $attempts attempts (${stopwatch.elapsed.inSeconds}s)',
        );
        return true;
      }

      // Update status periodically
      if (attempts % 10 == 0) {
        _updateStatus(
          'Waiting for backend at $backendHost:$backendPort... (${stopwatch.elapsed.inSeconds}s)',
        );
      }

      await Future.delayed(const Duration(milliseconds: 500));
    }

    debugPrint('Backend startup timeout after ${stopwatch.elapsed.inSeconds}s');
    return false;
  }

  Future<bool> _isProcessRunning(Process process) async {
    try {
      await process.exitCode.timeout(Duration.zero);
      return false;
    } on TimeoutException {
      return true;
    }
  }

  /// Stop the backend process.
  Future<void> stopBackend() async {
    final process = _backendProcess;
    if (process != null) {
      _updateStatus('Stopping backend...');
      process.kill(ProcessSignal.sigterm);

      // Wait a bit for graceful shutdown
      await Future.delayed(const Duration(seconds: 2));

      // Force kill if still running
      try {
        process.kill(ProcessSignal.sigkill);
      } catch (e) {
        // Process already terminated
      }

      _backendProcess = null;
      _portConflict = null;
      _updateStatus('Backend stopped');
    }
  }

  void _updateStatus(String status) {
    _setupStatus = status;
    _statusController.add(status);
    debugPrint('[BackendService] $status');
  }

  void dispose() {
    stopBackend();
    _statusController.close();
  }
}
