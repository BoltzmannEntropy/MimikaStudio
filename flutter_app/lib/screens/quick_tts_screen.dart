import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../services/api_service.dart';
import '../widgets/audio_player_widget.dart';
import '../widgets/model_status_banner.dart';

class QuickTtsScreen extends StatefulWidget {
  const QuickTtsScreen({super.key});

  @override
  State<QuickTtsScreen> createState() => _QuickTtsScreenState();
}

class _QuickTtsScreenState extends State<QuickTtsScreen> {
  static const String _defaultKokoroText =
      'Genesis chapter 4, verses 6 and 7: And the Lord said unto Cain, Why art thou wroth? '
      'and why is thy countenance fallen? If thou doest well, shalt thou not be accepted? '
      'and if thou doest not well, sin lieth at the door.';

  final ApiService _api = ApiService();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final TextEditingController _textController = TextEditingController();
  List<Map<String, dynamic>> _voices = [];
  List<Map<String, dynamic>> _voiceSamples = [];
  Map<String, dynamic>? _systemInfo;
  String _selectedVoice = 'bf_emma';
  double _speed = 1.0;
  String _audioModelLabel = 'Kokoro';

  // Smart chunking + merge
  bool _smartChunking = true;
  int _maxCharsPerChunk = 1500;
  int _crossfadeMs = 40;

  bool _isLoading = false;
  bool _isGenerating = false;
  String? _audioUrl;
  String? _error;

