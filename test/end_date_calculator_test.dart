import 'package:flutter_test/flutter_test.dart';
import 'package:gymdesk/core/utils/app_date_utils.dart';
import 'package:gymdesk/domain/end_date_calculator.dart';

void main() {
  group('AppDateUtils.addMonthsClamped', () {
    test('clamps Jan 31 + 1 month to Feb 28 (non-leap year)', () {
      final result = AppDateUtils.addMonthsClamped(DateTime(2026, 1, 31), 1);
      expect(result, DateTime(2026, 2, 28));
    });

    test('clamps Jan 31 + 1 month to Feb 29 in a leap year', () {
      final result = AppDateUtils.addMonthsClamped(DateTime(2028, 1, 31), 1);
      expect(result, DateTime(2028, 2, 29));
    });

    test('adds months across year boundaries', () {
      expect(
        AppDateUtils.addMonthsClamped(DateTime(2026, 11, 14), 2),
        DateTime(2027, 1, 14),
      );
    });

    test('same month is a no-op', () {
      expect(
        AppDateUtils.addMonthsClamped(DateTime(2026, 3, 15), 0),
        DateTime(2026, 3, 15),
      );
    });

    test('handles negative months', () {
      expect(
        AppDateUtils.addMonthsClamped(DateTime(2026, 3, 31), -1),
        DateTime(2026, 2, 28),
      );
    });
  });

  group('EndDateCalculator.calculate', () {
    test('spec case: start 2026-01-31, 1 month -> end 2026-02-27', () {
      final end = EndDateCalculator.calculate(DateTime(2026, 1, 31), 1);
      expect(end, DateTime(2026, 2, 27));
    });

    test('spec case: start 2026-11-14 monthly -> end 2026-12-13', () {
      final end = EndDateCalculator.calculate(DateTime(2026, 11, 14), 1);
      expect(end, DateTime(2026, 12, 13));
    });

    test('spec case: start 2026-03-01 yearly -> end 2027-02-28', () {
      final end = EndDateCalculator.calculate(DateTime(2026, 3, 1), 12);
      expect(end, DateTime(2027, 2, 28));
    });

    test('leap-year yearly plan: 2027-03-01 yearly -> 2028-02-29', () {
      final end = EndDateCalculator.calculate(DateTime(2027, 3, 1), 12);
      expect(end, DateTime(2028, 2, 29));
    });

    test('quarterly: start 2026-01-15 -> end 2026-04-14', () {
      final end = EndDateCalculator.calculate(DateTime(2026, 1, 15), 3);
      expect(end, DateTime(2026, 4, 14));
    });

    test('half-yearly across a leap February', () {
      final end = EndDateCalculator.calculate(DateTime(2027, 9, 30), 6);
      expect(end, DateTime(2028, 3, 29));
    });
  });

  group('Freeze date shifting', () {
    test('freeze extends the end date by exact days', () {
      final current = DateTime(2026, 12, 13);
      final extended =
          EndDateCalculator.afterFreezeExtension(current, 15);
      expect(extended, DateTime(2026, 12, 28));
    });

    test('freeze days used counts inclusive days', () {
      final used = EndDateCalculator.freezeDaysUsed(
        DateTime(2026, 11, 1),
        DateTime(2026, 11, 10),
      );
      expect(used, 10);
    });

    test('ending early subtracts unused days', () {
      // Planned 15 days, owner ended it after 6 days -> 9 unused.
      final current = DateTime(2026, 12, 28);
      final reverted = EndDateCalculator.afterFreezeEndedEarly(
        currentEndDate: current,
        plannedFreezeDays: 15,
        daysActuallyUsed: 6,
      );
      expect(reverted, DateTime(2026, 12, 19));
    });

    test('ending early after using all days changes nothing', () {
      final current = DateTime(2026, 12, 28);
      final reverted = EndDateCalculator.afterFreezeEndedEarly(
        currentEndDate: current,
        plannedFreezeDays: 15,
        daysActuallyUsed: 15,
      );
      expect(reverted, current);
    });
  });

  group('AppDateUtils', () {
    test('storage round-trip', () {
      final d = DateTime(2026, 11, 14);
      expect(AppDateUtils.parse(AppDateUtils.toStorage(d)), d);
    });

    test('parse handles malformed input', () {
      expect(AppDateUtils.parse('garbage'), isNull);
      expect(AppDateUtils.parse(''), isNull);
      expect(AppDateUtils.parse(null), isNull);
    });

    test('daysBetween is inclusive-safe', () {
      expect(
        AppDateUtils.daysBetween(
          DateTime(2026, 11, 14),
          DateTime(2026, 11, 14),
        ),
        0,
      );
      expect(
        AppDateUtils.daysBetween(
          DateTime(2026, 11, 21),
          DateTime(2026, 11, 14),
        ),
        7,
      );
      expect(
        AppDateUtils.daysBetween(
          DateTime(2026, 11, 14),
          DateTime(2026, 11, 21),
        ),
        -7,
      );
    });

    test('monthKey zero-pads the month', () {
      expect(AppDateUtils.monthKey(DateTime(2026, 3, 5)), '2026-03');
    });
  });
}
