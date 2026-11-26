import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymdesk/core/utils/app_date_utils.dart';
import 'package:gymdesk/data/database.dart';
import 'package:gymdesk/data/repositories/enroll_repository.dart';
import 'package:gymdesk/data/repositories/member_profile_repository.dart';
import 'package:gymdesk/data/repositories/members_repository.dart';
import 'package:gymdesk/data/repositories/settings_repository.dart';
import 'package:gymdesk/domain/enums.dart';

void main() {
  late AppDatabase db;
  late EnrollRepository enroll;
  late MemberProfileRepository profile;
  late MembersRepository members;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    enroll = EnrollRepository(db, SettingsRepository(db));
    profile = MemberProfileRepository(db);
    members = MembersRepository(db);
  });

  tearDown(() async => db.close());

  Future<EnrollResult> enrollRavi({
    int? amountPaid = 1000,
    DateTime? startDate,
  }) async {
    final plan = await (db.select(db.plans)..where((p) => p.name.equals('Monthly')))
        .getSingle();
    return enroll.enroll(EnrollDraft(
      name: 'Ravi Kumar',
      phone: '9876543210',
      age: 28,
      gender: 'Male',
      plan: plan,
      startDate: startDate ?? DateTime(2026, 3, 1),
      amountPaid: amountPaid,
    ));
  }

  test('profile loads the latest subscription, paid sum and due', () async {
    final result = await enrollRavi(amountPaid: 400);
    final p = await profile.load(result.memberId);

    expect(p.member.name, 'Ravi Kumar');
    expect(p.member.joinedOn, '2026-03-01');
    expect(p.subscriptionId, result.subscriptionId);
    expect(p.planName, 'Monthly');
    expect(p.startDate, '2026-03-01');
    expect(p.totalAmount, 1000); // seeded Monthly placeholder price
    expect(p.paid, 400);
    expect(p.due, 600);
  });

  test('profile history lists every subscription newest-first, with paid sums',
      () async {
    final result = await enrollRavi(amountPaid: 1000);
    final plan = await (db.select(db.plans)..where((p) => p.name.equals('Monthly')))
        .getSingle();

    // A second (older-style) subscription for history: insert directly.
    await db.into(db.subscriptions).insert(SubscriptionsCompanion.insert(
          memberId: result.memberId,
          planId: plan.id,
          planNameSnapshot: 'Monthly',
          planPriceSnapshot: plan.price,
          discountType: DiscountType.none,
          startDate: '2026-02-01',
          originalEndDate: '2026-02-28',
          endDate: '2026-02-28',
          totalAmount: plan.price,
          createdAt: DateTime(2026, 2, 1),
        ));

    final p = await profile.load(result.memberId);
    expect(p.history, hasLength(2));
    // Newest first by id (a real renewal always gets a higher id).
    expect(p.history.first.id, greaterThan(p.history.last.id));
    // The enroll-created subscription with its payment sum.
    final enrolled = p.history.singleWhere((h) => h.id == result.subscriptionId);
    expect(enrolled.paid, 1000);
    expect(enrolled.cancelled, isFalse);
    expect(enrolled.startDate, '2026-03-01');
    // The directly-inserted one.
    final manual = p.history.singleWhere((h) => h.id != result.subscriptionId);
    expect(manual.startDate, '2026-02-01');
    expect(manual.paid, 0);
    expect(manual.cancelled, isFalse);
  });

  test('voided payments are excluded from paid sums', () async {
    final result = await enrollRavi(amountPaid: 0);
    // Record two payments, void one.
    final now = DateTime.now();
    await db.into(db.payments).insert(PaymentsCompanion.insert(
          memberId: result.memberId,
          amount: 300,
          mode: PaymentMode.cash,
          paidOn: '2026-03-05',
          createdAt: now,
        ));
    await db.into(db.payments).insert(PaymentsCompanion.insert(
          memberId: result.memberId,
          amount: 200,
          mode: PaymentMode.upi_qr,
          paidOn: '2026-03-06',
          voided: const Value(true),
          voidReason: const Value('Mistake'),
          voidedAt: Value(now),
          createdAt: now,
        ));

    final p = await profile.load(result.memberId);
    expect(p.paid, 300);
    expect(p.due, 700);
    expect(p.payments, hasLength(2));
    expect(p.payments.where((x) => x.voided), hasLength(1));
  });

  test('attendance summary counts distinct days in the last 90 days', () async {
    final result = await enrollRavi(amountPaid: 0);
    final today = AppDateUtils.today();
    final threeDaysAgo = today.subtract(const Duration(days: 3));
    final hundredDaysAgo = today.subtract(const Duration(days: 100));

    Future<void> checkin(DateTime day) => db.into(db.checkins).insert(
          CheckinsCompanion.insert(
            memberId: result.memberId,
            checkedInAt: DateTime(day.year, day.month, day.day, 8),
          ),
        );

    await checkin(today);
    await checkin(today); // twice the same day = 1 distinct day
    await checkin(threeDaysAgo);
    await checkin(hundredDaysAgo); // outside the 90-day window

    final p = await profile.load(result.memberId);
    final a = p.attendance!;
    expect(a.totalCount, 4);
    expect(a.last90Count, 2); // distinct days within 90 days
    expect(a.recentDates, hasLength(2));
    expect(a.lastVisit, isNotNull);
  });

  test('updateMember edits fields and keeps the existing photo', () async {
    final result = await enrollRavi(amountPaid: 0);
    await profile.updateMember(
      id: result.memberId,
      name: 'Ravi K',
      phone: '9000000002',
      age: 29,
      gender: 'Male',
      notes: 'Evening batch',
      photoPath: null,
    );
    final p = await profile.load(result.memberId);
    expect(p.member.name, 'Ravi K');
    expect(p.member.phone, '9000000002');
    expect(p.member.age, 29);
    expect(p.member.notes, 'Evening batch');
  });

  test('archived members vanish from the members list', () async {
    final result = await enrollRavi(amountPaid: 0);
    expect((await members.watchMembers().first), hasLength(1));

    await profile.setArchived(result.memberId, true);
    expect((await members.watchMembers().first), isEmpty);
  });

  test('member code, joined date and demographic fields round-trip', () async {
    final result = await enrollRavi(amountPaid: 0);
    final p = await profile.load(result.memberId);
    expect(p.member.memberCode, 'GYM-0001');
    expect(p.member.age, 28);
    expect(p.member.gender, 'Male');
  });
}
