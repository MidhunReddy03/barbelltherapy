import 'package:drift/drift.dart';

import '../../core/utils/app_date_utils.dart';
import '../database.dart';
import '../../domain/enums.dart';
import 'members_repository.dart';

/// A payment row with its mode/void info, for the profile payments list.
class ProfilePayment {
  const ProfilePayment({
    required this.id,
    required this.amount,
    required this.mode,
    required this.paidOn,
    this.note,
    required this.voided,
    this.voidReason,
  });

  final int id;
  final int amount;
  final PaymentMode mode;
  final String paidOn;
  final String? note;
  final bool voided;
  final String? voidReason;
}

/// One past subscription with its add-ons, for the profile history section.
class HistorySubscription {
  const HistorySubscription({
    required this.id,
    required this.planName,
    required this.planPrice,
    required this.startDate,
    required this.endDate,
    required this.totalAmount,
    required this.paid,
    required this.cancelled,
    required this.addons,
  });

  final int id;
  final String planName;
  final int planPrice;
  final String startDate;
  final String endDate;
  final int totalAmount;
  final int paid;
  final bool cancelled;
  final List<String> addons;
}

/// Attendance summary for the profile attendance section.
class AttendanceSummary {
  const AttendanceSummary({
    required this.last90Count,
    required this.totalCount,
    this.lastVisit,
    required this.recentDates,
  });

  final int last90Count;
  final int totalCount;
  final DateTime? lastVisit;

  /// `yyyy-MM-dd` keys of check-in days within the last 90 days, ascending.
  final List<String> recentDates;
}

/// Full member + subscription detail for the profile screen.
class MemberProfile {
  const MemberProfile({
    required this.member,
    required this.subscriptionId,
    this.planName,
    this.planPrice,
    this.startDate,
    this.endDate,
    this.originalEndDate,
    this.totalAmount,
    this.admissionFee,
    this.discountType,
    this.discountValue,
    this.addons = const [],
    this.payments = const [],
    this.history = const [],
    this.attendance,
  });

  final MemberListRow member;
  final int? subscriptionId;

  // Current subscription (null = no plan)
  final String? planName;
  final int? planPrice;
  final String? startDate;
  final String? endDate;
  final String? originalEndDate;
  final int? totalAmount;
  final int? admissionFee;
  final DiscountType? discountType;
  final int? discountValue;
  final List<String> addons;
  final List<ProfilePayment> payments;
  final List<HistorySubscription> history;
  final AttendanceSummary? attendance;

  int get paid =>
      payments.where((p) => !p.voided).fold(0, (s, p) => s + p.amount);

  int get due => totalAmount == null ? 0 : (totalAmount! - paid < 0 ? 0 : totalAmount! - paid);
}

class MemberProfileRepository {
  MemberProfileRepository(this._db);

  final AppDatabase _db;

