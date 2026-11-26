import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/providers/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/app_date_utils.dart';
import '../../core/utils/app_formatters.dart';
import '../../core/utils/phone_utils.dart';
import '../../core/widgets/common_widgets.dart';
import '../../core/widgets/status_pill.dart';
import '../../data/repositories/reminders_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../domain/template_engine.dart';

/// Reminders screen matching GymDesk App Screens (page_7aac60db.html).
class RemindersScreen extends ConsumerStatefulWidget {
  const RemindersScreen({super.key});

  @override
  ConsumerState<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends ConsumerState<RemindersScreen> {
  late Future<List<PendingReminder>> _future;
  String _samplePreview = 'Hi Sneha, your GymDesk Quarterly plan ends in 3 days on 18 Nov. Renew today to keep your streak! ₹500 due balance.';

  @override
  void initState() {
    super.initState();
    _future = _load();
    _updateSamplePreview();
  }

  Future<List<PendingReminder>> _load() =>
      ref.read(remindersRepositoryProvider).todayReminders();

  void _refresh() {
    setState(() => _future = _load());
    _updateSamplePreview();
  }

  Future<void> _updateSamplePreview() async {
    final list = await _load();
    if (list.isNotEmpty) {
      final first = list.first;
      final repo = ref.read(remindersRepositoryProvider);
      final settings = ref.read(settingsRepositoryProvider);
      final lang = await settings.defaultLanguage();
      final tmpl = await repo.templateFor(first.selection.type, lang);
      if (tmpl != null) {
        final values = {
          'name': first.candidate.name,
          'plan': first.candidate.planName,
          'end_date': AppFormatters.dateShort(AppDateUtils.parse(first.candidate.endDate) ?? AppDateUtils.today()),
          'days_left': '${first.daysLeft}',
          'amount_due': first.candidate.due > 0 ? '${first.candidate.due}' : null,
          'gym_name': await settings.get(SettingKeys.gymName),
        };
        if (mounted) {
          setState(() => _samplePreview = TemplateEngine.render(tmpl.$2, values));
        }
      }
    }
  }

  Future<void> _send(PendingReminder reminder) async {
    final repo = ref.read(remindersRepositoryProvider);
    final settings = ref.read(settingsRepositoryProvider);
    final language = await settings.defaultLanguage();

    final template = await repo.templateFor(
      reminder.selection.type,
      language,
    );
    if (!mounted) return;
    if (template == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No template found for this reminder type.')),
      );
      return;
    }
    final (templateId, body) = template;

    final values = {
      'name': reminder.candidate.name,
      'plan': reminder.candidate.planName,
      'end_date': AppFormatters.dateShort(
          AppDateUtils.parse(reminder.candidate.endDate) ??
              AppDateUtils.today()),
      'days_left': '${reminder.daysLeft}',
      'amount_due': reminder.candidate.due > 0 ? '${reminder.candidate.due}' : null,
      'gym_name': await settings.get(SettingKeys.gymName),
      'gym_phone': await settings.get(SettingKeys.gymPhone),
      'member_code': reminder.candidate.memberCode,
      'start_date': reminder.candidate.startDate,
    };
    final rendered = TemplateEngine.render(body, values);

    final edited = await _showPreviewDialog(rendered);
    if (edited == null || edited.trim().isEmpty || !mounted) return;

    final uri = PhoneUtils.whatsappUri(reminder.candidate.phone, edited);
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      final sms = PhoneUtils.smsUri(reminder.candidate.phone, edited);
      await launchUrl(sms, mode: LaunchMode.externalApplication);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('WhatsApp not found — opened SMS instead.')),
        );
      }
    }

    if (!mounted) return;
    final confirmed = await _showSentSheet();
    if (confirmed) {
      await repo.markSent(
        memberId: reminder.candidate.memberId,
        subscriptionId: reminder.candidate.subscriptionId,
        type: reminder.selection.type,
        templateId: templateId,
      );
      _refresh();
    }
  }

  Future<String?> _showPreviewDialog(String initial) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text('MESSAGE PREVIEW', style: AppTheme.dsp(fontSize: 20)),
        content: TextField(
          controller: controller,
          maxLines: 6,
          decoration: const InputDecoration(hintText: 'Edit message before sending...'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondaryDark)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: AppColors.onAccent,
            ),
            child: const Text('Open WhatsApp'),
          ),
        ],
      ),
    );
  }

  Future<bool> _showSentSheet() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.surfaceDark,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'DID YOU SEND IT?',
                style: AppTheme.dsp(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              const Text(
                'Marking as sent logs this notification and suppresses duplicate reminders for today.',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondaryDark),
              ),
              const SizedBox(height: 20),
              PrimaryButton(
                label: 'Yes, mark as sent ✓',
                onPressed: () => Navigator.pop(context, true),
              ),
              const SizedBox(height: 10),
              SecondaryButton(
                label: 'No, keep pending',
                onPressed: () => Navigator.pop(context, false),
              ),
            ],
          ),
        ),
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: SafeArea(
        child: FutureBuilder<List<PendingReminder>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: AppColors.accent));
            }
            final reminders = snapshot.data ?? const <PendingReminder>[];

            return RefreshIndicator(
              color: AppColors.accent,
              backgroundColor: AppColors.surfaceDark,
              onRefresh: () async => _refresh(),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 90),
                children: [
                  // Top Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'REMINDERS',
                        style: AppTheme.dsp(fontSize: 32, fontWeight: FontWeight.w700),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: AppTheme.cardDecoration(),
                        child: Text(
                          '${reminders.length} PENDING',
                          style: AppTheme.cap(color: reminders.isEmpty ? AppColors.statusActive : AppColors.statusExpiring),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // WhatsApp Message Preview Card matching HTML
                  SectionCard(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('WHATSAPP MESSAGE PREVIEW', style: AppTheme.cap()),
                            const Text('One tap opens wa.me', style: TextStyle(fontSize: 11, color: AppColors.textSecondaryDark)),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.whatsappBubble,
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(4),
                              topRight: Radius.circular(12),
                              bottomLeft: Radius.circular(12),
                              bottomRight: Radius.circular(12),
                            ),
                          ),
                          child: Text(
                            _samplePreview,
                            style: const TextStyle(
                              fontSize: 13,
                              height: 1.5,
                              color: AppColors.whatsappText,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  if (reminders.isEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: EmptyState(
                        icon: Icons.verified_outlined,
                        title: 'All caught up! 🎉',
                        hint: 'No reminders to send today. You are all set.',
                      ),
                    ),
                  ] else ...[
                    // Reminder Row Cards matching HTML
                    ...reminders.map((r) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _ReminderCard(
                            reminder: r,
                            onSend: () => _send(r),
                          ),
                        )),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ReminderCard extends StatelessWidget {
  const _ReminderCard({required this.reminder, required this.onSend});

  final PendingReminder reminder;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final candidate = reminder.candidate;
    final isExpired = reminder.daysLeft < 0;
    final borderColor = isExpired
        ? AppColors.statusExpired
        : reminder.daysLeft <= 3
            ? AppColors.statusExpiring
            : AppColors.statusActive;

    final subtitle = isExpired
        ? 'Expired ${-reminder.daysLeft} days ago${candidate.due > 0 ? " · ₹${candidate.due} due" : ""}'
        : reminder.daysLeft == 0
            ? 'Expires TODAY${candidate.due > 0 ? " · ₹${candidate.due} due" : ""}'
            : 'Expires in ${reminder.daysLeft} days${candidate.due > 0 ? " · ₹${candidate.due} due" : ""}';

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(AppColors.radius),
        border: Border.all(color: AppColors.borderDark),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppColors.radius),
        child: Container(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: borderColor, width: 3.5)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              MemberAvatar(
                name: candidate.name,
                photoPath: candidate.photoPath,
                radius: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      candidate.name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimaryDark,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: borderColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                onPressed: onSend,
                icon: const Icon(Icons.chat, size: 16),
                label: const Text('WhatsApp'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.statusActive,
                  foregroundColor: const Color(0xFF17191C),
                  elevation: 0,
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
