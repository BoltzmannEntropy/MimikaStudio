import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:file_picker/file_picker.dart';
import '../services/api_service.dart';
import '../widgets/audio_player_widget.dart';

// Speaker data with colors for CustomVoice mode
class Speaker {
  final String name;
  final String language;
  final String description;
  final Color color;

  const Speaker(this.name, this.language, this.description, this.color);
}

const List<Speaker> kSpeakers = [
  Speaker('Ryan', 'English', 'Dynamic male, strong rhythm', Color(0xFF2196F3)),
  Speaker('Aiden', 'English', 'Sunny American male', Color(0xFF03A9F4)),
  Speaker('Vivian', 'Chinese', 'Bright young female', Color(0xFFE91E63)),
  Speaker('Serena', 'Chinese', 'Warm gentle female', Color(0xFFFF4081)),
  Speaker('Uncle_Fu', 'Chinese', 'Seasoned male, mellow', Color(0xFF795548)),
  Speaker('Dylan', 'Chinese', 'Beijing youthful male', Color(0xFF4CAF50)),
  Speaker('Eric', 'Chinese', 'Sichuan lively male', Color(0xFF8BC34A)),
  Speaker('Ono_Anna', 'Japanese', 'Playful female', Color(0xFF9C27B0)),
  Speaker('Sohee', 'Korean', 'Warm emotional female', Color(0xFFFF5722)),
];

// Language data with flags
class LanguageOption {
  final String code;
  final String name;
  final String flag;
  final Color color;

  const LanguageOption(this.code, this.name, this.flag, this.color);
}

const List<LanguageOption> kLanguages = [
  LanguageOption('Auto', 'Auto Detect', '🌐', Color(0xFF607D8B)),
  LanguageOption('English', 'English', '🇺🇸', Color(0xFF2196F3)),
  LanguageOption('Chinese', 'Chinese', '🇨🇳', Color(0xFFE91E63)),
  LanguageOption('Japanese', 'Japanese', '🇯🇵', Color(0xFF9C27B0)),
  LanguageOption('Korean', 'Korean', '🇰🇷', Color(0xFFFF5722)),
  LanguageOption('German', 'German', '🇩🇪', Color(0xFF795548)),
  LanguageOption('French', 'French', '🇫🇷', Color(0xFF3F51B5)),
  LanguageOption('Russian', 'Russian', '🇷🇺', Color(0xFF9C27B0)),
  LanguageOption('Portuguese', 'Portuguese', '🇵🇹', Color(0xFF4CAF50)),
  LanguageOption('Spanish', 'Spanish', '🇪🇸', Color(0xFFF57C00)),
  LanguageOption('Italian', 'Italian', '🇮🇹', Color(0xFF009688)),
];

const Map<String, String> kChatterboxLanguageNames = {
  'en': 'English',
  'zh': 'Chinese',
  'ja': 'Japanese',
  'ko': 'Korean',
  'de': 'German',
  'fr': 'French',
  'ru': 'Russian',
  'pt': 'Portuguese',
  'es': 'Spanish',
  'it': 'Italian',
};

class VoiceCloneScreen extends StatefulWidget {
  const VoiceCloneScreen({super.key});

  @override
  State<VoiceCloneScreen> createState() => _VoiceCloneScreenState();
}

class _VoiceCloneScreenState extends State<VoiceCloneScreen> {
  final ApiService _api = ApiService();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final TextEditingController _textController = TextEditingController();
  final TextEditingController _transcriptController = TextEditingController();
  final TextEditingController _instructController = TextEditingController();

  // Qwen3 mode: 'clone' or 'custom'
  String _qwen3Mode = 'custom';

  // Model size: '0.6B' or '1.7B'
  String _modelSize = '0.6B';

  // Selected preset speaker for custom mode
  String _selectedSpeaker = 'Ryan';

  // Qwen3 state
  List<Map<String, dynamic>> _qwen3Voices = [];
  List<String> _qwen3Languages = [];
  String? _selectedQwen3Voice;
  Map<String, dynamic>? _qwen3Info;

