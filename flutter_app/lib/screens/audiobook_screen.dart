import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;

import '../services/api_service.dart';
import '../utils/local_file_actions.dart';

class AudiobookScreen extends StatefulWidget {
  const AudiobookScreen({super.key});

  @override
  State<AudiobookScreen> createState() => _AudiobookScreenState();
}

class _AudiobookScreenState extends State<AudiobookScreen> {
  static const double _collapsedPaneWidth = 72;
  static const double _collapsedSectionHeight = 68;
  static const double _minDocumentsPaneWidth = 240;
  static const double _maxDocumentsPaneWidth = 420;
  static const double _minAudiobooksPaneHeight = 190;
  static const double _minMainPaneHeight = 220;
  static const List<String> _supportedExtensions = [
    'pdf',
    'txt',
    'md',
    'docx',
    'epub',
    'html',
    'htm',
    'rtf',
    'odt',
    'doc',
  ];

  static const List<Map<String, String>> _kokoroVoices = [
    {'id': 'bf_emma', 'name': 'Emma'},
    {'id': 'bf_alice', 'name': 'Alice'},
    {'id': 'bf_lily', 'name': 'Lily'},
    {'id': 'bm_george', 'name': 'George'},
    {'id': 'bm_lewis', 'name': 'Lewis'},
  ];

  final ApiService _api = ApiService();
  final AudioPlayer _audioPlayer = AudioPlayer();

  List<Map<String, dynamic>> _documents = [];
  List<Map<String, dynamic>> _audiobooks = [];
  List<Map<String, dynamic>> _qwenVoices = [];
  Map<String, dynamic>? _selectedDocument;
  Uint8List? _selectedBytes;
  String _previewText = '';
  bool _isLoadingDocuments = false;
  bool _isExtractingPreview = false;
  bool _isLoadingAudiobooks = false;
  String _engine = 'kokoro';
  String _kokoroVoice = 'bf_emma';
  String? _qwenVoice = 'Yelena';
  String _qwenModelSize = '0.6B';
  String _qwenQuantization = 'bf16';
  final String _qwenLanguage = 'English';
  double _speed = 1.0;
  String _outputFormat = 'm4b';
  String _subtitleFormat = 'none';
  bool _smartChunking = true;
  int _maxCharsPerChunk = 1500;
  int _crossfadeMs = 40;
  String? _playingAudiobookId;
  bool _isPlaybackPaused = false;
  StreamSubscription<PlayerState>? _playerSub;
  // Track multiple pending audiobooks keyed by job_id
  final Map<String, Map<String, dynamic>> _pendingAudiobooks = {};
  final Map<String, Timer> _pendingAudiobookTimers = {};
  bool _isDocumentsPaneCollapsed = false;
  bool _isAudiobooksPaneCollapsed = false;
  bool _isDocumentDropActive = false;
  double _documentsPaneWidth = 280;
  double _audiobooksPaneHeight = 250;

  @override
  void initState() {
    super.initState();
    _loadDocuments();
    _loadAudiobooks();
    _loadQwenVoices();
  }

