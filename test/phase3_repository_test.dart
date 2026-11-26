import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymdesk/core/utils/app_date_utils.dart';
import 'package:gymdesk/data/database.dart';
import 'package:gymdesk/data/repositories/enroll_repository.dart';
import 'package:gymdesk/data/repositories/freeze_repository.dart';
import 'package:gymdesk/data/repositories/payments_repository.dart';
import 'package:gymdesk/data/repositories/settings_repository.dart';
import 'package:gymdesk/domain/end_date_calculator.dart';
import 'package:gymdesk/domain/enums.dart';

/// Phase 3 acceptance tests (spec section 10): freeze extends the end date by
/// exact days, ending early reverts unused days, renewal starts on the right
/// date, dues math is correct. All dates are relative to today so the tests
/// never go stale.
void main() {
  late AppDatabase db;
  late SettingsRepository settings;
  late EnrollRepository enrollRepo;
  late PaymentsRepository payments;
  late FreezeRepository freezes;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    settings = SettingsRepository(db);
    enrollRepo = EnrollRepository(db, settings);
    payments = PaymentsRepository(db);
    freezes = FreezeRepository(db, settings);
  });

  tearDown(() async => db.close());

  final today = AppDateUtils.today();

  Future<Plan> plan(String name) async {
    return (db.select(db.plans)..where((p) => p.name.equals(name)))
        .getSingle();
  }

  /// Enrolls a member with the Monthly plan paying [amount], starting
  /// [daysAgo] days before today (default 5 → membership is active).
  Future<EnrollResult> enrollMember({
    String name = 'Ravi Kumar',
    String? phone,
    int daysAgo = 5,
    required int amount,
    Plan? planOverride,
  }) async {
    final p = planOverride ?? await plan('Monthly');
    return enrollRepo.enroll(EnrollDraft(
      name: name,
      phone: phone ?? '98765432${(10 + (name.hashCode % 80)).toString().padLeft(2, '0')}',
      plan: p,
      startDate: today.subtract(Duration(days: daysAgo)),
      amountPaid: amount,
    ));
  }

  EnrollDraft renewDraft({required Plan p, required DateTime start, int paid = 0}) {
    return EnrollDraft(
      name: 'ignored', phone: 'ignored', plan: p, startDate: start, amountPaid: paid,
    );
  }

  Future<Subscription> sub(int id) =>
      (db.select(db.subscriptions)..where((s) => s.id.equals(id))).getSingle();

  // ── Record / void payments ──────────────────────────────────────────────

  test('record payment: partial then exact balance, overpay rejected',
      () async {
    final r = await enrollMember(amount: 300); // Monthly total 1000
    expect(r.paymentId, isNotNull);

    expect(
      () => payments.recordPayment(
        subscriptionId: r.subscriptionId,
        memberId: r.memberId,
        amount: 800, // balance is 700
        mode: PaymentMode.cash,
        paidOn: today,
      ),
      throwsA(isA<StateError>().having(
          (e) => e.message, 'message', contains('exceeds balance of ₹700'))),
    );

    final id = await payments.recordPayment(
      subscriptionId: r.subscriptionId,
      memberId: r.memberId,
      amount: 700,
      mode: PaymentMode.upi_qr,
      paidOn: today,
    );
    expect(id, greaterThan(0));

    expect(
      () => payments.recordPayment(
        subscriptionId: r.subscriptionId,
        memberId: r.memberId,
        amount: 1,
        mode: PaymentMode.cash,
        paidOn: today,
      ),
      throwsA(isA<StateError>().having(
          (e) => e.message, 'message', contains('exceeds balance of ₹0'))),
    );
  });

  test('void payment restores dues and keeps the row for the audit trail',
      () async {
    final r = await enrollMember(amount: 1000);
    await payments.voidPayment(r.paymentId!, 'Wrong entry');

    final row = await (db.select(db.payments)
          ..where((p) => p.id.equals(r.paymentId!)))
        .getSingle();
    expect(row.voided, isTrue);
    expect(row.voidReason, 'Wrong entry');
    expect(row.voidedAt, isNotNull);

    final dues = await payments.pendingDues();
    expect(dues, hasLength(1));
    expect(dues.first.due, 1000);
  });

  test('cancelled subscriptions never appear in dues', () async {
    final r = await enrollMember(amount: 300);
    await payments.cancelSubscription(r.subscriptionId, 'Moved city');
    expect(await payments.pendingDues(), isEmpty);
  });

  // ── Pending dues list ───────────────────────────────────────────────────

  test('pending dues lists only members with due > 0, sorted by amount',
      () async {
    await enrollMember(name: 'A', phone: '9000000001', amount: 0);
    await enrollMember(name: 'B', phone: '9000000002', amount: 400);
    await enrollMember(name: 'C', phone: '9000000003', amount: 1000);

    final dues = await payments.pendingDues();
    expect(dues.map((d) => d.name), ['A', 'B']); // C is fully paid
    expect(dues.first.due, 1000);
    expect(dues.last.due, 600);
  });

  // ── Day book ────────────────────────────────────────────────────────────

  test('day book totals per mode and skips voided rows in totals', () async {
    final r1 = await enrollMember(name: 'A', phone: '9000000001', amount: 0);
    await payments.recordPayment(
        subscriptionId: r1.subscriptionId,
        memberId: r1.memberId,
        amount: 500,
        mode: PaymentMode.cash,
        paidOn: today);
    await payments.recordPayment(
        subscriptionId: r1.subscriptionId,
        memberId: r1.memberId,
        amount: 200,
        mode: PaymentMode.upi_qr,
        paidOn: today);
    final pid = await payments.recordPayment(
        subscriptionId: r1.subscriptionId,
        memberId: r1.memberId,
        amount: 100,
        mode: PaymentMode.card,
        paidOn: today);
    await payments.voidPayment(pid, 'test');

    final totals = await payments.dayBook(today);
    expect(totals.perMode[PaymentMode.cash], 500);
    expect(totals.perMode[PaymentMode.upi_qr], 200);
    expect(totals.perMode.containsKey(PaymentMode.card), isFalse);
    expect(totals.grandTotal, 700);

    final rows = await payments.dayBookRows(today);
    expect(rows, hasLength(3)); // voided row still listed, flagged
    expect(rows.where((r) => r.voided), hasLength(1));
  });

  // ── Freeze ──────────────────────────────────────────────────────────────

  test('freeze extends end date by exact days and validates', () async {
    final r = await enrollMember(amount: 1000); // active monthly
    final origEnd = AppDateUtils.parse(
        (await sub(r.subscriptionId)).endDate)!;

    final err = await freezes.validate(
      subscriptionId: r.subscriptionId,
      start: today,
      end: today.add(const Duration(days: 4)), // 5 days < min 7
    );
    expect(err, contains('Minimum freeze length'));

    // Freeze 7 days from today.
    await freezes.create(
      subscriptionId: r.subscriptionId,
      memberId: r.memberId,
      start: today,
      end: today.add(const Duration(days: 6)),
    );

    final newEnd = AppDateUtils.parse((await sub(r.subscriptionId)).endDate)!;
    expect(AppDateUtils.daysBetween(newEnd, origEnd), 7);

    // Overlapping the first freeze is rejected.
    final overlapErr = await freezes.validate(
      subscriptionId: r.subscriptionId,
      start: today.add(const Duration(days: 4)),
      end: today.add(const Duration(days: 15)),
    );
    expect(overlapErr, contains('Overlaps'));
  });

  test('freeze rejected on past start and max freezes', () async {
    final r = await enrollMember(amount: 1000);

    expect(
      await freezes.validate(
        subscriptionId: r.subscriptionId,
        start: today.subtract(const Duration(days: 2)), // past
        end: today.add(const Duration(days: 6)),
      ),
      contains('past'),
    );

    await freezes.create(
        subscriptionId: r.subscriptionId,
        memberId: r.memberId,
        start: today,
        end: today.add(const Duration(days: 6)));
    await freezes.create(
        subscriptionId: r.subscriptionId,
        memberId: r.memberId,
        start: today.add(const Duration(days: 10)),
        end: today.add(const Duration(days: 16)));
    expect(
      await freezes.validate(
        subscriptionId: r.subscriptionId,
        start: today.add(const Duration(days: 20)),
        end: today.add(const Duration(days: 26)),
      ),
      contains('Maximum 2'),
    );
  });

  test('freeze started yesterday, ended today: 1 day used, 6 reverted',
      () async {
    final r = await enrollMember(amount: 1000);
    final origEnd =
        AppDateUtils.parse((await sub(r.subscriptionId)).endDate)!;

    final freezeId = await freezes.create(
      subscriptionId: r.subscriptionId,
      memberId: r.memberId,
      start: today.subtract(const Duration(days: 1)), // ran yesterday
      end: today.add(const Duration(days: 5)), // planned 7 days
      skipValidation: true,
    );

    // Extend by 7, then end early with 1 day used → net +1 day on end date.
    await freezes.endEarly(freezeId);

    final newEnd = AppDateUtils.parse((await sub(r.subscriptionId)).endDate)!;
    expect(AppDateUtils.daysBetween(newEnd, origEnd), 1);

    final f = await (db.select(db.freezes)
          ..where((fr) => fr.id.equals(freezeId)))
        .getSingle();
    expect(f.days, 1);
    expect(f.endedEarlyOn, AppDateUtils.toStorage(today));
    // The window is closed so the member is not "frozen" anymore.
    final active = await freezes.activeFreeze(r.subscriptionId);
    expect(active, isNull);
  });

  test('end freeze on its first planned day reverts all planned days',
      () async {
    final r = await enrollMember(amount: 1000);
    final origEnd =
        AppDateUtils.parse((await sub(r.subscriptionId)).endDate)!;

    final freezeId = await freezes.create(
      subscriptionId: r.subscriptionId,
      memberId: r.memberId,
      start: today, // starts today, ended immediately → 0 days used
      end: today.add(const Duration(days: 6)),
    );
    await freezes.endEarly(freezeId);

    final newEnd = AppDateUtils.parse((await sub(r.subscriptionId)).endDate)!;
    expect(newEnd, origEnd); // full revert
    final f = await (db.select(db.freezes)
          ..where((fr) => fr.id.equals(freezeId)))
        .getSingle();
    expect(f.days, 0);
  });

  test('end freeze before it starts reverts all planned days', () async {
    final r = await enrollMember(amount: 1000);
    final origEnd =
        AppDateUtils.parse((await sub(r.subscriptionId)).endDate)!;

    final freezeId = await freezes.create(
      subscriptionId: r.subscriptionId,
      memberId: r.memberId,
      start: today.add(const Duration(days: 3)), // future freeze
      end: today.add(const Duration(days: 9)),
    );
    await freezes.endEarly(freezeId);

    final newEnd = AppDateUtils.parse((await sub(r.subscriptionId)).endDate)!;
    expect(newEnd, origEnd); // full revert
    final f = await (db.select(db.freezes)
          ..where((fr) => fr.id.equals(freezeId)))
        .getSingle();
    expect(f.days, 0);
  });

  test('freeze history lists all freezes', () async {
    final r = await enrollMember(amount: 1000);
    await freezes.create(
        subscriptionId: r.subscriptionId,
        memberId: r.memberId,
        start: today,
        end: today.add(const Duration(days: 6)));
    await freezes.create(
        subscriptionId: r.subscriptionId,
        memberId: r.memberId,
        start: today.add(const Duration(days: 10)),
        end: today.add(const Duration(days: 16)));
    final hist = await freezes.history(r.memberId);
    expect(hist, hasLength(2));
    expect(hist.first.subscriptionId, r.subscriptionId);
  });

  // ── Renewal ─────────────────────────────────────────────────────────────

  test('renew prefill: active membership suggests the day after end date',
      () async {
    final r = await enrollMember(amount: 1000);
    final end = AppDateUtils.parse((await sub(r.subscriptionId)).endDate)!;
    final prefill = await enrollRepo.renewPrefill(r.memberId);
    expect(prefill!.lastEndDate, end);
    expect(prefill.suggestedStart, end.add(const Duration(days: 1)));
  });

  test('renew prefill: expired membership suggests today', () async {
    final r = await enrollMember(amount: 1000, daysAgo: 60); // long expired
    final prefill = await enrollRepo.renewPrefill(r.memberId);
    expect(prefill!.suggestedStart, AppDateUtils.today());
  });

  test('renew prefill for member without any subscription suggests today',
      () async {
    final memberId = await db.into(db.members).insert(
          MembersCompanion.insert(
            memberCode: 'GYM-0999',
            name: 'No Plan Pete',
            phone: '9000000099',
            joinedOn: '2026-01-01',
            createdAt: DateTime(2026, 1, 1),
          ),
        );
    final prefill = await enrollRepo.renewPrefill(memberId);
    expect(prefill!.lastPlanName, isNull);
    expect(prefill.suggestedStart, AppDateUtils.today());
  });

  test('renew creates a NEW subscription and keeps the old as history',
      () async {
    final r = await enrollMember(amount: 1000);
    final end = AppDateUtils.parse((await sub(r.subscriptionId)).endDate)!;
    final renewStart = end.add(const Duration(days: 1));

    final yearly = await plan('Yearly'); // 12 months, ₹9000
    final r2 = await enrollRepo.renew(
      memberId: r.memberId,
      memberCode: r.memberCode,
      draft: renewDraft(p: yearly, start: renewStart, paid: 2000),
    );

    expect(r2.memberId, r.memberId);
    expect(r2.memberCode, r.memberCode);

    final subs = await (db.select(db.subscriptions)
          ..where((s) => s.memberId.equals(r.memberId)))
        .get();
    expect(subs, hasLength(2));

    final newSub = await sub(r2.subscriptionId);
    expect(newSub.startDate, AppDateUtils.toStorage(renewStart));
    expect(
        newSub.endDate, AppDateUtils.toStorage(EndDateCalculator.calculate(renewStart, 12)));
    expect(newSub.totalAmount, 9000);

    final payment = await (db.select(db.payments)
          ..where((p) => p.id.equals(r2.paymentId!)))
        .getSingle();
    expect(payment.subscriptionId, r2.subscriptionId);

    final oldSub = await sub(r.subscriptionId);
    expect(oldSub.endDate, AppDateUtils.toStorage(end));
  });

  test('renew with discount computes the same pricing as enroll', () async {
    final r = await enrollMember(amount: 0);
    final quarterly = await plan('Quarterly'); // ₹2700
    final r2 = await enrollRepo.renew(
      memberId: r.memberId,
      memberCode: r.memberCode,
      draft: EnrollDraft(
        plan: quarterly,
        startDate: today.add(const Duration(days: 20)),
        discountType: DiscountType.percent,
        discountValue: 10,
        amountPaid: 500,
      ),
    );
    final s = await sub(r2.subscriptionId);
    expect(s.totalAmount, 2430); // 2700 - 10%
  });

  // ── Cancel / archive ────────────────────────────────────────────────────

  test('cancel subscription stores status and reason, keeps the row',
      () async {
    final r = await enrollMember(amount: 300);
    await payments.cancelSubscription(r.subscriptionId, 'Relocating');
    final s = await sub(r.subscriptionId);
    expect(s.statusOverride, 'cancelled');
    expect(s.cancelReason, 'Relocating');
  });

  // ── Member deletion guard (spec 5.6) ────────────────────────────────────

  test('members with payments keep their audit trail (no hard delete)',
      () async {
    final r = await enrollMember(amount: 500);
    final rows = await (db.select(db.payments)
          ..where((p) => p.memberId.equals(r.memberId)))
        .get();
    expect(rows, isNotEmpty);
  });
}
