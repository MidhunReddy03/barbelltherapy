import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/providers/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/app_date_utils.dart';
import '../../../core/utils/app_formatters.dart';
import '../../../core/utils/app_image.dart';
import '../../../core/utils/phone_utils.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../data/database.dart';
import '../../../data/repositories/catalog_repository.dart';
import '../../../data/repositories/enroll_repository.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../../domain/enums.dart';
import '../../../domain/pricing_calculator.dart';

/// Arguments handed to the success screen after saving.
class EnrollSuccessArgs {
  const EnrollSuccessArgs({required this.draft, required this.result});

  final EnrollDraft draft;
  final EnrollResult result;
}

/// Enroll new member (spec 6.4): 4-step wizard with a progress bar.
/// Back navigation preserves everything; leaving mid-flow asks to confirm.
class EnrollScreen extends ConsumerStatefulWidget {
  const EnrollScreen({super.key});

  @override
  ConsumerState<EnrollScreen> createState() => _EnrollScreenState();
}

class _EnrollScreenState extends ConsumerState<EnrollScreen> {
  final _pageController = PageController();
  int _page = 0;

  EnrollDraft _draft = EnrollDraft();

  // Step 1 controls (kept outside the draft; synced on change).
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _ageController = TextEditingController();
  final _notesController = TextEditingController();
  String? _nameError;
  String? _phoneError;
  String? _ageError;
  bool _duplicateCheckBusy = false;
  String? _duplicate;

  // Step 2 controls.
  final _admissionController = TextEditingController();
  final _discountController = TextEditingController();