  @override
  void dispose() {
    _playerSub?.cancel();
    for (final timer in _pendingAudiobookTimers.values) {
      timer.cancel();
    }
    _pendingAudiobookTimers.clear();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _loadDocuments() async {
    setState(() => _isLoadingDocuments = true);
    try {
      final docs = await _api.listPdfDocuments();
      if (!mounted) return;
      setState(() {
        _documents = docs
            .map(
              (doc) => <String, dynamic>{
                'name': doc['name'],
                'path': doc['url'],
                'url': doc['url'],
              },
            )
            .toList();
        _isLoadingDocuments = false;
      });
      if (_documents.isNotEmpty && _selectedDocument == null) {
        await _selectDocument(_documents.first);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingDocuments = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load documents: $e')));
    }
  }

  Future<void> _loadQwenVoices() async {
    try {
      final response = await _api.getQwen3Voices();
      final voices = List<Map<String, dynamic>>.from(
        response['voices'] as List<dynamic>? ?? [],
      );
      if (!mounted) return;
      setState(() {
        _qwenVoices = voices;
        if (_qwenVoice == null ||
            !voices.any((voice) => voice['name'] == _qwenVoice)) {
          _qwenVoice = voices.isNotEmpty
              ? voices.first['name'] as String?
              : null;
        }
      });
    } catch (e) {
      debugPrint('Failed to load Qwen voices for audiobooks: $e');
    }
  }

  Future<void> _loadAudiobooks() async {
    setState(() => _isLoadingAudiobooks = true);
    try {
      final books = await _api.getAudiobooks();
      if (!mounted) return;
      setState(() {
        _audiobooks = _mergeAudiobooks(books);
        _isLoadingAudiobooks = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingAudiobooks = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load audiobooks: $e')));
    }
  }

  List<Map<String, dynamic>> _mergeAudiobooks(
    List<Map<String, dynamic>> books,
  ) {
    if (_pendingAudiobooks.isEmpty) {
      return books;
    }
    // Filter out books that are in our pending map
    final pendingJobIds = _pendingAudiobooks.keys.toSet();
    final merged = books
        .where(
          (book) => !pendingJobIds.contains(book['job_id']?.toString() ?? ''),
        )
        .toList();
    // Add all pending audiobooks at the front
    return [..._pendingAudiobooks.values, ...merged];
  }

  Map<String, dynamic> _buildPendingAudiobook({
    required String jobId,
    required String title,
    required String status,
    required int queuePosition,
    required String engine,
    String? voice,
  }) {
    final engineLabel = engine == 'kokoro' ? 'Kokoro' : 'Qwen Clone';
    return {
      'job_id': jobId,
      'filename': title,
      'audio_url': null,
      'file_path': null,
      'format': _outputFormat,
      'size_mb': 0.0,
      'duration_seconds': 0.0,
      'created_at': DateTime.now().toIso8601String(),
      'is_audiobook_format': _outputFormat == 'm4b',
      'metrics_available': false,
      'status': status,
      'queue_position': queuePosition,
      'percent': 0,
      'current_chunk': 0,
      'total_chunks': 0,
      'eta_seconds': null,
      'is_pending': true,
      'engine': engine,
      'engine_label': engineLabel,
      'voice': voice,
    };
  }

  void _addPendingAudiobook(String jobId, Map<String, dynamic> book) {
    setState(() {
      _pendingAudiobooks[jobId] = book;
      _audiobooks = _mergeAudiobooks(
        _audiobooks
            .where(
              (item) => !_pendingAudiobooks.containsKey(
                item['job_id']?.toString() ?? '',
              ),
            )
            .toList(),
      );
    });
  }

  void _updatePendingAudiobook(String jobId, Map<String, dynamic> book) {
    if (!_pendingAudiobooks.containsKey(jobId)) return;
    setState(() {
      _pendingAudiobooks[jobId] = book;
      _audiobooks = _mergeAudiobooks(
        _audiobooks
            .where(
              (item) => !_pendingAudiobooks.containsKey(
                item['job_id']?.toString() ?? '',
              ),
            )
            .toList(),
      );
    });
  }

  void _removePendingAudiobook(String jobId) {
    setState(() {
      _pendingAudiobooks.remove(jobId);
      _pendingAudiobookTimers[jobId]?.cancel();
      _pendingAudiobookTimers.remove(jobId);
      _audiobooks = _mergeAudiobooks(
        _audiobooks
            .where(
              (item) => !_pendingAudiobooks.containsKey(
                item['job_id']?.toString() ?? '',
              ),
            )
            .toList(),
      );
    });
  }

  void _startPendingAudiobookPolling(String jobId) {
    _pendingAudiobookTimers[jobId]?.cancel();
    _pendingAudiobookTimers[jobId] = Timer.periodic(
      const Duration(seconds: 2),
      (_) {
        unawaited(_pollPendingAudiobook(jobId));
      },
    );
  }

  Future<void> _pollPendingAudiobook(String jobId) async {
    if (!_pendingAudiobooks.containsKey(jobId)) {
      _pendingAudiobookTimers[jobId]?.cancel();
      _pendingAudiobookTimers.remove(jobId);
      return;
    }

    try {
      final status = await _api.getAudiobookStatus(jobId);
      if (!mounted) return;
      if (!_pendingAudiobooks.containsKey(jobId)) return;

      final state = (status['status']?.toString() ?? 'queued').toLowerCase();
      if (state == 'completed') {
        _removePendingAudiobook(jobId);
        await _loadAudiobooks();
        return;
      }
      if (state == 'failed' || state == 'cancelled') {
        _removePendingAudiobook(jobId);
        final detail = status['error']?.toString();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              detail == null || detail.isEmpty
                  ? 'Audiobook job $jobId ${state == 'failed' ? 'failed' : 'was cancelled'}.'
                  : 'Audiobook job $jobId failed: $detail',
            ),
          ),
        );
        return;
      }

      final updated = Map<String, dynamic>.from(_pendingAudiobooks[jobId]!);
      updated['status'] = state;
      updated['queue_position'] =
          (status['queue_position'] as num?)?.toInt() ?? 0;
      updated['percent'] = (status['percent'] as num?)?.toInt() ?? 0;
      updated['current_chunk'] =
          (status['current_chunk'] as num?)?.toInt() ?? 0;
      updated['total_chunks'] = (status['total_chunks'] as num?)?.toInt() ?? 0;
      updated['eta_seconds'] = (status['eta_seconds'] as num?)?.toDouble();
      _updatePendingAudiobook(jobId, updated);
    } catch (_) {
      // Keep the optimistic pending row visible even if polling is temporarily unavailable.
    }
  }

  Future<void> _pickLocalDocument() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _supportedExtensions,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.single;
    final path =
        file.path ??
        'uploaded://${DateTime.now().millisecondsSinceEpoch}_${file.name}';
    final entry = <String, dynamic>{
      'name': file.name,
      'path': path,
      'bytes': file.bytes,
    };

    await _addDocuments([entry]);
  }

