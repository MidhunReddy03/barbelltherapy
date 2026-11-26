import '../core/utils/app_date_utils.dart';

/// End-date calculation (spec 5.1).
///
/// A membership is valid *through* the end date (inclusive):
/// `end_date = addMonths(start_date, duration_months) - 1 day`, where
/// addMonths clamps to the last day of the target month.
class EndDateCalculator {
  EndDateCalculator._();

  /// Computes the inclusive end date of a membership period.
  ///
  /// Examples (all verified by unit tests):
  ///  - start 2026-01-31, 1 month  -> 2026-02-27 (Jan 31 clamps to Feb 28, -1d)
  ///  - start 2026-11-14, 1 month  -> 2026-12-13
  ///  - start 2026-03-01, 12 months-> 2027-02-28
  static DateTime calculate(DateTime startDate, int durationMonths) {
    assert(durationMonths > 0, 'duration must be positive');
    final endExclusive = AppDateUtils.addMonthsClamped(startDate, durationMonths);
    return endExclusive.subtract(const Duration(days: 1));
  }

  /// End date after a freeze extends the current end date by [freezeDays].
  static DateTime afterFreezeExtension(DateTime currentEndDate, int freezeDays) {
    return AppDateUtils.dateOnly(currentEndDate)
        .add(Duration(days: freezeDays));
  }

  /// End date after ending a freeze early: subtract the unused days
  /// (`plannedDays - daysActuallyUsed`) from the current end date.
  static DateTime afterFreezeEndedEarly({
    required DateTime currentEndDate,
    required int plannedFreezeDays,
    required int daysActuallyUsed,
  }) {
    final unused = plannedFreezeDays - daysActuallyUsed;
    if (unused <= 0) return AppDateUtils.dateOnly(currentEndDate);
    return AppDateUtils.dateOnly(currentEndDate)
        .subtract(Duration(days: unused));
  }

  /// Days a freeze actually ran: `freeze_end - freeze_start + 1`.
  static int freezeDaysUsed(DateTime freezeStart, DateTime freezeEndInclusive) {
    return AppDateUtils.daysBetween(freezeEndInclusive, freezeStart) + 1;
  }
}
