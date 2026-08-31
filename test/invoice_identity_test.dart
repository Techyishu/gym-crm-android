import 'package:flutter_test/flutter_test.dart';
import 'package:gym_crm/core/utils/invoice_pdf.dart';
import 'package:gym_crm/shared/models/invoice.dart';

void main() {
  test('issued server number wins over the legacy generated number', () {
    expect(
      invoiceNumber(
        '12345678-1234-4123-8123-123456789012',
        '2026-08-28T10:00:00Z',
        issuedNumber: 'GYM-000042',
      ),
      'GYM-000042',
    );
  });

  test('invoice model retains immutable identity and admission fee', () {
    final invoice = Invoice.fromJson({
      'id': '12345678-1234-4123-8123-123456789012',
      'member_id': 'member',
      'gym_id': 'gym',
      'invoice_number': 'INV-000007',
      'amount': 1180,
      'original_amount': 1000,
      'discount_amount': 20,
      'admission_fee': 200,
      'status': 'open',
      'created_at': '2026-08-28T10:00:00Z',
    });

    expect(invoice.invoiceNumber, 'INV-000007');
    expect(invoice.originalAmount, 1000);
    expect(invoice.admissionFee, 200);
    expect(invoice.discountAmount, 20);
  });
}
