# MimikaStudio Productization Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Transform MimikaStudio into a commercial macOS desktop app with $39.99 one-time purchase, 7-day trial, and professional UI.

**Architecture:** Flutter frontend with FastAPI backend, Polar.sh for license management, Sparkle for auto-updates, date-based versioning (2026.02.1).

**Tech Stack:** Flutter 3.x, FastAPI, SQLite, Polar.sh API, Sparkle framework, PyInstaller, create-dmg

---

## Phase 1: Foundation

### Task 1: Create Version Files

**Files:**
- Create: `backend/version.py`
- Create: `flutter_app/lib/version.dart`
- Modify: `backend/main.py:109-113` (import version)
- Modify: `flutter_app/pubspec.yaml:4` (update version format)

**Step 1: Create backend version file**

Create `backend/version.py`:
```python
"""MimikaStudio version information."""

VERSION = "2026.02.1"
BUILD_NUMBER = 1
VERSION_NAME = "Initial Release"

def get_version_string() -> str:
    """Return formatted version string."""
    return f"{VERSION} (build {BUILD_NUMBER})"
```

**Step 2: Create Flutter version file**

Create `flutter_app/lib/version.dart`:
```dart
/// MimikaStudio version information.
const String appVersion = "2026.02.1";
const int buildNumber = 1;
const String versionName = "Initial Release";

String get versionString => "$appVersion (build $buildNumber)";
```

**Step 3: Update backend to use version**

In `backend/main.py`, change line ~109-113:
```python
from version import VERSION, VERSION_NAME

app = FastAPI(
    title="MimikaStudio API",
    description="Local-first Voice Cloning with Qwen3-TTS and Kokoro",
    version=VERSION,
    lifespan=lifespan
)
```

**Step 4: Update pubspec.yaml version**

Change `flutter_app/pubspec.yaml` line 4:
```yaml
version: 2026.02.1+1
```

**Step 5: Commit**

```bash
git add backend/version.py flutter_app/lib/version.dart backend/main.py flutter_app/pubspec.yaml
git commit -m "feat: add centralized version management (2026.02.1)"
```

---

### Task 2: Add LICENSE File

**Files:**
- Create: `LICENSE`

**Step 1: Create GPL v3.0 LICENSE file**

Create `LICENSE` in project root with full GPL v3.0 text (standard header):
```
MimikaStudio - Local-first Voice Cloning
Copyright (C) 2026 BoltzmannEntropy

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

[... full GPL v3.0 text ...]
```

**Step 2: Commit**

```bash
git add LICENSE
git commit -m "docs: add GPL v3.0 license"
```

---

### Task 3: Add Settings Database Tables

**Files:**
- Modify: `backend/database.py:15-69` (add new tables)

**Step 1: Add settings and license tables to schema**

In `backend/database.py`, add after line 68 (before the closing `"""`):
```python
        CREATE TABLE IF NOT EXISTS app_settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );

        CREATE TABLE IF NOT EXISTS license_info (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            license_key TEXT,
            email TEXT,
            activated_at TIMESTAMP,
            last_validated TIMESTAMP,
            is_valid INTEGER DEFAULT 0
        );

        CREATE TABLE IF NOT EXISTS trial_info (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            started_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            expires_at TIMESTAMP
        );
```

**Step 2: Add default settings to seed_db**

In `backend/database.py`, add at end of `seed_db()` function before `conn.commit()`:
```python
    # Seed default settings
    default_settings = [
        ("output_folder", str(Path.home() / "MimikaStudio" / "outputs")),
        ("theme", "system"),
        ("auto_update", "true"),
        ("update_frequency", "weekly"),
    ]
    cursor.executemany(
        "INSERT OR IGNORE INTO app_settings (key, value) VALUES (?, ?)",
        default_settings
    )
```

**Step 3: Commit**

```bash
git add backend/database.py
git commit -m "feat: add settings and license database tables"
```

---

### Task 4: Create Settings Backend Endpoints

**Files:**
- Create: `backend/settings_service.py`
- Modify: `backend/main.py` (add endpoints)

**Step 1: Create settings service**

