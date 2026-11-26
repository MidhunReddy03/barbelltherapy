import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/utils/app_date_utils.dart';
import '../../core/utils/app_image.dart';

/// Inputs for a receipt PDF (spec 6.7).
class ReceiptData {
  const ReceiptData({
    required this.gymName,
    required this.gymPhone,
    this.gymAddress,
    this.logoPath,
    required this.memberName,
    required this.memberCode,
    required this.planName,
    required this.startDate,
    required this.endDate,
    required this.totalAmount,
    required this.paidSoFar,
    required this.paymentId,
    required this.paymentAmount,
    required this.paymentMode,
    required this.paidOn,
    this.paymentNote,
  });

  final String gymName;
  final String gymPhone;
  final String? gymAddress;
  final String? logoPath;
  final String memberName;
  final String memberCode;
  final String planName;
  final String startDate;
  final String endDate;
  final int totalAmount;
  final int paidSoFar;
  final int paymentId;
  final int paymentAmount;
  final String paymentMode;
  final String paidOn;
  final String? paymentNote;

  /// `R-000123` receipt number derived from the payment id (DECISIONS.md).
  String get receiptNumber => 'R-${paymentId.toString().padLeft(6, '0')}';

  int get balanceDue {
    final d = totalAmount - paidSoFar;
    return d < 0 ? 0 : d;
  }
}

/// Builds the receipt PDF and returns the generated file bytes.
Future<List<int>> buildReceiptPdf(ReceiptData r) async {
  final doc = pw.Document();

  pw.MemoryImage? logo;
  final logoBytes = await AppImage.readBytes(r.logoPath);
  if (logoBytes != null) {
    try {
      logo = pw.MemoryImage(logoBytes);
    } catch (_) {
      logo = null;
    }
  }

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a5,
      margin: const pw.EdgeInsets.all(36),
      build: (context) {
        final accent = PdfColor.fromInt(0xFFFF6B2C);
        const dark = PdfColor.fromInt(0xFF15181D);
        const grey = PdfColor.fromInt(0xFF5C6470);

        pw.Widget row(String label, String value, {bool bold = false}) =>
            pw.Padding(
              padding: pw.EdgeInsets.symmetric(vertical: 2),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.SizedBox(
                    width: 110,
                    child: pw.Text(label,
                        style: pw.TextStyle(fontSize: 10, color: grey)),
                  ),
                  pw.Expanded(
                    child: pw.Text(
                      value,
                      style: pw.TextStyle(
                        fontSize: 10,
                        color: dark,
                        fontWeight: bold
                            ? pw.FontWeight.bold
                            : pw.FontWeight.normal,
                      ),
                    ),
                  ),
                ],
              ),
            );

        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                if (logo != null) pw.Container(width: 46, child: pw.Image(logo)),
                if (logo != null) pw.SizedBox(width: 12),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(r.gymName,
                          style: pw.TextStyle(
                              fontSize: 18,
                              fontWeight: pw.FontWeight.bold,
                              color: dark)),
                      if (r.gymAddress != null && r.gymAddress!.isNotEmpty)
                        pw.Text(r.gymAddress!,
                            style: const pw.TextStyle(
                                fontSize: 9, color: grey)),
                      pw.Text('Phone: ${r.gymPhone}',
                          style: const pw.TextStyle(
                              fontSize: 9, color: grey)),
                    ],
                  ),
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: pw.BoxDecoration(
                        color: accent,
                        borderRadius: pw.BorderRadius.circular(4),
                      ),
                      child: pw.Text('PAYMENT RECEIPT',
                          style: pw.TextStyle(
                              fontSize: 9,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.white)),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(r.receiptNumber,
                        style: pw.TextStyle(
                            fontSize: 10,
                            fontWeight: pw.FontWeight.bold,
                            color: dark)),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 14),
            pw.Divider(color: PdfColors.grey300),
            pw.SizedBox(height: 10),
            row('Received from', '${r.memberName} (${r.memberCode})',
                bold: true),
            row('Date',
                '${_fmtDate(r.paidOn)} · ${_fmtDate(AppDateUtils.toStorage(DateTime.now()))}'),
            row('Plan', r.planName),
            row('Period', '${_fmtDate(r.startDate)} to ${_fmtDate(r.endDate)}'),
            pw.SizedBox(height: 8),
            row('Total amount', '₹${r.totalAmount}'),
            row('Paid this receipt', '₹${r.paymentAmount}', bold: true),
            row('Paid so far', '₹${r.paidSoFar}'),
            row('Payment mode', _modeLabel(r.paymentMode)),
            if (r.paymentNote != null && r.paymentNote!.isNotEmpty)
              row('Note', r.paymentNote!),
            pw.SizedBox(height: 8),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromInt(0xFFF1F3F6),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Balance due',
                      style: pw.TextStyle(
                          fontSize: 12,
                          fontWeight: pw.FontWeight.bold,
                          color: dark)),
                  pw.Text(
                    r.balanceDue == 0 ? 'PAID IN FULL ✓' : '₹${r.balanceDue}',
                    style: pw.TextStyle(
                        fontSize: 13,
                        fontWeight: pw.FontWeight.bold,
                        color: r.balanceDue == 0
                            ? PdfColor.fromInt(0xFF2ECC71)
                            : PdfColor.fromInt(0xFFE5484D)),
                  ),
                ],
              ),
            ),
            pw.Spacer(),
            pw.Divider(color: PdfColors.grey300),
            pw.SizedBox(height: 6),
            pw.Text(
              'Thank you for training with us! Keep this receipt for your records.',
              style: const pw.TextStyle(fontSize: 8, color: grey),
            ),
          ],
        );
      },
    ),
  );

  return doc.save();
}

/// Builds the PDF and opens the platform share sheet (on web: downloads
/// the file).
Future<void> shareReceipt(ReceiptData r) async {
  final bytes = await buildReceiptPdf(r);
  await AppImage.shareBytes(
    bytes: bytes,
    fileName: 'receipt_${r.receiptNumber}.pdf',
    mimeType: 'application/pdf',
    subject: 'Receipt ${r.receiptNumber} - ${r.gymName}',
    text: 'Payment receipt ${r.receiptNumber} for ${r.memberName}',
  );
}

String _modeLabel(String mode) {
  switch (mode) {
    case 'cash':
      return 'Cash';
    case 'upi_qr':
      return 'UPI / QR';
    case 'card':
      return 'Card';
    default:
      return 'Other';
  }
}

String _fmtDate(String yyyyMmDd) {
  final d = AppDateUtils.parse(yyyyMmDd);
  if (d == null) return yyyyMmDd;
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}
