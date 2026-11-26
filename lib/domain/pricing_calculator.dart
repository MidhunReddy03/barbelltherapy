import 'enums.dart';

/// Pricing and dues math (spec 5.3). All values are integer rupees.
class PricingCalculator {
  PricingCalculator._();

  /// Computes the total for a subscription at creation time.
  ///
  /// - subtotal = plan price + add-on prices + admission fee
  /// - `flat` discount subtracts the rupee value from the subtotal
  /// - `percent` discount applies to plan + add-ons only, **not** the
  ///   admission fee, and is rounded to the nearest rupee (documented in
  ///   DECISIONS.md per spec 5.3)
  /// - the total never goes below 0
  static PricingResult compute({
    required int planPrice,
    required List<int> addonPrices,
    required int admissionFee,
    required DiscountType discountType,
    required int discountValue,
  }) {
    final addonsTotal = addonPrices.fold(0, (sum, p) => sum + p);
    final beforeAdmission = planPrice + addonsTotal;
    final subtotal = beforeAdmission + admissionFee;

    var discount = 0;
    switch (discountType) {
      case DiscountType.none:
        discount = 0;
        break;
      case DiscountType.flat:
        discount = discountValue;
        break;
      case DiscountType.percent:
        discount = (beforeAdmission * discountValue / 100).round();
        break;
    }
    if (discount < 0) discount = 0;

    var total = subtotal - discount;
    if (total < 0) total = 0;

    return PricingResult(
      subtotal: subtotal,
      discount: discount,
      total: total,
    );
  }

  /// Dues for a subscription: `total - paid`, never negative (over-payment is
  /// rejected at entry time instead).
  static int due({required int total, required int paid}) {
    final d = total - paid;
    return d < 0 ? 0 : d;
  }

  /// Payment state for the UI (spec 5.3).
  static SubscriptionPaymentState paymentState({
    required int total,
    required int paid,
  }) {
    if (paid <= 0) return SubscriptionPaymentState.unpaid;
    if (paid >= total) return SubscriptionPaymentState.paid;
    return SubscriptionPaymentState.partial;
  }

  /// Validates a payment amount against the remaining balance.
  /// Returns an error message, or null when the amount is acceptable.
  static String? validatePaymentAmount({
    required int amount,
    required int total,
    required int paidSoFar,
  }) {
    if (amount <= 0) return 'Enter an amount greater than ₹0';
    final balance = due(total: total, paid: paidSoFar);
    if (amount > balance) {
      return 'Amount exceeds balance of ₹$balance';
    }
    return null;
  }
}

class PricingResult {
  const PricingResult({
    required this.subtotal,
    required this.discount,
    required this.total,
  });

  /// plan + add-ons + admission fee.
  final int subtotal;
  final int discount;
  final int total;
}

enum SubscriptionPaymentState { paid, partial, unpaid }

extension SubscriptionPaymentStateX on SubscriptionPaymentState {
  String get label {
    switch (this) {
      case SubscriptionPaymentState.paid:
        return 'Paid';
      case SubscriptionPaymentState.partial:
        return 'Partial';
      case SubscriptionPaymentState.unpaid:
        return 'Unpaid';
    }
  }
}
