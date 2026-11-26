import 'package:drift/drift.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/app_date_utils.dart';
import '../../core/utils/phone_utils.dart';
import '../../domain/end_date_calculator.dart';
import '../../domain/enums.dart';
import '../../domain/pricing_calculator.dart';
import '../database.dart';
import 'settings_repository.dart';

/// Everything the 4-step enroll wizard collects. Back navigation keeps this
/// object alive; "Confirm & Enroll" persists it in ONE transaction.
class EnrollDraft {
  EnrollDraft({
    this.photoPath,
    this.name = '',
    this.phone = '',
    this.age,
    this.gender,
    this.notes,
    this.plan,
    DateTime? startDate,
    this.addonIds = const [],
    int? admissionFee,
    this.discountType = DiscountType.none,
    this.discountValue = 0,
    this.paymentMode = PaymentMode.cash,
    this.amountPaid,
    this.paymentNote,
  })  : startDate = startDate ?? AppDateUtils.today(),
        admissionFee = admissionFee ?? 0;

  // Step 1 — details
  final String? photoPath;
  final String name;
  final String phone; // normalized
  final int? age;
  final String? gender;
  final String? notes;

  // Step 2 — plan
  final Plan? plan;
  final DateTime startDate;
  final List<Addon> addonIds; // selected add-ons
  final int admissionFee;
  final DiscountType discountType;
  final int discountValue;

  // Step 3 — payment
  final PaymentMode paymentMode;
  final int? amountPaid; // null = unpaid (₹0)
  final String? paymentNote;

  /// Inclusive end date, computed live for step 2 display.
  DateTime? get endDate {
    final plan = this.plan;
    if (plan == null) return null;
    return EndDateCalculator.calculate(startDate, plan.durationMonths);
  }

  /// Price summary for step 3 (spec 6.4).
  PricingResult? get pricing {
    final plan = this.plan;
    if (plan == null) return null;
    return PricingCalculator.compute(
      planPrice: plan.price,
      addonPrices: addonIds.map((a) => a.price).toList(),
      admissionFee: admissionFee,
      discountType: discountType,
      discountValue: discountValue,
    );
  }

  int get paid => amountPaid ?? 0;

  /// Due after the amount entered in step 3.
  int? get due => pricing == null ? null : PricingCalculator.due(
        total: pricing!.total,
        paid: paid,
      );

  /// Step-level validity for the Next button.
  bool get detailsValid =>
      name.trim().isNotEmpty && PhoneUtils.isValid(phone);

  bool get planValid => plan != null && admissionFee >= 0;

  bool get paymentValid {
    final p = pricing;
    if (p == null) return false;
    return paid >= 0 && paid <= p.total;
  }

  EnrollDraft copyWith({
    Object? photoPath = _sentinel,
    String? name,
    String? phone,
    Object? age = _sentinel,
    Object? gender = _sentinel,
    Object? notes = _sentinel,
    Plan? plan,
    DateTime? startDate,
    List<Addon>? addonIds,
    int? admissionFee,
    DiscountType? discountType,
    int? discountValue,
    PaymentMode? paymentMode,
    Object? amountPaid = _sentinel,
    Object? paymentNote = _sentinel,
  }) {
    return EnrollDraft(
      photoPath: photoPath == _sentinel ? this.photoPath : photoPath as String?,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      age: age == _sentinel ? this.age : age as int?,
      gender: gender == _sentinel ? this.gender : gender as String?,
      notes: notes == _sentinel ? this.notes : notes as String?,
      plan: plan ?? this.plan,
      startDate: startDate ?? this.startDate,
      addonIds: addonIds ?? this.addonIds,
      admissionFee: admissionFee ?? this.admissionFee,
      discountType: discountType ?? this.discountType,
      discountValue: discountValue ?? this.discountValue,
      paymentMode: paymentMode ?? this.paymentMode,
      amountPaid:
          amountPaid == _sentinel ? this.amountPaid : amountPaid as int?,
      paymentNote:
          paymentNote == _sentinel ? this.paymentNote : paymentNote as String?,
    );
  }

  static const _sentinel = Object();
}

/// Result of a successful enroll transaction.
class EnrollResult {
  const EnrollResult({
    required this.memberId,
    required this.subscriptionId,
    required this.paymentId,
    required this.memberCode,
  });