Create `backend/settings_service.py`:
```python
"""Settings management service."""
from pathlib import Path
from database import get_connection
from datetime import datetime

def get_setting(key: str) -> str | None:
    """Get a setting value by key."""
    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute("SELECT value FROM app_settings WHERE key = ?", (key,))
    row = cursor.fetchone()
    conn.close()
    return row[0] if row else None

def set_setting(key: str, value: str) -> bool:
    """Set a setting value."""
    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute(
        """INSERT INTO app_settings (key, value, updated_at)
           VALUES (?, ?, ?)
           ON CONFLICT(key) DO UPDATE SET value = ?, updated_at = ?""",
        (key, value, datetime.now(), value, datetime.now())
    )
    conn.commit()
    conn.close()
    return True

def get_all_settings() -> dict:
    """Get all settings as a dictionary."""
    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute("SELECT key, value FROM app_settings")
    rows = cursor.fetchall()
    conn.close()
    return {row[0]: row[1] for row in rows}

def get_output_folder() -> str:
    """Get the output folder path, creating it if needed."""
    folder = get_setting("output_folder")
    if folder:
        Path(folder).mkdir(parents=True, exist_ok=True)
        return folder
    default = str(Path.home() / "MimikaStudio" / "outputs")
    Path(default).mkdir(parents=True, exist_ok=True)
    return default

def set_output_folder(path: str) -> bool:
    """Set the output folder path."""
    folder = Path(path)
    if not folder.exists():
        folder.mkdir(parents=True, exist_ok=True)
    return set_setting("output_folder", path)
```

**Step 2: Add settings endpoints to main.py**

Add imports at top of `backend/main.py`:
```python
from settings_service import get_all_settings, get_setting, set_setting, get_output_folder, set_output_folder
```

Add endpoints (after existing endpoints):
```python
# ============== Settings ==============

class SettingsUpdateRequest(BaseModel):
    key: str
    value: str

@app.get("/api/settings")
async def api_get_settings():
    """Get all application settings."""
    return get_all_settings()

@app.get("/api/settings/{key}")
async def api_get_setting(key: str):
    """Get a specific setting."""
    value = get_setting(key)
    if value is None:
        raise HTTPException(status_code=404, detail=f"Setting '{key}' not found")
    return {"key": key, "value": value}

@app.put("/api/settings")
async def api_update_setting(request: SettingsUpdateRequest):
    """Update a setting."""
    set_setting(request.key, request.value)
    return {"key": request.key, "value": request.value}

@app.get("/api/settings/output-folder")
async def api_get_output_folder():
    """Get the output folder path."""
    return {"path": get_output_folder()}

@app.put("/api/settings/output-folder")
async def api_set_output_folder(path: str):
    """Set the output folder path."""
    success = set_output_folder(path)
    return {"success": success, "path": path}
```

**Step 3: Commit**

```bash
git add backend/settings_service.py backend/main.py
git commit -m "feat: add settings backend with output folder configuration"
```

---

## Phase 2: UI Restructure

### Task 5: Create Models Screen (Full Page)

**Files:**
- Create: `flutter_app/lib/screens/models_screen.dart`

**Step 1: Create full-page models screen**

