import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/providers/providers.dart';
import '../../core/utils/hash_utils.dart';
import '../../core/utils/phone_utils.dart';
import '../../core/widgets/common_widgets.dart';
import '../../data/repositories/settings_repository.dart';
import '../../domain/enums.dart';

/// Settings (spec 6.12, Phase-1 scope): gym profile, payment QR, appearance,
/// security (app lock + PIN), default language, and About with the data
/// notice. The template editor and reminder-rule editor arrive in Phase 4;
/// backup/restore in Phase 6.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _gymName = TextEditingController();
  final _gymPhone = TextEditingController();
  final _gymAddress = TextEditingController();
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = ref.read(settingsRepositoryProvider);
    final all = await settings.getAll();
    if (!mounted) return;
    setState(() {
      _gymName.text = all[SettingKeys.gymName] ?? '';
      _gymPhone.text = PhoneUtils.display(all[SettingKeys.gymPhone] ?? '');
      _gymAddress.text = all[SettingKeys.gymAddress] ?? '';
      _loaded = true;
    });
  }

  @override
  void dispose() {
    _gymName.dispose();
    _gymPhone.dispose();
    _gymAddress.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    final settings = ref.read(settingsRepositoryProvider);
    final name = _gymName.text.trim();
    final phone = PhoneUtils.normalize(_gymPhone.text);
    if (name.isEmpty || !PhoneUtils.isValid(phone)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Gym name and a valid 10-digit phone are required.')),
        );
      }
      return;
    }
    await settings.setAll({
      SettingKeys.gymName: name,
      SettingKeys.gymPhone: phone,
      SettingKeys.gymAddress: _gymAddress.text.trim(),
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gym profile saved')),
      );
    }
  }

  Future<void> _setThemeMode(ThemeAppMode mode) async {
    await ref
        .read(settingsRepositoryProvider)
        .set(SettingKeys.themeMode, mode.storageValue);
  }

  Future<void> _toggleAppLock(bool enable) async {
    final settings = ref.read(settingsRepositoryProvider);
    if (enable) {
      final ok = await _changePinFlow(requireExisting: false);
      if (!ok) return;
      await settings.set(SettingKeys.appLockEnabled, '1');
    } else {
      await settings.set(SettingKeys.appLockEnabled, '0');
    }
  }

  /// Returns true when a (new) PIN was saved.
  Future<bool> _changePinFlow({required bool requireExisting}) async {
    final settings = ref.read(settingsRepositoryProvider);
    final oldHash = await settings.get(SettingKeys.lockPinHash);

    if (requireExisting && oldHash != null) {
      final oldPin = await _promptPinDialog(title: 'Current PIN');
      if (oldPin == null) return false;
      final salt = await settings.get(SettingKeys.lockPinSalt) ?? '';
      if (!HashUtils.verifyPin(salt, oldPin, oldHash)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Current PIN is wrong.')),
          );
        }
        return false;
      }
    }

    final newPin = await _promptPinDialog(title: 'New PIN (4-6 digits)');
    if (newPin == null) return false;
    final salt = HashUtils.generateSalt();
    await settings.setAll({
      SettingKeys.lockPinSalt: salt,
      SettingKeys.lockPinHash: HashUtils.hashPin(salt, newPin),
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PIN updated')),
      );
    }
    return true;
  }

  Future<String?> _promptPinDialog({required String title}) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          obscureText: true,
          maxLength: 6,
          decoration: const InputDecoration(
            labelText: 'PIN',
            counterText: '',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final v = controller.text.trim();
              if (v.length >= 4 && v.length <= 6) {
                Navigator.pop(context, v);
              }
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _setDefaultLanguage(LanguageCode lang) async {
    await ref
        .read(settingsRepositoryProvider)
        .set(SettingKeys.defaultLanguage, lang == LanguageCode.te ? 'te' : 'en');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settingsMap = ref.watch(settingsMapProvider).value ?? const {};
    final lockEnabled = settingsMap[SettingKeys.appLockEnabled] == '1';
    final lang = settingsMap[SettingKeys.defaultLanguage] == 'te'
        ? LanguageCode.te
        : LanguageCode.en;
    final themeMode = ThemeAppModeX.fromString(settingsMap[SettingKeys.themeMode]);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Gym profile', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                TextField(
                  controller: _gymName,
                  decoration: const InputDecoration(labelText: 'Gym name'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _gymPhone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Gym phone'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _gymAddress,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Address'),
                ),
                const SizedBox(height: 8),
                PrimaryButton(
                  label: 'Save profile',
                  onPressed: _saveProfile,
                ),
                const SizedBox(height: 24),

                Text('Appearance', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 'dark', label: FittedBox(fit: BoxFit.scaleDown, child: Text('Dark', maxLines: 1))),
                    ButtonSegment(value: 'light', label: FittedBox(fit: BoxFit.scaleDown, child: Text('Light', maxLines: 1))),
                    ButtonSegment(value: 'system', label: FittedBox(fit: BoxFit.scaleDown, child: Text('System', maxLines: 1))),
                  ],
                  selected: {themeMode.storageValue},
                  onSelectionChanged: (s) async {
                    await _setThemeMode(ThemeAppModeX.fromString(s.first));
                  },
                ),
                const SizedBox(height: 24),

                Text('Messages', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Default message language'),
                  subtitle: const Text(
                      'Used for reminders when a member has no preference'),
                  trailing: SegmentedButton<String>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: 'en', label: Text('EN')),
                      ButtonSegment(value: 'te', label: Text('తె')),
                    ],
                    selected: {lang == LanguageCode.te ? 'te' : 'en'},
                    onSelectionChanged: (s) async {
                      await _setDefaultLanguage(
                          s.first == 'te' ? LanguageCode.te : LanguageCode.en);
                    },
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Message templates'),
                  subtitle: const Text(
                      'Customize English + Telugu WhatsApp notification copy'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.go('/more/templates'),
                ),
                const SizedBox(height: 24),

                Text('Security', style: theme.textTheme.titleMedium),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('App lock'),
                  subtitle: const Text(
                      'PIN + biometrics. Re-locks after '
                      '${AppConstants.lockAfterBackgroundSeconds}s in background'),
                  value: lockEnabled,
                  onChanged: _toggleAppLock,
                ),
                if (lockEnabled)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Change PIN'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _changePinFlow(requireExisting: true),
                  ),
                const SizedBox(height: 24),

                Text('About', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(AppConstants.appName),
                  subtitle: const Text(
                    'Version ${AppConstants.appVersion}\n'
                    'Your data is stored only on this phone. Back it up '
                    'regularly (Backup arrives in Phase 6).',
                  ),
                  isThreeLine: true,
                ),
              ],
            ),
    );
  }
}
