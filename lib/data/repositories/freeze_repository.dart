import 'package:drift/drift.dart';

import '../../core/utils/app_date_utils.dart';
import '../database.dart';
import 'settings_repository.dart';

/// One freeze record for the profile history.
class FreezeRecord {
  const FreezeRecord({
    required this.id,
    required this.subscriptionId,
    required this.freezeStart,
    required this.freezeEnd,
    required this.days,
    this.reason,
    this.endedEarlyOn,
    required this.activeToday,
  });

  final int id;
  final int subscriptionId;
  final String freezeStart;
  final String freezeEnd;
  final int days;
  final String? reason;
  final String? endedEarlyOn;
  final bool activeToday;
}

/// Freeze creation with full validation and the end-early recalculation
/// (spec 5.4). Date shifting runs inside a transaction.
class FreezeRepository {
  FreezeRepository(this._db, this._settings);

  final AppDatabase _db;
  final SettingsRepository _settings;

  /// Validates a freeze request. Returns an error message or null when valid.
  Future<String?> validate({
    required int subscriptionId,
    required DateTime start,
    required DateTime end,
  }) async {
    final today = AppDateUtils.today();
    if (AppDateUtils.dateOnly(end)
        .isBefore(AppDateUtils.dateOnly(start))) {
      return 'Freeze end must be on or after the start';
    }

    final sub = await (_db.select(_db.subscriptions)
          ..where((s) => s.id.equals(subscriptionId)))
        .getSingleOrNull();
    if (sub == null) return 'Subscription not found';
    if (sub.statusOverride != null) return 'This subscription is cancelled';

    final subEnd = AppDateUtils.parse(sub.endDate)!;
    if (subEnd.isBefore(today)) return 'Expired memberships cannot be frozen';

    if (AppDateUtils.dateOnly(start).isBefore(today)) {
      return 'Freeze start cannot be in the past';
    }

    final plannedDays =
        AppDateUtils.daysBetween(end, start) + 1;
    final minDays = await _settings.minFreezeDays();
    if (plannedDays < minDays) {
      return 'Minimum freeze length is $minDays days';
    }

    final existing = await (_db.select(_db.freezes)
          ..where((f) => f.subscriptionId.equals(subscriptionId)))
        .get();
    final activeOnes =
        existing.where((f) => f.endedEarlyOn == null).toList();
    final maxFreezes = await _settings.maxFreezesPerSubscription();
    if (activeOnes.length >= maxFreezes) {
      return 'Maximum $maxFreezes freezes per subscription';
    }
    // Overlap check: existing freeze windows (planned or used) must not
    // intersect [start, end].
    for (final f in existing) {
      final overlap =
          AppDateUtils.parse(f.freezeStart)! .isBefore(end) &&
              AppDateUtils.parse(f.freezeEnd)!.isAfter(start);
      if (overlap) return 'Overlaps an existing freeze';
    }
    return null;
  }

  /// Creates the freeze and shifts the subscription end date by the planned
  /// days. All-or-nothing. Returns the freeze id.
  Future<int> create({
    required int subscriptionId,
    required int memberId,
    required DateTime start,
    required DateTime end,
    String? reason,
    bool skipValidation = false,
  }) async {
    if (!skipValidation) {
      final error = await validate(
        subscriptionId: subscriptionId,
        start: start,
        end: end,
      );
      if (error != null) throw StateError(error);
    }

    final plannedDays = AppDateUtils.daysBetween(end, start) + 1;
    final now = DateTime.now();

    return _db.transaction(() async {
      final freezeId = await _db.into(_db.freezes).insert(
            FreezesCompanion.insert(
              subscriptionId: subscriptionId,
              memberId: memberId,
              freezeStart: AppDateUtils.toStorage(start),
              freezeEnd: AppDateUtils.toStorage(end),
              days: plannedDays,
              reason: Value(reason),
              createdAt: now,
            ),
          );

      final sub = await (_db.select(_db.subscriptions)
            ..where((s) => s.id.equals(subscriptionId)))
          .getSingle();
      final newEnd = AppDateUtils.toStorage(
        AppDateUtils.dateOnly(AppDateUtils.parse(sub.endDate)!)
            .add(Duration(days: plannedDays)),
      );
      await (_db.update(_db.subscriptions)
            ..where((s) => s.id.equals(subscriptionId)))
          .write(SubscriptionsCompanion(endDate: Value(newEnd)));

      return freezeId;
    });
  }

