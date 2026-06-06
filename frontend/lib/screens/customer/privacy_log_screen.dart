import 'package:flutter/material.dart';
import '../../services/api_service.dart';

class PrivacyLogScreen extends StatefulWidget {
  final String sessionId;
  const PrivacyLogScreen({super.key, required this.sessionId});

  @override
  State<PrivacyLogScreen> createState() => _PrivacyLogScreenState();
}

class _PrivacyLogScreenState extends State<PrivacyLogScreen> {
  List<dynamic> _log = [];
  int _strikes = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await ApiService.get('/session/${widget.sessionId}/privacy-log');
      setState(() {
        _log = (data['privacy_log'] as List?) ?? [];
        _strikes = (data['safety_strikes'] as int?) ?? 0;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  static const _typeIcon = {
    'phone': Icons.phone_outlined,
    'cnic': Icons.badge_outlined,
    'email': Icons.email_outlined,
    'address': Icons.home_outlined,
  };

  static const _typeColor = {
    'phone': Color(0xFF6938ef),
    'cnic': Color(0xFFda2721),
    'email': Color(0xFF0070f3),
    'address': Color(0xFF079455),
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFf8fafc),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Privacy Log',
          style: TextStyle(
            fontFamily: 'Satoshi Variable',
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Color(0xFF121926),
          ),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF121926)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFFcdd5df)),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF6938ef)))
          : Column(
              children: [
                _buildSummaryBanner(),
                Expanded(
                  child: _log.isEmpty
                      ? _buildEmptyState()
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _log.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (_, i) => _buildLogEntry(_log[i]),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildSummaryBanner() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFf0fdf4),
        border: Border.all(color: const Color(0xFF079455).withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFF079455).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.shield_outlined, color: Color(0xFF079455), size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _log.isEmpty
                      ? 'No personal data detected'
                      : '${_log.length} field${_log.length == 1 ? '' : 's'} masked before AI',
                  style: const TextStyle(
                    fontFamily: 'Satoshi Variable',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF079455),
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Your personal details are never sent to AI models.',
                  style: TextStyle(
                    fontFamily: 'Satoshi Variable',
                    fontSize: 12,
                    color: Color(0xFF697586),
                  ),
                ),
              ],
            ),
          ),
          if (_strikes > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFfef2f2),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFda2721).withValues(alpha: 0.3)),
              ),
              child: Text(
                '$_strikes ⚠️',
                style: const TextStyle(
                  fontFamily: 'Satoshi Variable',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFda2721),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLogEntry(dynamic entry) {
    final type = entry['type'] as String? ?? 'unknown';
    final token = entry['token'] as String? ?? '';
    final ts = entry['timestamp'] as String? ?? '';
    final icon = _typeIcon[type] ?? Icons.lock_outline;
    final color = _typeColor[type] ?? const Color(0xFF697586);
    final time = ts.isNotEmpty ? ts.substring(11, 19) : '';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFcdd5df)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${type[0].toUpperCase()}${type.substring(1)} detected and masked',
                  style: const TextStyle(
                    fontFamily: 'Satoshi Variable',
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF121926),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Replaced with $token',
                  style: const TextStyle(
                    fontFamily: 'Satoshi Variable',
                    fontSize: 12,
                    color: Color(0xFF697586),
                  ),
                ),
              ],
            ),
          ),
          Text(
            time,
            style: const TextStyle(
              fontFamily: 'Satoshi Variable',
              fontSize: 11,
              color: Color(0xFF697586),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.verified_user_outlined, size: 48, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          const Text(
            'No personal data detected\nin this session.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Satoshi Variable',
              fontSize: 14,
              color: Color(0xFF697586),
            ),
          ),
        ],
      ),
    );
  }
}
