import 'package:flutter/material.dart';
import '../services/api_service.dart';

class McpEndpointsScreen extends StatefulWidget {
  const McpEndpointsScreen({super.key});

  @override
  State<McpEndpointsScreen> createState() => _McpEndpointsScreenState();
}

class _McpEndpointsScreenState extends State<McpEndpointsScreen> {
  final ApiService _api = ApiService();
  bool _loading = true;
  bool _mcpOnline = false;
  bool _backendOnline = false;
  Map<String, dynamic>? _systemInfo;
  List<Map<String, dynamic>> _mcpTools = [];
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final futures = await Future.wait([
      _api.checkHealth(),
      _api.checkMcpHealth(),
      _api.getSystemInfo().catchError((_) => <String, dynamic>{}),
      _api.getMcpTools().catchError((_) => <Map<String, dynamic>>[]),
    ]);
    if (mounted) {
      setState(() {
        _backendOnline = futures[0] as bool;
        _mcpOnline = futures[1] as bool;
        _systemInfo = futures[2] as Map<String, dynamic>?;
        _mcpTools = futures[3] as List<Map<String, dynamic>>;
        _loading = false;
      });
    }
  }

  // Static REST API endpoint definitions
  static const List<Map<String, dynamic>> _restEndpoints = [
    // System & Health
    {
      'method': 'GET',
      'path': '/api/health',
      'description': 'Health check',
      'category': 'System & Health',
    },
    {
      'method': 'GET',
      'path': '/api/system/info',
      'description': 'System information (device, models, versions)',
      'category': 'System & Health',
    },
    {
      'method': 'GET',
      'path': '/api/system/stats',
      'description': 'Real-time CPU, RAM, GPU stats',
      'category': 'System & Health',
    },
    // Kokoro
    {
      'method': 'POST',
      'path': '/api/kokoro/generate',
      'description': 'Generate speech with Kokoro TTS',
      'category': 'Kokoro TTS',
    },
    {
      'method': 'GET',
      'path': '/api/kokoro/voices',
      'description': 'List British Kokoro voices',
      'category': 'Kokoro TTS',
    },
    {
      'method': 'GET',
      'path': '/api/kokoro/audio/list',
      'description': 'List generated Kokoro audio files',
      'category': 'Kokoro TTS',
    },
    {
      'method': 'DELETE',
      'path': '/api/kokoro/audio/{filename}',
      'description': 'Delete a Kokoro audio file',
      'category': 'Kokoro TTS',
    },
    // Qwen3
    {
      'method': 'POST',
      'path': '/api/qwen3/generate',
      'description': 'Generate speech (clone or custom mode)',
      'category': 'Qwen3 TTS',
    },
    {
      'method': 'POST',
      'path': '/api/qwen3/generate/stream',
      'description': 'Generate with streaming response',
      'category': 'Qwen3 TTS',
    },
    {
      'method': 'GET',
      'path': '/api/qwen3/voices',
      'description': 'List saved voice samples',
      'category': 'Qwen3 TTS',
    },
    {
      'method': 'GET',
      'path': '/api/qwen3/voices/{name}/audio',
      'description': 'Serve voice preview audio',
      'category': 'Qwen3 TTS',
    },
    {
      'method': 'POST',
      'path': '/api/qwen3/voices',
      'description': 'Upload voice sample',
      'category': 'Qwen3 TTS',
    },
    {
      'method': 'DELETE',
      'path': '/api/qwen3/voices/{name}',
      'description': 'Delete a voice sample',
      'category': 'Qwen3 TTS',
    },
    {
      'method': 'PUT',
      'path': '/api/qwen3/voices/{name}',
      'description': 'Update voice sample',
      'category': 'Qwen3 TTS',
    },
    {
      'method': 'GET',
      'path': '/api/qwen3/speakers',
      'description': 'List preset speakers',
      'category': 'Qwen3 TTS',
    },
    {
      'method': 'GET',
      'path': '/api/qwen3/models',
      'description': 'List available models',
      'category': 'Qwen3 TTS',
    },
    {
      'method': 'GET',
      'path': '/api/qwen3/languages',
      'description': 'List supported languages',
      'category': 'Qwen3 TTS',
    },
    {
      'method': 'GET',
      'path': '/api/qwen3/info',
      'description': 'Model information',
      'category': 'Qwen3 TTS',
    },
    {
      'method': 'POST',
      'path': '/api/qwen3/clear-cache',
      'description': 'Clear voice prompt cache',
      'category': 'Qwen3 TTS',
    },
    // Chatterbox
    {
      'method': 'POST',
      'path': '/api/chatterbox/generate',
      'description': 'Generate speech with Chatterbox',
      'category': 'Chatterbox TTS',
    },
    {
      'method': 'GET',
      'path': '/api/chatterbox/voices',
      'description': 'List voice samples',
      'category': 'Chatterbox TTS',
    },
    {
      'method': 'GET',
      'path': '/api/chatterbox/voices/{name}/audio',
      'description': 'Serve voice preview audio',
      'category': 'Chatterbox TTS',
    },
    {
      'method': 'POST',
      'path': '/api/chatterbox/voices',
      'description': 'Upload voice sample',
      'category': 'Chatterbox TTS',
    },
    {
      'method': 'DELETE',
      'path': '/api/chatterbox/voices/{name}',
      'description': 'Delete a voice sample',
      'category': 'Chatterbox TTS',
    },
    {
      'method': 'PUT',
      'path': '/api/chatterbox/voices/{name}',
      'description': 'Update voice sample',
      'category': 'Chatterbox TTS',
    },
    {
      'method': 'GET',
      'path': '/api/chatterbox/languages',
      'description': 'List supported languages',
      'category': 'Chatterbox TTS',
    },
    {
      'method': 'GET',
      'path': '/api/chatterbox/info',
      'description': 'Model information',
      'category': 'Chatterbox TTS',
    },
    // Unified voices
    {
      'method': 'GET',
      'path': '/api/voices/custom',
      'description': 'List all custom voice samples across engines',
      'category': 'Voice Management',
    },
    // Audiobook
    {
      'method': 'POST',
      'path': '/api/audiobook/generate',
      'description': 'Start audiobook generation from text',
      'category': 'Audiobook',
    },
    {
      'method': 'POST',
      'path': '/api/audiobook/generate-from-file',
      'description': 'Start from uploaded file (PDF, EPUB, TXT)',
      'category': 'Audiobook',
    },
    {
      'method': 'GET',
      'path': '/api/audiobook/status/{job_id}',
      'description': 'Get job status with progress',
      'category': 'Audiobook',
    },
    {
      'method': 'POST',
      'path': '/api/audiobook/cancel/{job_id}',
      'description': 'Cancel generation job',
      'category': 'Audiobook',
    },
    {
      'method': 'GET',
      'path': '/api/audiobook/list',
      'description': 'List all audiobooks',
      'category': 'Audiobook',
    },
    {
      'method': 'DELETE',
      'path': '/api/audiobook/{job_id}',
      'description': 'Delete an audiobook',
      'category': 'Audiobook',
    },
    // Audio Library
    {
      'method': 'GET',
      'path': '/api/tts/audio/list',
      'description': 'List generated TTS audio files',
      'category': 'Audio Library',
    },
    {
      'method': 'DELETE',
      'path': '/api/tts/audio/{filename}',
      'description': 'Delete TTS audio file',
      'category': 'Audio Library',
    },
    {
      'method': 'GET',
      'path': '/api/voice-clone/audio/list',
      'description': 'List voice clone audio files',
      'category': 'Audio Library',
    },
    {
      'method': 'DELETE',
      'path': '/api/voice-clone/audio/{filename}',
      'description': 'Delete voice clone audio file',
      'category': 'Audio Library',
    },
    // Samples
    {
      'method': 'GET',
      'path': '/api/samples/{engine}',
      'description': 'Get sample texts for engine',
      'category': 'Samples',
    },
    {
      'method': 'GET',
      'path': '/api/pregenerated',
      'description': 'List pregenerated audio samples',
      'category': 'Samples',
    },
    {
      'method': 'GET',
      'path': '/api/voice-samples',
      'description': 'List voice sample sentences',
      'category': 'Samples',
    },
  ];

  List<Map<String, dynamic>> _filteredTools() {
    if (_searchQuery.isEmpty) return _mcpTools;
    final q = _searchQuery.toLowerCase();
    return _mcpTools.where((t) {
      final name = (t['name'] as String? ?? '').toLowerCase();
      final desc = (t['description'] as String? ?? '').toLowerCase();
      return name.contains(q) || desc.contains(q);
    }).toList();
  }

  List<Map<String, dynamic>> _filteredEndpoints() {
    if (_searchQuery.isEmpty) return _restEndpoints;
    final q = _searchQuery.toLowerCase();
    return _restEndpoints.where((ep) {
      final path = (ep['path'] as String? ?? '').toLowerCase();
      final desc = (ep['description'] as String? ?? '').toLowerCase();
      final method = (ep['method'] as String? ?? '').toLowerCase();
      return path.contains(q) || desc.contains(q) || method.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Server status cards
            _buildServerStatusRow(colorScheme),
            const SizedBox(height: 16),

            // Search bar
            TextField(
              decoration: InputDecoration(
                hintText: 'Search tools and endpoints...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: colorScheme.surfaceContainerLow,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
            const SizedBox(height: 20),

            // MCP Tools section
            _buildSectionHeader(
              'MCP Tools',
              Icons.extension,
              '${_filteredTools().length} tools',
              colorScheme.primary,
            ),
            const SizedBox(height: 8),
            _buildMcpToolsList(colorScheme),
            const SizedBox(height: 24),

            // REST API section
            _buildSectionHeader(
              'REST API Endpoints',
              Icons.api,
              '${_filteredEndpoints().length} endpoints',
              colorScheme.tertiary,
            ),
            const SizedBox(height: 8),
            _buildRestEndpointsList(colorScheme),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildServerStatusRow(ColorScheme colorScheme) {
    return Row(
      children: [
        Expanded(
          child: _buildServerCard(
            'Backend API',
            ApiService.baseUrl,
            _backendOnline,
            Icons.dns,
            colorScheme,
            subtitle: _systemInfo != null
                ? '${_systemInfo!['device'] ?? 'Unknown device'}'
                : null,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildServerCard(
            'MCP Server',
            'http://localhost:8010',
            _mcpOnline,
            Icons.hub,
            colorScheme,
            subtitle: _mcpOnline ? 'mimikastudio-mcp v2.0.0' : null,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildServerCard(
            'API Docs',
            '${ApiService.baseUrl}/docs',
            _backendOnline,
            Icons.description,
            colorScheme,
            subtitle: 'Swagger / OpenAPI',
          ),
        ),
      ],
    );
  }

  Widget _buildServerCard(
    String title,
    String url,
    bool online,
    IconData icon,
    ColorScheme colorScheme, {
    String? subtitle,
  }) {
    final statusColor = online ? Colors.green : Colors.red;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: statusColor.withValues(alpha: 0.4),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              url,
              style: TextStyle(
                fontSize: 11,
                color: colorScheme.onSurfaceVariant,
                fontFamily: 'monospace',
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(
    String title,
    IconData icon,
    String badge,
    Color color,
  ) {
    return Row(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            badge,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMcpToolsList(ColorScheme colorScheme) {
    if (_mcpTools.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Column(
              children: [
                Icon(
                  Icons.cloud_off,
                  size: 40,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 8),
                Text(
                  _mcpOnline ? 'No tools found' : 'MCP server not connected',
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
                if (!_mcpOnline) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Start with: ./bin/mimikactl up',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    // Group filtered tools
    final filtered = _filteredTools();
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final tool in filtered) {
      final name = tool['name'] as String? ?? '';
      String category;
      if (name.startsWith('health') || name.startsWith('tts_system')) {
        category = 'System & Health';
      } else if (name.startsWith('tts_generate_kokoro') ||
          name.startsWith('kokoro') ||
          name == 'tts_list_voices' ||
          name.startsWith('tts_audio')) {
        category = 'Kokoro TTS';
      } else if (name.startsWith('qwen3') || name == 'tts_generate_qwen3') {
        category = 'Qwen3 TTS';
      } else if (name.startsWith('chatterbox')) {
        category = 'Chatterbox TTS';
      } else if (name.startsWith('audiobook')) {
        category = 'Audiobook';
      } else if (name.startsWith('voice_clone') ||
          name == 'list_all_custom_voices') {
        category = 'Voice Management';
      } else if (name.startsWith('list_samples') ||
          name.startsWith('list_pregenerated') ||
          name.startsWith('list_voice_samples')) {
        category = 'Samples';
      } else {
        category = 'Other';
      }
      groups.putIfAbsent(category, () => []);
      groups[category]!.add(tool);
    }

    final categoryOrder = [
      'System & Health',
      'Kokoro TTS',
      'Qwen3 TTS',
      'Chatterbox TTS',
      'Voice Management',
      'Audiobook',
      'Samples',
      'Other',
    ];
    final sortedKeys = groups.keys.toList()
      ..sort(
        (a, b) => categoryOrder.indexOf(a).compareTo(categoryOrder.indexOf(b)),
      );

    final categoryIcons = {
      'System & Health': Icons.monitor_heart,
      'Kokoro TTS': Icons.volume_up,
      'Qwen3 TTS': Icons.record_voice_over,
      'Chatterbox TTS': Icons.chat_bubble,
      'Voice Management': Icons.library_music,
      'Audiobook': Icons.menu_book,
      'Samples': Icons.playlist_play,
      'Other': Icons.more_horiz,
    };

    final categoryColors = {
      'System & Health': Colors.green,
      'Kokoro TTS': Colors.indigo,
      'Qwen3 TTS': Colors.teal,
      'Chatterbox TTS': Colors.orange,
      'Voice Management': Colors.purple,
      'Audiobook': Colors.blue,
      'Samples': Colors.pink,
      'Other': Colors.blueGrey,
    };

    return Column(
      children: sortedKeys.map((category) {
        final tools = groups[category]!;
        final icon = categoryIcons[category] ?? Icons.extension;
        final color = categoryColors[category] ?? colorScheme.primary;
        return _buildCategoryExpansionTile(
          category,
          icon,
          color,
          tools,
          colorScheme,
        );
      }).toList(),
    );
  }

  Widget _buildCategoryExpansionTile(
    String category,
    IconData icon,
    Color color,
    List<Map<String, dynamic>> tools,
    ColorScheme colorScheme,
  ) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: Icon(icon, color: color, size: 20),
        title: Row(
          children: [
            Text(
              category,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: color,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${tools.length}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ),
          ],
        ),
        children: tools
            .map((tool) => _buildMcpToolTile(tool, colorScheme))
            .toList(),
      ),
    );
  }

  Widget _buildMcpToolTile(Map<String, dynamic> tool, ColorScheme colorScheme) {
    final name = tool['name'] as String? ?? '';
    final desc = tool['description'] as String? ?? '';
    final inputSchema = tool['inputSchema'] as Map<String, dynamic>?;
    final properties =
        inputSchema?['properties'] as Map<String, dynamic>? ?? {};
    final required = List<String>.from(inputSchema?['required'] ?? []);

    return ExpansionTile(
      tilePadding: const EdgeInsets.only(left: 56, right: 16),
      childrenPadding: const EdgeInsets.only(left: 72, right: 16, bottom: 12),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'TOOL',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: colorScheme.onPrimaryContainer,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              name,
              style: const TextStyle(
                fontSize: 13,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
      subtitle: Text(
        desc,
        style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      children: [
        if (properties.isNotEmpty) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Parameters:',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
          ),
          const SizedBox(height: 4),
          ...properties.entries.map((entry) {
            final paramName = entry.key;
            final paramInfo = entry.value as Map<String, dynamic>? ?? {};
            final paramType = paramInfo['type'] as String? ?? 'any';
            final paramDesc = paramInfo['description'] as String? ?? '';
            final isRequired = required.contains(paramName);
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 140,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          paramName,
                          style: TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                            color: colorScheme.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (isRequired)
                          Text(
                            ' *',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.red.shade400,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      paramType,
                      style: TextStyle(
                        fontSize: 10,
                        color: colorScheme.onSurfaceVariant,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      paramDesc,
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ] else
          Text(
            'No parameters',
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
          ),
      ],
    );
  }

  Widget _buildRestEndpointsList(ColorScheme colorScheme) {
    final filtered = _filteredEndpoints();
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final ep in filtered) {
      final cat = ep['category'] as String;
      groups.putIfAbsent(cat, () => []);
      groups[cat]!.add(ep);
    }

    final categoryOrder = [
      'System & Health',
      'Kokoro TTS',
      'Qwen3 TTS',
      'Chatterbox TTS',
      'Voice Management',
      'Audiobook',
      'Audio Library',
      'Samples',
    ];
    final sortedKeys = groups.keys.toList()
      ..sort(
        (a, b) => categoryOrder.indexOf(a).compareTo(categoryOrder.indexOf(b)),
      );

    final categoryIcons = {
      'System & Health': Icons.monitor_heart,
      'Kokoro TTS': Icons.volume_up,
      'Qwen3 TTS': Icons.record_voice_over,
      'Chatterbox TTS': Icons.chat_bubble,
      'Voice Management': Icons.library_music,
      'Audiobook': Icons.menu_book,
      'Audio Library': Icons.audiotrack,
      'Samples': Icons.playlist_play,
    };

    final categoryColors = {
      'System & Health': Colors.green,
      'Kokoro TTS': Colors.indigo,
      'Qwen3 TTS': Colors.teal,
      'Chatterbox TTS': Colors.orange,
      'Voice Management': Colors.purple,
      'Audiobook': Colors.blue,
      'Audio Library': Colors.cyan,
      'Samples': Colors.pink,
    };

    return Column(
      children: sortedKeys.map((category) {
        final endpoints = groups[category]!;
        final icon = categoryIcons[category] ?? Icons.api;
        final color = categoryColors[category] ?? colorScheme.tertiary;
        return _buildRestCategoryTile(
          category,
          icon,
          color,
          endpoints,
          colorScheme,
        );
      }).toList(),
    );
  }

  Widget _buildRestCategoryTile(
    String category,
    IconData icon,
    Color color,
    List<Map<String, dynamic>> endpoints,
    ColorScheme colorScheme,
  ) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: Icon(icon, color: color, size: 20),
        title: Row(
          children: [
            Text(
              category,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: color,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${endpoints.length}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ),
          ],
        ),
        children: endpoints
            .map((ep) => _buildEndpointRow(ep, colorScheme))
            .toList(),
      ),
    );
  }

  Widget _buildEndpointRow(Map<String, dynamic> ep, ColorScheme colorScheme) {
    final method = ep['method'] as String;
    final path = ep['path'] as String;
    final desc = ep['description'] as String;

    final methodColors = {
      'GET': Colors.green,
      'POST': Colors.blue,
      'PUT': Colors.orange,
      'DELETE': Colors.red,
    };
    final mColor = methodColors[method] ?? colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 56, vertical: 4),
      child: Row(
        children: [
          Container(
            width: 56,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: mColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              method,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: mColor,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: Text(
              path,
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 3,
            child: Text(
              desc,
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
