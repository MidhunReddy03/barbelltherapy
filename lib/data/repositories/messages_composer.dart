import '../../core/utils/app_date_utils.dart';
import 'members_repository.dart';
import 'reminders_repository.dart';
import 'settings_repository.dart';
import '../../domain/enums.dart';
import '../../domain/membership_status.dart';
import '../../domain/template_engine.dart';

/// Composes a WhatsApp message for a member outside the reminders tab —
/// used by member-profile quick actions and members-list swipe actions
/// (spec 6.3 "opens the right template by status").
///
/// Mapping (logged in DECISIONS.md):
///  - no plan / upcoming        -> `welcome`
///  - days left 4..7            -> `expiry_7`
///  - days left 1..3            -> `expiry_3`
///  - days left 0               -> `expiry_0`
///  - expired 1..3 days         -> `expired_3`
///  - expired 4+ days           -> `expired_7`
class MessagesComposer {
  MessagesComposer(this._settings, this._reminders);

  final SettingsRepository _settings;
  final RemindersRepository _reminders;

  /// Returns `(type, templateId, renderedBody)`, or null when no template
  /// exists for the language.
  Future<(MessageType, int, String)?> composeByStatus({
    required MemberListRow member,
    required MembershipStatusResult status,
    required LanguageCode language,
  }) async {
    MessageType type;
    final daysLeft = status.daysLeft ?? 0;
    switch (status.status) {
      case MembershipStatus.noPlan:
      case MembershipStatus.upcoming:
        type = MessageType.welcome;
        break;
      case MembershipStatus.frozen:
        // No reminder for frozen members; a friendly "come back" message is
        // the closest match.
        type = MessageType.inactivity;
        break;
      case MembershipStatus.expired:
        type = daysLeft >= -3 ? MessageType.expired_3 : MessageType.expired_7;
        break;
      case MembershipStatus.expiringSoon:
      case MembershipStatus.active:
        if (daysLeft <= 0) {
          type = MessageType.expiry_0;
        } else if (daysLeft <= 3) {
          type = MessageType.expiry_3;
        } else {
          type = MessageType.expiry_7;
        }
        break;
    }

    final template = await _reminders.templateFor(type, language);
    if (template == null) return null;
    final (templateId, body) = template;

    final gymName = await _settings.get(SettingKeys.gymName);
    final gymPhone = await _settings.get(SettingKeys.gymPhone);
    final endDate = AppDateUtils.parse(member.endDate);
    final startDate = AppDateUtils.parse(member.startDate);

    final values = <String, String?>{
      'name': member.name,
      'plan': member.planName,
      'member_code': member.memberCode,
      'end_date': endDate == null ? null : _short(endDate),
      'start_date': startDate == null ? null : _short(startDate),
      'days_left': '$daysLeft',
      'days_away': '${status.daysLeft == null ? 0 : -daysLeft}',
      'amount_due': member.due > 0 ? '${member.due}' : null,
      'gym_name': gymName,
      'gym_phone': gymPhone,
    };

    return (type, templateId, TemplateEngine.render(body, values));
  }

  static String _short(DateTime d) =>
      '${d.day} ${_monthShort(d.month)} ${d.year}';

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String _monthShort(int m) => _months[m - 1];
}
