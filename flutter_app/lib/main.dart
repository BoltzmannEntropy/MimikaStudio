import 'package:flutter/material.dart';
import 'screens/voice_clone_screen.dart';
import 'screens/quick_tts_screen.dart';
import 'screens/pdf_reader_screen.dart';
import 'services/api_service.dart';

void main() {
  runApp(const MimikaStudioApp());
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
  bool _isBackendConnected = false;
  bool _isChecking = true;
  Map<String, dynamic>? _systemStats;

  @override
  void initState() {
    super.initState();
    _checkBackend();
    _startStatsPolling();
  }

  Future<void> _checkBackend() async {
    setState(() => _isChecking = true);
    final connected = await _api.checkHealth();
    setState(() {
      _isBackendConnected = connected;
      _isChecking = false;
    });
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
          cpuPercent > 80 ? Colors.red : (cpuPercent > 50 ? Colors.orange : Colors.green),
        ),
        const SizedBox(width: 8),
        _buildStatChip(
          Icons.storage,
          'RAM',
          '${ramUsed.toStringAsFixed(1)}/${ramTotal.toStringAsFixed(0)}GB',
          ramPercent > 80 ? Colors.red : (ramPercent > 50 ? Colors.orange : Colors.green),
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
                    : ((gpu['memory_percent'] ?? 0.0) > 50 ? Colors.orange : Colors.green))
                : Colors.teal,
          ),
        ],
      ],
    );
  }

  Widget _buildStatChip(IconData icon, String label, String value, Color color) {
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
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: color),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Connecting to backend...'),
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
              const Text('Run: tssctl up'),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _checkBackend,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 40,
          title: _buildSystemStatsBar(),
          bottom: const TabBar(
            labelStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            unselectedLabelStyle: TextStyle(fontSize: 14),
            tabs: [
              Tab(icon: Icon(Icons.volume_up, size: 28), text: 'Kokoro TTS'),
              Tab(icon: Icon(Icons.record_voice_over, size: 28), text: 'Voice Clone'),
              Tab(icon: Icon(Icons.menu_book, size: 28), text: 'PDF Reader'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            QuickTtsScreen(),
            VoiceCloneScreen(),
            PdfReaderScreen(),
          ],
        ),
      ),
    );
  }
}
