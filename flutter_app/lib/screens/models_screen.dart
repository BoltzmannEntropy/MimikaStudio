import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';

/// Full-page Models screen for managing AI model downloads.
/// Displays all models grouped by engine with download status and actions.
class ModelsScreen extends StatefulWidget {
  const ModelsScreen({super.key});

  @override
  State<ModelsScreen> createState() => _ModelsScreenState();
}

class _ModelsScreenState extends State<ModelsScreen> {
  final ApiService _api = ApiService();
  static const Set<String> _hiddenEngines = {'cosyvoice3'};
  List<Map<String, dynamic>> _models = [];
  bool _isLoading = true;
  String? _error;
  Timer? _pollTimer;

  // Engine order and labels
  static const List<String> _engineOrder = [
    'kokoro',
    'supertonic',
    'qwen3',
    'chatterbox',
    'indextts2',
  ];
  static const Map<String, String> _engineLabels = {
    'kokoro': 'Kokoro',
    'supertonic': 'Supertonic',
    'qwen3': 'Qwen3-TTS',
    'chatterbox': 'Chatterbox',
    'indextts2': 'IndexTTS-2',
  };
  static const Map<String, String> _engineDescriptions = {
    'kokoro': 'High-quality British English TTS with multiple voices',
    'supertonic': 'Lightning-fast multilingual ONNX text-to-speech',
    'qwen3': 'Voice cloning and custom voice synthesis',
    'chatterbox': 'Expressive voice cloning with emotion control',
    'indextts2': 'Fast voice cloning with natural prosody',
  };

