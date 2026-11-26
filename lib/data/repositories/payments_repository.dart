import 'package:drift/drift.dart';

import '../../core/utils/app_date_utils.dart';
import '../../domain/enums.dart';
import '../../domain/pricing_calculator.dart';
import '../database.dart';
import 'member_profile_repository.dart';

/// One row of the pending-dues list (spec 6.7).
class PendingDueRow {
  const PendingDueRow({
    required this.memberId,
    required this.memberCode,
    required this.name,
    required this.phone,
    required this.photoPath,
    required this.subscriptionId,
    required this.planName,
    required this.startDate,
    required this.endDate,
    required this.total,
    required this.paid,
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
  final int total;
  final int paid;

  int get due => PricingCalculator.due(total: total, paid: paid);
}

/// One payment of the day book (spec 6.7).
class DayBookRow {
  const DayBookRow({
    required this.id,
    required this.memberName,
    required this.memberCode,
    required this.amount,
    required this.mode,
    required this.note,
    required this.voided,
  });

  final int id;
  final String memberName;
  final String memberCode;
  final int amount;
  final PaymentMode mode;
  final String? note;
  final bool voided;
}

/// Day-book totals, one entry per payment mode (non-voided only).
class DayBookTotals {
  const DayBookTotals({required this.perMode, required this.grandTotal});

  final Map<PaymentMode, int> perMode;
  final int grandTotal;
}

/// Record / void payments, pending dues and the day book (spec 6.7).
class PaymentsRepository {
  PaymentsRepository(this._db);

  final AppDatabase _db;

  // ── Record / void ────────────────────────────────────────────────────────

  /// Records a payment against a subscription. The balance check runs inside
  /// the transaction so concurrent saves can never overpay.
  ///
  /// Throws [StateError] with a user-friendly message when the amount is
  /// invalid (caller shows it in the sheet).
  Future<int> recordPayment({
    required int subscriptionId,
    required int memberId,
    required int amount,
    required PaymentMode mode,
    required DateTime paidOn,
    String? note,
  }) async {
    if (amount <= 0) {
      throw StateError('Enter an amount greater than ₹0');
    }
    final now = DateTime.now();
    return _db.transaction(() async {
      final sub = await (_db.select(_db.subscriptions)
            ..where((s) => s.id.equals(subscriptionId)))
          .getSingleOrNull();
      if (sub == null) throw StateError('Subscription not found');
      if (sub.statusOverride != null) {
        throw StateError('This subscription is cancelled');
      }

      final paidRow = await _db.customSelect(
        'SELECT COALESCE(SUM(amount), 0) AS paid FROM payments '
        'WHERE subscription_id = ? AND voided = 0',
        variables: [Variable.withInt(subscriptionId)],
        readsFrom: {_db.payments},
      ).getSingle();
      final paidSoFar = paidRow.read<int>('paid');

      final balance = PricingCalculator.due(
        total: sub.totalAmount,
        paid: paidSoFar,
      );
      if (amount > balance) {
        throw StateError('Amount exceeds balance of ₹$balance');
      }

      return _db.into(_db.payments).insert(
            PaymentsCompanion.insert(
              subscriptionId: Value(subscriptionId),
              memberId: memberId,
              amount: amount,
              mode: mode,
              paidOn: AppDateUtils.toStorage(paidOn),
              note: Value(note),
              createdAt: now,
            ),
          );
    });
  }

  /// Voids a payment (soft-delete, never removed — spec section 4).
  Future<void> voidPayment(int paymentId, String reason) async {
    await (_db.update(_db.payments)..where((p) => p.id.equals(paymentId)))
        .write(PaymentsCompanion(
      voided: const Value(true),
      voidReason: Value(reason.trim().isEmpty ? null : reason.trim()),
      voidedAt: Value(DateTime.now()),
    ));
  }

  // ── Pending dues ─────────────────────────────────────────────────────────

  /// Members whose latest non-cancelled subscription has due > 0.
  Future<List<PendingDueRow>> pendingDues({bool archivedToo = false}) async {
    final rows = await _db.customSelect(
      '''
      WITH latest AS (
        SELECT id, member_id, plan_name_snapshot, start_date, end_date, total_amount,
               ROW_NUMBER() OVER (PARTITION BY member_id ORDER BY id DESC) AS rn
        FROM subscriptions
        WHERE status_override IS NULL
      )
      SELECT m.id AS member_id, m.member_code, m.name, m.phone, m.photo_path,
             m.is_archived, l.id AS sub_id, l.plan_name_snapshot, l.start_date,
             l.end_date, l.total_amount,
             COALESCE((SELECT SUM(amount) FROM payments p
                       WHERE p.subscription_id = l.id AND p.voided = 0), 0) AS paid
      FROM latest l
      JOIN members m ON m.id = l.member_id
      WHERE l.rn = 1 AND l.total_amount > paid
      ORDER BY (l.total_amount - paid) DESC, l.end_date ASC
      ''',
      readsFrom: {_db.members, _db.subscriptions, _db.payments},
    ).get();

    return rows
        .where((r) => archivedToo || !r.read<bool>('is_archived'))
        .map((r) => PendingDueRow(
              memberId: r.read<int>('member_id'),
              memberCode: r.read<String>('member_code'),
              name: r.read<String>('name'),
              phone: r.read<String>('phone'),
              photoPath: r.readNullable<String>('photo_path'),
              subscriptionId: r.read<int>('sub_id'),
              planName: r.read<String>('plan_name_snapshot'),
              startDate: r.read<String>('start_date'),
              endDate: r.read<String>('end_date'),
              total: r.read<int>('total_amount'),
              paid: r.read<int>('paid'),
            ))
        .toList();
  }

  /// Live stream of the dues list for the Home dues card count.
  Stream<int> watchPendingDuesCount() {
    return _db.customSelect(
      '''
      WITH latest AS (
        SELECT id, member_id, total_amount,
               ROW_NUMBER() OVER (PARTITION BY member_id ORDER BY id DESC) AS rn
        FROM subscriptions
        WHERE status_override IS NULL
      )
      SELECT COUNT(*) AS cnt
      FROM latest l
      JOIN members m ON m.id = l.member_id
      WHERE l.rn = 1 AND m.is_archived = 0
        AND l.total_amount > COALESCE((SELECT SUM(amount) FROM payments p
              WHERE p.subscription_id = l.id AND p.voided = 0), 0)
      ''',
      readsFrom: {_db.members, _db.subscriptions, _db.payments},
    ).watchSingle().map((r) => r.read<int>('cnt'));
  }

  // ── Day book ─────────────────────────────────────────────────────────────

  /// All payments recorded on [date] (voided ones included, flagged).
  Future<DayBookTotals> dayBook(DateTime date) async {
    final day = AppDateUtils.toStorage(date);
    final rows = await _db.customSelect(
      '''
      SELECT p.id, p.amount, p.mode, p.note, p.voided, m.name AS member_name,
             m.member_code
      FROM payments p JOIN members m ON m.id = p.member_id
      WHERE p.paid_on = ?
      ORDER BY p.id ASC
      ''',
      variables: [Variable.withString(day)],
      readsFrom: {_db.payments, _db.members},
    ).get();

    final perMode = <PaymentMode, int>{};
    var grand = 0;
    for (final r in rows) {
      if (r.read<bool>('voided')) continue;
      final mode = PaymentMode.values.firstWhere(
        (m) => m.name == r.read<String>('mode'),
      );
      final amount = r.read<int>('amount');
      perMode[mode] = (perMode[mode] ?? 0) + amount;
      grand += amount;
    }
    return DayBookTotals(perMode: perMode, grandTotal: grand);
  }

  /// Day-book rows for [date], oldest first.
  Future<List<DayBookRow>> dayBookRows(DateTime date) async {
    final day = AppDateUtils.toStorage(date);
    final rows = await _db.customSelect(
      '''
      SELECT p.id, p.amount, p.mode, p.note, p.voided, m.name AS member_name,
             m.member_code
      FROM payments p JOIN members m ON m.id = p.member_id
      WHERE p.paid_on = ?
      ORDER BY p.id ASC
      ''',
      variables: [Variable.withString(day)],
      readsFrom: {_db.payments, _db.members},
    ).get();

    return rows.map((r) {
      final modeName = r.read<String>('mode');
      return DayBookRow(
        id: r.read<int>('id'),
        memberName: r.read<String>('member_name'),
        memberCode: r.read<String>('member_code'),
        amount: r.read<int>('amount'),
        mode: PaymentMode.values.firstWhere((m) => m.name == modeName),
        note: r.readNullable<String>('note'),
        voided: r.read<bool>('voided'),
      );
    }).toList();
  }

  // ── Cancel ───────────────────────────────────────────────────────────────

  /// Cancels a subscription with a reason (spec 5.6). The row remains as
  /// history; status computation ignores it.
  Future<void> cancelSubscription(int subscriptionId, String reason) async {
    await (_db.update(_db.subscriptions)
          ..where((s) => s.id.equals(subscriptionId)))
        .write(SubscriptionsCompanion(
      statusOverride: const Value('cancelled'),
      cancelReason: Value(reason.trim().isEmpty ? null : reason.trim()),
    ));
  }

  /// The receipt data needs member + subscription context; the caller loads a
  /// profile and builds [ReceiptData] itself. Kept here for cohesion.
  static int memberPaidTotal(List<ProfilePayment> payments) =>
      payments.where((p) => !p.voided).fold(0, (s, p) => s + p.amount);
}
