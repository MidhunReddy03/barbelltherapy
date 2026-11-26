import 'package:flutter_test/flutter_test.dart';
import 'package:gymdesk/core/utils/app_date_utils.dart';
import 'package:gymdesk/domain/membership_status.dart';

void main() {
  final today = AppDateUtils.today();

  MembershipStatusResult eval({
    required int daysLeft,
    bool frozenToday = false,
    bool upcoming = false,
    int window = 7,
  }) {
    final start = upcoming
        ? today.add(const Duration(days: 5))
        : today.subtract(const Duration(days: 30));
    final end = today.add(Duration(days: daysLeft));
    return MembershipStatusCalculator.evaluate(
      today: today,
      hasSubscription: true,
      startDate: start,
      endDate: end,
      frozenToday: frozenToday,
      expiringSoonWindowDays: window,
    );
  }

  group('MembershipStatusCalculator', () {
    test('no subscription -> noPlan', () {
      final r = MembershipStatusCalculator.evaluate(
        today: today,
        hasSubscription: false,
      );
      expect(r.status, MembershipStatus.noPlan);
      expect(r.daysLeft, isNull);
    });

    test('frozen overrides everything', () {
      expect(eval(daysLeft: 40, frozenToday: true).status,
          MembershipStatus.frozen);
      expect(eval(daysLeft: -5, frozenToday: true).status,
          MembershipStatus.frozen);
    });

    test('upcoming when start date is in the future', () {
      expect(eval(daysLeft: 35, upcoming: true).status,
          MembershipStatus.upcoming);
    });

    test('active when more than the window remains', () {
      // days_left = 8 is just outside the default 7-day window.
      expect(eval(daysLeft: 8).status, MembershipStatus.active);
      expect(eval(daysLeft: 30).status, MembershipStatus.active);
    });

    test('expiring soon on the 0..7 boundary', () {
      expect(eval(daysLeft: 7).status, MembershipStatus.expiringSoon);
      expect(eval(daysLeft: 3).status, MembershipStatus.expiringSoon);
      // days_left = 0: membership is valid *through* the end date.
      expect(eval(daysLeft: 0).status, MembershipStatus.expiringSoon);
    });

    test('custom window is respected', () {
      expect(eval(daysLeft: 10, window: 14).status,
          MembershipStatus.expiringSoon);
      expect(eval(daysLeft: 15, window: 14).status, MembershipStatus.active);
    });

    test('expired when today is past the end date', () {
      expect(eval(daysLeft: -1).status, MembershipStatus.expired);
      expect(eval(daysLeft: -30).status, MembershipStatus.expired);
    });

    test('daysLeft is returned for display', () {
      expect(eval(daysLeft: 3).daysLeft, 3);
      expect(eval(daysLeft: -2).daysLeft, -2);
    });
  });
}
