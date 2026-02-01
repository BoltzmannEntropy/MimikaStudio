import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:url_launcher/url_launcher.dart';

class AudioPlayerWidget extends StatefulWidget {
  final AudioPlayer player;
  final String? audioUrl;
  final String modelName;
  final String? filename;

  const AudioPlayerWidget({
    super.key,
    required this.player,
    required this.audioUrl,
    required this.modelName,
    this.filename,
  });

  @override
  State<AudioPlayerWidget> createState() => _AudioPlayerWidgetState();
}

class _AudioPlayerWidgetState extends State<AudioPlayerWidget> {
  double _volume = 1.0;
  bool _isDragging = false;
  double _dragValue = 0.0;

  @override
  void initState() {
    super.initState();
    _volume = widget.player.volume;
  }

  String _formatDuration(Duration? duration) {
    if (duration == null) return '0:00';
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            // Model name badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                widget.modelName,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Play/Pause button
            StreamBuilder<PlayerState>(
              stream: widget.player.playerStateStream,
              builder: (context, snapshot) {
                final playerState = snapshot.data;
                final processingState = playerState?.processingState;
                final playing = playerState?.playing;

                if (processingState == ProcessingState.loading ||
                    processingState == ProcessingState.buffering) {
                  return const SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  );
                } else if (playing != true) {
                  return IconButton(
                    iconSize: 24,
                    onPressed: () async {
                      if (widget.audioUrl != null) {
                        if (processingState == ProcessingState.completed ||
                            widget.player.duration == null) {
                          await widget.player.setUrl(widget.audioUrl!);
                          await widget.player.seek(Duration.zero);
                        }
                        widget.player.play();
                      }
                    },
                    icon: const Icon(Icons.play_arrow),
                    style: IconButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    ),
                  );
                } else {
                  return IconButton(
                    iconSize: 24,
                    onPressed: widget.player.pause,
                    icon: const Icon(Icons.pause),
                    style: IconButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    ),
                  );
                }
              },
            ),

            // Stop button
            IconButton(
              iconSize: 20,
              onPressed: () async {
                await widget.player.stop();
                await widget.player.seek(Duration.zero);
              },
              icon: const Icon(Icons.stop),
              tooltip: 'Stop',
            ),

            // Progress slider and time
            Expanded(
              child: StreamBuilder<Duration?>(
                stream: widget.player.durationStream,
                builder: (context, durationSnapshot) {
                  final duration = durationSnapshot.data ?? Duration.zero;
                  return StreamBuilder<Duration>(
                    stream: widget.player.positionStream,
                    builder: (context, positionSnapshot) {
                      final position = positionSnapshot.data ?? Duration.zero;

                      // Calculate slider value - use drag value if dragging
                      final sliderValue = _isDragging
                          ? _dragValue
                          : (duration.inMilliseconds > 0
                              ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
                              : 0.0);

                      // Calculate display position based on drag or actual position
                      final displayPosition = _isDragging
                          ? Duration(milliseconds: (_dragValue * duration.inMilliseconds).round())
                          : position;

                      return Row(
                        children: [
                          Text(
                            _formatDuration(displayPosition),
                            style: const TextStyle(fontSize: 11),
                          ),
                          Expanded(
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 4,
                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                              ),
                              child: Slider(
                                value: sliderValue,
                                onChangeStart: (value) {
                                  setState(() {
                                    _isDragging = true;
                                    _dragValue = value;
                                  });
                                },
                                onChanged: (value) {
                                  setState(() {
                                    _dragValue = value;
                                  });
                                },
                                onChangeEnd: (value) {
                                  setState(() {
                                    _isDragging = false;
                                  });
                                  widget.player.seek(Duration(
                                    milliseconds: (value * duration.inMilliseconds).round(),
                                  ));
                                },
                              ),
                            ),
                          ),
                          Text(
                            _formatDuration(duration),
                            style: const TextStyle(fontSize: 11),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),

            // Volume
            const SizedBox(width: 8),
            Icon(
              _volume == 0 ? Icons.volume_off : Icons.volume_up,
              size: 18,
            ),
            SizedBox(
              width: 80,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                ),
                child: Slider(
                  value: _volume,
                  min: 0.0,
                  max: 1.0,
                  onChanged: (value) {
                    setState(() => _volume = value);
                    widget.player.setVolume(value);
                  },
                ),
              ),
            ),

            // Download button
            const SizedBox(width: 4),
            IconButton(
              iconSize: 20,
              onPressed: widget.audioUrl != null
                  ? () async {
                      final url = Uri.parse(widget.audioUrl!);
                      if (await canLaunchUrl(url)) {
                        await launchUrl(url);
                      }
                    }
                  : null,
              icon: const Icon(Icons.download),
              tooltip: 'Download audio',
            ),

            // Copy path button
            if (widget.filename != null) ...[
              IconButton(
                iconSize: 20,
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: widget.filename!));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Copied: ${widget.filename}'),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
                icon: const Icon(Icons.copy),
                tooltip: 'Copy filename',
              ),
            ],
          ],
        ),
      ),
    );
  }
}
