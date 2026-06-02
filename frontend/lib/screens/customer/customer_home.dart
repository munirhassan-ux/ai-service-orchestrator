import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'chat_screen.dart';
import 'bookings_screen.dart';
import 'alerts_screen.dart';
import 'profile_screen.dart';
import '../provider/provider_home.dart';
import '../../services/booking_events.dart';
import '../../services/api_service.dart';

class CustomerHome extends StatefulWidget {
  const CustomerHome({super.key});
  @override
  State<CustomerHome> createState() => _CustomerHomeState();
}

class _CustomerHomeState extends State<CustomerHome> {
  int _tab = 0;
  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      CustomerLandingScreen(onSwitchToBookings: _goToBookings),
      const BookingsScreen(),
      const AlertsScreen(),
      const ProfileScreen(),
    ];
  }

  void _goToBookings() {
    BookingEvents.refresh();
    setState(() => _tab = 1);
  }

  void _onTabTap(int i) {
    BookingEvents.refresh();
    setState(() => _tab = i);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            SvgPicture.asset('assets/haazir_logo.svg', height: 28),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.person_rounded, size: 16, color: Colors.white),
                const SizedBox(width: 4),
                const Text('Customer',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white)),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const ProviderHome()),
                  ),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text('Provider',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ],
        backgroundColor: const Color(0xFF163300),
        elevation: 0,
      ),
      body: IndexedStack(index: _tab, children: _screens),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: const Color(0xFFE8EDE6))),
        ),
        child: BottomNavigationBar(
          currentIndex: _tab,
          onTap: _onTabTap,
          backgroundColor: Colors.transparent,
          selectedItemColor: const Color(0xFF3A9010),
          unselectedItemColor: const Color(0xFF767773),
          type: BottomNavigationBarType.fixed,
          elevation: 0,
          items: const [
            BottomNavigationBarItem(
                icon: Icon(Icons.chat_bubble_outline_rounded),
                activeIcon: Icon(Icons.chat_bubble_rounded),
                label: "Chat"),
            BottomNavigationBarItem(
                icon: Icon(Icons.list_alt_outlined),
                activeIcon: Icon(Icons.list_alt_rounded),
                label: "Bookings"),
            BottomNavigationBarItem(
                icon: Icon(Icons.notifications_none_rounded),
                activeIcon: Icon(Icons.notifications_rounded),
                label: "Alerts"),
            BottomNavigationBarItem(
                icon: Icon(Icons.person_outline_rounded),
                activeIcon: Icon(Icons.person_rounded),
                label: "Profile"),
          ],
        ),
      ),
    );
  }
}

class CustomerLandingScreen extends StatefulWidget {
  final VoidCallback? onSwitchToBookings;
  const CustomerLandingScreen({super.key, this.onSwitchToBookings});

  @override
  State<CustomerLandingScreen> createState() => _CustomerLandingScreenState();
}

class _CustomerLandingScreenState extends State<CustomerLandingScreen> {
  final _ctrl = TextEditingController();
  StreamSubscription<void>? _sub;