  @override
  void initState() {
    super.initState();
    _loadModels();
    // Poll for status updates every 3 seconds
    _pollTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _loadModels(),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadModels() async {
    try {
      final models = (await _api.getModelsStatus())
          .where((m) => !_hiddenEngines.contains(m['engine']))
          .toList();
      if (mounted) {
        setState(() {
          _models = models;
          _isLoading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && _models.isEmpty) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _downloadModel(String modelName) async {
    try {
      await _api.downloadModel(modelName);
      // Update status to show downloading
      setState(() {
        for (final model in _models) {
          if (model['name'] == modelName) {
            model['download_status'] = 'downloading';
          }
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to start download: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteModel(String modelName, num? sizeGb) async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Model?'),
        content: Text(
          'Are you sure you want to delete "$modelName"?\n\n'
          'This will free up ${sizeGb ?? 0}GB of disk space.\n'
          'You can re-download it later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _api.deleteModel(modelName);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Model "$modelName" deleted successfully'),
            backgroundColor: Colors.green,
          ),
        );
        _loadModels(); // Refresh the list
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete model: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  IconData _engineIcon(String engine) {
    switch (engine) {
      case 'kokoro':
        return Icons.volume_up;
      case 'qwen3':
        return Icons.record_voice_over;
      case 'chatterbox':
        return Icons.mic;
      case 'supertonic':
        return Icons.bolt;
      case 'indextts2':
        return Icons.auto_awesome;
      default:
        return Icons.model_training;
    }
  }

  Color _engineColor(String engine) {
    switch (engine) {
      case 'kokoro':
        return Colors.blue;
      case 'qwen3':
        return Colors.teal;
      case 'chatterbox':
        return Colors.orange;
      case 'supertonic':
        return Colors.deepPurple;
      case 'indextts2':
        return Colors.deepPurple;
      default:
        return Colors.grey;
    }
  }

  Widget _buildModelCard(Map<String, dynamic> model) {
    final name = model['name'] as String;
    final engine = model['engine'] as String;
    final sizeGb = model['size_gb'] as num?;
    final downloaded = model['downloaded'] as bool? ?? false;
    final modelType = model['model_type'] as String? ?? 'huggingface';
    final description = model['description'] as String? ?? '';
    final hfRepo = model['hf_repo'] as String? ?? '';
    final downloadStatus = model['download_status'] as String?;
    final downloadError = model['download_error'] as String?;
    final downloadedPath = (model['downloaded_path'] as String?)?.trim();
    final cacheDir = (model['cache_dir'] as String?)?.trim();
    final resolvedPath = (downloadedPath != null && downloadedPath.isNotEmpty)
        ? downloadedPath
        : ((cacheDir != null && cacheDir.isNotEmpty) ? cacheDir : null);

    final isDownloading = downloadStatus == 'downloading';
    final downloadFailed = downloadStatus == 'failed';
    final color = _engineColor(engine);
    final hfUrl = hfRepo.isNotEmpty ? 'https://huggingface.co/$hfRepo' : '';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 6),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Engine icon
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(_engineIcon(engine), color: color, size: 26),
            ),
            const SizedBox(width: 16),
            // Model info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      if (sizeGb != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${sizeGb}GB',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                  // Source URL
                  if (hfUrl.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: () => _launchUrl(hfUrl),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.link,
                            size: 14,
                            color: Colors.blue.shade600,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              hfRepo,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.blue.shade600,
                                decoration: TextDecoration.underline,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (downloadFailed && downloadError != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 16,
                            color: Colors.red.shade700,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              downloadError,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.red.shade700,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  // Status and actions row
                  Row(
                    children: [
                      _buildStatusWidget(
                        downloaded,
                        isDownloading,
                        downloadFailed,
                        modelType,
                        name,
                      ),
                      if (downloaded && modelType != 'pip') ...[
                        const SizedBox(width: 12),
                        IconButton.outlined(
                          onPressed: () => _deleteModel(name, sizeGb),
                          icon: const Icon(Icons.delete_outline, size: 20),
                          tooltip: 'Delete model',
                          style: IconButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: BorderSide(color: Colors.red.shade300),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (resolvedPath != null && modelType != 'pip') ...[
                    const SizedBox(height: 8),
                    SelectableText(
                      '${downloaded ? 'Path' : 'Target'}: $resolvedPath',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade700,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusWidget(
    bool downloaded,
    bool isDownloading,
    bool downloadFailed,
    String modelType,
    String name,
  ) {
    if (downloaded) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.green.withValues(alpha: 0.5)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, size: 18, color: Colors.green),
            SizedBox(width: 6),
            Text(
              'Ready',
              style: TextStyle(
                fontSize: 13,
                color: Colors.green,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    if (isDownloading) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.blue.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 8),
            Text(
              'Downloading...',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      );
    }

    if (modelType == 'pip') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.warning_amber, size: 18, color: Colors.orange),
            SizedBox(width: 6),
            Text(
              'Requires pip install',
              style: TextStyle(
                fontSize: 13,
                color: Colors.orange,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    return FilledButton.icon(
      onPressed: () => _downloadModel(name),
      icon: Icon(downloadFailed ? Icons.refresh : Icons.download, size: 18),
      label: Text(
        downloadFailed ? 'Retry Download' : 'Download',
        style: const TextStyle(fontSize: 13),
      ),
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
    );
  }

  Widget _buildEngineSection(String engine, List<Map<String, dynamic>> models) {
    final color = _engineColor(engine);
    final label = _engineLabels[engine] ?? engine;
    final description = _engineDescriptions[engine] ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Engine header
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(_engineIcon(engine), color: color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        description,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // Models count badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${models.where((m) => m['downloaded'] == true).length}/${models.length}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Model cards
        ...models.map(_buildModelCard),
        const SizedBox(height: 24),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Group models by engine
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final model in _models) {
      final engine = model['engine'] as String;
      grouped.putIfAbsent(engine, () => []).add(model);
    }

    final downloadedCount = _models
        .where((m) => m['downloaded'] == true)
        .length;
    final totalCount = _models.length;
    final allDownloaded = downloadedCount == totalCount && totalCount > 0;

    return Scaffold(
      body: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              border: Border(
                bottom: BorderSide(color: Theme.of(context).dividerColor),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.model_training,
                    color: Theme.of(context).colorScheme.primary,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'AI Models',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Manage TTS model downloads',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                // Download count badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: allDownloaded
                        ? Colors.green.withValues(alpha: 0.15)
                        : Colors.orange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: allDownloaded
                          ? Colors.green.withValues(alpha: 0.5)
                          : Colors.orange.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        allDownloaded ? Icons.check_circle : Icons.downloading,
                        size: 18,
                        color: allDownloaded ? Colors.green : Colors.orange,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '$downloadedCount/$totalCount ready',
                        style: TextStyle(
                          fontSize: 14,
                          color: allDownloaded ? Colors.green : Colors.orange,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Refresh button
                IconButton.filled(
                  onPressed: () {
                    setState(() => _isLoading = true);
                    _loadModels();
                  },
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Refresh',
                ),
              ],
            ),
          ),
          // Content
          Expanded(
            child: _isLoading
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Loading models...'),
                      ],
                    ),
                  )
                : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 64,
                            color: Colors.red.shade300,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Failed to load models',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.red.shade700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _error!,
                            style: TextStyle(color: Colors.grey.shade600),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),
                          FilledButton.icon(
                            onPressed: () {
                              setState(() => _isLoading = true);
                              _loadModels();
                            },
                            icon: const Icon(Icons.refresh),
                            label: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  )
                : _models.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.inbox,
                          size: 64,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No models available',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final engine in _engineOrder)
                          if (grouped.containsKey(engine))
                            _buildEngineSection(engine, grouped[engine]!),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
