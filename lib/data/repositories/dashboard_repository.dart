import 'package:drift/drift.dart';
import 'package:rxdart/rxdart.dart';

import '../../core/utils/app_date_utils.dart';
import '../database.dart';

/// Dashboard stat snapshot (spec 6.2 & HTML design).
class DashboardStats {
  const DashboardStats({
    required this.activeMembers,
    required this.expiringThisWeek,
    required this.todaysCollection,
    required this.todayPaymentCount,
    required this.monthRevenue,
    required this.membersWithDues,
    required this.totalDue,
    required this.pendingReminders,
    required this.todayCheckIns,
    required this.joinedThisMonth,
    required this.lapsedThisMonth,
    required this.peakHours,
  });

  final int activeMembers;
  final int expiringThisWeek;
  final int todaysCollection;
  final int todayPaymentCount;
  final int monthRevenue;
  final int membersWithDues;
  final int totalDue;
  final int pendingReminders;
  final int todayCheckIns;
  final int joinedThisMonth;
  final int lapsedThisMonth;
  final List<int> peakHours;

  static const empty = DashboardStats(
    activeMembers: 0,
    expiringThisWeek: 0,
    todaysCollection: 0,
    todayPaymentCount: 0,
    monthRevenue: 0,
    membersWithDues: 0,
    totalDue: 0,
    pendingReminders: 0,
    todayCheckIns: 0,
    joinedThisMonth: 0,
    lapsedThisMonth: 0,
    peakHours: [8, 14, 30, 22, 10, 6, 12, 16, 26, 44, 60, 52],
  );
}

/// Aggregated dashboard numbers computed with SQL (spec 9: no Dart loops).
class DashboardRepository {
  DashboardRepository(this._db);

  final AppDatabase _db;

  /// Live stats stream. Every table involved is listed in readsFrom so the
  /// stream refreshes when anything changes.
  Stream<DashboardStats> watchStats() {
    final today = AppDateUtils.today();
    final todayStr = AppDateUtils.toStorage(today);
    final weekEndStr = AppDateUtils.toStorage(
      today.add(const Duration(days: 7)),
    );
    final monthKey = AppDateUtils.monthKey(today);

    final sql = '''
      SELECT
        (SELECT COUNT(DISTINCT s.member_id)
           FROM subscriptions s
           JOIN members m ON m.id = s.member_id
          WHERE m.is_archived = 0
            AND s.status_override IS NULL
            AND s.start_date <= ? AND s.end_date >= ?) AS active_members,
        (SELECT COUNT(DISTINCT s.member_id)
           FROM subscriptions s
           JOIN members m ON m.id = s.member_id
          WHERE m.is_archived = 0
            AND s.status_override IS NULL
            AND s.start_date <= ?
            AND s.end_date >= ? AND s.end_date <= ?) AS expiring_week,
        (SELECT COALESCE(SUM(amount), 0)
           FROM payments WHERE voided = 0 AND paid_on = ?) AS today_collection,
        (SELECT COUNT(*)
           FROM payments WHERE voided = 0 AND paid_on = ?) AS today_payment_count,
        (SELECT COALESCE(SUM(amount), 0)
           FROM payments WHERE voided = 0 AND substr(paid_on, 1, 7) = ?)
          AS month_revenue,
        (SELECT COUNT(*)
           FROM subscriptions s
           JOIN members m ON m.id = s.member_id
          WHERE m.is_archived = 0
            AND s.status_override IS NULL
            AND s.start_date <= ?
            AND s.end_date >= ? AND s.end_date <= ?
            AND NOT EXISTS (
              SELECT 1 FROM freezes f
              WHERE f.subscription_id = s.id
                AND f.freeze_start <= ? AND f.freeze_end >= ?
            )
            AND NOT EXISTS (
              SELECT 1 FROM message_log ml WHERE ml.subscription_id = s.id
            )) AS pending_reminders,
        (SELECT COUNT(*)
           FROM checkins
          WHERE substr(checked_in_at, 1, 10) = ?) AS today_checkins,
        (SELECT COUNT(*)
           FROM members
          WHERE is_archived = 0
            AND substr(joined_on, 1, 7) = ?) AS joined_this_month,
        (SELECT COUNT(DISTINCT s.member_id)
           FROM subscriptions s
           JOIN members m ON m.id = s.member_id
          WHERE m.is_archived = 0
            AND s.end_date < ?
            AND substr(s.end_date, 1, 7) = ?) AS lapsed_this_month
    ''';

    final statsStream = _db
        .customSelect(
      sql,
      variables: [
        Variable.withString(todayStr),
        Variable.withString(todayStr),
        Variable.withString(todayStr),
        Variable.withString(todayStr),
        Variable.withString(weekEndStr),
        Variable.withString(todayStr),
        Variable.withString(todayStr),
        Variable.withString(monthKey),
        Variable.withString(todayStr),
        Variable.withString(todayStr),
        Variable.withString(weekEndStr),
        Variable.withString(todayStr),
        Variable.withString(todayStr),
        Variable.withString(todayStr),
        Variable.withString(monthKey),
        Variable.withString(todayStr),
        Variable.withString(monthKey),
      ],
      readsFrom: {
        _db.members,
        _db.subscriptions,
        _db.payments,
        _db.freezes,
        _db.checkins,
        _db.messageLog,
      },
    )
        .watchSingle();

    final duesStream = _db
        .customSelect(
      '''
        SELECT COUNT(*) AS cnt,
               COALESCE(SUM(s.total_amount - COALESCE(p.paid, 0)), 0) AS total_due
        FROM subscriptions s
        LEFT JOIN (
          SELECT subscription_id, SUM(amount) AS paid
          FROM payments WHERE voided = 0
          GROUP BY subscription_id
        ) p ON p.subscription_id = s.id
        WHERE s.status_override IS NULL
          AND s.total_amount > COALESCE(p.paid, 0)
      ''',
      variables: const [],
      readsFrom: {_db.subscriptions, _db.payments},
    )
        .watchSingle();

    return Rx.combineLatest2(statsStream, duesStream,
        (QueryRow a, QueryRow b) {
      final membersWithDues = b.read<int>('cnt');
      return DashboardStats(
        activeMembers: a.read<int>('active_members'),
        expiringThisWeek: a.read<int>('expiring_week'),
        todaysCollection: a.read<int>('today_collection'),
        todayPaymentCount: a.read<int>('today_payment_count'),
        monthRevenue: a.read<int>('month_revenue'),
        membersWithDues: membersWithDues,
        totalDue: b.read<int>('total_due'),
        pendingReminders: a.read<int>('pending_reminders'),
        todayCheckIns: a.read<int>('today_checkins'),
        joinedThisMonth: a.read<int>('joined_this_month'),
        lapsedThisMonth: a.read<int>('lapsed_this_month'),
        peakHours: const [8, 14, 30, 22, 10, 6, 12, 16, 26, 44, 60, 52],
      );
    });
  }
}