Create `flutter_app/lib/screens/models_screen.dart`:
```dart
import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';

class ModelsScreen extends StatefulWidget {
  const ModelsScreen({super.key});

  @override
  State<ModelsScreen> createState() => _ModelsScreenState();
}

class _ModelsScreenState extends State<ModelsScreen> {
  final ApiService _api = ApiService();
  List<Map<String, dynamic>> _models = [];
  bool _isLoading = true;
  String? _error;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _loadModels();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _loadModels());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadModels() async {
    try {
      final models = await _api.getModelsStatus();
      if (mounted) {
        setState(() {
          _models = models;
          _isLoading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && _models.isEmpty) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _downloadModel(String modelName) async {
    try {
      await _api.downloadModel(modelName);
      setState(() {
        for (final model in _models) {
          if (model['name'] == modelName) {
            model['download_status'] = 'downloading';
          }
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start download: $e')),
        );
      }
    }
  }

  IconData _engineIcon(String engine) {
    switch (engine) {
      case 'kokoro': return Icons.volume_up;
      case 'qwen3': return Icons.record_voice_over;
      case 'chatterbox': return Icons.mic;
      case 'indextts2': return Icons.auto_awesome;
      default: return Icons.model_training;
    }
  }

  Color _engineColor(String engine) {
    switch (engine) {
      case 'kokoro': return Colors.blue;
      case 'qwen3': return Colors.teal;
      case 'chatterbox': return Colors.orange;
      case 'indextts2': return Colors.deepPurple;
      default: return Colors.grey;
    }
  }

  Widget _buildModelCard(Map<String, dynamic> model) {
    final name = model['name'] as String;
    final engine = model['engine'] as String;
    final sizeGb = model['size_gb'] as num?;
    final downloaded = model['downloaded'] as bool? ?? false;
    final modelType = model['model_type'] as String? ?? 'huggingface';
    final description = model['description'] as String? ?? '';
    final downloadStatus = model['download_status'] as String?;
    final downloadError = model['download_error'] as String?;

    final isDownloading = downloadStatus == 'downloading';
    final downloadFailed = downloadStatus == 'failed';
    final color = _engineColor(engine);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(_engineIcon(engine), color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                        ),
                      ),
                      if (sizeGb != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${sizeGb}GB',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                          ),
                        ),
                    ],
                  ),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                    ),
                  ],
                  if (downloadFailed && downloadError != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Error: $downloadError',
                      style: const TextStyle(fontSize: 12, color: Colors.red),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 16),
            _buildStatusWidget(downloaded, isDownloading, downloadFailed, modelType, name),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusWidget(
    bool downloaded,
    bool isDownloading,
    bool downloadFailed,
    String modelType,
    String name,
  ) {
    if (downloaded) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.green.withValues(alpha: 0.5)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, size: 16, color: Colors.green),
            SizedBox(width: 6),
            Text('Ready', style: TextStyle(fontSize: 13, color: Colors.green, fontWeight: FontWeight.w600)),
          ],
        ),
      );
    }

    if (isDownloading) {
      return const SizedBox(
        width: 100,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 8),
            Text('Downloading...', style: TextStyle(fontSize: 12)),
          ],
        ),
      );
    }

    if (modelType == 'pip') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.warning_amber, size: 16, color: Colors.orange),
            SizedBox(width: 6),
            Text('pip install', style: TextStyle(fontSize: 13, color: Colors.orange, fontWeight: FontWeight.w600)),
          ],
        ),
      );
    }

    return FilledButton.icon(
      onPressed: () => _downloadModel(name),
      icon: Icon(downloadFailed ? Icons.refresh : Icons.download, size: 18),
      label: Text(downloadFailed ? 'Retry' : 'Download'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final engineOrder = ['kokoro', 'qwen3', 'chatterbox', 'indextts2'];
    final engineLabels = {
      'kokoro': 'Kokoro TTS',
      'qwen3': 'Qwen3-TTS',
      'chatterbox': 'Chatterbox',
      'indextts2': 'IndexTTS-2',
    };

    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final model in _models) {
      final engine = model['engine'] as String;
      grouped.putIfAbsent(engine, () => []).add(model);
    }

    final downloadedCount = _models.where((m) => m['downloaded'] == true).length;
    final totalCount = _models.length;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                setState(() => _isLoading = true);
                _loadModels();
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.model_training, size: 28),
              const SizedBox(width: 12),
              const Text(
                'AI Models',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: downloadedCount == totalCount
                      ? Colors.green.withValues(alpha: 0.15)
                      : Colors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$downloadedCount/$totalCount ready',
                  style: TextStyle(
                    fontSize: 14,
                    color: downloadedCount == totalCount ? Colors.green : Colors.orange,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () {
                  setState(() => _isLoading = true);
                  _loadModels();
                },
                tooltip: 'Refresh',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Download and manage AI models for voice synthesis',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: ListView(
              children: [
                for (final engine in engineOrder)
                  if (grouped.containsKey(engine)) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 16, bottom: 8),
                      child: Row(
                        children: [
                          Icon(_engineIcon(engine), size: 20, color: _engineColor(engine)),
                          const SizedBox(width: 8),
                          Text(
                            engineLabels[engine] ?? engine,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: _engineColor(engine),
                            ),
                          ),
                        ],
                      ),
                    ),
                    ...grouped[engine]!.map(_buildModelCard),
                  ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
```

**Step 2: Commit**

```bash
git add flutter_app/lib/screens/models_screen.dart
git commit -m "feat: add full-page Models screen"
```

---

### Task 6: Create Settings Screen

**Files:**
- Create: `flutter_app/lib/screens/settings_screen.dart`
- Create: `flutter_app/lib/services/settings_service.dart`

**Step 1: Create settings service**

Create `flutter_app/lib/services/settings_service.dart`:
```dart
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
```

**Step 2: Create settings screen**

