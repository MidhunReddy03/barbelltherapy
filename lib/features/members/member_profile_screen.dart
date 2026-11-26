import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/providers/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/app_date_utils.dart';
import '../../core/utils/app_formatters.dart';
import '../../core/utils/app_image.dart';
import '../../core/utils/phone_utils.dart';
import '../../core/widgets/common_widgets.dart';
import '../../core/widgets/status_pill.dart';
import '../../data/database.dart' show Plan;
import '../../data/repositories/enroll_repository.dart';
import '../../data/repositories/member_profile_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../domain/end_date_calculator.dart';
import '../../domain/enums.dart';
import '../../domain/membership_status.dart';
import '../payments/receipt_pdf.dart';

enum _ProfileTab { membership, payments, history }

/// Member profile matching GymDesk App Screens (page_e3c21e84.html).
/// Phase 3 (Payments, Dues, Freeze, Renew, Cancel) fully implemented.
class MemberProfileScreen extends ConsumerStatefulWidget {
  const MemberProfileScreen({super.key, required this.memberId});

  final int memberId;

  @override
  ConsumerState<MemberProfileScreen> createState() =>
      _MemberProfileScreenState();
}

class _MemberProfileScreenState extends ConsumerState<MemberProfileScreen> {
  late Future<MemberProfile> _future;
  _ProfileTab _tab = _ProfileTab.membership;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<MemberProfile> _load() =>
      ref.read(memberProfileRepositoryProvider).load(widget.memberId);

