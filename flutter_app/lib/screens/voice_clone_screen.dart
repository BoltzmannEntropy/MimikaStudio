import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:file_picker/file_picker.dart';
import '../services/api_service.dart';
import '../widgets/audio_player_widget.dart';

enum VoiceCloneEngine { xtts, qwen3 }

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
];

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

  // Engine selection
  VoiceCloneEngine _selectedEngine = VoiceCloneEngine.qwen3;

  // Qwen3 mode: 'clone' or 'custom'
  String _qwen3Mode = 'custom';

  // Model size: '0.6B' or '1.7B'
  String _modelSize = '0.6B';

  // Selected preset speaker for custom mode
  String _selectedSpeaker = 'Ryan';

  // XTTS state
  List<Map<String, dynamic>> _xttsVoices = [];
  List<String> _xttsLanguages = [];
  String? _selectedXttsVoice;

  // Qwen3 state
  List<Map<String, dynamic>> _qwen3Voices = [];
  List<String> _qwen3Languages = [];
  String? _selectedQwen3Voice;
  Map<String, dynamic>? _qwen3Info;

  // Common state
  List<Map<String, dynamic>> _samples = [];
  Map<String, dynamic>? _systemInfo;
  String _selectedLanguage = 'Auto'; // For Qwen3
  String _selectedXttsLanguage = 'English'; // For XTTS
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
      // Load common data
      final systemInfo = await _api.getSystemInfo();

      // Load XTTS voices
      List<Map<String, dynamic>> xttsVoices = [];
      try {
        xttsVoices = await _api.getXttsVoices();
      } catch (e) {
        debugPrint('XTTS voices not available: $e');
      }

      // Load XTTS languages
      final xttsLanguages = await _api.getXttsLanguages();
      final samples = await _api.getSamples('xtts');

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

      setState(() {
        _systemInfo = systemInfo;

        // XTTS
        _xttsVoices = xttsVoices;
        _xttsLanguages = xttsLanguages;
        if (xttsVoices.isNotEmpty) {
          _selectedXttsVoice = xttsVoices[0]['name'];
        }

        // Qwen3
        _qwen3Voices = qwen3Voices;
        _qwen3Languages = qwen3Languages;
        _qwen3Info = qwen3Info;
        if (qwen3Voices.isNotEmpty) {
          _selectedQwen3Voice = qwen3Voices[0]['name'];
        }

        _samples = samples;
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
      if (_selectedEngine == VoiceCloneEngine.xtts) {
        if (_selectedXttsVoice == null) {
          throw Exception('Please select a voice');
        }
        audioUrl = await _api.generateXtts(
          text: _textController.text,
          speakerId: _selectedXttsVoice!,
          language: _selectedXttsLanguage,
          speed: _speed,
        );
      } else {
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
      }

      // Extract filename from URL (e.g., http://localhost:8000/audio/qwen3-xxx.wav -> qwen3-xxx.wav)
      final uri = Uri.parse(audioUrl);
      final filename = uri.pathSegments.isNotEmpty
          ? uri.pathSegments.last
          : null;

      setState(() {
        _audioUrl = audioUrl;
        _audioFilename = filename;
        _isGenerating = false;
      });

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

  Future<void> _uploadXttsVoice() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      allowMultiple: false,
    );

    if (result != null && result.files.single.path != null) {
      final name = await _showNameDialog();
      if (name != null && name.isNotEmpty) {
        try {
          await _api.uploadXttsVoice(name, File(result.files.single.path!));
          await _loadData();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Voice "$name" uploaded successfully')),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('Failed to upload: $e')));
          }
        }
      }
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

  Future<String?> _showNameDialog() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Voice Name'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Enter name for this voice',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
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

    final isQwen3 = _selectedEngine == VoiceCloneEngine.qwen3;
    // Qwen3 is available - custom mode with preset speakers always works
    final qwen3Available = true;

    return Row(
      children: [
        _buildSidebar(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Engine Selector
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: SegmentedButton<VoiceCloneEngine>(
                      segments: [
                        ButtonSegment(
                          value: VoiceCloneEngine.qwen3,
                          label: const Text('Qwen3-TTS'),
                          icon: Icon(
                            Icons.auto_awesome,
                            color: qwen3Available ? null : Colors.grey,
                          ),
                        ),
                        const ButtonSegment(
                          value: VoiceCloneEngine.xtts,
                          label: Text('XTTS2'),
                          icon: Icon(Icons.record_voice_over),
                        ),
                      ],
                      selected: {_selectedEngine},
                      onSelectionChanged: (selection) {
                        setState(() => _selectedEngine = selection.first);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Model Header with System Info
                _buildModelHeader(isQwen3, qwen3Available),
                const SizedBox(height: 16),

                // Qwen3 not installed warning
                if (isQwen3 && !qwen3Available)
                  Card(
                    color: Colors.orange.shade100,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.warning, color: Colors.orange),
                              const SizedBox(width: 8),
                              const Text(
                                'Qwen3-TTS Not Installed',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Install with: pip install -U qwen-tts soundfile',
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Features: 3-second voice cloning, 10 languages, MPS/CUDA support',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Qwen3 Mode-specific UI
                if (isQwen3) ...[
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
                  const SizedBox(height: 16),
                ] else ...[
                  // XTTS Voice Selection
                  _buildXttsVoiceSection(),
                  const SizedBox(height: 16),

                  // Language Selection for XTTS
                  if (_xttsLanguages.isNotEmpty)
                    DropdownButtonFormField<String>(
                      value: _xttsLanguages.contains(_selectedXttsLanguage)
                          ? _selectedXttsLanguage
                          : _xttsLanguages.first,
                      decoration: const InputDecoration(
                        labelText: 'Language',
                        border: OutlineInputBorder(),
                      ),
                      items: _xttsLanguages.map((lang) {
                        return DropdownMenuItem(value: lang, child: Text(lang));
                      }).toList(),
                      onChanged: (value) {
                        if (value != null)
                          setState(() => _selectedXttsLanguage = value);
                      },
                    ),
                  const SizedBox(height: 12),
                ],

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
                        min: isQwen3 ? 0.5 : 0.1,
                        max: isQwen3 ? 2.0 : 1.99,
                        divisions: 15,
                        label: '${_speed.toStringAsFixed(1)}x',
                        onChanged: (value) => setState(() => _speed = value),
                      ),
                    ),
                    Text('${_speed.toStringAsFixed(1)}x'),
                  ],
                ),

                // Advanced parameters (Qwen3 only)
                if (isQwen3) ...[
                  const SizedBox(height: 12),
                  _buildAdvancedPanel(),
                ],
                const SizedBox(height: 16),

                // Sample Texts (XTTS only)
                if (!isQwen3 && _samples.isNotEmpty) ...[
                  const Text(
                    'Sample texts:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _samples.map((s) {
                      return ActionChip(
                        label: Text(
                          (s['text'] as String).length > 30
                              ? '${(s['text'] as String).substring(0, 30)}...'
                              : s['text'] as String,
                        ),
                        onPressed: () =>
                            _textController.text = s['text'] as String,
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                ],

                // Generate Button
                FilledButton.icon(
                  onPressed:
                      (_isGenerating || !_canGenerate(isQwen3, qwen3Available))
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
                    modelName: isQwen3 ? 'Qwen3' : 'XTTS2',
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

  bool _canGenerate(bool isQwen3, bool qwen3Available) {
    if (_textController.text.isEmpty) return false;
    if (isQwen3) {
      if (_qwen3Mode == 'clone') {
        return _selectedQwen3Voice != null;
      } else {
        // Custom mode always available with preset speakers
        return true;
      }
    } else {
      return _selectedXttsVoice != null;
    }
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

  Widget _buildModelHeader(bool isQwen3, bool qwen3Available) {
    if (isQwen3) {
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
    } else {
      return Card(
        color: Theme.of(context).colorScheme.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.record_voice_over,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'XTTS2 Voice Cloning',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Coqui AI',
                      style: TextStyle(
                        fontSize: 10,
                        color: Theme.of(context).colorScheme.onPrimary,
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
                      _systemInfo!['models']?['xtts']?['model'] ?? 'XTTS v2',
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      );
    }
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

  Widget _buildQwen3VoiceSection() {
    // Only show Qwen3 voices in the Qwen3 panel
    final allVoices = _qwen3Voices
        .where((voice) => (voice['source'] as String? ?? 'qwen3') != 'xtts')
        .toList();

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
                '${allVoices.length} voices',
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
              label: Text(_isUploading ? 'Uploading...' : 'Upload Voice'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (allVoices.isEmpty)
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
                    'Upload a 3+ second audio clip with its transcript to clone a voice',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: allVoices.length,
            itemBuilder: (context, index) {
              final voice = allVoices[index];
              final name = voice['name'] as String;
              final transcript = voice['transcript'] as String? ?? '';
              final source = voice['source'] as String? ?? 'qwen3';
              final isSelected = name == _selectedQwen3Voice;

              return Card(
                color: isSelected
                    ? Theme.of(context).colorScheme.primaryContainer
                    : null,
                child: ListTile(
                  leading: Radio<String>(
                    value: name,
                    groupValue: _selectedQwen3Voice,
                    onChanged: (value) =>
                        setState(() => _selectedQwen3Voice = value),
                  ),
                  title: Row(
                    children: [
                      Text(
                        name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: source == 'qwen3'
                              ? Colors.teal.shade100
                              : Colors.blue.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          source == 'qwen3' ? 'Qwen3' : 'XTTS',
                          style: TextStyle(
                            fontSize: 10,
                            color: source == 'qwen3'
                                ? Colors.teal.shade700
                                : Colors.blue.shade700,
                          ),
                        ),
                      ),
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
                        icon: const Icon(Icons.edit, size: 20),
                        onPressed: () => _editQwen3Voice(name, transcript),
                        tooltip: 'Edit',
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.delete,
                          size: 20,
                          color: Colors.red,
                        ),
                        onPressed: () => _deleteQwen3Voice(name),
                        tooltip: 'Delete',
                      ),
                    ],
                  ),
                  onTap: () => setState(() => _selectedQwen3Voice = name),
                ),
              );
            },
          ),
      ],
    );
  }

  Future<void> _deleteXttsVoice(String name) async {
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
        await _api.deleteXttsVoice(name);
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

  Future<void> _editXttsVoice(String name) async {
    final nameController = TextEditingController(text: name);

    final result = await showDialog<Map<String, dynamic>>(
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
            OutlinedButton.icon(
              onPressed: () async {
                final result = await FilePicker.platform.pickFiles(
                  type: FileType.audio,
                );
                if (result != null && result.files.single.path != null) {
                  Navigator.pop(context, {
                    'name': nameController.text,
                    'file': File(result.files.single.path!),
                  });
                }
              },
              icon: const Icon(Icons.upload_file),
              label: const Text('Replace Audio File'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(context, {'name': nameController.text}),
            child: const Text('Save Name'),
          ),
        ],
      ),
    );

    if (result != null) {
      try {
        await _api.updateXttsVoice(
          name,
          newName: result['name'] != name ? result['name'] as String : null,
          file: result['file'] as File?,
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

  Widget _buildXttsVoiceSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _selectedXttsVoice,
                decoration: const InputDecoration(
                  labelText: 'Speaker Voice',
                  border: OutlineInputBorder(),
                ),
                items: _xttsVoices.map((v) {
                  return DropdownMenuItem(
                    value: v['name'] as String,
                    child: Text(v['name'] as String),
                  );
                }).toList(),
                onChanged: (value) =>
                    setState(() => _selectedXttsVoice = value),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _uploadXttsVoice,
              icon: const Icon(Icons.add),
              tooltip: 'Upload voice sample',
            ),
          ],
        ),
        if (_xttsVoices.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text(
            'Manage voices:',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _xttsVoices.length,
            itemBuilder: (context, index) {
              final voice = _xttsVoices[index];
              final name = voice['name'] as String;
              final isSelected = name == _selectedXttsVoice;

              return Card(
                color: isSelected
                    ? Theme.of(context).colorScheme.primaryContainer
                    : null,
                child: ListTile(
                  leading: IconButton(
                    icon: const Icon(Icons.play_circle_outline),
                    onPressed: () async {
                      try {
                        final audioUrl = await _api.generateXtts(
                          text: 'Hello, this is a voice preview for $name.',
                          speakerId: name,
                          language: 'English',
                          speed: 0.8,
                        );
                        await _audioPlayer.setUrl(audioUrl);
                        await _audioPlayer.play();
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Preview failed: $e')),
                          );
                        }
                      }
                    },
                    tooltip: 'Preview',
                  ),
                  title: Text(
                    name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, size: 20),
                        onPressed: () => _editXttsVoice(name),
                        tooltip: 'Edit',
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.delete,
                          size: 20,
                          color: Colors.red,
                        ),
                        onPressed: () => _deleteXttsVoice(name),
                        tooltip: 'Delete',
                      ),
                    ],
                  ),
                  onTap: () => setState(() => _selectedXttsVoice = name),
                ),
              );
            },
          ),
        ],
      ],
    );
  }
}
