import 'package:flutter_test/flutter_test.dart';
import 'package:gymdesk/domain/enums.dart';
import 'package:gymdesk/domain/pricing_calculator.dart';

void main() {
  group('PricingCalculator.compute', () {
    test('subtotal without add-ons or discount', () {
      final r = PricingCalculator.compute(
        planPrice: 1000,
        addonPrices: [],
        admissionFee: 0,
        discountType: DiscountType.none,
        discountValue: 0,
      );
      expect(r.subtotal, 1000);
      expect(r.discount, 0);
      expect(r.total, 1000);
    });

    test('subtotal includes add-ons and admission fee', () {
      final r = PricingCalculator.compute(
        planPrice: 1000,
        addonPrices: [500, 300],
        admissionFee: 200,
        discountType: DiscountType.none,
        discountValue: 0,
      );
      expect(r.subtotal, 2000);
      expect(r.total, 2000);
    });

    test('flat discount subtracts rupees', () {
      final r = PricingCalculator.compute(
        planPrice: 1000,
        addonPrices: [500],
        admissionFee: 200,
        discountType: DiscountType.flat,
        discountValue: 300,
      );
      expect(r.total, 1400);
    });

    test('percent discount applies to plan + add-ons, not admission fee', () {
      // plan 1000 + addon 500 = 1500; 10% -> 150 off; admission 200 untaxed.
      final r = PricingCalculator.compute(
        planPrice: 1000,
        addonPrices: [500],
        admissionFee: 200,
        discountType: DiscountType.percent,
        discountValue: 10,
      );
      expect(r.discount, 150);
      expect(r.total, 1700 - 150); // subtotal 1700 - 150 = 1550
    });

    test('percent discount is rounded to the nearest rupee', () {
      // plan 999, 10% -> 99.9 -> rounds to 100.
      final r = PricingCalculator.compute(
        planPrice: 999,
        addonPrices: [],
        admissionFee: 0,
        discountType: DiscountType.percent,
        discountValue: 10,
      );
      expect(r.discount, 100);
      expect(r.total, 899);
    });

    test('discount larger than subtotal never goes below 0', () {
      final r = PricingCalculator.compute(
        planPrice: 500,
        addonPrices: [],
        admissionFee: 0,
        discountType: DiscountType.flat,
        discountValue: 900,
      );
      expect(r.total, 0);
    });

    test('zero-price plan is allowed', () {
      final r = PricingCalculator.compute(
        planPrice: 0,
        addonPrices: [],
        admissionFee: 0,
        discountType: DiscountType.none,
        discountValue: 0,
      );
      expect(r.total, 0);
    });
  });

  group('Dues and payment state', () {
    test('due math', () {
      expect(
        PricingCalculator.due(total: 1500, paid: 500),
        1000,
      );
      expect(PricingCalculator.due(total: 1500, paid: 1500), 0);
      // Defensive: over-payment never shows negative dues.
      expect(PricingCalculator.due(total: 1500, paid: 2000), 0);
    });

    test('payment states', () {
      expect(
        PricingCalculator.paymentState(total: 1000, paid: 0),
        SubscriptionPaymentState.unpaid,
      );
      expect(
        PricingCalculator.paymentState(total: 1000, paid: 400),
        SubscriptionPaymentState.partial,
      );
      expect(
        PricingCalculator.paymentState(total: 1000, paid: 1000),
        SubscriptionPaymentState.paid,
      );
    });

    test('payment amount validation', () {
      expect(
        PricingCalculator.validatePaymentAmount(
          amount: 600,
          total: 1500,
          paidSoFar: 500,
        ),
        isNull,
      );
      expect(
        PricingCalculator.validatePaymentAmount(
          amount: 1001,
          total: 1500,
          paidSoFar: 500,
        ),
        'Amount exceeds balance of ₹1000',
      );
      expect(
        PricingCalculator.validatePaymentAmount(
          amount: 0,
          total: 1500,
          paidSoFar: 0,
        ),
        isNotNull,
      );
    });
  });
}
