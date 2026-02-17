import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as pdf;
import 'package:file_picker/file_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import '../services/api_service.dart';

class _SearchQueryCandidate {
  const _SearchQueryCandidate({
    required this.query,
    required this.expectedOccurrence,
    required this.totalExpectedOccurrences,
    required this.tokenCount,
  });

  final String query;
  final int expectedOccurrence;
  final int totalExpectedOccurrences;
  final int tokenCount;
}

enum _SearchWaitOutcome { matched, noMatch, unavailable, superseded }

class _PdfWordAnchor {
  const _PdfWordAnchor({required this.normalizedWord, required this.line});

  final String normalizedWord;
  final PdfTextLine line;
}

class PdfReaderScreen extends StatefulWidget {
  const PdfReaderScreen({super.key});

  @override
  State<PdfReaderScreen> createState() => _PdfReaderScreenState();
}

class _PdfReaderScreenState extends State<PdfReaderScreen>
    with AutomaticKeepAliveClientMixin {
  static const Color _activeReadAloudHighlightColor = Color.fromARGB(
    220,
    68,
    84,
    170,
  );
  static const Color _trailingReadAloudHighlightColor = Color.fromARGB(
    150,
    255,
    213,
    79,
  );
  final ApiService _api = ApiService();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final PdfViewerController _pdfController = PdfViewerController();
  final GlobalKey<SfPdfViewerState> _pdfViewerKey = GlobalKey();

  @override
  bool get wantKeepAlive => true;

  // Library state
  List<Map<String, dynamic>> _pdfLibrary = [];
  String? _selectedPdfPath;
  String? _selectedPdfName;
  Uint8List? _selectedPdfBytes;
  bool _isInitialized = false;
  String? _textFileContent; // For .txt and .md files
  String? _pdfExtractedText; // Extracted text from PDF
  bool _isExtractingText = false;

  // Reading state
  bool _isReading = false;
  bool _isPaused = false;
  PdfTextSearchResult? _searchResult; // For highlighting current word
  int _currentPage = 1;
  int _totalPages = 0;
  String? _selectedText;
  List<String> _sentences = [];
  int _currentSentenceIndex = -1;
  String _currentReadingText = '';
  String _readingSource = '';
  int _currentSentenceStartIndex = 0;

  // Word-level sync state
  List<String> _currentSentenceWords = [];
  int _currentWordIndex = -1;
  StreamSubscription<Duration>? _positionSubscription;
  List<int> _wordTimings = []; // Estimated start time (ms) for each word
  List<String> _globalWords = []; // Normalized words for sequence matching
  List<String> _globalSurfaceWords =
      []; // Searchable words with punctuation context
  List<int> _globalWordAnchorIndices = [];
  List<_PdfWordAnchor> _pdfWordAnchors = [];
  final List<Annotation> _activeReadAloudAnnotations = <Annotation>[];
  int _activeReadAloudAnchorIndex = -1;
  int _pdfWordAnchorBuildId = 0;
  List<int> _sentenceWordStart = [];
  final Map<String, int> _queryOccurrenceProgress = <String, int>{};
  int _searchRequestId = 0;
  bool _highlightSearchInFlight = false;
  bool _highlightRetryPending = false;

  // TTS settings
  String _selectedVoice = 'bf_emma';
  double _speed = 1.0;

  // Audiobook generation state
  bool _isGeneratingAudiobook = false;
  String? _audiobookJobId;
  int _audiobookCurrentChunk = 0;
  int _audiobookTotalChunks = 0;
  String _audiobookStatus = '';
  Timer? _audiobookPollTimer;
  String? _audiobookUrl;
  String _audiobookOutputFormat = 'mp3'; // 'wav', 'mp3', or 'm4b'
  String _audiobookSubtitleFormat = 'none'; // 'none', 'srt', or 'vtt'
  bool _audiobookSmartChunking = true;
  int _audiobookMaxCharsPerChunk = 1500;
  int _audiobookCrossfadeMs = 40;

  // Audiobook library state
  List<Map<String, dynamic>> _audiobooks = [];
  bool _isLoadingAudiobooks = false;
  String? _playingAudiobookId;
  bool _isAudiobookPaused = false;
  double _audiobookPlaybackSpeed = 1.0;
  StreamSubscription<PlayerState>? _audiobookPlayerSubscription;

  // Kokoro British voices (supported by backend)
  final List<Map<String, String>> _voices = [
    {'id': 'bf_emma', 'name': 'Emma (British F)'},
    {'id': 'bf_alice', 'name': 'Alice (British F)'},
    {'id': 'bf_lily', 'name': 'Lily (British F)'},
    {'id': 'bm_george', 'name': 'George (British M)'},
    {'id': 'bm_lewis', 'name': 'Lewis (British M)'},
  ];

  @override
  void initState() {
    super.initState();
    _loadSamplePdfs();
    _loadAudiobooks();
  }

  Future<void> _loadAudiobooks() async {
    setState(() => _isLoadingAudiobooks = true);
    try {
      final audiobooks = await _api.getAudiobooks();
      if (mounted) {
        setState(() {
          _audiobooks = audiobooks;
          _isLoadingAudiobooks = false;
        });
      }
    } catch (e) {
      debugPrint('Failed to load audiobooks: $e');
      if (mounted) {
        setState(() => _isLoadingAudiobooks = false);
      }
    }
  }

  Future<void> _loadSamplePdfs() async {
    // Prefer backend API for both web and desktop (more reliable than local path guessing).
    await _loadSamplePdfsFromApi();

    // Desktop fallback: scan local pdf directory relative to backend
    if (!kIsWeb && _pdfLibrary.isEmpty) {
      final foundDocs = <Map<String, dynamic>>[];
      final backendPdfDir = _resolveBackendPdfDir();

      if (backendPdfDir != null) {
        try {
          final dir = Directory(backendPdfDir);
          if (await dir.exists()) {
            debugPrint('PDF directory exists: $backendPdfDir');
            await for (final entity in dir.list()) {
              if (entity is File) {
                final lowerPath = entity.path.toLowerCase();
                if (lowerPath.endsWith('.pdf') ||
                    lowerPath.endsWith('.txt') ||
                    lowerPath.endsWith('.md')) {
                  final name = p.basename(entity.path);
                  foundDocs.add({'path': entity.path, 'name': name});
                  debugPrint('Found document: $name');
                }
              }
            }
          } else {
            debugPrint('PDF directory does not exist: $backendPdfDir');
          }
        } catch (e) {
          debugPrint('Error loading PDFs: $e');
        }
      }

      debugPrint(
        'Loading complete. Found ${foundDocs.length} documents. mounted=$mounted',
      );
      if (mounted) {
        setState(() {
          _pdfLibrary = foundDocs;
          _isInitialized = true;
        });

        // Auto-select first document
        if (_selectedPdfPath == null && _pdfLibrary.isNotEmpty) {
          final defaultDoc = _preferredDefaultDocument(_pdfLibrary)!;
          _selectPdf(
            defaultDoc['path'] as String,
            defaultDoc['name'] as String,
          );
        }
      }
    }
  }

  Map<String, dynamic>? _preferredDefaultDocument(
    List<Map<String, dynamic>> docs,
  ) {
    if (docs.isEmpty) return null;
    for (final doc in docs) {
      final name = ((doc['name'] as String?) ?? '').toLowerCase();
      if (name == 'genesis-chapter-1.pdf') {
        return doc;
      }
    }
    return docs.first;
  }

  /// Resolve the backend/data/pdf directory relative to the project.
  String? _resolveBackendPdfDir() {
    // Try common locations relative to the running app
    final candidates = [
      // When running from flutter_app/ or project root
      '../backend/data/pdf',
      'backend/data/pdf',
      // Absolute fallback for typical dev layout
      '${p.dirname(p.dirname(p.current))}/backend/data/pdf',
    ];
    for (final candidate in candidates) {
      final dir = Directory(candidate);
      if (dir.existsSync()) return dir.path;
    }
    return null;
  }

  /// Load document list from backend API (used on web).
  Future<void> _loadSamplePdfsFromApi() async {
    try {
      final docs = await _api.listPdfDocuments();
      final List<Map<String, dynamic>> library = docs
          .map(
            (doc) => <String, dynamic>{
              'path': doc['url'] as String,
              'name': doc['name'] as String,
              'url': doc['url'] as String,
            },
          )
          .toList();

      if (mounted) {
        setState(() {
          _pdfLibrary = library;
          _isInitialized = true;
        });

        // Auto-select first document and load its bytes
        if (_selectedPdfPath == null && _pdfLibrary.isNotEmpty) {
          final defaultDoc = _preferredDefaultDocument(_pdfLibrary)!;
          await _selectPdfFromUrl(
            defaultDoc['url'] as String,
            defaultDoc['name'] as String,
          );
        }
      }
    } catch (e) {
      debugPrint('Error loading PDFs from API: $e');
      if (mounted) {
        setState(() {
          _pdfLibrary = [];
          _isInitialized = true;
        });
      }
    }
  }

  bool _isLoadingPdfBytes = false;
  String? _selectedPdfNetworkUrl; // Full URL for SfPdfViewer.network on web

  /// Select a PDF by fetching its bytes from the backend (for web).
  Future<void> _selectPdfFromUrl(String urlPath, String name) async {
    final fullUrl = _api.getPdfUrl(urlPath);

    // Set path and network URL immediately so UI can render
    setState(() {
      _selectedPdfPath = urlPath;
      _selectedPdfName = name;
      _selectedPdfBytes = null;
      _selectedPdfNetworkUrl = fullUrl;
      _isLoadingPdfBytes = true;
      _textFileContent = null;
      _pdfExtractedText = null;
      _pdfWordAnchors = [];
      _globalWordAnchorIndices = [];
      _activeReadAloudAnnotations.clear();
      _activeReadAloudAnchorIndex = -1;
      _pdfWordAnchorBuildId++;
    });

    // Also fetch bytes for text extraction (read-aloud)
    try {
      final bytes = await _api.fetchPdfBytes(urlPath);
      if (mounted) {
        for (final doc in _pdfLibrary) {
          if (doc['path'] == urlPath || doc['url'] == urlPath) {
            doc['bytes'] = bytes;
            break;
          }
        }
        setState(() {
          _selectedPdfBytes = bytes;
          _isLoadingPdfBytes = false;
        });
        final lowerPath = urlPath.toLowerCase();
        if (lowerPath.endsWith('.txt') || lowerPath.endsWith('.md')) {
          _loadTextFromBytes(bytes);
        } else if (lowerPath.endsWith('.pdf')) {
          _extractPdfTextFromBytes(bytes, filename: name);
        }
      }
    } catch (e) {
      debugPrint('Error fetching PDF bytes: $e');
      if (mounted) {
        setState(() => _isLoadingPdfBytes = false);
      }
    }
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _audiobookPollTimer?.cancel();
    _audiobookPlayerSubscription?.cancel();
    _audioPlayer.dispose();
    _pdfController.dispose();
    super.dispose();
  }

  Future<void> _openPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'txt', 'md'],
      withData: true, // Always request bytes for cross-platform compatibility
    );

    if (result != null && result.files.isNotEmpty) {
      final file = result.files.single;
      final path =
          file.path ??
          'uploaded://${DateTime.now().millisecondsSinceEpoch}_${file.name}';
      final name = file.path != null ? p.basename(path) : file.name;
      final bytes = file.bytes;

      // Add to library if not exists
      if (!_pdfLibrary.any((p) => p['path'] == path)) {
        setState(() {
          _pdfLibrary.add({'path': path, 'name': name, 'bytes': bytes});
        });
      }

      _selectPdf(path, name, bytes: bytes);
    }
  }

  void _selectPdf(String path, String name, {Uint8List? bytes}) {
    setState(() {
      _selectedPdfPath = path;
      _selectedPdfName = name;
      _selectedPdfBytes = bytes;
      _selectedPdfNetworkUrl =
          null; // Clear network URL when selecting directly
      _isLoadingPdfBytes = false;
      _currentPage = 1;
      _totalPages = 0;
      _textFileContent = null;
      _selectedText = null;
      _pdfExtractedText = null;
      _pdfWordAnchors = [];
      _globalWordAnchorIndices = [];
      _activeReadAloudAnnotations.clear();
      _activeReadAloudAnchorIndex = -1;
      _pdfWordAnchorBuildId++;
      _stopReading();
    });

    // Load text content for .txt and .md files
    final lowerPath = path.toLowerCase();

    // If we have bytes, always prefer the bytes-based path (works on all platforms)
    if (bytes != null) {
      if (lowerPath.endsWith('.txt') || lowerPath.endsWith('.md')) {
        _loadTextFromBytes(bytes);
      } else if (lowerPath.endsWith('.pdf')) {
        _extractPdfTextFromBytes(bytes, filename: name);
      }
      return;
    }

    // Fallback to file-based loading (desktop only)
    if (!kIsWeb) {
      if (lowerPath.endsWith('.txt') || lowerPath.endsWith('.md')) {
        _loadTextFile(path);
      } else if (lowerPath.endsWith('.pdf')) {
        _extractPdfText(path);
      }
    }
  }

  Future<void> _loadTextFile(String path) async {
    try {
      final file = File(path);
      final content = await file.readAsString();
      setState(() {
        _textFileContent = content;
        _selectedText = content; // Auto-select all text for reading
        _totalPages = 1;
      });
    } catch (e) {
      debugPrint('Error loading text file: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading file: $e')));
      }
    }
  }

  Future<void> _loadTextFromBytes(Uint8List bytes) async {
    try {
      final content = utf8.decode(bytes);
      setState(() {
        _textFileContent = content;
        _selectedText = content; // Auto-select all text for reading
        _totalPages = 1;
      });
    } catch (e) {
      debugPrint('Error loading text bytes: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading file: $e')));
      }
    }
  }

  Future<void> _extractPdfText(String path) async {
    setState(() => _isExtractingText = true);

    try {
      final file = File(path);
      final bytes = await file.readAsBytes();
      await _extractPdfTextFromBytes(bytes, filename: p.basename(path));
    } catch (e) {
      debugPrint('Error extracting PDF text: $e');
      if (mounted) {
        setState(() => _isExtractingText = false);
      }
    }
  }

  Future<void> _extractPdfTextFromBytes(
    Uint8List bytes, {
    String? filename,
  }) async {
    try {
      if (mounted) {
        setState(() => _isExtractingText = true);
      }

      String text = '';

      // Prefer backend extraction (PyMuPDF + cleanup) for better spacing fidelity.
      try {
        text = await _api.extractPdfText(
          bytes,
          filename: filename ?? _selectedPdfName ?? 'document.pdf',
        );
      } catch (e) {
        debugPrint('Backend PDF extraction failed, using local fallback: $e');
      }

      // Fallback to local extraction when backend is unavailable or result looks degraded.
      if (text.trim().isEmpty || _looksCorruptedPdfText(text)) {
        text = _extractPdfTextWithSyncfusion(bytes);
      }

      text = _normalizeExtractedPdfText(text);

      if (mounted) {
        setState(() {
          _pdfExtractedText = text;
          _isExtractingText = false;
        });
        print('Extracted ${text.length} characters from PDF');
      }
    } catch (e) {
      debugPrint('Error extracting PDF text: $e');
      if (mounted) {
        setState(() => _isExtractingText = false);
      }
    }
  }

  String _extractPdfTextWithSyncfusion(Uint8List bytes) {
    final document = pdf.PdfDocument(inputBytes: bytes);
    final textExtractor = pdf.PdfTextExtractor(document);
    final textBuffer = StringBuffer();
    try {
      for (int pageIndex = 0; pageIndex < document.pages.count; pageIndex++) {
        final pageText = textExtractor.extractText(
          startPageIndex: pageIndex,
          endPageIndex: pageIndex,
        );
        if (pageText.trim().isEmpty) continue;
        textBuffer.writeln(_normalizeExtractedPdfText(pageText));
        textBuffer.writeln();
      }
      return textBuffer.toString().trim();
    } finally {
      document.dispose();
    }
  }

  String _normalizeExtractedPdfText(String text) {
    if (text.isEmpty) return text;

    var normalized = text.replaceAll('\u00a0', ' ');
    normalized = normalized.replaceAll(RegExp(r'(?<!\n)\n(?!\n)'), ' ');
    normalized = normalized.replaceAll(
      RegExp(r'([.!?;:,])(?=[A-Za-z])'),
      r'$1 ',
    );
    normalized = normalized.replaceAll(RegExp(r'(?<=[a-z])(?=[A-Z])'), ' ');
    normalized = normalized.replaceAll(RegExp(r'[ \t]+'), ' ');
    normalized = normalized.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return normalized.trim();
  }

  bool _looksCorruptedPdfText(String text) {
    if (text.isEmpty) return true;
    final compact = text.replaceAll(RegExp(r'\s+'), '');
    if (compact.length < 120) return false;

    final whitespaceCount = RegExp(r'\s').allMatches(text).length;
    final whitespaceRatio = whitespaceCount / text.length;
    final longWordRuns = RegExp(r'[A-Za-z]{30,}').allMatches(text).length;
    return whitespaceRatio < 0.08 || longWordRuns >= 3;
  }

  bool get _isTextFile {
    if (_selectedPdfPath == null) return false;
    final lowerPath = _selectedPdfPath!.toLowerCase();
    return lowerPath.endsWith('.txt') || lowerPath.endsWith('.md');
  }

  bool get _hasTextToRead {
    if (_selectedText != null && _selectedText!.isNotEmpty) return true;
    if (_pdfExtractedText != null && _pdfExtractedText!.isNotEmpty) return true;
    if (_textFileContent != null && _textFileContent!.isNotEmpty) return true;
    return false;
  }

  void _removePdf(String path) {
    setState(() {
      _pdfLibrary.removeWhere((p) => p['path'] == path);
      if (_selectedPdfPath == path) {
        _selectedPdfPath = null;
        _selectedPdfName = null;
        _selectedPdfBytes = null;
        _pdfWordAnchors = [];
        _globalWordAnchorIndices = [];
        _activeReadAloudAnnotations.clear();
        _activeReadAloudAnchorIndex = -1;
        _pdfWordAnchorBuildId++;
        _stopReading();
      }
    });
  }

  Future<void> _startReading() async {
    if (_selectedPdfPath == null) return;

    // Get text: selected text first, then extracted PDF text, then text file content
    String textToRead = _selectedText ?? '';
    _readingSource = '';

    if (textToRead.isEmpty && _pdfExtractedText != null) {
      textToRead = _pdfExtractedText!;
      _readingSource = 'pdf';
    }

    if (textToRead.isEmpty && _textFileContent != null) {
      textToRead = _textFileContent!;
      _readingSource = 'text';
    }

    if (_selectedText != null && _selectedText!.isNotEmpty) {
      _readingSource = 'selection';
    }

    if (textToRead.isEmpty) {
      if (_isExtractingText) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Still extracting text from PDF, please wait...'),
            duration: Duration(seconds: 2),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No text found in document'),
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    // Split into sentences
    _sentences = _splitIntoSentences(textToRead);
    if (_sentences.isEmpty) return;
    _buildWordIndex(_sentences);
    if (_readingSource == 'pdf') {
      await _preparePdfWordAnchorsIfNeeded();
      _buildGlobalWordAnchorMap();
    } else {
      _globalWordAnchorIndices = List<int>.filled(_globalWords.length, -1);
    }

    setState(() {
      _isReading = true;
      _isPaused = false;
      _currentSentenceIndex = 0;
    });

    await _readNextSentence();
  }

  List<String> _splitIntoSentences(String text) {
    final normalized = _normalizeExtractedPdfText(text);
    if (normalized.isEmpty) return [];

    final splitter = RegExp(r'(?<=[.!?])\s+|(?<=[.!?])(?=[A-Z])|\n+');
    final sentences = normalized
        .split(splitter)
        .map((s) => s.trim())
        .where((s) => s.length > 1)
        .toList();

    return sentences;
  }

  String _cleanWordForSearch(String word) {
    final cleaned = word.replaceAll(RegExp(r'[^\w]'), '');
    return cleaned.toLowerCase();
  }

  String _surfaceWordForSearch(String word) {
    var surface = word.trim();
    surface = surface.replaceAll(RegExp(r'^[^A-Za-z0-9]+'), '');
    surface = surface.replaceAll(RegExp(r'[^A-Za-z0-9]+$'), '');
    return surface;
  }

  List<String> _splitSentenceWords(String sentence) {
    return sentence
        .split(RegExp(r'\s+'))
        .map((w) => w.trim())
        .where((w) => _cleanWordForSearch(w).length >= 2)
        .toList();
  }

  void _buildWordIndex(List<String> sentences) {
    _globalWords = [];
    _globalSurfaceWords = [];
    _globalWordAnchorIndices = [];
    _sentenceWordStart = [];

    for (final sentence in sentences) {
      _sentenceWordStart.add(_globalWords.length);
      final words = _splitSentenceWords(sentence);
      for (final word in words) {
        final clean = _cleanWordForSearch(word);
        if (clean.length < 2) continue;
        final surface = _surfaceWordForSearch(word);
        if (surface.isEmpty) continue;
        _globalWords.add(clean);
        _globalSurfaceWords.add(surface);
      }
    }

    _globalWordAnchorIndices = List<int>.filled(_globalWords.length, -1);
  }

  Future<Uint8List?> _loadCurrentPdfBytesForAnchors() async {
    if (_isTextFile || _selectedPdfPath == null) return null;
    if (_selectedPdfBytes != null && _selectedPdfBytes!.isNotEmpty) {
      return _selectedPdfBytes;
    }
    if (kIsWeb) return null;

    final path = _selectedPdfPath!;
    if (path.startsWith('http://') || path.startsWith('https://')) return null;
    final file = File(path);
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  Future<void> _preparePdfWordAnchorsIfNeeded() async {
    if (_readingSource != 'pdf' || _isTextFile) return;
    if (_pdfWordAnchors.isNotEmpty) return;

    final bytes = await _loadCurrentPdfBytesForAnchors();
    if (bytes == null || bytes.isEmpty) return;

    final buildId = ++_pdfWordAnchorBuildId;
    final anchors = <_PdfWordAnchor>[];
    pdf.PdfDocument? document;
    try {
      document = pdf.PdfDocument(inputBytes: bytes);
      final extractor = pdf.PdfTextExtractor(document);
      final textLines = extractor.extractTextLines();

      for (final line in textLines) {
        final pageNumber = line.pageIndex + 1;
        for (final word in line.wordCollection) {
          final normalized = _cleanWordForSearch(word.text);
          if (normalized.length < 2) continue;
          anchors.add(
            _PdfWordAnchor(
              normalizedWord: normalized,
              line: PdfTextLine(word.bounds, word.text, pageNumber),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Failed to build PDF word anchors: $e');
      return;
    } finally {
      document?.dispose();
    }

    if (!mounted || buildId != _pdfWordAnchorBuildId) return;
    _pdfWordAnchors = anchors;
  }

  void _buildGlobalWordAnchorMap() {
    _globalWordAnchorIndices = List<int>.filled(_globalWords.length, -1);
    if (_globalWords.isEmpty || _pdfWordAnchors.isEmpty) return;

    int anchorCursor = 0;
    for (int i = 0; i < _globalWords.length; i++) {
      final target = _globalWords[i];
      while (anchorCursor < _pdfWordAnchors.length &&
          _pdfWordAnchors[anchorCursor].normalizedWord != target) {
        anchorCursor++;
      }
      if (anchorCursor >= _pdfWordAnchors.length) break;
      _globalWordAnchorIndices[i] = anchorCursor;
      anchorCursor++;
    }
  }

  void _clearReadAloudAnnotations() {
    final stale = <Annotation>[..._activeReadAloudAnnotations];

    try {
      final existing = _pdfController.getAnnotations();
      for (final annotation in existing) {
        if ((annotation.subject ?? '') == 'mimika.readaloud') {
          stale.add(annotation);
        }
      }
    } catch (_) {
      // Viewer may not be ready for annotation enumeration yet.
    }

    for (final annotation in stale.toSet()) {
      try {
        _pdfController.removeAnnotation(annotation);
      } catch (_) {
        // Ignore stale references while rapidly updating playback highlights.
      }
    }

    _activeReadAloudAnnotations.clear();
    _activeReadAloudAnchorIndex = -1;
  }

  bool _tryHighlightWithPdfWordAnchor(int globalIndex) {
    if (_readingSource != 'pdf') return false;
    if (globalIndex < 0 || globalIndex >= _globalWordAnchorIndices.length) {
      return false;
    }

    final indices = <int>[];
    for (int offset = 2; offset >= 0; offset--) {
      final idx = globalIndex - offset;
      if (idx < 0 || idx >= _globalWordAnchorIndices.length) continue;
      final anchorIndex = _globalWordAnchorIndices[idx];
      if (anchorIndex < 0 || anchorIndex >= _pdfWordAnchors.length) continue;
      indices.add(anchorIndex);
    }
    if (indices.isEmpty) return false;

    final currentAnchorIndex = indices.last;
    if (_activeReadAloudAnchorIndex == currentAnchorIndex &&
        _activeReadAloudAnnotations.length == indices.length) {
      return true;
    }

    // Clear search UI highlight to avoid painting entire matched phrases.
    _searchResult?.clear();
    _searchResult = null;

    _clearReadAloudAnnotations();
    for (int i = 0; i < indices.length; i++) {
      final anchor = _pdfWordAnchors[indices[i]];
      final isCurrentWord = i == indices.length - 1;
      final annotation =
          HighlightAnnotation(textBoundsCollection: [anchor.line])
            ..subject = 'mimika.readaloud'
            ..author = 'mimika'
            ..color = isCurrentWord
                ? _activeReadAloudHighlightColor
                : _trailingReadAloudHighlightColor
            ..opacity = isCurrentWord ? 0.82 : 0.55;
      _pdfController.addAnnotation(annotation);
      _activeReadAloudAnnotations.add(annotation);
    }
    _activeReadAloudAnchorIndex = currentAnchorIndex;

    final currentAnchor = _pdfWordAnchors[currentAnchorIndex];
    if (_pdfController.pageNumber != currentAnchor.line.pageNumber) {
      _pdfController.jumpToPage(currentAnchor.line.pageNumber);
    }

    return true;
  }

  Future<void> _readNextSentence() async {
    if (!_isReading || _isPaused) return;
    if (_currentSentenceIndex >= _sentences.length) {
      _stopReading();
      return;
    }

    final sentence = _sentences[_currentSentenceIndex];
    setState(() {
      _currentReadingText = sentence;
    });

    // Split sentence into words for word-level highlighting
    _currentSentenceWords = _splitSentenceWords(sentence);
    _currentWordIndex = -1;
    _currentSentenceStartIndex =
        (_currentSentenceIndex >= 0 &&
            _currentSentenceIndex < _sentenceWordStart.length)
        ? _sentenceWordStart[_currentSentenceIndex]
        : 0;

    try {
      // Generate TTS audio
      final audioUrl = await _api.generateKokoro(
        text: sentence,
        voice: _selectedVoice,
        speed: _speed,
      );

      if (!_isReading) return; // Check if stopped while generating

      // Set up audio
      await _audioPlayer.setUrl(audioUrl);

      if (_currentSentenceWords.isNotEmpty) {
        var aligned = false;
        try {
          final alignedTimings = await _api.alignWordsToAudio(
            text: sentence,
            audioUrl: audioUrl,
            language: 'en',
          );
          if (alignedTimings.length == _currentSentenceWords.length) {
            _wordTimings = alignedTimings;
            aligned = true;
          }
        } catch (_) {
          // Alignment is optional; fall back to heuristic timings.
        }

        if (!aligned) {
          final duration =
              _audioPlayer.duration ??
              Duration(
                milliseconds: _estimateSentenceDurationMs(
                  _currentSentenceWords,
                ),
              );
          _calculateWordTimings(duration);
        }
        _startWordTracking();
      }

      // Play audio
      await _audioPlayer.play();

      // Wait for audio to complete
      await _audioPlayer.processingStateStream.firstWhere(
        (state) => state == ProcessingState.completed,
      );

      if (!_isReading || _isPaused) return;

      // Stop word tracking and clear highlight
      _stopWordTracking();
      _clearHighlight();

      // Move to next sentence
      setState(() {
        _currentSentenceIndex++;
        _currentWordIndex = -1;
        _currentSentenceWords = [];
      });

      // Small pause between sentences
      await Future.delayed(const Duration(milliseconds: 300));

      _readNextSentence();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('TTS Error: $e')));
      }
      _stopReading();
    }
  }

  void _calculateWordTimings(Duration audioDuration) {
    // Estimate word timing based on character count
    // Words with more characters take longer to say
    _wordTimings = [];

    if (_currentSentenceWords.isEmpty) return;

    // Calculate total "weight" (chars + pause between words)
    int totalWeight = 0;
    for (final word in _currentSentenceWords) {
      totalWeight += word.length + 2; // +2 for inter-word pause
    }

    final totalMs = audioDuration.inMilliseconds;
    final msPerWeight = totalMs / totalWeight;

    int cumulativeMs = 0;
    for (final word in _currentSentenceWords) {
      _wordTimings.add(cumulativeMs);
      cumulativeMs += ((word.length + 2) * msPerWeight).round();
    }
  }

  int _estimateSentenceDurationMs(List<String> words) {
    if (words.isEmpty) return 0;
    final totalChars = words.fold<int>(0, (sum, w) => sum + w.length);
    // Approximate 4.2 words/sec baseline and adjust by playback speed.
    final baseMs = ((words.length / 4.2) * 1000).round();
    final charMs = (totalChars * 22).round();
    final adjusted = ((baseMs + charMs) / _speed).round();
    return adjusted.clamp(600, 16000);
  }

  void _startWordTracking() {
    _positionSubscription?.cancel();

    if (_wordTimings.isNotEmpty && _currentSentenceWords.isNotEmpty) {
      if (mounted) {
        setState(() {
          _currentWordIndex = 0;
        });
      } else {
        _currentWordIndex = 0;
      }
      _highlightCurrentWord();
    }

    _positionSubscription = _audioPlayer.positionStream.listen((position) {
      if (!_isReading || _isPaused) return;
      if (_wordTimings.isEmpty || _currentSentenceWords.isEmpty) return;

      final ms = position.inMilliseconds;

      // Find which word we should be highlighting
      int newWordIndex = 0;
      for (int i = 0; i < _wordTimings.length; i++) {
        if (ms >= _wordTimings[i]) {
          newWordIndex = i;
        }
      }

      // Update highlight if word changed
      if (newWordIndex != _currentWordIndex) {
        if (mounted) {
          setState(() {
            _currentWordIndex = newWordIndex;
          });
        } else {
          _currentWordIndex = newWordIndex;
        }
        _highlightCurrentWord();
      }
    });
  }

  void _stopWordTracking() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
  }

  List<_SearchQueryCandidate> _buildSearchCandidates(int globalIndex) {
    if (_globalWords.isEmpty ||
        _globalSurfaceWords.length != _globalWords.length ||
        globalIndex < 0 ||
        globalIndex >= _globalWords.length) {
      return const [];
    }

    final candidates = <_SearchQueryCandidate>[];
    final seenQueries = <String>{};

    void addCandidate(int leftContextWords, int rightContextWords) {
      final start = globalIndex - leftContextWords;
      final end = globalIndex + rightContextWords + 1;
      if (start < 0 || end > _globalWords.length || start >= end) return;

      final normalizedTokens = _globalWords.sublist(start, end);
      final surfaceTokens = _globalSurfaceWords.sublist(start, end);
      if (normalizedTokens.length < 3 || surfaceTokens.isEmpty) return;

      final query = surfaceTokens.join(' ');
      if (query.length < 3 || !seenQueries.add(query)) return;

      final expected = _countSequenceOccurrences(
        normalizedTokens,
        uptoStart: start,
      );
      final totalExpected = _countSequenceOccurrences(normalizedTokens);
      candidates.add(
        _SearchQueryCandidate(
          query: query,
          expectedOccurrence: expected,
          totalExpectedOccurrences: totalExpected,
          tokenCount: normalizedTokens.length,
        ),
      );
    }

    // First try exact local context: previous + target + next.
    addCandidate(1, 1);
    // Then widen context for disambiguation in repetitive text.
    addCandidate(8, 8);
    addCandidate(7, 7);
    addCandidate(6, 6);
    addCandidate(5, 5);
    addCandidate(4, 4);
    addCandidate(3, 3);
    addCandidate(2, 2);
    addCandidate(0, 4);
    addCandidate(4, 0);
    addCandidate(0, 3);
    addCandidate(3, 0);
    addCandidate(1, 3);
    addCandidate(3, 1);

    return candidates;
  }

  int _countSequenceOccurrences(List<String> sequence, {int? uptoStart}) {
    if (sequence.isEmpty || _globalWords.length < sequence.length) return 0;

    int count = 0;
    final lastStart = _globalWords.length - sequence.length;
    final cappedEnd = uptoStart == null
        ? lastStart
        : uptoStart.clamp(0, lastStart);

    for (int i = 0; i <= cappedEnd; i++) {
      bool isMatch = true;
      for (int j = 0; j < sequence.length; j++) {
        if (_globalWords[i + j] != sequence[j]) {
          isMatch = false;
          break;
        }
      }
      if (isMatch) count++;
    }

    return count;
  }

  int _countWordOccurrences(String normalizedWord, {int? uptoIndex}) {
    if (normalizedWord.isEmpty || _globalWords.isEmpty) return 0;

    int count = 0;
    final endIndex = uptoIndex == null
        ? _globalWords.length - 1
        : uptoIndex.clamp(0, _globalWords.length - 1);

    for (int i = 0; i <= endIndex; i++) {
      if (_globalWords[i] == normalizedWord) {
        count++;
      }
    }

    return count;
  }

  int _resolveDesiredOccurrence({
    required int desiredOccurrence,
    required int expectedTotalOccurrences,
    required int actualTotalOccurrences,
    int? previousDesiredOccurrence,
  }) {
    var desired = desiredOccurrence;
    if (desired <= 0) desired = 1;

    if (desired > actualTotalOccurrences && expectedTotalOccurrences > 0) {
      final ratio = desired / expectedTotalOccurrences;
      desired = (ratio * actualTotalOccurrences).round();
    }

    if (previousDesiredOccurrence != null &&
        desired < previousDesiredOccurrence) {
      desired = previousDesiredOccurrence;
    }

    return desired.clamp(1, actualTotalOccurrences);
  }

  void _seekToSearchOccurrence(
    PdfTextSearchResult result,
    int desiredOccurrence,
    int totalOccurrences,
  ) {
    int safety = 0;
    while (result.currentInstanceIndex != desiredOccurrence &&
        safety < totalOccurrences) {
      result.nextInstance();
      safety++;
    }
  }

  Future<_SearchWaitOutcome> _waitForSearchCompletion(
    PdfTextSearchResult result,
    int requestId, {
    Duration timeout = const Duration(milliseconds: 2000),
  }) {
    final completer = Completer<_SearchWaitOutcome>();
    late VoidCallback listener;
    Timer? timer;
    final initialHasResult = result.hasResult;
    final initialTotal = result.totalInstanceCount;
    final initialCurrent = result.currentInstanceIndex;
    final initialCompleted = result.isSearchCompleted;
    bool hasStateChange = false;

    bool hasUsableMatch() =>
        result.hasResult &&
        result.totalInstanceCount > 0 &&
        result.currentInstanceIndex > 0;

    _SearchWaitOutcome evaluate() {
      if (!hasStateChange) return _SearchWaitOutcome.unavailable;
      if (hasUsableMatch()) return _SearchWaitOutcome.matched;
      if (result.isSearchCompleted) return _SearchWaitOutcome.noMatch;
      return _SearchWaitOutcome.unavailable;
    }

    void finish(_SearchWaitOutcome outcome) {
      if (completer.isCompleted) return;
      timer?.cancel();
      result.removeListener(listener);
      completer.complete(outcome);
    }

    listener = () {
      if (requestId != _searchRequestId) {
        finish(_SearchWaitOutcome.superseded);
        return;
      }
      if (!hasStateChange &&
          (result.hasResult != initialHasResult ||
              result.totalInstanceCount != initialTotal ||
              result.currentInstanceIndex != initialCurrent ||
              result.isSearchCompleted != initialCompleted)) {
        hasStateChange = true;
      }
      final outcome = evaluate();
      if (outcome == _SearchWaitOutcome.matched ||
          outcome == _SearchWaitOutcome.noMatch) {
        finish(outcome);
      }
    };

    result.addListener(listener);
    timer = Timer(timeout, () => finish(evaluate()));

    return completer.future;
  }

  Future<bool> _trySearchCandidate(
    _SearchQueryCandidate candidate,
    int requestId,
  ) async {
    if (requestId != _searchRequestId) return false;

    if (candidate.tokenCount < 3) return false;

    Future<({PdfTextSearchResult? result, _SearchWaitOutcome outcome})>
    runSearch({required bool wholeWords}) async {
      if (requestId != _searchRequestId) {
        return (result: null, outcome: _SearchWaitOutcome.superseded);
      }
      final result = wholeWords
          ? _pdfController.searchText(
              candidate.query,
              searchOption: pdf.TextSearchOption.wholeWords,
            )
          : _pdfController.searchText(candidate.query);
      final outcome = await _waitForSearchCompletion(result, requestId);
      if (requestId != _searchRequestId) {
        return (result: null, outcome: _SearchWaitOutcome.superseded);
      }
      if (outcome != _SearchWaitOutcome.matched) {
        return (result: null, outcome: outcome);
      }
      if (!result.hasResult ||
          result.totalInstanceCount <= 0 ||
          result.currentInstanceIndex <= 0) {
        return (result: null, outcome: _SearchWaitOutcome.noMatch);
      }
      return (result: result, outcome: outcome);
    }

    final firstAttempt = await runSearch(wholeWords: true);
    if (firstAttempt.outcome == _SearchWaitOutcome.superseded ||
        firstAttempt.outcome == _SearchWaitOutcome.unavailable) {
      return false;
    }

    PdfTextSearchResult? result = firstAttempt.result;
    if (result == null) {
      final secondAttempt = await runSearch(wholeWords: false);
      if (secondAttempt.outcome == _SearchWaitOutcome.superseded ||
          secondAttempt.outcome == _SearchWaitOutcome.unavailable) {
        return false;
      }
      result = secondAttempt.result;
    }
    if (result == null) return false;
    _searchResult = result;

    final total = result.totalInstanceCount;
    final previousDesired = _queryOccurrenceProgress[candidate.query];
    final desired = _resolveDesiredOccurrence(
      desiredOccurrence: candidate.expectedOccurrence,
      expectedTotalOccurrences: candidate.totalExpectedOccurrences,
      actualTotalOccurrences: total,
      previousDesiredOccurrence: previousDesired,
    );

    _seekToSearchOccurrence(result, desired, total);
    _queryOccurrenceProgress[candidate.query] = desired;
    return true;
  }

  Future<bool> _tryHighlightExactWord(int globalIndex, int requestId) async {
    if (requestId != _searchRequestId) return false;
    if (globalIndex < 0 || globalIndex >= _globalWords.length) return false;
    if (_globalSurfaceWords.length != _globalWords.length) return false;

    final normalizedWord = _globalWords[globalIndex];
    if (normalizedWord.length < 2) return false;

    final surfaceWord = _globalSurfaceWords[globalIndex];
    final queries = <String>{
      if (surfaceWord.length >= 2) surfaceWord,
      normalizedWord,
      if (normalizedWord.isNotEmpty)
        '${normalizedWord[0].toUpperCase()}${normalizedWord.substring(1)}',
    };

    for (final query in queries) {
      if (requestId != _searchRequestId) return false;

      for (final wholeWords in [true, false]) {
        if (requestId != _searchRequestId) return false;

        final result = wholeWords
            ? _pdfController.searchText(
                query,
                searchOption: pdf.TextSearchOption.wholeWords,
              )
            : _pdfController.searchText(query);
        final outcome = await _waitForSearchCompletion(result, requestId);
        if (requestId != _searchRequestId ||
            outcome == _SearchWaitOutcome.superseded) {
          return false;
        }
        if (outcome == _SearchWaitOutcome.unavailable) {
          return false;
        }
        if (outcome != _SearchWaitOutcome.matched ||
            !result.hasResult ||
            result.totalInstanceCount <= 0 ||
            result.currentInstanceIndex <= 0) {
          continue;
        }

        final expectedOccurrence = _countWordOccurrences(
          normalizedWord,
          uptoIndex: globalIndex,
        );
        final expectedTotal = _countWordOccurrences(normalizedWord);
        final progressKey = 'word::$normalizedWord';
        final previousDesired = _queryOccurrenceProgress[progressKey];
        final desired = _resolveDesiredOccurrence(
          desiredOccurrence: expectedOccurrence,
          expectedTotalOccurrences: expectedTotal,
          actualTotalOccurrences: result.totalInstanceCount,
          previousDesiredOccurrence: previousDesired,
        );

        _seekToSearchOccurrence(result, desired, result.totalInstanceCount);
        _searchResult = result;
        _queryOccurrenceProgress[progressKey] = desired;
        return true;
      }
    }

    return false;
  }

  Future<void> _performHighlightCurrentWord() async {
    if (_currentWordIndex < 0 ||
        _currentWordIndex >= _currentSentenceWords.length) {
      return;
    }

    final globalIndex = _currentSentenceStartIndex + _currentWordIndex;
    final hasGlobalWord = globalIndex >= 0 && globalIndex < _globalWords.length;

    if (_isTextFile || !hasGlobalWord) {
      return;
    }
    if (!(_readingSource == 'pdf' || _readingSource == 'selection')) {
      return;
    }

    if (_globalWords[globalIndex].isEmpty) return;
    if (_readingSource == 'pdf' && _pdfWordAnchors.isNotEmpty) {
      _tryHighlightWithPdfWordAnchor(globalIndex);
      return;
    }

    final int requestId = ++_searchRequestId;

    final exactWordMatched = await _tryHighlightExactWord(
      globalIndex,
      requestId,
    );
    if (exactWordMatched) return;

    final candidates = _buildSearchCandidates(globalIndex);
    if (candidates.isEmpty) return;

    for (final candidate in candidates) {
      if (requestId != _searchRequestId || !_isReading || _isPaused) {
        return;
      }
      final matched = await _trySearchCandidate(candidate, requestId);
      if (matched) return;
    }
  }

  Future<void> _highlightCurrentWord() async {
    if (_highlightSearchInFlight) {
      _highlightRetryPending = true;
      return;
    }

    _highlightSearchInFlight = true;
    try {
      do {
        _highlightRetryPending = false;
        await _performHighlightCurrentWord();
      } while (_highlightRetryPending && _isReading && !_isPaused);
    } finally {
      _highlightSearchInFlight = false;
      _highlightRetryPending = false;
    }
  }

  void _pauseReading() {
    setState(() {
      _isPaused = true;
    });
    _audioPlayer.pause();
  }

  void _resumeReading() {
    setState(() {
      _isPaused = false;
    });
    _audioPlayer.play();

    // If audio finished while paused, continue to next
    if (_audioPlayer.processingState == ProcessingState.completed) {
      _stopWordTracking();
      setState(() {
        _currentSentenceIndex++;
        _currentWordIndex = -1;
        _currentSentenceWords = [];
      });
      _readNextSentence();
    }
  }

  void _stopReading() {
    _stopWordTracking();
    _clearHighlight();
    setState(() {
      _isReading = false;
      _isPaused = false;
      _currentSentenceIndex = -1;
      _currentWordIndex = -1;
      _currentReadingText = '';
      _sentences = [];
      _currentSentenceWords = [];
      _wordTimings = [];
      _globalWords = [];
      _globalSurfaceWords = [];
      _globalWordAnchorIndices = [];
      _sentenceWordStart = [];
      _queryOccurrenceProgress.clear();
      _currentSentenceStartIndex = 0;
      _highlightSearchInFlight = false;
      _highlightRetryPending = false;
    });
    _audioPlayer.stop();
  }

  void _clearHighlight() {
    _clearReadAloudAnnotations();
    _searchResult?.clear();
    _searchResult = null;
  }

  // ============== Audiobook Generation ==============

  Future<void> _startAudiobookGeneration() async {
    // Get text to convert
    String textToConvert = _selectedText ?? '';
    if (textToConvert.isEmpty && _pdfExtractedText != null) {
      textToConvert = _pdfExtractedText!;
    }
    if (textToConvert.isEmpty && _textFileContent != null) {
      textToConvert = _textFileContent!;
    }

    if (textToConvert.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No text available to convert')),
      );
      return;
    }

    setState(() {
      _isGeneratingAudiobook = true;
      _audiobookCurrentChunk = 0;
      _audiobookTotalChunks = 0;
      _audiobookStatus = 'Starting...';
      _audiobookUrl = null;
    });

    try {
      final result = await _api.startAudiobookGeneration(
        text: textToConvert,
        title: _selectedPdfName ?? 'Untitled',
        voice: _selectedVoice,
        speed: _speed,
        outputFormat: _audiobookOutputFormat,
        subtitleFormat: _audiobookSubtitleFormat,
        smartChunking: _audiobookSmartChunking,
        maxCharsPerChunk: _audiobookMaxCharsPerChunk,
        crossfadeMs: _audiobookCrossfadeMs,
      );

      _audiobookJobId = result['job_id'] as String;
      _audiobookTotalChunks = result['total_chunks'] as int;

      // Start polling for status
      _startAudiobookPolling();
    } catch (e) {
      setState(() {
        _isGeneratingAudiobook = false;
        _audiobookStatus = '';
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to start: $e')));
      }
    }
  }

  void _startAudiobookPolling() {
    _audiobookPollTimer?.cancel();
    _audiobookPollTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _pollAudiobookStatus(),
    );
  }

  Future<void> _pollAudiobookStatus() async {
    if (_audiobookJobId == null) return;

    try {
      final status = await _api.getAudiobookStatus(_audiobookJobId!);
      final jobStatus = status['status'] as String;

      setState(() {
        _audiobookCurrentChunk = status['current_chunk'] as int;
        _audiobookTotalChunks = status['total_chunks'] as int;
        _audiobookStatus =
            'Processing chunk $_audiobookCurrentChunk/$_audiobookTotalChunks';
      });

      if (jobStatus == 'completed') {
        _audiobookPollTimer?.cancel();
        final audioUrl = status['audio_url'] as String;

        setState(() {
          _isGeneratingAudiobook = false;
          _audiobookUrl = _api.getAudiobookUrl(audioUrl);
          _audiobookStatus = '';
        });

        if (mounted) {
          _loadAudiobooks(); // Refresh the audiobook list
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Audiobook ready!'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      } else if (jobStatus == 'failed') {
        _audiobookPollTimer?.cancel();
        final error = status['error'] ?? 'Unknown error';
        setState(() {
          _isGeneratingAudiobook = false;
          _audiobookStatus = '';
        });
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Generation failed: $error')));
        }
      } else if (jobStatus == 'cancelled') {
        _audiobookPollTimer?.cancel();
        setState(() {
          _isGeneratingAudiobook = false;
          _audiobookStatus = '';
        });
      }
    } catch (e) {
      // Ignore polling errors, will retry
      debugPrint('Polling error: $e');
    }
  }

  Future<void> _cancelAudiobookGeneration() async {
    if (_audiobookJobId == null) return;

    try {
      await _api.cancelAudiobookGeneration(_audiobookJobId!);
      _audiobookPollTimer?.cancel();
      setState(() {
        _isGeneratingAudiobook = false;
        _audiobookStatus = '';
        _audiobookJobId = null;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to cancel: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    debugPrint('PDF Reader build: _pdfLibrary.length=${_pdfLibrary.length}');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Sidebar
        _buildSidebar(),
        // Main content
        Expanded(
          child: Column(
            children: [
              _buildTopControls(),
              Expanded(
                child: _selectedPdfPath != null
                    ? _buildPdfViewer()
                    : _buildEmptyState(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 250,
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
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              border: Border(
                bottom: BorderSide(color: Theme.of(context).dividerColor),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.library_books, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Documents',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  onPressed: _loadSamplePdfs,
                  tooltip: 'Refresh',
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  icon: const Icon(Icons.add, size: 20),
                  onPressed: _openPdf,
                  tooltip: 'Open Document',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          // Document list
          Expanded(
            flex: 3,
            child: !_isInitialized
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 8),
                        Text('Loading...'),
                      ],
                    ),
                  )
                : _pdfLibrary.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.auto_stories,
                          size: 48,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'No Documents',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                        const SizedBox(height: 4),
                        TextButton.icon(
                          onPressed: _openPdf,
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Open'),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _pdfLibrary.length,
                    itemBuilder: (context, index) {
                      final pdf = _pdfLibrary[index];
                      final name = (pdf['name'] as String?) ?? 'Untitled';
                      final path = (pdf['path'] as String?) ?? '';
                      final isSelected = path == _selectedPdfPath;

                      final lowerName = name.toLowerCase();
                      final IconData icon;
                      if (lowerName.endsWith('.md')) {
                        icon = Icons.code;
                      } else if (lowerName.endsWith('.txt')) {
                        icon = Icons.article;
                      } else {
                        icon = Icons.picture_as_pdf;
                      }

                      return ListTile(
                        dense: true,
                        selected: isSelected,
                        selectedTileColor: Theme.of(
                          context,
                        ).colorScheme.primaryContainer,
                        leading: Icon(
                          icon,
                          color: isSelected
                              ? Theme.of(context).colorScheme.primary
                              : null,
                          size: 20,
                        ),
                        title: Text(
                          name,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isSelected ? FontWeight.bold : null,
                          ),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.close, size: 16),
                          onPressed: () => _removePdf(path),
                          visualDensity: VisualDensity.compact,
                        ),
                        onTap: () {
                          final bytes = pdf['bytes'] as Uint8List?;
                          if (bytes != null) {
                            _selectPdf(path, name, bytes: bytes);
                          } else if (kIsWeb && pdf['url'] != null) {
                            _selectPdfFromUrl(pdf['url'] as String, name);
                          } else {
                            _selectPdf(path, name);
                          }
                        },
                      );
                    },
                  ),
          ),
          Container(height: 1, color: Theme.of(context).dividerColor),
          Expanded(flex: 2, child: _buildSidebarAudiobookHistory()),
        ],
      ),
    );
  }

  Color _voiceCardColor(int index) {
    const palette = <Color>[
      Colors.teal,
      Colors.indigo,
      Colors.green,
      Colors.deepPurple,
      Colors.orange,
      Colors.blue,
      Colors.pink,
      Colors.brown,
    ];
    return palette[index % palette.length];
  }

  Widget _buildTopControls() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Kokoro Voices',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(_voices.length, (index) {
                final voice = _voices[index];
                final voiceId = voice['id']!;
                final voiceName = voice['name']!;
                final isSelected = _selectedVoice == voiceId;
                final color = _voiceCardColor(index);
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedVoice = voiceId),
                    child: Container(
                      width: 150,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? color.withValues(alpha: 0.16)
                            : Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected ? color : Colors.grey.shade300,
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
                                  color: color,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  voiceName.split(' ').first,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: isSelected ? color : Colors.black87,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            voiceName,
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.speed, size: 16),
              const SizedBox(width: 8),
              const Text('Read-aloud speed:'),
              Expanded(
                child: Slider(
                  value: _speed,
                  min: 0.5,
                  max: 2.0,
                  divisions: 150,
                  label: '${_speed.toStringAsFixed(2)}x',
                  onChanged: (v) => setState(() => _speed = v),
                ),
              ),
              Text('${_speed.toStringAsFixed(2)}x'),
            ],
          ),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              leading: const Icon(Icons.library_music),
              title: const Text(
                'Audiobook Settings',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: const Text(
                'Format, subtitles, and chunking',
                style: TextStyle(fontSize: 12),
              ),
              children: [_buildAudiobookLibrary()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAudiobookLibrary() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Playback speed control (for audiobook preview player)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                const Text('Speed:', style: TextStyle(fontSize: 11)),
                Expanded(
                  child: Slider(
                    value: _audiobookPlaybackSpeed,
                    min: 0.5,
                    max: 2.0,
                    divisions: 150,
                    label: '${_audiobookPlaybackSpeed.toStringAsFixed(2)}x',
                    onChanged: _setAudiobookSpeed,
                  ),
                ),
                Text(
                  '${_audiobookPlaybackSpeed.toStringAsFixed(2)}x',
                  style: const TextStyle(fontSize: 10),
                ),
              ],
            ),
          ),
          // Output format selector
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                const Text('Format:', style: TextStyle(fontSize: 11)),
                const SizedBox(width: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'mp3',
                      label: Text('MP3', style: TextStyle(fontSize: 10)),
                    ),
                    ButtonSegment(
                      value: 'wav',
                      label: Text('WAV', style: TextStyle(fontSize: 10)),
                    ),
                    ButtonSegment(
                      value: 'm4b',
                      label: Text('M4B', style: TextStyle(fontSize: 10)),
                    ),
                  ],
                  selected: {_audiobookOutputFormat},
                  onSelectionChanged: (Set<String> selection) {
                    setState(() => _audiobookOutputFormat = selection.first);
                  },
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ),
          // Subtitle format selector
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                const Text('Subtitles:', style: TextStyle(fontSize: 11)),
                const SizedBox(width: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'none',
                      label: Text('None', style: TextStyle(fontSize: 10)),
                    ),
                    ButtonSegment(
                      value: 'srt',
                      label: Text('SRT', style: TextStyle(fontSize: 10)),
                    ),
                    ButtonSegment(
                      value: 'vtt',
                      label: Text('VTT', style: TextStyle(fontSize: 10)),
                    ),
                  ],
                  selected: {_audiobookSubtitleFormat},
                  onSelectionChanged: (Set<String> selection) {
                    setState(() => _audiobookSubtitleFormat = selection.first);
                  },
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Smart Chunking',
                style: TextStyle(fontSize: 11),
              ),
              value: _audiobookSmartChunking,
              onChanged: (value) =>
                  setState(() => _audiobookSmartChunking = value),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                const Text('Chunk size:', style: TextStyle(fontSize: 11)),
                Expanded(
                  child: Slider(
                    value: _audiobookMaxCharsPerChunk.toDouble(),
                    min: 400,
                    max: 4000,
                    divisions: 36,
                    label: _audiobookMaxCharsPerChunk.toString(),
                    onChanged: _audiobookSmartChunking
                        ? (value) => setState(
                            () => _audiobookMaxCharsPerChunk = value.round(),
                          )
                        : null,
                  ),
                ),
                Text(
                  _audiobookMaxCharsPerChunk.toString(),
                  style: const TextStyle(fontSize: 10),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                const Text('Crossfade:', style: TextStyle(fontSize: 11)),
                Expanded(
                  child: Slider(
                    value: _audiobookCrossfadeMs.toDouble(),
                    min: 0,
                    max: 200,
                    divisions: 20,
                    label: '${_audiobookCrossfadeMs}ms',
                    onChanged: _audiobookSmartChunking
                        ? (value) => setState(
                            () => _audiobookCrossfadeMs = value.round(),
                          )
                        : null,
                  ),
                ),
                Text(
                  '${_audiobookCrossfadeMs}ms',
                  style: const TextStyle(fontSize: 10),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarAudiobookHistory() {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Column(
        children: [
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
                const Icon(Icons.library_music, size: 18),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Audiobooks',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 18),
                  onPressed: _loadAudiobooks,
                  tooltip: 'Refresh',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Row(
              children: [
                const Text('Speed:', style: TextStyle(fontSize: 11)),
                Expanded(
                  child: Slider(
                    value: _audiobookPlaybackSpeed,
                    min: 0.5,
                    max: 2.0,
                    divisions: 150,
                    label: '${_audiobookPlaybackSpeed.toStringAsFixed(2)}x',
                    onChanged: _setAudiobookSpeed,
                  ),
                ),
                Text(
                  '${_audiobookPlaybackSpeed.toStringAsFixed(2)}x',
                  style: const TextStyle(fontSize: 10),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoadingAudiobooks
                ? const Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : _audiobooks.isEmpty
                ? Center(
                    child: Text(
                      'No audiobooks yet',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: _audiobooks.length,
                    itemBuilder: (context, index) {
                      final book = _audiobooks[index];
                      final jobId = book['job_id'] as String;
                      final shortId = jobId.length > 8
                          ? jobId.substring(0, 8)
                          : jobId;
                      final duration = book['duration_seconds'] as num;
                      final sizeMb = book['size_mb'] as num;
                      final isThisPlaying = _playingAudiobookId == jobId;

                      final mins = (duration / 60).floor();
                      final secs = (duration % 60).round();
                      final durationStr = mins > 0
                          ? '${mins}m ${secs}s'
                          : '${secs}s';

                      return Container(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: isThisPlaying
                              ? Theme.of(context).colorScheme.primaryContainer
                              : Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isThisPlaying
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).dividerColor,
                          ),
                        ),
                        child: Column(
                          children: [
                            ListTile(
                              dense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              leading: Icon(
                                Icons.audiotrack,
                                size: 18,
                                color: isThisPlaying
                                    ? Theme.of(context).colorScheme.primary
                                    : null,
                              ),
                              title: Text(
                                'Audiobook $shortId',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: isThisPlaying
                                      ? FontWeight.bold
                                      : null,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                '$durationStr • ${sizeMb.toStringAsFixed(1)} MB',
                                style: const TextStyle(fontSize: 10),
                              ),
                              trailing: IconButton(
                                icon: const Icon(
                                  Icons.delete_outline,
                                  size: 16,
                                ),
                                onPressed: () => _deleteAudiobook(jobId),
                                tooltip: 'Delete',
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(
                                left: 8,
                                right: 8,
                                bottom: 8,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.start,
                                children: [
                                  IconButton(
                                    icon: const Icon(
                                      Icons.play_arrow,
                                      size: 18,
                                    ),
                                    onPressed:
                                        (!isThisPlaying || _isAudiobookPaused)
                                        ? () => _playAudiobookFromList(book)
                                        : null,
                                    tooltip: 'Play',
                                    visualDensity: VisualDensity.compact,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                      minWidth: 28,
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.pause, size: 18),
                                    onPressed:
                                        (isThisPlaying && !_isAudiobookPaused)
                                        ? _pauseAudiobookPlayback
                                        : null,
                                    tooltip: 'Pause',
                                    visualDensity: VisualDensity.compact,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                      minWidth: 28,
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.stop, size: 18),
                                    onPressed: isThisPlaying
                                        ? _stopAudiobookPlayback
                                        : null,
                                    tooltip: 'Stop',
                                    visualDensity: VisualDensity.compact,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                      minWidth: 28,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _playAudiobookFromList(Map<String, dynamic> book) async {
    final jobId = book['job_id'] as String;
    final audioUrl = book['audio_url'] as String;

    // If same audiobook and paused, just resume
    if (_playingAudiobookId == jobId && _isAudiobookPaused) {
      setState(() => _isAudiobookPaused = false);
      await _audioPlayer.play();
      return;
    }

    // Update UI immediately
    setState(() {
      _playingAudiobookId = jobId;
      _isAudiobookPaused = false;
    });

    // Let the frame render before starting async work
    await Future.delayed(Duration.zero);

    if (!mounted) return;

    try {
      // Cancel previous subscription
      await _audiobookPlayerSubscription?.cancel();

      // Stop any current playback
      await _audioPlayer.stop();

      // Start new playback
      await _audioPlayer.setUrl(_api.getAudiobookUrl(audioUrl));
      await _audioPlayer.setSpeed(_audiobookPlaybackSpeed);
      await _audioPlayer.play();

      // Listen for completion with managed subscription
      _audiobookPlayerSubscription = _audioPlayer.playerStateStream.listen((
        state,
      ) {
        if (state.processingState == ProcessingState.completed) {
          if (mounted) {
            setState(() {
              _playingAudiobookId = null;
              _isAudiobookPaused = false;
            });
          }
        }
      });
    } catch (e) {
      // Reset state on error
      if (mounted) {
        setState(() {
          _playingAudiobookId = null;
          _isAudiobookPaused = false;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to play: $e')));
      }
    }
  }

  Future<void> _pauseAudiobookPlayback() async {
    if (_playingAudiobookId != null) {
      await _audioPlayer.pause();
      setState(() => _isAudiobookPaused = true);
    }
  }

  Future<void> _stopAudiobookPlayback() async {
    await _audiobookPlayerSubscription?.cancel();
    _audiobookPlayerSubscription = null;
    await _audioPlayer.stop();
    setState(() {
      _playingAudiobookId = null;
      _isAudiobookPaused = false;
    });
  }

  Future<void> _setAudiobookSpeed(double speed) async {
    setState(() => _audiobookPlaybackSpeed = speed);
    if (_playingAudiobookId != null) {
      await _audioPlayer.setSpeed(speed);
    }
  }

  Future<void> _deleteAudiobook(String jobId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Audiobook'),
        content: Text('Delete audiobook $jobId?'),
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
        if (_playingAudiobookId == jobId) {
          await _audioPlayer.stop();
          setState(() => _playingAudiobookId = null);
        }

        await _api.deleteAudiobook(jobId);
        _loadAudiobooks(); // Refresh list
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
        }
      }
    }
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.auto_stories, size: 80, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            'Open a document to get started',
            style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          Text(
            'Supported: PDF, TXT, MD',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _openPdf,
            icon: const Icon(Icons.folder_open),
            label: const Text('Open Document'),
          ),
        ],
      ),
    );
  }

  Widget _buildPdfViewer() {
    // Use text viewer for .txt and .md files
    if (_isTextFile) {
      return _buildTextViewer();
    }

    // If we have bytes in memory, use the memory viewer (works everywhere)
    if (_selectedPdfBytes != null) {
      return Column(
        children: [
          _buildToolbar(),
          if (_isReading) _buildReadingIndicator(),
          Expanded(
            child: SfPdfViewer.memory(
              _selectedPdfBytes!,
              key: _pdfViewerKey,
              controller: _pdfController,
              currentSearchTextHighlightColor: _activeReadAloudHighlightColor,
              otherSearchTextHighlightColor: Colors.transparent,
              onDocumentLoaded: (details) {
                setState(() {
                  _totalPages = details.document.pages.count;
                });
              },
              onPageChanged: (details) {
                setState(() {
                  _currentPage = details.newPageNumber;
                });
              },
              onTextSelectionChanged: (details) {
                setState(() {
                  _selectedText = details.selectedText;
                });
              },
            ),
          ),
          _buildPageIndicator(),
        ],
      );
    }

    // On web: use network viewer if we have a URL, or show loading/error state
    if (kIsWeb) {
      if (_selectedPdfNetworkUrl != null) {
        return Column(
          children: [
            _buildToolbar(),
            if (_isReading) _buildReadingIndicator(),
            Expanded(
              child: SfPdfViewer.network(
                _selectedPdfNetworkUrl!,
                key: _pdfViewerKey,
                controller: _pdfController,
                currentSearchTextHighlightColor: _activeReadAloudHighlightColor,
                otherSearchTextHighlightColor: Colors.transparent,
                onDocumentLoaded: (details) {
                  setState(() {
                    _totalPages = details.document.pages.count;
                  });
                },
                onPageChanged: (details) {
                  setState(() {
                    _currentPage = details.newPageNumber;
                  });
                },
                onTextSelectionChanged: (details) {
                  setState(() {
                    _selectedText = details.selectedText;
                  });
                },
              ),
            ),
            _buildPageIndicator(),
          ],
        );
      }
      if (_isLoadingPdfBytes) {
        return const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Loading document...'),
            ],
          ),
        );
      }
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.orange),
            const SizedBox(height: 16),
            const Text('Could not load document', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _openPdf,
              icon: const Icon(Icons.upload_file),
              label: const Text('Upload PDF'),
            ),
          ],
        ),
      );
    }

    // Desktop: use file-based viewer
    final file = File(_selectedPdfPath!);
    if (!file.existsSync()) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              'File not found:\n$_selectedPdfPath',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        _buildToolbar(),
        if (_isReading) _buildReadingIndicator(),
        Expanded(
          child: SfPdfViewer.file(
            file,
            key: _pdfViewerKey,
            controller: _pdfController,
            currentSearchTextHighlightColor: _activeReadAloudHighlightColor,
            otherSearchTextHighlightColor: Colors.transparent,
            onDocumentLoaded: (details) {
              setState(() {
                _totalPages = details.document.pages.count;
              });
            },
            onPageChanged: (details) {
              setState(() {
                _currentPage = details.newPageNumber;
              });
            },
            onTextSelectionChanged: (details) {
              setState(() {
                _selectedText = details.selectedText;
              });
            },
          ),
        ),
        _buildPageIndicator(),
      ],
    );
  }

  Widget _buildTextViewer() {
    return Column(
      children: [
        // Toolbar (simplified for text files)
        _buildTextToolbar(),
        // Reading indicator
        if (_isReading) _buildReadingIndicator(),
        // Text content
        Expanded(
          child: _textFileContent == null
              ? const Center(child: CircularProgressIndicator())
              : Container(
                  color: Theme.of(context).colorScheme.surface,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: SelectableText(
                      _textFileContent!,
                      style: TextStyle(
                        fontSize: 16,
                        height: 1.6,
                        fontFamily:
                            _selectedPdfPath!.toLowerCase().endsWith('.md')
                            ? 'monospace'
                            : null,
                      ),
                      onSelectionChanged: (selection, cause) {
                        if (selection.baseOffset != selection.extentOffset) {
                          final selected = _textFileContent!.substring(
                            selection.baseOffset,
                            selection.extentOffset,
                          );
                          setState(() => _selectedText = selected);
                        }
                      },
                    ),
                  ),
                ),
        ),
        // Info bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            border: Border(
              top: BorderSide(color: Theme.of(context).dividerColor),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('${_textFileContent?.length ?? 0} characters'),
              const SizedBox(width: 16),
              Text('${_textFileContent?.split('\n').length ?? 0} lines'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTextToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          // File type indicator
          Chip(
            avatar: Icon(
              _selectedPdfPath!.toLowerCase().endsWith('.md')
                  ? Icons.code
                  : Icons.article,
              size: 16,
            ),
            label: Text(
              _selectedPdfPath!.toLowerCase().endsWith('.md')
                  ? 'Markdown'
                  : 'Text',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          const SizedBox(width: 8),
          // Select all button
          TextButton.icon(
            onPressed: () {
              setState(() => _selectedText = _textFileContent);
            },
            icon: const Icon(Icons.select_all, size: 18),
            label: const Text('Select All'),
          ),
          const Spacer(),
          // TTS controls
          if (_selectedText != null && _selectedText!.isNotEmpty && !_isReading)
            Chip(
              avatar: const Icon(Icons.text_fields, size: 16),
              label: Text(
                '${_selectedText!.length} chars selected',
                style: const TextStyle(fontSize: 12),
              ),
            )
          else if (_textFileContent != null && !_isReading)
            Chip(
              avatar: const Icon(Icons.auto_stories, size: 16),
              label: Text(
                '${_textFileContent!.length} chars ready',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          const SizedBox(width: 8),
          if (!_isReading && !_isGeneratingAudiobook)
            FilledButton.icon(
              onPressed: _hasTextToRead ? _startReading : null,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Read Aloud'),
            )
          else if (_isReading)
            Row(
              children: [
                if (_isPaused)
                  FilledButton.icon(
                    onPressed: _resumeReading,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Resume'),
                  )
                else
                  FilledButton.tonalIcon(
                    onPressed: _pauseReading,
                    icon: const Icon(Icons.pause),
                    label: const Text('Pause'),
                  ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: _stopReading,
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.red.shade100,
                    foregroundColor: Colors.red.shade700,
                  ),
                ),
              ],
            ),
          // Audiobook generation button (text files)
          if (!_isReading && !_isGeneratingAudiobook) ...[
            const SizedBox(width: 8),
            FilledButton.tonalIcon(
              onPressed: _hasTextToRead ? _startAudiobookGeneration : null,
              icon: const Icon(Icons.audiotrack),
              label: const Text('Convert to Audiobook'),
            ),
          ],
          // Audiobook generation progress (text files)
          if (_isGeneratingAudiobook) ...[
            const SizedBox(width: 8),
            _buildAudiobookProgress(),
          ],
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          // Zoom controls
          IconButton(
            icon: const Icon(Icons.zoom_out),
            onPressed: () => _pdfController.zoomLevel -= 0.25,
            tooltip: 'Zoom out',
          ),
          IconButton(
            icon: const Icon(Icons.zoom_in),
            onPressed: () => _pdfController.zoomLevel += 0.25,
            tooltip: 'Zoom in',
          ),
          const VerticalDivider(),
          // Navigation
          IconButton(
            icon: const Icon(Icons.navigate_before),
            onPressed: () => _pdfController.previousPage(),
            tooltip: 'Previous page',
          ),
          IconButton(
            icon: const Icon(Icons.navigate_next),
            onPressed: () => _pdfController.nextPage(),
            tooltip: 'Next page',
          ),
          const Spacer(),
          // Status indicator
          if (_isExtractingText)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          // TTS controls
          if (_selectedText != null && _selectedText!.isNotEmpty && !_isReading)
            Chip(
              avatar: const Icon(Icons.text_fields, size: 16),
              label: Text(
                '${_selectedText!.length} chars selected',
                style: const TextStyle(fontSize: 12),
              ),
            )
          else if (_pdfExtractedText != null && !_isReading)
            Chip(
              avatar: const Icon(Icons.auto_stories, size: 16),
              label: Text(
                '${_pdfExtractedText!.length} chars ready',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          const SizedBox(width: 8),
          if (!_isReading && !_isGeneratingAudiobook)
            FilledButton.icon(
              onPressed: _hasTextToRead ? _startReading : null,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Read Aloud'),
            )
          else if (_isReading)
            Row(
              children: [
                if (_isPaused)
                  FilledButton.icon(
                    onPressed: _resumeReading,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Resume'),
                  )
                else
                  FilledButton.tonalIcon(
                    onPressed: _pauseReading,
                    icon: const Icon(Icons.pause),
                    label: const Text('Pause'),
                  ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: _stopReading,
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.red.shade100,
                    foregroundColor: Colors.red.shade700,
                  ),
                ),
              ],
            ),
          // Audiobook generation button
          if (!_isReading && !_isGeneratingAudiobook) ...[
            const SizedBox(width: 8),
            FilledButton.tonalIcon(
              onPressed: _hasTextToRead ? _startAudiobookGeneration : null,
              icon: const Icon(Icons.audiotrack),
              label: const Text('Convert to Audiobook'),
            ),
          ],
          // Audiobook generation progress
          if (_isGeneratingAudiobook) ...[
            const SizedBox(width: 8),
            _buildAudiobookProgress(),
          ],
        ],
      ),
    );
  }

  Widget _buildAudiobookProgress() {
    final percent = _audiobookTotalChunks > 0
        ? (_audiobookCurrentChunk / _audiobookTotalChunks * 100).round()
        : 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 8),
        Text(
          '$percent% ($_audiobookCurrentChunk/$_audiobookTotalChunks)',
          style: const TextStyle(fontSize: 12),
        ),
        const SizedBox(width: 8),
        TextButton(
          onPressed: _cancelAudiobookGeneration,
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  Widget _buildReadingIndicator() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).colorScheme.primary),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _isPaused ? Icons.pause_circle : Icons.volume_up,
                color: Theme.of(context).colorScheme.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _isPaused
                      ? 'Paused'
                      : 'Sentence ${_currentSentenceIndex + 1}/${_sentences.length}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ),
          if (_currentReadingText.isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildCurrentSentencePreview(),
          ],
          // Word progress bar
          if (_currentSentenceWords.isNotEmpty) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: _currentSentenceWords.isEmpty
                  ? 0
                  : (_currentWordIndex + 1) / _currentSentenceWords.length,
              backgroundColor: Theme.of(context).colorScheme.surface,
              valueColor: AlwaysStoppedAnimation<Color>(
                Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Word ${_currentWordIndex + 1} of ${_currentSentenceWords.length}',
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(
                  context,
                ).colorScheme.onPrimaryContainer.withValues(alpha: 0.7),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCurrentSentencePreview() {
    final colorScheme = Theme.of(context).colorScheme;
    final baseStyle = TextStyle(
      fontSize: 14,
      color: colorScheme.onPrimaryContainer,
      height: 1.35,
    );
    final highlightedStyle = baseStyle.copyWith(
      fontWeight: FontWeight.w700,
      color: colorScheme.onPrimaryContainer,
      backgroundColor: colorScheme.primary.withValues(alpha: 0.25),
    );

    final sentence = _currentReadingText;
    final spans = <InlineSpan>[];
    final tokenPattern = RegExp(r'\S+');

    int cursor = 0;
    int trackedWordIndex = -1;
    for (final match in tokenPattern.allMatches(sentence)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: sentence.substring(cursor, match.start)));
      }

      final token = match.group(0) ?? '';
      final clean = _cleanWordForSearch(token);
      final shouldTrack = clean.length >= 2;
      if (shouldTrack) trackedWordIndex++;

      final isActiveWord =
          !_isPaused &&
          _currentWordIndex >= 0 &&
          shouldTrack &&
          trackedWordIndex == _currentWordIndex;

      spans.add(
        TextSpan(
          text: token,
          style: isActiveWord ? highlightedStyle : baseStyle,
        ),
      );
      cursor = match.end;
    }

    if (cursor < sentence.length) {
      spans.add(TextSpan(text: sentence.substring(cursor)));
    }

    return RichText(
      text: TextSpan(style: baseStyle, children: spans),
    );
  }

  Widget _buildPageIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [Text('Page $_currentPage of $_totalPages')],
      ),
    );
  }
}
