import 'package:drift/drift.dart';

import '../../core/constants/app_constants.dart';
import '../../domain/enums.dart';
import '../database.dart';

/// Keys used in the settings table. Defaults are returned when a key is
/// missing so fresh installs work without pre-seeding every row.
abstract final class SettingKeys {
  static const gymName = 'gym_name';
  static const gymPhone = 'gym_phone';
  static const gymAddress = 'gym_address';
  static const logoPath = 'logo_path';
  static const qrImagePath = 'qr_image_path';
  static const defaultLanguage = 'default_language'; // 'en' | 'te'
  static const reminderOffsets = 'reminder_offsets'; // JSON [{offset,enabled}]
  static const inactivityDays = 'inactivity_days';
  static const expiringSoonWindow = 'expiring_soon_window';
  static const maxFreezesPerSubscription = 'max_freezes_per_subscription';
  static const minFreezeDays = 'min_freeze_days';
  static const themeMode = 'theme_mode'; // 'dark' | 'light' | 'system'
  static const appLockEnabled = 'app_lock_enabled'; // '0' | '1'
  static const lockPinHash = 'lock_pin_hash';
  static const lockPinSalt = 'lock_pin_salt';
  static const memberSeq = 'member_seq';
  static const lastBackupAt = 'last_backup_at'; // ISO datetime
  static const backupEmail = 'backup_email'; // Gmail address for backup
  static const onboardingComplete = 'onboarding_complete'; // '0' | '1'
  static const discountPresets = 'discount_presets'; // JSON array
}

/// Typed access to the key-value settings store.
class SettingsRepository {
  SettingsRepository(this._db);

  final AppDatabase _db;

  /// Live map of all settings for reactive UI.
  Stream<Map<String, String>> watchAll() {
    final query = _db.select(_db.settingsEntries);
    return query.watch().map((rows) => {
          for (final row in rows)
            if (row.value != null) row.key: row.value!,
        });
  }

  Future<Map<String, String>> getAll() async {
    final rows = await _db.select(_db.settingsEntries).get();
    return {
      for (final row in rows)
        if (row.value != null) row.key: row.value!,
    };
  }

  Future<String?> get(String key) async {
    final row = await (_db.select(_db.settingsEntries)
          ..where((s) => s.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  Future<void> set(String key, String? value) async {
    await _db.into(_db.settingsEntries).insert(
      SettingsEntriesCompanion.insert(key: key, value: Value(value)),
      mode: InsertMode.insertOrReplace,
    );
  }

  Future<void> setAll(Map<String, String?> values) async {
    await _db.batch((batch) {
      for (final entry in values.entries) {
        batch.insert(
          _db.settingsEntries,
          SettingsEntriesCompanion.insert(
            key: entry.key,
            value: Value(entry.value),
          ),
          mode: InsertMode.insertOrReplace,
        );
      }
    });
  }

  // ── Typed helpers ─────────────────────────────────────────────────────────

  Future<int> getInt(String key, int fallback) async {
    final raw = await get(key);
    return int.tryParse(raw ?? '') ?? fallback;
  }

  Future<int> expiringSoonWindow() =>
      getInt(SettingKeys.expiringSoonWindow, AppConstants.defaultExpiringSoonWindowDays);

  Future<int> inactivityDays() =>
      getInt(SettingKeys.inactivityDays, AppConstants.defaultInactivityDays);

  Future<int> maxFreezesPerSubscription() => getInt(
      SettingKeys.maxFreezesPerSubscription,
      AppConstants.defaultMaxFreezesPerSubscription);

  Future<int> minFreezeDays() =>
      getInt(SettingKeys.minFreezeDays, AppConstants.defaultMinFreezeDays);

  Future<int> admissionFeeDefault() =>
      getInt('admission_fee_default', AppConstants.defaultAdmissionFee);

  Future<LanguageCode> defaultLanguage() async {
    final raw = await get(SettingKeys.defaultLanguage);
    return raw == 'te' ? LanguageCode.te : LanguageCode.en;
  }

  Future<ThemeAppMode> themeMode() async {
    final raw = await get(SettingKeys.themeMode);
    return ThemeAppModeX.fromString(raw);
  }

  Future<bool> isAppLockEnabled() async =>
      (await get(SettingKeys.appLockEnabled)) == '1';

  /// Reminder offsets as parsed JSON-ish rows: [{offset, enabled}].
  Future<List<ReminderOffsetConfig>> reminderOffsets() async {
    final raw = await get(SettingKeys.reminderOffsets);
    if (raw == null || raw.isEmpty) {
      return AppConstants.defaultReminderOffsets
          .map((o) => ReminderOffsetConfig(offset: o, enabled: true))
          .toList();
    }
    try {
      return decodeReminderOffsets(raw);
    } catch (_) {
      return AppConstants.defaultReminderOffsets
          .map((o) => ReminderOffsetConfig(offset: o, enabled: true))
          .toList();
    }
  }

  /// Next sequential member code, e.g. `GYM-0007`.
  Future<String> nextMemberCode() async {
    final current = await getInt(SettingKeys.memberSeq, 0);
    final next = current + 1;
    return '${AppConstants.memberCodePrefix}-${next.toString().padLeft(4, '0')}';
  }

  Future<void> bumpMemberSeq() async {
    final current = await getInt(SettingKeys.memberSeq, 0);
    await set(SettingKeys.memberSeq, '${current + 1}');
  }
}

class ReminderOffsetConfig {
  const ReminderOffsetConfig({required this.offset, required this.enabled});

  final int offset;
  final bool enabled;

  String encode() => '{"offset":$offset,"enabled":${enabled ? 1 : 0}}';

  static ReminderOffsetConfig decodeJson(Map<String, dynamic> json) =>
      ReminderOffsetConfig(
        offset: (json['offset'] as num?)?.toInt() ?? 0,
        enabled: json['enabled'] != 0 && json['enabled'] != false,
      );
}

String encodeReminderOffsets(List<ReminderOffsetConfig> configs) =>
    '[${configs.map((c) => c.encode()).join(',')}]';

List<ReminderOffsetConfig> decodeReminderOffsets(String raw) {
  // Tiny hand-rolled decoder to avoid a dart:convert list-typing dance; the
  // format is always [{offset:int,enabled:int},...].
  final result = <ReminderOffsetConfig>[];
  final objectPattern = RegExp(r'\{"offset":(-?\d+),"enabled":(0|1)\}');
  for (final m in objectPattern.allMatches(raw)) {
    result.add(ReminderOffsetConfig(
      offset: int.parse(m.group(1)!),
      enabled: m.group(2) == '1',
    ));
  }
  return result;
}

/// App theme preference stored in settings.
enum ThemeAppMode { dark, light, system }

extension ThemeAppModeX on ThemeAppMode {
  String get storageValue {
    switch (this) {
      case ThemeAppMode.dark:
        return 'dark';
      case ThemeAppMode.light:
        return 'light';
      case ThemeAppMode.system:
        return 'system';
    }
  }

  static ThemeAppMode fromString(String? raw) {
    switch (raw) {
      case 'light':
        return ThemeAppMode.light;
      case 'system':
        return ThemeAppMode.system;
      case 'dark':
      default:
        return ThemeAppMode.dark; // dark is the default (spec 3)
    }
  }
}
