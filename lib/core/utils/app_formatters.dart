import 'package:intl/intl.dart';

import 'app_date_utils.dart';

/// Money and date display formatting. All amounts are integer rupees.
class AppFormatters {
  AppFormatters._();

  static final NumberFormat _rupee = NumberFormat.decimalPattern('en_IN');

  /// `₹1,250` (Indian digit grouping, no decimals).
  static String money(int rupees) => '₹${_rupee.format(rupees)}';

  /// Signed display for dues, e.g. `₹500 due`.
  static String moneyDue(int rupees) => '${money(rupees)} due';

  /// `13 Dec 2026`.
  static String date(DateTime d) => DateFormat('d MMM yyyy').format(d);

  /// `13 Dec`.
  static String dateShort(DateTime d) => DateFormat('d MMM').format(d);

  /// `13 Nov, 6:42 AM` for check-in timestamps.
  static String dateTime(DateTime d) =>
      DateFormat('d MMM, h:mm a').format(d);

  /// `6:42 AM`.
  static String time(DateTime d) => DateFormat('h:mm a').format(d);

  /// `17 Nov` (day + short month).
  static String dayMonth(DateTime d) => DateFormat('d MMM').format(d);

  /// "Ends 13 Dec" / "Expired 3 days ago" / "Ends today" / "Starts 5 Jan".
  static String endsLabel({
    required DateTime today,
    required DateTime startDate,
    required DateTime? endDate,
  }) {
    if (endDate == null) return 'No plan';
    if (AppDateUtils.dateOnly(startDate).isAfter(today)) {
      return 'Starts ${dateShort(startDate)}';
    }
    final daysLeft = AppDateUtils.daysBetween(endDate, today);
    if (daysLeft == 0) return 'Ends today';
    if (daysLeft > 0) return 'Ends ${dateShort(endDate)}';
    final ago = -daysLeft;
    return ago == 1 ? 'Expired 1 day ago' : 'Expired $ago days ago';
  }

  /// Human label for a days-left value: `in 7 days`, `today`, `3 days ago`.
  static String relativeDays(int daysLeft) {
    if (daysLeft == 0) return 'today';
    if (daysLeft == 1) return 'tomorrow';
    if (daysLeft > 0) return 'in $daysLeft days';
    final ago = -daysLeft;
    return ago == 1 ? '1 day ago' : '$ago days ago';
  }
}