  /// Ends the active freeze today: days actually used are kept, unused days
  /// are subtracted from the subscription end date, and `ended_early_on` is
  /// recorded (spec 5.4). Runs in one transaction.
  Future<void> endEarly(int freezeId) async {
    final today = AppDateUtils.today();
    await _db.transaction(() async {
      final freeze = await (_db.select(_db.freezes)
            ..where((f) => f.id.equals(freezeId)))
          .getSingleOrNull();
      if (freeze == null || freeze.endedEarlyOn != null) return;

      final start = AppDateUtils.parse(freeze.freezeStart)!;
      final plannedEnd = AppDateUtils.parse(freeze.freezeEnd)!;
      final plannedDays = freeze.days;

      // Days actually frozen: every day *before* today counts (the freeze
      // ends immediately — "end freeze now" — so today itself is not
      // frozen). A freeze that has not started yet uses zero days.
      final daysUsed =
          today.isBefore(start) ? 0 : AppDateUtils.daysBetween(today, start);
      final clampedUsed = daysUsed < 0
          ? 0
          : (daysUsed > plannedDays ? plannedDays : daysUsed);
      final unused = plannedDays - clampedUsed;

      final sub = await (_db.select(_db.subscriptions)
            ..where((s) => s.id.equals(freeze.subscriptionId)))
          .getSingle();
      final currentEnd = AppDateUtils.parse(sub.endDate)!;
      final newEnd = AppDateUtils.toStorage(
        currentEnd.subtract(Duration(days: unused)),
      );
      await (_db.update(_db.subscriptions)
            ..where((s) => s.id.equals(freeze.subscriptionId)))
          .write(SubscriptionsCompanion(endDate: Value(newEnd)));

      // Keep the freeze row as history but close it so status/freeze checks
      // no longer see it as active: the last frozen day is the day before
      // the early end. A freeze that never ran is recorded with zero days
      // and a window ending the day before it was planned to start.
      final lastFrozenDay = clampedUsed == 0
          ? start.subtract(const Duration(days: 1))
          : today.subtract(const Duration(days: 1));
      await (_db.update(_db.freezes)..where((f) => f.id.equals(freezeId)))
          .write(FreezesCompanion(
        freezeEnd: Value(AppDateUtils.toStorage(
            lastFrozenDay.isBefore(plannedEnd) ? lastFrozenDay : plannedEnd)),
        days: Value(clampedUsed),
        endedEarlyOn: Value(AppDateUtils.toStorage(today)),
      ));
    });
  }

  /// The freeze covering today for a subscription, if any.
  Future<FreezeRecord?> activeFreeze(int subscriptionId) async {
    final today = AppDateUtils.toStorage(AppDateUtils.today());
    final rows = await _db.customSelect(
      '''
      SELECT id, subscription_id, freeze_start, freeze_end, days, reason,
             ended_early_on
      FROM freezes
      WHERE subscription_id = ? AND freeze_start <= ? AND freeze_end >= ?
      LIMIT 1
      ''',
      variables: [
        Variable.withInt(subscriptionId),
        Variable.withString(today),
        Variable.withString(today),
      ],
      readsFrom: {_db.freezes},
    ).get();
    if (rows.isEmpty) return null;
    return _toRecord(rows.first, activeToday: true);
  }

  /// All freezes of a member, newest first (profile history).
  Future<List<FreezeRecord>> history(int memberId) async {
    final today = AppDateUtils.toStorage(AppDateUtils.today());
    final rows = await (_db.select(_db.freezes)
          ..where((f) => f.memberId.equals(memberId))
          ..orderBy([(f) => OrderingTerm.desc(f.id)]))
        .get();
    return rows.map((f) {
      final active =
          f.freezeStart.compareTo(today) <= 0 && f.freezeEnd.compareTo(today) >= 0;
      return FreezeRecord(
        id: f.id,
        subscriptionId: f.subscriptionId,
        freezeStart: f.freezeStart,
        freezeEnd: f.freezeEnd,
        days: f.days,
        reason: f.reason,
        endedEarlyOn: f.endedEarlyOn,
        activeToday: active && f.endedEarlyOn == null,
      );
    }).toList();
  }

  FreezeRecord _toRecord(QueryRow r, {required bool activeToday}) {
    return FreezeRecord(
      id: r.read<int>('id'),
      subscriptionId: r.read<int>('subscription_id'),
      freezeStart: r.read<String>('freeze_start'),
      freezeEnd: r.read<String>('freeze_end'),
      days: r.read<int>('days'),
      reason: r.readNullable<String>('reason'),
      endedEarlyOn: r.readNullable<String>('ended_early_on'),
      activeToday: activeToday,
    );
  }
}
