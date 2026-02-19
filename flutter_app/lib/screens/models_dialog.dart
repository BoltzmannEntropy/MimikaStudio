import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';

class ModelsDialog extends StatefulWidget {
  const ModelsDialog({super.key});

  @override
  State<ModelsDialog> createState() => _ModelsDialogState();
}

class _ModelsDialogState extends State<ModelsDialog> {
  final ApiService _api = ApiService();
  List<Map<String, dynamic>> _models = [];
  bool _isLoading = true;
  String? _error;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _loadModels();
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
      final models = await _api.getModelsStatus();
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to start download: $e')));
      }
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

  Widget _buildModelTile(Map<String, dynamic> model) {
    final name = model['name'] as String;
    final engine = model['engine'] as String;
    final sizeGb = model['size_gb'] as num?;
    final downloaded = model['downloaded'] as bool? ?? false;
    final modelType = model['model_type'] as String? ?? 'huggingface';
    final description = model['description'] as String? ?? '';
    final downloadStatus = model['download_status'] as String?;
    final downloadError = model['download_error'] as String?;

    final isDownloading = downloadStatus == 'downloading';
    final downloadFailed = downloadStatus == 'failed';
    final color = _engineColor(engine);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(_engineIcon(engine), color: color, size: 22),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                name,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
            if (sizeGb != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${sizeGb}GB',
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade700),
                ),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (description.isNotEmpty)
              Text(description, style: const TextStyle(fontSize: 11)),
            if (downloadFailed && downloadError != null)
              Text(
                'Error: $downloadError',
                style: const TextStyle(fontSize: 10, color: Colors.red),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        trailing: _buildStatusWidget(
          downloaded,
          isDownloading,
          downloadFailed,
          modelType,
          name,
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
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.green.withValues(alpha: 0.5)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, size: 14, color: Colors.green),
            SizedBox(width: 4),
            Text(
              'Ready',
              style: TextStyle(
                fontSize: 11,
                color: Colors.green,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    if (isDownloading) {
      return const SizedBox(
        width: 80,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 6),
            Text('Downloading', style: TextStyle(fontSize: 10)),
          ],
        ),
      );
    }

    if (modelType == 'pip') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.warning_amber, size: 14, color: Colors.orange),
            SizedBox(width: 4),
            Text(
              'pip install',
              style: TextStyle(
                fontSize: 11,
                color: Colors.orange,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    return FilledButton.tonalIcon(
      onPressed: () => _downloadModel(name),
      icon: Icon(downloadFailed ? Icons.refresh : Icons.download, size: 16),
      label: Text(
        downloadFailed ? 'Retry' : 'Download',
        style: const TextStyle(fontSize: 11),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Group models by engine
    final engineOrder = [
      'kokoro',
      'supertonic',
      'qwen3',
      'chatterbox',
      'indextts2',
    ];
    final engineLabels = {
      'kokoro': 'Kokoro',
      'supertonic': 'Supertonic',
      'qwen3': 'Qwen3-TTS',
      'chatterbox': 'Chatterbox',
      'indextts2': 'IndexTTS-2',
    };

    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final model in _models) {
      final engine = model['engine'] as String;
      grouped.putIfAbsent(engine, () => []).add(model);
    }

    final downloadedCount = _models
        .where((m) => m['downloaded'] == true)
        .length;
    final totalCount = _models.length;

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 600),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: Row(
              children: [
                const Icon(Icons.model_training, size: 22),
                const SizedBox(width: 8),
                const Text('Models', style: TextStyle(fontSize: 18)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: downloadedCount == totalCount
                        ? Colors.green.withValues(alpha: 0.15)
                        : Colors.orange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$downloadedCount/$totalCount ready',
                    style: TextStyle(
                      fontSize: 12,
                      color: downloadedCount == totalCount
                          ? Colors.green
                          : Colors.orange,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            automaticallyImplyLeading: false,
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: () {
                  setState(() => _isLoading = true);
                  _loadModels();
                },
                tooltip: 'Refresh',
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          body: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 48,
                        color: Colors.red,
                      ),
                      const SizedBox(height: 8),
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () {
                          setState(() => _isLoading = true);
                          _loadModels();
                        },
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    for (final engine in engineOrder)
                      if (grouped.containsKey(engine)) ...[
                        Padding(
                          padding: const EdgeInsets.only(top: 8, bottom: 4),
                          child: Row(
                            children: [
                              Icon(
                                _engineIcon(engine),
                                size: 16,
                                color: _engineColor(engine),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                engineLabels[engine] ?? engine,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: _engineColor(engine),
                                ),
                              ),
                            ],
                          ),
                        ),
                        ...grouped[engine]!.map(_buildModelTile),
                      ],
                  ],
                ),
        ),
      ),
    );
  }
}
