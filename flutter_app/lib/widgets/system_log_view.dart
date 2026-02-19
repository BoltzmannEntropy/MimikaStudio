import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_service.dart';

class SystemLogView extends StatefulWidget {
  final String title;
  final int maxLines;
  final bool autoRefresh;
  final Duration refreshInterval;

  const SystemLogView({
    super.key,
    this.title = 'System Log',
    this.maxLines = 500,
    this.autoRefresh = true,
    this.refreshInterval = const Duration(seconds: 4),
  });

  @override
  State<SystemLogView> createState() => _SystemLogViewState();
}

class _SystemLogViewState extends State<SystemLogView> {
  final ApiService _api = ApiService();
  Timer? _pollTimer;
  bool _isLoading = false;
  bool _isExporting = false;
  List<String> _lines = const <String>[];
  List<String> _sources = const <String>[];
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadLogs();
    if (widget.autoRefresh) {
      _pollTimer = Timer.periodic(widget.refreshInterval, (_) => _loadLogs());
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  String get _joinedLog => _lines.join('\n');

  Future<void> _loadLogs() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      final payload = await _api.getSystemLogs(maxLines: widget.maxLines);
      if (!mounted) return;
      setState(() {
        _lines = List<String>.from(
          payload['lines'] as List<dynamic>? ?? const <String>[],
        );
        _sources = List<String>.from(
          payload['sources'] as List<dynamic>? ?? const <String>[],
        );
        _error = null;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _copyLogs() async {
    final text = _joinedLog;
    if (text.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('System log is empty')));
      }
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copied ${_lines.length} log lines')),
    );
  }

  Future<void> _exportLogs() async {
    if (_isExporting) return;
    setState(() => _isExporting = true);
    try {
      final bundle = await _api.exportSystemLogs(maxLines: 2000);
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
        setState(() => _isExporting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.04),
        border: Border.all(color: Colors.black.withValues(alpha: 0.15)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 6, 6),
            child: Row(
              children: [
                const Icon(Icons.terminal_rounded, size: 16),
                const SizedBox(width: 6),
                Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (_sources.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${_sources.length} source${_sources.length == 1 ? '' : 's'}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ] else
                  const Spacer(),
                IconButton(
                  tooltip: 'Refresh',
                  visualDensity: VisualDensity.compact,
                  onPressed: _loadLogs,
                  icon: const Icon(Icons.refresh, size: 18),
                ),
                IconButton(
                  tooltip: 'Copy logs',
                  visualDensity: VisualDensity.compact,
                  onPressed: _copyLogs,
                  icon: const Icon(Icons.copy_rounded, size: 18),
                ),
                IconButton(
                  tooltip: 'Export logs',
                  visualDensity: VisualDensity.compact,
                  onPressed: _isExporting ? null : _exportLogs,
                  icon: _isExporting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download_rounded, size: 18),
                ),
              ],
            ),
          ),
          if (_isLoading) const LinearProgressIndicator(minHeight: 1),
          Expanded(
            child: Container(
              margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.black.withValues(alpha: 0.12)),
              ),
              child: _error != null
                  ? Align(
                      alignment: Alignment.topLeft,
                      child: Text(
                        _error!,
                        style: const TextStyle(fontSize: 12, color: Colors.red),
                      ),
                    )
                  : _lines.isEmpty
                  ? Text(
                      'No system logs found yet.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                      ),
                    )
                  : SingleChildScrollView(
                      child: SelectableText(
                        _joinedLog,
                        style: const TextStyle(
                          fontSize: 11,
                          height: 1.22,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
