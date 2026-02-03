import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

class ApiService {
  static const String baseUrl = 'http://localhost:8000';

  // Health check
  Future<bool> checkHealth() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/health'));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // System info
  Future<Map<String, dynamic>> getSystemInfo() async {
    final response = await http.get(Uri.parse('$baseUrl/api/system/info'));
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('Failed to load system info');
  }

  // System stats (CPU/RAM/GPU)
  Future<Map<String, dynamic>> getSystemStats() async {
    final response = await http.get(Uri.parse('$baseUrl/api/system/stats'));
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('Failed to load system stats');
  }

  // ============== Kokoro ==============

  Future<Map<String, dynamic>> getKokoroVoices() async {
    final response = await http.get(Uri.parse('$baseUrl/api/kokoro/voices'));
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('Failed to load Kokoro voices');
  }

  Future<String> generateKokoro({
    required String text,
    required String voice,
    double speed = 1.0,
    bool smartChunking = true,
    int maxCharsPerChunk = 1500,
    int crossfadeMs = 40,
  }) async {
    final response = await http.post(
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
      final data = json.decode(response.body);
      return '$baseUrl${data['audio_url']}';
    }
    throw Exception('Failed to generate Kokoro audio: ${response.body}');
  }

  // ============== Samples ==============

  Future<List<Map<String, dynamic>>> getSamples(String engine) async {
    final response = await http.get(Uri.parse('$baseUrl/api/samples/$engine'));
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return List<Map<String, dynamic>>.from(data['samples']);
    }
    throw Exception('Failed to load samples');
  }

  // ============== Pregenerated Samples ==============

  Future<List<Map<String, dynamic>>> getPregeneratedSamples({String? engine}) async {
    final uri = engine != null
        ? Uri.parse('$baseUrl/api/pregenerated?engine=$engine')
        : Uri.parse('$baseUrl/api/pregenerated');
    final response = await http.get(uri);
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return List<Map<String, dynamic>>.from(data['samples']);
    }
    throw Exception('Failed to load pregenerated samples');
  }

  String getPregeneratedAudioUrl(String audioPath) {
    return '$baseUrl$audioPath';
  }

  // ============== Voice Samples ==============

  Future<List<Map<String, dynamic>>> getVoiceSamples() async {
    final response = await http.get(Uri.parse('$baseUrl/api/voice-samples'));
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return List<Map<String, dynamic>>.from(data['samples']);
    }
    throw Exception('Failed to load voice samples');
  }

  String getSampleAudioUrl(String audioPath) {
    return '$baseUrl$audioPath';
  }

  // ============== Qwen3-TTS (Voice Clone + Custom Voice) ==============

  Future<Map<String, dynamic>> getQwen3Voices() async {
    final response = await http.get(Uri.parse('$baseUrl/api/qwen3/voices'));
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('Failed to load Qwen3 voices');
  }

  Future<Map<String, dynamic>> getQwen3Speakers() async {
    final response = await http.get(Uri.parse('$baseUrl/api/qwen3/speakers'));
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('Failed to load Qwen3 speakers');
  }

  Future<Map<String, dynamic>> getQwen3Models() async {
    final response = await http.get(Uri.parse('$baseUrl/api/qwen3/models'));
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('Failed to load Qwen3 models');
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
      'temperature': temperature,
      'top_p': topP,
      'top_k': topK,
      'repetition_penalty': repetitionPenalty,
      'seed': seed,
      'unload_after': unloadAfter,
    };

    if (mode == 'clone') {
      body['voice_name'] = voiceName;
    } else {
      body['speaker'] = speaker;
      if (instruct != null && instruct.isNotEmpty) {
        body['instruct'] = instruct;
      }
    }

    final response = await http.post(
      Uri.parse('$baseUrl/api/qwen3/generate'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(body),
    );
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return '$baseUrl${data['audio_url']}';
    }
    throw Exception('Failed to generate Qwen3 audio: ${response.body}');
  }

  Future<void> uploadQwen3Voice(String name, File file, String transcript) async {
    var request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/qwen3/voices'),
    );
    request.fields['name'] = name;
    request.fields['transcript'] = transcript;
    request.files.add(await http.MultipartFile.fromPath('file', file.path));

    final response = await request.send();
    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      throw Exception('Failed to upload Qwen3 voice: $body');
    }
  }

  Future<void> deleteQwen3Voice(String name) async {
    final response = await http.delete(Uri.parse('$baseUrl/api/qwen3/voices/$name'));
    if (response.statusCode != 200) {
      throw Exception('Failed to delete voice: ${response.body}');
    }
  }

  Future<void> updateQwen3Voice(String name, {String? newName, String? transcript, File? file}) async {
    var request = http.MultipartRequest(
      'PUT',
      Uri.parse('$baseUrl/api/qwen3/voices/$name'),
    );
    if (newName != null) request.fields['new_name'] = newName;
    if (transcript != null) request.fields['transcript'] = transcript;
    if (file != null) {
      request.files.add(await http.MultipartFile.fromPath('file', file.path));
    }

    final response = await request.send();
    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      throw Exception('Failed to update voice: $body');
    }
  }

  Future<List<String>> getQwen3Languages() async {
    final response = await http.get(Uri.parse('$baseUrl/api/qwen3/languages'));
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return List<String>.from(data['languages']);
    }
    throw Exception('Failed to load Qwen3 languages');
  }

  Future<Map<String, dynamic>> getQwen3Info() async {
    final response = await http.get(Uri.parse('$baseUrl/api/qwen3/info'));
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('Failed to load Qwen3 info');
  }

  // ============== Chatterbox (Voice Clone) ==============

  Future<Map<String, dynamic>> getChatterboxVoices() async {
    final response = await http.get(Uri.parse('$baseUrl/api/chatterbox/voices'));
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('Failed to load Chatterbox voices');
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

    final response = await http.post(
      Uri.parse('$baseUrl/api/chatterbox/generate'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(body),
    );
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return '$baseUrl${data['audio_url']}';
    }
    throw Exception('Failed to generate Chatterbox audio: ${response.body}');
  }

  Future<void> uploadChatterboxVoice(String name, File file, String transcript) async {
    var request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/chatterbox/voices'),
    );
    request.fields['name'] = name;
    request.fields['transcript'] = transcript;
    request.files.add(await http.MultipartFile.fromPath('file', file.path));

    final response = await request.send();
    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      throw Exception('Failed to upload Chatterbox voice: $body');
    }
  }

  Future<void> deleteChatterboxVoice(String name) async {
    final response =
        await http.delete(Uri.parse('$baseUrl/api/chatterbox/voices/$name'));
    if (response.statusCode != 200) {
      throw Exception('Failed to delete voice: ${response.body}');
    }
  }

  Future<void> updateChatterboxVoice(
    String name, {
    String? newName,
    String? transcript,
    File? file,
  }) async {
    var request = http.MultipartRequest(
      'PUT',
      Uri.parse('$baseUrl/api/chatterbox/voices/$name'),
    );
    if (newName != null) request.fields['new_name'] = newName;
    if (transcript != null) request.fields['transcript'] = transcript;
    if (file != null) {
      request.files.add(await http.MultipartFile.fromPath('file', file.path));
    }

    final response = await request.send();
    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      throw Exception('Failed to update voice: $body');
    }
  }

  Future<List<String>> getChatterboxLanguages() async {
    final response = await http.get(Uri.parse('$baseUrl/api/chatterbox/languages'));
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return List<String>.from(data['languages']);
    }
    throw Exception('Failed to load Chatterbox languages');
  }

  Future<Map<String, dynamic>> getChatterboxInfo() async {
    final response = await http.get(Uri.parse('$baseUrl/api/chatterbox/info'));
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('Failed to load Chatterbox info');
  }

  // ============== IndexTTS-2 (Voice Clone) ==============

  Future<Map<String, dynamic>> getIndexTTS2Voices() async {
    final response = await http.get(Uri.parse('$baseUrl/api/indextts2/voices'));
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('Failed to load IndexTTS-2 voices');
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

    final response = await http.post(
      Uri.parse('$baseUrl/api/indextts2/generate'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(body),
    );
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return '$baseUrl${data['audio_url']}';
    }
    throw Exception('Failed to generate IndexTTS-2 audio: ${response.body}');
  }

  Future<void> uploadIndexTTS2Voice(String name, File file, String transcript) async {
    var request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/indextts2/voices'),
    );
    request.fields['name'] = name;
    request.fields['transcript'] = transcript;
    request.files.add(await http.MultipartFile.fromPath('file', file.path));

    final response = await request.send();
    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      throw Exception('Failed to upload IndexTTS-2 voice: $body');
    }
  }

  Future<void> deleteIndexTTS2Voice(String name) async {
    final response =
        await http.delete(Uri.parse('$baseUrl/api/indextts2/voices/$name'));
    if (response.statusCode != 200) {
      throw Exception('Failed to delete voice: ${response.body}');
    }
  }

  Future<void> updateIndexTTS2VoiceName(
    String name, {
    String? newName,
    String? transcript,
    File? file,
  }) async {
    var request = http.MultipartRequest(
      'PUT',
      Uri.parse('$baseUrl/api/indextts2/voices/$name'),
    );
    if (newName != null) request.fields['new_name'] = newName;
    if (transcript != null) request.fields['transcript'] = transcript;
    if (file != null) {
      request.files.add(await http.MultipartFile.fromPath('file', file.path));
    }

    final response = await request.send();
    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      throw Exception('Failed to update voice: $body');
    }
  }

  Future<Map<String, dynamic>> getIndexTTS2Info() async {
    final response = await http.get(Uri.parse('$baseUrl/api/indextts2/info'));
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('Failed to load IndexTTS-2 info');
  }

  // ============== Model Management ==============

  Future<List<Map<String, dynamic>>> getModelsStatus() async {
    final response = await http.get(Uri.parse('$baseUrl/api/models/status'));
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return List<Map<String, dynamic>>.from(data['models']);
    }
    throw Exception('Failed to load models status');
  }

  Future<Map<String, dynamic>> downloadModel(String modelName) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/models/${Uri.encodeComponent(modelName)}/download'),
      headers: {'Content-Type': 'application/json'},
    );
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('Failed to start model download: ${response.body}');
  }

  // ============== LLM Configuration ==============

  Future<Map<String, dynamic>> getLlmConfig() async {
    final response = await http.get(Uri.parse('$baseUrl/api/llm/config'));
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('Failed to load LLM config');
  }

  Future<List<String>> getOllamaModels() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/llm/ollama/models'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
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
    final response = await http.post(
      Uri.parse('$baseUrl/api/llm/config'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(config),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to update LLM config: ${response.body}');
    }
  }

  // ============== Emma IPA ==============

  Future<List<Map<String, dynamic>>> getEmmaIpaSamples() async {
    final response = await http.get(Uri.parse('$baseUrl/api/ipa/samples'));
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return List<Map<String, dynamic>>.from(data['samples']);
    }
    throw Exception('Failed to load Emma IPA samples');
  }

  Future<String> getEmmaIpaSampleText() async {
    final response = await http.get(Uri.parse('$baseUrl/api/ipa/sample'));
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return data['text'] as String;
    }
    throw Exception('Failed to load Emma IPA sample text');
  }

  Future<Map<String, dynamic>> generateEmmaIpa({
    required String text,
    String? provider,
    String? model,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/ipa/generate'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'text': text,
        if (provider != null) 'provider': provider,
        if (model != null) 'model': model,
      }),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('Failed to generate Emma IPA: ${response.body}');
  }

  Future<Map<String, dynamic>> getEmmaIpaPregenerated() async {
    final response = await http.get(Uri.parse('$baseUrl/api/ipa/pregenerated'));
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('Failed to load pregenerated IPA');
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
    final response = await http.post(
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
      return json.decode(response.body);
    }
    throw Exception('Failed to start audiobook generation: ${response.body}');
  }

  /// Get the status of an audiobook generation job.
  Future<Map<String, dynamic>> getAudiobookStatus(String jobId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/audiobook/status/$jobId'),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('Failed to get audiobook status: ${response.body}');
  }

  /// Cancel an in-progress audiobook generation job.
  Future<void> cancelAudiobookGeneration(String jobId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/audiobook/cancel/$jobId'),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to cancel audiobook: ${response.body}');
    }
  }

  /// Get the full URL for an audiobook file.
  String getAudiobookUrl(String audioPath) {
    return '$baseUrl$audioPath';
  }

  /// List all generated audiobooks.
  Future<List<Map<String, dynamic>>> getAudiobooks() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/audiobook/list'),
    );
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return List<Map<String, dynamic>>.from(data['audiobooks']);
    }
    throw Exception('Failed to list audiobooks: ${response.body}');
  }

  /// Delete an audiobook.
  Future<void> deleteAudiobook(String jobId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/api/audiobook/$jobId'),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to delete audiobook: ${response.body}');
    }
  }

  // ============== Kokoro Audio Library ==============

  /// List all generated TTS audio files (Kokoro).
  Future<List<Map<String, dynamic>>> getTtsAudioFiles() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/tts/audio/list'),
    );
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return List<Map<String, dynamic>>.from(data['audio_files']);
    }
    throw Exception('Failed to list TTS audio files: ${response.body}');
  }

  /// Delete a TTS audio file.
  Future<void> deleteTtsAudio(String filename) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/api/tts/audio/$filename'),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to delete audio file: ${response.body}');
    }
  }

  /// List all generated Kokoro TTS audio files.
  Future<List<Map<String, dynamic>>> getKokoroAudioFiles() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/kokoro/audio/list'),
    );
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return List<Map<String, dynamic>>.from(data['audio_files']);
    }
    throw Exception('Failed to list Kokoro audio files: ${response.body}');
  }

  /// Delete a Kokoro audio file.
  Future<void> deleteKokoroAudio(String filename) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/api/kokoro/audio/$filename'),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to delete audio file: ${response.body}');
    }
  }

  // ============== Voice Clone Audio Library ==============

  /// List all generated voice clone audio files (Qwen3).
  Future<List<Map<String, dynamic>>> getVoiceCloneAudioFiles() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/voice-clone/audio/list'),
    );
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return List<Map<String, dynamic>>.from(data['audio_files']);
    }
    throw Exception('Failed to list voice clone audio files: ${response.body}');
  }

  /// Delete a voice clone audio file.
  Future<void> deleteVoiceCloneAudio(String filename) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/api/voice-clone/audio/$filename'),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to delete audio file: ${response.body}');
    }
  }

  // ============== PDF Documents ==============

  /// List available PDF/TXT/MD documents from the backend.
  Future<List<Map<String, dynamic>>> listPdfDocuments() async {
    final response = await http.get(Uri.parse('$baseUrl/api/pdf/list'));
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return List<Map<String, dynamic>>.from(data['documents']);
    }
    throw Exception('Failed to list documents');
  }

  /// Get the full URL for a PDF document served by the backend.
  String getPdfUrl(String pdfPath) {
    return '$baseUrl$pdfPath';
  }

  /// Fetch PDF bytes from the backend by URL path.
  Future<Uint8List> fetchPdfBytes(String urlPath) async {
    final response = await http.get(Uri.parse('$baseUrl$urlPath'));
    if (response.statusCode == 200) {
      return response.bodyBytes;
    }
    throw Exception('Failed to fetch document');
  }

  // ============== MCP Server ==============

  /// Fetch available MCP tools from the MCP server via JSON-RPC.
  /// The MCP server runs on port 8010 by default.
  Future<List<Map<String, dynamic>>> getMcpTools({int mcpPort = 8010}) async {
    try {
      // First initialize the MCP session
      final initResponse = await http.post(
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
      final response = await http.post(
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
        final data = json.decode(response.body);
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
      final response = await http.post(
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