  // Voice clone engine selection
  String _voiceCloneEngine = 'qwen3'; // 'qwen3' or 'chatterbox'

  // Chatterbox state
  List<Map<String, dynamic>> _chatterboxVoices = [];
  List<String> _chatterboxLanguages = [];
  String? _selectedChatterboxVoice;
  String _selectedChatterboxLanguage = 'en';
  Map<String, dynamic>? _chatterboxInfo;

  // Common state
  Map<String, dynamic>? _systemInfo;
  String _selectedLanguage = 'Auto'; // For Qwen3
  double _speed = 1.0;

  // Advanced parameters
  bool _showAdvanced = false;
  double _temperature = 0.9;
  double _topP = 0.9;
  int _topK = 50;
  double _repetitionPenalty = 1.0;
  int _seed = -1;
  bool _unloadAfter = false;

  bool _isLoading = false;
  bool _isGenerating = false;
  bool _isUploading = false;
  String? _audioUrl;
  String? _audioFilename;
  String? _error;

  // Audio library state
  List<Map<String, dynamic>> _audioFiles = [];
  bool _isLoadingAudioFiles = false;
  String? _playingAudioId;
  bool _isAudioPaused = false;
  String? _previewVoiceName;
  String? _previewVoiceEngine;
  bool _isPreviewPaused = false;
  double _libraryPlaybackSpeed = 1.0;
  StreamSubscription<PlayerState>? _playerSubscription;

  // Chatterbox advanced parameters
  double _chatterboxTemperature = 0.8;
  double _chatterboxCfgWeight = 1.0;
  double _chatterboxExaggeration = 0.5;
  int _chatterboxSeed = -1;

  String _audioModelName = 'Qwen3';

  @override
  void initState() {
    super.initState();
    _textController.text =
        'For many, the experience of Vietnam had a radicalizing effect, leading them to conclude that US military intervention was not a well-intentioned mistake by policymakers, but part of a consistent effort to preserve American political, economic, and military domination globally, largely in service of corporate profits. From this perspective, embraced by the "New Left"—as opposed to the old-line socialist and communist groups marginalized by the early 1950s—official rhetoric about freedom, democracy, and progress was seen as mere lip service.';
    _loadData();
    _loadAudioFiles();
  }

  @override
  void dispose() {
    _playerSubscription?.cancel();
    _audioPlayer.dispose();
    _textController.dispose();
    _transcriptController.dispose();
    _instructController.dispose();
    super.dispose();
  }

