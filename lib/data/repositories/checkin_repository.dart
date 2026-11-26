import 'package:drift/drift.dart';

import '../../core/utils/app_date_utils.dart';
import '../database.dart';
import 'members_repository.dart';

/// A member selected for check-in together with their latest subscription.
class CheckInCandidate {
  CheckInCandidate({
    required this.member,
    required this.subscriptionId,
    required this.endDate,
    required this.frozenToday,
    required this.alreadyCheckedInToday,
    required this.lastCheckInToday,
  });

  final MemberListRow member;
  final int? subscriptionId;
  final String? endDate;
  final bool frozenToday;
  final bool alreadyCheckedInToday;
  final DateTime? lastCheckInToday;
}

class TodayCheckIn {
  const TodayCheckIn({
    required this.id,
    required this.memberId,
    required this.memberName,
    required this.memberCode,
    this.photoPath,
    required this.checkedInAt,
    required this.wasExpired,
  });

  final int id;
  final int memberId;
  final String memberName;
  final String memberCode;
  final String? photoPath;
  final DateTime checkedInAt;
  final bool wasExpired;
}

/// Check-in recording and today's list (spec 6.10).
class CheckInRepository {
  CheckInRepository(this._db);

  final AppDatabase _db;

  /// Builds the check-in context for a member (latest subscription, frozen
  /// check, duplicate check-in detection).
  Future<CheckInCandidate> prepare(int memberId) async {
    final todayStr = AppDateUtils.toStorage(AppDateUtils.today());
    final row = await _db.customSelect(
      '''
      WITH latest AS (
        SELECT id, end_date,
               ROW_NUMBER() OVER (PARTITION BY member_id ORDER BY id DESC) AS rn
        FROM subscriptions
        WHERE status_override IS NULL
      )
      SELECT l.id AS sub_id, l.end_date AS sub_end,
             CASE WHEN EXISTS (
               SELECT 1 FROM freezes f
               WHERE f.subscription_id = l.id
                 AND f.freeze_start <= ? AND f.freeze_end >= ?
             ) THEN 1 ELSE 0 END AS frozen_today
      FROM members m
      LEFT JOIN latest l ON l.member_id = m.id AND l.rn = 1
      WHERE m.id = ?
      ''',
      variables: [
        Variable.withString(todayStr),
        Variable.withString(todayStr),
        Variable.withInt(memberId),
      ],
      readsFrom: {_db.members, _db.subscriptions, _db.freezes},
    ).getSingleOrNull();

    final dayStart = AppDateUtils.today();
    final dayEnd = CheckInRepository.dayEndOf(dayStart);
    final todayCheckins = await (_db.select(_db.checkins)
          ..where((c) =>
              c.memberId.equals(memberId) &
              c.checkedInAt.isBetweenValues(
                  dayStart.subtract(const Duration(milliseconds: 1)),
                  dayEnd)))
        .get();

    DateTime? lastToday;
    for (final c in todayCheckins) {
      if (lastToday == null || c.checkedInAt.isAfter(lastToday)) {
        lastToday = c.checkedInAt;
      }
    }

    final member = await _memberRow(memberId);

    return CheckInCandidate(
      member: member,
      subscriptionId: row?.readNullable<int>('sub_id'),
      endDate: row?.readNullable<String>('sub_end'),
      frozenToday: (row?.readNullable<int>('frozen_today') ?? 0) == 1,
      alreadyCheckedInToday: lastToday != null,
      lastCheckInToday: lastToday,
    );
  }

