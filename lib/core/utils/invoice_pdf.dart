import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'formatters.dart';

/// Shared by InvoiceDetailScreen (share button) and future WhatsApp flow.
/// Takes the same map shape returned by:
///   invoices.select('*, members(first_name, last_name, email), gyms(name, settings)')
Future<Uint8List> buildInvoicePdf(Map<String, dynamic> inv) async {
  final regularData = await rootBundle.load(
    'assets/fonts/Manrope_400Regular.ttf',
  );
  final boldData = await rootBundle.load('assets/fonts/Manrope_700Bold.ttf');
  final regular = pw.Font.ttf(regularData);
  final bold = pw.Font.ttf(boldData);

  final member = inv['members'] as Map<String, dynamic>?;
  final gym = inv['gyms'] as Map<String, dynamic>?;
  final settings =
      (inv['settings_snapshot'] as Map<String, dynamic>?) ??
      (gym?['settings'] as Map<String, dynamic>?) ??
      {};
  final memberSnapshot =
      (inv['member_snapshot'] as Map<String, dynamic>?) ?? {};

  final gymName =
      (settings['gym_name'] as String? ?? gym?['name'] as String? ?? 'Gym')
          .toUpperCase();
  final address = settings['address'] as String?;
  final phone =
      settings['contact_phone'] as String? ?? settings['phone'] as String?;
  final website =
      settings['contact_email'] as String? ?? settings['website'] as String?;
  final ownerName = settings['owner_name'] as String?;
  final gstin = settings['gstin'] as String?;
  final refundPolicy = settings['refund_policy'] as String?;
  final terms = settings['terms_and_conditions'] as String?;
  pw.MemoryImage? logo;
  final logoUrl = settings['logo_url'] as String?;
  if (logoUrl != null && logoUrl.isNotEmpty) {
    try {
      final response = await http.get(Uri.parse(logoUrl));
      if (response.statusCode == 200) logo = pw.MemoryImage(response.bodyBytes);
    } catch (_) {
      // A broken remote logo must never prevent the invoice from rendering.
    }
  }

  final memberName =
      memberSnapshot['name'] as String? ??
      (member != null
          ? '${member['first_name'] ?? ''} ${member['last_name'] ?? ''}'.trim()
          : 'Member');
  final memberEmail =
      memberSnapshot['email'] as String? ?? (member?['email'] as String?) ?? '';
  final membershipId =
      inv['membership_id_snapshot'] as String? ??
      memberSnapshot['membership_id'] as String?;

  final status = inv['status'] as String? ?? 'unknown';
  final amount = (inv['amount'] as num?) ?? 0;
  final originalAmount = (inv['original_amount'] as num?);
  final discountAmount = (inv['discount_amount'] as num?) ?? 0;
  final admissionFee = (inv['admission_fee'] as num?) ?? 0;
  final taxableAmount = (inv['taxable_amount'] as num?) ?? amount;
  final gstAmount = (inv['gst_amount'] as num?) ?? 0;
  final cgstAmount = (inv['cgst_amount'] as num?) ?? 0;
  final sgstAmount = (inv['sgst_amount'] as num?) ?? 0;
  final igstAmount = (inv['igst_amount'] as num?) ?? 0;
  final hasDiscount = discountAmount > 0 && settings['show_discount'] != false;
  final notes = inv['notes'] as String?;
  final description = ((inv['description'] as String?)?.isNotEmpty == true)
      ? inv['description'] as String
      : 'Membership fee';
  final payments = (inv['payments'] as List?) ?? const [];
  final paidSoFar = payments
      .where((p) => (p as Map)['status'] == 'succeeded')
      .fold<double>(0, (s, p) => s + ((p as Map)['amount'] as num).toDouble());
  final balanceDue = (amount - paidSoFar).clamp(0, amount);
  final isPartial = paidSoFar > 0 && balanceDue > 0;

  final invNum = invoiceNumber(
    inv['id'] as String,
    inv['created_at'] as String,
    issuedNumber: inv['invoice_number'] as String?,
  );
  final issueDate = formatDateFromString(inv['created_at'] as String?);
  final dueDate = inv['due_at'] != null
      ? formatDateFromString(inv['due_at'] as String?)
      : '—';
  final paidOn = inv['paid_at'] != null
      ? formatDateFromString(inv['paid_at'] as String?)
      : null;
  final generatedDate = inv['generated_at'] != null
      ? formatDateFromString(inv['generated_at'] as String?)
      : issueDate;

  final (statusLabel, statusBg) = _statusInfo(status);

  final pdf = pw.Document();
  final theme = pw.ThemeData.withFont(base: regular, bold: bold);

  pdf.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      theme: theme,
      margin: const pw.EdgeInsets.fromLTRB(40, 40, 40, 32),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // ── Header ────────────────────────────────────────────────────
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    if (logo != null) ...[
                      pw.Image(logo, height: 34, fit: pw.BoxFit.contain),
                      pw.SizedBox(height: 7),
                    ],
                    pw.Text(
                      gymName,
                      style: pw.TextStyle(font: bold, fontSize: 18),
                    ),
                    if (ownerName != null && ownerName.isNotEmpty)
                      pw.Text(
                        ownerName,
                        style: pw.TextStyle(
                          font: regular,
                          fontSize: 10,
                          color: PdfColors.grey700,
                        ),
                      ),
                    if (address != null) ...[
                      pw.SizedBox(height: 3),
                      pw.Text(
                        address,
                        style: pw.TextStyle(
                          font: regular,
                          fontSize: 10,
                          color: PdfColors.grey700,
                        ),
                      ),
                    ],
                    if (phone != null)
                      pw.Text(
                        phone,
                        style: pw.TextStyle(
                          font: regular,
                          fontSize: 10,
                          color: PdfColors.grey700,
                        ),
                      ),
                    if (website != null)
                      pw.Text(
                        website,
                        style: pw.TextStyle(
                          font: regular,
                          fontSize: 10,
                          color: PdfColors.grey700,
                        ),
                      ),
                    if (gstin != null && gstin.isNotEmpty)
                      pw.Text(
                        'GSTIN: $gstin',
                        style: pw.TextStyle(
                          font: regular,
                          fontSize: 10,
                          color: PdfColors.grey700,
                        ),
                      ),
                  ],
                ),
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    'INVOICE',
                    style: pw.TextStyle(
                      font: regular,
                      fontSize: 9,
                      color: PdfColors.grey500,
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    invNum,
                    style: pw.TextStyle(font: bold, fontSize: 13),
                  ),
                  pw.SizedBox(height: 8),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: pw.BoxDecoration(
                      color: statusBg,
                      borderRadius: const pw.BorderRadius.all(
                        pw.Radius.circular(4),
                      ),
                    ),
                    child: pw.Text(
                      statusLabel,
                      style: pw.TextStyle(
                        font: bold,
                        fontSize: 9,
                        color: PdfColors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),

          pw.SizedBox(height: 14),
          pw.Divider(thickness: 2, color: PdfColors.grey900),
          pw.SizedBox(height: 14),

          // ── Dates ─────────────────────────────────────────────────────
          pw.Row(
            children: [
              if (settings['show_invoice_date'] != false)
                _dateCell(regular, bold, 'ISSUE DATE', issueDate),
              if (settings['show_invoice_date'] != false)
                pw.SizedBox(width: 28),
              pw.SizedBox(width: 28),
              _dateCell(regular, bold, 'DUE DATE', dueDate),
              if (settings['show_generated_date'] != false) ...[
                pw.SizedBox(width: 28),
                _dateCell(regular, bold, 'GENERATED', generatedDate),
              ],
              if (paidOn != null) ...[
                pw.SizedBox(width: 28),
                _dateCell(
                  regular,
                  bold,
                  'PAID ON',
                  paidOn,
                  valueColor: PdfColors.green700,
                ),
              ],
            ],
          ),

          pw.SizedBox(height: 16),
          pw.Divider(color: PdfColors.grey300),
          pw.SizedBox(height: 14),

          // ── Bill To ───────────────────────────────────────────────────
          pw.Text(
            'BILL TO',
            style: pw.TextStyle(
              font: regular,
              fontSize: 9,
              color: PdfColors.grey500,
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Text(memberName, style: pw.TextStyle(font: bold, fontSize: 14)),
          if (memberEmail.isNotEmpty) ...[
            pw.SizedBox(height: 2),
            pw.Text(
              memberEmail,
              style: pw.TextStyle(
                font: regular,
                fontSize: 12,
                color: PdfColors.grey700,
              ),
            ),
          ],
          if (settings['show_membership_id'] != false &&
              membershipId != null &&
              membershipId.isNotEmpty) ...[
            pw.SizedBox(height: 2),
            pw.Text(
              'Membership ID: $membershipId',
              style: pw.TextStyle(
                font: regular,
                fontSize: 10,
                color: PdfColors.grey700,
              ),
            ),
          ],

          pw.SizedBox(height: 16),
          pw.Divider(color: PdfColors.grey300),
          pw.SizedBox(height: 12),

          // ── Line item ─────────────────────────────────────────────────
          pw.Row(
            children: [
              pw.Expanded(
                child: pw.Text(
                  'DESCRIPTION',
                  style: pw.TextStyle(
                    font: regular,
                    fontSize: 9,
                    color: PdfColors.grey500,
                  ),
                ),
              ),
              pw.Text(
                'AMOUNT',
                style: pw.TextStyle(
                  font: regular,
                  fontSize: 9,
                  color: PdfColors.grey500,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Divider(thickness: 0.5, color: PdfColors.grey300),
          pw.SizedBox(height: 8),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Text(
                  description,
                  style: pw.TextStyle(font: regular, fontSize: 13),
                ),
              ),
              pw.SizedBox(width: 16),
              pw.Text(
                formatCurrency(originalAmount ?? amount),
                style: pw.TextStyle(font: bold, fontSize: 13),
              ),
            ],
          ),

          pw.SizedBox(height: 12),
          pw.Divider(color: PdfColors.grey300),

          // ── Discount row (only when a discount was applied) ────────────
          if (hasDiscount) ...[
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 8),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'DISCOUNT',
                    style: pw.TextStyle(
                      font: regular,
                      fontSize: 10,
                      color: PdfColors.green700,
                    ),
                  ),
                  pw.Text(
                    '− ${formatCurrency(discountAmount)}',
                    style: pw.TextStyle(
                      font: bold,
                      fontSize: 13,
                      color: PdfColors.green700,
                    ),
                  ),
                ],
              ),
            ),
            pw.Divider(color: PdfColors.grey300),
          ],

          if (settings['show_admission_fee'] != false && admissionFee > 0) ...[
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 8),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'ADMISSION FEE',
                    style: pw.TextStyle(
                      font: regular,
                      fontSize: 10,
                      color: PdfColors.grey700,
                    ),
                  ),
                  pw.Text(
                    formatCurrency(admissionFee),
                    style: pw.TextStyle(font: bold, fontSize: 13),
                  ),
                ],
              ),
            ),
            pw.Divider(color: PdfColors.grey300),
          ],

          if (settings['show_gst_breakup'] == true && gstAmount > 0) ...[
            _pdfAmountRow(regular, bold, 'TAXABLE VALUE', taxableAmount),
            if (cgstAmount > 0)
              _pdfAmountRow(regular, bold, 'CGST', cgstAmount),
            if (sgstAmount > 0)
              _pdfAmountRow(regular, bold, 'SGST', sgstAmount),
            if (igstAmount > 0)
              _pdfAmountRow(regular, bold, 'IGST', igstAmount),
            pw.Divider(color: PdfColors.grey300),
          ],

          // ── Paid so far row (only when a partial payment was made) ─────
          if (isPartial) ...[
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 8),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'PAID SO FAR',
                    style: pw.TextStyle(
                      font: regular,
                      fontSize: 10,
                      color: PdfColors.green700,
                    ),
                  ),
                  pw.Text(
                    formatCurrency(paidSoFar),
                    style: pw.TextStyle(
                      font: bold,
                      fontSize: 13,
                      color: PdfColors.green700,
                    ),
                  ),
                ],
              ),
            ),
            pw.Divider(color: PdfColors.grey300),
          ],

          // ── Total ─────────────────────────────────────────────────────
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 14),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  isPartial ? 'BALANCE DUE' : 'TOTAL DUE',
                  style: pw.TextStyle(
                    font: regular,
                    fontSize: 10,
                    color: PdfColors.grey600,
                  ),
                ),
                pw.Text(
                  formatCurrency(isPartial ? balanceDue : amount),
                  style: pw.TextStyle(font: bold, fontSize: 22),
                ),
              ],
            ),
          ),
          pw.Divider(color: PdfColors.grey300),

          // ── Notes ─────────────────────────────────────────────────────
          if (notes != null && notes.isNotEmpty) ...[
            pw.SizedBox(height: 14),
            pw.Text(
              'NOTES',
              style: pw.TextStyle(
                font: regular,
                fontSize: 9,
                color: PdfColors.grey500,
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Text(
              notes,
              style: pw.TextStyle(
                font: regular,
                fontSize: 12,
                color: PdfColors.grey700,
              ),
            ),
          ],
          if (refundPolicy != null && refundPolicy.isNotEmpty) ...[
            pw.SizedBox(height: 10),
            pw.Text(
              'REFUND POLICY',
              style: pw.TextStyle(
                font: regular,
                fontSize: 9,
                color: PdfColors.grey500,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              refundPolicy,
              style: pw.TextStyle(
                font: regular,
                fontSize: 9,
                color: PdfColors.grey700,
              ),
            ),
          ],
          if (terms != null && terms.isNotEmpty) ...[
            pw.SizedBox(height: 10),
            pw.Text(
              'TERMS & CONDITIONS',
              style: pw.TextStyle(
                font: regular,
                fontSize: 9,
                color: PdfColors.grey500,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              terms,
              style: pw.TextStyle(
                font: regular,
                fontSize: 9,
                color: PdfColors.grey700,
              ),
            ),
          ],

          pw.Spacer(),

          // ── Footer ────────────────────────────────────────────────────
          pw.Divider(color: PdfColors.grey300),
          pw.SizedBox(height: 6),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                invNum,
                style: pw.TextStyle(
                  font: regular,
                  fontSize: 9,
                  color: PdfColors.grey400,
                ),
              ),
              pw.Text(
                'Powered by GymCRM',
                style: pw.TextStyle(
                  font: regular,
                  fontSize: 9,
                  color: PdfColors.grey400,
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  return pdf.save();
}

/// Public — also used by InvoiceDetailScreen for the AppBar title and body.
String invoiceNumber(String id, String createdAt, {String? issuedNumber}) {
  if (issuedNumber != null && issuedNumber.trim().isNotEmpty) {
    return issuedNumber.trim();
  }
  final dt = DateTime.parse(createdAt);
  final month = '${dt.year}${dt.month.toString().padLeft(2, '0')}';
  final shortId = id.replaceAll('-', '').substring(0, 6).toUpperCase();
  return 'INV-$month-$shortId';
}

// ── Private helpers ─────────────────────────────────────────────────────────

pw.Widget _dateCell(
  pw.Font regular,
  pw.Font bold,
  String label,
  String value, {
  PdfColor valueColor = PdfColors.grey900,
}) => pw.Column(
  crossAxisAlignment: pw.CrossAxisAlignment.start,
  children: [
    pw.Text(
      label,
      style: pw.TextStyle(font: regular, fontSize: 9, color: PdfColors.grey500),
    ),
    pw.SizedBox(height: 3),
    pw.Text(
      value,
      style: pw.TextStyle(font: bold, fontSize: 12, color: valueColor),
    ),
  ],
);

(String, PdfColor) _statusInfo(String status) => switch (status) {
  'paid' => ('PAID', PdfColors.green700),
  'open' => ('PENDING', PdfColors.orange700),
  'partial' => ('PARTIAL', PdfColors.orange700),
  'failed' => ('FAILED', PdfColors.red700),
  'void' => ('VOID', PdfColors.grey600),
  _ => ('DRAFT', PdfColors.grey600),
};

pw.Widget _pdfAmountRow(
  pw.Font regular,
  pw.Font bold,
  String label,
  num amount,
) => pw.Padding(
  padding: const pw.EdgeInsets.symmetric(vertical: 4),
  child: pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: [
      pw.Text(
        label,
        style: pw.TextStyle(
          font: regular,
          fontSize: 9,
          color: PdfColors.grey600,
        ),
      ),
      pw.Text(
        formatCurrencyExact(amount),
        style: pw.TextStyle(font: bold, fontSize: 11),
      ),
    ],
  ),
);
