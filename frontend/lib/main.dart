import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'screens/customer/customer_home.dart';
import 'services/notification_service.dart';
import 'screens/provider/provider_home.dart';

void main() {
  runApp(const KhedmatgarApp());
}

class KhedmatgarApp extends StatelessWidget {
  const KhedmatgarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Khedmatgar',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFF00C853), // Emerald Green
        scaffoldBackgroundColor: const Color(0xFF0F172A), // Deep Slate
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00C853),
          brightness: Brightness.dark,
          secondary: const Color(0xFFFFD700), // Amber Gold
        ),
        textTheme: GoogleFonts.outfitTextTheme(ThemeData.dark().textTheme),
        useMaterial3: true,
      ),
      builder: (context, child) {
        return NotificationOverlay(child: child!);
      },
      home: const CustomerHome(),
    );
  }
}

class NotificationOverlay extends StatefulWidget {
  final Widget child;
  const NotificationOverlay({super.key, required this.child});

  @override
  State<NotificationOverlay> createState() => _NotificationOverlayState();
}

class _NotificationOverlayState extends State<NotificationOverlay> {
  AppNotification? _currentNotification;

  @override
  void initState() {
    super.initState();
    NotificationService().startPolling();
    NotificationService().onNotification.listen((notif) {
      if (mounted) {
        setState(() => _currentNotification = notif);
        Future.delayed(const Duration(seconds: 5), () {
          if (mounted && _currentNotification?.id == notif.id) {
            setState(() => _currentNotification = null);
          }
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_currentNotification != null)
          Positioned(
            top: 50,
            left: 16,
            right: 16,
            child: Material(
              color: Colors.transparent,
              child: GestureDetector(
                onTap: () {
                  // Handle navigation/role toggle
                  // For now we just dismiss
                  setState(() => _currentNotification = null);
                },
                child: TweenAnimationBuilder<double>(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                  tween: Tween(begin: -100, end: 0),
                  builder: (context, value, child) {
                    return Transform.translate(
                      offset: Offset(0, value),
                      child: child,
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _currentNotification!.roleTarget == 'PROVIDER'
                          ? const Color(0xFF1E293B) // Darker background for provider
                          : const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _currentNotification!.roleTarget == 'PROVIDER'
                            ? Colors.amber.withOpacity(0.5)
                            : const Color(0xFF00C853).withOpacity(0.5),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _currentNotification!.roleTarget == 'PROVIDER'
                              ? Icons.work_rounded
                              : Icons.info_rounded,
                          color: _currentNotification!.roleTarget == 'PROVIDER'
                              ? Colors.amber
                              : const Color(0xFF00C853),
                          size: 32,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _currentNotification!.title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _currentNotification!.body,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Colors.white70,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
