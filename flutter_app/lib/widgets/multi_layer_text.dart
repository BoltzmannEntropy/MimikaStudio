import 'package:flutter/material.dart';

class MultiLayerText extends StatelessWidget {
  final String native;
  final String transliteration;
  final String literal;
  final String natural;

  const MultiLayerText({
    super.key,
    required this.native,
    required this.transliteration,
    required this.literal,
    required this.natural,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Native script (black, bold, larger)
        if (native.isNotEmpty)
          Text(
            native,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
            textDirection: TextDirection.rtl,
          ),
        const SizedBox(height: 4),

        // Transliteration (orange, italic)
        if (transliteration.isNotEmpty)
          Text(
            transliteration,
            style: TextStyle(
              fontSize: 14,
              fontStyle: FontStyle.italic,
              color: Colors.orange.shade700,
            ),
          ),
        const SizedBox(height: 4),

        // Literal translation (blue)
        if (literal.isNotEmpty)
          Text(
            literal,
            style: TextStyle(
              fontSize: 13,
              color: Colors.blue.shade700,
            ),
          ),
        const SizedBox(height: 4),

        // Natural translation (green)
        if (natural.isNotEmpty)
          Text(
            natural,
            style: TextStyle(
              fontSize: 14,
              color: Colors.green.shade700,
            ),
          ),
      ],
    );
  }
}
