import 'dart:async';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../services/api_service.dart';
import '../widgets/audio_player_widget.dart';

class QuickTtsScreen extends StatefulWidget {
  const QuickTtsScreen({super.key});

  @override
  State<QuickTtsScreen> createState() => _QuickTtsScreenState();
}

class _QuickTtsScreenState extends State<QuickTtsScreen> {
  final ApiService _api = ApiService();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final TextEditingController _textController = TextEditingController();
  List<Map<String, dynamic>> _voices = [];
  List<Map<String, dynamic>> _voiceSamples = [];
  List<Map<String, dynamic>> _ipaSamples = [];
  Map<String, dynamic>? _systemInfo;
  Map<String, dynamic>? _selectedIpaSample;
  String _selectedVoice = 'bf_emma';
  double _speed = 1.0;
  String _audioModelLabel = 'Kokoro';

  // Smart chunking + merge
  bool _smartChunking = true;
  int _maxCharsPerChunk = 1500;
  int _crossfadeMs = 40;

  bool _isLoading = false;
  bool _isGenerating = false;
  bool _isGeneratingIpa = false;
  String? _audioUrl;
  String? _error;
  String? _ipaOutput;

  // Audio library state
  List<Map<String, dynamic>> _audioFiles = [];
  bool _isLoadingAudioFiles = false;
  String? _playingAudioId;
  bool _isAudioPaused = false;
  double _libraryPlaybackSpeed = 1.0;
  StreamSubscription<PlayerState>? _playerSubscription;

  // LLM selection for IPA
  String _selectedProvider = 'claude';
  String _selectedModel = 'claude-sonnet-4-20250514';
  List<String> _ollamaModels = [];
  final _providers = ['claude', 'openai', 'ollama', 'codex', 'claude_code_cli'];
  final Map<String, List<String>> _modelsByProvider = {
    'claude': ['claude-sonnet-4-20250514', 'claude-opus-4-20250514', 'claude-haiku-3-20240307'],
    'openai': ['gpt-4', 'gpt-4-turbo', 'gpt-3.5-turbo'],
    'ollama': [], // Will be populated dynamically
    'codex': ['codex-via-mcp'],
    'claude_code_cli': ['default'],
  };

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

      // Load IPA samples - handle gracefully if not available
      List<Map<String, dynamic>> ipaSamples = [];
      try {
        ipaSamples = await _api.getEmmaIpaSamples();
      } catch (e) {
        debugPrint('IPA samples not available: $e');
      }

      // Load Ollama models - handle gracefully
      List<String> ollamaModels = [];
      try {
        ollamaModels = await _api.getOllamaModels();
      } catch (e) {
        debugPrint('Ollama not available: $e');
      }