  void _refresh() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: SafeArea(
        child: FutureBuilder<MemberProfile>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: AppColors.accent));
            }
            if (snapshot.hasError) {
              return Center(
                child: EmptyState(
                  icon: Icons.error_outline,
                  title: 'Could not load this member',
                  hint: '${snapshot.error}',
                  action: PrimaryButton(label: 'Retry', onPressed: _refresh),
                ),
              );
            }
            final profile = snapshot.data!;
            final status = _evaluate(profile);

            return Stack(
              children: [
                ListView(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 110),
                  children: [
                    // Top Bar (Back & Actions)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _IconCardButton(
                          icon: Icons.arrow_back,
                          tooltip: 'Back',
                          onTap: () => context.pop(),
                        ),
                        Row(
                          children: [
                            _IconCardButton(
                              icon: Icons.edit_outlined,
                              tooltip: 'Edit member',
                              onTap: () => _editMember(profile),
                            ),
                            const SizedBox(width: 8),
                            _IconCardButton(
                              icon: Icons.archive_outlined,
                              tooltip: 'Archive member',
                              onTap: () => _archive(profile),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Profile Header matching HTML
                    _HeaderSection(
                      profile: profile,
                      status: status,
                      onPhotoTap: _changePhoto,
                    ),
                    const SizedBox(height: 14),

                    // 4 Quick Action Buttons Row (.qa)
                    _QuickActionsRow(
                      profile: profile,
                      onWhatsApp: () => _whatsapp(profile, status),
                      onCall: () => _call(profile),
                      onRenew: () => _showRenewDialog(profile),
                      onFreeze: () => _showFreezeDialog(profile),
                    ),
                    const SizedBox(height: 14),

                    // 3 Profile Tabs Pill Container
                    _TabSelector(
                      current: _tab,
                      onSelect: (t) => setState(() => _tab = t),
                    ),
                    const SizedBox(height: 14),

                    // Active Tab Content
                    switch (_tab) {
                      _ProfileTab.membership => _MembershipTabContent(
                          profile: profile,
                          status: status,
                          onEndFreezeEarly: _endFreezeEarly,
                          onCancelMembership: () => _cancelMembership(profile),
                        ),
                      _ProfileTab.payments => _PaymentsTabContent(
                          profile: profile,
                          onShareReceipt: (p) => _sharePaymentReceipt(profile, p),
                          onVoidPayment: _voidPayment,
                        ),
                      _ProfileTab.history => _HistoryTabContent(profile: profile),
                    },
                  ],
                ),

                // Bottom Fixed Actions Bar matching HTML:
                // Record payment (bg #282C31) and Renew plan (bg #D98A5B)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    decoration: const BoxDecoration(
                      color: AppColors.surfaceDark,
                      border: Border(top: BorderSide(color: AppColors.borderDark)),
                    ),
                    padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: SecondaryButton(
                            label: 'Record payment',
                            height: 50,
                            onPressed: () => _showRecordPaymentSheet(profile),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: PrimaryButton(
                            label: 'Renew plan',
                            height: 50,
                            onPressed: () => _showRenewDialog(profile),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  MembershipStatusResult _evaluate(MemberProfile profile) {
    final today = AppDateUtils.today();
    final end = AppDateUtils.parse(profile.endDate);
    final start = AppDateUtils.parse(profile.startDate);
    return MembershipStatusCalculator.evaluate(
      today: today,
      hasSubscription: end != null,
      startDate: start,
      endDate: end,
      frozenToday: profile.member.frozenToday,
      expiringSoonWindowDays: 7,
    );
  }

  // ── Action Handlers ────────────────────────────────────────────────────────

  Future<void> _changePhoto() async {
    final xfile = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (xfile == null) return;
    final compressed = await AppImage.store(xfile, prefix: 'member');
    if (compressed == null || !mounted) return;
    final profile = await _future;
    await ref.read(memberProfileRepositoryProvider).updateMember(
          id: widget.memberId,
          name: profile.member.name,
          phone: profile.member.phone,
          photoPath: compressed,
        );
    _refresh();
  }

  Future<void> _whatsapp(MemberProfile profile, MembershipStatusResult status) async {
    final settings = ref.read(settingsRepositoryProvider);
    final language = await settings.defaultLanguage();
    final composed = await ref.read(messagesComposerProvider).composeByStatus(
          member: profile.member,
          status: status,
          language: language,
        );
    if (!mounted) return;
    if (composed == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No template available for this status.')),
      );
      return;
    }
    final (type, templateId, message) = composed;
    final controller = TextEditingController(text: message);
    final edited = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppColors.borderDark),
        ),
        title: Text('MESSAGE PREVIEW', style: AppTheme.dsp(fontSize: 20)),
        content: TextField(controller: controller, maxLines: 6),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondaryDark)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: AppColors.onAccent,
            ),
            child: const Text('Open WhatsApp'),
          ),
        ],
      ),
    );
    if (edited == null || !mounted) return;

    final uri = PhoneUtils.whatsappUri(profile.member.phone, edited);
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      final sms = PhoneUtils.smsUri(profile.member.phone, edited);
      await launchUrl(sms, mode: LaunchMode.externalApplication);
    }
    await ref.read(remindersRepositoryProvider).markSent(
          memberId: profile.member.id,
          type: type,
          templateId: templateId,
        );
  }

  Future<void> _call(MemberProfile profile) async {
    final uri = PhoneUtils.telUri(profile.member.phone);
    await launchUrl(uri);
  }

  Future<void> _editMember(MemberProfile profile) async {
    final nameCtrl = TextEditingController(text: profile.member.name);
    final phoneCtrl = TextEditingController(text: profile.member.phone);
    final notesCtrl = TextEditingController(text: profile.member.notes ?? '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppColors.borderDark),
        ),
        title: Text('EDIT MEMBER', style: AppTheme.dsp(fontSize: 20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name')),
            const SizedBox(height: 10),
            TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: 'Phone (10 digits)')),
            const SizedBox(height: 10),
            TextField(controller: notesCtrl, decoration: const InputDecoration(labelText: 'Notes (optional)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent, foregroundColor: AppColors.onAccent),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (saved == true && mounted) {
      await ref.read(memberProfileRepositoryProvider).updateMember(
            id: profile.member.id,
            name: nameCtrl.text.trim(),
            phone: phoneCtrl.text.trim(),
            notes: notesCtrl.text.trim(),
          );
      _refresh();
    }
  }

  Future<void> _archive(MemberProfile profile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppColors.borderDark),
        ),
        title: Text('ARCHIVE MEMBER', style: AppTheme.dsp(fontSize: 20)),
        content: Text('Archive ${profile.member.name}? They will no longer appear in active member lists.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.statusExpired),
            child: const Text('Archive'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await ref.read(memberProfileRepositoryProvider).setArchived(profile.member.id, true);
      if (mounted) context.pop();
    }
  }

  // ── Phase 3: Record Payment Sheet ──────────────────────────────────────────

  Future<void> _showRecordPaymentSheet(MemberProfile profile) async {
    if (profile.subscriptionId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This member does not have an active plan to record payment against.')),
      );
      return;
    }

    final amountCtrl = TextEditingController(text: '${profile.due > 0 ? profile.due : ""}');
    final noteCtrl = TextEditingController();
    PaymentMode selectedMode = PaymentMode.cash;

    final recorded = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceDark,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(18, 20, 18, MediaQuery.of(context).viewInsets.bottom + 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('RECORD PAYMENT', style: AppTheme.dsp(fontSize: 22, fontWeight: FontWeight.w700)),
                      IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context, false)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Outstanding due: ${AppFormatters.money(profile.due)}',
                    style: TextStyle(
                      fontSize: 13,
                      color: profile.due > 0 ? AppColors.statusExpired : AppColors.statusActive,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: amountCtrl,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textPrimaryDark),
                    decoration: const InputDecoration(
                      labelText: 'Amount (₹)',
                      prefixText: '₹ ',
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text('PAYMENT MODE', style: AppTheme.cap()),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _ModeChip(
                        label: 'Cash',
                        isSelected: selectedMode == PaymentMode.cash,
                        onTap: () => setModalState(() => selectedMode = PaymentMode.cash),
                      ),
                      const SizedBox(width: 8),
                      _ModeChip(
                        label: 'UPI QR',
                        isSelected: selectedMode == PaymentMode.upi_qr,
                        onTap: () => setModalState(() => selectedMode = PaymentMode.upi_qr),
                      ),
                      const SizedBox(width: 8),
                      _ModeChip(
                        label: 'Card',
                        isSelected: selectedMode == PaymentMode.card,
                        onTap: () => setModalState(() => selectedMode = PaymentMode.card),
                      ),
                      const SizedBox(width: 8),
                      _ModeChip(
                        label: 'Other',
                        isSelected: selectedMode == PaymentMode.other,
                        onTap: () => setModalState(() => selectedMode = PaymentMode.other),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: noteCtrl,
                    decoration: const InputDecoration(labelText: 'Note (optional)'),
                  ),
                  const SizedBox(height: 20),
                  PrimaryButton(
                    label: 'Confirm Payment',
                    expanded: true,
                    onPressed: () async {
                      final amount = int.tryParse(amountCtrl.text.trim()) ?? 0;
                      if (amount <= 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Please enter a valid amount greater than ₹0.')),
                        );
                        return;
                      }
                      try {
                        final paymentId = await ref.read(paymentsRepositoryProvider).recordPayment(
                              subscriptionId: profile.subscriptionId!,
                              memberId: profile.member.id,
                              amount: amount,
                              mode: selectedMode,
                              paidOn: AppDateUtils.today(),
                              note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
                            );
                        if (context.mounted) Navigator.pop(context, true);

                        // Offer to share receipt
                        if (mounted) {
                          await _offerShareReceipt(profile, paymentId, amount, selectedMode);
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('$e')),
                          );
                        }
                      }
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (recorded == true) {
      _refresh();
    }
  }

  Future<void> _offerShareReceipt(MemberProfile profile, int paymentId, int amount, PaymentMode mode) async {
    final settings = ref.read(settingsRepositoryProvider);
    final gymName = await settings.get(SettingKeys.gymName) ?? 'GymDesk';
    final gymPhone = await settings.get(SettingKeys.gymPhone) ?? '';
    final gymAddress = await settings.get(SettingKeys.gymAddress) ?? '';

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        title: Text('PAYMENT RECORDED ✓', style: AppTheme.dsp(fontSize: 20, color: AppColors.statusActive)),
        content: Text('Payment of ${AppFormatters.money(amount)} recorded successfully. Would you like to share the receipt PDF?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.pop(context);
              final receiptData = ReceiptData(
                paymentId: paymentId,
                gymName: gymName,
                gymPhone: gymPhone,
                gymAddress: gymAddress,
                memberName: profile.member.name,
                memberCode: profile.member.memberCode,
                planName: profile.planName ?? 'Membership',
                startDate: profile.startDate ?? '',
                endDate: profile.endDate ?? '',
                totalAmount: profile.totalAmount ?? 0,
                paidSoFar: profile.paid + amount,
                paymentAmount: amount,
                paymentMode: mode.name,
                paidOn: AppDateUtils.toStorage(AppDateUtils.today()),
              );
              await shareReceipt(receiptData);
            },
            icon: const Icon(Icons.picture_as_pdf),
            label: const Text('Share Receipt PDF'),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent, foregroundColor: AppColors.onAccent),
          ),
        ],
      ),
    );
  }

  Future<void> _sharePaymentReceipt(MemberProfile profile, ProfilePayment p) async {
    final settings = ref.read(settingsRepositoryProvider);
    final gymName = await settings.get(SettingKeys.gymName) ?? 'GymDesk';
    final gymPhone = await settings.get(SettingKeys.gymPhone) ?? '';
    final gymAddress = await settings.get(SettingKeys.gymAddress) ?? '';

    final receiptData = ReceiptData(
      paymentId: p.id,
      gymName: gymName,
      gymPhone: gymPhone,
      gymAddress: gymAddress,
      memberName: profile.member.name,
      memberCode: profile.member.memberCode,
      planName: profile.planName ?? 'Membership',
      startDate: profile.startDate ?? '',
      endDate: profile.endDate ?? '',
      totalAmount: profile.totalAmount ?? 0,
      paidSoFar: profile.paid,
      paymentAmount: p.amount,
      paymentMode: p.mode.name,
      paidOn: p.paidOn,
    );
    await shareReceipt(receiptData);
  }

  Future<void> _voidPayment(int paymentId) async {
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        title: Text('VOID PAYMENT', style: AppTheme.dsp(fontSize: 20, color: AppColors.statusExpired)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Voiding reverses this payment in the accounts while preserving an audit trail.'),
            const SizedBox(height: 10),
            TextField(controller: reasonCtrl, decoration: const InputDecoration(labelText: 'Reason for voiding')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.statusExpired),
            child: const Text('Void Payment'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await ref.read(paymentsRepositoryProvider).voidPayment(
            paymentId,
            reasonCtrl.text.trim().isEmpty ? 'Voided by gym owner' : reasonCtrl.text.trim(),
          );
      _refresh();
    }
  }

  // ── Phase 3: Renewal Dialog ────────────────────────────────────────────────

  Future<void> _showRenewDialog(MemberProfile profile) async {
    final plans = await ref.read(catalogRepositoryProvider).watchActivePlans().first;
    if (plans.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No active membership plans found.')),
      );
      return;
    }

    final prefill = await ref.read(enrollRepositoryProvider).renewPrefill(profile.member.id);
    DateTime startDate = prefill?.suggestedStart ?? AppDateUtils.today();
    Plan selectedPlan = plans.firstWhere(
      (p) => p.name == profile.planName,
      orElse: () => plans.first,
    );
    final amountPaidCtrl = TextEditingController(text: '${selectedPlan.price}');
    PaymentMode paymentMode = PaymentMode.cash;

    if (!mounted) return;
    final renewed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceDark,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final endDate = EndDateCalculator.calculate(startDate, selectedPlan.durationMonths);
            return Padding(
              padding: EdgeInsets.fromLTRB(18, 20, 18, MediaQuery.of(context).viewInsets.bottom + 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('RENEW PLAN', style: AppTheme.dsp(fontSize: 22, fontWeight: FontWeight.w700)),
                      IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context, false)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text('CHOOSE PLAN', style: AppTheme.cap()),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: plans.map((p) {
                      final isSelected = p.id == selectedPlan.id;
                      return ChoiceChip(
                        label: Text('${p.name} (₹${p.price})'),
                        selected: isSelected,
                        selectedColor: AppColors.accent,
                        labelStyle: TextStyle(
                          color: isSelected ? AppColors.onAccent : AppColors.textPrimaryDark,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        ),
                        onSelected: (s) {
                          if (s) {
                            setModalState(() {
                              selectedPlan = p;
                              amountPaidCtrl.text = '${p.price}';
                            });
                          }
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Start: ${AppFormatters.date(startDate)}',
                          style: const TextStyle(fontSize: 13, color: AppColors.textPrimaryDark),
                        ),
                      ),
                      Text(
                        'Ends: ${AppFormatters.date(endDate)}',
                        style: const TextStyle(fontSize: 13, color: AppColors.statusActive, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: amountPaidCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Amount Paid Now (₹)',
                      prefixText: '₹ ',
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text('PAYMENT MODE', style: AppTheme.cap()),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _ModeChip(label: 'Cash', isSelected: paymentMode == PaymentMode.cash, onTap: () => setModalState(() => paymentMode = PaymentMode.cash)),
                      const SizedBox(width: 8),
                      _ModeChip(label: 'UPI QR', isSelected: paymentMode == PaymentMode.upi_qr, onTap: () => setModalState(() => paymentMode = PaymentMode.upi_qr)),
                      const SizedBox(width: 8),
                      _ModeChip(label: 'Card', isSelected: paymentMode == PaymentMode.card, onTap: () => setModalState(() => paymentMode = PaymentMode.card)),
                      const SizedBox(width: 8),
                      _ModeChip(label: 'Other', isSelected: paymentMode == PaymentMode.other, onTap: () => setModalState(() => paymentMode = PaymentMode.other)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  PrimaryButton(
                    label: 'Confirm Renewal',
                    expanded: true,
                    onPressed: () async {
                      final paid = int.tryParse(amountPaidCtrl.text.trim()) ?? 0;
                      final draft = EnrollDraft(
                        name: profile.member.name,
                        phone: profile.member.phone,
                        plan: selectedPlan,
                        startDate: startDate,
                        amountPaid: paid,
                        paymentMode: paymentMode,
                      );
                      try {
                        await ref.read(enrollRepositoryProvider).renew(
                              memberId: profile.member.id,
                              memberCode: profile.member.memberCode,
                              draft: draft,
                            );
                        if (context.mounted) Navigator.pop(context, true);
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
                        }
                      }
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (renewed == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Plan renewed successfully!')),
      );
      _refresh();
    }
  }

  // ── Phase 3: Freeze & End Freeze Handlers ──────────────────────────────────

  Future<void> _showFreezeDialog(MemberProfile profile) async {
    if (profile.subscriptionId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot freeze a member without an active subscription.')),
      );
      return;
    }

    if (profile.member.frozenToday) {
      // Prompt to end freeze early
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppColors.surfaceDark,
          title: Text('END FREEZE EARLY', style: AppTheme.dsp(fontSize: 20, color: AppColors.statusFrozen)),
          content: const Text('Member is currently frozen. End freeze today and resume membership? Unused days will be shifted back.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent, foregroundColor: AppColors.onAccent),
              child: const Text('Resume Today'),
            ),
          ],
        ),
      );
      if (confirm == true) {
        await _endFreezeEarly(profile);
      }
      return;
    }

    DateTime freezeStart = AppDateUtils.today();
    DateTime freezeEnd = freezeStart.add(const Duration(days: 14));
    final reasonCtrl = TextEditingController(text: 'Travel / medical');

    if (!mounted) return;
    final frozen = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final days = freezeEnd.difference(freezeStart).inDays + 1;
            return AlertDialog(
              backgroundColor: AppColors.surfaceDark,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              title: Text('FREEZE MEMBERSHIP', style: AppTheme.dsp(fontSize: 20, color: AppColors.statusFrozen)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Freeze for $days days. End date will shift automatically.', style: const TextStyle(fontSize: 13, color: AppColors.textSecondaryDark)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: freezeStart,
                              firstDate: AppDateUtils.today(),
                              lastDate: AppDateUtils.today().add(const Duration(days: 365)),
                            );
                            if (picked != null) {
                              setDialogState(() {
                                freezeStart = picked;
                                if (freezeEnd.isBefore(freezeStart)) freezeEnd = freezeStart;
                              });
                            }
                          },
                          child: Text('Start: ${DateFormat('d MMM').format(freezeStart)}'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: freezeEnd,
                              firstDate: freezeStart,
                              lastDate: freezeStart.add(const Duration(days: 180)),
                            );
                            if (picked != null) {
                              setDialogState(() => freezeEnd = picked);
                            }
                          },
                          child: Text('End: ${DateFormat('d MMM').format(freezeEnd)}'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(controller: reasonCtrl, decoration: const InputDecoration(labelText: 'Reason for freeze')),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.statusFrozen, foregroundColor: Colors.white),
                  child: const Text('Confirm Freeze'),
                ),
              ],
            );
          },
        );
      },
    );

    if (frozen == true && mounted) {
      final err = await ref.read(freezeRepositoryProvider).validate(
            subscriptionId: profile.subscriptionId!,
            start: freezeStart,
            end: freezeEnd,
          );
      if (err != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
        return;
      }
      await ref.read(freezeRepositoryProvider).create(
            subscriptionId: profile.subscriptionId!,
            memberId: profile.member.id,
            start: freezeStart,
            end: freezeEnd,
            reason: reasonCtrl.text.trim().isEmpty ? null : reasonCtrl.text.trim(),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Membership frozen successfully.')),
      );
      _refresh();
    }
  }

  Future<void> _endFreezeEarly(MemberProfile profile) async {
    final active = await ref.read(freezeRepositoryProvider).activeFreeze(profile.subscriptionId!);
    if (active != null) {
      await ref.read(freezeRepositoryProvider).endEarly(active.id);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Freeze ended early! Membership resumed.')),
    );
    _refresh();
  }

  Future<void> _cancelMembership(MemberProfile profile) async {
    final reasonCtrl = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        title: Text('CANCEL MEMBERSHIP', style: AppTheme.dsp(fontSize: 20, color: AppColors.statusExpired)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Are you sure you want to cancel this membership? This will mark it as cancelled in the database.'),
            const SizedBox(height: 10),
            TextField(controller: reasonCtrl, decoration: const InputDecoration(labelText: 'Cancellation reason')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep Active')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.statusExpired),
            child: const Text('Cancel Membership'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      await ref.read(paymentsRepositoryProvider).cancelSubscription(
            profile.subscriptionId!,
            reasonCtrl.text.trim().isEmpty ? 'Cancelled by owner' : reasonCtrl.text.trim(),
          );
      _refresh();
    }
  }
}

// ── Supporting Profile Widgets ─────────────────────────────────────────────

const verticalRadius = Radius.circular(20);

class _IconCardButton extends StatelessWidget {
  const _IconCardButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceDark,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 44,
          height: 44,
          decoration: AppTheme.cardDecoration(),
          child: Icon(icon, size: 20, color: AppColors.textPrimaryDark),
        ),
      ),
    );
  }
}

