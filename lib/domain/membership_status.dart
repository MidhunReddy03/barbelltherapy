import '../core/utils/app_date_utils.dart';

/// Membership status, computed live and never stored (spec 5.2).
enum MembershipStatus {
  active,
  expiringSoon,
  expired,
  frozen,
  upcoming,
  noPlan;

  /// Short UI label used by pills and filters.
  String get label {
    switch (this) {
      case active:
        return 'Active';
      case expiringSoon:
        return 'Expiring soon';
      case expired:
        return 'Expired';
      case frozen:
        return 'Frozen';
      case upcoming:
        return 'Upcoming';
      case noPlan:
        return 'No plan';
    }
  }
}

/// Result of evaluating a member's latest relevant subscription.
class MembershipStatusResult {
  const MembershipStatusResult({required this.status, required this.daysLeft});

  final MembershipStatus status;

  /// Whole days from today to the end date; negative when expired,
  /// null when there is no end date (no plan).
  final int? daysLeft;
}

class MembershipStatusCalculator {
  MembershipStatusCalculator._();

  /// Evaluates the status for a member's **latest relevant subscription**
  /// (the one covering today, or the most recent non-cancelled one).
  ///
  /// The caller is responsible for picking the latest non-cancelled
  /// subscription and for checking whether an active freeze covers today.
  /// Cancelled subscriptions are ignored entirely (handled by the caller).
  static MembershipStatusResult evaluate({
    required DateTime today,
    required bool hasSubscription,
    DateTime? startDate,
    DateTime? endDate,
    bool frozenToday = false,
    int expiringSoonWindowDays = 7,
  }) {
    if (!hasSubscription || endDate == null) {
      return const MembershipStatusResult(
        status: MembershipStatus.noPlan,
        daysLeft: null,
      );
    }

    if (frozenToday) {
      return MembershipStatusResult(
        status: MembershipStatus.frozen,
        daysLeft: AppDateUtils.daysBetween(endDate, today),
      );
    }

    final start = AppDateUtils.dateOnly(startDate ?? endDate);
    if (start.isAfter(today)) {
      return MembershipStatusResult(
        status: MembershipStatus.upcoming,
        daysLeft: AppDateUtils.daysBetween(endDate, today),
      );
    }

    final daysLeft = AppDateUtils.daysBetween(endDate, today);
    if (daysLeft < 0) {
      return MembershipStatusResult(
        status: MembershipStatus.expired,
        daysLeft: daysLeft,
      );
    }
    if (daysLeft <= expiringSoonWindowDays) {
      return MembershipStatusResult(
        status: MembershipStatus.expiringSoon,
        daysLeft: daysLeft,
      );
    }
    return MembershipStatusResult(
      status: MembershipStatus.active,
      daysLeft: daysLeft,
    );
  }
}
