import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as pdf;
import 'package:file_picker/file_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import '../services/api_service.dart';

class PdfReaderScreen extends StatefulWidget {
  const PdfReaderScreen({super.key});

  @override
  State<PdfReaderScreen> createState() => _PdfReaderScreenState();
}

class _PdfReaderScreenState extends State<PdfReaderScreen>
    with AutomaticKeepAliveClientMixin {
  final ApiService _api = ApiService();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final PdfViewerController _pdfController = PdfViewerController();
  final GlobalKey<SfPdfViewerState> _pdfViewerKey = GlobalKey();

  @override
  bool get wantKeepAlive => true;

  // Library state
  List<Map<String, String>> _pdfLibrary = [];
  String? _selectedPdfPath;
  String? _selectedPdfName;
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

  // Word-level sync state
  List<String> _currentSentenceWords = [];
  int _currentWordIndex = -1;
  String _currentHighlightedWord = '';
  StreamSubscription<Duration>? _positionSubscription;
  List<int> _wordTimings = []; // Estimated start time (ms) for each word

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
  String _audiobookOutputFormat = 'mp3'; // 'wav' or 'mp3'

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
    {'id': 'bf_isabella', 'name': 'Isabella (British F)'},
    {'id': 'bf_lily', 'name': 'Lily (British F)'},
    {'id': 'bm_george', 'name': 'George (British M)'},
    {'id': 'bm_daniel', 'name': 'Daniel (British M)'},
    {'id': 'bm_fable', 'name': 'Fable (British M)'},
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
    // Collect documents first
    final foundDocs = <Map<String, String>>[];

    // Default PDF for read aloud
    const defaultPdfPath =
        '/Volumes/SSD4tb/Dropbox/DSS/artifacts/code/TSSUi/backend/data/pdf/jusadbellum.pdf';
    final pdfDirs = <String>{p.dirname(defaultPdfPath)};

    try {
      for (final pdfDir in pdfDirs) {
        final dir = Directory(pdfDir);
        if (await dir.exists()) {
          debugPrint('PDF directory exists: $pdfDir');
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
          debugPrint('PDF directory does not exist: $pdfDir');
        }
      }
    } catch (e) {
      debugPrint('Error loading PDFs: $e');
    }

    // Ensure default PDF is included if present
    try {
      final defaultFile = File(defaultPdfPath);
      if (await defaultFile.exists() &&
          !foundDocs.any((doc) => doc['path'] == defaultPdfPath)) {
        foundDocs.add({'path': defaultPdfPath, 'name': p.basename(defaultPdfPath)});
      }
    } catch (e) {
      debugPrint('Error checking default PDF: $e');
    }

    // Update state with all documents at once
    debugPrint('Loading complete. Found ${foundDocs.length} documents. mounted=$mounted');
    if (mounted) {
      setState(() {
        _pdfLibrary = foundDocs;
        _isInitialized = true;
        debugPrint('setState called. _pdfLibrary.length=${_pdfLibrary.length}');
      });

      // Auto-select default PDF if present, else first document
      if (_selectedPdfPath == null && _pdfLibrary.isNotEmpty) {
        Map<String, String>? defaultDoc;
        for (final doc in _pdfLibrary) {
          if (doc['path'] == defaultPdfPath) {
            defaultDoc = doc;
            break;
          }
        }
        if (defaultDoc != null) {
          debugPrint('Auto-selecting default document: ${defaultDoc['name']}');
          _selectPdf(defaultDoc['path']!, defaultDoc['name']!);
        } else {
          debugPrint('Auto-selecting first document: ${_pdfLibrary.first['name']}');
          _selectPdf(_pdfLibrary.first['path']!, _pdfLibrary.first['name']!);
        }
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
    );

    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      final name = p.basename(path);

      // Add to library if not exists
      if (!_pdfLibrary.any((p) => p['path'] == path)) {
        setState(() {
          _pdfLibrary.add({'path': path, 'name': name});
        });
      }

      _selectPdf(path, name);
    }
  }

  void _selectPdf(String path, String name) {
    setState(() {
      _selectedPdfPath = path;
      _selectedPdfName = name;
      _currentPage = 1;
      _totalPages = 0;
      _textFileContent = null;
      _selectedText = null;
      _pdfExtractedText = null;
      _stopReading();
    });

    // Load text content for .txt and .md files
    final lowerPath = path.toLowerCase();
    if (lowerPath.endsWith('.txt') || lowerPath.endsWith('.md')) {
      _loadTextFile(path);
    } else if (lowerPath.endsWith('.pdf')) {
      _extractPdfText(path);
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading file: $e')),
        );
      }
    }
  }

  Future<void> _extractPdfText(String path) async {
    setState(() => _isExtractingText = true);

    try {
      final file = File(path);
      final bytes = await file.readAsBytes();
      final document = pdf.PdfDocument(inputBytes: bytes);

      final textExtractor = pdf.PdfTextExtractor(document);
      final text = textExtractor.extractText();

      document.dispose();

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
        _stopReading();
      }
    });
  }

  Future<void> _startReading() async {
    if (_selectedPdfPath == null) return;

    // Get text: selected text first, then extracted PDF text, then text file content
    String textToRead = _selectedText ?? '';

    if (textToRead.isEmpty && _pdfExtractedText != null) {
      textToRead = _pdfExtractedText!;
    }

    if (textToRead.isEmpty && _textFileContent != null) {
      textToRead = _textFileContent!;
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

    setState(() {
      _isReading = true;
      _isPaused = false;
      _currentSentenceIndex = 0;
    });

    await _readNextSentence();
  }

  List<String> _splitIntoSentences(String text) {
    // Split by sentence endings
    final sentences = <String>[];
    final buffer = StringBuffer();

    for (int i = 0; i < text.length; i++) {
      buffer.write(text[i]);

      if (text[i] == '.' || text[i] == '!' || text[i] == '?') {
        // Check if followed by space or end
        if (i + 1 >= text.length || text[i + 1] == ' ' || text[i + 1] == '\n') {
          final sentence = buffer.toString().trim();
          if (sentence.isNotEmpty && sentence.length > 1) {
            sentences.add(sentence);
          }
          buffer.clear();
        }
      }
    }

    // Add remaining text as last sentence
    final remaining = buffer.toString().trim();
    if (remaining.isNotEmpty) {
      sentences.add(remaining);
    }

    return sentences;
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
    _currentSentenceWords = sentence
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty && w.length > 1)
        .toList();
    _currentWordIndex = -1;

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

      // Get audio duration for word timing estimation
      final duration = _audioPlayer.duration;
      if (duration != null && _currentSentenceWords.isNotEmpty) {
        _calculateWordTimings(duration);
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('TTS Error: $e')),
        );
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

  void _startWordTracking() {
    _positionSubscription?.cancel();

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
        _currentWordIndex = newWordIndex;
        _highlightCurrentWord();
      }
    });
  }

  void _stopWordTracking() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
  }

  void _highlightCurrentWord() {
    if (_currentWordIndex < 0 || _currentWordIndex >= _currentSentenceWords.length) {
      return;
    }

    final word = _currentSentenceWords[_currentWordIndex];

    // Clear previous highlight
    _searchResult?.clear();

    // Only search for words with enough characters to be meaningful
    if (word.length >= 2) {
      // Remove punctuation for better matching
      final cleanWord = word.replaceAll(RegExp(r'[^\w]'), '');
      if (cleanWord.isNotEmpty) {
        _searchResult = _pdfController.searchText(cleanWord);
      }
    }

    setState(() {
      _currentHighlightedWord = word;
    });
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
      _currentHighlightedWord = '';
      _sentences = [];
      _currentSentenceWords = [];
      _wordTimings = [];
    });
    _audioPlayer.stop();
  }

  void _clearHighlight() {
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start: $e')),
        );
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
        _audiobookStatus = 'Processing chunk $_audiobookCurrentChunk/$_audiobookTotalChunks';
      });

      if (jobStatus == 'completed') {
        _audiobookPollTimer?.cancel();
        final audioUrl = status['audio_url'] as String;
        final durationSecs = status['duration_seconds'] as num;
        final sizeMb = status['file_size_mb'] as num;

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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Generation failed: $error')),
          );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to cancel: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    debugPrint('PDF Reader build: _pdfLibrary.length=${_pdfLibrary.length}');
    return Row(
      children: [
        // Sidebar
        _buildSidebar(),
        // Main content
        Expanded(
          child: _selectedPdfPath != null
              ? _buildPdfViewer()
              : _buildEmptyState(),
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
                const Text('Documents', style: TextStyle(fontWeight: FontWeight.bold)),
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
          // Library list
          Expanded(
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
                            Icon(Icons.auto_stories, size: 48, color: Colors.grey.shade400),
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
                      final isSelected = pdf['path'] == _selectedPdfPath;

                      final lowerName = pdf['name']!.toLowerCase();
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
                        selectedTileColor: Theme.of(context).colorScheme.primaryContainer,
                        leading: Icon(
                          icon,
                          color: isSelected ? Theme.of(context).colorScheme.primary : null,
                          size: 20,
                        ),
                        title: Text(
                          pdf['name']!,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isSelected ? FontWeight.bold : null,
                          ),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.close, size: 16),
                          onPressed: () => _removePdf(pdf['path']!),
                          visualDensity: VisualDensity.compact,
                        ),
                        onTap: () => _selectPdf(pdf['path']!, pdf['name']!),
                      );
                    },
                  ),
          ),
          // TTS Settings
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              border: Border(
                top: BorderSide(color: Theme.of(context).dividerColor),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('TTS Voice', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                DropdownButtonFormField<String>(
                  value: _selectedVoice,
                  isExpanded: true,
                  isDense: true,
                  decoration: const InputDecoration(
                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    border: OutlineInputBorder(),
                  ),
                  items: _voices.map((v) {
                    return DropdownMenuItem(
                      value: v['id'],
                      child: Text(v['name']!, style: const TextStyle(fontSize: 12)),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => _selectedVoice = value);
                  },
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('Speed:', style: TextStyle(fontSize: 12)),
                    Expanded(
                      child: Slider(
                        value: _speed,
                        min: 0.5,
                        max: 2.0,
                        divisions: 15,
                        label: '${_speed.toStringAsFixed(1)}x',
                        onChanged: (v) => setState(() => _speed = v),
                      ),
                    ),
                    Text('${_speed.toStringAsFixed(1)}x', style: const TextStyle(fontSize: 11)),
                  ],
                ),
              ],
            ),
          ),
          // Audiobook Library
          _buildAudiobookLibrary(),
        ],
      ),
    );
  }

  Widget _buildAudiobookLibrary() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Icon(Icons.library_music, size: 16),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Audiobooks',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 16),
                  onPressed: _loadAudiobooks,
                  tooltip: 'Refresh',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          // Playback speed control
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
                    divisions: 15,
                    label: '${_audiobookPlaybackSpeed.toStringAsFixed(1)}x',
                    onChanged: _setAudiobookSpeed,
                  ),
                ),
                Text(
                  '${_audiobookPlaybackSpeed.toStringAsFixed(1)}x',
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
                    ButtonSegment(value: 'mp3', label: Text('MP3', style: TextStyle(fontSize: 10))),
                    ButtonSegment(value: 'wav', label: Text('WAV', style: TextStyle(fontSize: 10))),
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
          // List
          if (_isLoadingAudiobooks)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (_audiobooks.isEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'No audiobooks yet',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 250),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _audiobooks.length,
                itemBuilder: (context, index) {
                  final book = _audiobooks[index];
                  final jobId = book['job_id'] as String;
                  final duration = book['duration_seconds'] as num;
                  final sizeMb = book['size_mb'] as num;
                  final isThisPlaying = _playingAudiobookId == jobId;

                  // Format duration
                  final mins = (duration / 60).floor();
                  final secs = (duration % 60).round();
                  final durationStr = mins > 0 ? '${mins}m ${secs}s' : '${secs}s';

                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: isThisPlaying
                          ? Theme.of(context).colorScheme.primaryContainer
                          : null,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                          leading: Icon(
                            Icons.audiotrack,
                            color: isThisPlaying
                                ? Theme.of(context).colorScheme.primary
                                : null,
                            size: 20,
                          ),
                          title: Text(
                            'Audiobook $jobId',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: isThisPlaying ? FontWeight.bold : null,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '$durationStr • ${sizeMb.toStringAsFixed(1)} MB',
                            style: const TextStyle(fontSize: 10),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, size: 16),
                            onPressed: () => _deleteAudiobook(jobId),
                            tooltip: 'Delete',
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ),
                        // Playback controls
                        Padding(
                          padding: const EdgeInsets.only(left: 8, right: 8, bottom: 8),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Play button
                              IconButton(
                                icon: const Icon(Icons.play_arrow, size: 20),
                                onPressed: (!isThisPlaying || _isAudiobookPaused)
                                    ? () => _playAudiobookFromList(book)
                                    : null,
                                tooltip: 'Play',
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 32),
                              ),
                              // Pause button
                              IconButton(
                                icon: const Icon(Icons.pause, size: 20),
                                onPressed: (isThisPlaying && !_isAudiobookPaused)
                                    ? _pauseAudiobookPlayback
                                    : null,
                                tooltip: 'Pause',
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 32),
                              ),
                              // Stop button
                              IconButton(
                                icon: const Icon(Icons.stop, size: 20),
                                onPressed: isThisPlaying ? _stopAudiobookPlayback : null,
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
      _audiobookPlayerSubscription = _audioPlayer.playerStateStream.listen((state) {
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to play: $e')),
        );
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete: $e')),
          );
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
    final file = File(_selectedPdfPath!);
    if (!file.existsSync()) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text('File not found:\n$_selectedPdfPath', textAlign: TextAlign.center),
          ],
        ),
      );
    }

    // Use text viewer for .txt and .md files
    if (_isTextFile) {
      return _buildTextViewer();
    }

    return Column(
      children: [
        // Toolbar
        _buildToolbar(),
        // Reading indicator (shown when reading)
        if (_isReading) _buildReadingIndicator(),
        // PDF Viewer (full width, highlighting via searchText)
        Expanded(
          child: SfPdfViewer.file(
            file,
            key: _pdfViewerKey,
            controller: _pdfController,
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
        // Page indicator
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
                        fontFamily: _selectedPdfPath!.toLowerCase().endsWith('.md')
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
              _selectedPdfPath!.toLowerCase().endsWith('.md') ? 'Markdown' : 'Text',
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
              // Current word being read
              if (_currentHighlightedWord.isNotEmpty && !_isPaused)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    _currentHighlightedWord,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onPrimary,
                    ),
                  ),
                ),
            ],
          ),
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
                color: Theme.of(context).colorScheme.onPrimaryContainer.withOpacity(0.7),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPageIndicator() {
    return Container(
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
          Text('Page $_currentPage of $_totalPages'),
        ],
      ),
    );
  }
}
