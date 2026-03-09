import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../services/api_service.dart';

class VoicePromptManagementScreen extends StatefulWidget {
  const VoicePromptManagementScreen({super.key});

  @override
  State<VoicePromptManagementScreen> createState() =>
      _VoicePromptManagementScreenState();
}

class _VoicePromptManagementScreenState
    extends State<VoicePromptManagementScreen> {
  final ApiService _api = ApiService();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final AudioPlayer _youtubePreviewPlayer = AudioPlayer();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _youtubeUrlController = TextEditingController();
  final TextEditingController _youtubeStartController = TextEditingController();
  final TextEditingController _youtubeNameController = TextEditingController();
  final TextEditingController _youtubeTranscriptController =
      TextEditingController();
  final TextEditingController _youtubeGenderController =
      TextEditingController();
  final TextEditingController _youtubeLanguageController =
      TextEditingController();

  List<Map<String, dynamic>> _voices = [];
  bool _isLoading = false;
  bool _isUploading = false;
  String? _error;

  String _sortBy = 'name';
  String _sortOrder = 'asc';
  String _genderFilter = '';
  String _languageFilter = '';
  String _sourceFilter = '';

  String? _previewingName;
  bool _isPreviewPaused = false;
  StreamSubscription<PlayerState>? _previewSubscription;
  StreamSubscription<PlayerState>? _youtubePreviewSubscription;

  bool _isYoutubeDownloading = false;
  bool _isYoutubeCommitting = false;
  String? _youtubePreviewId;
  String? _youtubePreviewAudioUrl;
  double? _youtubePreviewDurationSec;
  bool _isYoutubePreviewPaused = false;
  String? _youtubeImportError;

  @override
  void initState() {
    super.initState();
    _loadVoices();
  }

  @override
  void dispose() {
    _previewSubscription?.cancel();
    _youtubePreviewSubscription?.cancel();
    _audioPlayer.dispose();
    _youtubePreviewPlayer.dispose();
    _searchController.dispose();
    _youtubeUrlController.dispose();
    _youtubeStartController.dispose();
    _youtubeNameController.dispose();
    _youtubeTranscriptController.dispose();
    _youtubeGenderController.dispose();
    _youtubeLanguageController.dispose();
    super.dispose();
  }

  Future<void> _loadVoices() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final voices = await _api.getVoicePrompts(
        search: _searchController.text,
        gender: _genderFilter,
        language: _languageFilter,
        source: _sourceFilter,
        sortBy: _sortBy,
        sortOrder: _sortOrder,
      );
      if (!mounted) return;
      setState(() {
        _voices = voices;
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

  bool _voiceNameExists(String name, {String? excludeName}) {
    final target = name.trim().toLowerCase();
    final excluded = excludeName?.trim().toLowerCase() ?? '';
    for (final voice in _voices) {
      final current = (voice['name']?.toString() ?? '').trim().toLowerCase();
      if (current.isEmpty || current == excluded) continue;
      if (current == target) return true;
    }
    return false;
  }

  String? _validateVoiceName(String name) {
    final clean = name.trim();
    if (clean.isEmpty) return 'Voice name is required';
    final namePattern = RegExp(r'^[A-Za-z0-9_-]+$');
    if (!namePattern.hasMatch(clean)) {
      return 'Use only letters, numbers, "_" and "-" for voice names';
    }
    return null;
  }

  Future<String?> _validateVoiceNameAvailability(
    String name, {
    String? excludeName,
  }) async {
    final clean = name.trim();
    if (_voiceNameExists(clean, excludeName: excludeName)) {
      return 'Voice "$clean" already exists';
    }
    try {
      final allVoices = await _api.getVoicePrompts(
        sortBy: 'name',
        sortOrder: 'asc',
      );
      final target = clean.toLowerCase();
      final excluded = excludeName?.trim().toLowerCase() ?? '';
      for (final voice in allVoices) {
        final current = (voice['name']?.toString() ?? '').trim().toLowerCase();
        if (current.isEmpty || current == excluded) continue;
        if (current == target) {
          return 'Voice "$clean" already exists';
        }
      }
    } catch (e) {
      debugPrint('Remote voice-name validation failed: $e');
    }
    return null;
  }

  Future<void> _uploadVoicePrompt() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['wav', 'wave'],
      withData: true,
    );
    if (result == null ||
        result.files.isEmpty ||
        result.files.single.bytes == null) {
      return;
    }

    final payload = await _showVoiceEditorDialog(
      title: 'Upload Voice Prompt',
      initialName: result.files.single.name.split('.').first,
      initialTranscript: '',
      initialGender: '',
      initialLanguage: '',
      initialSource: 'local',
    );
    if (payload == null) {
      return;
    }
    final nameError = _validateVoiceName(payload['name'] ?? '');
    if (nameError != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(nameError)));
      return;
    }
    final availabilityError = await _validateVoiceNameAvailability(
      payload['name'] ?? '',
    );
    if (availabilityError != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(availabilityError)));
      return;
    }

    setState(() => _isUploading = true);
    try {
      await _api.uploadVoicePrompt(
        name: payload['name']!,
        fileBytes: result.files.single.bytes!,
        fileName: result.files.single.name,
        transcript: payload['transcript'] ?? '',
        gender: payload['gender'] ?? '',
        language: payload['language'] ?? '',
        source: payload['source'] ?? 'local',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Voice prompt uploaded')));
      await _loadVoices();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  Future<void> _downloadYoutubePreview() async {
    final url = _youtubeUrlController.text.trim();
    if (url.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('YouTube URL is required')),
      );
      return;
    }

    final startRaw = _youtubeStartController.text.trim();
    final parsedStart = startRaw.isEmpty ? null : double.tryParse(startRaw);
    if (startRaw.isNotEmpty && parsedStart == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Start seconds must be a number')),
      );
      return;
    }

    setState(() {
      _isYoutubeDownloading = true;
      _youtubeImportError = null;
    });
    try {
      final previousPreviewId = _youtubePreviewId;
      if (previousPreviewId != null && previousPreviewId.isNotEmpty) {
        unawaited(_api.deleteYoutubeVoicePromptPreview(previousPreviewId));
      }
      await _stopYoutubePreview();
      final response = await _api.previewVoicePromptFromYoutube(
        url: url,
        startSec: parsedStart,
      );
      if (!mounted) return;
      setState(() {
        _youtubePreviewId = response['preview_id']?.toString();
        final audioPath = response['audio_url']?.toString() ?? '';
        _youtubePreviewAudioUrl = audioPath.startsWith('http')
            ? audioPath
            : '${ApiService.baseUrl}$audioPath';
        _youtubePreviewDurationSec =
            (response['duration_sec'] as num?)?.toDouble();
        _isYoutubePreviewPaused = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preview ready. Listen before saving.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _youtubeImportError = e.toString());
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('YouTube preview failed: $e')));
    } finally {
      if (mounted) {
        setState(() => _isYoutubeDownloading = false);
      }
    }
  }

  Future<void> _saveYoutubePreviewAsVoicePrompt() async {
    final previewId = (_youtubePreviewId ?? '').trim();
    if (previewId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Download a preview first')),
      );
      return;
    }

    final name = _youtubeNameController.text.trim();
    final nameError = _validateVoiceName(name);
    if (nameError != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(nameError)));
      return;
    }
    final availabilityError = await _validateVoiceNameAvailability(name);
    if (availabilityError != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(availabilityError)));
      return;
    }

    setState(() => _isYoutubeCommitting = true);
    try {
      await _api.commitYoutubeVoicePrompt(
        previewId: previewId,
        name: name,
        transcript: _youtubeTranscriptController.text.trim(),
        gender: _youtubeGenderController.text.trim(),
        language: _youtubeLanguageController.text.trim(),
      );
      if (!mounted) return;
      await _stopYoutubePreview();
      setState(() {
        _youtubePreviewId = null;
        _youtubePreviewAudioUrl = null;
        _youtubePreviewDurationSec = null;
        _youtubeImportError = null;
      });
      _youtubeNameController.clear();
      _youtubeTranscriptController.clear();
      _youtubeGenderController.clear();
      _youtubeLanguageController.clear();
      await _loadVoices();
      if (!mounted) return;
      DefaultTabController.maybeOf(context)?.animateTo(0);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('YouTube voice imported successfully')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _youtubeImportError = e.toString());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save voice prompt: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isYoutubeCommitting = false);
      }
    }
  }

  Future<void> _playYoutubePreview() async {
    final url = (_youtubePreviewAudioUrl ?? '').trim();
    if (url.isEmpty) return;
    try {
      if (_isYoutubePreviewPaused) {
        setState(() => _isYoutubePreviewPaused = false);
        await _youtubePreviewPlayer.play();
        return;
      }
      await _youtubePreviewSubscription?.cancel();
      _youtubePreviewSubscription = null;
      await _youtubePreviewPlayer.stop();
      await _youtubePreviewPlayer.setUrl(url);
      if (!mounted) return;
      setState(() => _isYoutubePreviewPaused = false);
      _youtubePreviewSubscription = _youtubePreviewPlayer.playerStateStream
          .listen((state) {
            if (state.processingState == ProcessingState.completed && mounted) {
              setState(() => _isYoutubePreviewPaused = false);
            }
          });
      await _youtubePreviewPlayer.play();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Preview playback failed: $e')),
      );
    }
  }

  Future<void> _pauseYoutubePreview() async {
    await _youtubePreviewPlayer.pause();
    if (mounted) {
      setState(() => _isYoutubePreviewPaused = true);
    }
  }

  Future<void> _stopYoutubePreview() async {
    await _youtubePreviewSubscription?.cancel();
    _youtubePreviewSubscription = null;
    await _youtubePreviewPlayer.stop();
    if (mounted) {
      setState(() => _isYoutubePreviewPaused = false);
    }
  }

  Future<void> _editVoicePrompt(Map<String, dynamic> voice) async {
    final name = voice['name']?.toString() ?? '';
    if (name.isEmpty) return;

    final payload = await _showVoiceEditorDialog(
      title: 'Edit Voice Prompt',
      initialName: name,
      initialTranscript: voice['transcript']?.toString() ?? '',
      initialGender: voice['gender']?.toString() ?? '',
      initialLanguage: voice['language']?.toString() ?? '',
      initialSource: voice['source']?.toString() ?? 'local',
    );
    if (payload == null) return;
    final nameError = _validateVoiceName(payload['name'] ?? '');
    if (nameError != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(nameError)));
      return;
    }
    final availabilityError = await _validateVoiceNameAvailability(
      payload['name'] ?? '',
      excludeName: name,
    );
    if (availabilityError != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(availabilityError)));
      return;
    }

    try {
      await _api.updateVoicePrompt(
        name,
        newName: payload['name'] != name ? payload['name'] : null,
        transcript: payload['transcript'],
        gender: payload['gender'],
        language: payload['language'],
        source: payload['source'],
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Voice prompt updated')));
      await _loadVoices();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Update failed: $e')));
    }
  }

  Future<void> _deleteVoicePrompt(String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Voice Prompt'),
        content: Text('Delete "$name"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _api.deleteVoicePrompt(name);
      if (!mounted) return;
      if (_previewingName == name) {
        await _stopPreview();
        if (!mounted) return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Voice prompt deleted')));
      await _loadVoices();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    }
  }

  Future<void> _previewVoice(String name) async {
    if (_previewingName == name && _isPreviewPaused) {
      setState(() => _isPreviewPaused = false);
      await _audioPlayer.play();
      return;
    }

    try {
      await _previewSubscription?.cancel();
      _previewSubscription = null;
      await _audioPlayer.stop();
      final url = _api.getVoicePromptAudioUrl(name);
      await _audioPlayer.setUrl(url);
      if (!mounted) return;
      setState(() {
        _previewingName = name;
        _isPreviewPaused = false;
      });
      _previewSubscription = _audioPlayer.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed && mounted) {
          setState(() {
            _previewingName = null;
            _isPreviewPaused = false;
          });
        }
      });
      unawaited(_audioPlayer.play());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Preview failed: $e')));
    }
  }

  Future<void> _pausePreview() async {
    await _audioPlayer.pause();
    if (mounted) {
      setState(() => _isPreviewPaused = true);
    }
  }

  Future<void> _stopPreview() async {
    await _previewSubscription?.cancel();
    _previewSubscription = null;
    await _audioPlayer.stop();
    if (mounted) {
      setState(() {
        _previewingName = null;
        _isPreviewPaused = false;
      });
    }
  }

  Future<Map<String, String>?> _showVoiceEditorDialog({
    required String title,
    required String initialName,
    required String initialTranscript,
    required String initialGender,
    required String initialLanguage,
    required String initialSource,
  }) async {
    final nameController = TextEditingController(text: initialName);
    final transcriptController = TextEditingController(text: initialTranscript);
    final genderController = TextEditingController(text: initialGender);
    final languageController = TextEditingController(text: initialLanguage);
    String source = initialSource;

    try {
      return await showDialog<Map<String, String>>(
        context: context,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                title: Text(title),
                content: SizedBox(
                  width: 520,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(labelText: 'Name'),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: transcriptController,
                              maxLines: 2,
                              decoration: const InputDecoration(
                                labelText: 'Transcript',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: genderController,
                              decoration: const InputDecoration(
                                labelText: 'Gender',
                                hintText: 'female / male / neutral',
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: languageController,
                              decoration: const InputDecoration(
                                labelText: 'Language',
                                hintText: 'English',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: source == 'external'
                            ? 'external'
                            : 'local',
                        items: const [
                          DropdownMenuItem(
                            value: 'local',
                            child: Text('Local'),
                          ),
                          DropdownMenuItem(
                            value: 'external',
                            child: Text('External'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setDialogState(() => source = value);
                        },
                        decoration: const InputDecoration(labelText: 'Source'),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () {
                      final cleanName = nameController.text.trim();
                      if (cleanName.isEmpty) return;
                      Navigator.of(context).pop({
                        'name': cleanName,
                        'transcript': transcriptController.text.trim(),
                        'gender': genderController.text.trim(),
                        'language': languageController.text.trim(),
                        'source': source.trim().isEmpty
                            ? 'local'
                            : source.trim(),
                      });
                    },
                    child: const Text('Save'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      nameController.dispose();
      transcriptController.dispose();
      genderController.dispose();
      languageController.dispose();
    }
  }

  void _toggleSort(String sortBy) {
    setState(() {
      if (_sortBy == sortBy) {
        _sortOrder = _sortOrder == 'asc' ? 'desc' : 'asc';
      } else {
        _sortBy = sortBy;
        _sortOrder = 'asc';
      }
    });
    _loadVoices();
  }

  @override
  Widget build(BuildContext context) {
    final genders = <String>{
      for (final v in _voices)
        if ((v['gender']?.toString().trim() ?? '').isNotEmpty)
          v['gender'].toString().trim(),
    }.toList()..sort();
    final languages = <String>{
      for (final v in _voices)
        if ((v['language']?.toString().trim() ?? '').isNotEmpty)
          v['language'].toString().trim(),
    }.toList()..sort();

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              border: Border(
                bottom: BorderSide(color: Theme.of(context).dividerColor),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.library_music_rounded),
                    SizedBox(width: 8),
                    Text(
                      'Voice Prompt Management',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const TabBar(
                  tabs: [
                    Tab(text: 'Voice Library'),
                    Tab(text: 'Import YouTube'),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildVoiceLibraryTab(genders: genders, languages: languages),
                _buildYoutubeImportTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVoiceLibraryTab({
    required List<String> genders,
    required List<String> languages,
  }) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            border: Border(
              bottom: BorderSide(color: Theme.of(context).dividerColor),
            ),
          ),
          child: Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 260,
                child: TextField(
                  controller: _searchController,
                  onSubmitted: (_) => _loadVoices(),
                  decoration: InputDecoration(
                    hintText: 'Search by name',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    isDense: true,
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.refresh, size: 18),
                      onPressed: _loadVoices,
                    ),
                  ),
                ),
              ),
              _buildFilterDropdown(
                label: 'Gender',
                value: _genderFilter,
                values: genders,
                onChanged: (value) {
                  setState(() => _genderFilter = value ?? '');
                  _loadVoices();
                },
              ),
              _buildFilterDropdown(
                label: 'Language',
                value: _languageFilter,
                values: languages,
                onChanged: (value) {
                  setState(() => _languageFilter = value ?? '');
                  _loadVoices();
                },
              ),
              _buildFilterDropdown(
                label: 'Source',
                value: _sourceFilter,
                values: const ['local', 'external'],
                onChanged: (value) {
                  setState(() => _sourceFilter = value ?? '');
                  _loadVoices();
                },
              ),
              FilledButton.icon(
                onPressed: _isUploading ? null : _uploadVoicePrompt,
                icon: _isUploading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.upload_rounded),
                label: Text(_isUploading ? 'Uploading...' : 'Upload Voice'),
              ),
            ],
          ),
        ),
        Expanded(child: _buildVoiceLibraryTable()),
      ],
    );
  }

  Widget _buildVoiceLibraryTable() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text(_error!));
    }
    if (_voices.isEmpty) {
      return const Center(child: Text('No voice prompts found'));
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          sortColumnIndex: _columnIndexForSort(_sortBy),
          sortAscending: _sortOrder == 'asc',
          columns: [
            DataColumn(
              label: _sortableHeader('Name', 'name'),
              onSort: (columnIndex, ascending) => _toggleSort('name'),
            ),
            DataColumn(
              label: _sortableHeader('Gender', 'gender'),
              onSort: (columnIndex, ascending) => _toggleSort('gender'),
            ),
            DataColumn(
              label: _sortableHeader('Language', 'language'),
              onSort: (columnIndex, ascending) => _toggleSort('language'),
            ),
            DataColumn(
              numeric: true,
              label: _sortableHeader('Duration', 'duration'),
              onSort: (columnIndex, ascending) => _toggleSort('duration'),
            ),
            DataColumn(
              label: _sortableHeader('Source', 'source'),
              onSort: (columnIndex, ascending) => _toggleSort('source'),
            ),
            const DataColumn(label: Text('Actions')),
          ],
          rows: _voices
              .map((voice) {
                final name = voice['name']?.toString() ?? '';
                final isPreviewing = _previewingName == name;
                final duration =
                    (voice['duration_sec'] as num?)?.toDouble() ?? 0.0;
                final engines = List<String>.from(
                  voice['engines_supported'] as List<dynamic>? ?? const [],
                );
                return DataRow(
                  cells: [
                    DataCell(
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(name),
                          if (engines.isNotEmpty)
                            Text(
                              engines.join(', '),
                              style: TextStyle(
                                fontSize: 10,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                    DataCell(Text(voice['gender']?.toString() ?? '-')),
                    DataCell(Text(voice['language']?.toString() ?? '-')),
                    DataCell(Text('${duration.toStringAsFixed(2)}s')),
                    DataCell(
                      Text((voice['source']?.toString() ?? '-').toUpperCase()),
                    ),
                    DataCell(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Play preview',
                            onPressed: (!isPreviewing || _isPreviewPaused)
                                ? () => _previewVoice(name)
                                : null,
                            icon: const Icon(Icons.play_arrow_rounded),
                          ),
                          IconButton(
                            tooltip: 'Pause preview',
                            onPressed: (isPreviewing && !_isPreviewPaused)
                                ? _pausePreview
                                : null,
                            icon: const Icon(Icons.pause_rounded),
                          ),
                          IconButton(
                            tooltip: 'Stop preview',
                            onPressed: isPreviewing ? _stopPreview : null,
                            icon: const Icon(Icons.stop_rounded),
                          ),
                          IconButton(
                            tooltip: 'Edit',
                            onPressed: () => _editVoicePrompt(voice),
                            icon: const Icon(Icons.edit_rounded),
                          ),
                          IconButton(
                            tooltip: 'Delete',
                            onPressed: () => _deleteVoicePrompt(name),
                            icon: const Icon(Icons.delete_outline_rounded),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              })
              .toList(growable: false),
        ),
      ),
    );
  }

  Widget _buildYoutubeImportTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'YouTube Import',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Step 1: Download a 20-second preview. Step 2: Listen. Step 3: Save as a voice prompt.',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _youtubeUrlController,
                    decoration: const InputDecoration(
                      labelText: 'YouTube URL',
                      hintText: 'https://www.youtube.com/watch?v=...',
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      SizedBox(
                        width: 220,
                        child: TextField(
                          controller: _youtubeStartController,
                          keyboardType:
                              const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'Start Seconds (optional)',
                            hintText: 'Leave blank to use t= from URL',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      FilledButton.icon(
                        onPressed: _isYoutubeDownloading
                            ? null
                            : _downloadYoutubePreview,
                        icon: _isYoutubeDownloading
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.download_rounded),
                        label: Text(
                          _isYoutubeDownloading
                              ? 'Downloading...'
                              : 'Download Preview',
                        ),
                      ),
                    ],
                  ),
                  if (_youtubePreviewAudioUrl != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Theme.of(context).dividerColor,
                        ),
                      ),
                      child: Row(
                        children: [
                          Text(
                            _youtubePreviewDurationSec == null
                                ? 'Preview ready'
                                : 'Preview ready (${_youtubePreviewDurationSec!.toStringAsFixed(2)}s)',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const Spacer(),
                          IconButton(
                            tooltip: 'Play preview',
                            onPressed: _playYoutubePreview,
                            icon: const Icon(Icons.play_arrow_rounded),
                          ),
                          IconButton(
                            tooltip: 'Pause preview',
                            onPressed: _isYoutubePreviewPaused
                                ? null
                                : _pauseYoutubePreview,
                            icon: const Icon(Icons.pause_rounded),
                          ),
                          IconButton(
                            tooltip: 'Stop preview',
                            onPressed: _stopYoutubePreview,
                            icon: const Icon(Icons.stop_rounded),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Save Preview as Voice Prompt',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _youtubeNameController,
                    decoration: const InputDecoration(labelText: 'Voice Name'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _youtubeTranscriptController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Transcript (optional)',
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _youtubeGenderController,
                          decoration: const InputDecoration(
                            labelText: 'Gender',
                            hintText: 'female / male / neutral',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _youtubeLanguageController,
                          decoration: const InputDecoration(
                            labelText: 'Language',
                            hintText: 'English',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _isYoutubeCommitting
                        ? null
                        : _saveYoutubePreviewAsVoicePrompt,
                    icon: _isYoutubeCommitting
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_rounded),
                    label: Text(
                      _isYoutubeCommitting
                          ? 'Saving...'
                          : 'Add as Voice Prompt',
                    ),
                  ),
                  if (_youtubeImportError != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _youtubeImportError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterDropdown({
    required String label,
    required String value,
    required List<String> values,
    required ValueChanged<String?> onChanged,
  }) {
    final normalizedValues = List<String>.from(values);
    if (value.isNotEmpty && !normalizedValues.contains(value)) {
      normalizedValues.insert(0, value);
    }
    final items = [
      const DropdownMenuItem<String>(value: '', child: Text('All')),
      ...normalizedValues.map(
        (v) => DropdownMenuItem<String>(value: v, child: Text(v)),
      ),
    ];
    return SizedBox(
      width: 140,
      child: DropdownButtonFormField<String>(
        initialValue: value,
        items: items,
        onChanged: onChanged,
        decoration: InputDecoration(labelText: label, isDense: true),
      ),
    );
  }

  Widget _sortableHeader(String label, String key) {
    final isActive = _sortBy == key;
    return Row(
      children: [
        Text(label),
        if (isActive)
          Icon(
            _sortOrder == 'asc'
                ? Icons.arrow_upward_rounded
                : Icons.arrow_downward_rounded,
            size: 14,
          ),
      ],
    );
  }

  int? _columnIndexForSort(String sortBy) {
    switch (sortBy) {
      case 'name':
        return 0;
      case 'gender':
        return 1;
      case 'language':
        return 2;
      case 'duration':
        return 3;
      case 'source':
        return 4;
      default:
        return null;
    }
  }
}
