/// App-wide constants. All money is integer rupees; all dates are date-only
/// strings in `yyyy-MM-dd` format (see DECISIONS.md).
class AppConstants {
  AppConstants._();

  static const String appName = 'Barbell Therapy';

  /// Version shown in Settings > About (bump alongside pubspec version).
  static const String appVersion = '0.1.0';

  /// Lock the app again after this many seconds in background.
  static const int lockAfterBackgroundSeconds = 60;

  /// Member code prefix, e.g. GYM-0001.
  static const String memberCodePrefix = 'GYM';

  /// Currency and locale constants.
  static const String currencySymbol = '₹';
  static const String timeZoneLabel = 'Asia/Kolkata';

  /// Phone helpers for WhatsApp deep links.
  static const String indiaCountryCode = '91';

  /// Seed defaults for settings (section 4 of the spec).
  static const int defaultExpiringSoonWindowDays = 7;
  static const int defaultInactivityDays = 10;
  static const int defaultMaxFreezesPerSubscription = 2;
  static const int defaultMinFreezeDays = 7;
  static const int defaultAdmissionFee = 0;

  /// Default reminder day offsets (editable in Settings in Phase 4).
  static const List<int> defaultReminderOffsets = [7, 3, 1, 0, -3, -7];

  /// Missed-day lookback window for reminders (spec 5.8).
  static const int reminderLookbackDays = 3;

  /// Enrollment date cannot be more than 1 year in the past (spec 6.4).
  static const int maxStartDateLookbackDays = 365;

  /// Photo compression target (spec 6.4).
  static const int memberPhotoMaxDimension = 512;
  static const int memberPhotoQuality = 80;
}
