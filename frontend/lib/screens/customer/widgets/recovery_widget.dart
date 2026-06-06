import 'package:flutter/material.dart';

/// Shown in the chat thread when a provider cancels post-lock.
/// Displays: apology, compensation badge, new provider comparison card.
class RecoveryWidget extends StatelessWidget {
  final String apologyMessage;
  final Map<String, dynamic> compensation;
  final Map<String, dynamic>? newBooking;
  final String cause;

  const RecoveryWidget({
    super.key,
    required this.apologyMessage,
    required this.compensation,
    this.newBooking,
    required this.cause,
  });

  static const _compensationColors = {
    'priority_rematch': Color(0xFF6938ef),
    'fee_waiver': Color(0xFF079455),
    'honour_original_price': Color(0xFF0070f3),
    'apology_retry': Color(0xFFf59e0b),
  };

  static const _compensationIcons = {
    'priority_rematch': Icons.flash_on_outlined,
    'fee_waiver': Icons.savings_outlined,
    'honour_original_price': Icons.price_check_outlined,
    'apology_retry': Icons.replay_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final compType = compensation['type'] as String? ?? 'apology_retry';
    final compDesc = compensation['description'] as String? ?? '';
    final compColor = _compensationColors[compType] ?? const Color(0xFF697586);
    final compIcon = _compensationIcons[compType] ?? Icons.info_outline;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Apology bubble
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFfff7ed),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFf59e0b).withValues(alpha: 0.3)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.support_agent_outlined, color: Color(0xFFf59e0b), size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  apologyMessage,
                  style: const TextStyle(
                    fontFamily: 'Satoshi Variable',
                    fontSize: 13,
                    color: Color(0xFF121926),
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 8),

        // Compensation badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: compColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: compColor.withValues(alpha: 0.25)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(compIcon, size: 14, color: compColor),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  compDesc,
                  style: TextStyle(
                    fontFamily: 'Satoshi Variable',
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: compColor,
                  ),
                ),
              ),
            ],
          ),
        ),

        if (newBooking != null) ...[
          const SizedBox(height: 8),
          _newProviderCard(),
        ],
      ],
    );
  }

  Widget _newProviderCard() {
    final nb = newBooking!;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF6938ef).withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6938ef).withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person_outline, size: 14, color: Color(0xFF6938ef)),
              const SizedBox(width: 6),
              Text(
                nb['provider_name'] ?? 'New Provider',
                style: const TextStyle(
                  fontFamily: 'Satoshi Variable',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF121926),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFf0fdf4),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'Reassigned',
                  style: TextStyle(
                    fontFamily: 'Satoshi Variable',
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF079455),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Rs. ${nb['final_price']} · ${nb['booking_id']}',
            style: const TextStyle(
              fontFamily: 'Satoshi Variable',
              fontSize: 12,
              color: Color(0xFF697586),
            ),
          ),
        ],
      ),
    );
  }
}