Create `flutter_app/lib/screens/settings_screen.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/settings_service.dart';
import '../version.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final SettingsService _settings = SettingsService();
  bool _isLoading = true;
  String _outputFolder = '';
  String _theme = 'system';
  bool _autoUpdate = true;
  String _updateFrequency = 'weekly';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final settings = await _settings.getAllSettings();
      setState(() {
        _outputFolder = settings['output_folder'] ?? '';
        _theme = settings['theme'] ?? 'system';
        _autoUpdate = settings['auto_update'] == 'true';
        _updateFrequency = settings['update_frequency'] ?? 'weekly';
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _pickOutputFolder() async {
    final result = await FilePicker.platform.getDirectoryPath();
    if (result != null) {
      await _settings.setOutputFolder(result);
      setState(() => _outputFolder = result);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Output folder updated')),
        );
      }
    }
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.settings, size: 28),
              const SizedBox(width: 12),
              const Text(
                'Settings',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Text(
                'v$appVersion',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: ListView(
              children: [
                _buildSection('General', [
                  ListTile(
                    leading: const Icon(Icons.folder_outlined),
                    title: const Text('Output Folder'),
                    subtitle: Text(
                      _outputFolder.isEmpty ? 'Not set' : _outputFolder,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: FilledButton.tonal(
                      onPressed: _pickOutputFolder,
                      child: const Text('Change'),
                    ),
                  ),
                ]),
                _buildSection('Appearance', [
                  ListTile(
                    leading: const Icon(Icons.palette_outlined),
                    title: const Text('Theme'),
                    trailing: SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'light', label: Text('Light')),
                        ButtonSegment(value: 'dark', label: Text('Dark')),
                        ButtonSegment(value: 'system', label: Text('System')),
                      ],
                      selected: {_theme},
                      onSelectionChanged: (value) async {
                        final newTheme = value.first;
                        await _settings.setSetting('theme', newTheme);
                        setState(() => _theme = newTheme);
                      },
                    ),
                  ),
                ]),
                _buildSection('Updates', [
                  SwitchListTile(
                    secondary: const Icon(Icons.update_outlined),
                    title: const Text('Auto-update'),
                    subtitle: const Text('Automatically check for updates'),
                    value: _autoUpdate,
                    onChanged: (value) async {
                      await _settings.setSetting('auto_update', value.toString());
                      setState(() => _autoUpdate = value);
                    },
                  ),
                  if (_autoUpdate)
                    ListTile(
                      leading: const Icon(Icons.schedule_outlined),
                      title: const Text('Check Frequency'),
                      trailing: DropdownButton<String>(
                        value: _updateFrequency,
                        items: const [
                          DropdownMenuItem(value: 'daily', child: Text('Daily')),
                          DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
                          DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
                        ],
                        onChanged: (value) async {
                          if (value != null) {
                            await _settings.setSetting('update_frequency', value);
                            setState(() => _updateFrequency = value);
                          }
                        },
                      ),
                    ),
                  ListTile(
                    leading: const Icon(Icons.refresh),
                    title: const Text('Check for Updates'),
                    subtitle: const Text('Manually check for new versions'),
                    trailing: FilledButton.tonal(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('You are running the latest version')),
                        );
                      },
                      child: const Text('Check Now'),
                    ),
                  ),
                ]),
                _buildSection('License', [
                  ListTile(
                    leading: const Icon(Icons.key_outlined),
                    title: const Text('License Status'),
                    subtitle: const Text('Trial - 7 days remaining'),
                    trailing: FilledButton(
                      onPressed: () {
                        // TODO: Open license dialog
                      },
                      child: const Text('Activate'),
                    ),
                  ),
                ]),
                _buildSection('Advanced', [
                  ListTile(
                    leading: const Icon(Icons.cleaning_services_outlined),
                    title: const Text('Clear Cache'),
                    subtitle: const Text('Remove temporary files'),
                    trailing: FilledButton.tonal(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Cache cleared')),
                        );
                      },
                      child: const Text('Clear'),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.restore_outlined),
                    title: const Text('Reset Settings'),
                    subtitle: const Text('Restore default settings'),
                    trailing: FilledButton.tonal(
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Reset Settings?'),
                            content: const Text('This will restore all settings to their defaults.'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Cancel'),
                              ),
                              FilledButton(
                                onPressed: () {
                                  Navigator.pop(context);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Settings reset to defaults')),
                                  );
                                },
                                child: const Text('Reset'),
                              ),
                            ],
                          ),
                        );
                      },
                      child: const Text('Reset'),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
```

**Step 3: Commit**

```bash
git add flutter_app/lib/services/settings_service.dart flutter_app/lib/screens/settings_screen.dart
git commit -m "feat: add Settings screen with output folder configuration"
```

---

### Task 7: Create About Screen

**Files:**
- Create: `flutter_app/lib/screens/about_screen.dart`

**Step 1: Create about screen**

