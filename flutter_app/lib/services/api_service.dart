import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

class ApiService {
  static const String baseUrl = 'http://localhost:7693';
  static const Duration _requestTimeout = Duration(seconds: 120);

  Future<http.Response> _get(Uri uri, {Duration timeout = _requestTimeout}) {
    return http.get(uri).timeout(timeout);
  }

  Future<http.Response> _post(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Duration timeout = _requestTimeout,
  }) {
    return http.post(uri, headers: headers, body: body).timeout(timeout);
  }

  Future<http.Response> _delete(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Duration timeout = _requestTimeout,
  }) {
    return http.delete(uri, headers: headers, body: body).timeout(timeout);
  }

  dynamic _decodeJson(String body) {
    try {
      return json.decode(body);
    } catch (e) {
      throw Exception('Backend returned invalid JSON');
    }
  }

  String _extractErrorMessage(http.Response response) {
    final fallback = response.body.trim().isEmpty
        ? 'HTTP ${response.statusCode}'
        : response.body.trim();
    try {
      final parsed = _decodeJson(response.body);
      if (parsed is Map<String, dynamic>) {
        final detail = parsed['detail'] ?? parsed['error'] ?? parsed['message'];
        if (detail != null) {
          return detail.toString();
        }
      }
    } catch (_) {
      // Fall back to raw body.
    }
    return fallback;
  }

  Exception _apiError(String action, http.Response response) {
    return Exception(
      '$action failed (${response.statusCode}): ${_extractErrorMessage(response)}',
    );
  }

  Future<String> _awaitJobAudioUrl(
    String jobId, {
    String actionLabel = 'Generation',
    Duration timeout = const Duration(minutes: 30),
    Duration pollInterval = const Duration(seconds: 2),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final job = await getJob(jobId);
      final status = (job['status'] as String? ?? '').toLowerCase();
      if (status == 'completed') {
        final audioPath = job['audio_url'] as String?;
        if (audioPath != null && audioPath.isNotEmpty) {
          return '$baseUrl$audioPath';
        }
        throw Exception('$actionLabel completed but no audio was produced');
      }
      if (status == 'failed') {
        final error = job['error']?.toString() ?? 'Unknown backend error';
        throw Exception('$actionLabel failed: $error');
      }
      if (status == 'cancelled') {
        throw Exception('$actionLabel was cancelled');
      }
      await Future.delayed(pollInterval);
    }
    throw Exception('$actionLabel timed out waiting for job completion');
  }

  String _extractDownloadFilename(String? contentDisposition, String fallback) {
    if (contentDisposition == null || contentDisposition.isEmpty) {
      return fallback;
    }
    final quotedMatch = RegExp(
      r'filename="([^"]+)"',
    ).firstMatch(contentDisposition);
    if (quotedMatch != null) {
      return quotedMatch.group(1) ?? fallback;
    }
    final plainMatch = RegExp(
      r'filename=([^;]+)',
    ).firstMatch(contentDisposition);
    if (plainMatch != null) {
      return plainMatch.group(1)?.trim() ?? fallback;
    }
    return fallback;
  }

  // Health check
  Future<bool> checkHealth() async {
    try {
      final response = await _get(Uri.parse('$baseUrl/api/health'));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // System info
  Future<Map<String, dynamic>> getSystemInfo() async {
    final response = await _get(Uri.parse('$baseUrl/api/system/info'));
    if (response.statusCode == 200) {
      return _decodeJson(response.body);
    }
    throw _apiError('Failed to load system info', response);
  }

  Future<List<Map<String, dynamic>>> getSystemFolders() async {
    final response = await _get(Uri.parse('$baseUrl/api/system/folders'));
    if (response.statusCode == 200) {
      final data = _decodeJson(response.body) as Map<String, dynamic>;
      return List<Map<String, dynamic>>.from(
        data['folders'] as List<dynamic>? ?? const [],
      );
    }
    throw _apiError('Failed to load system folders', response);
  }

  // System stats (CPU/RAM/GPU)
  Future<Map<String, dynamic>> getSystemStats() async {
    final response = await _get(Uri.parse('$baseUrl/api/system/stats'));
    if (response.statusCode == 200) {
      return _decodeJson(response.body);
    }
    throw _apiError('Failed to load system stats', response);
  }

  Future<Map<String, dynamic>> exportDiagnosticLogs() async {
    final response = await _get(
      Uri.parse('$baseUrl/api/system/diagnostics/export'),
      timeout: const Duration(seconds: 180),
    );
    if (response.statusCode == 200) {
      final now = DateTime.now();
      final fallbackName =
          'mimika_diagnostics_'
          '${now.year}'
          '${now.month.toString().padLeft(2, '0')}'
          '${now.day.toString().padLeft(2, '0')}.zip';
      final fileName = _extractDownloadFilename(
        response.headers['content-disposition'],
        fallbackName,
      );
      return {'fileName': fileName, 'bytes': response.bodyBytes};
    }
    throw _apiError('Failed to export diagnostic logs', response);
  }

  Future<Map<String, dynamic>> getSystemLogs({int maxLines = 500}) async {
    final response = await _get(
      Uri.parse('$baseUrl/api/system/logs?max_lines=$maxLines'),
      timeout: const Duration(seconds: 45),
    );
    if (response.statusCode == 200) {
      return _decodeJson(response.body);
    }
    throw _apiError('Failed to load system logs', response);
  }

  Future<Map<String, dynamic>> exportSystemLogs({int maxLines = 2000}) async {
    final response = await _get(
      Uri.parse('$baseUrl/api/system/logs/export?max_lines=$maxLines'),
      timeout: const Duration(seconds: 120),
    );
    if (response.statusCode == 200) {
      final now = DateTime.now();
      final fallbackName =
          'mimika_system_logs_'
          '${now.year}'
          '${now.month.toString().padLeft(2, '0')}'
          '${now.day.toString().padLeft(2, '0')}.log';
      final fileName = _extractDownloadFilename(
        response.headers['content-disposition'],
        fallbackName,
      );
      return {'fileName': fileName, 'bytes': response.bodyBytes};
    }
    throw _apiError('Failed to export system logs', response);
  }

  // ============== Kokoro ==============

  Future<Map<String, dynamic>> getKokoroVoices() async {
    final response = await _get(Uri.parse('$baseUrl/api/kokoro/voices'));
    if (response.statusCode == 200) {
      return _decodeJson(response.body);
    }
    throw _apiError('Failed to load Kokoro voices', response);
  }

  Future<String> generateKokoro({
    required String text,
    required String voice,
    double speed = 1.0,
    bool smartChunking = true,
    int maxCharsPerChunk = 1500,
    int crossfadeMs = 40,
  }) async {
    final response = await _post(
      Uri.parse('$baseUrl/api/kokoro/generate'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'text': text,
        'voice': voice,
        'speed': speed,
        'smart_chunking': smartChunking,
        'max_chars_per_chunk': maxCharsPerChunk,
        'crossfade_ms': crossfadeMs,
      }),
    );
    if (response.statusCode == 200) {
      final data = _decodeJson(response.body);
      return '$baseUrl${data['audio_url']}';
    }
    throw _apiError('Failed to generate Kokoro audio', response);
  }

  // ============== Supertonic ==============

  Future<Map<String, dynamic>> getSupertonicVoices() async {
    final response = await _get(Uri.parse('$baseUrl/api/supertonic/voices'));
    if (response.statusCode == 200) {
      return _decodeJson(response.body);
    }
    throw _apiError('Failed to load Supertonic voices', response);
  }

  Future<Map<String, dynamic>> getSupertonicLanguages() async {
    final response = await _get(Uri.parse('$baseUrl/api/supertonic/languages'));
    if (response.statusCode == 200) {
      return _decodeJson(response.body);
    }
    throw _apiError('Failed to load Supertonic languages', response);
  }

  Future<Map<String, dynamic>> getSupertonicInfo() async {
    final response = await _get(Uri.parse('$baseUrl/api/supertonic/info'));
    if (response.statusCode == 200) {
      return _decodeJson(response.body);
    }
    throw _apiError('Failed to load Supertonic info', response);
  }

  Future<String> generateSupertonic({
    required String text,
    required String voice,
    String language = 'en',
    double speed = 1.05,
    int totalSteps = 5,
    bool smartChunking = true,
    int maxCharsPerChunk = 300,
    int silenceMs = 300,
  }) async {
    final response = await _post(
      Uri.parse('$baseUrl/api/supertonic/generate'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'text': text,
        'voice': voice,
        'language': language,
        'speed': speed,
        'total_steps': totalSteps,
        'smart_chunking': smartChunking,
        'max_chars_per_chunk': maxCharsPerChunk,
        'silence_ms': silenceMs,
      }),
      timeout: const Duration(seconds: 180),
    );
    if (response.statusCode == 200) {
      final data = _decodeJson(response.body);
      return '$baseUrl${data['audio_url']}';
    }
    throw _apiError('Failed to generate Supertonic audio', response);
  }

  // ============== CosyVoice3 (backed by Supertonic-2) ==============

  Future<Map<String, dynamic>> getCosyVoice3Voices() async {
    final response = await _get(Uri.parse('$baseUrl/api/cosyvoice3/voices'));
    if (response.statusCode == 200) {
      return _decodeJson(response.body);
    }
    throw _apiError('Failed to load CosyVoice3 voices', response);
  }

  Future<Map<String, dynamic>> getCosyVoice3Languages() async {
    final response = await _get(Uri.parse('$baseUrl/api/cosyvoice3/languages'));
    if (response.statusCode == 200) {
      return _decodeJson(response.body);
    }
    throw _apiError('Failed to load CosyVoice3 languages', response);
  }

  Future<Map<String, dynamic>> getCosyVoice3Info() async {
    final response = await _get(Uri.parse('$baseUrl/api/cosyvoice3/info'));
    if (response.statusCode == 200) {
      return _decodeJson(response.body);
    }
    throw _apiError('Failed to load CosyVoice3 info', response);
  }

  Future<String> generateCosyVoice3({
    required String text,
    required String voice,
    String language = 'en',
    double speed = 1.05,
    int totalSteps = 5,
    bool smartChunking = true,
    int maxCharsPerChunk = 300,
    int silenceMs = 300,
  }) async {
    final response = await _post(
      Uri.parse('$baseUrl/api/cosyvoice3/generate'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'text': text,
        'voice': voice,
        'language': language,
        'speed': speed,
        'total_steps': totalSteps,
        'smart_chunking': smartChunking,
        'max_chars_per_chunk': maxCharsPerChunk,
        'silence_ms': silenceMs,
      }),
      timeout: const Duration(seconds: 180),
    );
    if (response.statusCode == 200) {
      final data = _decodeJson(response.body);
      return '$baseUrl${data['audio_url']}';
    }
    throw _apiError('Failed to generate CosyVoice3 audio', response);
  }

  Future<List<int>> alignWordsToAudio({
    required String text,
    required String audioUrl,
    String language = 'en',
  }) async {
    final response = await _post(
      Uri.parse('$baseUrl/api/tts/align-words'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'text': text,
        'audio_url': audioUrl,
        'language': language,
      }),
      timeout: const Duration(seconds: 30),
    );
    if (response.statusCode == 200) {
      final data = _decodeJson(response.body);
      final timings = (data['timings_ms'] as List<dynamic>? ?? const [])
          .map((e) => (e as num).toInt())
          .toList();
      return timings;
    }
    throw _apiError('Failed to align words to audio', response);
  }

  // ============== Samples ==============

  Future<List<Map<String, dynamic>>> getSamples(String engine) async {
    final response = await _get(Uri.parse('$baseUrl/api/samples/$engine'));
    if (response.statusCode == 200) {
      final data = _decodeJson(response.body);
      return List<Map<String, dynamic>>.from(data['samples']);
    }
    throw _apiError('Failed to load samples', response);
  }

  // ============== Pregenerated Samples ==============

  Future<List<Map<String, dynamic>>> getPregeneratedSamples({
    String? engine,
  }) async {
    final uri = engine != null
        ? Uri.parse('$baseUrl/api/pregenerated?engine=$engine')
        : Uri.parse('$baseUrl/api/pregenerated');
    final response = await _get(uri);
    if (response.statusCode == 200) {
      final data = _decodeJson(response.body);
      return List<Map<String, dynamic>>.from(data['samples']);
    }
    throw _apiError('Failed to load pregenerated samples', response);
  }

  String getPregeneratedAudioUrl(String audioPath) {
    return '$baseUrl$audioPath';
  }

  // ============== Voice Samples ==============

  Future<List<Map<String, dynamic>>> getVoiceSamples() async {
    final response = await _get(Uri.parse('$baseUrl/api/voice-samples'));
    if (response.statusCode == 200) {
      final data = _decodeJson(response.body);
      return List<Map<String, dynamic>>.from(data['samples']);
    }
    throw _apiError('Failed to load voice samples', response);
  }

  String getSampleAudioUrl(String audioPath) {
    return '$baseUrl$audioPath';
  }

  // ============== Qwen3-TTS (Voice Clone + Custom Voice) ==============

  Future<Map<String, dynamic>> getQwen3Voices() async {
    final response = await _get(Uri.parse('$baseUrl/api/qwen3/voices'));
    if (response.statusCode == 200) {
      return _decodeJson(response.body);
    }
    throw _apiError('Failed to load Qwen3 voices', response);
  }

  Future<Map<String, dynamic>> getQwen3Speakers() async {
    final response = await _get(Uri.parse('$baseUrl/api/qwen3/speakers'));
    if (response.statusCode == 200) {
      return _decodeJson(response.body);
    }
    throw _apiError('Failed to load Qwen3 speakers', response);
  }

  Future<Map<String, dynamic>> getQwen3Models() async {
    final response = await _get(Uri.parse('$baseUrl/api/qwen3/models'));
    if (response.statusCode == 200) {
      return _decodeJson(response.body);
    }
    throw _apiError('Failed to load Qwen3 models', response);
  }

  /// Generate speech using Qwen3-TTS.
  ///
  /// [mode] can be 'clone' (voice cloning) or 'custom' (preset speakers).
  /// For clone mode, provide [voiceName].
  /// For custom mode, provide [speaker].
  Future<String> generateQwen3({
    required String text,
    String mode = 'clone',
    String? voiceName,
    String? speaker,
    String language = 'Auto',
    double speed = 1.0,
    String modelSize = '0.6B',
    String modelQuantization = 'bf16',
    String? instruct,
    // Advanced parameters
    double temperature = 0.9,
    double topP = 0.9,
    int topK = 50,
    double repetitionPenalty = 1.0,
    int seed = -1,
    bool unloadAfter = false,
  }) async {
    final body = <String, dynamic>{
      'text': text,
      'mode': mode,
      'language': language,
      'speed': speed,
      'model_size': modelSize,
      'model_quantization': modelQuantization,
      'temperature': temperature,
      'top_p': topP,
      'top_k': topK,
      'repetition_penalty': repetitionPenalty,
      'seed': seed,
      'unload_after': unloadAfter,
      'enqueue': true,
    };

    if (mode == 'clone') {
      body['voice_name'] = voiceName;
    } else {
      body['speaker'] = speaker;
      if (instruct != null && instruct.isNotEmpty) {
        body['instruct'] = instruct;
      }
    }

    final response = await _post(
      Uri.parse('$baseUrl/api/qwen3/generate'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(body),
    );
    if (response.statusCode == 200) {
      final data = _decodeJson(response.body);
      final audioPath = data['audio_url'] as String?;
      if (audioPath != null && audioPath.isNotEmpty) {
        return '$baseUrl$audioPath';
      }
      final jobId = data['job_id']?.toString();
      if (jobId != null && jobId.isNotEmpty) {
        return _awaitJobAudioUrl(jobId, actionLabel: 'Qwen3 generation');
      }
      throw Exception('Failed to generate Qwen3 audio: missing audio_url/job_id');
    }
    throw _apiError('Failed to generate Qwen3 audio', response);
  }

  Future<Map<String, dynamic>> uploadQwen3Voice(
    String name,
    Uint8List fileBytes,
    String fileName,
    String transcript,
  ) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/qwen3/voices'),
    );
    request.fields['name'] = name;
    request.fields['transcript'] = transcript;
    request.files.add(
      http.MultipartFile.fromBytes('file', fileBytes, filename: fileName),
    );

    final response = await request.send().timeout(_requestTimeout);
    final body = await response.stream.bytesToString();
    if (response.statusCode != 200) {
      throw Exception('Failed to upload Qwen3 voice: $body');
    }
    if (body.trim().isEmpty) {
      return const {};
    }
    final parsed = _decodeJson(body);
    if (parsed is Map<String, dynamic>) {
      return parsed;
    }
    return const {};
  }

  Future<void> deleteQwen3Voice(String name) async {
    final response = await _delete(
      Uri.parse('$baseUrl/api/qwen3/voices/$name'),
    );
    if (response.statusCode != 200) {
      throw _apiError('Failed to delete voice', response);
    }
  }

  Future<void> updateQwen3Voice(
    String name, {
    String? newName,
    String? transcript,
    Uint8List? fileBytes,
    String? fileName,
  }) async {
    var request = http.MultipartRequest(
      'PUT',
      Uri.parse('$baseUrl/api/qwen3/voices/$name'),
    );
    if (newName != null) request.fields['new_name'] = newName;
    if (transcript != null) request.fields['transcript'] = transcript;
    if (fileBytes != null) {
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          fileBytes,
          filename: fileName ?? 'voice.wav',
        ),
      );
    }

    final response = await request.send().timeout(_requestTimeout);
    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      throw Exception('Failed to update voice: $body');
    }
  }

  Future<List<String>> getQwen3Languages() async {
    final response = await _get(Uri.parse('$baseUrl/api/qwen3/languages'));
    if (response.statusCode == 200) {
      final data = _decodeJson(response.body);
      return List<String>.from(data['languages']);
    }
    throw _apiError('Failed to load Qwen3 languages', response);
  }

  Future<Map<String, dynamic>> getQwen3Info() async {
    final response = await _get(Uri.parse('$baseUrl/api/qwen3/info'));
    if (response.statusCode == 200) {
      return _decodeJson(response.body);
    }
    throw _apiError('Failed to load Qwen3 info', response);
  }

  // ============== Chatterbox (Voice Clone) ==============

  Future<Map<String, dynamic>> getChatterboxVoices() async {
    final response = await _get(Uri.parse('$baseUrl/api/chatterbox/voices'));
    if (response.statusCode == 200) {
      return _decodeJson(response.body);
    }
    throw _apiError('Failed to load Chatterbox voices', response);
  }

  Future<String> generateChatterbox({
    required String text,
    required String voiceName,
    String language = 'en',
    double speed = 1.0,
    double temperature = 0.8,
    double cfgWeight = 1.0,
    double exaggeration = 0.5,
    int seed = -1,
    int maxChars = 300,
    int crossfadeMs = 0,
    bool unloadAfter = false,
  }) async {
    final body = <String, dynamic>{
      'text': text,
      'voice_name': voiceName,
      'language': language,
      'speed': speed,
      'temperature': temperature,
      'cfg_weight': cfgWeight,
      'exaggeration': exaggeration,
      'seed': seed,
      'max_chars': maxChars,
      'crossfade_ms': crossfadeMs,
      'unload_after': unloadAfter,
    };

    final response = await _post(
      Uri.parse('$baseUrl/api/chatterbox/generate'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(body),
    );
    if (response.statusCode == 200) {
      final data = _decodeJson(response.body);
      return '$baseUrl${data['audio_url']}';
    }
    throw _apiError('Failed to generate Chatterbox audio', response);
  }

  Future<void> uploadChatterboxVoice(
    String name,
    Uint8List fileBytes,
    String fileName,
    String transcript,
  ) async {
    var request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/chatterbox/voices'),
    );
    request.fields['name'] = name;
    request.fields['transcript'] = transcript;
    request.files.add(
      http.MultipartFile.fromBytes('file', fileBytes, filename: fileName),
    );

    final response = await request.send().timeout(_requestTimeout);
    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      throw Exception('Failed to upload Chatterbox voice: $body');
    }
  }

  Future<void> deleteChatterboxVoice(String name) async {
    final response = await _delete(
      Uri.parse('$baseUrl/api/chatterbox/voices/${Uri.encodeComponent(name)}'),
    );
    if (response.statusCode != 200) {
      throw _apiError('Failed to delete voice', response);
    }
  }

  Future<void> updateChatterboxVoice(
    String name, {
    String? newName,
    String? transcript,
    Uint8List? fileBytes,
    String? fileName,
  }) async {
    var request = http.MultipartRequest(
      'PUT',
      Uri.parse('$baseUrl/api/chatterbox/voices/$name'),
    );
    if (newName != null) request.fields['new_name'] = newName;
    if (transcript != null) request.fields['transcript'] = transcript;
    if (fileBytes != null) {
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          fileBytes,
          filename: fileName ?? 'voice.wav',
        ),
      );
    }

    final response = await request.send().timeout(_requestTimeout);
    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      throw Exception('Failed to update voice: $body');
    }
  }

  Future<List<String>> getChatterboxLanguages() async {
    final response = await _get(Uri.parse('$baseUrl/api/chatterbox/languages'));
    if (response.statusCode == 200) {
      final data = _decodeJson(response.body);
      return List<String>.from(data['languages']);
    }
    throw _apiError('Failed to load Chatterbox languages', response);
  }

  Future<Map<String, dynamic>> getChatterboxInfo() async {
    final response = await _get(Uri.parse('$baseUrl/api/chatterbox/info'));
    if (response.statusCode == 200) {
      return _decodeJson(response.body);
    }
    throw _apiError('Failed to load Chatterbox info', response);
  }

  Future<Map<String, dynamic>> getChatterboxDictaStatus() async {
    final response = await _get(
      Uri.parse('$baseUrl/api/chatterbox/dicta/status'),
    );
    if (response.statusCode == 200) {
      return _decodeJson(response.body);
    }
    throw _apiError('Failed to load Dicta status', response);
  }

  Future<Map<String, dynamic>> downloadChatterboxDictaModel() async {
    final response = await _post(
      Uri.parse('$baseUrl/api/chatterbox/dicta/download'),
      headers: {'Content-Type': 'application/json'},
    );
    if (response.statusCode == 200) {
      return _decodeJson(response.body);
    }
    throw _apiError('Failed to start Dicta download', response);
  }

  // ============== IndexTTS-2 (Voice Clone) ==============

  Future<Map<String, dynamic>> getIndexTTS2Voices() async {
    final response = await _get(Uri.parse('$baseUrl/api/indextts2/voices'));
    if (response.statusCode == 200) {
      return _decodeJson(response.body);
    }
    throw _apiError('Failed to load IndexTTS-2 voices', response);
  }

  Future<String> generateIndexTTS2({
    required String text,
    required String voiceName,
    double speed = 1.0,
    int maxChars = 300,
    int crossfadeMs = 0,
    bool unloadAfter = false,
  }) async {
    final body = <String, dynamic>{
      'text': text,
      'voice_name': voiceName,
      'speed': speed,
      'max_chars': maxChars,
      'crossfade_ms': crossfadeMs,
      'unload_after': unloadAfter,
    };

    final response = await _post(
      Uri.parse('$baseUrl/api/indextts2/generate'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(body),
    );
    if (response.statusCode == 200) {
      final data = _decodeJson(response.body);
      return '$baseUrl${data['audio_url']}';
    }
    throw _apiError('Failed to generate IndexTTS-2 audio', response);
  }

  Future<void> uploadIndexTTS2Voice(
    String name,
    Uint8List fileBytes,
    String fileName,
    String transcript,
  ) async {
    var request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/indextts2/voices'),
    );
    request.fields['name'] = name;
    request.fields['transcript'] = transcript;
    request.files.add(
      http.MultipartFile.fromBytes('file', fileBytes, filename: fileName),
    );

    final response = await request.send().timeout(_requestTimeout);
    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      throw Exception('Failed to upload IndexTTS-2 voice: $body');
    }
  }

  Future<void> deleteIndexTTS2Voice(String name) async {
    final response = await _delete(
      Uri.parse('$baseUrl/api/indextts2/voices/$name'),
    );
    if (response.statusCode != 200) {
      throw _apiError('Failed to delete voice', response);
    }
  }

  Future<void> updateIndexTTS2VoiceName(
    String name, {
    String? newName,
    String? transcript,
    Uint8List? fileBytes,
    String? fileName,
  }) async {
    var request = http.MultipartRequest(
      'PUT',
      Uri.parse('$baseUrl/api/indextts2/voices/$name'),
    );
    if (newName != null) request.fields['new_name'] = newName;
    if (transcript != null) request.fields['transcript'] = transcript;
    if (fileBytes != null) {
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          fileBytes,
          filename: fileName ?? 'voice.wav',
        ),
      );
    }

    final response = await request.send().timeout(_requestTimeout);
    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      throw Exception('Failed to update voice: $body');
    }
  }

  Future<Map<String, dynamic>> getIndexTTS2Info() async {
    final response = await _get(Uri.parse('$baseUrl/api/indextts2/info'));
    if (response.statusCode == 200) {
      return _decodeJson(response.body);
    }
    throw _apiError('Failed to load IndexTTS-2 info', response);
  }

  // ============== Model Management ==============

  Future<List<Map<String, dynamic>>> getModelsStatus() async {
    final response = await _get(Uri.parse('$baseUrl/api/models/status'));
    if (response.statusCode == 200) {
      final data = _decodeJson(response.body);
      return List<Map<String, dynamic>>.from(data['models']);
    }
    throw _apiError('Failed to load models status', response);
  }

  Future<Map<String, dynamic>> downloadModel(String modelName) async {
    final response = await _post(
      Uri.parse(
        '$baseUrl/api/models/${Uri.encodeComponent(modelName)}/download',
      ),
      headers: {'Content-Type': 'application/json'},
    );
    if (response.statusCode == 200) {
      return _decodeJson(response.body);
    }
    throw _apiError('Failed to start model download', response);
  }

  Future<Map<String, dynamic>> deleteModel(String modelName) async {
    final response = await _delete(
      Uri.parse('$baseUrl/api/models/${Uri.encodeComponent(modelName)}'),
    );
    if (response.statusCode == 200) {
      return _decodeJson(response.body);
    }
    throw _apiError('Failed to delete model', response);
  }

  // ============== LLM Configuration ==============

  Future<Map<String, dynamic>> getLlmConfig() async {
    final response = await _get(Uri.parse('$baseUrl/api/llm/config'));
    if (response.statusCode == 200) {
      return _decodeJson(response.body);
    }
    throw _apiError('Failed to load LLM config', response);
  }

  Future<List<String>> getOllamaModels() async {
    try {
      final response = await _get(Uri.parse('$baseUrl/api/llm/ollama/models'));
      if (response.statusCode == 200) {
        final data = _decodeJson(response.body);
        if (data['available'] == true) {
          return List<String>.from(data['models']);
        }
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<void> updateLlmConfig(Map<String, dynamic> config) async {
    final response = await _post(
      Uri.parse('$baseUrl/api/llm/config'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(config),
    );
    if (response.statusCode != 200) {
      throw _apiError('Failed to update LLM config', response);
    }
  }

  // ============== Emma IPA ==============

  Future<List<Map<String, dynamic>>> getEmmaIpaSamples() async {
    final response = await _get(Uri.parse('$baseUrl/api/ipa/samples'));
    if (response.statusCode == 200) {
      final data = _decodeJson(response.body);
      return List<Map<String, dynamic>>.from(data['samples']);
    }
    throw _apiError('Failed to load Emma IPA samples', response);
  }

  Future<String> getEmmaIpaSampleText() async {
    final response = await _get(Uri.parse('$baseUrl/api/ipa/sample'));
    if (response.statusCode == 200) {
      final data = _decodeJson(response.body);
      return data['text'] as String;
    }
    throw _apiError('Failed to load Emma IPA sample text', response);
  }

  Future<Map<String, dynamic>> generateEmmaIpa({
    required String text,
    String? provider,
    String? model,
  }) async {
    final response = await _post(
      Uri.parse('$baseUrl/api/ipa/generate'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'text': text,
        if (provider != null) 'provider': provider,
        if (model != null) 'model': model,
      }),
    );
    if (response.statusCode == 200) {
      return _decodeJson(response.body);
    }
    throw _apiError('Failed to generate Emma IPA', response);
  }

  Future<Map<String, dynamic>> getEmmaIpaPregenerated() async {
    final response = await _get(Uri.parse('$baseUrl/api/ipa/pregenerated'));
    if (response.statusCode == 200) {
      return _decodeJson(response.body);
    }
    throw _apiError('Failed to load pregenerated IPA', response);
  }

  // ============== Audiobook Generation ==============

  /// Start audiobook generation from text with optional subtitles.
  /// Returns job info including job_id for status polling.
  /// [outputFormat] can be "wav", "mp3", or "m4b".
  /// [subtitleFormat] can be "none", "srt", or "vtt".
  Future<Map<String, dynamic>> startAudiobookGeneration({
    required String text,
    String title = 'Untitled',
    String voice = 'bf_emma',
    double speed = 1.0,
    String outputFormat = 'wav',
    String subtitleFormat = 'none',
    bool smartChunking = true,
    int maxCharsPerChunk = 1500,
    int crossfadeMs = 40,
  }) async {
    final response = await _post(
      Uri.parse('$baseUrl/api/audiobook/generate'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'text': text,
        'title': title,
        'voice': voice,
        'speed': speed,
        'output_format': outputFormat,
        'subtitle_format': subtitleFormat,
        'smart_chunking': smartChunking,
        'max_chars_per_chunk': maxCharsPerChunk,
        'crossfade_ms': crossfadeMs,
      }),
    );
    if (response.statusCode == 200) {
      return _decodeJson(response.body);
    }
    throw _apiError('Failed to start audiobook generation', response);
  }

  /// Get the status of an audiobook generation job.
  Future<Map<String, dynamic>> getAudiobookStatus(String jobId) async {
    final response = await _get(
      Uri.parse('$baseUrl/api/audiobook/status/$jobId'),
    );
    if (response.statusCode == 200) {
      return _decodeJson(response.body);
    }
    throw _apiError('Failed to get audiobook status', response);
  }

  /// Cancel an in-progress audiobook generation job.
  Future<void> cancelAudiobookGeneration(String jobId) async {
    final response = await _post(
      Uri.parse('$baseUrl/api/audiobook/cancel/$jobId'),
    );
    if (response.statusCode != 200) {
      throw _apiError('Failed to cancel audiobook', response);
    }
  }

  /// Get the full URL for an audiobook file.
  String getAudiobookUrl(String audioPath) {
    return '$baseUrl$audioPath';
  }

  /// List all generated audiobooks.
  Future<List<Map<String, dynamic>>> getAudiobooks() async {
    final response = await _get(Uri.parse('$baseUrl/api/audiobook/list'));
    if (response.statusCode == 200) {
      final data = _decodeJson(response.body);
      return List<Map<String, dynamic>>.from(data['audiobooks']);
    }
    throw _apiError('Failed to list audiobooks', response);
  }

  /// Delete an audiobook.
  Future<void> deleteAudiobook(String jobId) async {
    final response = await _delete(Uri.parse('$baseUrl/api/audiobook/$jobId'));
    if (response.statusCode != 200) {
      throw _apiError('Failed to delete audiobook', response);
    }
  }

  // ============== Kokoro Audio Library ==============

  /// List all generated TTS audio files (Kokoro).
  Future<List<Map<String, dynamic>>> getTtsAudioFiles() async {
    final response = await _get(Uri.parse('$baseUrl/api/tts/audio/list'));
    if (response.statusCode == 200) {
      final data = _decodeJson(response.body);
      return List<Map<String, dynamic>>.from(data['audio_files']);
    }
    throw _apiError('Failed to list TTS audio files', response);
  }

  /// Delete a TTS audio file.
  Future<void> deleteTtsAudio(String filename) async {
    final response = await _delete(
      Uri.parse('$baseUrl/api/tts/audio/$filename'),
    );
    if (response.statusCode != 200) {
      throw _apiError('Failed to delete audio file', response);
    }
  }

  /// List all generated Kokoro TTS audio files.
  Future<List<Map<String, dynamic>>> getKokoroAudioFiles() async {
    final response = await _get(Uri.parse('$baseUrl/api/kokoro/audio/list'));
    if (response.statusCode == 200) {
      final data = _decodeJson(response.body);
      return List<Map<String, dynamic>>.from(data['audio_files']);
    }
    throw _apiError('Failed to list Kokoro audio files', response);
  }

  /// Delete a Kokoro audio file.
  Future<void> deleteKokoroAudio(String filename) async {
    final response = await _delete(
      Uri.parse('$baseUrl/api/kokoro/audio/$filename'),
    );
    if (response.statusCode != 200) {
      throw _apiError('Failed to delete audio file', response);
    }
  }

  /// List all generated Supertonic audio files.
  Future<List<Map<String, dynamic>>> getSupertonicAudioFiles() async {
    final response = await _get(
      Uri.parse('$baseUrl/api/supertonic/audio/list'),
    );
    if (response.statusCode == 200) {
      final data = _decodeJson(response.body);
      return List<Map<String, dynamic>>.from(data['audio_files']);
    }
    throw _apiError('Failed to list Supertonic audio files', response);
  }

  /// Delete a Supertonic audio file.
  Future<void> deleteSupertonicAudio(String filename) async {
    final response = await _delete(
      Uri.parse('$baseUrl/api/supertonic/audio/$filename'),
    );
    if (response.statusCode != 200) {
      throw _apiError('Failed to delete audio file', response);
    }
  }

  /// List all generated CosyVoice3 audio files.
  Future<List<Map<String, dynamic>>> getCosyVoice3AudioFiles() async {
    final response = await _get(
      Uri.parse('$baseUrl/api/cosyvoice3/audio/list'),
    );
    if (response.statusCode == 200) {
      final data = _decodeJson(response.body);
      return List<Map<String, dynamic>>.from(data['audio_files']);
    }
    throw _apiError('Failed to list CosyVoice3 audio files', response);
  }

  /// Delete a CosyVoice3 audio file.
  Future<void> deleteCosyVoice3Audio(String filename) async {
    final response = await _delete(
      Uri.parse('$baseUrl/api/cosyvoice3/audio/$filename'),
    );
    if (response.statusCode != 200) {
      throw _apiError('Failed to delete audio file', response);
    }
  }

  // ============== Voice Clone Audio Library ==============

  /// List all generated voice clone audio files (Qwen3).
  Future<List<Map<String, dynamic>>> getVoiceCloneAudioFiles() async {
    final response = await _get(
      Uri.parse('$baseUrl/api/voice-clone/audio/list'),
    );
    if (response.statusCode == 200) {
      final data = _decodeJson(response.body);
      return List<Map<String, dynamic>>.from(data['audio_files']);
    }
    throw _apiError('Failed to list voice clone audio files', response);
  }

  /// Delete a voice clone audio file.
  Future<void> deleteVoiceCloneAudio(String filename) async {
    final response = await _delete(
      Uri.parse('$baseUrl/api/voice-clone/audio/$filename'),
    );
    if (response.statusCode != 200) {
      throw _apiError('Failed to delete audio file', response);
    }
  }

  // ============== PDF Documents ==============

  /// List available documents from the backend.
  Future<List<Map<String, dynamic>>> listPdfDocuments() async {
    final response = await _get(Uri.parse('$baseUrl/api/pdf/list'));
    if (response.statusCode == 200) {
      final data = _decodeJson(response.body);
      return List<Map<String, dynamic>>.from(data['documents']);
    }
    throw _apiError('Failed to list documents', response);
  }

  /// Get the full URL for a backend-served document.
  String getPdfUrl(String pdfPath) {
    return '$baseUrl$pdfPath';
  }

  /// Fetch PDF bytes from the backend by URL path.
  Future<Uint8List> fetchPdfBytes(String urlPath) async {
    final response = await _get(Uri.parse('$baseUrl$urlPath'));
    if (response.statusCode == 200) {
      return response.bodyBytes;
    }
    throw _apiError('Failed to fetch document', response);
  }

  /// Extract text from document bytes using backend extraction.
  Future<String> extractDocumentText(
    Uint8List bytes, {
    String filename = 'document.pdf',
  }) async {
    final lower = filename.toLowerCase();
    final allowed = ['.pdf', '.txt', '.md', '.docx', '.epub'];
    final hasKnownExt = allowed.any(lower.endsWith);
    final safeFilename = hasKnownExt ? filename : '$filename.pdf';
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/pdf/extract-text'),
    );
    request.files.add(
      http.MultipartFile.fromBytes('file', bytes, filename: safeFilename),
    );

    final streamed = await request.send().timeout(_requestTimeout);
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode == 200) {
      final data = _decodeJson(response.body) as Map<String, dynamic>;
      return (data['text'] as String?) ?? '';
    }
    throw _apiError('Failed to extract document text', response);
  }

  /// Backward-compatible PDF extraction wrapper.
  Future<String> extractPdfText(
    Uint8List bytes, {
    String filename = 'document.pdf',
  }) {
    return extractDocumentText(bytes, filename: filename);
  }

  /// Download an audio file (for local save/share flows).
  Future<Uint8List> downloadAudioBytes(String audioUrl) async {
    final absolute =
        audioUrl.startsWith('http://') || audioUrl.startsWith('https://');
    final uri = absolute ? Uri.parse(audioUrl) : Uri.parse('$baseUrl$audioUrl');
    final response = await _get(uri);
    if (response.statusCode == 200) {
      return response.bodyBytes;
    }
    throw _apiError('Failed to download audio', response);
  }

  /// List recent generation jobs from backend history.
  Future<List<Map<String, dynamic>>> getJobs({int limit = 200}) async {
    final response = await _get(Uri.parse('$baseUrl/api/jobs?limit=$limit'));
    if (response.statusCode == 200) {
      final data = _decodeJson(response.body);
      return List<Map<String, dynamic>>.from(data['jobs'] as List<dynamic>);
    }
    throw _apiError('Failed to load jobs', response);
  }

  Future<Map<String, dynamic>> getJob(String jobId) async {
    final response = await _get(Uri.parse('$baseUrl/api/jobs/$jobId'));
    if (response.statusCode == 200) {
      final data = _decodeJson(response.body) as Map<String, dynamic>;
      final job = data['job'];
      if (job is Map<String, dynamic>) {
        return job;
      }
      throw Exception('Failed to parse job response');
    }
    throw _apiError('Failed to load job', response);
  }

  // ============== MCP Server ==============

  /// Fetch available MCP tools from the MCP server via JSON-RPC.
  /// The MCP server runs on port 8010 by default.
  Future<List<Map<String, dynamic>>> getMcpTools({int mcpPort = 8010}) async {
    try {
      // First initialize the MCP session
      final initResponse = await _post(
        Uri.parse('http://localhost:$mcpPort/'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'initialize',
          'params': {
            'protocolVersion': '2024-11-05',
            'capabilities': {},
            'clientInfo': {'name': 'mimikastudio-flutter', 'version': '1.0.0'},
          },
        }),
      );
      if (initResponse.statusCode != 200) return [];

      // Then list tools
      final response = await _post(
        Uri.parse('http://localhost:$mcpPort/'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'jsonrpc': '2.0',
          'id': 2,
          'method': 'tools/list',
          'params': {},
        }),
      );
      if (response.statusCode == 200) {
        final data = _decodeJson(response.body);
        if (data['result'] != null && data['result']['tools'] != null) {
          return List<Map<String, dynamic>>.from(data['result']['tools']);
        }
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  /// Check if the MCP server is reachable.
  Future<bool> checkMcpHealth({int mcpPort = 8010}) async {
    try {
      final response = await _post(
        Uri.parse('http://localhost:$mcpPort/'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'initialize',
          'params': {
            'protocolVersion': '2024-11-05',
            'capabilities': {},
            'clientInfo': {'name': 'mimikastudio-flutter', 'version': '1.0.0'},
          },
        }),
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}