  // Step 3 controls.
  final _amountController = TextEditingController();

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadAdmissionDefault();
    _amountController.addListener(_syncAmount);
    _admissionController.addListener(_syncAdmission);
    _discountController.addListener(_syncDiscount);
  }

  Future<void> _loadAdmissionDefault() async {
    final fee = await ref.read(enrollRepositoryProvider).admissionFeeDefault();
    if (!mounted) return;
    _admissionController.text = fee == 0 ? '0' : '$fee';
    _syncAdmission();
  }

  void _syncAmount() {
    final v = int.tryParse(_amountController.text) ?? 0;
    _draft = _draft.copyWith(amountPaid: v);
  }

  void _syncAdmission() {
    final v = int.tryParse(_admissionController.text);
    if (v != null && v >= 0) {
      _draft = _draft.copyWith(admissionFee: v);
    }
  }

  void _syncDiscount() {
    final v = int.tryParse(_discountController.text) ?? 0;
    _draft = _draft.copyWith(
      discountValue:
          _draft.discountType == DiscountType.none ? 0 : (v < 0 ? 0 : v),
    );
    setState(() {});
  }

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _ageController.dispose();
    _notesController.dispose();
    _admissionController.dispose();
    _discountController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  // ── Validation ────────────────────────────────────────────────────────────

  bool _validateStep1() {
    final name = _nameController.text.trim();
    final age = int.tryParse(_ageController.text);
    setState(() {
      _nameError = name.isEmpty ? 'Name is required' : null;
      _phoneError = PhoneUtils.isValid(_draft.phone)
          ? null
          : 'Enter a valid 10-digit mobile number';
      _ageError = age == null || (age >= 10 && age <= 90)
          ? null
          : 'Age must be between 10 and 90';
    });
    return _nameError == null && _phoneError == null && _ageError == null;
  }

  Future<void> _checkDuplicate() async {
    final phone = PhoneUtils.normalize(_phoneController.text);
    if (!PhoneUtils.isValid(phone)) {
      setState(() => _duplicate = null);
      return;
    }
    setState(() => _duplicateCheckBusy = true);
    final dup = await ref
        .read(enrollRepositoryProvider)
        .findDuplicatePhone(phone);
    if (!mounted) return;
    setState(() {
      _duplicate = dup;
      _duplicateCheckBusy = false;
    });
  }

  Future<void> _pickPhoto({required ImageSource source}) async {
    final picked = await ImagePicker().pickImage(source: source);
    if (picked == null) return;
    final path = await AppImage.store(picked, prefix: 'member');
    if (!mounted || path == null) return;
    setState(() => _draft = _draft.copyWith(photoPath: path));
  }

  Future<void> _chooseStartDate() async {
    final minDate =
        AppDateUtils.today().subtract(const Duration(days: 365));
    final picked = await showDatePicker(
      context: context,
      initialDate: _draft.startDate,
      firstDate: minDate,
      lastDate: AppDateUtils.today().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() => _draft = _draft.copyWith(startDate: picked));
  }

  Future<void> _applyPreset(DiscountPreset preset) async {
    setState(() {
      _draft = _draft.copyWith(
        discountType: preset.type,
        discountValue: preset.value,
      );
      _discountController.text = '${preset.value}';
    });
  }

  // ── Navigation ────────────────────────────────────────────────────────────

  Future<bool> _canLeave() async {
    if (_page == 0 &&
        _nameController.text.isEmpty &&
        _phoneController.text.isEmpty &&
        _draft.photoPath == null) {
      return true; // nothing entered
    }
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard this enrollment?'),
        content: const Text(
            'The details you entered so far will be lost.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return leave ?? false;
  }

  void _next() {
    if (_page == 0 && !_validateStep1()) return;
    if (_page < 3) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    } else {
      _confirmAndEnroll();
    }
  }

  Future<void> _confirmAndEnroll() async {
    setState(() => _saving = true);
    try {
      final result =
          await ref.read(enrollRepositoryProvider).enroll(_draft);
      if (!mounted) return;
      context.pushReplacement('/members/enroll/success',
          extra: EnrollSuccessArgs(draft: _draft, result: result));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save the enrollment: $e')),
      );
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titles = ['Member details', 'Choose plan', 'Payment', 'Review'];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _canLeave() && mounted) {
          // ignore: use_build_context_synchronously
          context.pop();
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.bgDark,
        appBar: AppBar(
          backgroundColor: AppColors.bgDark,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              final canLeave = await _canLeave();
              if (!context.mounted) return;
              if (canLeave) {
                context.pop();
              }
            },
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titles[_page].toUpperCase(),
                style: AppTheme.dsp(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimaryDark,
                  letterSpacing: 0.04,
                ),
              ),
              Text(
                'Step ${_page + 1} of 4${_draft.name.isNotEmpty ? ' · ${_draft.name}' : ''}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: AppColors.textSecondaryDark,
                ),
              ),
            ],
          ),
        ),
        body: Column(
          children: [
            // 4 step bars (HTML style: 5px height, 3px radius, #D98A5B active, #32373D inactive)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 10),
              child: Row(
                children: List.generate(4, (i) {
                  return Expanded(
                    child: Container(
                      height: 5,
                      margin: EdgeInsets.only(right: i < 3 ? 6 : 0),
                      decoration: BoxDecoration(
                        color: i <= _page
                            ? AppColors.accent
                            : AppColors.borderDark,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  );
                }),
              ),
            ),
            Expanded(
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
            // Bottom Action Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: AppColors.surfaceDark,
                border: Border(top: BorderSide(color: AppColors.borderDark)),
              ),
              child: SafeArea(
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
                    if (_page > 0) const SizedBox(width: 12),
                    if (_page >= 1 && _draft.pricing != null) ...[
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('TOTAL', style: AppTheme.cap(fontSize: 10)),
                          Text(
                            AppFormatters.money(_draft.pricing!.total),
                            style: AppTheme.dsp(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimaryDark,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                    ] else
                      const Spacer(),
                    PrimaryButton(
                      label: _page == 3
                          ? (_saving ? 'Saving…' : 'Confirm & Enroll')
                          : 'Continue',
                      onPressed: _saving
                          ? null
                          : () {
                              if (_page == 0) _checkDuplicate();
                              _next();
                            },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Step 1: details ───────────────────────────────────────────────────────

  Widget _buildStep1(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            GestureDetector(
              onTap: () => _photoSourceSheet(),
              child: Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                clipBehavior: Clip.antiAlias,
                child: _draft.photoPath != null
                    ? AppImage.view(_draft.photoPath)
                    : const Icon(Icons.add_a_photo_outlined, size: 28),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Photo (optional)\nCompressed automatically',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _nameController,
          decoration: InputDecoration(
            labelText: 'Name *',
            errorText: _nameError,
          ),
          onChanged: (v) {
            _draft = _draft.copyWith(name: v);
            if (_nameError != null) setState(() => _nameError = null);
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(
            labelText: 'Phone *',
            hintText: '10-digit mobile number',
            errorText: _phoneError,
            suffixIcon: _duplicateCheckBusy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : null,
          ),
          onChanged: (v) {
            _draft =
                _draft.copyWith(phone: PhoneUtils.normalize(v));
            if (_phoneError != null) setState(() => _phoneError = null);
          },
        ),
        if (_duplicate != null) ...[
          const SizedBox(height: 8),
          _Banner(
            color: AppColors.statusExpiring,
            text: 'This phone is already registered to $_duplicate. '
                'You can still continue — it will create a second member.',
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _ageController,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'Age (10–90)',
            errorText: _ageError,
          ),
          onChanged: (v) {
            _draft = _draft.copyWith(age: int.tryParse(v));
            if (_ageError != null) setState(() => _ageError = null);
          },
        ),
        const SizedBox(height: 12),
        Text('GENDER', style: AppTheme.cap()),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: 'Male',
                label: FittedBox(fit: BoxFit.scaleDown, child: Text('Male', maxLines: 1)),
              ),
              ButtonSegment(
                value: 'Female',
                label: FittedBox(fit: BoxFit.scaleDown, child: Text('Female', maxLines: 1)),
              ),
              ButtonSegment(
                value: 'Other',
                label: FittedBox(fit: BoxFit.scaleDown, child: Text('Other', maxLines: 1)),
              ),
            ],
            selected: {_draft.gender ?? 'Male'},
            onSelectionChanged: (s) => setState(
                () => _draft = _draft.copyWith(gender: s.first)),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _notesController,
          maxLines: 2,
          decoration: const InputDecoration(labelText: 'Notes (optional)'),
          onChanged: (v) =>
              _draft = _draft.copyWith(notes: v.isEmpty ? null : v),
        ),
      ],
    );
  }

  Future<void> _photoSourceSheet() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            if (_draft.photoPath != null)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Remove photo'),
                onTap: () => Navigator.pop(context, null),
              ),
          ],
        ),
      ),
    );
    if (source == null) {
      setState(() => _draft = _draft.copyWith(photoPath: null));
      return;
    }
    await _pickPhoto(source: source);
  }

  // ── Step 2: plan & pricing ────────────────────────────────────────────────

  Widget _buildStep2(ThemeData theme) {
    final plansAsync = ref.watch(activePlansProvider);
    final addonsAsync = ref.watch(activeAddonsProvider);
    final presetsAsync = ref.watch(discountPresetsProvider);

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        Text('PLANS', style: AppTheme.cap()),
        const SizedBox(height: 8),
        plansAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text('Could not load plans: $e'),
          data: (plans) => plans.isEmpty
              ? const Text('No active plans — add one in Plans & Add-ons.')
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final cols = kIsWeb && constraints.maxWidth >= 680 ? 4 : 2;
                    return GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: kIsWeb
                          ? SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: cols,
                              mainAxisSpacing: 10,
                              crossAxisSpacing: 10,
                              mainAxisExtent: 124,
                            )
                          : const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              mainAxisSpacing: 10,
                              crossAxisSpacing: 10,
                              childAspectRatio: 1.25,
                            ),
                      itemCount: plans.length,
                      itemBuilder: (context, i) {
                        final plan = plans[i];
                        return _PlanCard(
                          plan: plan,
                          selected: _draft.plan?.id == plan.id,
                          onTap: () => setState(() {
                            _draft = _draft.copyWith(plan: plan);
                            _amountController.text =
                                '${_draft.pricing?.total ?? plan.price}';
                          }),
                        );
                      },
                    );
                  },
                ),
        ),
        const SizedBox(height: 14),
        // Date range card matching page_fa9ca1ec.html
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surfaceDark,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.borderDark),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              InkWell(
                onTap: _chooseStartDate,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('STARTS', style: AppTheme.cap()),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            AppFormatters.date(_draft.startDate),
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimaryDark,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.edit_calendar_outlined, size: 16, color: AppColors.textSecondaryDark),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const Icon(Icons.arrow_forward, color: AppColors.textSecondaryDark, size: 20),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('ENDS (AUTO)', style: AppTheme.cap()),
                  const SizedBox(height: 2),
                  Text(
                    _draft.endDate == null
                        ? '—'
                        : AppFormatters.date(_draft.endDate!),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.accentHighlight,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text('ADD-ONS', style: AppTheme.cap()),
        const SizedBox(height: 8),
        addonsAsync.maybeWhen(
          loading: () => const SizedBox(),
          orElse: () {
            final addons = addonsAsync.value ?? const <Addon>[];
            if (addons.isEmpty) {
              return Text('No add-ons configured.',
                  style: theme.textTheme.bodySmall);
            }
            return Container(
              decoration: BoxDecoration(
                color: AppColors.surfaceDark,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.borderDark),
              ),
              child: Column(
                children: [
                  for (int i = 0; i < addons.length; i++) ...[
                    if (i > 0) const Divider(height: 1, color: AppColors.borderDark),
                    _AddonTile(
                      addon: addons[i],
                      selected: _draft.addonIds.any((a) => a.id == addons[i].id),
                      onChanged: (selected) {
                        setState(() {
                          final list = [..._draft.addonIds];
                          if (selected) {
                            list.add(addons[i]);
                          } else {
                            list.removeWhere((a) => a.id == addons[i].id);
                          }
                          _draft = _draft.copyWith(addonIds: list);
                          _amountController.text =
                              '${_draft.pricing?.total ?? 0}';
                        });
                      },
                    ),
                  ],
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        // Admission fee & Discount card
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surfaceDark,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.borderDark),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _admissionController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Admission fee ₹'),
              ),
              const SizedBox(height: 14),
              Text('DISCOUNT', style: AppTheme.cap()),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: 'none',
                      label: FittedBox(fit: BoxFit.scaleDown, child: Text('None', maxLines: 1)),
                    ),
                    ButtonSegment(
                      value: 'flat',
                      label: FittedBox(fit: BoxFit.scaleDown, child: Text('₹ Flat', maxLines: 1)),
                    ),
                    ButtonSegment(
                      value: 'percent',
                      label: FittedBox(fit: BoxFit.scaleDown, child: Text('% Off', maxLines: 1)),
                    ),
                  ],
                  selected: {_draft.discountType.name},
                  onSelectionChanged: (s) {
                    setState(() {
                      _draft = _draft.copyWith(
                        discountType: DiscountType.values
                            .firstWhere((d) => d.name == s.first),
                      );
                      if (_draft.discountType == DiscountType.none) {
                        _discountController.text = '';
                        _draft = _draft.copyWith(discountValue: 0);
                      }
                      _amountController.text =
                          '${_draft.pricing?.total ?? 0}';
                    });
                  },
                ),
              ),
              if (_draft.discountType != DiscountType.none) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _discountController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: _draft.discountType == DiscountType.flat
                        ? 'Discount ₹'
                        : 'Discount %',
                  ),
                ),
              ],
              if (presetsAsync.value != null && presetsAsync.value!.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final preset in presetsAsync.value!)
                      ActionChip(
                        backgroundColor: AppColors.surfaceRaisedDark,
                        side: const BorderSide(color: AppColors.borderDark),
                        label: Text(preset.chipLabel, style: const TextStyle(color: AppColors.textPrimaryDark, fontSize: 12)),
                        onPressed: () => _applyPreset(preset),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ── Step 3: payment ───────────────────────────────────────────────────────

  Widget _buildStep3(ThemeData theme) {
    final pricing = _draft.pricing;
    if (pricing == null) {
      return const Center(child: Text('Pick a plan first.'));
    }
    final due = PricingCalculator.due(total: pricing.total, paid: _draft.paid);

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        // Summary Breakdown Card matching page_4d30e0b8.html
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surfaceDark,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.borderDark),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SummaryRow(
                label: _draft.plan?.name ?? 'Plan',
                value: AppFormatters.money(_draft.plan?.price ?? 0),
              ),
              for (final addon in _draft.addonIds)
                _SummaryRow(
                  label: addon.name,
                  value: AppFormatters.money(addon.price),
                ),
              if (_draft.admissionFee > 0)
                _SummaryRow(
                  label: 'Admission fee',
                  value: AppFormatters.money(_draft.admissionFee),
                ),
              if (pricing.discount > 0)
                _SummaryRow(
                  label: _draft.discountType == DiscountType.flat
                      ? 'Discount (₹)'
                      : 'Discount (${_draft.discountValue}%)',
                  value: '− ${AppFormatters.money(pricing.discount)}',
                  valueColor: AppColors.statusActive,
                ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Divider(height: 1, color: AppColors.borderDark),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text('TOTAL', style: AppTheme.cap()),
                  Text(
                    AppFormatters.money(pricing.total),
                    style: AppTheme.dsp(
                      fontSize: 34,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimaryDark,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text('PAYMENT MODE', style: AppTheme.cap()),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final mode in PaymentMode.values) ...[
              Expanded(
                child: _PaymentModeButton(
                  label: _modeLabel(mode),
                  selected: _draft.paymentMode == mode,
                  onTap: () {
                    setState(() => _draft = _draft.copyWith(paymentMode: mode));
                    if (mode == PaymentMode.upi_qr) _showUpiQrSheet();
                  },
                ),
              ),
              if (mode != PaymentMode.values.last) const SizedBox(width: 8),
            ],
          ],
        ),
        const SizedBox(height: 16),
        Text('AMOUNT PAID NOW', style: AppTheme.cap()),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _QuickPayButton(
                amount: AppFormatters.money(pricing.total),
                note: 'Full payment',
                selected: _draft.paid == pricing.total,
                onTap: () {
                  _amountController.text = '${pricing.total}';
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _QuickPayButton(
                amount: '₹0',
                note: 'Pay later / Unpaid',
                selected: _draft.paid == 0,
                onTap: () {
                  _amountController.text = '0';
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _amountController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Custom amount paid now ₹',
          ),
        ),
        const SizedBox(height: 12),
        // Balance due card matching page_4d30e0b8.html
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surfaceDark,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.borderDark),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Balance due after this',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondaryDark),
              ),
              Text(
                AppFormatters.money(due),
                style: AppTheme.dsp(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: due > 0 ? AppColors.statusExpired : AppColors.statusActive,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _showUpiQrSheet() async {
    final settings = ref.read(settingsRepositoryProvider);
    final qrPath = await settings.get(SettingKeys.qrImagePath);
    final gymName = await settings.get(SettingKeys.gymName);
    if (!mounted) return;

    final pricing = _draft.pricing;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Ask the member to scan & pay',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                pricing == null ? '' : AppFormatters.money(pricing.total),
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      color: AppColors.accent,
                    ),
              ),
              const SizedBox(height: 16),
              if (AppImage.exists(qrPath))
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: SizedBox(
                    width: 260,
                    height: 260,
                    child: AppImage.view(qrPath, fit: BoxFit.contain),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    children: [
                      const Icon(Icons.qr_code_2, size: 64),
                      const SizedBox(height: 8),
                      Text(
                        'No payment QR uploaded yet.\n'
                        'Add it in Settings to use this screen.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              Text(gymName ?? '', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 16),
              PrimaryButton(
                label: 'Payment received ✓',
                expanded: true,
                onPressed: () {
                  Navigator.pop(context);
                  setState(() {
                    _amountController.text =
                        '${pricing?.total ?? 0}';
                  });
                },
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Step 4: review ────────────────────────────────────────────────────────

  Widget _buildStep4(ThemeData theme) {
    final pricing = _draft.pricing;
    final end = _draft.endDate;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_draft.name.isEmpty ? '—' : _draft.name,
                  style: theme.textTheme.titleLarge),
              Text(PhoneUtils.display(_draft.phone),
                  style: theme.textTheme.bodySmall),
              const Divider(height: 24),
              _SummaryRow(
                  label: 'Plan',
                  value:
                      '${_draft.plan?.name ?? '—'} · ${AppFormatters.date(_draft.startDate)} → ${end == null ? '—' : AppFormatters.date(end)}'),
              for (final addon in _draft.addonIds)
                _SummaryRow(label: 'Add-on', value: addon.name),
              if (pricing != null) ...[
                _SummaryRow(
                    label: 'Total', value: AppFormatters.money(pricing.total)),
                _SummaryRow(
                    label: 'Paid now', value: AppFormatters.money(_draft.paid)),
                if (_draft.due != null && _draft.due! > 0)
                  _SummaryRow(
                    label: 'Due',
                    value: AppFormatters.money(_draft.due!),
                    valueColor: AppColors.statusExpiring,
                  ),
              ],
              _SummaryRow(label: 'Mode', value: _modeLabel(_draft.paymentMode)),
              const Divider(height: 24),
              Text(
                'Saving creates: member ${_draft.phone} + subscription + '
                'payment in one transaction.',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _modeLabel(PaymentMode mode) {
    switch (mode) {
      case PaymentMode.cash:
        return 'Cash';
      case PaymentMode.upi_qr:
        return 'UPI QR';
      case PaymentMode.card:
        return 'Card';
      case PaymentMode.other:
        return 'Other';
    }
  }
}

// ── Small building blocks ──────────────────────────────────────────────────

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.selected,
    required this.onTap,
  });

  final Plan plan;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected ? AppColors.accentDarkContainer : AppColors.surfaceDark,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? AppColors.accent : AppColors.borderDark,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${plan.durationMonths} MONTH${plan.durationMonths > 1 ? 'S' : ''}',
                    style: AppTheme.cap(fontSize: 10),
                  ),
                  Text(
                    plan.name.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.dsp(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimaryDark,
                    ),
                  ),
                  Text(
                    AppFormatters.money(plan.price),
                    style: AppTheme.dsp(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: selected ? AppColors.accentHighlight : AppColors.textPrimaryDark,
                    ),
                  ),
                ],
              ),
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: selected ? AppColors.accent : AppColors.surfaceRaisedDark,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected ? AppColors.accent : AppColors.borderDark,
                    ),
                  ),
                  child: selected
                      ? const Icon(Icons.check, size: 12, color: AppColors.bgDark)
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddonTile extends StatelessWidget {
  const _AddonTile({
    required this.addon,
    required this.selected,
    required this.onChanged,
  });

  final Addon addon;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!selected),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: selected ? AppColors.accent : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: selected ? AppColors.accent : AppColors.borderDark,
                  width: 1.5,
                ),
              ),
              child: selected
                  ? const Icon(Icons.check, size: 14, color: AppColors.bgDark)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                addon.name,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimaryDark,
                ),
              ),
            ),
            Text(
              '+${AppFormatters.money(addon.price)}',
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textSecondaryDark,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentModeButton extends StatelessWidget {
  const _PaymentModeButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.accentDarkContainer : AppColors.surfaceDark,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? AppColors.accent : AppColors.borderDark,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: selected ? AppColors.accentHighlight : AppColors.textSecondaryDark,
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickPayButton extends StatelessWidget {
  const _QuickPayButton({
    required this.amount,
    required this.note,
    required this.selected,
    required this.onTap,
  });

  final String amount;
  final String note;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 60,
          decoration: BoxDecoration(
            color: selected ? AppColors.accentDarkContainer : AppColors.surfaceDark,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.accent : AppColors.borderDark,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                amount,
                style: AppTheme.dsp(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimaryDark,
                ),
              ),
              Text(
                note,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondaryDark,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.color, required this.text});

  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(text, style: TextStyle(color: color)),
    );
  }
}
