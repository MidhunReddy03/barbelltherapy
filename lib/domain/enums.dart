/// Enums shared across the app. Drift stores these via `textEnum` using the
/// enum member names, which match the spec's string values exactly.
//
// Storage keys like `upi_qr`, `one_time`, `per_plan` and `dues_weekly` come
// straight from the spec's data model, so snake_case names are intentional.
// ignore_for_file: constant_identifier_names
enum PaymentMode { cash, upi_qr, card, other }

enum AddonBilling { one_time, per_plan }

enum DiscountType { none, flat, percent }

enum MessageChannel { whatsapp, sms }

enum LanguageCode { en, te }

/// Reminder / message-log types (spec section 4). Member names double as the
/// storage keys, e.g. `expiry_7`, `dues_weekly`.
enum MessageType {
  expiry_7,
  expiry_3,
  expiry_1,
  expiry_0,
  expired_3,
  expired_7,
  dues_weekly,
  welcome,
  receipt,
  inactivity,
  announcement;

  /// The expiry-day offset this type corresponds to, or null for
  /// non-expiry types. Positive = days before expiry, 0 = expiry day,
  /// negative = days after expiry.
  int? get expiryOffset {
    switch (this) {
      case expiry_7:
        return 7;
      case expiry_3:
        return 3;
      case expiry_1:
        return 1;
      case expiry_0:
        return 0;
      case expired_3:
        return -3;
      case expired_7:
        return -7;
      case dues_weekly:
      case welcome:
      case receipt:
      case inactivity:
      case announcement:
        return null;
    }
  }

  static MessageType? fromOffset(int offset) {
    for (final t in MessageType.values) {
      if (t.expiryOffset == offset) return t;
    }
    return null;
  }
}
