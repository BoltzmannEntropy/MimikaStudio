import 'dart:convert';
import 'package:http/http.dart' as http;

class SettingsService {
  static const String baseUrl = 'http://localhost:8000';

  Future<Map<String, String>> getAllSettings() async {
    final response = await http.get(Uri.parse('$baseUrl/api/settings'));
    if (response.statusCode == 200) {
      final data = json.decode(response.body) as Map<String, dynamic>;
      return data.map((k, v) => MapEntry(k, v.toString()));
    }
    throw Exception('Failed to load settings');
  }

  Future<String?> getSetting(String key) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/settings/$key'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['value'] as String?;
      }
    } catch (e) {
      // Setting not found
    }
    return null;
  }

  Future<void> setSetting(String key, String value) async {
    final response = await http.put(
      Uri.parse('$baseUrl/api/settings'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'key': key, 'value': value}),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to update setting');
    }
  }

  Future<String> getOutputFolder() async {
    final response = await http.get(Uri.parse('$baseUrl/api/settings/output-folder'));
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return data['path'] as String;
    }
    throw Exception('Failed to get output folder');
  }

  Future<void> setOutputFolder(String path) async {
    final response = await http.put(
      Uri.parse('$baseUrl/api/settings/output-folder?path=${Uri.encodeComponent(path)}'),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to set output folder');
    }
  }
}
