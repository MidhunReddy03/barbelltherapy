import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';import 'package:gymdesk/core/utils/app_date_utils.dart';
import 'package:gymdesk/data/database.dart';
import 'package:gymdesk/data/repositories/enroll_repository.dart';
import 'package:gymdesk/data/repositories/settings_repository.dart';
import 'package:gymdesk/domain/end_date_calculator.dart';
import 'package:gymdesk/domain/enums.dart';

void main() {
  late AppDatabase db;
  late SettingsRepository settings;
  late EnrollRepository enroll;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    settings = SettingsRepository(db);
    enroll = EnrollRepository(db, settings);
  });

  tearDown(() async => db.close());

  /// The seeded "Monthly" plan (1 month).
  Future<Plan> monthlyPlan() async {
    return (db.select(db.plans)
          ..where((p) => p.name.equals('Monthly')))
        .getSingle();
  }

  EnrollDraft draft({
    required Plan plan,
    String name = 'Ravi Kumar',
    String phone = '9876543210',
    DateTime? startDate,
    List<Addon> addons = const [],
    int admissionFee = 0,
    DiscountType discountType = DiscountType.none,
    int discountValue = 0,
    int? amountPaid,
    PaymentMode mode = PaymentMode.cash,
  }) {
    return EnrollDraft(
      name: name,
      phone: phone,
      age: 28,
      gender: 'Male',
      plan: plan,
      startDate: startDate ?? DateTime(2026, 3, 1),
      addonIds: addons,
      admissionFee: admissionFee,
      discountType: discountType,
      discountValue: discountValue,
      paymentMode: mode,
      amountPaid: amountPaid,
    );
  }

  test('full-payment enroll writes member, subscription and payment in one '
      'transaction, with GYM-0001 code and correct end date', () async {
    final plan = await monthlyPlan();
    final result = await enroll.enroll(draft(
      plan: plan,
      amountPaid: plan.price,
      admissionFee: 0,
    ));

    expect(result.memberCode, 'GYM-0001');
    final member = await (db.select(db.members)
          ..where((m) => m.id.equals(result.memberId)))
        .getSingle();
    expect(member.name, 'Ravi Kumar');
    expect(member.phone, '9876543210');
    expect(member.memberCode, 'GYM-0001');
    expect(member.joinedOn, '2026-03-01');

    final sub = await (db.select(db.subscriptions)
          ..where((s) => s.id.equals(result.subscriptionId)))
        .getSingle();
    // Inclusive end: addMonths(2026-03-01, 1) - 1 day = 2026-03-31.
    expect(sub.startDate, '2026-03-01');
    expect(sub.endDate, '2026-03-31');
    expect(sub.originalEndDate, '2026-03-31');
    expect(sub.planPriceSnapshot, plan.price);
    expect(sub.totalAmount, plan.price);

    final payments =
        await (db.select(db.payments)..where((p) => p.memberId.equals(member.id)))
            .get();
    expect(payments, hasLength(1));
    expect(payments.single.amount, plan.price);
    expect(payments.single.voided, isFalse);
  });

  test('partial payment stores the paid amount; the rest stays due', () async {
    final plan = await monthlyPlan();
    final result = await enroll.enroll(draft(
      plan: plan,
      amountPaid: 500, // less than plan price
      admissionFee: 0,
    ));

    final sub = await (db.select(db.subscriptions)
          ..where((s) => s.id.equals(result.subscriptionId)))
        .getSingle();
    final paid = await (db.select(db.payments)
          ..where((p) => p.subscriptionId.equals(sub.id))
          ..where((p) => p.voided.equals(false)))
        .get();
    final paidSum = paid.fold<int>(0, (s, p) => s + p.amount);

    expect(paidSum, 500);
    expect(sub.totalAmount - paidSum, plan.price - 500); // dues correct
  });

  test('unpaid enroll creates no payment row', () async {
    final plan = await monthlyPlan();
    final result = await enroll.enroll(draft(plan: plan));

    final payments = await db.select(db.payments).get();
    expect(payments, isEmpty);
    expect(result.paymentId, isNull);
  });

  test('percent discount applies to plan+addons but not the admission fee '
      '(end-to-end through the enroll transaction)', () async {
    final plan = await monthlyPlan();
    // plan 1000 + addon 300 + admission 300; 10% of 1300 = 130 -> 1470.
    final result = await enroll.enroll(draft(
      plan: plan,
      addons: const [
        Addon(
            id: 1,
            name: 'Personal Training',
            price: 300,
            billing: AddonBilling.one_time,
            isActive: true),
      ],
      admissionFee: 300,
      discountType: DiscountType.percent,
      discountValue: 10,
      amountPaid: 1470,
    ));

    final sub = await (db.select(db.subscriptions)
          ..where((s) => s.id.equals(result.subscriptionId)))
        .getSingle();
    expect(sub.totalAmount, 1470);
    expect(sub.discountType, DiscountType.percent);
    expect(sub.discountValue, 10);
    expect(sub.admissionFee, 300);

    final addons = await (db.select(db.subscriptionAddons)
          ..where((sa) => sa.subscriptionId.equals(sub.id)))
        .get();
    expect(addons, hasLength(1));
    expect(addons.single.nameSnapshot, 'Personal Training');
    expect(addons.single.priceSnapshot, 300);
  });

  test('flat discount subtracts from the subtotal', () async {
    final plan = await monthlyPlan();
    final result = await enroll.enroll(draft(
      plan: plan,
      admissionFee: 0,
      discountType: DiscountType.flat,
      discountValue: 200,
      amountPaid: plan.price - 200,
    ));
    final sub = await (db.select(db.subscriptions)
          ..where((s) => s.id.equals(result.subscriptionId)))
        .getSingle();
    expect(sub.totalAmount, plan.price - 200);
  });

  test('duplicate-phone check finds the active member by normalized phone',
      () async {
    final plan = await monthlyPlan();
    expect(
        await enroll.findDuplicatePhone('9876543210'), isNull); // free before

    await enroll.enroll(draft(plan: plan, amountPaid: 0));

    final dup = await enroll.findDuplicatePhone('9876543210');
    expect(dup, isNotNull);
    expect(dup, contains('Ravi Kumar'));
    expect(dup, contains('GYM-0001'));
  });

  test('archived members do not trigger the duplicate-phone warning',
      () async {
    final plan = await monthlyPlan();
    final result = await enroll.enroll(draft(plan: plan, amountPaid: 0));
    await (db.update(db.members)..where((m) => m.id.equals(result.memberId)))
        .write(const MembersCompanion(isArchived: Value(true)));

    expect(await enroll.findDuplicatePhone('9876543210'), isNull);
  });

  test('member code sequence increments across members', () async {
    final plan = await monthlyPlan();
    final r1 = await enroll.enroll(draft(plan: plan, amountPaid: 0));
    final r2 = await enroll.enroll(draft(
      plan: plan,
      name: 'Second',
      phone: '9000000001',
      amountPaid: 0,
    ));
    expect(r1.memberCode, 'GYM-0001');
    expect(r2.memberCode, 'GYM-0002');
  });

  test('enroll on a future start date marks the period as upcoming '
      '(start after today, stored as-is)', () async {
    final plan = await monthlyPlan();
    final future = AppDateUtils.today().add(const Duration(days: 10));
    final result = await enroll.enroll(draft(
      plan: plan,
      startDate: future,
      amountPaid: 0,
    ));
    final sub = await (db.select(db.subscriptions)
          ..where((s) => s.id.equals(result.subscriptionId)))
        .getSingle();
    expect(sub.startDate, AppDateUtils.toStorage(future));
    expect(
      sub.endDate,
      AppDateUtils.toStorage(
        EndDateCalculator.calculate(future, plan.durationMonths),
      ),
    );
  });

  test('welcome-message logging writes a message_log row', () async {
    final plan = await monthlyPlan();
    final result = await enroll.enroll(draft(plan: plan, amountPaid: 0));
    await enroll.markWelcomeSent(
      memberId: result.memberId,
      subscriptionId: result.subscriptionId,
      templateId: 1,
    );
    final logs = await db.select(db.messageLog).get();
    expect(logs, hasLength(1));
    expect(logs.single.type, MessageType.welcome);
    expect(logs.single.memberId, result.memberId);
  });
}
