import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymdesk/core/constants/app_constants.dart';
import 'package:gymdesk/data/database.dart';
import 'package:gymdesk/data/repositories/catalog_repository.dart';
import 'package:gymdesk/data/repositories/settings_repository.dart';
import 'package:gymdesk/domain/enums.dart';

void main() {
  late AppDatabase db;
  late CatalogRepository catalog;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    catalog = CatalogRepository(db, SettingsRepository(db));
  });

  tearDown(() async => db.close());

  test('first-run seed provides the four default plans', () async {
    final plans = await catalog.watchAllPlans().first;
    final names = plans.map((p) => p.name).toSet();
    expect(names, containsAll(['Monthly', 'Quarterly', 'Half-yearly', 'Yearly']));
  });

  test('plan CRUD works and price changes never touch existing subscriptions',
      () async {
    final id = await catalog.addPlan(name: 'Weekly', durationMonths: 1, price: 500);
    var plans = await catalog.watchAllPlans().first;
    expect(plans.map((p) => p.id), contains(id));

    await catalog.updatePlan(id: id, name: 'Weekly', durationMonths: 1, price: 600);
    plans = await catalog.watchAllPlans().first;
    expect(plans.firstWhere((p) => p.id == id).price, 600);

    await catalog.setPlanActive(id, false);
    expect(
        (await catalog.watchActivePlans().first).map((p) => p.id), isNot(contains(id)));
    await catalog.setPlanActive(id, true);
    expect(
        (await catalog.watchActivePlans().first).map((p) => p.id), contains(id));
  });

  test('reorderPlans persists the given sequence as sort orders', () async {
    final plans = await catalog.watchAllPlans().first;
    final reversedIds = plans.map((p) => p.id).toList().reversed.toList();

    await catalog.reorderPlans(reversedIds);

    final after = await catalog.watchAllPlans().first;
    expect(after.map((p) => p.id), reversedIds);
  });

  test('addon CRUD with billing modes', () async {
    final id = await catalog.addAddon(
        name: 'Locker', price: 100, billing: AddonBilling.one_time);
    var addons = await catalog.watchAllAddons().first;
    expect(addons.firstWhere((a) => a.id == id).billing, AddonBilling.one_time);

    await catalog.updateAddon(
        id: id, name: 'Locker', price: 150, billing: AddonBilling.per_plan);
    addons = await catalog.watchAllAddons().first;
    final addon = addons.firstWhere((a) => a.id == id);
    expect(addon.price, 150);
    expect(addon.billing, AddonBilling.per_plan);
  });

  test('discount presets round-trip through the settings store as JSON',
      () async {
    expect(await catalog.discountPresets(), isEmpty);

    await catalog.saveDiscountPresets([
      const DiscountPreset(name: 'Diwali', type: DiscountType.percent, value: 10),
      const DiscountPreset(name: 'Referral', type: DiscountType.flat, value: 200),
    ]);

    final presets = await catalog.discountPresets();
    expect(presets, hasLength(2));
    expect(presets[0].name, 'Diwali');
    expect(presets[0].type, DiscountType.percent);
    expect(presets[0].value, 10);
    expect(presets[1].chipLabel, 'Referral (₹200 off)');
  });

  test('corrupt preset JSON degrades to an empty list instead of crashing',
      () async {
    final settings = SettingsRepository(db);
    await settings.set(SettingKeys.discountPresets, 'not-json{{');
    expect(await catalog.discountPresets(), isEmpty);
  });

  test('admission-fee default round-trips with the app default as fallback',
      () async {
    final settings = SettingsRepository(db);
    // No value set yet -> falls back to the constant.
    expect(
        await settings.getInt('admission_fee_default', AppConstants.defaultAdmissionFee),
        AppConstants.defaultAdmissionFee);

    await catalog.setAdmissionFeeDefault(250);
    expect(await settings.getInt('admission_fee_default', 0), 250);
  });
}