class _HeaderSection extends StatelessWidget {
  const _HeaderSection({
    required this.profile,
    required this.status,
    required this.onPhotoTap,
  });

  final MemberProfile profile;
  final MembershipStatusResult status;
  final VoidCallback onPhotoTap;

  @override
  Widget build(BuildContext context) {
    final m = profile.member;
    final initials = m.name
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();

    return Row(
      children: [
        // 88x88 Avatar Ring
        GestureDetector(
          onTap: onPhotoTap,
          child: Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: StatusPill.colorFor(status.status), width: 2),
            ),
            padding: const EdgeInsets.all(4),
            child: Container(
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF33291A),
              ),
              clipBehavior: Clip.antiAlias,
              child: m.photoPath != null && m.photoPath!.isNotEmpty
                  ? AppImage.view(m.photoPath, width: 80, height: 80)
                  : Center(
                      child: Text(
                        initials.isEmpty ? '?' : initials,
                        style: AppTheme.dsp(fontSize: 34, fontWeight: FontWeight.w600, color: AppColors.statusExpiring),
                      ),
                    ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        // Details
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                m.name.toUpperCase(),
                style: AppTheme.dsp(fontSize: 30, fontWeight: FontWeight.w700, color: AppColors.textPrimaryDark),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                '${m.memberCode}${m.age != null ? ' · ${m.age} yrs' : ''}${m.gender != null ? ' · ${m.gender}' : ''}',
                style: const TextStyle(fontSize: 13, color: AppColors.textSecondaryDark),
              ),
              const SizedBox(height: 1),
              Text(
                PhoneUtils.display(m.phone),
                style: const TextStyle(fontSize: 13, color: AppColors.textSecondaryDark),
              ),
              const SizedBox(height: 6),
              StatusPill(status: status.status),
            ],
          ),
        ),
      ],
    );
  }
}

