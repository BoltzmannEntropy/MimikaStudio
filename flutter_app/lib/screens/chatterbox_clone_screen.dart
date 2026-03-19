import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:file_picker/file_picker.dart';
import '../services/api_service.dart';
import '../services/settings_service.dart';
import '../utils/local_file_actions.dart';
import '../widgets/audio_player_widget.dart';
import '../widgets/generation_metrics_dialog.dart';
import '../widgets/model_status_banner.dart';

class ChatterboxLanguageOption {
  final String code;
  final String name;
  final String flag;
  final Color color;

  const ChatterboxLanguageOption(this.code, this.name, this.flag, this.color);
}

const Map<String, ChatterboxLanguageOption> kChatterboxLanguageOptions = {
  'en': ChatterboxLanguageOption(
    'en',
    'English',
    '\u{1F1FA}\u{1F1F8}',
    Color(0xFF2196F3),
  ),
  'zh': ChatterboxLanguageOption(
    'zh',
    'Chinese',
    '\u{1F1E8}\u{1F1F3}',
    Color(0xFFE91E63),
  ),
  'ja': ChatterboxLanguageOption(
    'ja',
    'Japanese',
    '\u{1F1EF}\u{1F1F5}',
    Color(0xFF9C27B0),
  ),
  'ko': ChatterboxLanguageOption(
    'ko',
    'Korean',
    '\u{1F1F0}\u{1F1F7}',
    Color(0xFFFF5722),
  ),
  'de': ChatterboxLanguageOption(
    'de',
    'German',
    '\u{1F1E9}\u{1F1EA}',
    Color(0xFF795548),
  ),
  'fr': ChatterboxLanguageOption(
    'fr',
    'French',
    '\u{1F1EB}\u{1F1F7}',
    Color(0xFF3F51B5),
  ),
  'ru': ChatterboxLanguageOption(
    'ru',
    'Russian',
    '\u{1F1F7}\u{1F1FA}',
    Color(0xFF9C27B0),
  ),
  'pt': ChatterboxLanguageOption(
    'pt',
    'Portuguese',
    '\u{1F1F5}\u{1F1F9}',
    Color(0xFF4CAF50),
  ),
  'es': ChatterboxLanguageOption(
    'es',
    'Spanish',
    '\u{1F1EA}\u{1F1F8}',
    Color(0xFFF57C00),
  ),
  'it': ChatterboxLanguageOption(
    'it',
    'Italian',
    '\u{1F1EE}\u{1F1F9}',
    Color(0xFF009688),
  ),
  'he': ChatterboxLanguageOption(
    'he',
    'Hebrew',
    '\u{1F1EE}\u{1F1F1}',
    Color(0xFF6A1B9A),
  ),
  'ar': ChatterboxLanguageOption(
    'ar',
    'Arabic',
    '\u{1F1F8}\u{1F1E6}',
    Color(0xFF8E24AA),
  ),
  'da': ChatterboxLanguageOption(
    'da',
    'Danish',
    '\u{1F1E9}\u{1F1F0}',
    Color(0xFF546E7A),
  ),
  'el': ChatterboxLanguageOption(
    'el',
    'Greek',
    '\u{1F1EC}\u{1F1F7}',
    Color(0xFF3949AB),
  ),
  'fi': ChatterboxLanguageOption(
    'fi',
    'Finnish',
    '\u{1F1EB}\u{1F1EE}',
    Color(0xFF5C6BC0),
  ),
  'hi': ChatterboxLanguageOption(
    'hi',
    'Hindi',
    '\u{1F1EE}\u{1F1F3}',
    Color(0xFFEF6C00),
  ),
  'ms': ChatterboxLanguageOption(
    'ms',
    'Malay',
    '\u{1F1F2}\u{1F1FE}',
    Color(0xFF00897B),
  ),
  'nl': ChatterboxLanguageOption(
    'nl',
    'Dutch',
    '\u{1F1F3}\u{1F1F1}',
    Color(0xFF00ACC1),
  ),
  'no': ChatterboxLanguageOption(
    'no',
    'Norwegian',
    '\u{1F1F3}\u{1F1F4}',
    Color(0xFF1E88E5),
  ),
  'pl': ChatterboxLanguageOption(
    'pl',
    'Polish',
    '\u{1F1F5}\u{1F1F1}',
    Color(0xFFE53935),
  ),
};

class ChatterboxCloneScreen extends StatefulWidget {
  const ChatterboxCloneScreen({super.key});

  @override
  State<ChatterboxCloneScreen> createState() => _ChatterboxCloneScreenState();
}

class _ChatterboxCloneScreenState extends State<ChatterboxCloneScreen> {
  static const String _defaultChatterboxText =
      'Genesis chapter 5, verses 1 through 3: This is the book of the generations of Adam. '
      'In the day that God created man, in the likeness of God made he him; male and female '
      'created he them. And Adam lived an hundred and thirty years, and begat a son.';

