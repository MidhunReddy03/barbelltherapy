import 'package:intl/intl.dart';

/// Date-only helpers. Dates are handled as local DateTime values at midnight
/// and stored as `yyyy-MM-dd` strings to avoid timezone bugs (spec section 4).
class AppDateUtils {
  AppDateUtils._();

  static const String storageFormat = 'yyyy-MM-dd';

  static final DateFormat _storage = DateFormat(storageFormat);

  /// Today, date-only.
  static DateTime today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  /// Strips any time component, keeping the local calendar date.
  static DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Formats for storage / SQL comparisons: `yyyy-MM-dd`.
  static String toStorage(DateTime d) => _storage.format(dateOnly(d));

  /// Parses a `yyyy-MM-dd` string; returns null when malformed/empty.
  static DateTime? parse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return _storage.parseLoose(raw);
    } on FormatException {
      return null;
    }
  }

  /// Whole-day difference: `daysBetween(end, start)` = end - start.
  /// Example: end 2026-12-13, start 2026-12-13 -> 0.
  static int daysBetween(DateTime a, DateTime b) {
    final da = dateOnly(a);
    final db = dateOnly(b);
    return da.difference(db).inDays;
  }

  /// Adds [months] calendar months to [date], clamping to the last valid day
  /// of the target month (Jan 31 + 1 month -> Feb 28/29).
  static DateTime addMonthsClamped(DateTime date, int months) {
    if (months == 0) return dateOnly(date);
    final base = dateOnly(date);
    final year = base.year + (base.month - 1 + months) ~/ 12;
    final month = (base.month - 1 + months) % 12 + 1;
    final daysInTarget = _daysInMonth(year, month);
    final day = base.day > daysInTarget ? daysInTarget : base.day;
    return DateTime(year, month, day);
  }

  static int _daysInMonth(int year, int month) {
    // DateTime(year, month + 1, 0).day gives the last day of [month].
    return DateTime(year, month + 1, 0).day;
  }

  /// First day of the month containing [date], date-only.
  static DateTime startOfMonth(DateTime date) =>
      DateTime(date.year, date.month, 1);

  /// Last day of the month containing [date], date-only.
  static DateTime endOfMonth(DateTime date) =>
      DateTime(date.year, date.month + 1, 0);

  /// `yyyy-MM` key used for monthly revenue grouping.
  static String monthKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';
}