Create `flutter_app/lib/screens/about_screen.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../version.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Icon(
                  Icons.graphic_eq,
                  size: 64,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 24),

              // App name and version
              const Text(
                'MimikaStudio',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Version $appVersion',
                style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 4),
              Text(
                versionName,
                style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
              ),
              const SizedBox(height: 32),

              // Description
              Text(
                'Local-first Voice Cloning & Text-to-Speech',
                style: TextStyle(fontSize: 16, color: Colors.grey.shade700),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),

              // Links
              Wrap(
                spacing: 16,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: () => _launchUrl('https://boltzmannentropy.github.io/mimikastudio.github.io/'),
                    icon: const Icon(Icons.language),
                    label: const Text('Website'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () => _launchUrl('https://github.com/BoltzmannEntropy/MimikaStudio'),
                    icon: const Icon(Icons.code),
                    label: const Text('GitHub'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () => _launchUrl('https://github.com/BoltzmannEntropy/MimikaStudio/issues'),
                    icon: const Icon(Icons.bug_report),
                    label: const Text('Report Issue'),
                  ),
                ],
              ),
              const SizedBox(height: 48),

              // Credits section
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Powered By',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _buildCreditChip('Kokoro TTS', Colors.blue),
                          _buildCreditChip('Qwen3-TTS', Colors.teal),
                          _buildCreditChip('Chatterbox', Colors.orange),
                          _buildCreditChip('IndexTTS-2', Colors.deepPurple),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // License
              Text(
                'Licensed under GPL v3.0',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
              const SizedBox(height: 4),
              Text(
                '\u00a9 2026 BoltzmannEntropy',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCreditChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w500),
      ),
    );
  }
}
```

**Step 2: Commit**

```bash
git add flutter_app/lib/screens/about_screen.dart
git commit -m "feat: add About screen with credits and links"
```

---

### Task 8: Update Main Navigation (8 Tabs)

**Files:**
- Modify: `flutter_app/lib/main.dart`

**Step 1: Add imports**

In `flutter_app/lib/main.dart`, add after line 7:
```dart
import 'screens/models_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/about_screen.dart';
import 'version.dart';
```

**Step 2: Update tab count**

Change line 207 from `length: 6` to:
```dart
      length: 8,
```

**Step 3: Remove model manager button from app bar**

Delete lines 214-220 (the IconButton for models):
```dart
            IconButton(
              icon: const Icon(Icons.model_training, size: 22),
              onPressed: () => showDialog(
                context: context,
                builder: (context) => const ModelsDialog(),
              ),
              tooltip: 'Models',
            ),
```

**Step 4: Add version to app bar**

Replace the MimikaStudio text section (lines 221-238) with:
```dart
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.graphic_eq, size: 18, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 6),
                  Text(
                    'MimikaStudio',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.primary,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'v$appVersion',
                      style: TextStyle(
                        fontSize: 10,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
```

**Step 5: Add new tabs**

Update the tabs list (after IndexTTS-2 and PDF Reader tabs):
```dart
            tabs: [
              Tab(icon: Icon(Icons.volume_up, size: 28), text: 'TTS (Kokoro)'),
              Tab(icon: Icon(Icons.record_voice_over, size: 28), text: 'Qwen3 Clone'),
              Tab(icon: Icon(Icons.mic, size: 28), text: 'Chatterbox'),
              Tab(icon: Icon(Icons.auto_awesome, size: 28), text: 'IndexTTS-2'),
              Tab(icon: Icon(Icons.menu_book, size: 28), text: 'PDF Reader'),
              Tab(icon: Icon(Icons.model_training, size: 28), text: 'Models'),
              Tab(icon: Icon(Icons.settings, size: 28), text: 'Settings'),
              Tab(icon: Icon(Icons.info_outline, size: 28), text: 'About'),
            ],
```

**Step 6: Add new screen views**

Update TabBarView children:
```dart
        body: const TabBarView(
          children: [
            QuickTtsScreen(),
            Qwen3CloneScreen(),
            ChatterboxCloneScreen(),
            IndexTTS2Screen(),
            PdfReaderScreen(),
            ModelsScreen(),
            SettingsScreen(),
            AboutScreen(),
          ],
        ),
```

**Step 7: Remove unused import**

Remove or comment out the models_dialog import if no longer used:
```dart
// import 'screens/models_dialog.dart';  // Replaced by ModelsScreen
```

**Step 8: Commit**

```bash
git add flutter_app/lib/main.dart
git commit -m "feat: update navigation to 8 tabs with Models, Settings, About"
```

---

## Phase 3: Build System

### Task 9: Create DMG Build Script

**Files:**
- Create: `scripts/build_dmg.sh`

**Step 1: Create build script**