  final ApiService _api = ApiService();
  final SettingsService _settingsService = SettingsService();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final TextEditingController _textController = TextEditingController();

  // Chatterbox state
  List<Map<String, dynamic>> _chatterboxVoices = [];
  List<String> _chatterboxLanguages = [];
  List<Map<String, dynamic>> _pregeneratedSamples = [];
  String? _selectedChatterboxVoice;
  String _selectedChatterboxLanguage = 'en';
  Map<String, dynamic>? _chatterboxInfo;
  Map<String, dynamic>? _systemInfo;
  double _speed = 1.0;

  // Advanced parameters
  bool _showAdvanced = false;
  double _chatterboxTemperature = 0.8;
  double _chatterboxCfgWeight = 1.0;
  int _chatterboxSeed = -1;
  bool _unloadAfter = false;

  bool _isLoading = false;
  String? _audioUrl;
  String? _audioFilename;
  String _outputFolder = 'backend/outputs';
  String? _error;

  // Audio library state
  List<Map<String, dynamic>> _audioFiles = [];
  final Map<String, Map<String, dynamic>> _pendingAudioFiles = {};
  bool _isLoadingAudioFiles = false;
  String? _playingAudioId;
  bool _isAudioPaused = false;
  String? _previewVoiceName;
  bool _isPreviewPaused = false;
  double _libraryPlaybackSpeed = 1.0;
  StreamSubscription<PlayerState>? _playerSubscription;
  bool _isSidebarCollapsed = false;
  bool _isDefaultVoicesCollapsed = false;
  Map<String, dynamic>? _dictaStatus;
  bool _isDictaDownloading = false;
  Timer? _dictaPollTimer;
  TabController? _tabController;
  int _lastTabIndex = -1;

