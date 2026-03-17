import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;

import '../services/api_service.dart';
import '../utils/local_file_actions.dart';
import '../widgets/generation_metrics_dialog.dart';

class JobsScreen extends StatefulWidget {
  const JobsScreen({super.key});

  @override
  State<JobsScreen> createState() => _JobsScreenState();
}

class _JobsScreenState extends State<JobsScreen> {
  final ApiService _api = ApiService();
  final AudioPlayer _audioPlayer = AudioPlayer();
  List<Map<String, dynamic>> _jobs = [];
  bool _isLoading = true;
  String? _error;
  Timer? _pollTimer;
  Timer? _clockTimer;
  StreamSubscription<PlayerState>? _playerSub;
  String? _playingJobId;
  bool _isPaused = false;

  @override
  void initState() {
    super.initState();
    _loadJobs();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _loadJobs());
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _jobs.isEmpty) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _clockTimer?.cancel();
    _playerSub?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _playJobAudio(Map<String, dynamic> job) async {
    final jobId = (job['id'] as String?) ?? '';
    final audioUrl = (job['audio_url'] as String?) ?? '';
    if (jobId.isEmpty || audioUrl.isEmpty) return;

    if (_playingJobId == jobId && _isPaused) {
      setState(() => _isPaused = false);
      await _audioPlayer.play();
      return;
    }

    setState(() {
      _playingJobId = jobId;
      _isPaused = false;
    });

    try {
      await _playerSub?.cancel();
      await _audioPlayer.stop();
      await _audioPlayer.setUrl('${ApiService.baseUrl}$audioUrl');
      await _audioPlayer.play();
      _playerSub = _audioPlayer.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed && mounted) {
          setState(() {
            _playingJobId = null;
            _isPaused = false;
          });
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _playingJobId = null;
        _isPaused = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to play: $e')));
    }
  }

  Future<void> _pauseAudio() async {
    if (_playingJobId == null) return;
    await _audioPlayer.pause();
    setState(() => _isPaused = true);
  }

  Future<void> _stopAudio() async {
    await _playerSub?.cancel();
    _playerSub = null;
    await _audioPlayer.stop();
    setState(() {
      _playingJobId = null;
      _isPaused = false;
    });
  }

  Future<void> _loadJobs() async {
    try {
      final jobs = await _api.getJobs(limit: 400);
      if (!mounted) return;
      setState(() {
        _jobs = jobs;
        _error = null;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted || _jobs.isNotEmpty) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Color _statusColor(String status, BuildContext context) {
    switch (status.toLowerCase()) {
      case 'completed':
        return Colors.green;
      case 'processing':
      case 'started':
        return Theme.of(context).colorScheme.primary;
      case 'failed':
        return Theme.of(context).colorScheme.error;
      case 'cancelled':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  bool _isBusyStatus(String status) {
    switch (status.toLowerCase()) {
      case 'queued':
      case 'processing':
      case 'started':
        return true;
      default:
        return false;
    }
  }

  String _humanTimestamp(String raw) {
    if (raw.isEmpty) return '-';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    final local = parsed.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    final ss = local.second.toString().padLeft(2, '0');
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} $hh:$mm:$ss';
  }

  int? _elapsedSecondsFromTimestamp(String raw) {
    if (raw.isEmpty) return null;
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return null;
    final startUtc = parsed.toUtc();
    final nowUtc = DateTime.now().toUtc();
    final diff = nowUtc.difference(startUtc).inSeconds;
    return diff < 0 ? 0 : diff;
  }

  String _jobText(Map<String, dynamic> job) {
    return (job['text'] as String?)?.trim() ?? '';
  }

  Future<void> _copyJobText(Map<String, dynamic> job) async {
    final text = _jobText(job);
    if (text.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Text is not available for this job.')),
      );
      return;
    }

    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    final truncated = job['text_truncated'] == true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          truncated ? 'Text copied (truncated).' : 'Text copied to clipboard.',
        ),
      ),
    );
  }

  Future<void> _showGenerationMetrics(Map<String, dynamic> job) async {
    final jobId = (job['id'] as String?) ?? '';
    if (jobId.isEmpty) return;
    try {
      final payload = await _api.getJobGenerationMetrics(jobId);
      if (!mounted) return;
      await showGenerationMetricsDialog(
        context,
        title: jobId,
        payload: payload,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Metrics unavailable: $e')));
    }
  }

  Future<void> _openJobExternally(Map<String, dynamic> job) async {
    final filePath = (job['output_path'] as String?)?.trim() ?? '';
    if (filePath.isEmpty) return;
    try {
      await LocalFileActions.openPath(filePath);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to open file: $e')),
      );
    }
  }

  Future<void> _revealJobInFolder(Map<String, dynamic> job) async {
    final filePath = (job['output_path'] as String?)?.trim() ?? '';
    if (filePath.isEmpty) return;
    try {
      await LocalFileActions.revealInFolder(filePath);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to reveal file: $e')),
      );
    }
  }

  Future<void> _downloadJobAudio(Map<String, dynamic> job) async {
    final audioUrl = (job['audio_url'] as String?) ?? '';
    final outputPath = (job['output_path'] as String?) ?? '';
    if (audioUrl.isEmpty) return;

    try {
      final bytes = await _api.downloadAudioBytes(audioUrl);
      final suggestedName = outputPath.isNotEmpty
          ? p.basename(outputPath)
          : 'job-audio.wav';
      final ext = suggestedName.contains('.')
          ? suggestedName.split('.').last
          : 'wav';
      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save audio file',
        fileName: suggestedName,
        type: FileType.custom,
        allowedExtensions: [ext],
      );
      if (savePath == null) return;

      final file = File(savePath);
      await file.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved to $savePath')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to download: $e')),
      );
    }
  }

  Future<void> _deleteJob(Map<String, dynamic> job) async {
    final jobId = (job['id'] as String?) ?? '';
    if (jobId.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Job'),
        content: const Text('Delete this job and its audio file?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      if (_playingJobId == jobId) {
        await _stopAudio();
      }
      await _api.deleteJob(jobId);
      await _loadJobs();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Job deleted')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
      );
    }
    if (_jobs.isEmpty) {
      return const Center(child: Text('No jobs yet'));
    }

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            border: Border(
              bottom: BorderSide(color: Theme.of(context).dividerColor),
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.work_history_rounded),
              const SizedBox(width: 8),
              Text(
                'Jobs (${_jobs.length})',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _loadJobs,
                tooltip: 'Refresh',
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: _jobs.length,
            itemBuilder: (context, index) {
              final job = _jobs[index];
              final status = (job['status'] as String? ?? 'unknown')
                  .toLowerCase();
              final statusColor = _statusColor(status, context);
              final title = (job['title'] as String?) ?? 'Job';
              final engine = (job['engine'] as String?) ?? '-';
              final voice = (job['voice'] as String?) ?? '';
              final type = (job['type'] as String?) ?? '-';
              final rawTs = (job['timestamp'] as String?) ?? '';
              final ts = _humanTimestamp(rawTs);
              final elapsedSeconds = _elapsedSecondsFromTimestamp(rawTs);
              final chars = job['chars'];
              final percent = job['percent'];
              final queuePosition =
                  (job['queue_position'] as num?)?.toInt() ?? 0;
              final outputPath = (job['output_path'] as String?) ?? '';
              final isBusy = _isBusyStatus(status);
              final hasAudio =
                  (job['audio_url'] as String?) != null &&
                  (job['audio_url'] as String).isNotEmpty;
              final hasText = _jobText(job).isNotEmpty;
              final canShowMetrics = status == 'completed' && hasAudio;
              final isThisPlaying =
                  _playingJobId == (job['id'] as String? ?? '');

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isBusy) ...[
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  statusColor,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              status.toUpperCase(),
                              style: TextStyle(
                                color: statusColor,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            icon: const Icon(Icons.insights_rounded, size: 16),
                            onPressed: canShowMetrics
                                ? () => _showGenerationMetrics(job)
                                : null,
                            tooltip: canShowMetrics
                                ? 'Generation metrics'
                                : 'Metrics unavailable',
                            visualDensity: VisualDensity.compact,
                            constraints: const BoxConstraints(
                              minWidth: 28,
                              minHeight: 28,
                            ),
                            padding: EdgeInsets.zero,
                          ),
                          const SizedBox(width: 2),
                          IconButton(
                            icon: const Icon(
                              Icons.content_copy_rounded,
                              size: 16,
                            ),
                            onPressed: hasText ? () => _copyJobText(job) : null,
                            tooltip: hasText
                                ? 'Copy text'
                                : 'Text not available',
                            visualDensity: VisualDensity.compact,
                            constraints: const BoxConstraints(
                              minWidth: 28,
                              minHeight: 28,
                            ),
                            padding: EdgeInsets.zero,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '$type • $engine${voice.isNotEmpty ? ' • $voice' : ''}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'started: $ts${elapsedSeconds != null ? ' • elapsed: ${elapsedSeconds}s' : ''}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (chars != null || percent != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'chars: ${chars ?? '-'}${percent != null ? ' • ${percent.toString()}%' : ''}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      if (queuePosition > 0 && status != 'completed') ...[
                        const SizedBox(height: 2),
                        Text(
                          'queue position: $queuePosition',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      if (status == 'completed' && outputPath.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          outputPath,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      if (hasAudio || status == 'completed') ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 0,
                          runSpacing: 4,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.open_in_new_rounded, size: 18),
                              onPressed: outputPath.isNotEmpty
                                  ? () => _openJobExternally(job)
                                  : null,
                              tooltip: 'Open externally',
                              visualDensity: VisualDensity.compact,
                            ),
                            IconButton(
                              icon: const Icon(Icons.folder_open_rounded, size: 18),
                              onPressed: outputPath.isNotEmpty
                                  ? () => _revealJobInFolder(job)
                                  : null,
                              tooltip: 'Show in folder',
                              visualDensity: VisualDensity.compact,
                            ),
                            IconButton(
                              icon: const Icon(Icons.play_arrow, size: 18),
                              onPressed: hasAudio && (!isThisPlaying || _isPaused)
                                  ? () => _playJobAudio(job)
                                  : null,
                              tooltip: 'Play',
                              visualDensity: VisualDensity.compact,
                            ),
                            IconButton(
                              icon: const Icon(Icons.pause, size: 18),
                              onPressed: hasAudio && isThisPlaying && !_isPaused
                                  ? _pauseAudio
                                  : null,
                              tooltip: 'Pause',
                              visualDensity: VisualDensity.compact,
                            ),
                            IconButton(
                              icon: const Icon(Icons.stop, size: 18),
                              onPressed: hasAudio && isThisPlaying
                                  ? _stopAudio
                                  : null,
                              tooltip: 'Stop',
                              visualDensity: VisualDensity.compact,
                            ),
                            IconButton(
                              icon: const Icon(Icons.download_rounded, size: 18),
                              onPressed: hasAudio
                                  ? () => _downloadJobAudio(job)
                                  : null,
                              tooltip: 'Download',
                              visualDensity: VisualDensity.compact,
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 18),
                              onPressed: () => _deleteJob(job),
                              tooltip: 'Delete',
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
