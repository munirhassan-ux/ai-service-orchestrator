import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
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
    const green = Color(0xFF3A9010);
    const forest = Color(0xFF163300);
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAF5),
      body: SafeArea(child: FadeTransition(opacity: _fade, child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          SvgPicture.asset('assets/haazir_logo.svg', height: 48),
          const SizedBox(height: 12),
          const Text("AI-Powered Home Services", style: TextStyle(fontSize: 13, color: Color(0xFF767773), letterSpacing: 0.5)),
          const SizedBox(height: 60),
          _roleCard(
            title: "Mujhe service chahiye",
            subtitle: "I need a service",
            icon: Icons.person_search_rounded,
            color: green,
            borderColor: forest,
            description: "Plumber • Electrician • AC • Cleaning • Carpenter",
            onTap: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const CustomerHome())),
          ),
          const SizedBox(height: 18),
          _roleCard(
            title: "Main service deta hoon",
            subtitle: "I provide a service",
            icon: Icons.engineering_rounded,
            color: green,
            borderColor: forest,
            description: "Register as a Haazir service professional",
            onTap: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const ProviderHome())),
          ),
          const SizedBox(height: 40),
          const Text("No login required • AI-powered • Islamabad demo", style: TextStyle(color: Color(0xFF767773), fontSize: 11)),
        ]),
      ))),
    );
  }

  Widget _roleCard({required String title, required String subtitle, required IconData icon, required Color color, required Color borderColor, required String description, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: borderColor.withValues(alpha: 0.25), width: 1.5),
        ),
        child: Row(children: [
          Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16)), child: Icon(icon, color: color, size: 30)),
          const SizedBox(width: 18),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: borderColor)),
            const SizedBox(height: 2),
            const Text("", style: TextStyle(fontSize: 13, color: Color(0xFF565955))),
            Text(subtitle, style: const TextStyle(fontSize: 13, color: Color(0xFF565955))),
            const SizedBox(height: 5),
            Text(description, style: const TextStyle(fontSize: 11, color: Color(0xFF767773))),
          ])),
          Icon(Icons.arrow_forward_ios_rounded, color: color.withValues(alpha: 0.7), size: 16),
        ]),
      ),
    );
  }
}
