import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../services/api_service.dart';

/// Widget for Emma IPA British transcription generation
class EmmaIpaWidget extends StatefulWidget {
  final ApiService api;
  final Map<String, dynamic>? llmConfig;

  const EmmaIpaWidget({
    super.key,
    required this.api,
    this.llmConfig,
  });

  @override
  State<EmmaIpaWidget> createState() => _EmmaIpaWidgetState();
}

class _EmmaIpaWidgetState extends State<EmmaIpaWidget> {
  final TextEditingController _textController = TextEditingController();
  final AudioPlayer _audioPlayer = AudioPlayer();

  List<Map<String, dynamic>> _samples = [];
  Map<String, dynamic>? _selectedSample;
  bool _isLoading = false;
  bool _isGenerating = false;
  bool _isLoadingAudio = false;
  String? _error;
  String? _currentAudioUrl;

  // Audio player state
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  // Generated IPA output (single version)
  String? _ipaOutput;

  // LLM selection
  String _selectedProvider = 'claude';
  String _selectedModel = 'claude-sonnet-4-20250514';

  final _providers = ['claude', 'openai', 'ollama', 'claude_code_cli'];
  final _modelsByProvider = {
    'claude': ['claude-sonnet-4-20250514', 'claude-opus-4-20250514', 'claude-haiku-3-20240307'],
    'openai': ['gpt-4', 'gpt-4-turbo', 'gpt-3.5-turbo'],
    'ollama': ['llama3.2', 'llama3.1', 'mistral'],
    'claude_code_cli': ['default'],
  };

  @override
  void initState() {
    super.initState();
    _loadSamples();
    _initFromConfig();
    _setupAudioListeners();
  }

