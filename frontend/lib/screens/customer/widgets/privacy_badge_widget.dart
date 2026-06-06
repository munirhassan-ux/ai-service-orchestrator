import 'package:flutter/material.dart';
import '../privacy_log_screen.dart';

class PrivacyBadgeWidget extends StatelessWidget {
  final String? sessionId;
  final int redactionCount;

  const PrivacyBadgeWidget({
    super.key,
    required this.sessionId,
    this.redactionCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: sessionId != null
          ? () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PrivacyLogScreen(sessionId: sessionId!),
                ),
              )
          : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFFf0fdf4),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: const Color(0xFF079455).withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.shield_outlined, size: 13, color: Color(0xFF079455)),
            const SizedBox(width: 4),
            Text(
              redactionCount > 0
                  ? '$redactionCount field${redactionCount == 1 ? '' : 's'} masked'
                  : 'Privacy protected',
              style: const TextStyle(
                fontFamily: 'Satoshi Variable',
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: Color(0xFF079455),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
