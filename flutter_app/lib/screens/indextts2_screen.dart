import 'dart:async';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:file_picker/file_picker.dart';
import '../services/api_service.dart';
import '../services/settings_service.dart';
import '../widgets/audio_player_widget.dart';

class IndexTTS2Screen extends StatefulWidget {
  const IndexTTS2Screen({super.key});

  @override
  State<IndexTTS2Screen> createState() => _IndexTTS2ScreenState();
}

class _IndexTTS2ScreenState extends State<IndexTTS2Screen> {
  final ApiService _api = ApiService();
  final SettingsService _settingsService = SettingsService();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final TextEditingController _textController = TextEditingController();

  // IndexTTS-2 state
  List<Map<String, dynamic>> _voices = [];
  String? _selectedVoice;
  Map<String, dynamic>? _systemInfo;
  double _speed = 1.0;
  bool _unloadAfter = false;

  bool _isLoading = false;
  bool _isGenerating = false;
  bool _isUploading = false;
  String? _audioUrl;
  String? _audioFilename;
  String _outputFolder = 'backend/outputs';
  String? _error;

  // Audio library state
  List<Map<String, dynamic>> _audioFiles = [];
  bool _isLoadingAudioFiles = false;
  String? _playingAudioId;
  bool _isAudioPaused = false;
  String? _previewVoiceName;
  bool _isPreviewPaused = false;
  double _libraryPlaybackSpeed = 1.0;
  StreamSubscription<PlayerState>? _playerSubscription;