  Future<MemberProfile> load(int memberId) async {
    final today = AppDateUtils.toStorage(AppDateUtils.today());

    final memberRows = await _db.customSelect(
      '''
      WITH latest AS (
        SELECT id, member_id, plan_name_snapshot, plan_price_snapshot, start_date,
               end_date, original_end_date, total_amount, admission_fee,
               discount_type, discount_value, status_override,
               ROW_NUMBER() OVER (PARTITION BY member_id ORDER BY id DESC) AS rn
        FROM subscriptions
        WHERE status_override IS NULL
      )
      SELECT m.member_code, m.name, m.phone, m.photo_path, m.joined_on,
             m.age, m.gender, m.notes, m.is_archived,
             l.id AS sub_id, l.plan_name_snapshot AS plan_name,
             l.plan_price_snapshot AS plan_price, l.start_date AS sub_start,
             l.end_date AS sub_end, l.original_end_date AS sub_orig_end,
             l.total_amount AS sub_total, l.admission_fee AS sub_admission,
             l.discount_type AS sub_discount_type,
             l.discount_value AS sub_discount_value
      FROM members m
      LEFT JOIN latest l ON l.member_id = m.id AND l.rn = 1
      WHERE m.id = ?
      ''',
      variables: [Variable.withInt(memberId)],
      readsFrom: {_db.members, _db.subscriptions},
    ).getSingle();

    final subId = memberRows.readNullable<int>('sub_id');

    // Add-on snapshots of the current subscription.
    final addons = <String>[];
    if (subId != null) {
      final addonRows = await (_db.select(_db.subscriptionAddons)
            ..where((sa) => sa.subscriptionId.equals(subId)))
          .get();
      addons.addAll(addonRows.map((a) => a.nameSnapshot));
    }

    // Payments across ALL subscriptions of this member (profile shows all).
    final paymentRows = await (_db.select(_db.payments)
          ..where((p) => p.memberId.equals(memberId))
          ..orderBy([
            (p) => OrderingTerm.desc(p.paidOn),
            (p) => OrderingTerm.desc(p.id),
          ]))
        .get();
    final payments = paymentRows
        .map((p) => ProfilePayment(
              id: p.id,
              amount: p.amount,
              mode: p.mode,
              paidOn: p.paidOn,
              note: p.note,
              voided: p.voided,
              voidReason: p.voidReason,
            ))
        .toList();

    // History: every subscription (including cancelled), newest first, with
    // paid sums and add-on names.
    final historyRows = await _db.customSelect(
      '''
      SELECT s.id, s.plan_name_snapshot, s.plan_price_snapshot, s.start_date,
             s.end_date, s.total_amount, s.status_override,
             COALESCE((SELECT SUM(amount) FROM payments p
                       WHERE p.subscription_id = s.id AND p.voided = 0), 0)
               AS paid
      FROM subscriptions s
      WHERE s.member_id = ?
      ORDER BY s.id DESC
      ''',
      variables: [Variable.withInt(memberId)],
      readsFrom: {_db.subscriptions, _db.payments},
    ).get();

    final history = <HistorySubscription>[];
    for (final row in historyRows) {
      final sid = row.read<int>('id');
      final addonRows = await (_db.select(_db.subscriptionAddons)
            ..where((sa) => sa.subscriptionId.equals(sid)))
          .get();
      history.add(HistorySubscription(
        id: sid,
        planName: row.read<String>('plan_name_snapshot'),
        planPrice: row.read<int>('plan_price_snapshot'),
        startDate: row.read<String>('start_date'),
        endDate: row.read<String>('end_date'),
        totalAmount: row.read<int>('total_amount'),
        paid: row.read<int>('paid'),
        cancelled: row.readNullable<String>('status_override') != null,
        addons: addonRows.map((a) => a.nameSnapshot).toList(),
      ));
    }

    // Attendance: last 90 days + lifetime totals.
    final since = AppDateUtils.toStorage(
      AppDateUtils.today().subtract(const Duration(days: 90)),
    );
    final checkinRows = await (_db.select(_db.checkins)
          ..where((c) => c.memberId.equals(memberId))
          ..orderBy([(c) => OrderingTerm.desc(c.checkedInAt)]))
        .get();
    final recentDates = checkinRows
        .where((c) =>
            AppDateUtils.toStorage(c.checkedInAt).compareTo(since) >= 0)
        .map((c) => AppDateUtils.toStorage(c.checkedInAt))
        .toSet()
        .toList()
      ..sort();

    final attendance = AttendanceSummary(
      last90Count: recentDates.length,
      totalCount: checkinRows.length,
      lastVisit: checkinRows.isEmpty ? null : checkinRows.first.checkedInAt,
      recentDates: recentDates,
    );

    // Frozen-today check for the status pill.
    var frozenToday = false;
    if (subId != null) {
      frozenToday = (await _db.customSelect(
        '''
        SELECT COUNT(*) AS cnt FROM freezes
        WHERE subscription_id = ? AND freeze_start <= ? AND freeze_end >= ?
        ''',
        variables: [
          Variable.withInt(subId),
          Variable.withString(today),
          Variable.withString(today),
        ],
        readsFrom: {_db.freezes},
      ).getSingle())
          .read<int>('cnt') >
          0;
    }

    final memberRow = MemberListRow(
      id: memberId,
      memberCode: memberRows.read<String>('member_code'),
      name: memberRows.read<String>('name'),
      phone: memberRows.read<String>('phone'),
      photoPath: memberRows.readNullable<String>('photo_path'),
      joinedOn: memberRows.readNullable<String>('joined_on'),
      age: memberRows.readNullable<int>('age'),
      gender: memberRows.readNullable<String>('gender'),
      notes: memberRows.readNullable<String>('notes'),
      planName: memberRows.readNullable<String>('plan_name'),
      startDate: memberRows.readNullable<String>('sub_start'),
      endDate: memberRows.readNullable<String>('sub_end'),
      frozenToday: frozenToday,
    );

    return MemberProfile(
      member: memberRow,
      subscriptionId: subId,
      planName: memberRows.readNullable<String>('plan_name'),
      planPrice: memberRows.readNullable<int>('plan_price'),
      startDate: memberRows.readNullable<String>('sub_start'),
      endDate: memberRows.readNullable<String>('sub_end'),
      originalEndDate: memberRows.readNullable<String>('sub_orig_end'),
      totalAmount: memberRows.readNullable<int>('sub_total'),
      admissionFee: memberRows.readNullable<int>('sub_admission'),
      discountType: memberRows.readNullable<String>('sub_discount_type') == null
          ? null
          : DiscountType.values.firstWhere(
              (d) => d.name == memberRows.read<String>('sub_discount_type'),
            ),
      discountValue: memberRows.readNullable<int>('sub_discount_value'),
      addons: addons,
      payments: payments,
      history: history,
      attendance: attendance,
    );
  }

  /// Edits member details (spec 6.5).
  Future<void> updateMember({
    required int id,
    required String name,
    required String phone,
    int? age,
    String? gender,
    String? notes,
    String? photoPath,
  }) {
    return (_db.update(_db.members)..where((m) => m.id.equals(id))).write(
      MembersCompanion(
        name: Value(name.trim()),
        phone: Value(phone),
        age: Value(age),
        gender: Value(gender),
        notes: Value(notes),
        photoPath: Value(photoPath),
      ),
    );
  }

  /// Archive member (hidden from lists; history preserved).
  Future<void> setArchived(int id, bool archived) {
    return (_db.update(_db.members)..where((m) => m.id.equals(id)))
        .write(MembersCompanion(isArchived: Value(archived)));
  }
}
