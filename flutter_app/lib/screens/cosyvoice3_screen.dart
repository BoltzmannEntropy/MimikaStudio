import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../services/api_service.dart';
import '../widgets/audio_player_widget.dart';
import '../widgets/model_status_banner.dart';

class _ExpressionPreset {
  const _ExpressionPreset({
    required this.id,
    required this.label,
    required this.description,
    required this.icon,
    required this.speedDelta,
    required this.stepsDelta,
    required this.silenceDeltaMs,
  });

  final String id;
  final String label;
  final String description;
  final IconData icon;
  final double speedDelta;
  final int stepsDelta;
  final int silenceDeltaMs;
}

class CosyVoice3Screen extends StatefulWidget {
  const CosyVoice3Screen({super.key});

  @override
  State<CosyVoice3Screen> createState() => _CosyVoice3ScreenState();
}

class _CosyVoice3ScreenState extends State<CosyVoice3Screen> {
  static const String _defaultText =
      'This is the strategic brief for the evening watch. Hold calm, keep the tone measured, '
      'and deliver each line with clear emphasis where risk escalates.';
  static const List<_ExpressionPreset> _expressionPresets = [
    _ExpressionPreset(
      id: 'neutral',
      label: 'Neutral',
      description: 'Balanced delivery for general narration.',
      icon: Icons.radio_button_checked_rounded,
      speedDelta: 0,
      stepsDelta: 0,
      silenceDeltaMs: 0,
    ),
    _ExpressionPreset(
      id: 'calm',
      label: 'Calm',
      description: 'Softer pace with extra pauses.',
      icon: Icons.spa_rounded,
      speedDelta: -0.14,
      stepsDelta: 1,
      silenceDeltaMs: 90,
    ),
    _ExpressionPreset(
      id: 'warm',
      label: 'Warm',
      description: 'Gentle and conversational.',
      icon: Icons.favorite_border_rounded,
      speedDelta: -0.07,
      stepsDelta: 1,
      silenceDeltaMs: 40,
    ),
    _ExpressionPreset(
      id: 'excited',
      label: 'Excited',
      description: 'Faster, energetic emphasis.',
      icon: Icons.bolt_rounded,
      speedDelta: 0.18,
      stepsDelta: 2,
      silenceDeltaMs: -100,
    ),
    _ExpressionPreset(
      id: 'serious',
      label: 'Serious',
      description: 'Deliberate pacing for authority.',
      icon: Icons.gavel_rounded,
      speedDelta: -0.09,
      stepsDelta: 2,
      silenceDeltaMs: 70,
    ),
    _ExpressionPreset(
      id: 'dramatic',
      label: 'Dramatic',
      description: 'Higher contrast and longer beats.',
      icon: Icons.auto_awesome_rounded,
      speedDelta: -0.03,
      stepsDelta: 4,
      silenceDeltaMs: 180,
    ),
  ];
  static const Map<String, String> _styleAlias = {
    'F1': 'Eden',
    'F2': 'Astra',
    'F3': 'Lyra',
    'F4': 'Nova',
    'F5': 'Iris',
    'M1': 'Orion',
    'M2': 'Atlas',
    'M3': 'Silas',
    'M4': 'Kai',
    'M5': 'Noah',
  };

  final ApiService _api = ApiService();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final TextEditingController _textController = TextEditingController();

  List<Map<String, dynamic>> _voices = [];
  List<String> _languages = [];
  List<Map<String, dynamic>> _pregeneratedSamples = [];
  Map<String, dynamic>? _systemInfo;

  String _selectedVoice = 'Eden';
  String _selectedLanguage = 'en';
  double _speed = 1.05;
  int _totalSteps = 5;
  bool _smartChunking = true;
  int _maxCharsPerChunk = 300;
  int _silenceMs = 300;
  String _selectedExpressionId = 'neutral';
  double _expressionIntensity = 0.7;