  bool _isSupportedDocumentName(String name) {
    final extension = p.extension(name).replaceFirst('.', '').toLowerCase();
    return _supportedExtensions.contains(extension);
  }

  String _documentKey(Map<String, dynamic> document) {
    final name = (document['name'] as String? ?? '').trim().toLowerCase();
    final path = (document['path'] as String? ?? '').trim().toLowerCase();
    return '$name::$path';
  }

  List<Map<String, dynamic>> _prependDocuments(
    List<Map<String, dynamic>> documents,
  ) {
    final seenKeys = documents.map(_documentKey).toSet();
    final dedupedExisting = _documents
        .where((document) => !seenKeys.contains(_documentKey(document)))
        .toList();
    return [...documents, ...dedupedExisting];
  }

  Future<void> _addDocuments(List<Map<String, dynamic>> documents) async {
    if (documents.isEmpty) {
      return;
    }
    setState(() {
      _documents = _prependDocuments(documents);
      _isDocumentsPaneCollapsed = false;
    });
    await _selectDocument(documents.first);
  }

  Future<void> _handleDocumentDrop(DropDoneDetails detail) async {
    final droppedDocuments = <Map<String, dynamic>>[];
    final rejectedNames = <String>[];

    for (final file in detail.files) {
      final droppedPath = file.path.trim();
      final name = droppedPath.isNotEmpty ? p.basename(droppedPath) : file.name;
      if (!_isSupportedDocumentName(name)) {
        rejectedNames.add(name.isEmpty ? 'unknown file' : name);
        continue;
      }

      try {
        final entry = <String, dynamic>{
          'name': name,
          'path': droppedPath.isNotEmpty
              ? droppedPath
              : 'dropped://${DateTime.now().microsecondsSinceEpoch}_$name',
        };
        if (droppedPath.isEmpty) {
          entry['bytes'] = await file.readAsBytes();
        }
        droppedDocuments.add(entry);
      } catch (_) {
        rejectedNames.add(name.isEmpty ? 'unknown file' : name);
      }
    }

    if (droppedDocuments.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Drop a PDF, EPUB, DOCX, HTML, RTF, ODT, DOC, TXT, or MD file',
          ),
        ),
      );
      return;
    }

    await _addDocuments(droppedDocuments);

    if (!mounted) return;
    final addedCount = droppedDocuments.length;
    final skippedCount = rejectedNames.length;
    final addedLabel = addedCount == 1 ? 'document' : 'documents';
    final skippedLabel = skippedCount == 1 ? 'file' : 'files';
    final message = skippedCount == 0
        ? 'Added $addedCount $addedLabel from drop'
        : 'Added $addedCount $addedLabel from drop, skipped $skippedCount unsupported $skippedLabel';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _selectDocument(Map<String, dynamic> doc) async {
    setState(() {
      _selectedDocument = doc;
      _selectedBytes = null;
      _previewText = '';
      _isExtractingPreview = true;
    });

    try {
      Uint8List? bytes = doc['bytes'] as Uint8List?;
      final path = (doc['path'] as String? ?? '').trim();
      if (bytes == null && path.startsWith('/pdf/')) {
        bytes = await _api.fetchPdfBytes(path);
      } else if (bytes == null && !kIsWeb && path.isNotEmpty) {
        final file = File(path);
        if (await file.exists()) {
          bytes = await file.readAsBytes();
        }
      }

      if (bytes == null || bytes.isEmpty) {
        throw Exception('Could not load document bytes');
      }

      final preview = await _api.extractDocumentText(
        bytes,
        filename: doc['name'] as String? ?? 'document.pdf',
      );
      if (!mounted) return;
      setState(() {
        _selectedBytes = bytes;
        _previewText = preview;
        _isExtractingPreview = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isExtractingPreview = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to open document: $e')));
    }
  }

  Future<void> _startGeneration() async {
    final selected = _selectedDocument;
    if (selected == null || _selectedBytes == null || _selectedBytes!.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Select a document first')));
      return;
    }
    if (_engine == 'qwen3' && (_qwenVoice == null || _qwenVoice!.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a Qwen clone voice')),
      );
      return;
    }

    // Capture current settings for background generation
    final bytes = _selectedBytes!;
    final filename = selected['name'] as String? ?? 'document.pdf';
    final title = p.basenameWithoutExtension(
      selected['name'] as String? ?? 'Untitled',
    );
    final engine = _engine;
    final voice = engine == 'kokoro' ? _kokoroVoice : (_qwenVoice ?? 'Yelena');
    final speed = _speed;
    final outputFormat = _outputFormat;
    final subtitleFormat = _subtitleFormat;
    final smartChunking = _smartChunking;
    final maxCharsPerChunk = _maxCharsPerChunk;
    final crossfadeMs = _crossfadeMs;
    final qwenVoice = _qwenVoice;
    final qwenLanguage = _qwenLanguage;
    final qwenModelSize = _qwenModelSize;
    final qwenQuantization = _qwenQuantization;

    // Start queueing in background - don't await
    // The API call to queue is fast, so we just wait for the real job ID
    unawaited(
      _queueGenerationInBackground(
        bytes: bytes,
        filename: filename,
        title: title,
        engine: engine,
        voice: voice,
        speed: speed,
        outputFormat: outputFormat,
        subtitleFormat: subtitleFormat,
        smartChunking: smartChunking,
        maxCharsPerChunk: maxCharsPerChunk,
        crossfadeMs: crossfadeMs,
        qwenVoice: qwenVoice,
        qwenLanguage: qwenLanguage,
        qwenModelSize: qwenModelSize,
        qwenQuantization: qwenQuantization,
      ),
    );
  }

  Future<void> _queueGenerationInBackground({
    required Uint8List bytes,
    required String filename,
    required String title,
    required String engine,
    required String voice,
    required double speed,
    required String outputFormat,
    required String subtitleFormat,
    required bool smartChunking,
    required int maxCharsPerChunk,
    required int crossfadeMs,
    String? qwenVoice,
    required String qwenLanguage,
    required String qwenModelSize,
    required String qwenQuantization,
  }) async {
    try {
      final result = await _api.startAudiobookGenerationFromFile(
        bytes: bytes,
        filename: filename,
        title: title,
        engine: engine,
        voice: voice,
        speed: speed,
        outputFormat: outputFormat,
        subtitleFormat: subtitleFormat,
        smartChunking: smartChunking,
        maxCharsPerChunk: maxCharsPerChunk,
        crossfadeMs: crossfadeMs,
        qwenMode: 'clone',
        qwenVoiceName: engine == 'qwen3' ? qwenVoice : null,
        qwenLanguage: qwenLanguage,
        qwenModelSize: qwenModelSize,
        qwenModelQuantization: qwenQuantization,
      );
      if (!mounted) return;

      final jobId = result['job_id'] as String? ?? 'unknown';
      final queuePosition = (result['queue_position'] as num?)?.toInt() ?? 0;
      final pending = _buildPendingAudiobook(
        jobId: jobId,
        title: title,
        status: result['status']?.toString() ?? 'queued',
        queuePosition: queuePosition,
        engine: engine,
        voice: voice,
      );
      _addPendingAudiobook(jobId, pending);
      _startPendingAudiobookPolling(jobId);

      final engineLabel = engine == 'kokoro' ? 'Kokoro' : 'Qwen Clone';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            queuePosition > 0
                ? '[$engineLabel] Audiobook job $jobId queued (#$queuePosition)'
                : '[$engineLabel] Audiobook job $jobId started',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      await _showAudiobookStartErrorDialog(e);
    }
  }

  Future<void> _showAudiobookStartErrorDialog(Object error) async {
    final message = 'Failed to start audiobook:\n\n$error';
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Audiobook generation failed'),
          content: SingleChildScrollView(child: SelectableText(message)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _playAudiobook(Map<String, dynamic> book) async {
    final jobId = book['job_id'] as String? ?? '';
    final audioUrl = book['audio_url'] as String? ?? '';
    if (jobId.isEmpty || audioUrl.isEmpty) return;

    if (_playingAudiobookId == jobId && _isPlaybackPaused) {
      setState(() => _isPlaybackPaused = false);
      await _audioPlayer.play();
      return;
    }

    setState(() {
      _playingAudiobookId = jobId;
      _isPlaybackPaused = false;
    });

    try {
      await _playerSub?.cancel();
      await _audioPlayer.stop();
      await _audioPlayer.setUrl(_api.getAudiobookUrl(audioUrl));
      await _audioPlayer.play();
      _playerSub = _audioPlayer.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed && mounted) {
          setState(() {
            _playingAudiobookId = null;
            _isPlaybackPaused = false;
          });
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _playingAudiobookId = null;
        _isPlaybackPaused = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to play audiobook: $e')));
    }
  }

  Future<void> _pausePlayback() async {
    if (_playingAudiobookId == null) return;
    await _audioPlayer.pause();
    if (!mounted) return;
    setState(() => _isPlaybackPaused = true);
  }

  Future<void> _stopPlayback() async {
    await _playerSub?.cancel();
    _playerSub = null;
    await _audioPlayer.stop();
    if (!mounted) return;
    setState(() {
      _playingAudiobookId = null;
      _isPlaybackPaused = false;
    });
  }

  Future<void> _downloadAudiobook(Map<String, dynamic> book) async {
    final audioUrl = book['audio_url'] as String? ?? '';
    if (audioUrl.isEmpty) return;
    try {
      final bytes = await _api.downloadAudioBytes(audioUrl);
      final suggestedName = p.basename(Uri.parse(audioUrl).path);
      final ext = suggestedName.contains('.')
          ? suggestedName.split('.').last
          : 'wav';
      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save audiobook',
        fileName: suggestedName,
        type: FileType.custom,
        allowedExtensions: [ext],
      );
      if (savePath == null) return;
      final file = File(savePath);
      await file.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Saved to $savePath')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to download audiobook: $e')),
      );
    }
  }

  Future<void> _deleteAudiobook(String jobId) async {
    try {
      if (_playingAudiobookId == jobId) {
        await _stopPlayback();
      }
      await _api.deleteAudiobook(jobId);
      await _loadAudiobooks();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to delete audiobook: $e')));
    }
  }

  Future<void> _openAudiobookExternally(Map<String, dynamic> book) async {
    final filePath = (book['file_path'] as String?)?.trim() ?? '';
    if (filePath.isEmpty) return;
    try {
      await LocalFileActions.openPath(filePath);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to open audiobook: $e')));
    }
  }

  Future<void> _revealAudiobookInFolder(Map<String, dynamic> book) async {
    final filePath = (book['file_path'] as String?)?.trim() ?? '';
    if (filePath.isEmpty) return;
    try {
      await LocalFileActions.revealInFolder(filePath);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to reveal audiobook: $e')));
    }
  }

  String _documentTypeLabel(Map<String, dynamic>? doc) {
    final name = doc?['name'] as String? ?? '';
    final extension = p.extension(name).replaceFirst('.', '').trim();
    return extension.isEmpty ? 'FILE' : extension.toUpperCase();
  }

  IconData _documentTypeIcon(String type) {
    switch (type) {
      case 'PDF':
        return Icons.picture_as_pdf_rounded;
      case 'DOC':
      case 'DOCX':
      case 'ODT':
      case 'RTF':
        return Icons.article_rounded;
      case 'EPUB':
        return Icons.menu_book_rounded;
      case 'HTML':
      case 'HTM':
        return Icons.code_rounded;
      case 'MD':
      case 'TXT':
        return Icons.notes_rounded;
      default:
        return Icons.description_rounded;
    }
  }

  double _clampDocumentsPaneWidth(double width, double availableWidth) {
    final maxWidth = math.min(_maxDocumentsPaneWidth, availableWidth);
    final minWidth = math.min(_minDocumentsPaneWidth, maxWidth);
    return width.clamp(minWidth, maxWidth).toDouble();
  }

  double _clampAudiobooksPaneHeight(double height, double availableHeight) {
    final maxHeight = math.max(
      _minAudiobooksPaneHeight,
      availableHeight - _minMainPaneHeight,
    );
    return height.clamp(_minAudiobooksPaneHeight, maxHeight).toDouble();
  }

  Widget _buildVerticalResizeHandle({
    required ValueChanged<double> onDragUpdate,
  }) {
    final dividerColor = Theme.of(context).dividerColor;
    return Tooltip(
      message: 'Drag to resize',
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeLeftRight,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragUpdate: (details) => onDragUpdate(details.delta.dx),
          child: SizedBox(
            width: 12,
            child: Center(
              child: RotatedBox(
                quarterTurns: 1,
                child: Icon(
                  Icons.drag_indicator_rounded,
                  size: 18,
                  color: dividerColor,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHorizontalResizeHandle({
    required ValueChanged<double> onDragUpdate,
  }) {
    final dividerColor = Theme.of(context).dividerColor;
    return Tooltip(
      message: 'Drag to resize',
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeUpDown,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onVerticalDragUpdate: (details) => onDragUpdate(details.delta.dy),
          child: SizedBox(
            height: 12,
            child: Center(
              child: Icon(
                Icons.drag_indicator_rounded,
                size: 18,
                color: dividerColor,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDocumentList() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final selectedKey = _selectedDocument == null
        ? null
        : _documentKey(_selectedDocument!);

    return DropTarget(
      onDragEntered: (_) {
        setState(() {
          _isDocumentDropActive = true;
          _isDocumentsPaneCollapsed = false;
        });
      },
      onDragExited: (_) {
        if (_isDocumentDropActive) {
          setState(() => _isDocumentDropActive = false);
        }
      },
      onDragDone: (detail) async {
        if (_isDocumentDropActive) {
          setState(() => _isDocumentDropActive = false);
        }
        await _handleDocumentDrop(detail);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        child: Card(
          clipBehavior: Clip.antiAlias,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: _isDocumentDropActive
                  ? colorScheme.primary
                  : theme.dividerColor.withValues(alpha: 0.45),
              width: _isDocumentDropActive ? 1.6 : 1,
            ),
          ),
          child: _isDocumentsPaneCollapsed
              ? InkWell(
                  onTap: () {
                    setState(() => _isDocumentsPaneCollapsed = false);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 14,
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.library_books_rounded,
                          color: colorScheme.primary,
                        ),
                        const SizedBox(height: 12),
                        RotatedBox(
                          quarterTurns: 3,
                          child: Text(
                            'Documents',
                            style: theme.textTheme.titleSmall,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: _pickLocalDocument,
                          tooltip: 'Add document',
                          icon: const Icon(Icons.upload_file_rounded),
                        ),
                        IconButton(
                          onPressed: () {
                            setState(() => _isDocumentsPaneCollapsed = false);
                          },
                          tooltip: 'Expand documents',
                          icon: const Icon(Icons.chevron_right_rounded),
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
                      child: Row(
                        children: [
                          Icon(
                            Icons.library_books_rounded,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Documents',
                                  style: theme.textTheme.titleMedium,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Drop PDF, EPUB, DOCX, HTML, RTF, ODT, DOC, TXT, or MD',
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: _pickLocalDocument,
                            icon: const Icon(Icons.upload_file_rounded),
                            label: const Text('Add'),
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            onPressed: () {
                              setState(() => _isDocumentsPaneCollapsed = true);
                            },
                            tooltip: 'Collapse documents',
                            icon: const Icon(Icons.chevron_left_rounded),
                          ),
                        ],
                      ),
                    ),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      color: _isDocumentDropActive
                          ? colorScheme.primaryContainer.withValues(alpha: 0.5)
                          : colorScheme.surfaceContainerLowest,
                      child: Text(
                        _isDocumentDropActive
                            ? 'Release to drop documents into this list'
                            : 'Drop files here or click Add',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: _isDocumentDropActive
                              ? colorScheme.onPrimaryContainer
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: _isLoadingDocuments
                          ? const Center(child: CircularProgressIndicator())
                          : _documents.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.move_to_inbox_outlined,
                                      size: 42,
                                      color: colorScheme.primary,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      'Drop a document here',
                                      style: theme.textTheme.titleSmall,
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'You can also click Add to import a local file.',
                                      style: theme.textTheme.bodySmall,
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : ListView.builder(
                              itemCount: _documents.length,
                              itemBuilder: (context, index) {
                                final doc = _documents[index];
                                final name =
                                    doc['name'] as String? ?? 'document';
                                final selected =
                                    selectedKey != null &&
                                    selectedKey == _documentKey(doc);
                                final type = _documentTypeLabel(doc);
                                return ListTile(
                                  selected: selected,
                                  leading: Icon(_documentTypeIcon(type)),
                                  title: Text(
                                    name,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(type),
                                  onTap: () => _selectDocument(doc),
                                );
                              },
                            ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildSettingsPane() {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Audiobook Generation',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    _selectedDocument == null
                        ? 'Select a document to generate an audiobook.'
                        : (_selectedDocument!['name'] as String? ?? 'Document'),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _startGeneration,
                  icon: const Icon(Icons.library_music_rounded),
                  label: const Text('Generate Audiobook'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment<String>(
                  value: 'kokoro',
                  icon: Icon(Icons.record_voice_over_rounded),
                  label: Text('Kokoro'),
                ),
                ButtonSegment<String>(
                  value: 'qwen3',
                  icon: Icon(Icons.graphic_eq_rounded),
                  label: Text('Qwen Clone'),
                ),
              ],
              selected: {_engine},
              onSelectionChanged: (selection) {
                setState(() => _engine = selection.first);
              },
            ),
            const SizedBox(height: 16),
            if (_engine == 'kokoro')
              DropdownButtonFormField<String>(
                key: ValueKey('kokoro-$_kokoroVoice'),
                initialValue: _kokoroVoice,
                decoration: const InputDecoration(
                  labelText: 'Kokoro voice',
                  border: OutlineInputBorder(),
                ),
                items: _kokoroVoices
                    .map(
                      (voice) => DropdownMenuItem<String>(
                        value: voice['id'],
                        child: Text(voice['name']!),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _kokoroVoice = value);
                  }
                },
              )
            else
              Column(
                children: [
                  DropdownButtonFormField<String>(
                    key: ValueKey('qwen-voice-${_qwenVoice ?? 'none'}'),
                    initialValue: _qwenVoice,
                    decoration: const InputDecoration(
                      labelText: 'Qwen clone voice',
                      border: OutlineInputBorder(),
                    ),
                    items: _qwenVoices
                        .map(
                          (voice) => DropdownMenuItem<String>(
                            value: voice['name'] as String?,
                            child: Text(voice['name'] as String? ?? 'Voice'),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setState(() => _qwenVoice = value),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          key: ValueKey('qwen-size-$_qwenModelSize'),
                          initialValue: _qwenModelSize,
                          decoration: const InputDecoration(
                            labelText: 'Model size',
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: '0.6B',
                              child: Text('0.6B'),
                            ),
                            DropdownMenuItem(
                              value: '1.7B',
                              child: Text('1.7B'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _qwenModelSize = value);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          key: ValueKey('qwen-quant-$_qwenQuantization'),
                          initialValue: _qwenQuantization,
                          decoration: const InputDecoration(
                            labelText: 'Quantization',
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'bf16',
                              child: Text('bf16'),
                            ),
                            DropdownMenuItem(
                              value: '8bit',
                              child: Text('8-bit'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _qwenQuantization = value);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey('output-$_outputFormat'),
              initialValue: _outputFormat,
              decoration: const InputDecoration(
                labelText: 'Output format',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'mp3', child: Text('MP3')),
                DropdownMenuItem(value: 'wav', child: Text('WAV')),
                DropdownMenuItem(value: 'm4b', child: Text('M4B')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => _outputFormat = value);
                }
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey('subtitle-$_subtitleFormat'),
              initialValue: _subtitleFormat,
              decoration: const InputDecoration(
                labelText: 'Subtitle format',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'none', child: Text('None')),
                DropdownMenuItem(value: 'srt', child: Text('SRT')),
                DropdownMenuItem(value: 'vtt', child: Text('VTT')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => _subtitleFormat = value);
                }
              },
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              value: _smartChunking,
              contentPadding: EdgeInsets.zero,
              title: const Text('Smart chunking'),
              onChanged: (value) => setState(() => _smartChunking = value),
            ),
            Row(
              children: [
                const Text('Speed'),
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
            Row(
              children: [
                const Text('Chunk size'),
                Expanded(
                  child: Slider(
                    value: _maxCharsPerChunk.toDouble(),
                    min: 120,
                    max: 4000,
                    divisions: 97,
                    label: _maxCharsPerChunk.toString(),
                    onChanged: _smartChunking
                        ? (value) =>
                              setState(() => _maxCharsPerChunk = value.round())
                        : null,
                  ),
                ),
                Text(_maxCharsPerChunk.toString()),
              ],
            ),
            Row(
              children: [
                const Text('Crossfade'),
                Expanded(
                  child: Slider(
                    value: _crossfadeMs.toDouble(),
                    min: 0,
                    max: 200,
                    divisions: 20,
                    label: '${_crossfadeMs}ms',
                    onChanged: _smartChunking
                        ? (value) =>
                              setState(() => _crossfadeMs = value.round())
                        : null,
                  ),
                ),
                Text('${_crossfadeMs}ms'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewPane() {
    final hasPreview = _previewText.trim().isNotEmpty;
    final selected = _selectedDocument;
    final type = _documentTypeLabel(selected);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Document Preview',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (selected != null) ...[
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _documentTypeIcon(type),
                          size: 16,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSecondaryContainer,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          type,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSecondaryContainer,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      selected['name'] as String? ?? 'Document',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ],
            if (_isExtractingPreview)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (!hasPreview)
              const Expanded(
                child: Center(
                  child: Text('Select a document to preview extracted text'),
                ),
              )
            else
              Expanded(
                child: SelectableText(
                  _previewText,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAudiobookLibrary() {
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
            child: Row(
              children: [
                Icon(
                  Icons.library_music_rounded,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Generated Audiobooks',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _isAudiobooksPaneCollapsed
                            ? 'Expand this pane to see queued and completed runs.'
                            : 'Drag the divider above to move this pane.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _loadAudiobooks,
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Refresh',
                ),
                IconButton(
                  onPressed: () {
                    setState(
                      () => _isAudiobooksPaneCollapsed =
                          !_isAudiobooksPaneCollapsed,
                    );
                  },
                  tooltip: _isAudiobooksPaneCollapsed
                      ? 'Expand audiobooks'
                      : 'Collapse audiobooks',
                  icon: Icon(
                    _isAudiobooksPaneCollapsed
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                  ),
                ),
              ],
            ),
          ),
          if (!_isAudiobooksPaneCollapsed) ...[
            const Divider(height: 1),
            Expanded(
              child: _isLoadingAudiobooks
                  ? const Center(child: CircularProgressIndicator())
                  : _audiobooks.isEmpty
                  ? const Center(child: Text('No audiobooks yet'))
                  : ListView.builder(
                      itemCount: _audiobooks.length,
                      itemBuilder: (context, index) {
                        final book = _audiobooks[index];
                        final jobId = book['job_id'] as String? ?? '';
                        final status =
                            (book['status'] as String? ?? 'completed')
                                .toLowerCase();
                        final isPending = book['is_pending'] == true;
                        final filename =
                            book['filename'] as String? ?? 'audiobook';
                        final filePath =
                            (book['file_path'] as String?)?.trim() ?? '';
                        final queuePosition =
                            (book['queue_position'] as num?)?.toInt() ?? 0;
                        final percent = (book['percent'] as num?)?.toInt() ?? 0;
                        final currentChunk =
                            (book['current_chunk'] as num?)?.toInt() ?? 0;
                        final totalChunks =
                            (book['total_chunks'] as num?)?.toInt() ?? 0;
                        final etaSeconds = (book['eta_seconds'] as num?)
                            ?.toDouble();
                        final hasAudio =
                            ((book['audio_url'] as String?)?.isNotEmpty ??
                                false) &&
                            !isPending;
                        final isPlaying = _playingAudiobookId == jobId;
                        // Get engine label for display
                        final engine = book['engine'] as String? ?? '';
                        final engineLabel =
                            book['engine_label'] as String? ??
                            (engine == 'kokoro'
                                ? 'Kokoro'
                                : engine == 'qwen3'
                                ? 'Qwen Clone'
                                : '');
                        final voice = book['voice'] as String? ?? '';
                        return ListTile(
                          leading: isPending
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                  ),
                                )
                              : Icon(
                                  isPlaying
                                      ? Icons.graphic_eq_rounded
                                      : Icons.audiotrack,
                                ),
                          title: Text(
                            filename,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isPending
                                    ? '${status.toUpperCase()}${engineLabel.isNotEmpty ? ' • $engineLabel' : ''}${voice.isNotEmpty ? ' ($voice)' : ''}${queuePosition > 0 ? ' • Queue #$queuePosition' : ''}${percent > 0 ? ' • $percent%' : ''}${totalChunks > 0 ? ' • Chunk $currentChunk/$totalChunks' : ''}${etaSeconds != null ? ' • ETA ${etaSeconds.round()}s' : ''}'
                                    : '${book['format'] ?? 'audio'} • ${(book['size_mb'] as num?)?.toStringAsFixed(1) ?? '0.0'} MB${engineLabel.isNotEmpty ? ' • $engineLabel' : ''}${voice.isNotEmpty ? ' ($voice)' : ''}',
                              ),
                              if (!isPending && filePath.isNotEmpty)
                                Text(
                                  filePath,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                            ],
                          ),
                          trailing: Wrap(
                            spacing: 4,
                            children: [
                              IconButton(
                                onPressed: hasAudio && filePath.isNotEmpty
                                    ? () => _openAudiobookExternally(book)
                                    : null,
                                icon: const Icon(Icons.open_in_new_rounded),
                                tooltip: 'Open externally',
                              ),
                              IconButton(
                                onPressed: hasAudio && filePath.isNotEmpty
                                    ? () => _revealAudiobookInFolder(book)
                                    : null,
                                icon: const Icon(Icons.folder_open_rounded),
                                tooltip: 'Show in folder',
                              ),
                              IconButton(
                                onPressed:
                                    hasAudio &&
                                        (!isPlaying || _isPlaybackPaused)
                                    ? () => _playAudiobook(book)
                                    : null,
                                icon: const Icon(Icons.play_arrow),
                                tooltip: 'Play',
                              ),
                              IconButton(
                                onPressed:
                                    hasAudio && isPlaying && !_isPlaybackPaused
                                    ? _pausePlayback
                                    : null,
                                icon: const Icon(Icons.pause),
                                tooltip: 'Pause',
                              ),
                              IconButton(
                                onPressed: hasAudio && isPlaying
                                    ? _stopPlayback
                                    : null,
                                icon: const Icon(Icons.stop),
                                tooltip: 'Stop',
                              ),
                              IconButton(
                                onPressed: hasAudio
                                    ? () => _downloadAudiobook(book)
                                    : null,
                                icon: const Icon(Icons.download_rounded),
                                tooltip: 'Download',
                              ),
                              IconButton(
                                onPressed: () => _deleteAudiobook(jobId),
                                icon: const Icon(Icons.delete_outline),
                                tooltip: 'Delete',
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxDocumentsPaneWidth = math.max(
            _minDocumentsPaneWidth,
            constraints.maxWidth - 520,
          );
          final documentsPaneWidth = _isDocumentsPaneCollapsed
              ? _collapsedPaneWidth
              : _clampDocumentsPaneWidth(
                  _documentsPaneWidth,
                  maxDocumentsPaneWidth,
                );

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: documentsPaneWidth, child: _buildDocumentList()),
              if (!_isDocumentsPaneCollapsed) ...[
                _buildVerticalResizeHandle(
                  onDragUpdate: (delta) {
                    setState(() {
                      _documentsPaneWidth = _clampDocumentsPaneWidth(
                        _documentsPaneWidth + delta,
                        maxDocumentsPaneWidth,
                      );
                    });
                  },
                ),
                const SizedBox(width: 8),
              ] else
                const SizedBox(width: 12),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, rightConstraints) {
                    final audiobooksPaneHeight = _isAudiobooksPaneCollapsed
                        ? _collapsedSectionHeight
                        : _clampAudiobooksPaneHeight(
                            _audiobooksPaneHeight,
                            rightConstraints.maxHeight,
                          );

                    return Column(
                      children: [
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(flex: 2, child: _buildSettingsPane()),
                              const SizedBox(width: 12),
                              Expanded(flex: 3, child: _buildPreviewPane()),
                            ],
                          ),
                        ),
                        if (!_isAudiobooksPaneCollapsed) ...[
                          _buildHorizontalResizeHandle(
                            onDragUpdate: (delta) {
                              setState(() {
                                _audiobooksPaneHeight =
                                    _clampAudiobooksPaneHeight(
                                      _audiobooksPaneHeight - delta,
                                      rightConstraints.maxHeight,
                                    );
                              });
                            },
                          ),
                          const SizedBox(height: 8),
                        ] else
                          const SizedBox(height: 12),
                        SizedBox(
                          height: audiobooksPaneHeight,
                          child: _buildAudiobookLibrary(),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
