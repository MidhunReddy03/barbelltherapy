import 'package:drift/drift.dart';

import '../../core/utils/app_date_utils.dart';
import '../database.dart';

/// A member row joined with their latest subscription summary for list UIs.
class MemberListRow {
  const MemberListRow({
    required this.id,
    required this.memberCode,
    required this.name,
    required this.phone,
    this.photoPath,
    this.joinedOn,
    this.age,
    this.gender,
    this.notes,
    this.planName,
    this.startDate,
    this.endDate,
    this.due = 0,
    this.frozenToday = false,
  });

  final int id;
  final String memberCode;
  final String name;
  final String phone;
  final String? photoPath;
  final String? joinedOn;
  final int? age;
  final String? gender;
  final String? notes;
  final String? planName;
  final String? startDate;
  final String? endDate;
  final int due;
  final bool frozenToday;
}

/// Members list + search queries (spec 6.3). Uses SQL window functions so the
/// latest subscription per member is fetched in one indexed query.
class MembersRepository {
  MembersRepository(this._db);

  final AppDatabase _db;

  static const String _latestSubCte = '''
    WITH latest AS (
      SELECT id, member_id, plan_name_snapshot, start_date, end_date,
             total_amount,
             ROW_NUMBER() OVER (PARTITION BY member_id ORDER BY id DESC) AS rn
      FROM subscriptions
      WHERE status_override IS NULL
    )
  ''';

  static const String _selectColumns = '''
      SELECT m.id AS member_id, m.member_code, m.name, m.phone, m.photo_path,
             m.joined_on, m.age, m.gender, m.notes,
             l.plan_name_snapshot AS plan_name,
             l.start_date AS latest_start, l.end_date AS latest_end,
             l.total_amount - COALESCE(p.paid, 0) AS due,
             CASE WHEN EXISTS (
               SELECT 1 FROM freezes f
               WHERE f.subscription_id = l.id
                 AND f.freeze_start <= ? AND f.freeze_end >= ?
             ) THEN 1 ELSE 0 END AS frozen_today
  ''';

  static const String _joins = '''
      FROM members m
      LEFT JOIN latest l ON l.member_id = m.id AND l.rn = 1
      LEFT JOIN (
        SELECT subscription_id, SUM(amount) AS paid
        FROM payments WHERE voided = 0
        GROUP BY subscription_id
      ) p ON p.subscription_id = l.id
  ''';

  MemberListRow _rowFromQueryRow(QueryRow row) {
    return MemberListRow(
      id: row.read<int>('member_id'),
      memberCode: row.read<String>('member_code'),
      name: row.read<String>('name'),
      phone: row.read<String>('phone'),
      photoPath: row.readNullable<String>('photo_path'),
      joinedOn: row.readNullable<String>('joined_on'),
      age: row.readNullable<int>('age'),
      gender: row.readNullable<String>('gender'),
      notes: row.readNullable<String>('notes'),
      planName: row.readNullable<String>('plan_name'),
      startDate: row.readNullable<String>('latest_start'),
      endDate: row.readNullable<String>('latest_end'),
      due: row.readNullable<int>('due') ?? 0,
      frozenToday: (row.readNullable<int>('frozen_today') ?? 0) == 1,
    );
  }

  /// Watch the searchable member list (name / phone / member code).
  ///
  /// Variables, in order: today, today, search, search, search, search.
  Stream<List<MemberListRow>> watchMembers({String search = ''}) {
    final today = AppDateUtils.toStorage(AppDateUtils.today());
    final q = '%$search%';

    final sql = '''
      $_latestSubCte
      $_selectColumns
      $_joins
      WHERE m.is_archived = 0
        AND (? = '' OR m.name LIKE ? OR m.phone LIKE ? OR m.member_code LIKE ?)
      ORDER BY m.name COLLATE NOCASE
    ''';

    return _db
        .customSelect(
      sql,
      variables: [
        Variable.withString(today),
        Variable.withString(today),
        Variable.withString(q),
        Variable.withString(q),
        Variable.withString(q),
        Variable.withString(q),
      ],
      readsFrom: {
        _db.members,
        _db.subscriptions,
        _db.payments,
        _db.freezes,
      },
    )
        .watch()
        .map((rows) => rows.map(_rowFromQueryRow).toList());
  }

  /// Members search for check-in: fast phone/name/code lookup, small limit.
  ///
  /// Variables, in order: today, today, search, search, search.
  Future<List<MemberListRow>> searchForCheckIn(
    String query, {
    int limit = 10,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];
    final today = AppDateUtils.toStorage(AppDateUtils.today());
    final q = '%$trimmed%';

    final sql = '''
      $_latestSubCte
      $_selectColumns
      $_joins
      WHERE m.is_archived = 0
        AND (m.phone LIKE ? OR m.name LIKE ? OR m.member_code LIKE ?)
      ORDER BY m.name COLLATE NOCASE
      LIMIT $limit
    ''';

    final rows = await _db.customSelect(
      sql,
      variables: [
        Variable.withString(today),
        Variable.withString(today),
        Variable.withString(q),
        Variable.withString(q),
        Variable.withString(q),
      ],
      readsFrom: {_db.members, _db.subscriptions, _db.payments, _db.freezes},
    ).get();
    return rows.map(_rowFromQueryRow).toList();
  }
}
