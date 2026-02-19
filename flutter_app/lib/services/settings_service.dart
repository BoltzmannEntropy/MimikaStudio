import 'dart:convert';
import 'package:http/http.dart' as http;

class SettingsService {
  static const String baseUrl = 'http://localhost:7693';
  static const Duration _requestTimeout = Duration(seconds: 30);

  Future<http.Response> _get(Uri uri) {
    return http.get(uri).timeout(_requestTimeout);
  }

  Future<http.Response> _put(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
  }) {
    return http.put(uri, headers: headers, body: body).timeout(_requestTimeout);
  }

  dynamic _decodeJson(String body) {
    try {
      return json.decode(body);
    } catch (e) {
      throw Exception('Backend returned invalid JSON for settings');
    }
  }

  Exception _settingsError(String action, http.Response response) {
    final fallback = response.body.trim().isEmpty
        ? 'HTTP ${response.statusCode}'
        : response.body.trim();
    return Exception('$action failed (${response.statusCode}): $fallback');
  }

  Future<Map<String, String>> getAllSettings() async {
    final response = await _get(Uri.parse('$baseUrl/api/settings'));
    if (response.statusCode == 200) {
      final data = _decodeJson(response.body) as Map<String, dynamic>;
      return data.map((k, v) => MapEntry(k, v.toString()));
    }
    throw _settingsError('Failed to load settings', response);
  }

  Future<String?> getSetting(String key) async {
    try {
      final response = await _get(Uri.parse('$baseUrl/api/settings/$key'));
      if (response.statusCode == 200) {
        final data = _decodeJson(response.body);
        return data['value'] as String?;
      }
    } catch (e) {
      // Setting not found
    }
    return null;
  }

  Future<void> setSetting(String key, String value) async {
    final response = await _put(
      Uri.parse('$baseUrl/api/settings'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'key': key, 'value': value}),
    );
    if (response.statusCode != 200) {
      throw _settingsError('Failed to update setting', response);
    }
  }

  Future<String> getOutputFolder() async {
    final response = await _get(
      Uri.parse('$baseUrl/api/settings/output-folder'),
    );
    if (response.statusCode == 200) {
      final data = _decodeJson(response.body);
      return data['path'] as String;
    }
    throw _settingsError('Failed to get output folder', response);
  }

  Future<void> setOutputFolder(String path) async {
    final response = await _put(
      Uri.parse(
        '$baseUrl/api/settings/output-folder?path=${Uri.encodeComponent(path)}',
      ),
    );
    if (response.statusCode != 200) {
      throw _settingsError('Failed to set output folder', response);
    }
  }
}