class _QuickActionsRow extends StatelessWidget {
  const _QuickActionsRow({
    required this.profile,
    required this.onWhatsApp,
    required this.onCall,
    required this.onRenew,
    required this.onFreeze,
  });

  final MemberProfile profile;
  final VoidCallback onWhatsApp;
  final VoidCallback onCall;
  final VoidCallback onRenew;
  final VoidCallback onFreeze;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _QaButton(
            label: 'WhatsApp',
            icon: Icons.chat,
            iconBg: const Color(0x248DBB9A),
            iconColor: AppColors.statusActive,
            onTap: onWhatsApp,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _QaButton(
            label: 'Call',
            icon: Icons.call,
            iconBg: AppColors.surfaceRaisedDark,
            iconColor: AppColors.textPrimaryDark,
            onTap: onCall,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _QaButton(
            label: 'Renew',
            icon: Icons.autorenew,
            iconBg: const Color(0x24D98A5B),
            iconColor: AppColors.accentHighlight,
            onTap: onRenew,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _QaButton(
            label: 'Freeze',
            icon: Icons.ac_unit,
            iconBg: const Color(0x248DB0D0),
            iconColor: AppColors.statusFrozen,
            onTap: onFreeze,
          ),
        ),
      ],
    );
  }
}

class _QaButton extends StatelessWidget {
  const _QaButton({
    required this.label,
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surfaceDark,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.borderDark),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 40,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 20, color: iconColor),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimaryDark,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabSelector extends StatelessWidget {
  const _TabSelector({required this.current, required this.onSelect});

  final _ProfileTab current;
  final ValueChanged<_ProfileTab> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      padding: const EdgeInsets.all(4),
      decoration: AppTheme.cardDecoration(),
      child: Row(
        children: [
          _TabPill(
            label: 'Membership',
            isSelected: current == _ProfileTab.membership,
            onTap: () => onSelect(_ProfileTab.membership),
          ),
          _TabPill(
            label: 'Payments',
            isSelected: current == _ProfileTab.payments,
            onTap: () => onSelect(_ProfileTab.payments),
          ),
          _TabPill(
            label: 'History',
            isSelected: current == _ProfileTab.history,
            onTap: () => onSelect(_ProfileTab.history),
          ),
        ],
      ),
    );
  }
}