  bool _isLoading = false;
  bool _isGenerating = false;
  String? _audioUrl;
  String? _error;

  List<Map<String, dynamic>> _audioFiles = [];
  bool _isLoadingAudioFiles = false;
  String? _playingAudioId;
  bool _isAudioPaused = false;
  double _libraryPlaybackSpeed = 1.0;
  StreamSubscription<PlayerState>? _playerSubscription;

  @override
  void initState() {
    super.initState();
    _textController.text = _defaultText;
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

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final voicesData = await _api.getCosyVoice3Voices();
      final languageData = await _api.getCosyVoice3Languages();
      final systemInfo = await _api.getSystemInfo();
      List<Map<String, dynamic>> pregeneratedSamples = [];
      try {
        pregeneratedSamples = await _api.getPregeneratedSamples(
          engine: 'cosyvoice3',
        );
      } catch (e) {
        debugPrint('CosyVoice3 pregenerated samples not available: $e');
      }
      if (!mounted) return;
      final voices = List<Map<String, dynamic>>.from(
        voicesData['voices'] ?? [],
      );
      final languages = List<String>.from(
        languageData['languages'] ?? const ['en'],
      );
      setState(() {
        _voices = voices;
        _languages = languages;
        _pregeneratedSamples = pregeneratedSamples;
        _selectedVoice = voicesData['default'] as String? ?? _selectedVoice;
        if (!languages.contains(_selectedLanguage)) {
          _selectedLanguage = languages.isNotEmpty ? languages.first : 'en';
        }
        _systemInfo = systemInfo;
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
        _playingAudioId = null;
        _isAudioPaused = false;
      });
      await _audioPlayer.setUrl(audioUrl);
      await _audioPlayer.play();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to play sample: $e')));
    }
  }

  Future<void> _loadAudioFiles() async {
    setState(() => _isLoadingAudioFiles = true);
    try {
      final files = await _api.getCosyVoice3AudioFiles();
      if (!mounted) return;
      setState(() {
        _audioFiles = files;
        _isLoadingAudioFiles = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingAudioFiles = false);
    }
  }

  Future<void> _generateSpeech() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _isGenerating = true;
      _error = null;
    });

    try {
      final effectiveSpeed = _effectiveSpeed();
      final effectiveSteps = _effectiveTotalSteps();
      final effectiveSilenceMs = _effectiveSilenceMs();
      final audioUrl = await _api.generateCosyVoice3(
        text: text,
        voice: _selectedVoice,
        language: _selectedLanguage,
        speed: effectiveSpeed,
        totalSteps: effectiveSteps,
        smartChunking: _smartChunking,
        maxCharsPerChunk: _maxCharsPerChunk,
        silenceMs: effectiveSilenceMs,
      );

      if (!mounted) return;
      setState(() {
        _audioUrl = audioUrl;
        _isGenerating = false;
      });

      await _audioPlayer.setUrl(audioUrl);
      await _audioPlayer.play();
      _loadAudioFiles();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isGenerating = false;
      });
    }
  }

  _ExpressionPreset get _selectedExpression {
    for (final preset in _expressionPresets) {
      if (preset.id == _selectedExpressionId) {
        return preset;
      }
    }
    return _expressionPresets.first;
  }

  double _effectiveSpeed() {
    final adjusted =
        _speed + (_selectedExpression.speedDelta * _expressionIntensity);
    return adjusted.clamp(0.7, 2.0).toDouble();
  }

  int _effectiveTotalSteps() {
    final adjusted =
        _totalSteps + (_selectedExpression.stepsDelta * _expressionIntensity);
    return adjusted.round().clamp(2, 20).toInt();
  }

  int _effectiveSilenceMs() {
    final adjusted =
        _silenceMs +
        (_selectedExpression.silenceDeltaMs * _expressionIntensity).round();
    return adjusted.clamp(0, 800).toInt();
  }

  String _aliasVoice(String raw) {
    final trimmed = raw.trim();
    return _styleAlias[trimmed] ?? trimmed;
  }

  String _normalizeCosyLabel(String raw) {
    var out = raw.replaceAll('Supertonic', 'CosyVoice3');
    _styleAlias.forEach((style, alias) {
      out = out.replaceAll(style, alias);
    });
    return out;
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
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  color: Theme.of(context).colorScheme.tertiaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.bolt_rounded,
                              color: Theme.of(
                                context,
                              ).colorScheme.onTertiaryContainer,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'CosyVoice3',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onTertiaryContainer,
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.tertiary,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                'ONNX Runtime',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onTertiary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Emotionally expressive generation with preset voice styles.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context)
                                .colorScheme
                                .onTertiaryContainer
                                .withValues(alpha: 0.82),
                          ),
                        ),
                        if (_systemInfo != null) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 12,
                            runSpacing: 4,
                            children: [
                              _buildInfoChip(
                                Icons.memory,
                                _systemInfo!['device'] as String? ?? 'Unknown',
                              ),
                              _buildInfoChip(
                                Icons.code,
                                'Python ${_systemInfo!['python_version'] ?? '?'}',
                              ),
                              _buildInfoChip(
                                Icons.library_books,
                                _systemInfo!['models']?['cosyvoice3']?['model'] ??
                                    'ayousanz/cosy-voice3-onnx',
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
                  requiredModels: ['CosyVoice3'],
                  engineName: 'CosyVoice3',
                  themeColor: Colors.teal,
                ),
                if (_pregeneratedSamples.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _buildPregeneratedSamplesSection(),
                ],
                if (_audioUrl != null) ...[
                  AudioPlayerWidget(
                    player: _audioPlayer,
                    audioUrl: _audioUrl,
                    modelName: 'CosyVoice3',
                  ),
                  const SizedBox(height: 16),
                ],
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
                const Text(
                  'Preset Voices:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _voices.map((voice) {
                    final code = voice['code'] as String;
                    final name = (voice['name'] as String?) ?? code;
                    final gender = voice['gender'] as String? ?? 'female';
                    final isSelected = code == _selectedVoice;
                    return ChoiceChip(
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            gender == 'male' ? Icons.male : Icons.female,
                            size: 15,
                          ),
                          const SizedBox(width: 4),
                          Text(_aliasVoice(name)),
                        ],
                      ),
                      selected: isSelected,
                      onSelected: (selected) {
                        if (selected) {
                          setState(() => _selectedVoice = code);
                        }
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Expression:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _expressionPresets.map((preset) {
                    final selected = _selectedExpressionId == preset.id;
                    return ChoiceChip(
                      selected: selected,
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(preset.icon, size: 14),
                          const SizedBox(width: 4),
                          Text(preset.label),
                        ],
                      ),
                      onSelected: (value) {
                        if (value) {
                          setState(() => _selectedExpressionId = preset.id);
                        }
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 8),
                Text(
                  _selectedExpression.description,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
                Row(
                  children: [
                    const Icon(Icons.tune_rounded, size: 20),
                    const SizedBox(width: 8),
                    const Text('Intensity:'),
                    Expanded(
                      child: Slider(
                        value: _expressionIntensity,
                        min: 0.0,
                        max: 1.0,
                        divisions: 10,
                        label: (_expressionIntensity * 100).round().toString(),
                        onChanged: (value) =>
                            setState(() => _expressionIntensity = value),
                      ),
                    ),
                    Text('${(_expressionIntensity * 100).round()}%'),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Effective output: ${_effectiveSpeed().toStringAsFixed(2)}x speed · '
                  '${_effectiveTotalSteps()} steps · ${_effectiveSilenceMs()}ms pauses',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Language:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _languages.map((lang) {
                    final isSelected = lang == _selectedLanguage;
                    return ChoiceChip(
                      label: Text(lang.toUpperCase()),
                      selected: isSelected,
                      onSelected: (selected) {
                        if (selected) {
                          setState(() => _selectedLanguage = lang);
                        }
                      },
                    );
                  }).toList(),
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
                        min: 0.7,
                        max: 2.0,
                        divisions: 130,
                        label: '${_speed.toStringAsFixed(2)}x',
                        onChanged: (value) => setState(() => _speed = value),
                      ),
                    ),
                    Text('${_speed.toStringAsFixed(2)}x'),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.tune, size: 20),
                    const SizedBox(width: 8),
                    const Text('Quality steps:'),
                    Expanded(
                      child: Slider(
                        value: _totalSteps.toDouble(),
                        min: 2,
                        max: 20,
                        divisions: 18,
                        label: _totalSteps.toString(),
                        onChanged: (value) =>
                            setState(() => _totalSteps = value.round()),
                      ),
                    ),
                    Text(_totalSteps.toString()),
                  ],
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Chunking',
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
                                min: 120,
                                max: 800,
                                divisions: 34,
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
                              'Silence:',
                              style: TextStyle(fontSize: 12),
                            ),
                            Expanded(
                              child: Slider(
                                value: _silenceMs.toDouble(),
                                min: 0,
                                max: 800,
                                divisions: 32,
                                label: '${_silenceMs}ms',
                                onChanged: _smartChunking
                                    ? (v) =>
                                          setState(() => _silenceMs = v.round())
                                    : null,
                              ),
                            ),
                            Text('${_silenceMs}ms'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _textController,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    hintText: 'Enter text for CosyVoice3 generation...',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed:
                      _isGenerating || _textController.text.trim().isEmpty
                      ? null
                      : _generateSpeech,
                  icon: _isGenerating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow),
                  label: Text(
                    _isGenerating ? 'Generating...' : 'Generate Speech',
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
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
                Icon(Icons.record_voice_over, color: Colors.teal.shade600),
                const SizedBox(width: 8),
                const Text(
                  'CosyVoice3 Samples',
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
            ..._pregeneratedSamples.take(4).map((sample) {
              final voice = _aliasVoice(sample['voice'] as String? ?? 'Sample');
              final title = _normalizeCosyLabel(
                sample['title'] as String? ?? voice,
              );
              final description = sample['description'] as String? ?? '';
              final text = sample['text'] as String? ?? '';
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: InkWell(
                  onTap: () => _playPregeneratedSample(sample),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Theme.of(
                          context,
                        ).colorScheme.outline.withValues(alpha: 0.25),
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
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            voice,
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
                              if (text.isNotEmpty)
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
                        'No CosyVoice3 audio yet.\nGenerate speech to see it here.',
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
    final label = _normalizeCosyLabel(
      (file['label'] as String?) ?? 'CosyVoice3',
    );
    final duration = file['duration_seconds'] as num? ?? 0;
    final sizeMb = file['size_mb'] as num? ?? 0;
    final isThisPlaying = _playingAudioId == fileId;
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
              'COSYVOICE3 • $durationStr • ${sizeMb.toStringAsFixed(1)} MB',
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
        if (state.processingState == ProcessingState.completed && mounted) {
          setState(() {
            _playingAudioId = null;
            _isAudioPaused = false;
          });
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _playingAudioId = null;
        _isAudioPaused = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to play: $e')));
    }
  }

  Future<void> _pauseAudioPlayback() async {
    if (_playingAudioId == null) return;
    await _audioPlayer.pause();
    setState(() => _isAudioPaused = true);
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

    if (confirm != true) return;
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
      await _api.deleteCosyVoice3Audio(filename);
      _loadAudioFiles();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
    }
  }

  Future<void> _downloadAudioFile(Map<String, dynamic> file) async {
    final audioUrl = file['audio_url'] as String?;
    final filename = file['filename'] as String? ?? 'cosyvoice3-audio.wav';
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