  Future<void> _loadAudioFiles() async {
    setState(() => _isLoadingAudioFiles = true);
    try {
      final files = await _api.getVoiceCloneAudioFiles();
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
      // Load common data (non-fatal if unavailable)
      Map<String, dynamic>? systemInfo;
      try {
        systemInfo = await _api.getSystemInfo();
      } catch (e) {
        debugPrint('System info not available: $e');
      }

      // Load Qwen3 languages
      List<String> qwen3Languages = [];
      Map<String, dynamic>? qwen3Info;
      try {
        qwen3Languages = await _api.getQwen3Languages();
        qwen3Info = await _api.getQwen3Info();
      } catch (e) {
        debugPrint('Qwen3 not available: $e');
      }

      // Load Qwen3 voices
      List<Map<String, dynamic>> qwen3Voices = [];
      try {
        final qwen3VoiceResponse = await _api.getQwen3Voices();
        qwen3Voices = List<Map<String, dynamic>>.from(
          qwen3VoiceResponse['voices'] as List<dynamic>? ?? [],
        );
      } catch (e) {
        debugPrint('Qwen3 voices not available: $e');
      }

      // Load Chatterbox languages
      List<String> chatterboxLanguages = [];
      Map<String, dynamic>? chatterboxInfo;
      try {
        chatterboxLanguages = await _api.getChatterboxLanguages();
        chatterboxInfo = await _api.getChatterboxInfo();
      } catch (e) {
        debugPrint('Chatterbox not available: $e');
      }

      // Load Chatterbox voices
      List<Map<String, dynamic>> chatterboxVoices = [];
      try {
        final chatterboxVoiceResponse = await _api.getChatterboxVoices();
        chatterboxVoices = List<Map<String, dynamic>>.from(
          chatterboxVoiceResponse['voices'] as List<dynamic>? ?? [],
        );
      } catch (e) {
        debugPrint('Chatterbox voices not available: $e');
      }

      setState(() {
        _systemInfo = systemInfo;

        // Qwen3
        _qwen3Voices = qwen3Voices;
        _qwen3Languages = qwen3Languages;
        _qwen3Info = qwen3Info;
        if (qwen3Voices.isNotEmpty) {
          _selectedQwen3Voice = qwen3Voices[0]['name'];
        }

        // Chatterbox
        _chatterboxVoices = chatterboxVoices;
        _chatterboxLanguages = chatterboxLanguages;
        _chatterboxInfo = chatterboxInfo;
        if (chatterboxVoices.isNotEmpty) {
          _selectedChatterboxVoice = chatterboxVoices[0]['name'];
        }
        if (chatterboxLanguages.isNotEmpty) {
          _selectedChatterboxLanguage = chatterboxLanguages[0];
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
    if (_textController.text.isEmpty) return;

    setState(() {
      _isGenerating = true;
      _error = null;
    });

    try {
      String audioUrl;
      String engineLabel = 'Qwen3';

      if (_voiceCloneEngine == 'qwen3') {
        // Qwen3-TTS with mode support
        if (_qwen3Mode == 'clone') {
          if (_selectedQwen3Voice == null) {
            throw Exception('Please upload a voice sample first');
          }
          audioUrl = await _api.generateQwen3(
            text: _textController.text,
            mode: 'clone',
            voiceName: _selectedQwen3Voice!,
            language: _selectedLanguage,
            speed: _speed,
            modelSize: _modelSize,
            temperature: _temperature,
            topP: _topP,
            topK: _topK,
            repetitionPenalty: _repetitionPenalty,
            seed: _seed,
            unloadAfter: _unloadAfter,
          );
        } else {
          // Custom voice mode (preset speakers)
          audioUrl = await _api.generateQwen3(
            text: _textController.text,
            mode: 'custom',
            speaker: _selectedSpeaker,
            language: _selectedLanguage,
            speed: _speed,
            modelSize: _modelSize,
            instruct: _instructController.text.isNotEmpty
                ? _instructController.text
                : null,
            temperature: _temperature,
            topP: _topP,
            topK: _topK,
            repetitionPenalty: _repetitionPenalty,
            seed: _seed,
            unloadAfter: _unloadAfter,
          );
        }
        engineLabel = 'Qwen3';
      } else {
        if (_selectedChatterboxVoice == null) {
          throw Exception('Please upload a voice sample first');
        }
        audioUrl = await _api.generateChatterbox(
          text: _textController.text,
          voiceName: _selectedChatterboxVoice!,
          language: _selectedChatterboxLanguage,
          speed: _speed,
          temperature: _chatterboxTemperature,
          cfgWeight: _chatterboxCfgWeight,
          exaggeration: _chatterboxExaggeration,
          seed: _chatterboxSeed,
          unloadAfter: _unloadAfter,
        );
        engineLabel = 'Chatterbox';
      }

      // Extract filename from URL (e.g., http://localhost:8000/audio/qwen3-xxx.wav -> qwen3-xxx.wav)
      final uri = Uri.parse(audioUrl);
      final filename = uri.pathSegments.isNotEmpty
          ? uri.pathSegments.last
          : null;

      setState(() {
        _audioUrl = audioUrl;
        _audioFilename = filename;
        _audioModelName = engineLabel;
        _isGenerating = false;
        _playingAudioId = null;
        _isAudioPaused = false;
        _previewVoiceName = null;
        _previewVoiceEngine = null;
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

  Future<void> _uploadQwen3Voice() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      allowMultiple: false,
    );

    if (result != null && result.files.single.path != null) {
      final dialogResult = await _showQwen3UploadDialog();
      if (dialogResult != null) {
        setState(() => _isUploading = true);
        try {
          await _api.uploadQwen3Voice(
            dialogResult['name']!,
            File(result.files.single.path!),
            dialogResult['transcript']!,
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

  Future<Map<String, String>?> _showQwen3UploadDialog() async {
    final nameController = TextEditingController();
    final transcriptController = TextEditingController();

    return showDialog<Map<String, String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Qwen3 Voice Sample'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Voice Name',
                hintText: 'e.g., "MyVoice"',
              ),
              autofocus: true,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: transcriptController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Transcript (Required)',
                hintText: 'What is said in the audio file...',
                helperText: 'Must match exactly what is spoken',
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
              if (nameController.text.isNotEmpty &&
                  transcriptController.text.isNotEmpty) {
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
  }

  Future<void> _uploadChatterboxVoice() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      allowMultiple: false,
    );

    if (result != null && result.files.single.path != null) {
      final dialogResult = await _showChatterboxUploadDialog();
      if (dialogResult != null) {
        setState(() => _isUploading = true);
        try {
          await _api.uploadChatterboxVoice(
            dialogResult['name']!,
            File(result.files.single.path!),
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

  Future<Map<String, String>?> _showChatterboxUploadDialog() async {
    final nameController = TextEditingController();
    final transcriptController = TextEditingController();

    return showDialog<Map<String, String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Chatterbox Voice Sample'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Voice Name',
                hintText: 'e.g., Natasha',
              ),
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

  Future<void> _deleteChatterboxVoice(String name) async {
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
        await _api.deleteChatterboxVoice(name);
        await _loadData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Voice "$name" deleted')),
          );
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

  Future<void> _editChatterboxVoice(String name, String currentTranscript) async {
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
        await _api.updateChatterboxVoice(
          name,
          newName: result['name'] != name ? result['name'] : null,
          transcript: result['transcript'],
        );
        await _loadData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Voice updated')),
          );
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
                _buildEngineToggle(),
                const SizedBox(height: 8),
                // Model Header with System Info
                _buildModelHeader(),
                const SizedBox(height: 4),
                if (_voiceCloneEngine == 'qwen3') ...[
                  // Model size selector
                  _buildModelSizeSelector(),
                  const SizedBox(height: 12),

                  // Language selector with flags
                  _buildLanguageSelector(),
                  const SizedBox(height: 16),

                  // Mode-specific content
                  if (_qwen3Mode == 'custom') ...[
                    _buildSpeakerCarousel(),
                  ] else ...[
                    _buildQwen3VoiceSection(),
                  ],
                ] else ...[
                  _buildChatterboxLanguageSelector(),
                  const SizedBox(height: 16),
                  _buildChatterboxVoiceSection(),
                ],
                const SizedBox(height: 16),

                // Text Input
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
                        divisions: 15,
                        label: '${_speed.toStringAsFixed(1)}x',
                        onChanged: (value) => setState(() => _speed = value),
                      ),
                    ),
                    Text('${_speed.toStringAsFixed(1)}x'),
                  ],
                ),

                const SizedBox(height: 12),
                _buildAdvancedPanel(),
                const SizedBox(height: 16),

                // Generate Button
                FilledButton.icon(
                  onPressed:
                      (_isGenerating || !_canGenerate())
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

                // Error
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

                // Audio Player
                if (_audioUrl != null) ...[
                  // Show output file path
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
                              'Output: backend/outputs/$_audioFilename',
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
                    modelName: _audioModelName,
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

  bool _canGenerate() {
    if (_textController.text.isEmpty) return false;
    if (_voiceCloneEngine == 'qwen3') {
      if (_qwen3Mode == 'clone') {
        return _selectedQwen3Voice != null;
      }
      // Custom mode always available with preset speakers
      return true;
    }
    return _selectedChatterboxVoice != null;
  }

  Widget _buildModeToggle() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildModeButton('clone', 'Voice Clone', Icons.mic),
          _buildModeButton('custom', 'Preset Voice', Icons.record_voice_over),
        ],
      ),
    );
  }

  Widget _buildEngineToggle() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildEngineButton('qwen3', 'Qwen3-TTS', Icons.auto_awesome),
          _buildEngineButton('chatterbox', 'Chatterbox', Icons.record_voice_over),
        ],
      ),
    );
  }

  Widget _buildEngineButton(String engine, String label, IconData icon) {
    final isSelected = _voiceCloneEngine == engine;
    return GestureDetector(
      onTap: () {
        setState(() {
          _voiceCloneEngine = engine;
          _error = null;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.indigo : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? Colors.white : Colors.grey.shade600,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isSelected ? Colors.white : Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeButton(String mode, String label, IconData icon) {
    final isSelected = _qwen3Mode == mode;
    return GestureDetector(
      onTap: () => setState(() => _qwen3Mode = mode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.teal : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? Colors.white : Colors.grey.shade600,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isSelected ? Colors.white : Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModelSizeSelector() {
    return Row(
      children: [
        const Icon(Icons.memory, size: 16),
        const SizedBox(width: 8),
        const Text('Model:', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(width: 12),
        ChoiceChip(
          label: const Text('0.6B (Fast)'),
          selected: _modelSize == '0.6B',
          onSelected: (_) => setState(() => _modelSize = '0.6B'),
        ),
        const SizedBox(width: 8),
        ChoiceChip(
          label: const Text('1.7B (Quality)'),
          selected: _modelSize == '1.7B',
          onSelected: (_) => setState(() => _modelSize = '1.7B'),
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
                    divisions: 15,
                    label: '${_libraryPlaybackSpeed.toStringAsFixed(1)}x',
                    onChanged: _setLibraryPlaybackSpeed,
                  ),
                ),
                Text(
                  '${_libraryPlaybackSpeed.toStringAsFixed(1)}x',
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
    final label = (file['label'] as String?) ?? 'Voice Clone';
    final engine = (file['engine'] as String?) ?? '';
    final mode = (file['mode'] as String?) ?? '';
    final duration = (file['duration_seconds'] as num?) ?? 0;
    final sizeMb = (file['size_mb'] as num?) ?? 0;
    final isThisPlaying = _playingAudioId == fileId;

    final mins = (duration / 60).floor();
    final secs = (duration % 60).round();
    final durationStr = mins > 0 ? '${mins}m ${secs}s' : '${secs}s';
    final engineLabel = engine.isNotEmpty ? engine.toUpperCase() : 'VOICE';
    final modeLabel = mode.isNotEmpty ? mode.toUpperCase() : '';
    final meta = [
      engineLabel,
      modeLabel,
      durationStr,
      '${sizeMb.toStringAsFixed(1)} MB',
    ].where((part) => part.isNotEmpty).join(' • ');

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

    if (_playingAudioId == fileId && _isAudioPaused) {
      setState(() => _isAudioPaused = false);
      await _audioPlayer.play();
      return;
    }

    setState(() {
      _playingAudioId = fileId;
      _isAudioPaused = false;
      _previewVoiceName = null;
      _previewVoiceEngine = null;
      _isPreviewPaused = false;
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

  Widget _buildLanguageSelector() {
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
              children: kLanguages.map((lang) {
                final isSelected = _selectedLanguage == lang.code;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedLanguage = lang.code),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? lang.color.withValues(alpha: 0.15)
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected ? lang.color : Colors.grey.shade300,
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(lang.flag, style: const TextStyle(fontSize: 14)),
                          const SizedBox(width: 6),
                          Text(
                            lang.name,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isSelected
                                  ? lang.color
                                  : Colors.grey.shade700,
                            ),
                          ),
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

  String _formatChatterboxLanguage(String code) {
    return kChatterboxLanguageNames[code] ?? code;
  }

  Widget _buildChatterboxLanguageSelector() {
    final languages = _chatterboxLanguages.isNotEmpty
        ? _chatterboxLanguages
        : kChatterboxLanguageNames.keys.toList();

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
                            ? Colors.orange.withValues(alpha: 0.15)
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected
                              ? Colors.orange
                              : Colors.grey.shade300,
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Text(
                        _formatChatterboxLanguage(lang),
                        style: TextStyle(
                          fontSize: 12,
                          color: isSelected
                              ? Colors.orange.shade700
                              : Colors.grey.shade700,
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.w500,
                        ),
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

  Widget _buildSpeakerCarousel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.person, size: 16),
            SizedBox(width: 8),
            Text(
              'Select Speaker:',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 80,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: kSpeakers.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final speaker = kSpeakers[index];
              final isSelected = _selectedSpeaker == speaker.name;
              return GestureDetector(
                onTap: () => setState(() => _selectedSpeaker = speaker.name),
                child: Container(
                  width: 100,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? speaker.color.withValues(alpha: 0.2)
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected ? speaker.color : Colors.grey.shade300,
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: speaker.color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              speaker.name,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: isSelected
                                    ? speaker.color
                                    : Colors.black87,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        speaker.language,
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      Text(
                        speaker.description,
                        style: TextStyle(
                          fontSize: 9,
                          color: Colors.grey.shade500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _instructController,
          maxLines: 1,
          decoration: const InputDecoration(
            labelText: 'Style instruction (optional)',
            hintText: 'e.g., "Very happy", "Speak slowly", "Whisper"',
            border: OutlineInputBorder(),
          ),
        ),
      ],
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
          if (_voiceCloneEngine == 'qwen3') ...[
            _buildAdvancedSlider(
              'Temperature',
              _temperature,
              0.1,
              2.0,
              (v) => setState(() => _temperature = v),
            ),
            _buildAdvancedSlider(
              'Top P',
              _topP,
              0.1,
              1.0,
              (v) => setState(() => _topP = v),
            ),
            _buildAdvancedSlider(
              'Top K',
              _topK.toDouble(),
              1,
              100,
              (v) => setState(() => _topK = v.round()),
            ),
            _buildAdvancedSlider(
              'Rep. Penalty',
              _repetitionPenalty,
              1.0,
              2.0,
              (v) => setState(() => _repetitionPenalty = v),
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
                          onChanged: (v) =>
                              setState(() => _seed = int.tryParse(v) ?? -1),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ] else ...[
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
            _buildAdvancedSlider(
              'Exaggeration',
              _chatterboxExaggeration,
              0.0,
              1.5,
              (v) => setState(() => _chatterboxExaggeration = v),
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
                              () => _chatterboxSeed = int.tryParse(v) ?? -1),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
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

  Widget _buildModelHeader() {
    if (_voiceCloneEngine == 'qwen3') {
      return _buildQwen3Header();
    }
    return _buildChatterboxHeader();
  }

  Widget _buildQwen3Header() {
    return Card(
      color: Colors.teal.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome, color: Colors.teal.shade700),
                const SizedBox(width: 8),
                Text(
                  'Qwen3-TTS',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.teal.shade700,
                  ),
                ),
                const Spacer(),
                _buildModeToggle(),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _qwen3Mode == 'clone'
                  ? 'Clone a voice from your audio samples (3+ seconds).'
                  : 'Use preset premium speakers - no audio required.',
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
                  _buildInfoChip(
                    Icons.library_books,
                    'Qwen3-TTS-$_modelSize-${_qwen3Mode == 'clone' ? 'Base' : 'CustomVoice'}',
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildChatterboxHeader() {
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
                const Spacer(),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Multilingual voice cloning from a reference sample.',
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

  Future<void> _deleteQwen3Voice(String name) async {
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
        await _api.deleteQwen3Voice(name);
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

  Future<void> _editQwen3Voice(String name, String currentTranscript) async {
    final transcriptController = TextEditingController(text: currentTranscript);
    final nameController = TextEditingController(text: name);

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit Voice: $name'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Voice Name'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: transcriptController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Transcript',
                hintText: 'What is said in the audio...',
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
            onPressed: () => Navigator.pop(context, {
              'name': nameController.text,
              'transcript': transcriptController.text,
            }),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != null) {
      try {
        await _api.updateQwen3Voice(
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

  Future<void> _previewQwen3Voice(Map<String, dynamic> voice) async {
    final name = voice['name'] as String? ?? '';
    if (name.isEmpty) return;

    if (_previewVoiceName == name &&
        _previewVoiceEngine == 'qwen3' &&
        _isPreviewPaused) {
      setState(() => _isPreviewPaused = false);
      await _audioPlayer.play();
      return;
    }

    try {
      final audioUrl = voice['audio_url'] as String?;
      if (audioUrl == null || audioUrl.isEmpty) {
        throw Exception('Preview audio not available');
      }
      final playUrl =
          audioUrl.startsWith('http') ? audioUrl : '${ApiService.baseUrl}$audioUrl';

      await _playerSubscription?.cancel();
      _playerSubscription = null;
      await _audioPlayer.stop();

      if (!mounted) return;
      setState(() {
        _playingAudioId = null;
        _isAudioPaused = false;
        _previewVoiceName = name;
        _previewVoiceEngine = 'qwen3';
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

  Future<void> _previewChatterboxVoice(Map<String, dynamic> voice) async {
    final name = voice['name'] as String? ?? '';
    if (name.isEmpty) return;

    if (_previewVoiceName == name &&
        _previewVoiceEngine == 'chatterbox' &&
        _isPreviewPaused) {
      setState(() => _isPreviewPaused = false);
      await _audioPlayer.play();
      return;
    }

    try {
      final audioUrl = voice['audio_url'] as String?;
      if (audioUrl == null || audioUrl.isEmpty) {
        throw Exception('Preview audio not available');
      }
      final playUrl =
          audioUrl.startsWith('http') ? audioUrl : '${ApiService.baseUrl}$audioUrl';

      await _playerSubscription?.cancel();
      _playerSubscription = null;
      await _audioPlayer.stop();

      if (!mounted) return;
      setState(() {
        _playingAudioId = null;
        _isAudioPaused = false;
        _previewVoiceName = name;
        _previewVoiceEngine = 'chatterbox';
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
              _previewVoiceEngine = null;
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

  Future<void> _pausePreviewPlayback() async {
    if (_previewVoiceName != null && !_isPreviewPaused) {
      await _audioPlayer.pause();
      setState(() => _isPreviewPaused = true);
    }
  }

  Future<void> _stopPreviewPlayback() async {
    await _playerSubscription?.cancel();
    _playerSubscription = null;
    await _audioPlayer.stop();
    if (mounted) {
      setState(() {
        _previewVoiceName = null;
        _previewVoiceEngine = null;
        _isPreviewPaused = false;
      });
    }
  }

  Widget _buildQwen3VoiceList(
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
        final isSelected = name == _selectedQwen3Voice;
        final isPreviewing =
            _previewVoiceName == name && _previewVoiceEngine == 'qwen3';

        return Card(
          color: isSelected
              ? Theme.of(context).colorScheme.primaryContainer
              : null,
          child: ListTile(
            leading: Radio<String>(
              value: name,
              groupValue: _selectedQwen3Voice,
              onChanged: (value) => setState(() => _selectedQwen3Voice = value),
            ),
            title: Row(
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                if (showDefaultBadge) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                    style: TextStyle(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.play_arrow),
                  onPressed: (!isPreviewing || _isPreviewPaused)
                      ? () => _previewQwen3Voice(voice)
                      : null,
                  tooltip: 'Play',
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(minWidth: 32),
                ),
                IconButton(
                  icon: const Icon(Icons.pause),
                  onPressed: (isPreviewing && !_isPreviewPaused)
                      ? _pausePreviewPlayback
                      : null,
                  tooltip: 'Pause',
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(minWidth: 32),
                ),
                IconButton(
                  icon: const Icon(Icons.stop),
                  onPressed: isPreviewing ? _stopPreviewPlayback : null,
                  tooltip: 'Stop',
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(minWidth: 32),
                ),
                if (allowEdit) ...[
                  IconButton(
                    icon: const Icon(Icons.edit, size: 20),
                    onPressed: () => _editQwen3Voice(name, transcript),
                    tooltip: 'Edit',
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete,
                        size: 20, color: Colors.red),
                    onPressed: () => _deleteQwen3Voice(name),
                    tooltip: 'Delete',
                  ),
                ],
              ],
            ),
            onTap: () => setState(() => _selectedQwen3Voice = name),
          ),
        );
      },
    );
  }

  Widget _buildQwen3VoiceSection() {
    final voices = _qwen3Voices;
    final defaults = voices
        .where((voice) => (voice['source'] as String?) == 'default')
        .toList()
      ..sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
    final users = voices
        .where((voice) => (voice['source'] as String?) != 'default')
        .toList()
      ..sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));

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
              onPressed: _isUploading ? null : _uploadQwen3Voice,
              icon: _isUploading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.upload),
              label: Text(_isUploading ? 'Uploading...' : 'Upload Voice (WAV only)'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (voices.isEmpty)
          Card(
            color: Colors.blue.shade50,
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                children: [
                  Icon(Icons.mic, size: 48, color: Colors.blue),
                  SizedBox(height: 8),
                  Text(
                    'No voice samples yet',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Upload a 3+ second WAV clip with its transcript to clone a voice',
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
            _buildQwen3VoiceList(defaults, showDefaultBadge: true),
            const SizedBox(height: 12),
          ],
          if (users.isNotEmpty) ...[
            const Text(
              'Your Voices:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _buildQwen3VoiceList(users, allowEdit: true),
          ] else ...[
            Card(
              color: Colors.blue.shade50,
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

  Widget _buildChatterboxVoiceList(
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
        final isPreviewing =
            _previewVoiceName == name && _previewVoiceEngine == 'chatterbox';

        return Card(
          color: isSelected
              ? Theme.of(context).colorScheme.primaryContainer
              : null,
          child: ListTile(
            leading: Radio<String>(
              value: name,
              groupValue: _selectedChatterboxVoice,
              onChanged: (value) =>
                  setState(() => _selectedChatterboxVoice = value),
            ),
            title: Row(
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                if (showDefaultBadge) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                    style: TextStyle(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.play_arrow),
                  onPressed: (!isPreviewing || _isPreviewPaused)
                      ? () => _previewChatterboxVoice(voice)
                      : null,
                  tooltip: 'Play',
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(minWidth: 32),
                ),
                IconButton(
                  icon: const Icon(Icons.pause),
                  onPressed: (isPreviewing && !_isPreviewPaused)
                      ? _pausePreviewPlayback
                      : null,
                  tooltip: 'Pause',
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(minWidth: 32),
                ),
                IconButton(
                  icon: const Icon(Icons.stop),
                  onPressed: isPreviewing ? _stopPreviewPlayback : null,
                  tooltip: 'Stop',
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(minWidth: 32),
                ),
                if (allowEdit) ...[
                  IconButton(
                    icon: const Icon(Icons.edit, size: 20),
                    onPressed: () => _editChatterboxVoice(name, transcript),
                    tooltip: 'Edit',
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete,
                        size: 20, color: Colors.red),
                    onPressed: () => _deleteChatterboxVoice(name),
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

  Widget _buildChatterboxVoiceSection() {
    final voices = _chatterboxVoices;
    final defaults = voices
        .where((voice) => (voice['source'] as String?) == 'default')
        .toList()
      ..sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
    final users = voices
        .where((voice) => (voice['source'] as String?) != 'default')
        .toList()
      ..sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));

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
              onPressed: _isUploading ? null : _uploadChatterboxVoice,
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
                    'Upload a 3+ second WAV clip to clone a voice',
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
            _buildChatterboxVoiceList(defaults, showDefaultBadge: true),
            const SizedBox(height: 12),
          ],
          if (users.isNotEmpty) ...[
            const Text(
              'Your Voices:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _buildChatterboxVoiceList(users, allowEdit: true),
          ] else ...[
            Card(
              color: Colors.orange.shade50,
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

}
