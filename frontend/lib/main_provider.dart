import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'screens/provider/provider_home.dart';
import 'services/notification_service.dart';
import 'services/booking_events.dart';

void main() {
  runApp(const HaazirProviderApp());
}

class HaazirProviderApp extends StatelessWidget {
  const HaazirProviderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Haazir — Provider',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        primaryColor: const Color(0xFF3A9010),
        scaffoldBackgroundColor: const Color(0xFFF7FAF5),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3A9010),
          brightness: Brightness.light,
          primary: const Color(0xFF3A9010),
          secondary: const Color(0xFF163300),
          surface: Colors.white,
          error: const Color(0xFFB00020),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF163300),
          foregroundColor: Colors.white,
          elevation: 0,
          iconTheme: IconThemeData(color: Colors.white),
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Colors.white,
          selectedItemColor: Color(0xFF3A9010),
          unselectedItemColor: Color(0xFF767773),
        ),
        dividerColor: const Color(0xFFE8EDE6),
        textTheme: GoogleFonts.outfitTextTheme(ThemeData.light().textTheme),
        useMaterial3: true,
      ),
      builder: (context, child) {
        return NotificationOverlay(child: child!);
      },
      home: const ProviderHome(),
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
    NotificationService().setRole('PROVIDER');
    NotificationService().startPolling();
    NotificationService().onNotification.listen((notif) {
      // Refresh jobs list whenever any notification arrives
      BookingEvents.refresh();
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
                onTap: () => setState(() => _currentNotification = null),
                child: TweenAnimationBuilder<double>(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                  tween: Tween(begin: -100, end: 0),
                  builder: (context, value, child) => Transform.translate(
                    offset: Offset(0, value),
                    child: child,
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFF3A9010).withValues(alpha: 0.5),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.work_rounded,
                            color: Color(0xFF3A9010), size: 32),
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
                                  color: Color(0xFF21231D),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _currentNotification!.body,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF3E3F3B),
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
