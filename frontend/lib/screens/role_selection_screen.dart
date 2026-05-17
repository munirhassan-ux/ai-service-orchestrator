import 'package:flutter/material.dart';
import 'customer/customer_home.dart';
import 'provider/provider_home.dart';

class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({super.key});
  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [Color(0xFF0A0F1E), Color(0xFF0F172A), Color(0xFF111827)], begin: Alignment.topCenter, end: Alignment.bottomCenter),
        ),
        child: SafeArea(child: FadeTransition(opacity: _fade, child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            // Logo
            Container(width: 80, height: 80, decoration: BoxDecoration(
              color: const Color(0xFF00C853).withOpacity(0.12),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF00C853).withOpacity(0.4), width: 2),
            ), child: const Icon(Icons.handyman_rounded, color: Color(0xFF00C853), size: 40)),
            const SizedBox(height: 20),
            const Text("KHEDMATGAR", style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 5, color: Color(0xFF00C853))),
            const SizedBox(height: 6),
            const Text("AI Home Services Orchestrator", style: TextStyle(fontSize: 13, color: Colors.white38, letterSpacing: 1)),
            const SizedBox(height: 60),
            // Customer card
            _roleCard(
              title: "Mujhe service chahiye",
              subtitle: "I need a service",
              icon: Icons.person_search_rounded,
              color: const Color(0xFF00C853),
              description: "Plumber • Electrician • AC • Cleaning • Carpenter",
              onTap: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const CustomerHome())),
            ),
            const SizedBox(height: 18),
            // Provider card
            _roleCard(
              title: "Main service deta hoon",
              subtitle: "I provide a service",
              icon: Icons.engineering_rounded,
              color: Colors.amber,
              description: "Register as a Khedmatgar service professional",
              onTap: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const ProviderHome())),
            ),
            const SizedBox(height: 40),
            const Text("No login required • AI-powered • Islamabad demo", style: TextStyle(color: Colors.white24, fontSize: 11)),
          ]),
        ))),
      ),
    );
  }

  Widget _roleCard({required String title, required String subtitle, required IconData icon, required Color color, required String description, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: color.withOpacity(0.3), width: 1.5),
        ),
        child: Row(children: [
          Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(16)), child: Icon(icon, color: color, size: 30)),
          const SizedBox(width: 18),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 2),
            Text(subtitle, style: const TextStyle(fontSize: 13, color: Colors.white54)),
            const SizedBox(height: 5),
            Text(description, style: const TextStyle(fontSize: 11, color: Colors.white38)),
          ])),
          Icon(Icons.arrow_forward_ios_rounded, color: color.withOpacity(0.5), size: 16),
        ]),
      ),
    );
  }
}