  @override
  void initState() {
    super.initState();
    _textController.text = _defaultChatterboxText;
    _loadOutputFolder();
    _loadData();
    _loadDictaStatus();
    _dictaPollTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _loadDictaStatus(),
    );
    _loadAudioFiles();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = DefaultTabController.maybeOf(context);
    if (controller == null) {
      _tabController?.animation?.removeListener(_onTabChanged);
      _tabController = null;
      _lastTabIndex = -1;
      return;
    }
    if (_tabController == controller) {
      return;
    }
    _tabController?.animation?.removeListener(_onTabChanged);
    _tabController = controller;
    _lastTabIndex = controller.index;
    _tabController?.animation?.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    final controller = _tabController;
    if (controller == null) return;
    final index = controller.index;
    if (index == _lastTabIndex) return;
    _lastTabIndex = index;
    if (index == 4) {
      unawaited(
        _refreshChatterboxVoices(preferredName: _selectedChatterboxVoice),
      );
    }
  }

  @override
  void dispose() {
    _playerSubscription?.cancel();
    _dictaPollTimer?.cancel();
    _tabController?.animation?.removeListener(_onTabChanged);
    _audioPlayer.dispose();
    _textController.dispose();
    super.dispose();
  }

  Future<void> _loadAudioFiles() async {
    setState(() => _isLoadingAudioFiles = true);
    try {
      final files = await _api.getVoiceCloneAudioFiles();
      final chatterboxFiles = files
          .where((f) => (f['engine'] as String?) == 'chatterbox')
          .toList();
      if (mounted) {
        setState(() {
          _audioFiles = _mergeAudioFiles(chatterboxFiles);
          _isLoadingAudioFiles = false;
        });
      }
    } catch (e) {
      debugPrint('Failed to load audio files: $e');
      if (mounted) setState(() => _isLoadingAudioFiles = false);
    }
  }

  List<Map<String, dynamic>> _mergeAudioFiles(
    List<Map<String, dynamic>> files,
  ) {
    if (_pendingAudioFiles.isEmpty) {
      return files;
    }
    final pendingIds = _pendingAudioFiles.keys.toSet();
    final merged = files
        .where((file) => !pendingIds.contains(file['id']?.toString() ?? ''))
        .toList();
    final pendingList = _pendingAudioFiles.values.toList()
      ..sort((a, b) {
        final aTime =
            DateTime.tryParse(a['created_at'] as String? ?? '') ??
            DateTime.now();
        final bTime =
            DateTime.tryParse(b['created_at'] as String? ?? '') ??
            DateTime.now();
        return bTime.compareTo(aTime);
      });
    return [...pendingList, ...merged];
  }

  void _addPendingAudioFile(Map<String, dynamic> file) {
    final pendingId = file['id']?.toString() ?? '';
    setState(() {
      _pendingAudioFiles[pendingId] = file;
      _audioFiles = _mergeAudioFiles(
        _audioFiles
            .where((f) => !_pendingAudioFiles.containsKey(f['id']?.toString()))
            .toList(),
      );
    });
  }

  void _removePendingAudioFile(String pendingId) {
    setState(() {
      _pendingAudioFiles.remove(pendingId);
      _audioFiles = _mergeAudioFiles(
        _audioFiles
            .where((f) => !_pendingAudioFiles.containsKey(f['id']?.toString()))
            .toList(),
      );
    });
  }

  Map<String, dynamic> _buildPendingAudioFile() {
    final timestamp = DateTime.now();
    final voiceLabel = _selectedChatterboxVoice ?? 'Clone';
    return {
      'id': 'pending-chatterbox-${timestamp.microsecondsSinceEpoch}',
      'filename': 'Generating Chatterbox audio...',
      'label': 'Chatterbox $voiceLabel',
      'engine': 'chatterbox',
      'voice': voiceLabel,
      'audio_url': '',
      'file_path': '',
      'size_mb': 0.0,
      'duration_seconds': 0.0,
      'created_at': timestamp.toIso8601String(),
      'metrics_available': false,
      'status': 'processing',
      'is_pending': true,
    };
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

      List<String> chatterboxLanguages = [];
      Map<String, dynamic>? chatterboxInfo;
      try {
        chatterboxLanguages = await _api.getChatterboxLanguages();
        chatterboxInfo = await _api.getChatterboxInfo();
      } catch (e) {
        debugPrint('Chatterbox not available: $e');
      }

      final chatterboxVoices = await _fetchChatterboxVoices();

      List<Map<String, dynamic>> pregeneratedSamples = [];
      try {
        pregeneratedSamples = await _api.getPregeneratedSamples(
          engine: 'chatterbox',
        );
      } catch (e) {
        debugPrint('Chatterbox pregenerated samples not available: $e');
      }

      if (!mounted) return;
      setState(() {
        _systemInfo = systemInfo;
        _chatterboxVoices = chatterboxVoices;
        _chatterboxLanguages = chatterboxLanguages;
        _pregeneratedSamples = pregeneratedSamples;
        _chatterboxInfo = chatterboxInfo;
        _selectedChatterboxVoice = _pickSelectedVoice(chatterboxVoices);
        if (chatterboxLanguages.isNotEmpty &&
            !chatterboxLanguages.contains(_selectedChatterboxLanguage)) {
          _selectedChatterboxLanguage = chatterboxLanguages[0];
        }
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

  Future<List<Map<String, dynamic>>> _fetchChatterboxVoices() async {
    try {
      final chatterboxVoiceResponse = await _api.getChatterboxVoices();
      return List<Map<String, dynamic>>.from(
        chatterboxVoiceResponse['voices'] as List<dynamic>? ?? [],
      );
    } catch (e) {
      debugPrint('Chatterbox voices not available: $e');
      return <Map<String, dynamic>>[];
    }
  }

  String? _pickSelectedVoice(
    List<Map<String, dynamic>> voices, {
    String? preferredName,
  }) {
    if (voices.isEmpty) return null;
    final target = preferredName ?? _selectedChatterboxVoice;
    if (target != null &&
        voices.any((voice) => (voice['name'] as String?) == target)) {
      return target;
    }
    return voices.first['name'] as String?;
  }

  Future<void> _refreshChatterboxVoices({String? preferredName}) async {
    final voices = await _fetchChatterboxVoices();
    if (!mounted) return;
    setState(() {
      _chatterboxVoices = voices;
      _selectedChatterboxVoice = _pickSelectedVoice(
        voices,
        preferredName: preferredName,
      );
    });
  }

  Future<void> _loadDictaStatus() async {
    try {
      final status = await _api.getChatterboxDictaStatus();
      if (!mounted) return;
      setState(() {
        _dictaStatus = status;
        _isDictaDownloading = status['download_status'] == 'downloading';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isDictaDownloading = false);
    }
  }

  Future<void> _downloadDicta() async {
    setState(() => _isDictaDownloading = true);
    try {
      final result = await _api.downloadChatterboxDictaModel();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result['message'] as String? ?? 'Dicta download started',
            ),
          ),
        );
      }
      await _loadDictaStatus();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isDictaDownloading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to download Dicta model: $e')),
      );
    }
  }

  Future<void> _generate() async {
    if (_textController.text.isEmpty) return;
    if (_selectedChatterboxVoice == null) {
      setState(
        () => _error = 'Please add a voice first in the Voice Prompts tab',
      );
      return;
    }
    if (_selectedChatterboxLanguage == 'he' &&
        (_dictaStatus?['installed'] != true)) {
      setState(
        () => _error =
            'Hebrew requires the Dicta model. Download it from the HE language chip.',
      );
      return;
    }

    // Clear any previous error
    setState(() => _error = null);

    // Build pending file with unique ID
    final pendingFile = _buildPendingAudioFile();
    final pendingId = pendingFile['id'] as String;

    // Add to pending immediately
    _addPendingAudioFile(pendingFile);

    // Capture current settings for background generation
    final text = _textController.text;
    final voiceName = _selectedChatterboxVoice!;
    final language = _selectedChatterboxLanguage;
    final speed = _speed;
    final temperature = _chatterboxTemperature;
    final cfgWeight = _chatterboxCfgWeight;
    final seed = _chatterboxSeed;
    final unloadAfter = _unloadAfter;

    // Start generation in background - don't await
    unawaited(
      _generateInBackground(
        pendingId: pendingId,
        text: text,
        voiceName: voiceName,
        language: language,
        speed: speed,
        temperature: temperature,
        cfgWeight: cfgWeight,
        seed: seed,
        unloadAfter: unloadAfter,
      ),
    );
  }

  Future<void> _generateInBackground({
    required String pendingId,
    required String text,
    required String voiceName,
    required String language,
    required double speed,
    required double temperature,
    required double cfgWeight,
    required int seed,
    required bool unloadAfter,
  }) async {
    try {
      final audioUrl = await _api.generateChatterbox(
        text: text,
        voiceName: voiceName,
        language: language,
        speed: speed,
        temperature: temperature,
        cfgWeight: cfgWeight,
        seed: seed,
        unloadAfter: unloadAfter,
      );

      final uri = Uri.parse(audioUrl);
      final filename = uri.pathSegments.isNotEmpty
          ? uri.pathSegments.last
          : null;

      if (!mounted) return;
      _removePendingAudioFile(pendingId);
      setState(() {
        _audioUrl = audioUrl;
        _audioFilename = filename;
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
      if (!mounted) return;
      _removePendingAudioFile(pendingId);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Generation failed: $e')));
    }
  }

  void _openVoicePromptsTab() {
    final controller = DefaultTabController.maybeOf(context);
    if (controller == null) return;
    controller.animateTo(7);
  }

  Future<void> _playPregeneratedSample(Map<String, dynamic> sample) async {
    final audioPath = sample['audio_url'] as String?;
    if (audioPath == null || audioPath.isEmpty) return;
    final audioUrl = _api.getPregeneratedAudioUrl(audioPath);

    try {
      await _playerSubscription?.cancel();
      _playerSubscription = null;
      await _audioPlayer.stop();
      if (!mounted) return;
      setState(() {
        _audioUrl = audioUrl;
        _audioFilename = null;
        _playingAudioId = null;
        _isAudioPaused = false;
        _previewVoiceName = null;
        _isPreviewPaused = false;
      });
      await _audioPlayer.setUrl(audioUrl);
      await _audioPlayer.play();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to play sample: $e')));
      }
    }
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
      final previousVoices = List<Map<String, dynamic>>.from(_chatterboxVoices);
      final previousSelectedVoice = _selectedChatterboxVoice;
      if (_previewVoiceName == name) {
        await _stopPreview();
      }
      if (mounted) {
        setState(() {
          final filtered = _chatterboxVoices
              .where((voice) => (voice['name'] as String?) != name)
              .toList();
          _chatterboxVoices = filtered;
          if (_selectedChatterboxVoice == name) {
            _selectedChatterboxVoice = _pickSelectedVoice(filtered);
          }
        });
      }

      try {
        await _api.deleteChatterboxVoice(name);
        await _refreshChatterboxVoices();
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Voice "$name" deleted')));
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _chatterboxVoices = previousVoices;
            _selectedChatterboxVoice = previousSelectedVoice;
          });
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

    try {
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
          await _api.updateChatterboxVoice(
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
    } finally {
      nameController.dispose();
      transcriptController.dispose();
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
      if (!mounted) return;
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
      if (!mounted) return;
      setState(() => _isAudioPaused = true);
    }
  }

  Future<void> _stopAudioPlayback() async {
    await _playerSubscription?.cancel();
    _playerSubscription = null;
    await _audioPlayer.stop();
    if (!mounted) return;
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

  Future<void> _downloadAudioFile(Map<String, dynamic> file) async {
    final audioUrl = file['audio_url'] as String?;
    final filename = file['filename'] as String? ?? 'chatterbox-audio.wav';
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Saved to $savePath')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to download: $e')));
    }
  }

  MaterialColor _sampleCardColor(Map<String, dynamic> sample) {
    final key = '${sample['title'] ?? ''} ${sample['description'] ?? ''}'
        .toLowerCase();
    if (key.contains('laugh') || key.contains('chuckle')) {
      return Colors.amber;
    }
    if (key.contains('sigh') || key.contains('neutral')) {
      return Colors.blueGrey;
    }
    if (key.contains('gasp') || key.contains('dramatic')) {
      return Colors.deepOrange;
    }
    if (key.contains('subtle')) {
      return Colors.lightGreen;
    }
    return Colors.orange;
  }

  ChatterboxLanguageOption _languageOption(String code) {
    final key = code.trim().toLowerCase();
    return kChatterboxLanguageOptions[key] ??
        ChatterboxLanguageOption(
          key,
          key.toUpperCase(),
          '\u{1F310}',
          const Color(0xFF607D8B),
        );
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSidebarShell(),
        Expanded(
          child: SingleChildScrollView(
            primary: false,
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(),
                const SizedBox(height: 4),
                const ModelStatusBanner(
                  requiredModels: ['Chatterbox Multilingual'],
                  engineName: 'Chatterbox',
                  themeColor: Colors.orange,
                ),
                if (_pregeneratedSamples.isNotEmpty) ...[
                  _buildPregeneratedSamplesSection(),
                  const SizedBox(height: 12),
                ],
                _buildLanguageSelector(),
                if (_selectedChatterboxLanguage == 'he') ...[
                  const SizedBox(height: 8),
                  _buildDictaStatusCard(),
                ],
                const SizedBox(height: 16),
                _buildVoiceSection(),
                const SizedBox(height: 16),
                TextField(
                  controller: _textController,
                  onChanged: (_) => setState(() {}),
                  minLines: 4,
                  maxLines: 10,
                  keyboardType: TextInputType.multiline,
                  decoration: const InputDecoration(
                    labelText: 'Text to synthesize',
                    hintText: 'Enter text to convert to speech.',
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
                const SizedBox(height: 12),
                _buildAdvancedPanel(),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed:
                      (_selectedChatterboxVoice == null ||
                          _textController.text.isEmpty)
                      ? null
                      : _generate,
                  icon: const Icon(Icons.mic),
                  label: const Text('Generate Speech'),
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
                    modelName: 'Chatterbox',
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

  Widget _buildSidebarShell() {
    if (_isSidebarCollapsed) {
      return Container(
        width: 44,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          border: Border(
            right: BorderSide(color: Theme.of(context).dividerColor),
          ),
        ),
        child: Center(
          child: IconButton(
            icon: const Icon(Icons.chevron_right_rounded),
            tooltip: 'Expand audio library',
            onPressed: () => setState(() => _isSidebarCollapsed = false),
          ),
        ),
      );
    }
    return _buildSidebar();
  }

  Widget _buildPregeneratedSamplesSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.record_voice_over,
                  color: Colors.orange.shade700,
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
                    style: TextStyle(fontSize: 10, color: Colors.green),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ..._pregeneratedSamples.map((sample) {
              final voice = sample['voice'] as String? ?? 'Sample';
              final title = sample['title'] as String? ?? voice;
              final description = sample['description'] as String? ?? '';
              final accent = _sampleCardColor(sample);
              final text =
                  (sample['text'] as String?) ??
                  (sample['description'] as String?) ??
                  (sample['title'] as String?) ??
                  '';
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: InkWell(
                  onTap: () => _playPregeneratedSample(sample),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.08),
                      border: Border.all(color: accent.withValues(alpha: 0.35)),
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
                            color: accent.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            voice,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: accent.shade800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (description.isNotEmpty)
                                Text(
                                  description,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade700,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              Text(
                                text,
                                style: const TextStyle(fontSize: 11),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.play_circle_outline, size: 20),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Card(
      color: Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.record_voice_over, color: Colors.orange.shade700),
                const SizedBox(width: 8),
                Text(
                  'Chatterbox',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Multilingual voice cloning from samples managed in Voice Prompts.',
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
                  if (_chatterboxInfo != null)
                    _buildInfoChip(
                      Icons.graphic_eq,
                      'SR ${_chatterboxInfo!['sample_rate'] ?? '?'}',
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDictaStatusCard() {
    final installed = _dictaStatus?['installed'] == true;
    final status = _dictaStatus?['download_status'] as String?;
    final size = _dictaStatus?['size_mb'];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: installed ? Colors.green.shade50 : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: installed ? Colors.green.shade200 : Colors.orange.shade200,
        ),
      ),
      child: Row(
        children: [
          Icon(
            installed ? Icons.check_circle : Icons.language,
            size: 18,
            color: installed ? Colors.green.shade700 : Colors.orange.shade700,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              installed
                  ? 'Dicta Hebrew model ready${size is num ? ' (${size.toStringAsFixed(1)} MB)' : ''}'
                  : 'Hebrew requires Dicta model',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: installed
                    ? Colors.green.shade800
                    : Colors.orange.shade900,
              ),
            ),
          ),
          if (!installed)
            FilledButton.tonalIcon(
              onPressed: _isDictaDownloading || status == 'downloading'
                  ? null
                  : _downloadDicta,
              icon: _isDictaDownloading || status == 'downloading'
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download, size: 16),
              label: Text(
                (_isDictaDownloading || status == 'downloading')
                    ? 'Downloading...'
                    : 'Download',
              ),
              style: FilledButton.styleFrom(
                textStyle: const TextStyle(fontSize: 11),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLanguageSelector() {
    final languages = _chatterboxLanguages.isNotEmpty
        ? List<String>.from(_chatterboxLanguages)
        : kChatterboxLanguageOptions.keys.toList();
    if (!languages.contains('he')) {
      languages.add('he');
    }
    final dictaInstalled = _dictaStatus?['installed'] == true;
    final dictaDownloading =
        _isDictaDownloading ||
        _dictaStatus?['download_status'] == 'downloading';

    return Row(
      children: [
        const Icon(Icons.language, size: 16),
        const SizedBox(width: 8),
        const Text('Language:', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(width: 12),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: languages.map((lang) {
                final option = _languageOption(lang);
                final isSelected = _selectedChatterboxLanguage == lang;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () =>
                        setState(() => _selectedChatterboxLanguage = lang),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? option.color.withValues(alpha: 0.15)
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected
                              ? option.color
                              : Colors.grey.shade300,
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            option.flag,
                            style: const TextStyle(fontSize: 14),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            option.name,
                            style: TextStyle(
                              fontSize: 12,
                              color: isSelected
                                  ? option.color
                                  : Colors.grey.shade700,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                            ),
                          ),
                          if (lang == 'he') ...[
                            const SizedBox(width: 6),
                            if (dictaInstalled)
                              Icon(
                                Icons.check_circle,
                                size: 14,
                                color: Colors.green.shade700,
                              )
                            else if (dictaDownloading)
                              const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            else if (isSelected)
                              GestureDetector(
                                onTap: _downloadDicta,
                                child: Icon(
                                  Icons.download,
                                  size: 14,
                                  color: Colors.orange.shade700,
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVoiceSection() {
    final voices = _chatterboxVoices;
    final defaults =
        voices
            .where((voice) => (voice['source'] as String?) == 'default')
            .toList()
          ..sort(
            (a, b) => (a['name'] as String).compareTo(b['name'] as String),
          );
    final users =
        voices
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
                '${voices.length} voices',
                style: TextStyle(fontSize: 10, color: Colors.grey.shade700),
              ),
            ),
            const Spacer(),
            FilledButton.tonalIcon(
              onPressed: _openVoicePromptsTab,
              icon: const Icon(Icons.mic_none_rounded),
              label: const Text('Manage in Voice Prompts'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (voices.isEmpty)
          Card(
            color: Colors.orange.shade50,
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                children: [
                  Icon(Icons.mic, size: 48, color: Colors.orange),
                  SizedBox(height: 8),
                  Text(
                    'No voice samples yet',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Add voices in the Voice Prompts tab to clone with Chatterbox',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          )
        else ...[
          if (defaults.isNotEmpty) ...[
            InkWell(
              onTap: () => setState(
                () => _isDefaultVoicesCollapsed = !_isDefaultVoicesCollapsed,
              ),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(
                      context,
                    ).dividerColor.withValues(alpha: 0.45),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.library_music, size: 16),
                    const SizedBox(width: 8),
                    const Text(
                      'Default Voices',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
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
                        '${defaults.length}',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      _isDefaultVoicesCollapsed
                          ? Icons.expand_more_rounded
                          : Icons.expand_less_rounded,
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (!_isDefaultVoicesCollapsed) ...[
              _buildVoiceCards(defaults, showDefaultBadge: true),
              const SizedBox(height: 12),
            ],
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
              color: Colors.orange.shade50,
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'No user voices yet. Add one in the Voice Prompts tab.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildVoiceCards(
    List<Map<String, dynamic>> voices, {
    bool allowEdit = false,
    bool showDefaultBadge = false,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        const spacing = 8.0;
        const compactTargetWidth = 180.0;
        const compactMinWidth = 150.0;
        final columns = (width / (compactTargetWidth + spacing)).floor().clamp(
          1,
          8,
        );
        final computedWidth = ((width - ((columns - 1) * spacing)) / columns)
            .toDouble();
        final cardWidth = computedWidth.clamp(
          compactMinWidth,
          compactTargetWidth,
        );
        return Wrap(
          spacing: spacing,
          runSpacing: 8,
          children: voices
              .map((voice) {
                return SizedBox(
                  width: cardWidth,
                  child: _buildVoiceCard(
                    voice,
                    allowEdit: allowEdit,
                    showDefaultBadge: showDefaultBadge,
                  ),
                );
              })
              .toList(growable: false),
        );
      },
    );
  }

  Widget _buildVoiceCard(
    Map<String, dynamic> voice, {
    bool allowEdit = false,
    bool showDefaultBadge = false,
  }) {
    final name = voice['name'] as String;
    final transcript = voice['transcript'] as String? ?? '';
    final isSelected = name == _selectedChatterboxVoice;
    final isPreviewing = _previewVoiceName == name;
    final accent = Theme.of(context).colorScheme.primary;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return GestureDetector(
      onTap: () => setState(() => _selectedChatterboxVoice = name),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: isSelected
              ? accent.withValues(alpha: 0.12)
              : Theme.of(context).colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? accent : Theme.of(context).dividerColor,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isSelected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  color: isSelected ? accent : muted,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    name,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: isSelected ? accent : null,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (showDefaultBadge)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'DEFAULT',
                      style: TextStyle(
                        fontSize: 9,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              transcript.isNotEmpty
                  ? (transcript.length > 24
                        ? '${transcript.substring(0, 24)}...'
                        : transcript)
                  : 'No transcript',
              style: TextStyle(
                fontSize: 10,
                fontStyle: transcript.isEmpty ? FontStyle.italic : null,
                color: muted,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.play_arrow_rounded, size: 16),
                  onPressed: (!isPreviewing || _isPreviewPaused)
                      ? () => _previewVoice(voice)
                      : null,
                  tooltip: 'Play',
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(
                    minWidth: 24,
                    minHeight: 24,
                  ),
                  padding: EdgeInsets.zero,
                ),
                IconButton(
                  icon: const Icon(Icons.pause_rounded, size: 16),
                  onPressed: (isPreviewing && !_isPreviewPaused)
                      ? _pausePreview
                      : null,
                  tooltip: 'Pause',
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(
                    minWidth: 24,
                    minHeight: 24,
                  ),
                  padding: EdgeInsets.zero,
                ),
                IconButton(
                  icon: const Icon(Icons.stop_rounded, size: 16),
                  onPressed: isPreviewing ? _stopPreview : null,
                  tooltip: 'Stop',
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(
                    minWidth: 24,
                    minHeight: 24,
                  ),
                  padding: EdgeInsets.zero,
                ),
                const Spacer(),
                if (allowEdit) ...[
                  IconButton(
                    icon: const Icon(Icons.edit_rounded, size: 16),
                    onPressed: () => _editVoice(name, transcript),
                    tooltip: 'Edit',
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(
                      minWidth: 24,
                      minHeight: 24,
                    ),
                    padding: EdgeInsets.zero,
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, size: 16),
                    onPressed: () => _deleteVoice(name),
                    tooltip: 'Delete',
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(
                      minWidth: 24,
                      minHeight: 24,
                    ),
                    padding: EdgeInsets.zero,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
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
        final isSelected = name == _selectedChatterboxVoice;
        final isPreviewing = _previewVoiceName == name;

        return Card(
          color: isSelected
              ? Theme.of(context).colorScheme.primaryContainer
              : null,
          child: ListTile(
            leading: Radio<String>(
              value: name,
              // ignore: deprecated_member_use
              groupValue: _selectedChatterboxVoice,
              // ignore: deprecated_member_use
              onChanged: (value) =>
                  setState(() => _selectedChatterboxVoice = value),
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
            onTap: () => setState(() => _selectedChatterboxVoice = name),
          ),
        );
      },
    );
  }

  Widget _buildAdvancedPanel() {
    return Column(
      children: [
        InkWell(
          onTap: () => setState(() => _showAdvanced = !_showAdvanced),
          child: Row(
            children: [
              Icon(
                _showAdvanced ? Icons.expand_less : Icons.expand_more,
                color: Colors.grey.shade600,
              ),
              Text(
                'Advanced Parameters',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        if (_showAdvanced) ...[
          const SizedBox(height: 12),
          _buildAdvancedSlider(
            'Temperature',
            _chatterboxTemperature,
            0.1,
            1.5,
            (v) => setState(() => _chatterboxTemperature = v),
          ),
          _buildAdvancedSlider(
            'CFG',
            _chatterboxCfgWeight,
            0.1,
            3.0,
            (v) => setState(() => _chatterboxCfgWeight = v),
          ),
          Row(
            children: [
              Expanded(
                child: CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Unload after',
                    style: TextStyle(fontSize: 12),
                  ),
                  value: _unloadAfter,
                  onChanged: (v) => setState(() => _unloadAfter = v ?? false),
                ),
              ),
              Expanded(
                child: Row(
                  children: [
                    const Text('Seed:', style: TextStyle(fontSize: 12)),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 60,
                      child: TextField(
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          isDense: true,
                          hintText: '-1',
                        ),
                        onChanged: (v) => setState(
                          () => _chatterboxSeed = int.tryParse(v) ?? -1,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildAdvancedSlider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) {
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(label, style: const TextStyle(fontSize: 11)),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: ((max - min) * 10).round(),
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(
            value.toStringAsFixed(value == value.roundToDouble() ? 0 : 1),
            style: const TextStyle(fontSize: 11),
          ),
        ),
      ],
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 320,
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
                IconButton(
                  icon: const Icon(Icons.chevron_left_rounded, size: 18),
                  onPressed: () => setState(() => _isSidebarCollapsed = true),
                  tooltip: 'Collapse',
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
                        'No Chatterbox audio files yet.\nGenerate speech to see it here.',
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
    final label = (file['label'] as String?) ?? 'Chatterbox Clone';
    final isPending = file['is_pending'] == true;
    final status = (file['status'] as String? ?? 'completed').toLowerCase();
    final filePath = _resolvedFilePath(file);
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
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    isPending ? Icons.hourglass_top_rounded : Icons.audiotrack,
                    color: isPending
                        ? Theme.of(context).colorScheme.secondary
                        : isThisPlaying
                        ? Theme.of(context).colorScheme.primary
                        : null,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isThisPlaying
                              ? FontWeight.bold
                              : FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isPending ? status.toUpperCase() : meta,
                        style: const TextStyle(fontSize: 10),
                      ),
                    ],
                  ),
                ),
                Wrap(
                  spacing: 0,
                  runSpacing: 0,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.insights_rounded, size: 16),
                      onPressed: isPending
                          ? null
                          : () => _showGenerationMetrics(file),
                      tooltip: 'Generation Metrics',
                      visualDensity: VisualDensity.compact,
                    ),
                    IconButton(
                      icon: const Icon(Icons.open_in_new_rounded, size: 16),
                      onPressed: isPending || filePath.isEmpty
                          ? null
                          : () => _openAudioExternally(file),
                      tooltip: 'Open externally',
                      visualDensity: VisualDensity.compact,
                    ),
                    IconButton(
                      icon: const Icon(Icons.folder_open_rounded, size: 16),
                      onPressed: isPending || filePath.isEmpty
                          ? null
                          : () => _revealAudioInFolder(file),
                      tooltip: 'Show in folder',
                      visualDensity: VisualDensity.compact,
                    ),
                    IconButton(
                      icon: const Icon(Icons.download_rounded, size: 16),
                      onPressed: isPending
                          ? null
                          : () => _downloadAudioFile(file),
                      tooltip: 'Download',
                      visualDensity: VisualDensity.compact,
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 16),
                      onPressed: isPending
                          ? null
                          : () => _deleteAudioFile(filename),
                      tooltip: 'Delete',
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (filePath.isNotEmpty || isPending)
            Padding(
              padding: const EdgeInsets.fromLTRB(42, 0, 12, 2),
              child: Text(
                isPending ? 'Generating now.' : filePath,
                maxLines: isPending ? 2 : 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 9,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(left: 12, right: 12, bottom: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.play_arrow, size: 20),
                  onPressed: !isPending && (!isThisPlaying || _isAudioPaused)
                      ? () => _playAudioFile(file)
                      : null,
                  tooltip: 'Play',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32),
                ),
                IconButton(
                  icon: const Icon(Icons.pause, size: 20),
                  onPressed: !isPending && (isThisPlaying && !_isAudioPaused)
                      ? _pauseAudioPlayback
                      : null,
                  tooltip: 'Pause',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32),
                ),
                IconButton(
                  icon: const Icon(Icons.stop, size: 20),
                  onPressed: !isPending && isThisPlaying
                      ? _stopAudioPlayback
                      : null,
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

  Future<void> _showGenerationMetrics(Map<String, dynamic> file) async {
    final filename = file['filename'] as String? ?? '';
    if (filename.isEmpty) return;
    try {
      final payload = await _api.getAudioGenerationMetrics(filename);
      if (!mounted) return;
      await showGenerationMetricsDialog(
        context,
        title: filename,
        payload: payload,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Metrics unavailable: $e')));
    }
  }

  String _resolvedFilePath(Map<String, dynamic> file) {
    final raw = (file['file_path'] as String?)?.trim() ?? '';
    if (raw.isNotEmpty) {
      return raw;
    }
    final filename = (file['filename'] as String?)?.trim() ?? '';
    if (filename.isEmpty) {
      return '';
    }
    return '$_outputFolder/$filename';
  }

  Future<void> _openAudioExternally(Map<String, dynamic> file) async {
    final filePath = _resolvedFilePath(file);
    if (filePath.isEmpty) return;
    try {
      await LocalFileActions.openPath(filePath);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to open audio: $e')));
    }
  }

  Future<void> _revealAudioInFolder(Map<String, dynamic> file) async {
    final filePath = _resolvedFilePath(file);
    if (filePath.isEmpty) return;
    try {
      await LocalFileActions.revealInFolder(filePath);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to reveal audio: $e')));
    }
  }
}
