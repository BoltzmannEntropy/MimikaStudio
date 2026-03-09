import 'package:flutter/material.dart';

Future<void> showGenerationMetricsDialog(
  BuildContext context, {
  required String title,
  required Map<String, dynamic> payload,
}) async {
  final metrics = (payload['metrics'] as Map<String, dynamic>?) ?? payload;
  final chunks =
      (metrics['chunk_durations_seconds'] as List<dynamic>? ?? const [])
          .map((e) => (e as num).toDouble())
          .toList(growable: false);

  String formatSeconds(num? value) {
    if (value == null) return '-';
    return '${value.toStringAsFixed(3)}s';
  }

  Future<void> openDialog() {
    return showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Generation Metrics - $title'),
          content: SizedBox(
            width: 640,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _metricRow(
                    'Started',
                    metrics['started_at']?.toString() ?? '-',
                  ),
                  _metricRow(
                    'Completed',
                    metrics['completed_at']?.toString() ?? '-',
                  ),
                  _metricRow(
                    'Total Time',
                    formatSeconds(metrics['total_time_seconds'] as num?),
                  ),
                  _metricRow(
                    'Chunks',
                    (metrics['total_chunks'] ?? chunks.length).toString(),
                  ),
                  _metricRow(
                    'Avg Chunk',
                    formatSeconds(metrics['avg_chunk_time_seconds'] as num?),
                  ),
                  _metricRow(
                    'Min Chunk',
                    formatSeconds(metrics['min_chunk_time_seconds'] as num?),
                  ),
                  _metricRow(
                    'Max Chunk',
                    formatSeconds(metrics['max_chunk_time_seconds'] as num?),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Chunk Duration Chart',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 10),
                  if (chunks.isEmpty)
                    const Text(
                      'No per-chunk timings available for this item.',
                      style: TextStyle(fontSize: 12),
                    )
                  else
                    SizedBox(
                      height: 220,
                      child: CustomPaint(
                        painter: _ChunkLineChartPainter(
                          values: chunks,
                          lineColor: Theme.of(context).colorScheme.primary,
                          axisColor: Theme.of(context).dividerColor,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.only(top: 4, right: 8),
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: Text(
                              'Chunk Index',
                              style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  return openDialog();
}

Widget _metricRow(String label, String value) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 12))),
      ],
    ),
  );
}

class _ChunkLineChartPainter extends CustomPainter {
  const _ChunkLineChartPainter({
    required this.values,
    required this.lineColor,
    required this.axisColor,
  });

  final List<double> values;
  final Color lineColor;
  final Color axisColor;

  @override
  void paint(Canvas canvas, Size size) {
    final chartLeft = 32.0;
    final chartTop = 12.0;
    final chartRight = size.width - 12.0;
    final chartBottom = size.height - 28.0;
    final chartWidth = chartRight - chartLeft;
    final chartHeight = chartBottom - chartTop;

    final axisPaint = Paint()
      ..color = axisColor
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    canvas.drawLine(
      Offset(chartLeft, chartBottom),
      Offset(chartRight, chartBottom),
      axisPaint,
    );
    canvas.drawLine(
      Offset(chartLeft, chartTop),
      Offset(chartLeft, chartBottom),
      axisPaint,
    );

    if (values.isEmpty) return;

    final maxValue = values
        .reduce((a, b) => a > b ? a : b)
        .clamp(0.001, double.infinity);
    final minValue = values
        .reduce((a, b) => a < b ? a : b)
        .clamp(0.0, double.infinity);
    final span = (maxValue - minValue).abs() < 0.0001
        ? 1.0
        : (maxValue - minValue);

    Offset pointAt(int index, double value) {
      final x = values.length == 1
          ? chartLeft + (chartWidth / 2)
          : chartLeft + (index / (values.length - 1)) * chartWidth;
      final normalized = (value - minValue) / span;
      final y = chartBottom - normalized * chartHeight;
      return Offset(x, y);
    }

    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final path = Path();
    for (int i = 0; i < values.length; i++) {
      final p = pointAt(i, values[i]);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(path, linePaint);

    final dotPaint = Paint()..color = lineColor;
    for (int i = 0; i < values.length; i++) {
      final p = pointAt(i, values[i]);
      canvas.drawCircle(p, 2.5, dotPaint);
    }

    final labelStyle = TextStyle(color: axisColor, fontSize: 10);
    final maxPainter = TextPainter(
      text: TextSpan(text: maxValue.toStringAsFixed(2), style: labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    maxPainter.paint(canvas, Offset(2, chartTop - 6));

    final minPainter = TextPainter(
      text: TextSpan(text: minValue.toStringAsFixed(2), style: labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    minPainter.paint(canvas, Offset(2, chartBottom - 10));
  }

  @override
  bool shouldRepaint(covariant _ChunkLineChartPainter oldDelegate) {
    if (oldDelegate.values.length != values.length) return true;
    for (int i = 0; i < values.length; i++) {
      if (oldDelegate.values[i] != values[i]) return true;
    }
    return oldDelegate.lineColor != lineColor ||
        oldDelegate.axisColor != axisColor;
  }
}