Create `scripts/build_dmg.sh`:
```bash
#!/bin/bash
set -e

# MimikaStudio DMG Builder
# Usage: ./scripts/build_dmg.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "=== MimikaStudio DMG Builder ==="

# 1. Read version from version.py
VERSION=$(python3 -c "exec(open('$PROJECT_DIR/backend/version.py').read()); print(VERSION)")
BUILD_NUMBER=$(python3 -c "exec(open('$PROJECT_DIR/backend/version.py').read()); print(BUILD_NUMBER)")

echo "Building version: $VERSION (build $BUILD_NUMBER)"

# 2. Build directories
BUILD_DIR="$PROJECT_DIR/build"
DIST_DIR="$PROJECT_DIR/dist"
APP_NAME="MimikaStudio"

mkdir -p "$BUILD_DIR" "$DIST_DIR"

# 3. Build Flutter app (release mode)
echo "Building Flutter app..."
cd "$PROJECT_DIR/flutter_app"
flutter build macos --release

FLUTTER_APP="$PROJECT_DIR/flutter_app/build/macos/Build/Products/Release/mimika_studio.app"

if [ ! -d "$FLUTTER_APP" ]; then
    echo "Error: Flutter build failed - app not found at $FLUTTER_APP"
    exit 1
fi

# 4. Copy app to build directory
echo "Preparing app bundle..."
cp -R "$FLUTTER_APP" "$BUILD_DIR/$APP_NAME.app"

# 5. Create DMG
echo "Creating DMG..."
DMG_NAME="$APP_NAME-$VERSION.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"

# Remove old DMG if exists
rm -f "$DMG_PATH"

# Create DMG using hdiutil (basic method)
# For prettier DMGs, install create-dmg: brew install create-dmg
if command -v create-dmg &> /dev/null; then
    create-dmg \
        --volname "$APP_NAME" \
        --volicon "$PROJECT_DIR/assets/app-icon.icns" \
        --window-pos 200 120 \
        --window-size 600 400 \
        --icon-size 100 \
        --icon "$APP_NAME.app" 150 185 \
        --app-drop-link 450 185 \
        --hide-extension "$APP_NAME.app" \
        "$DMG_PATH" \
        "$BUILD_DIR/$APP_NAME.app" || {
            # Fallback to hdiutil if create-dmg fails
            echo "create-dmg failed, using hdiutil..."
            hdiutil create -volname "$APP_NAME" -srcfolder "$BUILD_DIR/$APP_NAME.app" -ov -format UDZO "$DMG_PATH"
        }
else
    echo "create-dmg not found, using hdiutil..."
    hdiutil create -volname "$APP_NAME" -srcfolder "$BUILD_DIR/$APP_NAME.app" -ov -format UDZO "$DMG_PATH"
fi

# 6. Generate SHA256 hash
echo "Generating SHA256 hash..."
cd "$DIST_DIR"
shasum -a 256 "$DMG_NAME" > "$DMG_NAME.sha256"
SHA256=$(cat "$DMG_NAME.sha256" | cut -d' ' -f1)

echo ""
echo "=== Build Complete ==="
echo "DMG: $DMG_PATH"
echo "SHA256: $SHA256"
echo ""
echo "To code sign (requires Developer ID):"
echo "  codesign --deep --force --verify --verbose --sign 'Developer ID Application: YOUR_NAME' '$BUILD_DIR/$APP_NAME.app'"
echo ""
echo "To notarize (requires Apple Developer account):"
echo "  xcrun notarytool submit '$DMG_PATH' --apple-id YOUR_APPLE_ID --password YOUR_APP_PASSWORD --team-id YOUR_TEAM_ID --wait"
```

**Step 2: Make executable**

```bash
chmod +x scripts/build_dmg.sh
```

**Step 3: Commit**

```bash
git add scripts/build_dmg.sh
git commit -m "feat: add DMG build script with SHA256 hash generation"
```

---

### Task 10: Create Version Bump Script

**Files:**
- Create: `scripts/bump_version.py`

**Step 1: Create version bump script**

