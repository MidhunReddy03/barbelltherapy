import 'package:flutter_test/flutter_test.dart';
import 'package:gymdesk/core/utils/phone_utils.dart';

void main() {
  group('normalize', () {
    test('plain 10 digits stays as-is', () {
      expect(PhoneUtils.normalize('9876543210'), '9876543210');
    });

    test('strips spaces and dashes', () {
      expect(PhoneUtils.normalize('98765 43210'), '9876543210');
      expect(PhoneUtils.normalize('987-654-3210'), '9876543210');
    });

    test('strips +91 and 91 prefixes', () {
      expect(PhoneUtils.normalize('+919876543210'), '9876543210');
      expect(PhoneUtils.normalize('919876543210'), '9876543210');
    });

    test('strips a leading 0', () {
      expect(PhoneUtils.normalize('09876543210'), '9876543210');
    });

    test('landline-style 091+ prefix', () {
      expect(PhoneUtils.normalize('0919876543210'), '9876543210');
    });
  });

  group('isValid', () {
    test('valid mobile numbers start with 6-9', () {
      expect(PhoneUtils.isValid('9876543210'), isTrue);
      expect(PhoneUtils.isValid('6000000000'), isTrue);
      expect(PhoneUtils.isValid('9999999999'), isTrue);
    });

    test('invalid numbers are rejected', () {
      expect(PhoneUtils.isValid('1234567890'), isFalse); // starts with 1
      expect(PhoneUtils.isValid('5876543210'), isFalse); // starts with 5
      expect(PhoneUtils.isValid('987654321'), isFalse); // 9 digits
      expect(PhoneUtils.isValid('98765432101'), isFalse); // 11 digits
      expect(PhoneUtils.isValid(''), isFalse);
    });

    test('normalizeOrNull returns null for garbage', () {
      expect(PhoneUtils.normalizeOrNull('abc'), isNull);
      expect(PhoneUtils.normalizeOrNull('+919876543210'), '9876543210');
    });
  });

  group('links', () {
    test('whatsapp URI uses 91 prefix and URL-encoded text', () {
      final uri = PhoneUtils.whatsappUri('9876543210', 'Hi 🙏 Renew & stay fit');
      expect(uri.scheme, 'https');
      expect(uri.host, 'wa.me');
      expect(uri.path, '/919876543210');
      final text = uri.queryParameters['text']!;
      expect(text, 'Hi 🙏 Renew & stay fit');
    });

    test('sms fallback URI carries the body', () {
      final uri = PhoneUtils.smsUri('9876543210', 'Renew please');
      expect(uri.scheme, 'sms');
      expect(uri.path, '9876543210');
      expect(uri.queryParameters['body'], 'Renew please');
    });

    test('display formatting', () {
      expect(PhoneUtils.display('9876543210'), '98765 43210');
    });
  });
}
