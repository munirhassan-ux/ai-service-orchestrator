import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'chat_screen.dart';

class ProviderDashboard extends StatefulWidget {
  const ProviderDashboard({super.key});

  @override
  State<ProviderDashboard> createState() => _ProviderDashboardState();
}

class _ProviderDashboardState extends State<ProviderDashboard> {
  bool _isAvailable = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: const Color(0xFF163300),
        elevation: 0,
        title: Text("Dashboard",
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.white)),
        actions: [
          Switch(
            value: _isAvailable,
            onChanged: (val) => setState(() => _isAvailable = val),
            activeColor: const Color(0xFF3A9010),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatGrid(),
            const SizedBox(height: 32),
            const Text(
              'ACTIVE JOBS',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  color: const Color(0xFF565955)),
            ),
            const SizedBox(height: 16),
            _buildJobCard(),
            const SizedBox(height: 32),
            const Text(
              'REPUTATION',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  color: const Color(0xFF565955)),
            ),
            const SizedBox(height: 16),
            _buildReputationCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatGrid() {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      childAspectRatio: 1.5,
      children: [
        _buildStatTile('Today\'s Earnings', 'Rs. 4,500', Icons.payments_rounded,
            Colors.green),
        _buildStatTile('Completed', '142', Icons.task_alt_rounded, Colors.blue),
        _buildStatTile(
            'Rating', '4.7 / 5.0', Icons.star_rounded, const Color(0xFF3A9010)),
        _buildStatTile(
            'Risk Score', '0.08', Icons.security_rounded, Colors.orange),
      ],
    );
  }

  Widget _buildStatTile(
      String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAF5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8EDE6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: color, size: 24),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              Text(label,
                  style: const TextStyle(
                      fontSize: 12, color: const Color(0xFF565955))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildJobCard() {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const ProviderChatScreen(),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF3A9010).withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF3A9010).withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('AC Repair - G-13',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    Text('Today, 2:00 PM',
                        style: TextStyle(color: const Color(0xFF565955))),
                  ],
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3A9010),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text('EN ROUTE',
                      style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                          fontSize: 12)),
                ),
              ],
            ),
            const Divider(height: 32, color: const Color(0xFFE8EDE6)),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Agreed Price',
                    style: TextStyle(color: const Color(0xFF3E3F3B))),
                const Text('Rs. 1,200',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF3A9010))),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReputationCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAF5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Column(
        children: [
          _ReputationRow('On-time Score', 0.94),
          SizedBox(height: 12),
          _ReputationRow('Response Rate', 0.98),
          SizedBox(height: 12),
          _ReputationRow('Cancellation Rate', 0.04),
        ],
      ),
    );
  }
}

class _ReputationRow extends StatelessWidget {
  final String label;
  final double value;
  const _ReputationRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
            flex: 3,
            child: Text(label,
                style: const TextStyle(color: const Color(0xFF3E3F3B)))),
        Expanded(
          flex: 7,
          child: LinearProgressIndicator(
            value: value,
            backgroundColor: const Color(0xFFE8EDE6),
            color:
                value > 0.8 ? const Color(0xFF3A9010) : const Color(0xFF3A9010),
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 12),
        Text('${(value * 100).toInt()}%',
            style: const TextStyle(fontWeight: FontWeight.bold)),
      ],
    );
  }
}