class _TabPill extends StatelessWidget {
  const _TabPill({required this.label, required this.isSelected, required this.onTap});

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? AppColors.onAccent : AppColors.textSecondaryDark,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MembershipTabContent extends StatelessWidget {
  const _MembershipTabContent({
    required this.profile,
    required this.status,
    required this.onEndFreezeEarly,
    required this.onCancelMembership,
  });

  final MemberProfile profile;
  final MembershipStatusResult status;
  final Future<void> Function(MemberProfile) onEndFreezeEarly;
  final VoidCallback onCancelMembership;

  @override
  Widget build(BuildContext context) {
    if (profile.subscriptionId == null) {
      return SectionCard(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Icon(Icons.card_membership_outlined, size: 48, color: AppColors.textSecondaryDark),
              const SizedBox(height: 10),
              Text('NO ACTIVE PLAN', style: AppTheme.dsp(fontSize: 20)),
              const SizedBox(height: 4),
              const Text('Tap "Renew plan" below to assign a plan to this member.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondaryDark)),
            ],
          ),
        ),
      );
    }

    final start = AppDateUtils.parse(profile.startDate)!;
    final end = AppDateUtils.parse(profile.endDate)!;
    final today = AppDateUtils.today();
    final totalDays = end.difference(start).inDays;
    final usedDays = today.difference(start).inDays;
    final progress = totalDays <= 0 ? 1.0 : (usedDays / totalDays).clamp(0.0, 1.0);