  // Audio library state
  List<Map<String, dynamic>> _audioFiles = [];
  bool _isLoadingAudioFiles = false;
  String? _playingAudioId;
  bool _isAudioPaused = false;
  double _libraryPlaybackSpeed = 1.0;
  StreamSubscription<PlayerState>? _playerSubscription;

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadAudioFiles();
  }

  @override
  void dispose() {
    _playerSubscription?.cancel();
    _audioPlayer.dispose();
    _textController.dispose();
    super.dispose();
  }

  Future<void> _loadAudioFiles() async {
    setState(() => _isLoadingAudioFiles = true);
    try {
      final files = await _api.getTtsAudioFiles();
      if (mounted) {
        setState(() {
          _audioFiles = files;
          _isLoadingAudioFiles = false;
        });
      }
    } catch (e) {
      debugPrint('Failed to load audio files: $e');
      if (mounted) {
        setState(() => _isLoadingAudioFiles = false);
      }
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final voicesData = await _api.getKokoroVoices();
      final voiceSamples = await _api.getVoiceSamples();
      final systemInfo = await _api.getSystemInfo();

      if (!mounted) return;
      setState(() {
        _voices = List<Map<String, dynamic>>.from(voicesData['voices']);
        _selectedVoice = voicesData['default'] ?? 'bf_emma';
        _voiceSamples = voiceSamples;
        _systemInfo = systemInfo;
        _isLoading = false;
        if (_textController.text.trim().isEmpty) {
          _textController.text = _defaultKokoroText;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _generateSpeech() async {
    if (_textController.text.isEmpty) return;

    setState(() {
      _isGenerating = true;
      _error = null;
    });

    try {
      final audioUrl = await _api.generateKokoro(
        text: _textController.text,
        voice: _selectedVoice,
        speed: _speed,
        smartChunking: _smartChunking,
        maxCharsPerChunk: _maxCharsPerChunk,
        crossfadeMs: _crossfadeMs,
      );

      if (!mounted) return;
      setState(() {
        _audioUrl = audioUrl;
        _audioModelLabel = 'Kokoro';
        _isGenerating = false;
      });

      await _audioPlayer.setUrl(audioUrl);
      await _audioPlayer.play();

      // Refresh audio library
      _loadAudioFiles();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isGenerating = false;
      });
    }
  }

  Future<void> _playVoiceSample(Map<String, dynamic> sample) async {
    final audioUrl = _api.getSampleAudioUrl(sample['audio_url'] as String);
    setState(() => _audioUrl = audioUrl);
    await _audioPlayer.setUrl(audioUrl);
    await _audioPlayer.play();
  }

  Widget _buildInfoChip(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: Colors.grey.shade600),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Row(
      children: [
        // Sidebar with audio library
        _buildSidebar(),
        // Main content
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Model Header with System Info
                Card(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.volume_up,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSecondaryContainer,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Kokoro TTS',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSecondaryContainer,
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.secondary,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                'British English',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (_systemInfo != null) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 12,
                            runSpacing: 4,
                            children: [
                              _buildInfoChip(
                                Icons.memory,
                                _systemInfo!['device'] ?? 'Unknown',
                              ),
                              _buildInfoChip(
                                Icons.code,
                                'Python ${_systemInfo!['python_version'] ?? '?'}',
                              ),
                              _buildInfoChip(
                                Icons.library_books,
                                _systemInfo!['models']?['kokoro']?['model'] ??
                                    'Kokoro',
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const ModelStatusBanner(
                  requiredModels: ['Kokoro'],
                  engineName: 'Kokoro',
                  themeColor: Colors.indigo,
                ),

                // Voice Samples Section
                if (_voiceSamples.isNotEmpty) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.record_voice_over,
                                color: Theme.of(context).colorScheme.tertiary,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'Voice Samples',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade100,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  'Instant Play',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.green,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ..._voiceSamples.map((sample) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: InkWell(
                                onTap: () => _playVoiceSample(sample),
                                borderRadius: BorderRadius.circular(6),
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .outline
                                          .withValues(alpha: 0.2),
                                    ),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.tertiaryContainer,
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        child: Text(
                                          sample['voice_name'] as String,
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onTertiaryContainer,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          sample['text'] as String,
                                          style: const TextStyle(fontSize: 12),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const Icon(
                                        Icons.play_circle_outline,
                                        size: 20,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Smart Chunking',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                            'Enable smart chunking',
                            style: TextStyle(fontSize: 12),
                          ),
                          value: _smartChunking,
                          onChanged: (value) =>
                              setState(() => _smartChunking = value),
                        ),
                        Row(
                          children: [
                            const Text(
                              'Max chars:',
                              style: TextStyle(fontSize: 12),
                            ),
                            Expanded(
                              child: Slider(
                                value: _maxCharsPerChunk.toDouble(),
                                min: 400,
                                max: 4000,
                                divisions: 36,
                                label: _maxCharsPerChunk.toString(),
                                onChanged: _smartChunking
                                    ? (v) => setState(
                                        () => _maxCharsPerChunk = v.round(),
                                      )
                                    : null,
                              ),
                            ),
                            Text(_maxCharsPerChunk.toString()),
                          ],
                        ),
                        Row(
                          children: [
                            const Text(
                              'Crossfade:',
                              style: TextStyle(fontSize: 12),
                            ),
                            Expanded(
                              child: Slider(
                                value: _crossfadeMs.toDouble(),
                                min: 0,
                                max: 200,
                                divisions: 20,
                                label: '${_crossfadeMs}ms',
                                onChanged: _smartChunking
                                    ? (v) => setState(
                                        () => _crossfadeMs = v.round(),
                                      )
                                    : null,
                              ),
                            ),
                            Text('${_crossfadeMs}ms'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Audio Player
                if (_audioUrl != null) ...[
                  AudioPlayerWidget(
                    player: _audioPlayer,
                    audioUrl: _audioUrl,
                    modelName: _audioModelLabel,
                  ),
                  const SizedBox(height: 16),
                ],

                // Error
                if (_error != null) ...[
                  Card(
                    color: Colors.red.shade100,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                ...[
                  // British Voices Selection
                  const Text(
                    'British Voices:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _voices.map((voice) {
                      final code = voice['code'] as String;
                      final name = voice['name'] as String;
                      final gender = voice['gender'] as String;
                      final grade = voice['grade'] as String;
                      final isSelected = code == _selectedVoice;

                      return ChoiceChip(
                        label: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              gender == 'female' ? Icons.female : Icons.male,
                              size: 16,
                            ),
                            const SizedBox(width: 4),
                            Text(name),
                            const SizedBox(width: 4),
                            Text(
                              '($grade)',
                              style: TextStyle(
                                fontSize: 10,
                                color: isSelected ? null : Colors.grey,
                              ),
                            ),
                          ],
                        ),
                        selected: isSelected,
                        onSelected: (selected) {
                          if (selected) setState(() => _selectedVoice = code);
                        },
                        avatar: voice['is_default'] == true
                            ? const Icon(Icons.star, size: 16)
                            : null,
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),

                  // Speed Slider
                  Row(
                    children: [
                      const Icon(Icons.speed, size: 20),
                      const SizedBox(width: 8),
                      const Text('Speed:'),
                      Expanded(
                        child: Slider(
                          value: _speed,
                          min: 0.5,
                          max: 2.0,
                          divisions: 150,
                          label: '${_speed.toStringAsFixed(2)}x',
                          onChanged: (value) => setState(() => _speed = value),
                        ),
                      ),
                      Text('${_speed.toStringAsFixed(2)}x'),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],

                // Main Text Input
                TextField(
                  controller: _textController,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    hintText: 'Enter text for Kokoro TTS...',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),

                // Action button: Generate Speech
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _isGenerating || _textController.text.isEmpty
                            ? null
                            : _generateSpeech,
                        icon: _isGenerating
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.play_arrow),
                        label: Text(
                          _isGenerating ? 'Generating...' : 'Generate Speech',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        border: Border(
          right: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              border: Border(
                bottom: BorderSide(color: Theme.of(context).dividerColor),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.library_music, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Audio Library',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 18),
                  onPressed: _loadAudioFiles,
                  tooltip: 'Refresh',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          // Playback speed control
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              border: Border(
                bottom: BorderSide(color: Theme.of(context).dividerColor),
              ),
            ),
            child: Row(
              children: [
                const Text('Speed:', style: TextStyle(fontSize: 11)),
                Expanded(
                  child: Slider(
                    value: _libraryPlaybackSpeed,
                    min: 0.5,
                    max: 2.0,
                    divisions: 150,
                    label: '${_libraryPlaybackSpeed.toStringAsFixed(2)}x',
                    onChanged: _setLibraryPlaybackSpeed,
                  ),
                ),
                Text(
                  '${_libraryPlaybackSpeed.toStringAsFixed(2)}x',
                  style: const TextStyle(fontSize: 10),
                ),
              ],
            ),
          ),
          // Audio files list
          Expanded(
            child: _isLoadingAudioFiles
                ? const Center(child: CircularProgressIndicator())
                : _audioFiles.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'No audio files yet.\nGenerate speech to see it here.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: _audioFiles.length,
                    itemBuilder: (context, index) {
                      final file = _audioFiles[index];
                      return _buildAudioFileItem(file);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildAudioFileItem(Map<String, dynamic> file) {
    final fileId = file['id'] as String;
    final filename = file['filename'] as String;
    final engine = (file['engine'] as String?) ?? 'tts';
    final label =
        (file['label'] as String?) ?? (file['voice'] as String?) ?? 'Unknown';
    final duration = file['duration_seconds'] as num;
    final sizeMb = file['size_mb'] as num;
    final isThisPlaying = _playingAudioId == fileId;

    // Format duration
    final mins = (duration / 60).floor();
    final secs = (duration % 60).round();
    final durationStr = mins > 0 ? '${mins}m ${secs}s' : '${secs}s';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isThisPlaying
            ? Theme.of(context).colorScheme.primaryContainer
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            leading: Icon(
              Icons.audiotrack,
              color: isThisPlaying
                  ? Theme.of(context).colorScheme.primary
                  : null,
              size: 20,
            ),
            title: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isThisPlaying ? FontWeight.bold : FontWeight.w500,
              ),
            ),
            subtitle: Text(
              '${engine.toUpperCase()} • $durationStr • ${sizeMb.toStringAsFixed(1)} MB',
              style: const TextStyle(fontSize: 10),
            ),
            trailing: SizedBox(
              width: 72,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    icon: const Icon(Icons.download_rounded, size: 16),
                    onPressed: () => _downloadAudioFile(file),
                    tooltip: 'Download',
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 16),
                    onPressed: () => _deleteAudioFile(filename),
                    tooltip: 'Delete',
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
          ),
          // Playback controls
          Padding(
            padding: const EdgeInsets.only(left: 12, right: 12, bottom: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.play_arrow, size: 20),
                  onPressed: (!isThisPlaying || _isAudioPaused)
                      ? () => _playAudioFile(file)
                      : null,
                  tooltip: 'Play',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32),
                ),
                IconButton(
                  icon: const Icon(Icons.pause, size: 20),
                  onPressed: (isThisPlaying && !_isAudioPaused)
                      ? _pauseAudioPlayback
                      : null,
                  tooltip: 'Pause',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32),
                ),
                IconButton(
                  icon: const Icon(Icons.stop, size: 20),
                  onPressed: isThisPlaying ? _stopAudioPlayback : null,
                  tooltip: 'Stop',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _playAudioFile(Map<String, dynamic> file) async {
    final fileId = file['id'] as String;
    final audioUrl = file['audio_url'] as String;

    // If same file and paused, just resume
    if (_playingAudioId == fileId && _isAudioPaused) {
      setState(() => _isAudioPaused = false);
      await _audioPlayer.play();
      return;
    }

    // Update UI immediately
    setState(() {
      _playingAudioId = fileId;
      _isAudioPaused = false;
    });

    await Future.delayed(Duration.zero);
    if (!mounted) return;

    try {
      await _playerSubscription?.cancel();
      await _audioPlayer.stop();

      await _audioPlayer.setUrl('${ApiService.baseUrl}$audioUrl');
      await _audioPlayer.setSpeed(_libraryPlaybackSpeed);
      await _audioPlayer.play();

      _playerSubscription = _audioPlayer.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          if (mounted) {
            setState(() {
              _playingAudioId = null;
              _isAudioPaused = false;
            });
          }
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _playingAudioId = null;
          _isAudioPaused = false;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to play: $e')));
      }
    }
  }

  Future<void> _pauseAudioPlayback() async {
    if (_playingAudioId != null) {
      await _audioPlayer.pause();
      setState(() => _isAudioPaused = true);
    }
  }

  Future<void> _stopAudioPlayback() async {
    await _playerSubscription?.cancel();
    _playerSubscription = null;
    await _audioPlayer.stop();
    setState(() {
      _playingAudioId = null;
      _isAudioPaused = false;
    });
  }

  Future<void> _setLibraryPlaybackSpeed(double speed) async {
    setState(() => _libraryPlaybackSpeed = speed);
    if (_playingAudioId != null) {
      await _audioPlayer.setSpeed(speed);
    }
  }

  Future<void> _deleteAudioFile(String filename) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Audio'),
        content: const Text('Delete this audio file?'),
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

    if (confirm == true) {
      try {
        // Stop if currently playing
        if (_playingAudioId != null) {
          final currentFile = _audioFiles.firstWhere(
            (f) => f['id'] == _playingAudioId,
            orElse: () => {},
          );
          if (currentFile['filename'] == filename) {
            await _stopAudioPlayback();
          }
        }

        await _api.deleteTtsAudio(filename);
        _loadAudioFiles();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
        }
      }
    }
  }

  Future<void> _downloadAudioFile(Map<String, dynamic> file) async {
    final audioUrl = file['audio_url'] as String?;
    final filename = file['filename'] as String? ?? 'kokoro-audio.wav';
    if (audioUrl == null || audioUrl.isEmpty) return;

    try {
      final bytes = await _api.downloadAudioBytes(audioUrl);
      final ext = filename.contains('.') ? filename.split('.').last : 'wav';
      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save audio file',
        fileName: filename,
        type: FileType.custom,
        allowedExtensions: [ext],
      );
      if (savePath == null) return;

      final destination = File(savePath);
      await destination.create(recursive: true);
      await destination.writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved to $savePath')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to download: $e')));
    }
  }
}
