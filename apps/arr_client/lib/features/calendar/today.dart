/// The device's local day, which decides what "today" is.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The device's clock; tests put their own in its place.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Local midnight of today. It changes at the next midnight, and is checked
/// again when the app resumes, as a timer does not run while it is suspended,
/// and every minute, as the device's clock may be set while the app is open.
final todayProvider = NotifierProvider.autoDispose<TodayNotifier, DateTime>(
  TodayNotifier.new,
);

class TodayNotifier extends Notifier<DateTime> {
  static const _check = Duration(minutes: 1);

  Timer? _next;

  @override
  DateTime build() {
    final lifecycle = AppLifecycleListener(onResume: _update);
    ref.onDispose(() {
      lifecycle.dispose();
      _next?.cancel();
    });
    return _read();
  }

  void _update() => state = _read();

  DateTime _read() {
    final now = ref.read(clockProvider)().toLocal();
    _next?.cancel();
    // Not 24 hours on from midnight: a day on which the clocks change is
    // shorter or longer.
    final midnight = addDays(now, 1).difference(now);
    _next = Timer(midnight < _check ? midnight : _check, _update);
    return dayOf(now);
  }
}

/// Local midnight of the day [instant] falls on in the device's time zone.
DateTime dayOf(DateTime instant) {
  final local = instant.toLocal();
  return DateTime(local.year, local.month, local.day);
}

/// The date of [day], to keep a day the user has chosen. Unlike a local
/// midnight it stays that date when the device's time zone changes.
DateTime calendarDate(DateTime day) {
  final local = day.toLocal();
  return DateTime.utc(local.year, local.month, local.day);
}

/// Local midnight of a [calendarDate], in the zone the device is in now.
DateTime localDay(DateTime date) => DateTime(date.year, date.month, date.day);

/// Local midnight [days] days after the day of [day], or before it if negative.
/// By calendar days, not by hours, so that a change of the clocks does not
/// shift it.
DateTime addDays(DateTime day, int days) {
  final local = day.toLocal();
  return DateTime(local.year, local.month, local.day + days);
}
