import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Injectable clock: returns the current UTC time. Tests override this
/// provider to simulate midnight crossings.
final clockProvider = Provider<DateTime Function()>(
    (ref) => () => DateTime.now().toUtc());

/// yyyy-mm-dd (UTC) used for daily identity and streak bookkeeping.
String formatUtcDate(DateTime utc) =>
    '${utc.year.toString().padLeft(4, '0')}-'
    '${utc.month.toString().padLeft(2, '0')}-'
    '${utc.day.toString().padLeft(2, '0')}';

DateTime parseUtcDate(String yyyyMmDd) {
  final parts = yyyyMmDd.split('-').map(int.parse).toList();
  return DateTime.utc(parts[0], parts[1], parts[2]);
}

/// Today's UTC date string for a given clock reading.
String utcToday(DateTime Function() clock) => formatUtcDate(clock());

/// The UTC date one day before [yyyyMmDd].
String utcYesterday(String yyyyMmDd) =>
    formatUtcDate(parseUtcDate(yyyyMmDd).subtract(const Duration(days: 1)));