      setState(() {
        _voices = List<Map<String, dynamic>>.from(voicesData['voices']);
        _selectedVoice = voicesData['default'] ?? 'bf_emma';
        _voiceSamples = voiceSamples;
        _systemInfo = systemInfo;
        _ipaSamples = ipaSamples;
        _ollamaModels = ollamaModels;
        _modelsByProvider['ollama'] = ollamaModels.isNotEmpty ? ollamaModels : ['(no models found)'];
        _isLoading = false;

        // Load default IPA sample text
        final defaultSample = ipaSamples.firstWhere(
          (s) => s['is_default'] == true,
          orElse: () => ipaSamples.isNotEmpty ? ipaSamples.first : {},
        );
        if (defaultSample.isNotEmpty) {
          _selectIpaSample(defaultSample);
        }
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _selectIpaSample(Map<String, dynamic> sample) {
    setState(() {
      _selectedIpaSample = sample;
      _textController.text = sample['input_text'] ?? '';
      if (sample['has_preloaded_ipa'] == true) {
        _ipaOutput = sample['version1_ipa'] as String?;
      } else {
        _ipaOutput = null;
      }
    });
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
      setState(() {
        _error = e.toString();
        _isGenerating = false;
      });
    }
  }

  Future<void> _generateIpa() async {
    if (_textController.text.isEmpty) return;

    setState(() {
      _isGeneratingIpa = true;
      _error = null;
      _ipaOutput = null;
    });

    try {
      final result = await _api.generateEmmaIpa(
        text: _textController.text,
        provider: _selectedProvider,
        model: _selectedModel,
      );
      setState(() {
        _ipaOutput = result['ipa'] as String? ?? result['version1'] as String?;
        _isGeneratingIpa = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isGeneratingIpa = false;
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
        Text(
          text,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
        ),
      ],
    );
  }

  TextSpan _buildIpaTextSpan(String text) {
    final List<InlineSpan> spans = [];
    final RegExp boldPattern = RegExp(r'\*\*([^*]+)\*\*');

    int lastEnd = 0;
    for (final match in boldPattern.allMatches(text)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, match.start)));
      }
      spans.add(TextSpan(
        text: match.group(1),
        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.deepOrange),
      ));
      lastEnd = match.end;
    }
    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd)));
    }
    return TextSpan(children: spans);
  }

  String _providerLabel(String provider) {
    switch (provider) {
      case 'claude': return 'Claude';
      case 'openai': return 'OpenAI';
      case 'ollama': return 'Ollama';
      case 'codex': return 'Codex';
      case 'claude_code_cli': return 'Claude CLI';
      default: return provider;
    }
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
                        Icon(Icons.volume_up,
                            color: Theme.of(context).colorScheme.onSecondaryContainer),
                        const SizedBox(width: 8),
                        Text(
                          'Kokoro TTS',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onSecondaryContainer,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.secondary,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'British English',
                            style: TextStyle(
                              fontSize: 10,
                              color: Theme.of(context).colorScheme.onSecondary,
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
                          _buildInfoChip(Icons.memory, _systemInfo!['device'] ?? 'Unknown'),
                          _buildInfoChip(Icons.code, 'Python ${_systemInfo!['python_version'] ?? '?'}'),
                          _buildInfoChip(Icons.library_books, _systemInfo!['models']?['kokoro']?['model'] ?? 'Kokoro'),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),

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
                        Icon(Icons.record_voice_over,
                            color: Theme.of(context).colorScheme.tertiary,
                            size: 20),
                        const SizedBox(width: 8),
                        const Text('Voice Samples', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text('Instant Play', style: TextStyle(fontSize: 10, color: Colors.green)),
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
                              border: Border.all(color: Theme.of(context).colorScheme.outline.withOpacity(0.2)),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.tertiaryContainer,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    sample['voice_name'] as String,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(context).colorScheme.onTertiaryContainer,
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
            ),
            const SizedBox(height: 16),
          ],

          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Smart Chunking', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Enable smart chunking', style: TextStyle(fontSize: 12)),
                    value: _smartChunking,
                    onChanged: (value) => setState(() => _smartChunking = value),
                  ),
                  Row(
                    children: [
                      const Text('Max chars:', style: TextStyle(fontSize: 12)),
                      Expanded(
                        child: Slider(
                          value: _maxCharsPerChunk.toDouble(),
                          min: 400,
                          max: 4000,
                          divisions: 36,
                          label: _maxCharsPerChunk.toString(),
                          onChanged: _smartChunking
                              ? (v) => setState(() => _maxCharsPerChunk = v.round())
                              : null,
                        ),
                      ),
                      Text(_maxCharsPerChunk.toString()),
                    ],
                  ),
                  Row(
                    children: [
                      const Text('Crossfade:', style: TextStyle(fontSize: 12)),
                      Expanded(
                        child: Slider(
                          value: _crossfadeMs.toDouble(),
                          min: 0,
                          max: 200,
                          divisions: 20,
                          label: '${_crossfadeMs}ms',
                          onChanged: _smartChunking
                              ? (v) => setState(() => _crossfadeMs = v.round())
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
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            ),
            const SizedBox(height: 16),
          ],

          ...[
            // British Voices Selection
            const Text('British Voices:', style: TextStyle(fontWeight: FontWeight.bold)),
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
                      Icon(gender == 'female' ? Icons.female : Icons.male, size: 16),
                      const SizedBox(width: 4),
                      Text(name),
                      const SizedBox(width: 4),
                      Text('($grade)', style: TextStyle(fontSize: 10, color: isSelected ? null : Colors.grey)),
                    ],
                  ),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) setState(() => _selectedVoice = code);
                  },
                  avatar: voice['is_default'] == true ? const Icon(Icons.star, size: 16) : null,
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
                    divisions: 15,
                    label: '${_speed.toStringAsFixed(1)}x',
                    onChanged: (value) => setState(() => _speed = value),
                  ),
                ),
                Text('${_speed.toStringAsFixed(1)}x'),
              ],
            ),
            const SizedBox(height: 16),
          ],

          ...[
            // Emma IPA Section Header
            Card(
              color: Theme.of(context).colorScheme.tertiaryContainer.withOpacity(0.3),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.indigo,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'Emma IPA',
                        style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text('British Phonetic Transcription', style: TextStyle(fontWeight: FontWeight.bold)),
                    const Spacer(),
                    // LLM Provider dropdown
                    SizedBox(
                      width: 100,
                      child: DropdownButtonFormField<String>(
                        value: _selectedProvider,
                        decoration: const InputDecoration(
                          labelText: 'LLM',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          isDense: true,
                        ),
                        items: _providers.map((p) {
                          return DropdownMenuItem(value: p, child: Text(_providerLabel(p), style: const TextStyle(fontSize: 11)));
                        }).toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              _selectedProvider = value;
                              final models = _modelsByProvider[value] ?? ['default'];
                              _selectedModel = models.isNotEmpty ? models.first : 'default';
                            });
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Model dropdown
                    SizedBox(
                      width: 160,
                      child: DropdownButtonFormField<String>(
                        value: (_modelsByProvider[_selectedProvider]?.contains(_selectedModel) ?? false)
                            ? _selectedModel
                            : (_modelsByProvider[_selectedProvider]?.isNotEmpty ?? false)
                                ? _modelsByProvider[_selectedProvider]!.first
                                : null,
                        decoration: const InputDecoration(
                          labelText: 'Model',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          isDense: true,
                        ),
                        items: (_modelsByProvider[_selectedProvider] ?? []).map((m) {
                          final displayName = m.length > 20 ? '${m.substring(0, 18)}...' : m;
                          return DropdownMenuItem(value: m, child: Text(displayName, style: const TextStyle(fontSize: 11)));
                        }).toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _selectedModel = value);
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Sample text selector chips
            if (_ipaSamples.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _ipaSamples.map((sample) {
                  final isSelected = _selectedIpaSample?['id'] == sample['id'];
                  final hasPreloadedIpa = sample['has_preloaded_ipa'] == true;
                  return ActionChip(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(sample['title'] ?? 'Sample', style: TextStyle(fontSize: 12, color: isSelected ? Colors.white : null)),
                        if (hasPreloadedIpa) ...[
                          const SizedBox(width: 4),
                          Icon(Icons.check_circle, size: 14, color: isSelected ? Colors.white : Colors.green),
                        ],
                      ],
                    ),
                    backgroundColor: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : hasPreloadedIpa ? Colors.green.shade50 : null,
                    onPressed: () => _selectIpaSample(sample),
                  );
                }).toList(),
              ),
            const SizedBox(height: 12),
          ],

          // Main Text Input (editable Emma IPA text)
          TextField(
            controller: _textController,
            maxLines: 6,
            decoration: const InputDecoration(
              hintText: 'Enter text for TTS and IPA transcription...',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) {
              if (_selectedIpaSample != null && _textController.text != _selectedIpaSample!['input_text']) {
                setState(() {
                  _selectedIpaSample = null;
                  _ipaOutput = null;
                });
              }
            },
          ),
          const SizedBox(height: 12),

          // Action buttons: Generate Speech and Generate IPA
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _isGenerating || _textController.text.isEmpty ? null : _generateSpeech,
                  icon: _isGenerating
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.play_arrow),
                  label: Text(_isGenerating ? 'Generating...' : 'Generate Speech'),
                ),
              ),
              ...[
                const SizedBox(width: 12),
                FilledButton.tonalIcon(
                  onPressed: _isGeneratingIpa || _textController.text.isEmpty ? null : _generateIpa,
                  icon: _isGeneratingIpa
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.auto_awesome),
                  label: Text(_isGeneratingIpa ? 'Generating...' : 'Generate IPA'),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),

          // IPA Output
          if (_ipaOutput != null)
            Card(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.indigo,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'British IPA',
                            style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text('Phonetic Transcription', style: TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SelectableText.rich(
                      _buildIpaTextSpan(_ipaOutput!),
                      style: const TextStyle(fontSize: 14, height: 1.6),
                    ),
                  ],
                ),
              ),
            ),

          // Placeholder when no IPA output
          if (_ipaOutput == null && !_isGeneratingIpa)
            Card(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              child: const Padding(
                padding: EdgeInsets.all(32),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.record_voice_over, size: 48, color: Colors.grey),
                      SizedBox(height: 12),
                      Text(
                        'Enter text and click "Generate IPA" to create\nBritish IPA-like transcriptions',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ),
            ),
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
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
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
    final label = (file['label'] as String?) ?? (file['voice'] as String?) ?? 'Unknown';
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
              color: isThisPlaying ? Theme.of(context).colorScheme.primary : null,
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to play: $e')),
        );
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete: $e')),
          );
        }
      }
    }
  }
}