  Future<MemberListRow> _memberRow(int memberId) async {
    final todayStr = AppDateUtils.toStorage(AppDateUtils.today());
    final rows = await _db.customSelect(
      '''
      WITH latest AS (
        SELECT id, member_id, plan_name_snapshot, start_date, end_date,
               total_amount,
               ROW_NUMBER() OVER (PARTITION BY member_id ORDER BY id DESC) AS rn
        FROM subscriptions
        WHERE status_override IS NULL
      )
      SELECT m.id AS member_id, m.member_code, m.name, m.phone, m.photo_path,
             l.plan_name_snapshot AS plan_name,
             l.start_date AS latest_start, l.end_date AS latest_end,
             l.total_amount - COALESCE(p.paid, 0) AS due,
             CASE WHEN EXISTS (
               SELECT 1 FROM freezes f
               WHERE f.subscription_id = l.id
                 AND f.freeze_start <= ? AND f.freeze_end >= ?
             ) THEN 1 ELSE 0 END AS frozen_today
      FROM members m
      LEFT JOIN latest l ON l.member_id = m.id AND l.rn = 1
      LEFT JOIN (
        SELECT subscription_id, SUM(amount) AS paid
        FROM payments WHERE voided = 0
        GROUP BY subscription_id
      ) p ON p.subscription_id = l.id
      WHERE m.id = ?
      ''',
      variables: [
        Variable.withString(todayStr),
        Variable.withString(todayStr),
        Variable.withInt(memberId),
      ],
      readsFrom: {_db.members, _db.subscriptions, _db.payments, _db.freezes},
    ).get();
    if (rows.isEmpty) {
      throw StateError('Member $memberId not found');
    }
    final r = rows.first;
    return MemberListRow(
      id: r.read<int>('member_id'),
      memberCode: r.read<String>('member_code'),
      name: r.read<String>('name'),
      phone: r.read<String>('phone'),
      photoPath: r.readNullable<String>('photo_path'),
      planName: r.readNullable<String>('plan_name'),
      startDate: r.readNullable<String>('latest_start'),
      endDate: r.readNullable<String>('latest_end'),
      due: r.readNullable<int>('due') ?? 0,
      frozenToday: (r.readNullable<int>('frozen_today') ?? 0) == 1,
    );
  }

  /// Records a check-in. Returns the id of the new row.
  Future<int> recordCheckIn({
    required int memberId,
    int? subscriptionId,
    required bool wasExpired,
  }) async {
    return _db.into(_db.checkins).insert(
          CheckinsCompanion.insert(
            memberId: memberId,
            checkedInAt: DateTime.now(),
            subscriptionId: Value(subscriptionId),
            wasExpired: Value(wasExpired),
          ),
        );
  }

  /// Today's check-ins with member info for the "today" list.
  Future<List<TodayCheckIn>> todayList() async {
    final dayStart = AppDateUtils.today();
    final dayEnd = CheckInRepository.dayEndOf(dayStart);

    final query = _db.select(_db.checkins).join([
      innerJoin(_db.members, _db.members.id.equalsExp(_db.checkins.memberId)),
    ]);
    query.where(_db.checkins.checkedInAt
        .isBetweenValues(dayStart.subtract(const Duration(milliseconds: 1)), dayEnd));
    query.orderBy([OrderingTerm.desc(_db.checkins.checkedInAt)]);
    final rows = await query.get();

    return rows.map((row) {
      final c = row.readTable(_db.checkins);
      final m = row.readTable(_db.members);
      return TodayCheckIn(
        id: c.id,
        memberId: c.memberId,
        memberName: m.name,
        memberCode: m.memberCode,
        photoPath: m.photoPath,
        checkedInAt: c.checkedInAt,
        wasExpired: c.wasExpired,
      );
    }).toList();
  }

  /// Watch today's count live for the header counter.
  Stream<int> watchTodayCount() {
    final dayStart = AppDateUtils.today();
    final dayEnd = CheckInRepository.dayEndOf(dayStart);
    return (_db.select(_db.checkins)
          ..where((c) => c.checkedInAt.isBetweenValues(
              dayStart.subtract(const Duration(milliseconds: 1)), dayEnd)))
        .watch()
        .map((rows) => rows.length);
  }

  static DateTime dayEndOf(DateTime dayStart) =>
      DateTime(dayStart.year, dayStart.month, dayStart.day, 23, 59, 59, 999);
}
