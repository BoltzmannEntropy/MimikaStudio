import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/quick_tts_screen.dart';
import 'screens/supertonic_screen.dart';
import 'screens/qwen3_clone_screen.dart';
import 'screens/chatterbox_clone_screen.dart';
import 'screens/pdf_reader_screen.dart';
import 'screens/jobs_screen.dart';
import 'screens/models_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/mcp_endpoints_screen.dart';
import 'screens/pro_screen.dart';
import 'screens/about_screen.dart';
import 'services/api_service.dart';
import 'services/backend_service.dart';
import 'version.dart';
import 'widgets/system_log_view.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('Flutter framework error: ${details.exceptionAsString()}');
    debugPrintStack(stackTrace: details.stack);
  };

  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    debugPrint('Uncaught platform error: $error');
    debugPrintStack(stackTrace: stack);
    return true;
  };

  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Material(
      color: Colors.transparent,
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 520),
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.08),
            border: Border.all(color: Colors.red.withValues(alpha: 0.35)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Text(
            'A UI error occurred. Please restart MimikaStudio or check backend status.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  };

  runZonedGuarded(() => runApp(const MimikaStudioApp()), (
    Object error,
    StackTrace stack,
  ) {
    debugPrint('Uncaught zoned error: $error');
    debugPrintStack(stackTrace: stack);
  });
}

class MimikaStudioApp extends StatelessWidget {
  const MimikaStudioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MimikaStudio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final ApiService _api = ApiService();
  final BackendService _backendService = BackendService();
  bool _isBackendConnected = false;
  bool _isChecking = true;
  String _backendStatus = 'Connecting to backend...';
  StreamSubscription<String>? _backendStatusSubscription;
  Map<String, dynamic>? _systemStats;
  final List<String> _startupLogs = <String>[];
  bool _isLogFooterCollapsed = true;
  double _logFooterHeight = 210;
  bool _isExportingSystemLog = false;
  bool _isResolvingPortConflict = false;
  AppLifecycleListener? _appLifecycleListener;
  bool _isShuttingDown = false;
  bool _allowImmediateExit = false;
  bool _isShutdownDialogVisible = false;

  @override
  void initState() {
    super.initState();
    _recordStartupLog('App launched');
    _backendStatusSubscription = _backendService.statusStream.listen((status) {
      if (!mounted) return;
      setState(() {
        _backendStatus = status;
        _recordStartupLog(status);
      });
    });
    _ensureBackend();
    _startStatsPolling();
    if (Platform.isMacOS || Platform.isLinux || Platform.isWindows) {
      _appLifecycleListener = AppLifecycleListener(
        onExitRequested: _handleExitRequested,
      );
    }
  }

  Future<AppExitResponse> _handleExitRequested() async {
    if (_allowImmediateExit) {
      return AppExitResponse.exit;
    }
    if (_isShuttingDown) {
      return AppExitResponse.cancel;
    }
    _isShuttingDown = true;
    unawaited(_shutdownBackendThenExit());
    return AppExitResponse.cancel;
  }

  Future<void> _shutdownBackendThenExit() async {
    _showShutdownDialog();
    try {
      await _backendService.stopBackend().timeout(
        const Duration(seconds: 10),
        onTimeout: () {},
      );
    } catch (e) {
      debugPrint('Error stopping backend during exit: $e');
    } finally {
      _dismissShutdownDialog();
      _allowImmediateExit = true;
      await SystemNavigator.pop();
    }
  }

  void _showShutdownDialog() {
    if (!mounted || _isShutdownDialogVisible) {
      return;
    }
    _isShutdownDialogVisible = true;
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        useRootNavigator: true,
        builder: (dialogContext) {
          return const AlertDialog(
            title: Text('Stopping Server'),
            content: Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'MimikaStudio is stopping the backend before exit...',
                  ),
                ),
              ],
            ),
          );
        },
      ).whenComplete(() {
        _isShutdownDialogVisible = false;
      }),
    );
  }

  void _dismissShutdownDialog() {
    if (!mounted || !_isShutdownDialogVisible) {
      return;
    }
    final navigator = Navigator.of(context, rootNavigator: true);
    if (navigator.canPop()) {
      navigator.pop();
    }
  }

  Future<void> _ensureBackend({
    bool userInitiated = false,
    bool allowPortConflictPrompt = true,
  }) async {
    setState(() {
      _isChecking = true;
      _recordStartupLog('Checking backend health...');
    });

    final alreadyConnected = await _api.checkHealth();
    if (alreadyConnected) {
      if (!mounted) return;
      setState(() {
        _isBackendConnected = true;
        _isChecking = false;
        _backendStatus = userInitiated
            ? 'Backend already connected'
            : 'Backend connected';
        _recordStartupLog('Backend is already running');
      });
      return;
    }

    if (_backendService.hasBundledBackend) {
      setState(() {
        _backendStatus = 'Starting bundled backend...';
        _recordStartupLog('Bundled backend found, launching...');
      });
      final started = await _backendService.startBackend();
      final connected = started ? await _api.checkHealth() : false;
      if (!mounted) return;
      setState(() {
        _isBackendConnected = connected;
        _isChecking = false;
        _backendStatus = connected
            ? 'Backend connected'
            : (_backendService.currentStatus.isNotEmpty
                  ? _backendService.currentStatus
                  : 'Failed to start bundled backend');
        _recordStartupLog(_backendStatus);
      });
      if (!connected && allowPortConflictPrompt) {
        await _promptToResolvePortConflict();
      }
      return;
    }

    if (!mounted) return;
    setState(() {
      _isBackendConnected = false;
      _isChecking = false;
      _backendStatus = 'No bundled backend found (development mode)';
      _recordStartupLog(_backendStatus);
    });
  }

  Future<void> _promptToResolvePortConflict() async {
    if (_isResolvingPortConflict) return;
    final conflict =
        _backendService.portConflict ??
        await _backendService.detectPortConflict();
    if (!mounted || conflict == null) return;

    _isResolvingPortConflict = true;
    final shouldStop = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Port 7693 is already in use'),
          content: Text(
            'Another process is blocking MimikaStudio backend startup:\n\n'
            '${conflict.summary}\n\n'
            'Do you want MimikaStudio to stop it and restart our backend?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Stop & Restart'),
            ),
          ],
        );
      },
    );
    _isResolvingPortConflict = false;

    if (shouldStop != true || !mounted) {
      return;
    }

    setState(() {
      _isChecking = true;
      _backendStatus = 'Stopping ${conflict.summary}...';
      _recordStartupLog(_backendStatus);
    });

    final stopped = await _backendService.stopPortConflictProcess();
    if (!mounted) return;
    if (!stopped) {
      setState(() {
        _isChecking = false;
        _isBackendConnected = false;
        _backendStatus = _backendService.currentStatus;
        _recordStartupLog(_backendStatus);
      });
      return;
    }

    await _ensureBackend(userInitiated: true, allowPortConflictPrompt: false);
  }

  void _startStatsPolling() {
    _updateStats();
    // Poll every 2 seconds
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 2));
      if (mounted && _isBackendConnected) {
        await _updateStats();
        return true;
      }
      return mounted;
    });
  }

  Future<void> _updateStats() async {
    try {
      final stats = await _api.getSystemStats();
      if (mounted) {
        setState(() => _systemStats = stats);
      }
    } catch (e) {
      // Ignore errors
    }
  }

  @override
  void dispose() {
    _appLifecycleListener?.dispose();
    _backendStatusSubscription?.cancel();
    unawaited(_backendService.stopBackend());
    super.dispose();
  }

  void _recordStartupLog(String message) {
    final trimmed = message.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final now = DateTime.now();
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    final ss = now.second.toString().padLeft(2, '0');
    _startupLogs.add('[$hh:$mm:$ss] $trimmed');
    const maxLines = 80;
    if (_startupLogs.length > maxLines) {
      _startupLogs.removeRange(0, _startupLogs.length - maxLines);
    }
  }

  void _resizeLogFooter(double deltaY) {
    setState(() {
      _logFooterHeight = (_logFooterHeight - deltaY).clamp(130.0, 420.0);
    });
  }

  Future<void> _copySystemLogQuick() async {
    try {
      final payload = await _api.getSystemLogs(maxLines: 1500);
      final lines = List<String>.from(
        payload['lines'] as List<dynamic>? ?? const <String>[],
      );
      final text = lines.join('\n').trim();
      if (text.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('System log is empty')));
        return;
      }
      await Clipboard.setData(ClipboardData(text: text));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Copied ${lines.length} log lines')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to copy system log: $e')));
    }
  }

  Future<void> _exportSystemLogQuick() async {
    if (_isExportingSystemLog) return;
    setState(() => _isExportingSystemLog = true);
    try {
      final bundle = await _api.exportSystemLogs(maxLines: 2500);
      final fileName =
          (bundle['fileName'] as String?) ?? 'mimika_system_logs.log';
      final bytes = bundle['bytes'] as List<int>;

      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save System Log',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: const ['log', 'txt'],
      );
      if (savePath == null) {
        return;
      }

      final destinationPath = savePath.toLowerCase().endsWith('.log')
          ? savePath
          : '$savePath.log';
      final destination = File(destinationPath);
      await destination.writeAsBytes(bytes, flush: true);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('System log exported to $destinationPath')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to export system log: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isExportingSystemLog = false);
      }
    }
  }

  Future<void> _openSystemLogDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 20,
          ),
          child: SizedBox(
            width: 980,
            height: 620,
            child: const Padding(
              padding: EdgeInsets.all(10),
              child: SystemLogView(
                title: 'System Log Inspector',
                maxLines: 1600,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSystemLogFooter() {
    final targetHeight = _isLogFooterCollapsed ? 44.0 : _logFooterHeight;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      height: targetHeight,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Column(
        children: [
          GestureDetector(
            onVerticalDragUpdate: _isLogFooterCollapsed
                ? null
                : (details) => _resizeLogFooter(details.delta.dy),
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  const Icon(Icons.terminal_rounded, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    _isLogFooterCollapsed
                        ? 'System Log (collapsed)'
                        : 'System Log',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (!_isLogFooterCollapsed) ...[
                    const SizedBox(width: 8),
                    Icon(
                      Icons.drag_handle,
                      size: 16,
                      color: Colors.grey.shade600,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Drag to resize',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                  const Spacer(),
                  IconButton(
                    tooltip: 'Copy logs',
                    visualDensity: VisualDensity.compact,
                    onPressed: _copySystemLogQuick,
                    icon: const Icon(Icons.copy_rounded, size: 18),
                  ),
                  IconButton(
                    tooltip: 'Export logs',
                    visualDensity: VisualDensity.compact,
                    onPressed: _isExportingSystemLog
                        ? null
                        : _exportSystemLogQuick,
                    icon: _isExportingSystemLog
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download_rounded, size: 18),
                  ),
                  IconButton(
                    tooltip: 'Open log inspector',
                    visualDensity: VisualDensity.compact,
                    onPressed: _openSystemLogDialog,
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  ),
                  IconButton(
                    tooltip: _isLogFooterCollapsed ? 'Expand' : 'Collapse',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(
                      () => _isLogFooterCollapsed = !_isLogFooterCollapsed,
                    ),
                    icon: Icon(
                      _isLogFooterCollapsed
                          ? Icons.unfold_less_rounded
                          : Icons.unfold_more_rounded,
                      size: 18,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!_isLogFooterCollapsed)
            const Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: SystemLogView(title: 'System Log Footer', maxLines: 900),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStartupLogsPanel() {
    return Container(
      constraints: const BoxConstraints(maxWidth: 620),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Startup log',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 140,
            child: ListView.builder(
              reverse: true,
              itemCount: _startupLogs.length,
              itemBuilder: (context, index) {
                final line = _startupLogs[_startupLogs.length - 1 - index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    line,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.25,
                      fontFamily: 'monospace',
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSystemStatsBar() {
    if (_systemStats == null) {
      return const SizedBox.shrink();
    }

    final cpuPercent = _systemStats!['cpu_percent'] ?? 0.0;
    final ramUsed = _systemStats!['ram_used_gb'] ?? 0.0;
    final ramTotal = _systemStats!['ram_total_gb'] ?? 0.0;
    final ramPercent = _systemStats!['ram_percent'] ?? 0.0;
    final gpu = _systemStats!['gpu'];

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildStatChip(
          Icons.memory,
          'CPU',
          '${cpuPercent.toStringAsFixed(0)}%',
          cpuPercent > 80
              ? Colors.red
              : (cpuPercent > 50 ? Colors.orange : Colors.green),
        ),
        const SizedBox(width: 8),
        _buildStatChip(
          Icons.storage,
          'RAM',
          '${ramUsed.toStringAsFixed(1)}/${ramTotal.toStringAsFixed(0)}GB',
          ramPercent > 80
              ? Colors.red
              : (ramPercent > 50 ? Colors.orange : Colors.green),
        ),
        if (gpu != null) ...[
          const SizedBox(width: 8),
          _buildStatChip(
            Icons.videogame_asset,
            'GPU',
            gpu['memory_used_gb'] != null
                ? '${(gpu['memory_used_gb'] ?? 0.0).toStringAsFixed(1)}/${(gpu['memory_total_gb'] ?? 0.0).toStringAsFixed(0)}GB'
                : (gpu['name'] ?? 'Active'),
            gpu['memory_percent'] != null
                ? ((gpu['memory_percent'] ?? 0.0) > 80
                      ? Colors.red
                      : ((gpu['memory_percent'] ?? 0.0) > 50
                            ? Colors.orange
                            : Colors.green))
                : Colors.teal,
          ),
        ],
      ],
    );
  }

  Widget _buildStatChip(
    IconData icon,
    String label,
    String value,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            '$label: $value',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(_backendStatus),
              const SizedBox(height: 16),
              _buildStartupLogsPanel(),
            ],
          ),
        ),
      );
    }

    if (!_isBackendConnected) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cloud_off, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              const Text(
                'Backend not connected',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(_backendStatus, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              _buildStartupLogsPanel(),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => _ensureBackend(userInitiated: true),
                icon: Icon(
                  _backendService.hasBundledBackend
                      ? Icons.restart_alt_rounded
                      : Icons.refresh,
                ),
                label: Text(
                  _backendService.hasBundledBackend
                      ? 'Restart Server'
                      : 'Retry',
                ),
              ),
              if (!_backendService.hasBundledBackend) ...[
                const SizedBox(height: 10),
                const Text('Dev mode: run `bin/mimikactl up`'),
              ],
            ],
          ),
        ),
      );
    }

    return DefaultTabController(
      length: 11,
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 40,
          title: _buildSystemStatsBar(),
          actions: [
            IconButton(
              tooltip: 'System Log',
              onPressed: _openSystemLogDialog,
              icon: const Icon(Icons.terminal_rounded),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.multitrack_audio_rounded,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'MimikaStudio',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.primary,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'v$appVersion',
                      style: TextStyle(
                        fontSize: 10,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            labelStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            unselectedLabelStyle: TextStyle(fontSize: 14),
            tabs: [
              Tab(
                icon: Icon(Icons.psychology_alt_rounded, size: 26),
                text: 'Models',
              ),
              Tab(
                icon: Icon(Icons.graphic_eq_rounded, size: 26),
                text: 'TTS (Kokoro)',
              ),
              Tab(icon: Icon(Icons.bolt_rounded, size: 26), text: 'Supertonic'),
              Tab(
                icon: Icon(Icons.record_voice_over_rounded, size: 26),
                text: 'Qwen3 Clone',
              ),
              Tab(
                icon: Icon(Icons.mic_external_on_rounded, size: 26),
                text: 'Chatterbox',
              ),
              Tab(
                icon: Icon(Icons.description_rounded, size: 26),
                text: 'PDF Reader',
              ),
              Tab(icon: Icon(Icons.work_history_rounded, size: 26), text: 'Jobs'),
              Tab(icon: Icon(Icons.tune_rounded, size: 26), text: 'Settings'),
              Tab(icon: Icon(Icons.hub_rounded, size: 26), text: 'MCP'),
              Tab(
                icon: Icon(Icons.workspace_premium_rounded, size: 26),
                text: 'Pro',
              ),
              Tab(icon: Icon(Icons.info_rounded, size: 26), text: 'About'),
            ],
          ),
        ),
        body: Column(
          children: [
            const Expanded(
              child: TabBarView(
                children: [
                  ModelsScreen(),
                  QuickTtsScreen(),
                  SupertonicScreen(),
                  Qwen3CloneScreen(),
                  ChatterboxCloneScreen(),
                  PdfReaderScreen(),
                  JobsScreen(),
                  SettingsScreen(),
                  McpEndpointsScreen(),
                  ProScreen(),
                  AboutScreen(),
                ],
              ),
            ),
            _buildSystemLogFooter(),
          ],
        ),
      ),
    );
  }
}
