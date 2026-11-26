import 'package:flutter_test/flutter_test.dart';
import 'package:gymdesk/domain/template_engine.dart';

void main() {
  group('TemplateEngine.render', () {
    test('replaces all provided placeholders', () {
      final out = TemplateEngine.render(
        'Hi {name}, welcome to {gym_name}! Your {plan} ends {end_date}.',
        {
          'name': 'Ravi',
          'gym_name': 'Iron House',
          'plan': 'Monthly',
          'end_date': '13 Dec',
        },
      );
      expect(out, 'Hi Ravi, welcome to Iron House! Your Monthly ends 13 Dec.');
    });

    test('drops the sentence containing a missing value', () {
      final out = TemplateEngine.render(
        'Hi {name}, welcome to {gym_name}! Member ID: {member_code}. See you!',
        {'name': 'Ravi', 'gym_name': 'Iron House'},
      );
      expect(out, 'Hi Ravi, welcome to Iron House! See you!');
    });

    test('drops the whole message when it is a single sentence', () {
      final out = TemplateEngine.render(
        'Hi {name}, ₹{amount_due} is pending.',
        {'name': 'Ravi'},
      );
      expect(out, '');
    });

    test('missing name removes the greeting but keeps the rest', () {
      final out = TemplateEngine.render(
        'Hi {name}, your membership ends on {end_date}. Please renew!',
        {'end_date': '13 Dec'},
      );
      expect(out, 'Please renew!');
    });

    test('handles Telugu sentences with danda', () {
      final out = TemplateEngine.render(
        'నమస్కారం {name} గారు, మీ మెంబర్‌షిప్ {end_date} న ముగుస్తుంది. ధన్యవాదాలు!',
        {'end_date': '13 Dec'},
      );
      // The whole first sentence is dropped because {name} is missing
      // (spec 7: remove the whole sentence, never show a bare {}).
      expect(out, 'ధన్యవాదాలు!');
      expect(out, isNot(contains('{name}')));
    });

    test('newlines separate implicit sentences', () {
      final out = TemplateEngine.render(
        'Holiday notice\nGym closed on {missing_value}\nReopens Monday',
        {},
      );
      expect(out, 'Holiday notice\nReopens Monday');
    });

    test('placeholdersIn lists unique keys', () {
      final keys = TemplateEngine.placeholdersIn(
        '{name} {name} {plan} {end_date}',
      );
      expect(keys, ['name', 'plan', 'end_date']);
    });
  });
}