  final int memberId;
  final int subscriptionId;
  final int? paymentId;
  final String memberCode;
}

/// Saves an enrollment atomically: member + subscription + add-on snapshots +
/// first payment, all or nothing (spec 6.4 step 4).
class EnrollRepository {
  EnrollRepository(this._db, this._settings);

  final AppDatabase _db;
  final SettingsRepository _settings;

  /// Live duplicate-phone check for step 1 (spec 6.4).
  /// Returns the existing member's display info, or null when the phone is
  /// free. Cancelled/archived members are included — the owner must decide.
  Future<String?> findDuplicatePhone(String normalizedPhone) async {
    if (!PhoneUtils.isValid(normalizedPhone)) return null;
    final row = await (_db.select(_db.members)
          ..where((m) => m.phone.equals(normalizedPhone) & m.isArchived.equals(false))
          ..limit(1))
        .getSingleOrNull();
    if (row == null) return null;
    return '${row.name} (${row.memberCode})';
  }

  /// The enroll transaction (all-or-nothing).
  Future<EnrollResult> enroll(EnrollDraft draft) async {
    final plan = draft.plan;
    if (plan == null) {
      throw StateError('Cannot enroll without a plan');
    }
    final pricing = draft.pricing!;
    final endDate = draft.endDate!;

    final memberCode = await _settings.nextMemberCode();
    final now = DateTime.now();

    return _db.transaction(() async {
      final memberId = await _db.into(_db.members).insert(
            MembersCompanion.insert(
              memberCode: memberCode,
              name: draft.name.trim(),
              phone: draft.phone,
              age: Value(draft.age),
              gender: Value(draft.gender),
              photoPath: Value(draft.photoPath),
              joinedOn: AppDateUtils.toStorage(draft.startDate),
              notes: Value(draft.notes),
              createdAt: now,
            ),
          );

      final subscriptionId = await _db.into(_db.subscriptions).insert(
            SubscriptionsCompanion.insert(
              memberId: memberId,
              planId: plan.id,
              planNameSnapshot: plan.name,
              planPriceSnapshot: plan.price,
              startDate: AppDateUtils.toStorage(draft.startDate),
              originalEndDate: AppDateUtils.toStorage(endDate),
              endDate: AppDateUtils.toStorage(endDate),
              admissionFee: Value(draft.admissionFee),
              discountType: draft.discountType,
              discountValue: Value(draft.discountValue),
              totalAmount: pricing.total,
              createdAt: now,
            ),
          );

      if (draft.addonIds.isNotEmpty) {
        await _db.batch((batch) {
          batch.insertAll(
            _db.subscriptionAddons,
            draft.addonIds
                .map((a) => SubscriptionAddonsCompanion.insert(
                      subscriptionId: subscriptionId,
                      addonId: a.id,
                      nameSnapshot: a.name,
                      priceSnapshot: a.price,
                    ))
                .toList(),
          );
        });
      }

      int? paymentId;
      if (draft.paid > 0) {
        paymentId = await _db.into(_db.payments).insert(
              PaymentsCompanion.insert(
                subscriptionId: Value(subscriptionId),
                memberId: memberId,
                amount: draft.paid,
                mode: draft.paymentMode,
                paidOn: AppDateUtils.toStorage(AppDateUtils.today()),
                note: Value(draft.paymentNote),
                createdAt: now,
              ),
            );
      }

      await _settings.bumpMemberSeq();

      return EnrollResult(
        memberId: memberId,
        subscriptionId: subscriptionId,
        paymentId: paymentId,
        memberCode: memberCode,
      );
    });
  }

  /// Log a `welcome` message row when the owner sends the welcome message.
  Future<void> markWelcomeSent({
    required int memberId,
    required int subscriptionId,
    required int templateId,
  }) async {
    await _db.into(_db.messageLog).insert(
          MessageLogCompanion.insert(
            memberId: Value(memberId),
            type: MessageType.welcome,
            subscriptionId: Value(subscriptionId),
            sentAt: DateTime.now(),
            templateId: Value(templateId),
          ),
        );
  }

  /// Default admission fee for the enroll screen (Settings value).
  Future<int> admissionFeeDefault() => _settings.getInt(
        'admission_fee_default',
        AppConstants.defaultAdmissionFee,
      );

  // ── Renewal (spec 5.5) ───────────────────────────────────────────────────

