import 'dart:async';
import 'package:flutter/foundation.dart';
import 'api_service.dart';

class AppNotification {
  final String id;
  final String title;
  final String body;
  final String roleTarget;
  final String bookingId;
  final String type;
  final String timestamp;

  AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.roleTarget,
    required this.bookingId,
    required this.type,
    required this.timestamp,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      body: json['body'] ?? '',
      roleTarget: json['roleTarget'] ?? '',
      bookingId: json['bookingId'] ?? '',
      type: json['type'] ?? '',
      timestamp: json['timestamp'] ?? '',
    );
  }
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final _controller = StreamController<AppNotification>.broadcast();
  Stream<AppNotification> get onNotification => _controller.stream;

  Timer? _timer;
  String _currentRole = 'CUSTOMER'; // CUSTOMER or PROVIDER

  void setRole(String role) {
    _currentRole = role;
    _poll(); // Poll immediately on role switch
  }

  void startPolling() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _poll());
    _poll();
  }

  void stopPolling() {
    _timer?.cancel();
  }

  Future<void> _poll() async {
    try {
      final res = await ApiService.get('/notifications?role=$_currentRole');
      if (res is List && res.isNotEmpty) {
        for (var item in res) {
          final notif = AppNotification.fromJson(item as Map<String, dynamic>);
          _controller.add(notif);
          // Clear it from backend queue so we don't show it again
          await ApiService.post('/notifications/clear', {'id': notif.id});
        }
      }
    } catch (e) {
      debugPrint('Error polling notifications: $e');
    }
  }
}