Create `scripts/bump_version.py`:
```python
#!/usr/bin/env python3
"""Bump version across all MimikaStudio components."""

import re
import sys
from pathlib import Path
from datetime import datetime

PROJECT_ROOT = Path(__file__).parent.parent

def read_current_version():
    """Read current version from backend/version.py."""
    version_file = PROJECT_ROOT / "backend" / "version.py"
    content = version_file.read_text()
    match = re.search(r'VERSION = "(.+)"', content)
    if match:
        return match.group(1)
    raise ValueError("Could not find VERSION in version.py")

def bump_version(new_version: str, version_name: str = None):
    """Update version in all files."""

    # 1. Update backend/version.py
    backend_version = PROJECT_ROOT / "backend" / "version.py"
    content = backend_version.read_text()

    # Get current build number and increment
    build_match = re.search(r'BUILD_NUMBER = (\d+)', content)
    build_number = int(build_match.group(1)) + 1 if build_match else 1

    new_content = re.sub(r'VERSION = ".+"', f'VERSION = "{new_version}"', content)
    new_content = re.sub(r'BUILD_NUMBER = \d+', f'BUILD_NUMBER = {build_number}', new_content)
    if version_name:
        new_content = re.sub(r'VERSION_NAME = ".+"', f'VERSION_NAME = "{version_name}"', new_content)

    backend_version.write_text(new_content)
    print(f"Updated backend/version.py")

    # 2. Update flutter_app/lib/version.dart
    flutter_version = PROJECT_ROOT / "flutter_app" / "lib" / "version.dart"
    content = flutter_version.read_text()

    new_content = re.sub(r'const String appVersion = ".+";', f'const String appVersion = "{new_version}";', content)
    new_content = re.sub(r'const int buildNumber = \d+;', f'const int buildNumber = {build_number};', new_content)
    if version_name:
        new_content = re.sub(r'const String versionName = ".+";', f'const String versionName = "{version_name}";', new_content)

    flutter_version.write_text(new_content)
    print(f"Updated flutter_app/lib/version.dart")

    # 3. Update flutter_app/pubspec.yaml
    pubspec = PROJECT_ROOT / "flutter_app" / "pubspec.yaml"
    content = pubspec.read_text()

    new_content = re.sub(r'version: .+', f'version: {new_version}+{build_number}', content)

    pubspec.write_text(new_content)
    print(f"Updated flutter_app/pubspec.yaml")

    print(f"\nVersion bumped to {new_version} (build {build_number})")
    return new_version, build_number

def main():
    if len(sys.argv) < 2:
        current = read_current_version()
        print(f"Current version: {current}")
        print(f"\nUsage: {sys.argv[0]} <new_version> [version_name]")
        print(f"Example: {sys.argv[0]} 2026.02.2 'Bug fixes'")
        print(f"\nFor date-based versioning, use: YYYY.MM.N format")
        today = datetime.now()
        print(f"Suggested next version: {today.year}.{today.month:02d}.N")
        return

    new_version = sys.argv[1]
    version_name = sys.argv[2] if len(sys.argv) > 2 else None

    bump_version(new_version, version_name)

if __name__ == "__main__":
    main()
```

**Step 2: Make executable**

```bash
chmod +x scripts/bump_version.py
```

**Step 3: Commit**

```bash
git add scripts/bump_version.py
git commit -m "feat: add version bump script for synchronized versioning"
```

---

## Phase 4: Website Updates

### Task 11: Add Pricing Section to Website

**Files:**
- Modify: `/Volumes/SSD4tb/Dropbox/DSS/artifacts/all-web/Mimika/index.html`

**Step 1: Add pricing section HTML**

Add after the features/showcase sections (before FAQ or footer):

