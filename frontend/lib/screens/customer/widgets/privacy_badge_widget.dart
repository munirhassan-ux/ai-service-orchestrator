import 'package:flutter/material.dart';

class PrivacyBadgeWidget extends StatelessWidget {
  const PrivacyBadgeWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFf0fdf4),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: const Color(0xFF079455).withValues(alpha: 0.35)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.shield_outlined, size: 13, color: Color(0xFF079455)),
          SizedBox(width: 4),
          Text(
            'Privacy protected',
            style: TextStyle(
              fontFamily: 'Satoshi Variable',
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: Color(0xFF079455),
            ),
          ),
        ],
      ),
    );
  }
}
