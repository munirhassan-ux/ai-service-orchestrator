import 'package:flutter/material.dart';

class ReliabilityBadgeWidget extends StatelessWidget {
  final double score;
  final bool showLabel;

  const ReliabilityBadgeWidget({
    super.key,
    required this.score,
    this.showLabel = true,
  });

  Color get _color {
    if (score >= 80) return const Color(0xFF079455);
    if (score >= 60) return const Color(0xFFf59e0b);
    return const Color(0xFFda2721);
  }

  String get _label {
    if (score >= 80) return 'Trusted';
    if (score >= 60) return 'Good';
    return 'At Risk';
  }

  IconData get _icon {
    if (score >= 80) return Icons.verified_outlined;
    if (score >= 60) return Icons.thumb_up_outlined;
    return Icons.warning_amber_outlined;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_icon, size: 12, color: _color),
          const SizedBox(width: 4),
          Text(
            showLabel ? '$_label ${score.toStringAsFixed(0)}' : score.toStringAsFixed(0),
            style: TextStyle(
              fontFamily: 'Satoshi Variable',
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: _color,
            ),
          ),
        ],
      ),
    );
  }
}
