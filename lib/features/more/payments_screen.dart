import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/providers/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/app_date_utils.dart';
import '../../core/utils/app_formatters.dart';
import '../../core/widgets/common_widgets.dart';
import '../../core/widgets/status_pill.dart';
import '../../data/repositories/payments_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../domain/enums.dart';
import '../payments/receipt_pdf.dart';

enum _PaymentsTab { pendingDues, dayBook }

/// Payments & Dues hub (spec 6.7): Pending Dues list and Day Book.
class PaymentsScreen extends ConsumerStatefulWidget {
  const PaymentsScreen({super.key});

  @override
  ConsumerState<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends ConsumerState<PaymentsScreen> {
  _PaymentsTab _tab = _PaymentsTab.pendingDues;
  DateTime _dayBookDate = AppDateUtils.today();

  late Future<List<PendingDueRow>> _duesFuture;
  late Future<(List<DayBookRow>, DayBookTotals)> _dayBookFuture;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() {
      _duesFuture = ref.read(paymentsRepositoryProvider).pendingDues();
      _dayBookFuture = _fetchDayBook(_dayBookDate);
    });
  }

  Future<(List<DayBookRow>, DayBookTotals)> _fetchDayBook(DateTime date) async {
    final repo = ref.read(paymentsRepositoryProvider);
    final rows = await repo.dayBookRows(date);
    final totals = await repo.dayBook(date);
    return (rows, totals);
  }

  Future<void> _recordPaymentForDue(PendingDueRow due) async {
    final amountCtrl = TextEditingController(text: '${due.due}');
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
                  const SizedBox(height: 4),
                  Text('${due.name} (${due.memberCode}) · ${due.planName}', style: const TextStyle(fontSize: 13, color: AppColors.textSecondaryDark)),
                  Text('Due remaining: ${AppFormatters.money(due.due)}', style: const TextStyle(fontSize: 13, color: AppColors.statusExpired, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 14),
                  TextField(
                    controller: amountCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Amount (₹)', prefixText: '₹ '),
                  ),
                  const SizedBox(height: 14),
                  Text('PAYMENT MODE', style: AppTheme.cap()),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _ModeChip(label: 'Cash', isSelected: selectedMode == PaymentMode.cash, onTap: () => setModalState(() => selectedMode = PaymentMode.cash)),
                      const SizedBox(width: 8),
                      _ModeChip(label: 'UPI QR', isSelected: selectedMode == PaymentMode.upi_qr, onTap: () => setModalState(() => selectedMode = PaymentMode.upi_qr)),
                      const SizedBox(width: 8),
                      _ModeChip(label: 'Card', isSelected: selectedMode == PaymentMode.card, onTap: () => setModalState(() => selectedMode = PaymentMode.card)),
                      const SizedBox(width: 8),
                      _ModeChip(label: 'Other', isSelected: selectedMode == PaymentMode.other, onTap: () => setModalState(() => selectedMode = PaymentMode.other)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextField(controller: noteCtrl, decoration: const InputDecoration(labelText: 'Note (optional)')),
                  const SizedBox(height: 20),
                  PrimaryButton(
                    label: 'Confirm Payment',
                    expanded: true,
                    onPressed: () async {
                      final amount = int.tryParse(amountCtrl.text.trim()) ?? 0;
                      if (amount <= 0) return;
                      try {
                        final paymentId = await ref.read(paymentsRepositoryProvider).recordPayment(
                              subscriptionId: due.subscriptionId,
                              memberId: due.memberId,
                              amount: amount,
                              mode: selectedMode,
                              paidOn: AppDateUtils.today(),
                              note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
                            );
                        if (context.mounted) Navigator.pop(context, true);
                        if (mounted) await _offerReceipt(due, paymentId, amount, selectedMode);
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

    if (recorded == true) _refresh();
  }

  Future<void> _offerReceipt(PendingDueRow due, int paymentId, int amount, PaymentMode mode) async {
    final settings = ref.read(settingsRepositoryProvider);
    final gymName = await settings.get(SettingKeys.gymName) ?? 'GymDesk';
    final gymPhone = await settings.get(SettingKeys.gymPhone) ?? '';
    final gymAddress = await settings.get(SettingKeys.gymAddress) ?? '';

    final receiptData = ReceiptData(
      paymentId: paymentId,
      gymName: gymName,
      gymPhone: gymPhone,
      gymAddress: gymAddress,
      memberName: due.name,
      memberCode: due.memberCode,
      planName: due.planName,
      startDate: due.startDate,
      endDate: due.endDate,
      totalAmount: due.total,
      paidSoFar: due.paid + amount,
      paymentAmount: amount,
      paymentMode: mode.name,
      paidOn: AppDateUtils.toStorage(AppDateUtils.today()),
    );
    await shareReceipt(receiptData);
  }

  Future<void> _shareDayBookReceipt(DayBookRow row) async {
    final settings = ref.read(settingsRepositoryProvider);
    final gymName = await settings.get(SettingKeys.gymName) ?? 'GymDesk';
    final gymPhone = await settings.get(SettingKeys.gymPhone) ?? '';
    final gymAddress = await settings.get(SettingKeys.gymAddress) ?? '';

    final receiptData = ReceiptData(
      paymentId: row.id,
      gymName: gymName,
      gymPhone: gymPhone,
      gymAddress: gymAddress,
      memberName: row.memberName,
      memberCode: row.memberCode,
      planName: 'Gym Membership',
      startDate: AppDateUtils.toStorage(_dayBookDate),
      endDate: AppDateUtils.toStorage(_dayBookDate),
      totalAmount: row.amount,
      paidSoFar: row.amount,
      paymentAmount: row.amount,
      paymentMode: row.mode.name,
      paidOn: AppDateUtils.toStorage(_dayBookDate),
    );
    await shareReceipt(receiptData);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: AppColors.textPrimaryDark),
                    onPressed: () => context.pop(),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'PAYMENTS & DUES',
                    style: AppTheme.dsp(fontSize: 26, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),

            // Tab Selector Pill
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Container(
                height: 44,
                padding: const EdgeInsets.all(4),
                decoration: AppTheme.cardDecoration(),
                child: Row(
                  children: [
                    _TabItem(
                      label: 'Pending Dues',
                      isSelected: _tab == _PaymentsTab.pendingDues,
                      onTap: () => setState(() => _tab = _PaymentsTab.pendingDues),
                    ),
                    _TabItem(
                      label: 'Day Book',
                      isSelected: _tab == _PaymentsTab.dayBook,
                      onTap: () => setState(() => _tab = _PaymentsTab.dayBook),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Tab Content
            Expanded(
              child: _tab == _PaymentsTab.pendingDues
                  ? _buildPendingDuesTab()
                  : _buildDayBookTab(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPendingDuesTab() {
    return FutureBuilder<List<PendingDueRow>>(
      future: _duesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: AppColors.accent));
        }
        final dues = snapshot.data ?? const <PendingDueRow>[];
        final totalDue = dues.fold<int>(0, (sum, d) => sum + d.due);

        return ListView(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 90),
          children: [
            // Total Dues Summary Card
            SectionCard(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('TOTAL PENDING DUES', style: AppTheme.cap()),
                      const SizedBox(height: 4),
                      Text(
                        AppFormatters.money(totalDue),
                        style: AppTheme.dsp(fontSize: 32, fontWeight: FontWeight.w700, color: totalDue > 0 ? AppColors.statusExpired : AppColors.statusActive),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceRaisedDark,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.borderDark),
                    ),
                    child: Text(
                      '${dues.length} MEMBERS',
                      style: AppTheme.cap(color: AppColors.textPrimaryDark),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            if (dues.isEmpty) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: EmptyState(
                  icon: Icons.check_circle_outline,
                  title: 'No pending dues! 🎉',
                  hint: 'All member payments are up to date.',
                ),
              ),
            ] else ...[
              Text('MEMBERS WITH BALANCE DUE', style: AppTheme.cap()),
              const SizedBox(height: 8),
              ...dues.map((d) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SectionCard(
                      child: Row(
                        children: [
                          MemberAvatar(name: d.name, photoPath: d.photoPath, radius: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(d.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimaryDark)),
                                const SizedBox(height: 2),
                                Text('${d.planName} · ${d.memberCode}', style: const TextStyle(fontSize: 12, color: AppColors.textSecondaryDark)),
                                const SizedBox(height: 2),
                                Text(
                                  'Total ${AppFormatters.money(d.total)} · Paid ${AppFormatters.money(d.paid)}',
                                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondaryDark),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                AppFormatters.money(d.due),
                                style: AppTheme.dsp(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.statusExpired),
                              ),
                              const SizedBox(height: 4),
                              ElevatedButton(
                                onPressed: () => _recordPaymentForDue(d),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.accent,
                                  foregroundColor: AppColors.onAccent,
                                  minimumSize: const Size(0, 32),
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                                ),
                                child: const Text('Record'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  )),
            ],
          ],
        );
      },
    );
  }

  Widget _buildDayBookTab() {
    return FutureBuilder<(List<DayBookRow>, DayBookTotals)>(
      future: _dayBookFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: AppColors.accent));
        }
        final data = snapshot.data;
        final rows = data?.$1 ?? const <DayBookRow>[];
        final totals = data?.$2 ?? const DayBookTotals(perMode: {}, grandTotal: 0);

        final dateLabel = DateFormat('EEE d MMM yyyy').format(_dayBookDate);

        return ListView(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 90),
          children: [
            // Date Switcher Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left, color: AppColors.textPrimaryDark),
                  onPressed: () {
                    setState(() => _dayBookDate = _dayBookDate.subtract(const Duration(days: 1)));
                    _refresh();
                  },
                ),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _dayBookDate,
                      firstDate: AppDateUtils.today().subtract(const Duration(days: 365)),
                      lastDate: AppDateUtils.today(),
                    );
                    if (picked != null) {
                      setState(() => _dayBookDate = picked);
                      _refresh();
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: AppTheme.cardDecoration(),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today, size: 14, color: AppColors.accent),
                        const SizedBox(width: 8),
                        Text(dateLabel, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimaryDark)),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right, color: AppColors.textPrimaryDark),
                  onPressed: _dayBookDate.isBefore(AppDateUtils.today())
                      ? () {
                          setState(() => _dayBookDate = _dayBookDate.add(const Duration(days: 1)));
                          _refresh();
                        }
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Grand Total Card
            SectionCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('TOTAL COLLECTION', style: AppTheme.cap()),
                  const SizedBox(height: 4),
                  Text(
                    AppFormatters.money(totals.grandTotal),
                    style: AppTheme.dsp(fontSize: 34, fontWeight: FontWeight.w700, color: AppColors.statusActive),
                  ),
                  const SizedBox(height: 12),
                  // Mode Breakdown Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _ModeTotal(label: 'CASH', amount: totals.perMode[PaymentMode.cash] ?? 0),
                      _ModeTotal(label: 'UPI QR', amount: totals.perMode[PaymentMode.upi_qr] ?? 0),
                      _ModeTotal(label: 'CARD', amount: totals.perMode[PaymentMode.card] ?? 0),
                      _ModeTotal(label: 'OTHER', amount: totals.perMode[PaymentMode.other] ?? 0),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            if (rows.isEmpty) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: EmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'No payments on this day.',
                  hint: 'Payments recorded on this date appear here.',
                ),
              ),
            ] else ...[
              Text('PAYMENT ENTRIES (${rows.length})', style: AppTheme.cap()),
              const SizedBox(height: 8),
              ...rows.map((r) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SectionCard(
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      AppFormatters.money(r.amount),
                                      style: AppTheme.dsp(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w600,
                                        color: r.voided ? AppColors.textSecondaryDark : AppColors.textPrimaryDark,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppColors.surfaceRaisedDark,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(r.mode.name.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textSecondaryDark)),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text('${r.memberName} · ${r.memberCode}', style: const TextStyle(fontSize: 13, color: AppColors.textSecondaryDark)),
                                if (r.voided)
                                  const Text('VOIDED', style: TextStyle(fontSize: 11, color: AppColors.statusExpired, fontWeight: FontWeight.w700)),
                              ],
                            ),
                          ),
                          if (!r.voided)
                            IconButton(
                              icon: const Icon(Icons.picture_as_pdf, color: AppColors.accent, size: 20),
                              tooltip: 'Share receipt',
                              onPressed: () => _shareDayBookReceipt(r),
                            ),
                        ],
                      ),
                    ),
                  )),
            ],
          ],
        );
      },
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({required this.label, required this.isSelected, required this.onTap});

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
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: isSelected ? AppColors.onAccent : AppColors.textSecondaryDark,
            ),
          ),
        ),
      ),
    );
  }
}

class _ModeTotal extends StatelessWidget {
  const _ModeTotal({required this.label, required this.amount});

  final String label;
  final int amount;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textSecondaryDark, fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(
          AppFormatters.money(amount),
          style: AppTheme.dsp(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimaryDark),
        ),
      ],
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
          height: 40,
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