  void _setupAudioListeners() {
    _audioPlayer.playerStateStream.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state.playing;
          if (state.processingState == ProcessingState.completed) {
            _isPlaying = false;
            _position = Duration.zero;
          }
        });
      }
    });

    _audioPlayer.positionStream.listen((position) {
      if (mounted) {
        setState(() => _position = position);
      }
    });

    _audioPlayer.durationStream.listen((duration) {
      if (mounted && duration != null) {
        setState(() => _duration = duration);
      }
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  void _initFromConfig() {
    if (widget.llmConfig != null) {
      setState(() {
        _selectedProvider = widget.llmConfig!['provider'] ?? 'claude';
        _selectedModel = widget.llmConfig!['model'] ?? 'claude-sonnet-4-20250514';
      });
    }
  }

  Future<void> _loadSamples() async {
    setState(() => _isLoading = true);
    try {
      final samples = await widget.api.getEmmaIpaSamples();
      setState(() {
        _samples = samples;
        _isLoading = false;
        // Select default sample if available
        final defaultSample = samples.firstWhere(
          (s) => s['is_default'] == true,
          orElse: () => samples.isNotEmpty ? samples.first : {},
        );
        if (defaultSample.isNotEmpty) {
          _selectSample(defaultSample);
        }
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _selectSample(Map<String, dynamic> sample) {
    setState(() {
      _selectedSample = sample;
      _textController.text = sample['input_text'] ?? '';
      // Load preloaded IPA if available (use version1_ipa)
      if (sample['has_preloaded_ipa'] == true) {
        _ipaOutput = sample['version1_ipa'] as String?;
      } else {
        _ipaOutput = null;
      }
      // Reset audio state
      _currentAudioUrl = null;
      _isPlaying = false;
      _position = Duration.zero;
      _duration = Duration.zero;
    });
  }

  Future<void> _generateIpa() async {
    if (_textController.text.isEmpty) return;

    setState(() {
      _isGenerating = true;
      _error = null;
      _ipaOutput = null;
    });

    try {
      final result = await widget.api.generateEmmaIpa(
        text: _textController.text,
        provider: _selectedProvider,
        model: _selectedModel,
      );
      setState(() {
        // Use version1 (or ipa field if backend is updated)
        _ipaOutput = result['ipa'] as String? ?? result['version1'] as String?;
        _isGenerating = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isGenerating = false;
      });
    }
  }

  Future<void> _loadAndPlayAudio() async {
    if (_textController.text.isEmpty) return;

    setState(() => _isLoadingAudio = true);

    try {
      String audioUrl;
      if (_selectedSample != null && _selectedSample!['audio_url'] != null) {
        // Use preloaded audio
        audioUrl = widget.api.getPregeneratedAudioUrl(_selectedSample!['audio_url']);
      } else {
        // Generate audio on demand using Kokoro Lily voice
        audioUrl = await widget.api.generateKokoro(
          text: _textController.text,
          voice: 'bf_lily',
          speed: 1.0,
        );
      }

      setState(() {
        _currentAudioUrl = audioUrl;
        _isLoadingAudio = false;
      });

      await _audioPlayer.setUrl(audioUrl);
      await _audioPlayer.play();
    } catch (e) {
      setState(() => _isLoadingAudio = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Audio failed: $e')),
        );
      }
    }
  }

  void _togglePlayPause() async {
    if (_currentAudioUrl == null) {
      // First time - load and play
      await _loadAndPlayAudio();
    } else if (_isPlaying) {
      await _audioPlayer.pause();
    } else {
      await _audioPlayer.play();
    }
  }

  void _stopAudio() async {
    await _audioPlayer.stop();
    setState(() {
      _position = Duration.zero;
      _isPlaying = false;
    });
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Input section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header row with LLM selector
                  Row(
                    children: [
                      const Icon(Icons.text_fields, size: 20),
                      const SizedBox(width: 8),
                      const Text(
                        'Input Text',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const Spacer(),
                      // LLM Provider dropdown
                      SizedBox(
                        width: 140,
                        child: DropdownButtonFormField<String>(
                          value: _selectedProvider,
                          decoration: const InputDecoration(
                            labelText: 'LLM',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            isDense: true,
                          ),
                          items: _providers.map((p) {
                            return DropdownMenuItem(
                              value: p,
                              child: Text(_providerLabel(p), style: const TextStyle(fontSize: 12)),
                            );
                          }).toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setState(() {
                                _selectedProvider = value;
                                _selectedModel = _modelsByProvider[value]?.first ?? 'default';
                              });
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Model dropdown
                      SizedBox(
                        width: 180,
                        child: DropdownButtonFormField<String>(
                          value: _modelsByProvider[_selectedProvider]?.contains(_selectedModel) == true
                              ? _selectedModel
                              : _modelsByProvider[_selectedProvider]?.first,
                          decoration: const InputDecoration(
                            labelText: 'Model',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            isDense: true,
                          ),
                          items: (_modelsByProvider[_selectedProvider] ?? ['default']).map((m) {
                            return DropdownMenuItem(
                              value: m,
                              child: Text(m, style: const TextStyle(fontSize: 11)),
                            );
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
                  const SizedBox(height: 12),

                  // Sample text selector
                  if (_samples.isNotEmpty)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _samples.map((sample) {
                        final isSelected = _selectedSample?['id'] == sample['id'];
                        final hasPreloadedIpa = sample['has_preloaded_ipa'] == true;
                        final hasAudio = sample['has_audio'] == true;
                        return ActionChip(
                          label: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                sample['title'] ?? 'Sample',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isSelected ? Colors.white : null,
                                ),
                              ),
                              if (hasPreloadedIpa) ...[
                                const SizedBox(width: 4),
                                Icon(
                                  Icons.check_circle,
                                  size: 14,
                                  color: isSelected ? Colors.white : Colors.green,
                                ),
                              ],
                            ],
                          ),
                          backgroundColor: isSelected
                              ? Theme.of(context).colorScheme.primary
                              : hasPreloadedIpa
                                  ? Colors.green.shade50
                                  : null,
                          avatar: hasAudio
                              ? Icon(
                                  Icons.audiotrack,
                                  size: 16,
                                  color: isSelected ? Colors.white : Colors.green,
                                )
                              : null,
                          onPressed: () => _selectSample(sample),
                        );
                      }).toList(),
                    ),
                  const SizedBox(height: 12),

                  // Text input
                  TextField(
                    controller: _textController,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      hintText: 'Enter text for IPA transcription...',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) {
                      // Clear selection when user edits
                      if (_selectedSample != null && _textController.text != _selectedSample!['input_text']) {
                        setState(() {
                          _selectedSample = null;
                          _currentAudioUrl = null;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 12),

                  // Audio player controls (like Kokoro TTS)
                  if (_currentAudioUrl != null || _isLoadingAudio)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              // Play/Pause button
                              IconButton(
                                onPressed: _isLoadingAudio ? null : _togglePlayPause,
                                icon: _isLoadingAudio
                                    ? const SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : Icon(_isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled),
                                iconSize: 40,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              // Stop button
                              IconButton(
                                onPressed: _stopAudio,
                                icon: const Icon(Icons.stop_circle),
                                iconSize: 32,
                                color: Theme.of(context).colorScheme.error,
                              ),
                              const SizedBox(width: 8),
                              // Progress bar
                              Expanded(
                                child: Column(
                                  children: [
                                    SliderTheme(
                                      data: SliderTheme.of(context).copyWith(
                                        trackHeight: 4,
                                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                      ),
                                      child: Slider(
                                        value: _duration.inMilliseconds > 0
                                            ? _position.inMilliseconds / _duration.inMilliseconds
                                            : 0,
                                        onChanged: (value) async {
                                          final newPosition = Duration(
                                            milliseconds: (value * _duration.inMilliseconds).toInt(),
                                          );
                                          await _audioPlayer.seek(newPosition);
                                        },
                                      ),
                                    ),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          _formatDuration(_position),
                                          style: const TextStyle(fontSize: 11),
                                        ),
                                        const Text('Lily Voice', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                        Text(
                                          _formatDuration(_duration),
                                          style: const TextStyle(fontSize: 11),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 12),

                  // Action buttons
                  Row(
                    children: [
                      // Play Lily button (loads audio if not loaded)
                      FilledButton.tonalIcon(
                        onPressed: _isLoadingAudio || _textController.text.isEmpty
                            ? null
                            : _togglePlayPause,
                        icon: _isLoadingAudio
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Icon(_isPlaying ? Icons.pause : Icons.volume_up, size: 18),
                        label: Text(_isPlaying ? 'Pause' : 'Play Lily'),
                      ),
                      const Spacer(),
                      // Generate button
                      FilledButton.icon(
                        onPressed: _isGenerating || _textController.text.isEmpty
                            ? null
                            : _generateIpa,
                        icon: _isGenerating
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.auto_awesome, size: 18),
                        label: Text(_isGenerating ? 'Generating...' : 'Generate IPA'),
                      ),
                    ],
                  ),

                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Output section - single card (no version 2)
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
                        const Text(
                          'Phonetic Transcription',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
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

          // Placeholder when no output yet
          if (_ipaOutput == null && !_isGenerating)
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
    );
  }

  /// Parse markdown-style bold (**text**) and return a TextSpan with bold formatting
  TextSpan _buildIpaTextSpan(String text) {
    final List<InlineSpan> spans = [];
    final RegExp boldPattern = RegExp(r'\*\*([^*]+)\*\*');

    int lastEnd = 0;
    for (final match in boldPattern.allMatches(text)) {
      // Add text before the match
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, match.start)));
      }
      // Add bold text
      spans.add(TextSpan(
        text: match.group(1),
        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.deepOrange),
      ));
      lastEnd = match.end;
    }

    // Add remaining text
    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd)));
    }

    return TextSpan(children: spans);
  }

  String _providerLabel(String provider) {
    switch (provider) {
      case 'claude':
        return 'Claude';
      case 'openai':
        return 'OpenAI';
      case 'ollama':
        return 'Ollama';
      case 'claude_code_cli':
        return 'Claude CLI';
      default:
        return provider;
    }
  }
}
