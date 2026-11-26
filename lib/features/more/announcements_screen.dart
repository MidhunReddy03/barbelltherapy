import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/providers/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/app_date_utils.dart';
import '../../core/utils/phone_utils.dart';
import '../../core/widgets/common_widgets.dart';
import '../../data/repositories/members_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../domain/enums.dart';
import '../../domain/membership_status.dart';
import '../../domain/template_engine.dart';

enum _AnnouncementAudience { all, active, expiring, expired, dues }

/// Bulk WhatsApp announcement sender (spec 6.9).
class AnnouncementsScreen extends ConsumerStatefulWidget {
  const AnnouncementsScreen({super.key});

  @override
  ConsumerState<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends ConsumerState<AnnouncementsScreen> {
  _AnnouncementAudience _audience = _AnnouncementAudience.active;
  final _messageController = TextEditingController(
    text: 'Dear {name}, please note that {gym_name} will remain closed this Sunday for deep cleaning and equipment maintenance. Normal hours resume Monday morning! 💪',
  );
  int _currentIndex = 0;
  List<MemberListRow> _recipients = [];
  bool _sendingQueue = false;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<List<MemberListRow>> _getRecipients() async {
    final all = await ref.read(membersRepositoryProvider).watchMembers().first;
    final today = AppDateUtils.today();

    return all.where((m) {
      final end = AppDateUtils.parse(m.endDate);
      final start = AppDateUtils.parse(m.startDate);
      final status = MembershipStatusCalculator.evaluate(
        today: today,
        hasSubscription: end != null,
        startDate: start,
        endDate: end,
        frozenToday: m.frozenToday,
      );
      switch (_audience) {
        case _AnnouncementAudience.all:
          return true;
        case _AnnouncementAudience.active:
          return status.status == MembershipStatus.active || status.status == MembershipStatus.upcoming;
        case _AnnouncementAudience.expiring:
          return status.status == MembershipStatus.expiringSoon;
        case _AnnouncementAudience.expired:
          return status.status == MembershipStatus.expired;
        case _AnnouncementAudience.dues:
          return m.due > 0;
      }
    }).toList();
  }

  Future<void> _startQueue() async {
    final list = await _getRecipients();
    if (list.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No members found in this audience category.')),
      );
      return;
    }
    setState(() {
      _recipients = list;
      _currentIndex = 0;
      _sendingQueue = true;
    });
    await _sendToCurrent();
  }

  Future<void> _sendToCurrent() async {
    if (_currentIndex >= _recipients.length) {
      setState(() => _sendingQueue = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All announcement messages sent! 🎉')),
      );
      return;
    }
    final target = _recipients[_currentIndex];
    final settings = ref.read(settingsRepositoryProvider);
    final gymName = await settings.get(SettingKeys.gymName) ?? 'GymDesk';

    final text = TemplateEngine.render(_messageController.text, {
      'name': target.name,
      'gym_name': gymName,
      'plan': target.planName ?? 'Membership',
      'member_code': target.memberCode,
    });

    final uri = PhoneUtils.whatsappUri(target.phone, text);
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      final sms = PhoneUtils.smsUri(target.phone, text);
      await launchUrl(sms, mode: LaunchMode.externalApplication);
    }

    // Log send
    final tmpl = await ref.read(remindersRepositoryProvider).templateFor(MessageType.announcement, LanguageCode.en);
    await ref.read(remindersRepositoryProvider).markSent(
          memberId: target.id,
          type: MessageType.announcement,
          templateId: tmpl?.$1 ?? 1,
          channel: MessageChannel.whatsapp,
        );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 90),
          children: [
            // Header
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: AppColors.textPrimaryDark),
                  onPressed: () => context.pop(),
                ),
                const SizedBox(width: 8),
                Text(
                  'ANNOUNCEMENTS',
                  style: AppTheme.dsp(fontSize: 26, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Active Queue Banner if sending
            if (_sendingQueue) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.accentDarkContainer,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.accent),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'SENDING QUEUE',
                          style: AppTheme.dsp(fontSize: 20, color: AppColors.accentHighlight),
                        ),
                        Text(
                          '${_currentIndex + 1} OF ${_recipients.length}',
                          style: AppTheme.cap(color: AppColors.accentHighlight),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (_currentIndex + 1) / _recipients.length,
                        minHeight: 8,
                        backgroundColor: AppColors.surfaceRaisedDark,
                        valueColor: const AlwaysStoppedAnimation(AppColors.accent),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Next up: ${_recipients[_currentIndex].name} (${_recipients[_currentIndex].memberCode})',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimaryDark),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: PrimaryButton(
                            label: 'Send & Next Member →',
                            height: 46,
                            onPressed: () {
                              setState(() => _currentIndex++);
                              _sendToCurrent();
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () => setState(() => _sendingQueue = false),
                          child: const Text('Stop', style: TextStyle(color: AppColors.statusExpired)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],

            // Audience Selector Chips
            Text('RECIPIENT AUDIENCE', style: AppTheme.cap()),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _AudienceChip(label: 'Active members', isSelected: _audience == _AnnouncementAudience.active, onTap: () => setState(() => _audience = _AnnouncementAudience.active)),
                _AudienceChip(label: 'All members', isSelected: _audience == _AnnouncementAudience.all, onTap: () => setState(() => _audience = _AnnouncementAudience.all)),
                _AudienceChip(label: 'Expiring soon', isSelected: _audience == _AnnouncementAudience.expiring, onTap: () => setState(() => _audience = _AnnouncementAudience.expiring)),
                _AudienceChip(label: 'Expired members', isSelected: _audience == _AnnouncementAudience.expired, onTap: () => setState(() => _audience = _AnnouncementAudience.expired)),
                _AudienceChip(label: 'Dues pending', isSelected: _audience == _AnnouncementAudience.dues, onTap: () => setState(() => _audience = _AnnouncementAudience.dues)),
              ],
            ),
            const SizedBox(height: 14),

            // Message Composer
            Text('MESSAGE CONTENT', style: AppTheme.cap()),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: AppColors.surfaceDark,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.borderDark),
              ),
              padding: const EdgeInsets.all(14),
              child: TextField(
                controller: _messageController,
                maxLines: 5,
                style: const TextStyle(fontSize: 14, height: 1.6, color: AppColors.textPrimaryDark),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  contentPadding: EdgeInsets.zero,
                  hintText: 'Type your announcement message...',
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Supports {name}, {gym_name}, {plan}, {member_code}',
              style: TextStyle(fontSize: 11, color: AppColors.textSecondaryDark),
            ),
            const SizedBox(height: 20),

            PrimaryButton(
              label: 'Start WhatsApp Queue',
              expanded: true,
              height: 52,
              onPressed: _startQueue,
            ),
          ],
        ),
      ),
    );
  }
}

class _AudienceChip extends StatelessWidget {
  const _AudienceChip({required this.label, required this.isSelected, required this.onTap});

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.accentDarkContainer : AppColors.surfaceDark,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? AppColors.accent : AppColors.borderDark,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? AppColors.accentHighlight : AppColors.textPrimaryDark,
          ),
        ),
      ),
    );
  }
}

