import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/providers/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/app_date_utils.dart';
import '../../../core/utils/app_formatters.dart';
import '../../../core/utils/app_image.dart';
import '../../../core/utils/phone_utils.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../data/repositories/enroll_repository.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../../domain/enums.dart';
import '../../../domain/membership_status.dart';
import '../../../domain/template_engine.dart';
import '../../payments/receipt_pdf.dart';
import '../member_card.dart';
import 'enroll_screen.dart';

/// Post-save screen (spec 6.4): member card preview + welcome message,
/// receipt PDF, member-card image sharing.
class EnrollSuccessScreen extends ConsumerStatefulWidget {
  const EnrollSuccessScreen({super.key, required this.args});

  final EnrollSuccessArgs args;

  @override
  ConsumerState<EnrollSuccessScreen> createState() =>
      _EnrollSuccessScreenState();
}

class _EnrollSuccessScreenState extends ConsumerState<EnrollSuccessScreen> {
  final _cardKey = GlobalKey();

  late final EnrollDraft draft = widget.args.draft;
  late final EnrollResult result = widget.args.result;

  Future<void> _sendWelcome() async {
    final settings = ref.read(settingsRepositoryProvider);
    final reminders = ref.read(remindersRepositoryProvider);
    final language = await settings.defaultLanguage();
    final template =
        await reminders.templateFor(MessageType.welcome, language);
    if (!mounted) return;
    if (template == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No welcome template found.')),
      );
      return;
    }
    final (templateId, body) = template;

    final gymName = await settings.get(SettingKeys.gymName);
    final gymPhone = await settings.get(SettingKeys.gymPhone);
    final values = {
      'name': draft.name,
      'plan': draft.plan?.name,
      'member_code': result.memberCode,
      'start_date':
          AppFormatters.dateShort(draft.startDate),
      'end_date': draft.endDate == null
          ? null
          : AppFormatters.dateShort(draft.endDate!),
      'gym_name': gymName,
      'gym_phone': gymPhone,
    };
    final message = TemplateEngine.render(body, values);
    if (message.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Welcome template has empty placeholders — '
                'edit it in Settings > Templates (Phase 4).')),
      );
      return;
    }

    final uri = PhoneUtils.whatsappUri(draft.phone, message);
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      final sms = PhoneUtils.smsUri(draft.phone, message);
      await launchUrl(sms, mode: LaunchMode.externalApplication);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('WhatsApp not found — opened SMS instead.')),
        );
      }
    }
    await ref.read(enrollRepositoryProvider).markWelcomeSent(
          memberId: result.memberId,
          subscriptionId: result.subscriptionId,
          templateId: templateId,
        );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Welcome message logged as sent.')),
      );
    }
  }

  Future<void> _shareReceipt() async {
    if (result.paymentId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No payment was recorded, so there is no receipt.')),
      );
      return;
    }
    final settings = ref.read(settingsRepositoryProvider);
    final all = await settings.getAll();
    if (!mounted) return;

    final data = ReceiptData(
      gymName: all[SettingKeys.gymName] ?? 'My Gym',
      gymPhone: all[SettingKeys.gymPhone] ?? '',
      gymAddress: all[SettingKeys.gymAddress],
      logoPath: all[SettingKeys.logoPath],
      memberName: draft.name,
      memberCode: result.memberCode,
      planName: draft.plan?.name ?? '—',
      startDate: AppDateUtils.toStorage(draft.startDate),
      endDate: draft.endDate == null
          ? ''
          : AppDateUtils.toStorage(draft.endDate!),
      totalAmount: draft.pricing?.total ?? 0,
      paidSoFar: draft.paid,
      paymentId: result.paymentId!,
      paymentAmount: draft.paid,
      paymentMode: draft.paymentMode.name,
      paidOn: AppDateUtils.toStorage(AppDateUtils.today()),
      paymentNote: draft.paymentNote,
    );
    await shareReceipt(data);
  }

  Future<void> _shareCardImage() async {
    try {
      final boundary = _cardKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Card is still rendering, please try again.')),
          );
        }
        return;
      }
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes =
          await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return;
      final data = bytes.buffer.asUint8List(
        bytes.offsetInBytes,
        bytes.lengthInBytes,
      );
      await AppImage.shareBytes(
        bytes: data,
        fileName: 'member_card_${result.memberCode}.png',
        mimeType: 'image/png',
        subject: 'Member card ${result.memberCode}',
        text: '${draft.name} — ${result.memberCode}',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not share the card image: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gymName = ref.watch(gymNameProvider);
    final end = draft.endDate;
    final status = end == null
        ? null
        : (draft.startDate.isAfter(AppDateUtils.today())
            ? MembershipStatus.upcoming
            : MembershipStatus.active);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Member enrolled 🎉'),
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: Column(
              children: [
                const Icon(Icons.check_circle,
                    size: 56, color: AppColors.statusActive),
                const SizedBox(height: 8),
                Text(
                  '${draft.name} is enrolled!',
                  style: theme.textTheme.titleLarge,
                ),
                Text('${result.memberCode} · ${draft.plan?.name ?? ''}',
                    style: theme.textTheme.bodySmall),
                if (draft.due != null && draft.due! > 0) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${AppFormatters.money(draft.due!)} due — collect it any time from the member profile.',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: AppColors.statusExpiring),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Visible preview & RepaintBoundary used for PNG capture of the card.
          Center(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppColors.radius),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppColors.radius),
                child: RepaintBoundary(
                  key: _cardKey,
                  child: MemberCard(
                    gymName: gymName,
                    memberName: draft.name,
                    memberCode: result.memberCode,
                    planName: draft.plan?.name ?? '—',
                    endsLabel: end == null
                        ? 'No plan'
                        : 'Valid till ${AppFormatters.dateShort(end)}',
                    photoPath: draft.photoPath,
                    status: status,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          PrimaryButton(
            label: 'Send welcome on WhatsApp',
            icon: Icons.chat,
            expanded: true,
            onPressed: _sendWelcome,
          ),
          const SizedBox(height: 8),
          SecondaryButton(
            label: 'Share receipt (PDF)',
            icon: Icons.picture_as_pdf_outlined,
            expanded: true,
            onPressed: _shareReceipt,
          ),
          const SizedBox(height: 8),
          SecondaryButton(
            label: 'Share member card (image)',
            icon: Icons.badge_outlined,
            expanded: true,
            onPressed: _shareCardImage,
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () =>
                context.go('/members/${result.memberId}'),
            child: const Text('Open member profile'),
          ),
          const SizedBox(height: 4),
          PrimaryButton(
            label: 'Done',
            expanded: true,
            onPressed: () => context.go('/members'),
          ),
        ],
      ),
    );
  }
}
