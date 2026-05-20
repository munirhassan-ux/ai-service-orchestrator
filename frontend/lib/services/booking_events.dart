import 'dart:async';

/// Global event bus for booking state changes.
/// Any screen that modifies a booking calls [BookingEvents.refresh].
/// BookingsScreen and JobsScreen subscribe and re-fetch their lists.
class BookingEvents {
  BookingEvents._();
  static final _ctrl = StreamController<void>.broadcast();
  static Stream<void> get onRefresh => _ctrl.stream;
  static void refresh() => _ctrl.add(null);
}