  @override
  void initState() {
    super.initState();
    _textController.text =
        'For many, the experience of Vietnam had a radicalizing effect, leading them to conclude that US military intervention was not a well-intentioned mistake by policymakers, but part of a consistent effort to preserve American political, economic, and military domination globally, largely in service of corporate profits.';
    _loadOutputFolder();
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
      final files = await _api.getVoiceCloneAudioFiles();
      final indexFiles = files
          .where((f) => (f['engine'] as String?) == 'indextts2')
          .toList();
      if (mounted) {
        setState(() {
          _audioFiles = indexFiles;
          _isLoadingAudioFiles = false;
        });
      }
    } catch (e) {
      debugPrint('Failed to load audio files: $e');
      if (mounted) setState(() => _isLoadingAudioFiles = false);
    }
  }

  Future<void> _loadOutputFolder() async {
    try {
      final folder = await _settingsService.getOutputFolder();
      if (!mounted) return;
      setState(() => _outputFolder = folder);
    } catch (_) {
      // Keep fallback display path if settings API is unavailable.
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      Map<String, dynamic>? systemInfo;
      try {
        systemInfo = await _api.getSystemInfo();
      } catch (e) {
        debugPrint('System info not available: $e');
      }

      List<Map<String, dynamic>> voices = [];
      try {
        final voiceResponse = await _api.getIndexTTS2Voices();
        voices = List<Map<String, dynamic>>.from(
          voiceResponse['voices'] as List<dynamic>? ?? [],
        );
      } catch (e) {
        debugPrint('IndexTTS-2 voices not available: $e');
      }

      setState(() {
        _systemInfo = systemInfo;
        _voices = voices;
        if (voices.isNotEmpty) {
          _selectedVoice = voices[0]['name'];
        }
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _generate() async {
    if (_textController.text.isEmpty || _selectedVoice == null) return;

    setState(() {
      _isGenerating = true;
      _error = null;
    });

    try {
      final audioUrl = await _api.generateIndexTTS2(
        text: _textController.text,
        voiceName: _selectedVoice!,
        speed: _speed,
        unloadAfter: _unloadAfter,
      );

      final uri = Uri.parse(audioUrl);
      final filename = uri.pathSegments.isNotEmpty
          ? uri.pathSegments.last
          : null;

      setState(() {
        _audioUrl = audioUrl;
        _audioFilename = filename;
        _isGenerating = false;
        _playingAudioId = null;
        _isAudioPaused = false;
        _previewVoiceName = null;
        _isPreviewPaused = false;
      });

      await _playerSubscription?.cancel();
      _playerSubscription = null;
      await _audioPlayer.setUrl(audioUrl);
      await _audioPlayer.play();
      _loadAudioFiles();
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isGenerating = false;
      });
    }
  }

  Future<void> _uploadVoice() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      allowMultiple: false,
      withData: true,
    );

    if (result != null && result.files.single.bytes != null) {
      final fileBytes = result.files.single.bytes!;
      final fileName = result.files.single.name;
      final dialogResult = await _showUploadDialog();
      if (dialogResult != null) {
        setState(() => _isUploading = true);
        try {
          await _api.uploadIndexTTS2Voice(
            dialogResult['name']!,
            fileBytes,
            fileName,
            dialogResult['transcript'] ?? '',
          );
          await _loadData();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Voice "${dialogResult['name']}" uploaded successfully',
                ),
              ),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('Failed to upload: $e')));
          }
        } finally {
          setState(() => _isUploading = false);
        }
      }
    }
  }

  Future<Map<String, String>?> _showUploadDialog() async {
    final nameController = TextEditingController();
    final transcriptController = TextEditingController();

    return showDialog<Map<String, String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('IndexTTS-2 Voice Sample'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Voice Name',
                hintText: 'e.g., MyVoice',
              ),
              autofocus: true,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: transcriptController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Transcript (optional)',
                hintText: 'Reference audio transcript (optional)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (nameController.text.isNotEmpty) {
                Navigator.pop(context, {
                  'name': nameController.text,
                  'transcript': transcriptController.text,
                });
              }
            },
            child: const Text('Upload'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteVoice(String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Voice'),
        content: Text('Delete voice "$name"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await _api.deleteIndexTTS2Voice(name);
        await _loadData();
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Voice "$name" deleted')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
        }
      }
    }
  }

  Future<void> _editVoice(String name, String currentTranscript) async {
    final transcriptController = TextEditingController(text: currentTranscript);
    final nameController = TextEditingController(text: name);

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Voice'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Voice Name'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: transcriptController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Transcript (optional)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (nameController.text.isNotEmpty) {
                Navigator.pop(context, {
                  'name': nameController.text,
                  'transcript': transcriptController.text,
                });
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != null) {
      try {
        await _api.updateIndexTTS2VoiceName(
          name,
          newName: result['name'] != name ? result['name'] : null,
          transcript: result['transcript'],
        );
        await _loadData();
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Voice updated')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Failed to update: $e')));
        }
      }
    }
  }

  Future<void> _previewVoice(Map<String, dynamic> voice) async {
    final name = voice['name'] as String? ?? '';
    if (name.isEmpty) return;

    if (_previewVoiceName == name && _isPreviewPaused) {
      setState(() => _isPreviewPaused = false);
      await _audioPlayer.play();
      return;
    }

    try {
      final audioUrl = voice['audio_url'] as String?;
      if (audioUrl == null || audioUrl.isEmpty) {
        throw Exception('Preview audio not available');
      }
      final playUrl = audioUrl.startsWith('http')
          ? audioUrl
          : '${ApiService.baseUrl}$audioUrl';

      await _playerSubscription?.cancel();
      _playerSubscription = null;
      await _audioPlayer.stop();

      if (!mounted) return;
      setState(() {
        _playingAudioId = null;
        _isAudioPaused = false;
        _previewVoiceName = name;
        _isPreviewPaused = false;
      });

      await _audioPlayer.setUrl(playUrl);
      await _audioPlayer.setSpeed(1.0);
      await _audioPlayer.play();

      _playerSubscription = _audioPlayer.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed ||
            state.processingState == ProcessingState.idle) {
          if (mounted) {
            setState(() {
              _previewVoiceName = null;
              _isPreviewPaused = false;
            });
          }
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Preview failed: $e')));
      }
    }
  }

  Future<void> _pausePreview() async {
    if (_previewVoiceName != null && !_isPreviewPaused) {
      await _audioPlayer.pause();
      setState(() => _isPreviewPaused = true);
    }
  }

  Future<void> _stopPreview() async {
    await _playerSubscription?.cancel();
    _playerSubscription = null;
    await _audioPlayer.stop();
    if (mounted) {
      setState(() {
        _previewVoiceName = null;
        _isPreviewPaused = false;
      });
    }
  }

  Future<void> _playAudioFile(Map<String, dynamic> file) async {
    final fileId = file['id'] as String;
    final audioUrl = file['audio_url'] as String;

    if (_playingAudioId == fileId && _isAudioPaused) {
      setState(() => _isAudioPaused = false);
      await _audioPlayer.play();
      return;
    }

    setState(() {
      _playingAudioId = fileId;
      _isAudioPaused = false;
      _previewVoiceName = null;
      _isPreviewPaused = false;
    });

    try {
      await _playerSubscription?.cancel();
      await _audioPlayer.stop();
      await _audioPlayer.setUrl('${ApiService.baseUrl}$audioUrl');
      await _audioPlayer.setSpeed(_libraryPlaybackSpeed);
      await _audioPlayer.play();

      _playerSubscription = _audioPlayer.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed ||
            state.processingState == ProcessingState.idle) {
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
        if (_playingAudioId != null) {
          final currentFile = _audioFiles.firstWhere(
            (f) => f['id'] == _playingAudioId,
            orElse: () => {},
          );
          if (currentFile['filename'] == filename) {
            await _stopAudioPlayback();
          }
        }
        await _api.deleteVoiceCloneAudio(filename);
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
        _buildSidebar(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(),
                const SizedBox(height: 8),
                Card(
                  color: Colors.amber.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          color: Colors.orange.shade700,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'IndexTTS and Qwen3-TTS have a transformers version conflict. '
                            'A compatibility shim is applied at runtime, but some edge cases may not work.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.orange.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _buildVoiceSection(),
                const SizedBox(height: 16),
                TextField(
                  controller: _textController,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Text to speak',
                    hintText: 'Enter text to convert to speech...',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
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
                const SizedBox(height: 8),
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Unload model after generation',
                    style: TextStyle(fontSize: 12),
                  ),
                  value: _unloadAfter,
                  onChanged: (v) => setState(() => _unloadAfter = v ?? false),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed:
                      (_isGenerating ||
                          _selectedVoice == null ||
                          _textController.text.isEmpty)
                      ? null
                      : _generate,
                  icon: _isGenerating
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome),
                  label: Text(
                    _isGenerating ? 'Generating...' : 'Generate Speech',
                  ),
                ),
                const SizedBox(height: 16),
                if (_error != null)
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
                if (_audioUrl != null) ...[
                  if (_audioFilename != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Icon(
                            Icons.folder_open,
                            size: 16,
                            color: Colors.grey.shade600,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Output: $_outputFolder/$_audioFilename',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                                fontFamily: 'monospace',
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  AudioPlayerWidget(
                    player: _audioPlayer,
                    audioUrl: _audioUrl,
                    modelName: 'IndexTTS-2',
                    filename: _audioFilename,
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Card(
      color: Colors.deepPurple.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome, color: Colors.deepPurple.shade700),
                const SizedBox(width: 8),
                Text(
                  'IndexTTS-2',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.deepPurple.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'High-quality voice cloning from a reference audio sample. Upload a WAV file and enter text to generate speech in the cloned voice.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
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
                  _buildInfoChip(Icons.graphic_eq, 'SR 24000'),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildVoiceSection() {
    final defaults =
        _voices
            .where((voice) => (voice['source'] as String?) == 'default')
            .toList()
          ..sort(
            (a, b) => (a['name'] as String).compareTo(b['name'] as String),
          );
    final users =
        _voices
            .where((voice) => (voice['source'] as String?) != 'default')
            .toList()
          ..sort(
            (a, b) => (a['name'] as String).compareTo(b['name'] as String),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Voice Samples:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${_voices.length} voices',
                style: TextStyle(fontSize: 10, color: Colors.grey.shade700),
              ),
            ),
            const Spacer(),
            FilledButton.tonalIcon(
              onPressed: _isUploading ? null : _uploadVoice,
              icon: _isUploading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.upload),
              label: Text(
                _isUploading ? 'Uploading...' : 'Upload Voice (WAV only)',
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_voices.isEmpty)
          Card(
            color: Colors.deepPurple.shade50,
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                children: [
                  Icon(Icons.mic, size: 48, color: Colors.deepPurple),
                  SizedBox(height: 8),
                  Text(
                    'No voice samples yet',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Upload a WAV clip to clone a voice with IndexTTS-2',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          )
        else ...[
          if (defaults.isNotEmpty) ...[
            const Text(
              'Default Voices:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _buildVoiceList(defaults, showDefaultBadge: true),
            const SizedBox(height: 12),
          ],
          if (users.isNotEmpty) ...[
            const Text(
              'Your Voices:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _buildVoiceList(users, allowEdit: true),
          ] else ...[
            Card(
              color: Colors.deepPurple.shade50,
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'No user voices yet. Upload a sample to add your own voice.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildVoiceList(
    List<Map<String, dynamic>> voices, {
    bool allowEdit = false,
    bool showDefaultBadge = false,
  }) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: voices.length,
      itemBuilder: (context, index) {
        final voice = voices[index];
        final name = voice['name'] as String;
        final transcript = voice['transcript'] as String? ?? '';
        final isSelected = name == _selectedVoice;
        final isPreviewing = _previewVoiceName == name;

        return Card(
          color: isSelected
              ? Theme.of(context).colorScheme.primaryContainer
              : null,
          child: ListTile(
            leading: Radio<String>(
              value: name,
              groupValue: _selectedVoice,
              onChanged: (value) => setState(() => _selectedVoice = value),
            ),
            title: Row(
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                if (showDefaultBadge) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'DEFAULT',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            subtitle: transcript.isNotEmpty
                ? Text(
                    transcript.length > 50
                        ? '${transcript.substring(0, 50)}...'
                        : transcript,
                    style: const TextStyle(fontSize: 12),
                  )
                : const Text(
                    'No transcript',
                    style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                  ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.play_arrow),
                  onPressed: (!isPreviewing || _isPreviewPaused)
                      ? () => _previewVoice(voice)
                      : null,
                  tooltip: 'Play',
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(minWidth: 32),
                ),
                IconButton(
                  icon: const Icon(Icons.pause),
                  onPressed: (isPreviewing && !_isPreviewPaused)
                      ? _pausePreview
                      : null,
                  tooltip: 'Pause',
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(minWidth: 32),
                ),
                IconButton(
                  icon: const Icon(Icons.stop),
                  onPressed: isPreviewing ? _stopPreview : null,
                  tooltip: 'Stop',
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(minWidth: 32),
                ),
                if (allowEdit) ...[
                  IconButton(
                    icon: const Icon(Icons.edit, size: 20),
                    onPressed: () => _editVoice(name, transcript),
                    tooltip: 'Edit',
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, size: 20, color: Colors.red),
                    onPressed: () => _deleteVoice(name),
                    tooltip: 'Delete',
                  ),
                ],
              ],
            ),
            onTap: () => setState(() => _selectedVoice = name),
          ),
        );
      },
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
          Expanded(
            child: _isLoadingAudioFiles
                ? const Center(child: CircularProgressIndicator())
                : _audioFiles.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'No IndexTTS-2 audio files yet.\nGenerate speech to see it here.',
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
                    itemBuilder: (context, index) =>
                        _buildAudioFileItem(_audioFiles[index]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildAudioFileItem(Map<String, dynamic> file) {
    final fileId = file['id'] as String;
    final filename = file['filename'] as String;
    final label = (file['label'] as String?) ?? 'IndexTTS-2 Clone';
    final duration = (file['duration_seconds'] as num?) ?? 0;
    final sizeMb = (file['size_mb'] as num?) ?? 0;
    final isThisPlaying = _playingAudioId == fileId;

    final mins = (duration / 60).floor();
    final secs = (duration % 60).round();
    final durationStr = mins > 0 ? '${mins}m ${secs}s' : '${secs}s';
    final meta = [
      durationStr,
      '${sizeMb.toStringAsFixed(1)} MB',
    ].where((part) => part.isNotEmpty).join(' \u2022 ');

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
            subtitle: Text(meta, style: const TextStyle(fontSize: 10)),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, size: 16),
              onPressed: () => _deleteAudioFile(filename),
              tooltip: 'Delete',
              visualDensity: VisualDensity.compact,
            ),
          ),
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
}