  bool _hasActive = false;
  bool _hasActiveBooking = false;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _checkState();
    _sub = BookingEvents.onRefresh.listen((_) => _checkState());
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _checkState() async {
    if (!mounted) return;
    setState(() => _checking = true);

    // Validate any cached booking ID — clear if completed/cancelled-by-customer
    final bid = ActiveSessionService.bookingId;
    if (bid != null) {
      try {
        final b = await ApiService.get('booking/$bid');
        final st = b['status'] as String? ?? '';
        if (st == 'COMPLETED' || st == 'CANCELLED_CUSTOMER') {
          ActiveSessionService.clear();
        }
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() {
      _hasActiveBooking = ActiveSessionService.bookingId != null;
      _hasActive = _hasActiveBooking || ActiveSessionService.hasActive;
      _checking = false;
    });
  }

  void _submit() {
    if (_hasActive) return;
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    _ctrl.clear();
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => ChatScreen(initialPrompt: text)))
        .then((_) {
      _checkState();
      if (ActiveSessionService.hasActive) widget.onSwitchToBookings?.call();
    });
  }

  void _resume() {
    final bookingId = ActiveSessionService.bookingId;
    final sessionId = ActiveSessionService.sessionId;
    if (bookingId != null) {
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => ChatScreen(bookingId: bookingId)))
          .then((_) => _checkState());
    } else if (sessionId != null) {
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => ChatScreen(sessionId: sessionId)))
          .then((_) => _checkState());
    }
  }

  void _abandonSession() {
    ActiveSessionService.clear();
    setState(() {
      _hasActive = false;
      _hasActiveBooking = false;
    });
  }

  void _openWithPrompt(String prompt) {
    Navigator.of(context)
        .push(MaterialPageRoute(
            builder: (_) => ChatScreen(initialPrompt: prompt)))
        .then((_) {
      _checkState();
      if (ActiveSessionService.hasActive) widget.onSwitchToBookings?.call();
    });
  }

  Widget _serviceChip(String emoji, String label, String prompt) {
    return GestureDetector(
      onTap: () => _openWithPrompt(prompt),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFE8EDE6)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(emoji, style: const TextStyle(fontSize: 15)),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(
                  color: Color(0xFF21231D),
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAF5),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF3A9010).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.auto_awesome_rounded,
                    size: 48, color: const Color(0xFF3A9010)),
              ),
              const SizedBox(height: 32),
              const Text(
                "Assalam o Alaikum!",
                style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF21231D)),
              ),
              const SizedBox(height: 8),
              const Text(
                "How can I help you today?",
                style: TextStyle(fontSize: 18, color: const Color(0xFF3E3F3B)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),

              if (_checking)
                const CircularProgressIndicator(
                    strokeWidth: 2, color: Color(0xFF3A9010))
              else if (_hasActive) ...[
                // ── Active session/booking banner ──────────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3A9010).withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: const Color(0xFF3A9010).withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Icon(Icons.chat_bubble_rounded,
                            color: Color(0xFF3A9010), size: 16),
                        const SizedBox(width: 8),
                        Text(
                          _hasActiveBooking
                              ? "Active Booking in Progress"
                              : "Ongoing Conversation",
                          style: const TextStyle(
                              color: Color(0xFF3A9010),
                              fontSize: 13,
                              fontWeight: FontWeight.bold),
                        ),
                      ]),
                      const SizedBox(height: 6),
                      Text(
                        _hasActiveBooking
                            ? "Aap ka ek booking active hai. Naya booking tab ho sakta hai jab yeh complete ho."
                            : "Aap ki ek chat chal rahi hai. Pehle woh complete karein ya abandon karein.",
                        style: const TextStyle(
                            color: Color(0xFF565955),
                            fontSize: 12,
                            height: 1.5),
                      ),
                      const SizedBox(height: 14),
                      GestureDetector(
                        onTap: _resume,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                              color: const Color(0xFF3A9010),
                              borderRadius: BorderRadius.circular(14)),
                          child: const Center(
                            child: Text("Resume Chat",
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14)),
                          ),
                        ),
                      ),
                      if (!_hasActiveBooking) ...[
                        const SizedBox(height: 10),
                        GestureDetector(
                          onTap: _abandonSession,
                          child: const Center(
                            child: Text(
                              "Abandon and start new chat",
                              style: TextStyle(
                                  color: Color(0xFF767773),
                                  fontSize: 12,
                                  decoration: TextDecoration.underline),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ] else ...[
                // ── Normal input ───────────────────────────────────────
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: const Color(0xFFE8EDE6)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 10,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _ctrl,
                          style:
                              const TextStyle(color: const Color(0xFF21231D)),
                          decoration: const InputDecoration(
                            hintText: "e.g. mujhe kal sham plumber dhund do...",
                            hintStyle:
                                TextStyle(color: const Color(0xFF767773)),
                            border: InputBorder.none,
                          ),
                          onSubmitted: (_) => _submit(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: _submit,
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: const BoxDecoration(
                              color: Color(0xFF3A9010), shape: BoxShape.circle),
                          child: const Icon(Icons.send_rounded,
                              color: Colors.white, size: 20),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  "Popular Services",
                  style: TextStyle(
                      color: Color(0xFF767773),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    _serviceChip("🔧", "Plumber", "mujhe plumber chahiye"),
                    _serviceChip("⚡", "Electrician", "mujhe electrician chahiye"),
                    _serviceChip("❄️", "AC Repair", "mujhe AC repair karwani hai"),
                    _serviceChip("🧹", "Cleaning", "ghar ki safai karwani hai"),
                    _serviceChip("🪚", "Carpenter", "mujhe carpenter chahiye"),
                    _serviceChip("🎨", "Painter", "mujhe painter chahiye"),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
