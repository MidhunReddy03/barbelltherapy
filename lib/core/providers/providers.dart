import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/web_themes.dart';
import '../../core/utils/hash_utils.dart';
import '../../data/database.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../data/repositories/checkin_repository.dart';
import '../../data/repositories/dashboard_repository.dart';
import '../../data/repositories/enroll_repository.dart';
import '../../data/repositories/member_profile_repository.dart';
import '../../data/repositories/members_repository.dart';
import '../../data/repositories/messages_composer.dart';
import '../../data/repositories/payments_repository.dart';
import '../../data/repositories/freeze_repository.dart';
import '../../data/repositories/reminders_repository.dart';
import '../../data/repositories/settings_repository.dart';

// ── Database & repositories ────────────────────────────────────────────────

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final settingsRepositoryProvider = Provider<SettingsRepository>(
    (ref) => SettingsRepository(ref.watch(databaseProvider)));

final membersRepositoryProvider = Provider<MembersRepository>(
    (ref) => MembersRepository(ref.watch(databaseProvider)));

final dashboardRepositoryProvider = Provider<DashboardRepository>(
    (ref) => DashboardRepository(ref.watch(databaseProvider)));

final remindersRepositoryProvider = Provider<RemindersRepository>((ref) {
  return RemindersRepository(
    ref.watch(databaseProvider),
    ref.watch(settingsRepositoryProvider),
  );
});

final checkInRepositoryProvider = Provider<CheckInRepository>((ref) {
  return CheckInRepository(ref.watch(databaseProvider));
});

final catalogRepositoryProvider = Provider<CatalogRepository>((ref) {
  return CatalogRepository(
    ref.watch(databaseProvider),
    ref.watch(settingsRepositoryProvider),
  );
});

final enrollRepositoryProvider = Provider<EnrollRepository>((ref) {
  return EnrollRepository(
    ref.watch(databaseProvider),
    ref.watch(settingsRepositoryProvider),
  );
});

final memberProfileRepositoryProvider = Provider<MemberProfileRepository>(
    (ref) => MemberProfileRepository(ref.watch(databaseProvider)));

final paymentsRepositoryProvider = Provider<PaymentsRepository>(
    (ref) => PaymentsRepository(ref.watch(databaseProvider)));

final freezeRepositoryProvider = Provider<FreezeRepository>((ref) {
  return FreezeRepository(
    ref.watch(databaseProvider),
    ref.watch(settingsRepositoryProvider),
  );
});

final messagesComposerProvider = Provider<MessagesComposer>((ref) {
  return MessagesComposer(
    ref.watch(settingsRepositoryProvider),
    ref.watch(remindersRepositoryProvider),
  );
});

// ── Enroll catalog streams (shared by enroll + plans screens) ──────────────

final activePlansProvider = StreamProvider.autoDispose<List<Plan>>((ref) {
  return ref.watch(catalogRepositoryProvider).watchActivePlans();
});

final activeAddonsProvider = StreamProvider.autoDispose<List<Addon>>((ref) {
  return ref.watch(catalogRepositoryProvider).watchActiveAddons();
});

final discountPresetsProvider =
    StreamProvider.autoDispose<List<DiscountPreset>>((ref) {
  return ref.watch(catalogRepositoryProvider).watchDiscountPresets();
});

final allPlansProvider = StreamProvider.autoDispose<List<Plan>>((ref) {
  return ref.watch(catalogRepositoryProvider).watchAllPlans();
});

final allAddonsProvider = StreamProvider.autoDispose<List<Addon>>((ref) {
  return ref.watch(catalogRepositoryProvider).watchAllAddons();
});

final admissionFeeDefaultProvider = StreamProvider.autoDispose<int>((ref) {
  final settings = ref.watch(settingsRepositoryProvider);
  return settings
      .watchAll()
      .asyncMap((_) => settings.getInt('admission_fee_default', 0));
});

// ── Reactive settings ──────────────────────────────────────────────────────

/// Live map of all settings rows.
final settingsMapProvider =
    StreamProvider<Map<String, String>>((ref) {
  return ref.watch(settingsRepositoryProvider).watchAll();
});

final onboardingCompleteProvider = Provider<bool>((ref) {
  final map = ref.watch(settingsMapProvider).value ?? const {};
  return map[SettingKeys.onboardingComplete] == '1';
});

final gymNameProvider = Provider<String>((ref) {
  final map = ref.watch(settingsMapProvider).value ?? const {};
  return map[SettingKeys.gymName] ?? 'Barbell Therapy';
});

final appLockEnabledProvider = Provider<bool>((ref) {
  final map = ref.watch(settingsMapProvider).value ?? const {};
  return map[SettingKeys.appLockEnabled] == '1';
});

final themeModeProvider = Provider<ThemeMode>((ref) {
  final map = ref.watch(settingsMapProvider).value ?? const {};
  switch (map[SettingKeys.themeMode]) {
    case 'light':
      return ThemeMode.light;
    case 'system':
      return ThemeMode.system;
    case 'dark':
    default:
      return ThemeMode.dark;
  }
});

/// Website-only UI theme preset (persisted in settings, ignored on native).
final webThemePresetProvider = Provider<WebThemePreset>((ref) {
  final map = ref.watch(settingsMapProvider).value ?? const {};
  return WebThemePreset.fromId(map[SettingKeys.webThemePreset]);
});

// ── App lock state ─────────────────────────────────────────────────────────

/// Controller for the lock screen. The lock is engaged on launch when
/// enabled, and re-engaged after [AppConstants.lockAfterBackgroundSeconds]
/// in the background.
class LockController extends Notifier<bool> {
  DateTime? _pausedAt;

  @override
  bool build() {
    // Cold start: locked when the feature is enabled.
    return ref.watch(appLockEnabledProvider);
  }

  void onAppPaused() {
    _pausedAt = DateTime.now();
  }

  void onAppResumed() {
    final pausedAt = _pausedAt;
    _pausedAt = null;
    if (pausedAt == null) return;
    if (!ref.read(appLockEnabledProvider)) return;
    final elapsed = DateTime.now().difference(pausedAt);
    if (elapsed.inSeconds >= lockAfterBackgroundSeconds()) {
      state = true;
    }
  }

  int lockAfterBackgroundSeconds() {
    // Kept as a function so Settings can later expose it; constant for now.
    return 60;
  }

  /// Verifies a PIN attempt against the stored hash. Returns true when the
  /// PIN is correct (the caller flips state).
  Future<bool> verifyPin(String pin) async {
    final settings = ref.read(settingsRepositoryProvider);
    final hash = await settings.get(SettingKeys.lockPinHash);
    final salt = await settings.get(SettingKeys.lockPinSalt);
    if (hash == null || salt == null) return true; // no PIN set
    return HashUtils.verifyPin(salt, pin, hash);
  }

  void unlock() => state = false;

  void lock() {
    if (ref.read(appLockEnabledProvider)) state = true;
  }
}

final lockedProvider = NotifierProvider<LockController, bool>(
  LockController.new,
);
