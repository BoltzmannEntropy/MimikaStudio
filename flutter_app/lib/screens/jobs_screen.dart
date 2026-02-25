import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../services/api_service.dart';

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
              final status = (job['status'] as String? ?? 'unknown').toLowerCase();
              final statusColor = _statusColor(status, context);
              final title = (job['title'] as String?) ?? 'Job';
              final engine = (job['engine'] as String?) ?? '-';
              final type = (job['type'] as String?) ?? '-';
              final rawTs = (job['timestamp'] as String?) ?? '';
              final ts = _humanTimestamp(rawTs);
              final elapsedSeconds = _elapsedSecondsFromTimestamp(rawTs);
              final chars = job['chars'];
              final percent = job['percent'];
              final outputPath = (job['output_path'] as String?) ?? '';
              final hasAudio =
                  (job['audio_url'] as String?) != null &&
                  (job['audio_url'] as String).isNotEmpty;
              final isThisPlaying = _playingJobId == (job['id'] as String? ?? '');

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
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '$type • $engine',
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
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      if (hasAudio) ...[
                        const SizedBox(height: 8),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.play_arrow, size: 18),
                              onPressed: (!isThisPlaying || _isPaused)
                                  ? () => _playJobAudio(job)
                                  : null,
                              tooltip: 'Play',
                            ),
                            IconButton(
                              icon: const Icon(Icons.pause, size: 18),
                              onPressed:
                                  (isThisPlaying && !_isPaused) ? _pauseAudio : null,
                              tooltip: 'Pause',
                            ),
                            IconButton(
                              icon: const Icon(Icons.stop, size: 18),
                              onPressed: isThisPlaying ? _stopAudio : null,
                              tooltip: 'Stop',
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
