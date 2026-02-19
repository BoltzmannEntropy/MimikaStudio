import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';

/// A banner widget that shows the download status of required models
/// and allows users to download them if missing.
class ModelStatusBanner extends StatefulWidget {
  /// List of model names required for this screen
  final List<String> requiredModels;

  /// Engine name for display (e.g., "Kokoro", "Qwen3", "Chatterbox")
  final String engineName;

  /// Color theme for the banner
  final Color themeColor;

  const ModelStatusBanner({
    super.key,
    required this.requiredModels,
    required this.engineName,
    this.themeColor = Colors.blue,
  });

  @override
  State<ModelStatusBanner> createState() => _ModelStatusBannerState();
}

class _ModelStatusBannerState extends State<ModelStatusBanner> {
  final ApiService _api = ApiService();
  List<Map<String, dynamic>> _modelStatuses = [];
  bool _isLoading = true;
  Timer? _pollTimer;
  final Set<String> _downloadingModels = {};

  @override
  void initState() {
    super.initState();
    _loadModelStatus();
    // Poll every 3 seconds for status updates
    _pollTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _loadModelStatus(),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadModelStatus() async {
    try {
      final allModels = await _api.getModelsStatus();
      final relevant = allModels
          .where((m) => widget.requiredModels.contains(m['name']))
          .toList();
      if (mounted) {
        setState(() {
          _modelStatuses = relevant;
          _isLoading = false;
          // Update downloading set
          for (final model in relevant) {
            final name = model['name'] as String;
            if (model['download_status'] == 'downloading') {
              _downloadingModels.add(name);
            } else {
              _downloadingModels.remove(name);
            }
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _downloadModel(String modelName) async {
    setState(() => _downloadingModels.add(modelName));
    try {
      await _api.downloadModel(modelName);
    } catch (e) {
      if (mounted) {
        setState(() => _downloadingModels.remove(modelName));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to start download: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox.shrink();
    }

    final missingModels = _modelStatuses
        .where((m) => m['downloaded'] != true && m['model_type'] != 'pip')
        .toList();
    final downloadedModels = _modelStatuses
        .where((m) => m['downloaded'] == true || m['model_type'] == 'pip')
        .toList();

    // All models ready - show compact success indicator
    if (missingModels.isEmpty && downloadedModels.isNotEmpty) {
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.green.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green.shade700, size: 18),
            const SizedBox(width: 8),
            Text(
              '${widget.engineName} models ready',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.green.shade700,
              ),
            ),
            const Spacer(),
            Text(
              '${downloadedModels.length} model${downloadedModels.length > 1 ? 's' : ''} available',
              style: TextStyle(fontSize: 11, color: Colors.green.shade600),
            ),
          ],
        ),
      );
    }

    // Some models missing - show download prompts
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amber.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.download_for_offline,
                color: Colors.amber.shade700,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${widget.engineName} requires model download',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.amber.shade900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...missingModels.map((model) => _buildModelRow(model)),
          if (downloadedModels.isNotEmpty) ...[
            const Divider(height: 16),
            Text(
              'Downloaded:',
              style: TextStyle(
                fontSize: 11,
                color: Colors.green.shade700,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: downloadedModels
                  .map(
                    (m) => Chip(
                      avatar: Icon(
                        Icons.check,
                        size: 14,
                        color: Colors.green.shade700,
                      ),
                      label: Text(
                        m['name'] as String,
                        style: const TextStyle(fontSize: 11),
                      ),
                      visualDensity: VisualDensity.compact,
                      backgroundColor: Colors.green.shade100,
                      side: BorderSide.none,
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildModelRow(Map<String, dynamic> model) {
    final name = model['name'] as String;
    final sizeGb = model['size_gb'] as num?;
    final description = model['description'] as String? ?? '';
    final isDownloading = _downloadingModels.contains(name);
    final downloadStatus = model['download_status'] as String?;
    final downloadError = model['download_error'] as String?;
    final downloadedPath = (model['downloaded_path'] as String?)?.trim();
    final cacheDir = (model['cache_dir'] as String?)?.trim();
    final modelPath = (downloadedPath != null && downloadedPath.isNotEmpty)
        ? downloadedPath
        : ((cacheDir != null && cacheDir.isNotEmpty) ? cacheDir : null);
    final pathLabel = (downloadedPath != null && downloadedPath.isNotEmpty)
        ? 'Path'
        : 'Target';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.amber.shade900,
                  ),
                ),
                if (description.isNotEmpty)
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.amber.shade800,
                    ),
                  ),
                if (sizeGb != null)
                  Text(
                    '${sizeGb.toStringAsFixed(1)} GB',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.amber.shade700,
                      fontFamily: 'monospace',
                    ),
                  ),
                if (downloadError != null)
                  Text(
                    'Error: $downloadError',
                    style: TextStyle(fontSize: 10, color: Colors.red.shade700),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 320,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (isDownloading || downloadStatus == 'downloading')
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  FilledButton.tonalIcon(
                    onPressed: () => _downloadModel(name),
                    icon: const Icon(Icons.download, size: 16),
                    label: const Text('Download'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      textStyle: const TextStyle(fontSize: 11),
                    ),
                  ),
                if (modelPath != null) ...[
                  const SizedBox(height: 4),
                  SelectableText(
                    '$pathLabel: $modelPath',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 10,
                      height: 1.2,
                      color: Colors.amber.shade900,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