  /// Member details + suggested start date for the renew flow.
  Future<RenewPrefill?> renewPrefill(int memberId) async {
    final member = await (_db.select(_db.members)
          ..where((m) => m.id.equals(memberId)))
        .getSingleOrNull();
    if (member == null) return null;

    // Latest non-cancelled subscription decides the suggested start date.
    final sub = await (_db.select(_db.subscriptions)
          ..where((s) =>
              s.memberId.equals(memberId) & s.statusOverride.isNull())
          ..orderBy([(s) => OrderingTerm.desc(s.id)])
          ..limit(1))
        .getSingleOrNull();

    final today = AppDateUtils.today();
    DateTime suggestedStart = today;
    String? lastPlanName;
    DateTime? lastEndDate;
    if (sub != null) {
      lastPlanName = sub.planNameSnapshot;
      lastEndDate = AppDateUtils.parse(sub.endDate);
      // Still active/expiring: renew from the day after the current end date.
      // Already expired: renew from today.
      if (lastEndDate != null && !lastEndDate.isBefore(today)) {
        suggestedStart = lastEndDate.add(const Duration(days: 1));
      }
    }

    return RenewPrefill(
      memberId: memberId,
      memberCode: member.memberCode,
      name: member.name,
      phone: member.phone,
      age: member.age,
      gender: member.gender,
      photoPath: member.photoPath,
      notes: member.notes,
      suggestedStart: suggestedStart,
      lastPlanName: lastPlanName,
      lastEndDate: lastEndDate,
    );
  }

  /// Creates a NEW subscription (+ add-ons + first payment) for an EXISTING
  /// member in one transaction. Old subscriptions remain as history.
  Future<EnrollResult> renew({
    required int memberId,
    required String memberCode,
    required EnrollDraft draft,
  }) async {
    final plan = draft.plan;
    if (plan == null) throw StateError('Cannot renew without a plan');
    final pricing = draft.pricing!;
    final endDate = draft.endDate!;
    final now = DateTime.now();

    return _db.transaction(() async {
      final subscriptionId = await _db.into(_db.subscriptions).insert(
            SubscriptionsCompanion.insert(
              memberId: memberId,
              planId: plan.id,
              planNameSnapshot: plan.name,
              planPriceSnapshot: plan.price,
              startDate: AppDateUtils.toStorage(draft.startDate),
              originalEndDate: AppDateUtils.toStorage(endDate),
              endDate: AppDateUtils.toStorage(endDate),
              admissionFee: Value(draft.admissionFee),
              discountType: draft.discountType,
              discountValue: Value(draft.discountValue),
              totalAmount: pricing.total,
              createdAt: now,
            ),
          );

      if (draft.addonIds.isNotEmpty) {
        await _db.batch((batch) {
          batch.insertAll(
            _db.subscriptionAddons,
            draft.addonIds
                .map((a) => SubscriptionAddonsCompanion.insert(
                      subscriptionId: subscriptionId,
                      addonId: a.id,
                      nameSnapshot: a.name,
                      priceSnapshot: a.price,
                    ))
                .toList(),
          );
        });
      }

      int? paymentId;
      if (draft.paid > 0) {
        paymentId = await _db.into(_db.payments).insert(
              PaymentsCompanion.insert(
                subscriptionId: Value(subscriptionId),
                memberId: memberId,
                amount: draft.paid,
                mode: draft.paymentMode,
                paidOn: AppDateUtils.toStorage(AppDateUtils.today()),
                note: Value(draft.paymentNote),
                createdAt: now,
              ),
            );
      }

      return EnrollResult(
        memberId: memberId,
        subscriptionId: subscriptionId,
        paymentId: paymentId,
        memberCode: memberCode,
      );
    });
  }
}

/// Prefilled data for the renew flow (spec 5.5).
class RenewPrefill {
  const RenewPrefill({
    required this.memberId,
    required this.memberCode,
    required this.name,
    required this.phone,
    this.age,
    this.gender,
    this.photoPath,
    this.notes,
    required this.suggestedStart,
    this.lastPlanName,
    this.lastEndDate,
  });

  final int memberId;
  final String memberCode;
  final String name;
  final String phone;
  final int? age;
  final String? gender;
  final String? photoPath;
  final String? notes;

  /// Day after the current end date when still active, else today.
  final DateTime suggestedStart;
  final String? lastPlanName;
  final DateTime? lastEndDate;
}

