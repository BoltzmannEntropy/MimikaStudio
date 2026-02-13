import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

/// Service to manage the bundled Python backend lifecycle.
class BackendService {
  static final BackendService _instance = BackendService._internal();
  factory BackendService() => _instance;
  BackendService._internal();

  Process? _backendProcess;
  bool _isStarting = false;
  String _setupStatus = '';
  final _statusController = StreamController<String>.broadcast();

  Stream<String> get statusStream => _statusController.stream;
  String get currentStatus => _setupStatus;
  bool get isStarting => _isStarting;

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
    final venvPython = path.join(backendPath, 'venv', 'bin', 'python');
    return File(venvPython).existsSync();
  }

  /// Check if the backend is already running (on port 8000).
  Future<bool> isBackendRunning() async {
    try {
      final socket = await Socket.connect('127.0.0.1', 8000,
          timeout: const Duration(milliseconds: 500));
      socket.destroy();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Start the bundled backend if available.
  /// Returns true if backend is running (either started or already running).
  Future<bool> startBackend() async {
    // Check if already running
    if (await isBackendRunning()) {
      _updateStatus('Backend already running');
      return true;
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
      final runScript = path.join(backendPath, 'run_backend.sh');
      final venvDir = path.join(backendPath, 'venv');

      // Check if venv exists (first run check)
      if (!Directory(venvDir).existsSync()) {
        _updateStatus('First run: Setting up Python environment...');
        _updateStatus('This may take a few minutes...');
      }

      // Start the backend process
      final process = await Process.start(
        '/bin/bash',
        [runScript],
        workingDirectory: backendPath,
        environment: {
          ...Platform.environment,
          'PYTHONUNBUFFERED': '1',
        },
      );
      _backendProcess = process;

      // Log output in debug mode
      process.stdout.transform(const SystemEncoding().decoder).listen((data) {
        debugPrint('[Backend] $data');
        // Check for startup indicators
        if (data.contains('Uvicorn running') || data.contains('Application startup complete')) {
          _updateStatus('Backend ready');
        } else if (data.contains('Installing')) {
          _updateStatus('Installing dependencies...');
        }
      });

      process.stderr.transform(const SystemEncoding().decoder).listen((data) {
        debugPrint('[Backend Error] $data');
      });

      // Wait for backend to become available
      _updateStatus('Waiting for backend to start...');
      final started = await _waitForBackend(timeout: const Duration(minutes: 5));

      if (started) {
        _updateStatus('Backend started successfully');
        _isStarting = false;
        return true;
      } else {
        _updateStatus('Backend failed to start');
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
  Future<bool> _waitForBackend({Duration timeout = const Duration(seconds: 30)}) async {
    final stopwatch = Stopwatch()..start();
    int attempts = 0;

    while (stopwatch.elapsed < timeout) {
      attempts++;
      if (await isBackendRunning()) {
        debugPrint('Backend ready after $attempts attempts (${stopwatch.elapsed.inSeconds}s)');
        return true;
      }

      // Update status periodically
      if (attempts % 10 == 0) {
        _updateStatus('Waiting for backend... (${stopwatch.elapsed.inSeconds}s)');
      }

      await Future.delayed(const Duration(milliseconds: 500));
    }

    debugPrint('Backend startup timeout after ${stopwatch.elapsed.inSeconds}s');
    return false;
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
