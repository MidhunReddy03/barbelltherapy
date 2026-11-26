/// Indian phone number handling (spec 5.7).
///
/// Numbers are normalized to 10 digits and validated with `^[6-9]\d{9}$`.
/// WhatsApp links use the `91` prefix.
class PhoneUtils {
  PhoneUtils._();

  static final RegExp _valid = RegExp(r'^[6-9]\d{9}$');

  /// Strips spaces, dashes, parentheses, `+91`/`91` prefixes and a leading 0,
  /// and keeps digits only.
  static String normalize(String raw) {
    var digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 12 && digits.startsWith('91')) {
      digits = digits.substring(2);
    }
    if (digits.length == 11 && digits.startsWith('0')) {
      digits = digits.substring(1);
    }
    if (digits.length == 13 && digits.startsWith('091')) {
      digits = digits.substring(3);
    }
    return digits;
  }

  /// True when the normalized number matches `^[6-9]\d{9}$`.
  static bool isValid(String normalized) => _valid.hasMatch(normalized);

  /// Normalize + validate. Returns null when invalid.
  static String? normalizeOrNull(String raw) {
    final n = normalize(raw);
    return isValid(n) ? n : null;
  }

  /// Phone call URI for url_launcher.
  static Uri telUri(String normalizedPhone) => Uri.parse('tel:$normalizedPhone');

  /// `https://wa.me/91XXXXXXXXXX?text=...` for the semi-automatic WhatsApp flow.
  static Uri whatsappUri(String normalizedPhone, String message) {
    final text = Uri.encodeComponent(message);
    return Uri.parse('https://wa.me/91$normalizedPhone?text=$text');
  }

  /// SMS fallback used when WhatsApp is not installed.
  static Uri smsUri(String normalizedPhone, String message) {
    final text = Uri.encodeComponent(message);
    return Uri.parse('sms:$normalizedPhone?body=$text');
  }

  /// Display form: 98765 43210
  static String display(String normalized) {
    if (normalized.length != 10) return normalized;
    return '${normalized.substring(0, 5)} ${normalized.substring(5)}';
  }
}
