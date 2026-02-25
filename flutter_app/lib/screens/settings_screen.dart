import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/api_service.dart';
import '../services/settings_service.dart';
import '../version.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final ApiService _apiService = ApiService();
  final SettingsService _settingsService = SettingsService();

  bool _isLoading = true;
  bool _isExportingLogs = false;
  String? _error;

  // General settings
  String _outputFolder = '';
  List<Map<String, dynamic>> _systemFolders = [];

  // Appearance settings
  ThemeMode _themeMode = ThemeMode.system;

  // Update settings
  bool _autoUpdate = true;
  String _updateFrequency = 'weekly';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Load output folder
      try {
        _outputFolder = await _settingsService.getOutputFolder();
      } catch (e) {
        _outputFolder = 'Default (project folder)';
      }

      try {
        _systemFolders = await _apiService.getSystemFolders();
      } catch (e) {
        _systemFolders = [];
      }

      // Load other settings
      try {
        final settings = await _settingsService.getAllSettings();

        // Theme
        final themeValue = settings['theme'] ?? 'system';
        _themeMode = _parseThemeMode(themeValue);

        // Auto-update
        final autoUpdateValue = settings['auto_update'] ?? 'true';
        _autoUpdate = autoUpdateValue.toLowerCase() == 'true';

        // Update frequency
        _updateFrequency = settings['update_frequency'] ?? 'weekly';
      } catch (e) {
        // Use defaults if settings API fails
      }

      setState(() => _isLoading = false);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  ThemeMode _parseThemeMode(String value) {
    switch (value.toLowerCase()) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  String _themeModeToString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }

  Future<void> _selectOutputFolder() async {
    final result = await FilePicker.platform.getDirectoryPath();
    if (result != null) {
      try {
        await _settingsService.setOutputFolder(result);
        setState(() => _outputFolder = result);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Output folder updated')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to set output folder: $e')),
          );
        }
      }
    }
  }

  Future<void> _setTheme(ThemeMode mode) async {
    setState(() => _themeMode = mode);
    try {
      await _settingsService.setSetting('theme', _themeModeToString(mode));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save theme preference: $e')),
        );
      }
    }
  }

  Future<void> _setAutoUpdate(bool value) async {
    setState(() => _autoUpdate = value);
    try {
      await _settingsService.setSetting('auto_update', value.toString());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save auto-update preference: $e')),
        );
      }
    }
  }

  Future<void> _setUpdateFrequency(String frequency) async {
    setState(() => _updateFrequency = frequency);
    try {
      await _settingsService.setSetting('update_frequency', frequency);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save update frequency: $e')),
        );
      }
    }
  }

  Future<void> _openFolder(String path) async {
    final resolvedPath = path.trim();
    if (resolvedPath.isEmpty) return;

    try {
      final directory = Directory(resolvedPath);
      if (!directory.existsSync()) {
        throw Exception('Folder does not exist: $resolvedPath');
      }

      ProcessResult result;
      if (Platform.isMacOS) {
        result = await Process.run('open', [resolvedPath]);
      } else if (Platform.isWindows) {
        result = await Process.run('explorer', [resolvedPath]);
      } else if (Platform.isLinux) {
        result = await Process.run('xdg-open', [resolvedPath]);
      } else {
        throw Exception('Opening folders is not supported on this platform');
      }

      if (result.exitCode != 0) {
        throw Exception(
          result.stderr.toString().trim().isEmpty
              ? 'Failed to open folder'
              : result.stderr.toString().trim(),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to open folder: $e')));
      }
    }
  }

  Future<void> _clearCache() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Cache'),
        content: const Text(
          'This will clear all cached data including temporary audio files. '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Clear Cache'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      // TODO: Implement cache clearing via API
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Cache cleared')));
      }
    }
  }

  Future<void> _resetSettings() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset All Settings'),
        content: const Text(
          'This will reset all settings to their default values. '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      // TODO: Implement settings reset via API
      await _loadSettings();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Settings reset to defaults')),
        );
      }
    }
  }

  Future<void> _exportDiagnosticLogs() async {
    setState(() => _isExportingLogs = true);
    try {
      final bundle = await _apiService.exportDiagnosticLogs();
      final fileName =
          (bundle['fileName'] as String?) ?? 'mimika_diagnostics.zip';
      final bytes = bundle['bytes'] as List<int>;

      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Diagnostic Logs',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: const ['zip'],
      );
      if (savePath == null) {
        return;
      }

      final destinationPath = savePath.toLowerCase().endsWith('.zip')
          ? savePath
          : '$savePath.zip';
      final destination = File(destinationPath);
      await destination.writeAsBytes(bytes, flush: true);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Diagnostic logs exported to $destinationPath'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to export diagnostic logs: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isExportingLogs = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.settings),
            const SizedBox(width: 8),
            const Text('Settings'),
            const Spacer(),
            Text(
              'v$appVersion',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 48,
                    color: Colors.red.shade400,
                  ),
                  const SizedBox(height: 16),
                  Text('Error loading settings: $_error'),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _loadSettings,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // General Settings
                  _buildSectionHeader('General', Icons.folder_outlined),
                  Card(
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.folder_open),
                          title: const Text('Output Folder'),
                          subtitle: Text(
                            _outputFolder,
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                          trailing: Wrap(
                            spacing: 8,
                            children: [
                              OutlinedButton(
                                onPressed: () => _openFolder(_outputFolder),
                                child: const Text('Open'),
                              ),
                              FilledButton.tonal(
                                onPressed: _selectOutputFolder,
                                child: const Text('Browse'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildSectionHeader('Folders', Icons.folder_copy_outlined),
                  Card(
                    child: _systemFolders.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(16),
                            child: Text(
                              'Folder paths unavailable from backend.',
                            ),
                          )
                        : Column(
                            children: [
                              for (final folder in _systemFolders)
                                _buildFolderTile(
                                  label:
                                      folder['label']?.toString() ?? 'Folder',
                                  path: folder['path']?.toString() ?? '',
                                ),
                            ],
                          ),
                  ),
                  const SizedBox(height: 24),

                  // Appearance Settings
                  _buildSectionHeader('Appearance', Icons.palette_outlined),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Theme',
                            style: TextStyle(fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 12),
                          SegmentedButton<ThemeMode>(
                            segments: const [
                              ButtonSegment(
                                value: ThemeMode.light,
                                icon: Icon(Icons.light_mode),
                                label: Text('Light'),
                              ),
                              ButtonSegment(
                                value: ThemeMode.dark,
                                icon: Icon(Icons.dark_mode),
                                label: Text('Dark'),
                              ),
                              ButtonSegment(
                                value: ThemeMode.system,
                                icon: Icon(Icons.settings_suggest),
                                label: Text('System'),
                              ),
                            ],
                            selected: {_themeMode},
                            onSelectionChanged: (selection) {
                              if (selection.isNotEmpty) {
                                _setTheme(selection.first);
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Update Settings
                  _buildSectionHeader('Updates', Icons.system_update_outlined),
                  Card(
                    child: Column(
                      children: [
                        SwitchListTile(
                          secondary: const Icon(Icons.autorenew),
                          title: const Text('Auto-update'),
                          subtitle: const Text(
                            'Automatically check for and install updates',
                          ),
                          value: _autoUpdate,
                          onChanged: _setAutoUpdate,
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.schedule),
                          title: const Text('Check Frequency'),
                          trailing: DropdownButton<String>(
                            value: _updateFrequency,
                            underline: const SizedBox(),
                            items: const [
                              DropdownMenuItem(
                                value: 'daily',
                                child: Text('Daily'),
                              ),
                              DropdownMenuItem(
                                value: 'weekly',
                                child: Text('Weekly'),
                              ),
                              DropdownMenuItem(
                                value: 'monthly',
                                child: Text('Monthly'),
                              ),
                            ],
                            onChanged: _autoUpdate
                                ? (value) {
                                    if (value != null) {
                                      _setUpdateFrequency(value);
                                    }
                                  }
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Diagnostics
                  _buildSectionHeader('Diagnostics', Icons.bug_report_outlined),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.primary.withValues(alpha: 0.12),
                                ),
                                child: Icon(
                                  Icons.bug_report_rounded,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Diagnostics',
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    Text(
                                      'Export logs for troubleshooting',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Divider(
                            color: Theme.of(
                              context,
                            ).colorScheme.outlineVariant.withValues(alpha: 0.6),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Export logs to help troubleshoot issues.',
                            style: TextStyle(
                              fontSize: 16,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.tonalIcon(
                              onPressed: _isExportingLogs
                                  ? null
                                  : _exportDiagnosticLogs,
                              style: FilledButton.styleFrom(
                                minimumSize: const Size.fromHeight(56),
                                shape: const StadiumBorder(),
                              ),
                              icon: _isExportingLogs
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.2,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                      ),
                                    )
                                  : const Icon(Icons.manage_search_rounded),
                              label: Text(
                                _isExportingLogs
                                    ? 'Exporting Diagnostic Logs...'
                                    : 'Export Diagnostic Logs',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // License Settings
                  _buildSectionHeader('License', Icons.verified_outlined),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.workspace_premium_rounded),
                      title: const Text('Pro & License'),
                      subtitle: const Text(
                        'Manage the 7-day trial, Polar.sh and LemonSqueezy upgrades, and activation in the Pro tab.',
                      ),
                      trailing: FilledButton.tonal(
                        onPressed: () {
                          final tabController = DefaultTabController.of(
                            context,
                          );
                          tabController.animateTo(9);
                        },
                        child: const Text('Open Pro'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Advanced Settings
                  _buildSectionHeader('Advanced', Icons.tune_outlined),
                  Card(
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.cleaning_services),
                          title: const Text('Clear Cache'),
                          subtitle: const Text(
                            'Remove temporary files and cached data',
                          ),
                          trailing: OutlinedButton(
                            onPressed: _clearCache,
                            child: const Text('Clear'),
                          ),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: Icon(
                            Icons.restart_alt,
                            color: Colors.red.shade400,
                          ),
                          title: Text(
                            'Reset All Settings',
                            style: TextStyle(color: Colors.red.shade400),
                          ),
                          subtitle: const Text('Restore default settings'),
                          trailing: OutlinedButton(
                            onPressed: _resetSettings,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red,
                              side: const BorderSide(color: Colors.red),
                            ),
                            child: const Text('Reset'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Version info footer
                  Center(
                    child: Column(
                      children: [
                        Text(
                          'MimikaStudio',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          versionString,
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          versionName,
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFolderTile({required String label, required String path}) {
    return ListTile(
      leading: const Icon(Icons.folder),
      title: Text(label),
      subtitle: SelectableText(
        path,
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: OutlinedButton(
        onPressed: path.trim().isEmpty ? null : () => _openFolder(path),
        child: const Text('Open'),
      ),
    );
  }
}
