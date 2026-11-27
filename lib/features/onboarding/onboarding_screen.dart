import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/providers/providers.dart';
import '../../core/utils/app_image.dart';
import '../../core/utils/hash_utils.dart';
import '../../core/utils/phone_utils.dart';
import '../../core/widgets/common_widgets.dart';
import '../../data/database.dart';
import '../../data/repositories/settings_repository.dart';
import '../../domain/enums.dart';

/// First-run wizard (spec 6.1): 4 short steps with progress dots.
/// (a) Gym profile, (b) payment QR image, (c) plans + add-ons,
/// (d) language + app lock.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pageController = PageController();
  int _page = 0;

  // Step 1
  final _gymNameController = TextEditingController();
  final _gymPhoneController = TextEditingController();
  final _gymAddressController = TextEditingController();
  String? _logoPath;
  String? _gymNameError;
  String? _gymPhoneError;

  // Step 2
  String? _qrImagePath;

  // Step 3
  List<Plan>? _plans;
  final _planPriceControllers = <int, TextEditingController>{};

  // Step 4
  LanguageCode _language = LanguageCode.en;
  bool _appLock = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadDefaults();
  }

  Future<void> _loadDefaults() async {
    final db = ref.read(databaseProvider);
    final settings = ref.read(settingsRepositoryProvider);
    final plans =
        await (db.select(db.plans)..orderBy([(p) => OrderingTerm.asc(p.sortOrder)]))
            .get();
    final lang = await settings.defaultLanguage();
    if (!mounted) return;
    setState(() {
      _plans = plans;
      _language = lang;
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _gymNameController.dispose();
    _gymPhoneController.dispose();
    _gymAddressController.dispose();
    for (final c in _planPriceControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _next() async {
    if (_page == 0 && !_validateStep1()) return;
    if (_page < 3) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    } else {
      await _finish();
    }
  }

  bool _validateStep1() {
    final name = _gymNameController.text.trim();
    final phone = _gymPhoneController.text.trim();
    final normalized = PhoneUtils.normalize(phone);
    setState(() {
      _gymNameError = name.isEmpty ? 'Gym name is required' : null;
      _gymPhoneError = PhoneUtils.isValid(normalized)
          ? null
          : 'Enter a valid 10-digit mobile number';
    });
    return _gymNameError == null && _gymPhoneError == null;
  }

  Future<void> _syncFromCloudDialog() async {
    final service = ref.read(cloudSyncServiceProvider);
    final wsCtrl = TextEditingController(text: 'barbell-therapy');
    final passCtrl = TextEditingController();
    final urlCtrl = TextEditingController(text: service.resolveDefaultUrl());
    bool busy = false;
    String? err;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Sync from Cloud'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Enter the same Gym Sync ID and Passcode used on your other device.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: wsCtrl,
                decoration: const InputDecoration(labelText: 'Gym Sync ID'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: passCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Sync Passcode'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: urlCtrl,
                decoration: const InputDecoration(labelText: 'Server URL'),
              ),
              if (err != null) ...[
                const SizedBox(height: 8),
                Text(err!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      setDialogState(() {
                        busy = true;
                        err = null;
                      });
                      try {
                        await service.connect(
                          serverUrl: urlCtrl.text.trim(),
                          workspaceId: wsCtrl.text.trim(),
                          passcode: passCtrl.text.trim(),
                        );
                        // Ensure onboarding marks complete if synced gym had it set,
                        // or mark complete if workspace already has plans/members.
                        final settings = ref.read(settingsRepositoryProvider);
                        final done = await settings.get(SettingKeys.onboardingComplete);
                        if (done != '1') {
                          await settings.set(SettingKeys.onboardingComplete, '1');
                        }
                        if (ctx.mounted) Navigator.pop(ctx);
                      } catch (e) {
                        setDialogState(() {
                          busy = false;
                          err = e.toString().replaceFirst('Exception: ', '');
                        });
                      }
                    },
              child: Text(busy ? 'Syncing…' : 'Sync & Open'),
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _copyToAppStorage(XFile? picked, String prefix) async {
    // AppImage persists files on Android and data URIs on web; QR and
    // logo must stay lossless, so no compression here.
    return AppImage.store(picked, prefix: prefix, compress: false);
  }

  Future<void> _pickImage({required bool isLogo}) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    final path = await _copyToAppStorage(picked, isLogo ? 'logo' : 'qr');
    if (path == null) return;
    setState(() {
      if (isLogo) {
        _logoPath = path;
      } else {
        _qrImagePath = path;
      }
    });
  }

  Future<void> _finish() async {
    setState(() => _saving = true);

    if (_appLock) {
      final ok = await _ensurePinSet();
      if (!ok) {
        setState(() => _saving = false);
        return;
      }
    }

    final settings = ref.read(settingsRepositoryProvider);
    final db = ref.read(databaseProvider);

    // Plans edited in step 3 are written back to the seeded rows.
    await db.batch((batch) {
      for (final plan in _plans ?? const <Plan>[]) {
        final controller = _planPriceControllers[plan.id];
        final newPrice = int.tryParse(controller?.text ?? '') ?? plan.price;
        final newName = plan.name; // names are editable below in a later pass
        batch.update(
          db.plans,
          PlansCompanion(
            price: Value(newPrice),
            name: Value(newName),
          ),
          where: (tbl) => tbl.id.equals(plan.id),
        );
      }
    });

    await settings.setAll({
      SettingKeys.gymName: _gymNameController.text.trim(),
      SettingKeys.gymPhone: PhoneUtils.normalize(_gymPhoneController.text),
      SettingKeys.gymAddress: _gymAddressController.text.trim().isEmpty
          ? null
          : _gymAddressController.text.trim(),
      SettingKeys.logoPath: _logoPath,
      SettingKeys.qrImagePath: _qrImagePath,
      SettingKeys.defaultLanguage: _language == LanguageCode.te ? 'te' : 'en',
      SettingKeys.appLockEnabled: _appLock ? '1' : '0',
      SettingKeys.onboardingComplete: '1',
    });

    if (!mounted) return;
    // Router redirect sends the user to /home once onboarding_complete = 1.
    setState(() => _saving = false);
  }

  Future<bool> _ensurePinSet() async {
    final settings = ref.read(settingsRepositoryProvider);
    final existingHash = await settings.get(SettingKeys.lockPinHash);
    if (existingHash != null) return true;

    final pin = await _promptPinDialog();
    if (pin == null) return false;

    final salt = HashUtils.generateSalt();
    await settings.setAll({
      SettingKeys.lockPinSalt: salt,
      SettingKeys.lockPinHash: HashUtils.hashPin(salt, pin),
    });
    return true;
  }

  Future<String?> _promptPinDialog() async {
    final c1 = TextEditingController();
    final c2 = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Set your lock PIN'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: c1,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 6,
                decoration: const InputDecoration(
                    labelText: 'PIN (4-6 digits)', counterText: ''),
                validator: (v) =>
                    v != null && v.length >= 4 ? null : 'At least 4 digits',
              ),
              TextFormField(
                controller: c2,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 6,
                decoration: const InputDecoration(
                    labelText: 'Confirm PIN', counterText: ''),
                validator: (v) => v == c1.text ? null : 'PINs do not match',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(context, c1.text);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Welcome to Barbell Therapy 👋', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Row(
                    children: List.generate(4, (i) {
                      final active = i <= _page;
                      return Expanded(
                        child: Container(
                          height: 4,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            color: active
                                ? theme.colorScheme.primary
                                : theme.colorScheme.outline,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Form(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (i) => setState(() => _page = i),
                  children: [
                    _buildStep1(theme),
                    _buildStep2(theme),
                    _buildStep3(theme),
                    _buildStep4(theme),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  if (_page > 0)
                    SecondaryButton(
                      label: 'Back',
                      onPressed: () => _pageController.previousPage(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOut,
                      ),
                    ),
                  const Spacer(),
                  PrimaryButton(
                    label: _page == 3
                        ? (_saving ? 'Saving…' : 'Finish')
                        : 'Next',
                    onPressed: _saving ? null : _next,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep1(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SectionCard(
          onTap: _syncFromCloudDialog,
          borderColor: theme.colorScheme.primary.withValues(alpha: 0.45),
          child: Row(
            children: [
              Icon(Icons.cloud_download_outlined,
                  color: theme.colorScheme.primary, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Already set up on another device?',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontSize: 14)),
                    Text('Tap to sync your gym from Cloud',
                        style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: theme.colorScheme.primary),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text('Tell us about your gym', style: theme.textTheme.titleMedium),
        const SizedBox(height: 16),
        TextFormField(
          controller: _gymNameController,
          decoration: InputDecoration(
            labelText: 'Gym name *',
            errorText: _gymNameError,
          ),
          onChanged: (_) {
            if (_gymNameError != null) setState(() => _gymNameError = null);
          },
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _gymPhoneController,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(
            labelText: 'Gym phone *',
            hintText: '10-digit mobile number',
            errorText: _gymPhoneError,
          ),
          onChanged: (_) {
            if (_gymPhoneError != null) setState(() => _gymPhoneError = null);
          },
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _gymAddressController,
          maxLines: 2,
          decoration: const InputDecoration(labelText: 'Address'),
        ),
        const SizedBox(height: 20),
        _ImagePickTile(
          title: 'Gym logo (optional)',
          subtitle: 'Shown on receipts and reports',
          path: _logoPath,
          onPick: () => _pickImage(isLogo: true),
          onRemove: () => setState(() => _logoPath = null),
        ),
      ],
    );
  }

  Widget _buildStep2(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Payment QR image', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Upload a photo of your UPI payment QR. Members scan it to pay you. '
          'You can skip this and add it later in Settings.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        _ImagePickTile(
          title: 'Payment QR',
          subtitle: _qrImagePath == null
              ? 'No QR added yet'
              : 'QR image selected',
          path: _qrImagePath,
          onPick: () => _pickImage(isLogo: false),
          onRemove: () => setState(() => _qrImagePath = null),
        ),
      ],
    );
  }

  Widget _buildStep3(ThemeData theme) {
    final plans = _plans;
    if (plans == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Your plans', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'We created 4 starter plans. Set the prices your gym charges — '
          'you can change everything later.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        ...plans.map((plan) {
          final controller = _planPriceControllers.putIfAbsent(
            plan.id,
            () => TextEditingController(text: '${plan.price}'),
          );
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SectionCard(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(plan.name, style: theme.textTheme.titleMedium),
                        Text(
                          '${plan.durationMonths} month${plan.durationMonths > 1 ? 's' : ''}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 110,
                    child: TextFormField(
                      controller: controller,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Price ₹',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildStep4(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Messages & security', style: theme.textTheme.titleMedium),
        const SizedBox(height: 16),
        Text('Default language for WhatsApp messages',
            style: theme.textTheme.bodyMedium),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 'en', label: Text('English')),
            ButtonSegment(value: 'te', label: Text('తెలుగు')),
          ],
          selected: {_language == LanguageCode.te ? 'te' : 'en'},
          onSelectionChanged: (selection) {
            setState(() {
              _language =
                  selection.first == 'te' ? LanguageCode.te : LanguageCode.en;
            });
          },
        ),
        const SizedBox(height: 24),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('App lock (PIN / biometric)'),
          subtitle: const Text('Lock the app when you leave it for a minute'),
          value: _appLock,
          onChanged: (v) => setState(() => _appLock = v),
        ),
        if (_appLock)
          Text(
            'You\'ll set a PIN in the next step.',
            style: theme.textTheme.bodySmall,
          ),
      ],
    );
  }
}

class _ImagePickTile extends StatelessWidget {
  const _ImagePickTile({
    required this.title,
    required this.subtitle,
    required this.path,
    required this.onPick,
    required this.onRemove,
  });

  final String title;
  final String subtitle;
  final String? path;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SectionCard(
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            clipBehavior: Clip.antiAlias,
            child: path != null
                ? AppImage.view(path)
                : Icon(Icons.image_outlined,
                    color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                Text(subtitle, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          TextButton(onPressed: onPick, child: const Text('Choose')),
          if (path != null)
            IconButton(
              onPressed: onRemove,
              icon: const Icon(Icons.close),
              tooltip: 'Remove',
            ),
        ],
      ),
    );
  }
}