    return Column(
      children: [
        // Frozen Banner if applicable
        if (profile.member.frozenToday) ...[
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: const Color(0x248DB0D0),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.statusFrozen),
            ),
            child: Row(
              children: [
                const Icon(Icons.ac_unit, color: AppColors.statusFrozen, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Membership is currently frozen.', style: TextStyle(color: AppColors.statusFrozen, fontWeight: FontWeight.w600)),
                ),
                TextButton(
                  onPressed: () => onEndFreezeEarly(profile),
                  child: const Text('Resume Today', style: TextStyle(color: AppColors.statusFrozen, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        ],

        // Plan Card matching HTML
        SectionCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    (profile.planName ?? 'MEMBERSHIP').toUpperCase(),
                    style: AppTheme.dsp(fontSize: 22, fontWeight: FontWeight.w600),
                  ),
                  Text(
                    status.daysLeft != null && status.daysLeft! >= 0
                        ? '${status.daysLeft} days left'
                        : 'Expired',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: status.daysLeft != null && status.daysLeft! >= 0
                          ? AppColors.statusExpiring
                          : AppColors.statusExpired,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                '${AppFormatters.date(start)} to ${AppFormatters.date(end)}'
                '${profile.addons.isNotEmpty ? ' · + ${profile.addons.join(", ")}' : ''}',
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondaryDark),
              ),
              const SizedBox(height: 12),
              // Gradient progress bar
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  height: 8,
                  color: AppColors.surfaceRaisedDark,
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: progress.toDouble(),
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(colors: [AppColors.accent, AppColors.statusExpiring]),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              // 3-stat row: Total / Paid / Due
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _StatBlock(label: 'TOTAL', value: AppFormatters.money(profile.totalAmount ?? 0)),
                  _StatBlock(label: 'PAID', value: AppFormatters.money(profile.paid), valueColor: AppColors.statusActive),
                  _StatBlock(label: 'DUE', value: AppFormatters.money(profile.due), valueColor: profile.due > 0 ? AppColors.statusExpired : AppColors.statusActive),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Cancel membership link
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: onCancelMembership,
            icon: const Icon(Icons.cancel_outlined, size: 16, color: AppColors.statusExpired),
            label: const Text('Cancel membership', style: TextStyle(color: AppColors.statusExpired, fontSize: 13)),
          ),
        ),
      ],
    );
  }
}

