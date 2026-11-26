import 'package:drift/drift.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/app_date_utils.dart';
import '../database.dart';
import '../../domain/enums.dart';
import '../../domain/reminder_engine.dart';
import 'settings_repository.dart';

/// A candidate row for today's reminders: latest non-cancelled subscription
/// joined with member info.
class ReminderCandidate {
  const ReminderCandidate({
    required this.memberId,
    required this.memberCode,
    required this.name,
    required this.phone,
    this.photoPath,
    required this.subscriptionId,
    required this.planName,
    required this.startDate,
    required this.endDate,
    required this.due,
    required this.sentTypes,
  });

  final int memberId;
  final String memberCode;
  final String name;
  final String phone;
  final String? photoPath;
  final int subscriptionId;
  final String planName;
  final String startDate;
  final String endDate;
  final int due;
  final Set<MessageType> sentTypes;
}

/// A reminder ready to show for a member, plus the member context.
class PendingReminder {
  PendingReminder({
    required this.candidate,
    required this.selection,
  });

  final ReminderCandidate candidate;
  final ReminderSelection selection;

  int get daysLeft => AppDateUtils.daysBetween(
        AppDateUtils.parse(candidate.endDate) ?? AppDateUtils.today(),
        AppDateUtils.today(),
      );
}

/// Builds today's reminder list from the DB + the pure reminder engine.
class RemindersRepository {
  RemindersRepository(this._db, this._settings);

  final AppDatabase _db;
  final SettingsRepository _settings;

  Future<List<PendingReminder>> todayReminders() async {
    final today = AppDateUtils.today();
    final todayStr = AppDateUtils.toStorage(today);
    // Widest net: furthest past offset (7 days after expiry) + lookback, so
    // the pure engine can pick exact or missed rules from the candidate set.
    final fromStr = AppDateUtils.toStorage(today.subtract(
        const Duration(days: 7 + AppConstants.reminderLookbackDays)));
    final toStr = AppDateUtils.toStorage(
      today.add(const Duration(
          days: 7 + AppConstants.reminderLookbackDays)),
    );

    final sql = '''
      WITH latest AS (
        SELECT id, member_id, plan_name_snapshot, start_date, end_date,
               ROW_NUMBER() OVER (PARTITION BY member_id ORDER BY id DESC) AS rn
        FROM subscriptions
        WHERE status_override IS NULL
      )
      SELECT m.id AS member_id, m.member_code, m.name, m.phone, m.photo_path,
             l.id AS sub_id, l.plan_name_snapshot AS plan_name,
             l.start_date AS sub_start, l.end_date AS sub_end,
             l.total_amount - COALESCE(p.paid, 0) AS due,
             CASE WHEN EXISTS (
               SELECT 1 FROM freezes f
               WHERE f.subscription_id = l.id
                 AND f.freeze_start <= ? AND f.freeze_end >= ?
             ) THEN 1 ELSE 0 END AS frozen_today
      FROM members m
      JOIN latest l ON l.member_id = m.id AND l.rn = 1
      LEFT JOIN (
        SELECT subscription_id, SUM(amount) AS paid
        FROM payments WHERE voided = 0
        GROUP BY subscription_id
      ) p ON p.subscription_id = l.id
      WHERE m.is_archived = 0
        AND l.start_date <= ?
        AND l.end_date >= ? AND l.end_date <= ?
        AND (SELECT COUNT(*) FROM message_log ml
             WHERE ml.subscription_id = l.id
               AND ml.type IN ('expiry_7','expiry_3','expiry_1','expiry_0',
                               'expired_3','expired_7')) < 6
    ''';

    final rows = await _db.customSelect(
      sql,
      variables: [
        Variable.withString(todayStr),
        Variable.withString(todayStr),
        Variable.withString(todayStr),
        Variable.withString(fromStr),
        Variable.withString(toStr),
      ],
      readsFrom: {
        _db.members,
        _db.subscriptions,
        _db.payments,
        _db.freezes,
        _db.messageLog,
      },
    ).get();

    // Load all expiry-type logs for these subscriptions in one query.
    final subIds = rows.map((r) => r.read<int>('sub_id')).toSet();
    final sentBySub = <int, Set<MessageType>>{};
    if (subIds.isNotEmpty) {
      final logRows = await (_db.select(_db.messageLog)
            ..where((ml) => ml.subscriptionId.isIn(subIds)))
          .get();
      for (final log in logRows) {
        if (log.subscriptionId == null) continue;
        sentBySub
            .putIfAbsent(log.subscriptionId!, () => {})
            .add(log.type);
      }
    }

    final offsets = (await _settings.reminderOffsets())
        .where((c) => c.enabled)
        .map((c) => c.offset)
        .toList();

    final results = <PendingReminder>[];
    for (final row in rows) {
      final frozen = (row.readNullable<int>('frozen_today') ?? 0) == 1;
      final endDate =
          AppDateUtils.parse(row.read<String>('sub_end')) ?? today;
      final startDate =
          AppDateUtils.parse(row.read<String>('sub_start')) ?? today;
      final daysLeft = AppDateUtils.daysBetween(endDate, today);

      final selection = ReminderEngine.select(
        daysLeft: daysLeft,
        frozen: frozen,
        upcoming: startDate.isAfter(today),
        alreadyRenewed: false,
        sentTypes: sentBySub[row.read<int>('sub_id')] ?? {},
        enabledOffsets: offsets,
      );
      if (selection == null) continue;

      results.add(PendingReminder(
        candidate: ReminderCandidate(
          memberId: row.read<int>('member_id'),
          memberCode: row.read<String>('member_code'),
          name: row.read<String>('name'),
          phone: row.read<String>('phone'),
          photoPath: row.readNullable<String>('photo_path'),
          subscriptionId: row.read<int>('sub_id'),
          planName: row.read<String>('plan_name'),
          startDate: row.read<String>('sub_start'),
          endDate: row.read<String>('sub_end'),
          due: row.readNullable<int>('due') ?? 0,
          sentTypes: sentBySub[row.read<int>('sub_id')] ?? {},
        ),
        selection: selection,
      ));
    }

    // Only one reminder per member, most relevant first (soonest expiry).
    results.sort((a, b) => a.daysLeft.compareTo(b.daysLeft));
    return results;
  }

  /// Records a sent reminder in message_log.
  Future<void> markSent({
    required int memberId,
    int? subscriptionId,
    required MessageType type,
    required int templateId,
    MessageChannel channel = MessageChannel.whatsapp,
  }) async {
    await _db.into(_db.messageLog).insert(
          MessageLogCompanion.insert(
            memberId: Value(memberId),
            type: type,
            subscriptionId: Value(subscriptionId),
            sentAt: DateTime.now(),
            templateId: Value(templateId),
            channel: Value(channel.name),
          ),
        );
  }

  /// Resolves the template body for a message type and language.
  Future<(int, String)?> templateFor(
      MessageType type, LanguageCode language) async {
    final row = await (_db.select(_db.templates)
          ..where((t) =>
              t.key.equals(type.name) &
              t.language.equals(language == LanguageCode.te ? 'te' : 'en')))
        .getSingleOrNull();
    if (row == null) return null;
    return (row.id, row.body);
  }
}
