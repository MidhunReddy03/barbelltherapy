import 'dart:convert';

import 'package:drift/drift.dart';

import '../../domain/enums.dart';
import '../database.dart';
import 'settings_repository.dart';

/// A saved discount preset shown as one-tap "Offers" in the enroll screen,
/// e.g. `Diwali 10%` or `Friend referral ₹1200`.
///
/// Presets are stored as JSON in the settings table (the spec's data model
/// has no presets table; see DECISIONS.md).
class DiscountPreset {
  const DiscountPreset({
    required this.name,
    required this.type,
    required this.value,
  });

  final String name;
  final DiscountType type;
  final int value;

  Map<String, Object?> toJson() => {
        'name': name,
        'type': type.name,
        'value': value,
      };

  static DiscountPreset fromJson(Map<String, Object?> json) =>
      DiscountPreset(
        name: json['name'] as String? ?? '',
        type: DiscountType.values.firstWhere(
          (t) => t.name == json['type'],
          orElse: () => DiscountType.none,
        ),
        value: (json['value'] as num?)?.toInt() ?? 0,
      );

  /// Label shown on the offer chip, e.g. `Friend referral ₹1200 off` or
  /// `Diwali 10%`.
  String get chipLabel {
    switch (type) {
      case DiscountType.none:
        return name;
      case DiscountType.flat:
        return '$name (₹$value off)';
      case DiscountType.percent:
        return '$name ($value%)';
    }
  }
}

/// CRUD for plans, add-ons and the enroll catalog (plans, offers,
/// admission-fee default). Plan price changes never touch existing
/// subscriptions: subscriptions store price snapshots at creation time.
class CatalogRepository {
  CatalogRepository(this._db, this._settings);

  final AppDatabase _db;
  final SettingsRepository _settings;

  // ── Plans ─────────────────────────────────────────────────────────────────

  /// Active plans ordered for the enroll picker.
  Stream<List<Plan>> watchActivePlans() {
    return (_db.select(_db.plans)
          ..where((p) => p.isActive)
          ..orderBy([
            (p) => OrderingTerm.asc(p.sortOrder),
            (p) => OrderingTerm.asc(p.id),
          ]))
        .watch();
  }

  /// All plans including inactive ones (for the manager screen).
  Stream<List<Plan>> watchAllPlans() {
    return (_db.select(_db.plans)
          ..orderBy([
            (p) => OrderingTerm.asc(p.sortOrder),
            (p) => OrderingTerm.asc(p.id),
          ]))
        .watch();
  }

  Future<int> addPlan({
    required String name,
    required int durationMonths,
    required int price,
  }) {
    return _db.into(_db.plans).insert(PlansCompanion.insert(
          name: name.trim(),
          durationMonths: durationMonths,
          price: price,
        ));
  }

  Future<void> updatePlan({
    required int id,
    required String name,
    required int durationMonths,
    required int price,
  }) {
    return (_db.update(_db.plans)..where((p) => p.id.equals(id))).write(
      PlansCompanion(
        name: Value(name.trim()),
        durationMonths: Value(durationMonths),
        price: Value(price),
      ),
    );
  }

  Future<void> setPlanActive(int id, bool active) {
    return (_db.update(_db.plans)..where((p) => p.id.equals(id)))
        .write(PlansCompanion(isActive: Value(active)));
  }

  /// Persists a new ordering: the ids in [orderedIds] get sort orders
  /// 0,1,2,… in that sequence.
  Future<void> reorderPlans(List<int> orderedIds) async {
    await _db.batch((batch) {
      for (var i = 0; i < orderedIds.length; i++) {
        batch.update(
          _db.plans,
          PlansCompanion(sortOrder: Value(i)),
          where: (tbl) => tbl.id.equals(orderedIds[i]),
        );
      }
    });
  }

  // ── Add-ons ───────────────────────────────────────────────────────────────

  Stream<List<Addon>> watchActiveAddons() {
    return (_db.select(_db.addons)
          ..where((a) => a.isActive)
          ..orderBy([(a) => OrderingTerm.asc(a.id)]))
        .watch();
  }

  Stream<List<Addon>> watchAllAddons() {
    return (_db.select(_db.addons)
          ..orderBy([(a) => OrderingTerm.asc(a.id)]))
        .watch();
  }

  Future<int> addAddon({
    required String name,
    required int price,
    required AddonBilling billing,
  }) {
    return _db.into(_db.addons).insert(AddonsCompanion.insert(
          name: name.trim(),
          price: price,
          billing: billing,
        ));
  }

  Future<void> updateAddon({
    required int id,
    required String name,
    required int price,
    required AddonBilling billing,
  }) {
    return (_db.update(_db.addons)..where((a) => a.id.equals(id))).write(
      AddonsCompanion(
        name: Value(name.trim()),
        price: Value(price),
        billing: Value(billing),
      ),
    );
  }

  Future<void> setAddonActive(int id, bool active) {
    return (_db.update(_db.addons)..where((a) => a.id.equals(id)))
        .write(AddonsCompanion(isActive: Value(active)));
  }

  // ── Admission fee default ─────────────────────────────────────────────────

  Future<void> setAdmissionFeeDefault(int rupees) =>
      _settings.set('admission_fee_default', '$rupees');

  // ── Discount presets ──────────────────────────────────────────────────────

  Future<List<DiscountPreset>> discountPresets() async {
    final raw = await _settings.get(SettingKeys.discountPresets);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<Object?>;
      return list
          .whereType<Map<Object?, Object?>>()
          .map((m) => DiscountPreset.fromJson(
                m.map((k, v) => MapEntry('$k', v)),
              ))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Stream<List<DiscountPreset>> watchDiscountPresets() =>
      _settings.watchAll().asyncMap((_) => discountPresets());

  Future<void> saveDiscountPresets(List<DiscountPreset> presets) =>
      _settings.set(
        SettingKeys.discountPresets,
        jsonEncode(presets.map((p) => p.toJson()).toList()),
      );
}