class _StatBlock extends StatelessWidget {
  const _StatBlock({required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTheme.cap()),
        const SizedBox(height: 2),
        Text(
          value,
          style: AppTheme.dsp(fontSize: 26, fontWeight: FontWeight.w600, color: valueColor ?? AppColors.textPrimaryDark),
        ),
      ],
    );
  }
}

class _PaymentsTabContent extends StatelessWidget {
  const _PaymentsTabContent({
    required this.profile,
    required this.onShareReceipt,
    required this.onVoidPayment,
  });

  final MemberProfile profile;
  final ValueChanged<ProfilePayment> onShareReceipt;
  final ValueChanged<int> onVoidPayment;

  @override
  Widget build(BuildContext context) {
    if (profile.payments.isEmpty) {
      return const EmptyState(
        icon: Icons.payments_outlined,
        title: 'No payments recorded yet.',
        hint: 'Payments recorded during enrollment or renewals appear here.',
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: profile.payments.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final p = profile.payments[i];
        return SectionCard(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          AppFormatters.money(p.amount),
                          style: AppTheme.dsp(fontSize: 22, fontWeight: FontWeight.w600, color: p.voided ? AppColors.textSecondaryDark : AppColors.textPrimaryDark),
                        ),
                        const SizedBox(width: 8),
                        Text(p.mode.name.toUpperCase(), style: AppTheme.cap()),
                        const Spacer(),
                        Text(p.paidOn, style: const TextStyle(fontSize: 12, color: AppColors.textSecondaryDark)),
                      ],
                    ),
                    if (p.note != null && p.note!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(p.note!, style: const TextStyle(fontSize: 12, color: AppColors.textSecondaryDark)),
                    ],
                    if (p.voided) ...[
                      const SizedBox(height: 2),
                      Text('VOIDED (${p.voidReason ?? 'Reversed'})', style: const TextStyle(fontSize: 11, color: AppColors.statusExpired, fontWeight: FontWeight.w600)),
                    ],
                  ],
                ),
              ),
              if (!p.voided) ...[
                IconButton(
                  icon: const Icon(Icons.picture_as_pdf, color: AppColors.accent, size: 20),
                  tooltip: 'Share receipt PDF',
                  onPressed: () => onShareReceipt(p),
                ),
                IconButton(
                  icon: const Icon(Icons.block, color: AppColors.statusExpired, size: 20),
                  tooltip: 'Void payment',
                  onPressed: () => onVoidPayment(p.id),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _HistoryTabContent extends StatelessWidget {
  const _HistoryTabContent({required this.profile});

  final MemberProfile profile;

  @override
  Widget build(BuildContext context) {
    if (profile.history.isEmpty) {
      return const EmptyState(
        icon: Icons.history,
        title: 'No past subscriptions.',
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: profile.history.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final h = profile.history[i];
        return SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(h.planName.toUpperCase(), style: AppTheme.dsp(fontSize: 20, fontWeight: FontWeight.w600)),
                  if (h.cancelled)
                    const Text('CANCELLED', style: TextStyle(fontSize: 11, color: AppColors.statusExpired, fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                '${h.startDate} → ${h.endDate} · ${AppFormatters.money(h.totalAmount)} total (${AppFormatters.money(h.paid)} paid)',
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondaryDark),
              ),
              if (h.addons.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text('Add-ons: ${h.addons.join(", ")}', style: const TextStyle(fontSize: 12, color: AppColors.textSecondaryDark)),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({required this.label, required this.isSelected, required this.onTap});

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 42,
          decoration: BoxDecoration(
            color: isSelected ? AppColors.accentDarkContainer : AppColors.surfaceRaisedDark,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? AppColors.accent : AppColors.borderDark,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isSelected ? AppColors.accentHighlight : AppColors.textPrimaryDark,
            ),
          ),
        ),
      ),
    );
  }
}