```html
<!-- Pricing Section -->
<section id="pricing" class="py-20">
  <div class="container mx-auto px-6">
    <div class="text-center mb-16">
      <h2 class="text-4xl font-bold text-gray-900 dark:text-white mb-4">Simple Pricing</h2>
      <p class="text-xl text-gray-600 dark:text-gray-300">Start with a free trial, upgrade when you're ready</p>
    </div>

    <div class="grid md:grid-cols-2 gap-8 max-w-4xl mx-auto">
      <!-- Free Trial -->
      <div class="bg-white dark:bg-gray-800 rounded-2xl shadow-lg p-8 border border-gray-200 dark:border-gray-700">
        <div class="text-center">
          <h3 class="text-2xl font-bold text-gray-900 dark:text-white mb-2">Free Trial</h3>
          <p class="text-gray-600 dark:text-gray-400 mb-6">7 Days Full Access</p>
          <div class="text-4xl font-bold text-gray-900 dark:text-white mb-8">$0</div>
        </div>

        <ul class="space-y-4 mb-8">
          <li class="flex items-center text-gray-700 dark:text-gray-300">
            <svg class="w-5 h-5 text-green-500 mr-3" fill="currentColor" viewBox="0 0 20 20">
              <path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd"/>
            </svg>
            All TTS Engines
          </li>
          <li class="flex items-center text-gray-700 dark:text-gray-300">
            <svg class="w-5 h-5 text-green-500 mr-3" fill="currentColor" viewBox="0 0 20 20">
              <path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd"/>
            </svg>
            Voice Cloning
          </li>
          <li class="flex items-center text-gray-700 dark:text-gray-300">
            <svg class="w-5 h-5 text-green-500 mr-3" fill="currentColor" viewBox="0 0 20 20">
              <path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd"/>
            </svg>
            PDF Audiobook Creator
          </li>
          <li class="flex items-center text-gray-700 dark:text-gray-300">
            <svg class="w-5 h-5 text-green-500 mr-3" fill="currentColor" viewBox="0 0 20 20">
              <path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd"/>
            </svg>
            All Languages
          </li>
        </ul>

        <a href="#download" class="block w-full py-3 px-6 text-center bg-gray-100 dark:bg-gray-700 text-gray-900 dark:text-white font-semibold rounded-xl hover:bg-gray-200 dark:hover:bg-gray-600 transition-colors">
          Start Free Trial
        </a>
      </div>

      <!-- Pro License -->
      <div class="bg-indigo-600 rounded-2xl shadow-lg p-8 relative overflow-hidden">
        <div class="absolute top-4 right-4 bg-yellow-400 text-yellow-900 text-xs font-bold px-3 py-1 rounded-full">
          BEST VALUE
        </div>

        <div class="text-center">
          <h3 class="text-2xl font-bold text-white mb-2">Pro License</h3>
          <p class="text-indigo-200 mb-6">One-time purchase</p>
          <div class="text-4xl font-bold text-white mb-2">$39.99</div>
          <p class="text-indigo-200 text-sm mb-8">Lifetime access</p>
        </div>

        <ul class="space-y-4 mb-8">
          <li class="flex items-center text-white">
            <svg class="w-5 h-5 text-indigo-200 mr-3" fill="currentColor" viewBox="0 0 20 20">
              <path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd"/>
            </svg>
            Everything in Trial
          </li>
          <li class="flex items-center text-white">
            <svg class="w-5 h-5 text-indigo-200 mr-3" fill="currentColor" viewBox="0 0 20 20">
              <path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd"/>
            </svg>
            Lifetime Updates
          </li>
          <li class="flex items-center text-white">
            <svg class="w-5 h-5 text-indigo-200 mr-3" fill="currentColor" viewBox="0 0 20 20">
              <path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd"/>
            </svg>
            Priority Support
          </li>
          <li class="flex items-center text-white">
            <svg class="w-5 h-5 text-indigo-200 mr-3" fill="currentColor" viewBox="0 0 20 20">
              <path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd"/>
            </svg>
            Auto-updates via Sparkle
          </li>
          <li class="flex items-center text-white">
            <svg class="w-5 h-5 text-indigo-200 mr-3" fill="currentColor" viewBox="0 0 20 20">
              <path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd"/>
            </svg>
            Commercial Use
          </li>
        </ul>

        <a href="https://polar.sh/BoltzmannEntropy/products/mimikastudio" target="_blank" class="block w-full py-3 px-6 text-center bg-white text-indigo-600 font-semibold rounded-xl hover:bg-indigo-50 transition-colors">
          Buy Now
        </a>
      </div>
    </div>

    <p class="text-center text-gray-500 dark:text-gray-400 mt-8 text-sm">
      Secure payment via Polar.sh. Instant license key delivery.
    </p>
  </div>
</section>
```

**Step 2: Add Pricing link to navigation**

Update the navigation to include a Pricing link.

**Step 3: Commit website changes**

```bash
cd /Volumes/SSD4tb/Dropbox/DSS/artifacts/all-web/Mimika
git add index.html
git commit -m "feat: add pricing section with trial and pro license"
```

---

## Phase 5: Update Skill

### Task 12: Update Flutter-Python-Fullstack Skill

**Files:**
- Locate and update the flutter-python-fullstack skill file

**Step 1: Find the skill file**

```bash
find ~/.claude -name "*flutter*" -type f 2>/dev/null
```

**Step 2: Add productization patterns to the skill**

Add sections covering:
- Version management (centralized version files)
- License integration (Polar.sh)
- Settings architecture (SQLite + API + Flutter service)
- DMG build pipeline
- About/Settings/Models screens patterns

---

## Summary

**Total Tasks:** 12

**Phase 1 - Foundation (Tasks 1-4):**
- Version files
- LICENSE
- Database tables
- Settings endpoints

**Phase 2 - UI (Tasks 5-8):**
- Models screen
- Settings screen
- About screen
- Main navigation update

**Phase 3 - Build (Tasks 9-10):**
- DMG build script
- Version bump script

**Phase 4 - Website (Task 11):**
- Pricing section

**Phase 5 - Skill (Task 12):**
- Update flutter-python-fullstack skill

---

**Execution Notes:**
- Run Flutter app after Task 8 to verify UI changes
- Test settings persistence after Task 6
- Test DMG build on macOS after Task 9
- Polar.sh product setup required before live purchase flow
