import 'package:drift/drift.dart' hide Column;
import 'package:excel/excel.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/providers/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/app_date_utils.dart';
import '../../core/utils/app_image.dart';
import '../../core/widgets/common_widgets.dart';

/// Reports & Monthly Exports (spec 6.11): Excel workbook & PDF summary.
class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  DateTime _selectedMonth = AppDateUtils.today();

  Future<void> _exportExcel() async {
    final db = ref.read(databaseProvider);
    final monthKey = AppDateUtils.monthKey(_selectedMonth);

    // Fetch members
    final members = await (db.select(db.members)).get();
    // Fetch payments for this month
    final payments = await (db.select(db.payments)
          ..where((p) => p.paidOn.like('$monthKey%')))
        .get();
    // Fetch checkins for this month
    final checkins = await (db.select(db.checkins)).get();

    final excel = Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet();
    if (defaultSheet != null) excel.delete(defaultSheet);

    // Sheet 1: Members Directory
    final sheetMembers = excel['Members'];
    sheetMembers.appendRow([
      TextCellValue('Code'),
      TextCellValue('Name'),
      TextCellValue('Phone'),
      TextCellValue('Age'),
      TextCellValue('Gender'),
      TextCellValue('Joined On'),
    ]);
    for (final m in members) {
      sheetMembers.appendRow([
        TextCellValue(m.memberCode),
        TextCellValue(m.name),
        TextCellValue(m.phone),
        TextCellValue('${m.age ?? ""}'),
        TextCellValue(m.gender ?? ''),
        TextCellValue(m.joinedOn),
      ]);
    }

    // Sheet 2: Payments for Month
    final sheetPayments = excel['Payments_$monthKey'];
    sheetPayments.appendRow([
      TextCellValue('Payment ID'),
      TextCellValue('Member ID'),
      TextCellValue('Amount (₹)'),
      TextCellValue('Mode'),
      TextCellValue('Paid On'),
      TextCellValue('Voided'),
      TextCellValue('Note'),
    ]);
    for (final p in payments) {
      sheetPayments.appendRow([
        IntCellValue(p.id),
        IntCellValue(p.memberId),
        IntCellValue(p.amount),
        TextCellValue(p.mode.name.toUpperCase()),
        TextCellValue(p.paidOn),
        TextCellValue(p.voided ? 'YES' : 'NO'),
        TextCellValue(p.note ?? ''),
      ]);
    }

    // Sheet 3: Check-ins
    final sheetCheckins = excel['Checkins'];
    sheetCheckins.appendRow([
      TextCellValue('ID'),
      TextCellValue('Member ID'),
      TextCellValue('Timestamp'),
      TextCellValue('Was Expired'),
    ]);
    for (final c in checkins) {
      sheetCheckins.appendRow([
        IntCellValue(c.id),
        IntCellValue(c.memberId),
        TextCellValue(c.checkedInAt.toIso8601String()),
        TextCellValue(c.wasExpired ? 'YES' : 'NO'),
      ]);
    }

    final bytes = excel.save();
    if (bytes != null) {
      final filename = 'GymDesk_Report_$monthKey.xlsx';
      await AppImage.shareBytes(
        bytes: Uint8List.fromList(bytes),
        fileName: filename,
        mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        subject: 'GymDesk Report $monthKey',
        text: 'GymDesk monthly Excel report for $monthKey',
      );
    }
  }

  Future<void> _exportPdf() async {
    final db = ref.read(databaseProvider);
    final monthKey = AppDateUtils.monthKey(_selectedMonth);
    final payments = await (db.select(db.payments)
          ..where((p) => p.paidOn.like('$monthKey%') & p.voided.equals(false)))
        .get();
    final totalCollection = payments.fold<int>(0, (sum, p) => sum + p.amount);
    final membersCount = await (db.select(db.members)).get().then((l) => l.length);

    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (context) {
          return pw.Padding(
            padding: const pw.EdgeInsets.all(24),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('GYMDESK MONTHLY REPORT', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
                pw.Text('Period: $monthKey', style: const pw.TextStyle(fontSize: 14)),
                pw.Divider(height: 20),
                pw.Text('Summary Overview', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 8),
                pw.Text('Total Active Members: $membersCount'),
                pw.Text('Total Payments Recorded: ${payments.length}'),
                pw.Text('Total Revenue Collected: Rs. $totalCollection', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 20),
                pw.Text('Payment Entries ($monthKey)', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 8),
                pw.TableHelper.fromTextArray(
                  headers: ['ID', 'Date', 'Amount (Rs)', 'Mode'],
                  data: payments.map((p) => [
                    '#${p.id}',
                    p.paidOn,
                    '${p.amount}',
                    p.mode.name.toUpperCase(),
                  ]).toList(),
                ),
              ],
            ),
          );
        },
      ),
    );

    final bytes = await pdf.save();
    await Printing.sharePdf(bytes: bytes, filename: 'GymDesk_Monthly_$monthKey.pdf');
  }

  @override
  Widget build(BuildContext context) {
    final monthLabel = DateFormat('MMMM yyyy').format(_selectedMonth);

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 90),
          children: [
            // Header
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: AppColors.textPrimaryDark),
                  onPressed: () => context.pop(),
                ),
                const SizedBox(width: 8),
                Text(
                  'REPORTS & EXPORTS',
                  style: AppTheme.dsp(fontSize: 26, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Month Selector Card
            SectionCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('REPORT MONTH', style: AppTheme.cap()),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        monthLabel,
                        style: AppTheme.dsp(fontSize: 26, fontWeight: FontWeight.w700),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _selectedMonth,
                            firstDate: AppDateUtils.today().subtract(const Duration(days: 730)),
                            lastDate: AppDateUtils.today(),
                          );
                          if (picked != null) setState(() => _selectedMonth = picked);
                        },
                        icon: const Icon(Icons.calendar_month, size: 16),
                        label: const Text('Change'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Export Actions
            SectionCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ACCOUNTANT PACKS', style: AppTheme.cap()),
                  const SizedBox(height: 12),
                  PrimaryButton(
                    label: 'Export Excel Workbook (.xlsx)',
                    icon: Icons.table_chart_outlined,
                    expanded: true,
                    onPressed: _exportExcel,
                  ),
                  const SizedBox(height: 10),
                  SecondaryButton(
                    label: 'Export PDF Summary Report',
                    icon: Icons.picture_as_pdf_outlined,
                    expanded: true,
                    onPressed: _exportPdf,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ABOUT YOUR DATA', style: AppTheme.cap()),
                  const SizedBox(height: 6),
                  const Text(
                    'All exports are generated entirely on your device with zero cloud connectivity. You can safely share these spreadsheets with your CA or accountant at the end of each month.',
                    style: TextStyle(fontSize: 13, height: 1.5, color: AppColors.textSecondaryDark),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

