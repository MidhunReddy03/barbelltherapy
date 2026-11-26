import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
import '../../data/repositories/members_repository.dart';
import '../../domain/membership_status.dart';

enum _MemberFilter {
  all('All'),
  active('Active'),
  expiringSoon('Expiring'),
  expired('Expired'),
  frozen('Frozen'),
  duesPending('Dues');

  const _MemberFilter(this.label);
  final String label;
}

enum _MemberSort {
  expirySoonest('Expiry soonest'),
  nameAz('Name A-Z'),
  recentlyJoined('Recently joined');

  const _MemberSort(this.label);
  final String label;
}

/// Members screen matching the exact design in GymDesk App Screens (page_25a8c4b6.html).
class MembersScreen extends ConsumerStatefulWidget {
  const MembersScreen({super.key});

  @override
  ConsumerState<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends ConsumerState<MembersScreen> {
  final _searchController = TextEditingController();
  String _search = '';
  _MemberFilter _filter = _MemberFilter.all;
  _MemberSort _sort = _MemberSort.expirySoonest;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<_MemberRowVm> _apply(List<MemberListRow> rows) {
    final today = AppDateUtils.today();
    final vms = rows.map((r) => _MemberRowVm.of(r, today)).toList();

    final filtered = _filter == _MemberFilter.all
        ? vms
        : vms.where((vm) {
            switch (_filter) {
              case _MemberFilter.all:
                return true;
              case _MemberFilter.active:
                return vm.status == MembershipStatus.active ||
                    vm.status == MembershipStatus.upcoming;
              case _MemberFilter.expiringSoon:
                return vm.status == MembershipStatus.expiringSoon;
              case _MemberFilter.expired:
                return vm.status == MembershipStatus.expired;
              case _MemberFilter.frozen:
                return vm.status == MembershipStatus.frozen;
              case _MemberFilter.duesPending:
                return vm.row.due > 0;
            }
          }).toList();

    switch (_sort) {
      case _MemberSort.nameAz:
        filtered.sort((a, b) =>
            a.row.name.toLowerCase().compareTo(b.row.name.toLowerCase()));
        break;
      case _MemberSort.expirySoonest:
        filtered.sort((a, b) {
          final aEnd = AppDateUtils.parse(a.row.endDate);
          final bEnd = AppDateUtils.parse(b.row.endDate);
          if (aEnd == null && bEnd == null) return 0;
          if (aEnd == null) return 1;
          if (bEnd == null) return -1;
          return aEnd.compareTo(bEnd);
        });
        break;
      case _MemberSort.recentlyJoined:
        filtered.sort((a, b) => b.row.memberCode.compareTo(a.row.memberCode));
        break;
    }
    return filtered;
  }

  Future<void> _swipeWhatsApp(_MemberRowVm vm) async {
    final settings = ref.read(settingsRepositoryProvider);
    final language = await settings.defaultLanguage();
    final composed = await ref.read(messagesComposerProvider).composeByStatus(
          member: vm.row,
          status: vm.statusResult,
          language: language,
        );
    if (!mounted) return;
    if (composed == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No template found for this status.')),
      );
      return;
    }
    final (type, templateId, message) = composed;
    final edited = await _previewDialog(message);
    if (edited == null || edited.trim().isEmpty || !mounted) return;

    final uri = PhoneUtils.whatsappUri(vm.row.phone, edited);
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      final sms = PhoneUtils.smsUri(vm.row.phone, edited);
      await launchUrl(sms, mode: LaunchMode.externalApplication);
    }
    await ref.read(remindersRepositoryProvider).markSent(
          memberId: vm.row.id,
          type: type,
          templateId: templateId,
        );
  }

  Future<String?> _previewDialog(String initial) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppColors.borderDark),
        ),
        title: Text(
          'MESSAGE PREVIEW',
          style: AppTheme.dsp(fontSize: 20, fontWeight: FontWeight.w600, color: AppColors.textPrimaryDark),
        ),
        content: TextField(
          controller: controller,
          maxLines: 6,
          style: const TextStyle(fontSize: 14, color: AppColors.textPrimaryDark),
          decoration: const InputDecoration(
            hintText: 'Type your message...',
          ),
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Open WhatsApp', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final membersAsync = ref.watch(membersListProvider(_search));

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'MEMBERS',
                    style: AppTheme.dsp(fontSize: 32, fontWeight: FontWeight.w700, color: AppColors.textPrimaryDark),
                  ),
                  PopupMenuButton<_MemberSort>(
                    tooltip: 'Sort members',
                    onSelected: (s) => setState(() => _sort = s),
                    color: AppColors.surfaceRaisedDark,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(color: AppColors.borderDark),
                    ),
                    itemBuilder: (context) => _MemberSort.values.map((s) {
                      return PopupMenuItem(
                        value: s,
                        child: Text(
                          s.label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: _sort == s ? FontWeight.w700 : FontWeight.w500,
                            color: _sort == s ? AppColors.accentHighlight : AppColors.textPrimaryDark,
                          ),
                        ),
                      );
                    }).toList(),
                    child: Container(
                      height: 36,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: AppTheme.cardDecoration(),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.sort, size: 16, color: AppColors.textSecondaryDark),
                          const SizedBox(width: 6),
                          Text(
                            _sort.label,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textPrimaryDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Search Bar matching HTML
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Container(
                height: 48,
                decoration: AppTheme.cardDecoration(),
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(fontSize: 14, color: AppColors.textPrimaryDark),
                  decoration: InputDecoration(
                    hintText: 'Search name, phone or member code',
                    hintStyle: const TextStyle(fontSize: 14, color: AppColors.textSecondaryDark),
                    prefixIcon: const Icon(Icons.search, size: 20, color: AppColors.textSecondaryDark),
                    suffixIcon: _search.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close, size: 18, color: AppColors.textSecondaryDark),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _search = '');
                            },
                          ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onChanged: (v) => setState(() => _search = v.trim()),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Filter Chips with counts matching HTML
            membersAsync.maybeWhen(
              orElse: () {
                final rows = membersAsync.value ?? const <MemberListRow>[];
                final today = AppDateUtils.today();
                final vms = rows.map((r) => _MemberRowVm.of(r, today)).toList();
                int count(bool Function(_MemberRowVm) test) =>
                    vms.where(test).length;

                final chips = <(_MemberFilter, int)>[
                  (_MemberFilter.all, vms.length),
                  (_MemberFilter.active, count((v) =>
                      v.status == MembershipStatus.active ||
                      v.status == MembershipStatus.upcoming)),
                  (_MemberFilter.expiringSoon,
                      count((v) => v.status == MembershipStatus.expiringSoon)),
                  (_MemberFilter.expired,
                      count((v) => v.status == MembershipStatus.expired)),
                  (_MemberFilter.frozen,
                      count((v) => v.status == MembershipStatus.frozen)),
                  (_MemberFilter.duesPending, count((v) => v.row.due > 0)),
                ];

                return SizedBox(
                  height: 38,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    itemCount: chips.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, i) {
                      final (filter, n) = chips[i];
                      final isSelected = _filter == filter;
                      return InkWell(
                        onTap: () => setState(() => _filter = filter),
                        borderRadius: BorderRadius.circular(10),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            color: isSelected ? AppColors.accentDarkContainer : AppColors.surfaceDark,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected ? AppColors.accent : AppColors.borderDark,
                              width: isSelected ? 1.5 : 1,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                filter.label,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: isSelected ? AppColors.accentHighlight : AppColors.textPrimaryDark,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '$n',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: isSelected ? AppColors.accentHighlight : AppColors.textSecondaryDark,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
            const SizedBox(height: 12),

            // Members List
            Expanded(
              child: membersAsync.when(
                loading: () => const Center(child: CircularProgressIndicator(color: AppColors.accent)),
                error: (e, _) => EmptyState(
                  icon: Icons.error_outline,
                  title: 'Could not load members',
                  hint: '$e',
                ),
                data: (rows) {
                  final vms = _apply(rows);
                  if (vms.isEmpty) {
                    return EmptyState(
                      icon: Icons.groups_outlined,
                      title: _search.isEmpty
                          ? 'No members yet.'
                          : 'No members match your search.',
                      hint: _search.isEmpty
                          ? 'Tap + to enroll your first gym member.'
                          : 'Try searching by a different name, phone, or code.',
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(18, 4, 18, 90),
                    itemCount: vms.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final vm = vms[index];
                      return _SwipeableMemberTile(
                        vm: vm,
                        onWhatsApp: () => _swipeWhatsApp(vm),
                        onRenew: () => context.go('/members/${vm.row.id}'),
                        onTap: () => context.go('/members/${vm.row.id}'),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      // FAB matching HTML: width 54, height 54, border-radius 16, #D98A5B
      floatingActionButton: Container(
        margin: const EdgeInsets.only(bottom: 12),
        width: 54,
        height: 54,
        decoration: BoxDecoration(
          color: AppColors.accent,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => context.go('/members/enroll'),
            borderRadius: BorderRadius.circular(16),
            child: const Icon(Icons.add, size: 28, color: AppColors.onAccent),
          ),
        ),
      ),
    );
  }
}

class _MemberRowVm {
  const _MemberRowVm({required this.row, required this.statusResult});

  final MemberListRow row;
  final MembershipStatusResult statusResult;

  MembershipStatus get status => statusResult.status;

  static _MemberRowVm of(MemberListRow row, DateTime today) {
    final end = AppDateUtils.parse(row.endDate);
    final start = AppDateUtils.parse(row.startDate);
    final status = MembershipStatusCalculator.evaluate(
      today: today,
      hasSubscription: end != null,
      startDate: start,
      endDate: end,
      frozenToday: row.frozenToday,
    );
    return _MemberRowVm(row: row, statusResult: status);
  }
}

/// Member tile matching HTML (.card with 3px solid status color on left border).
class _SwipeableMemberTile extends StatelessWidget {
  const _SwipeableMemberTile({
    required this.vm,
    required this.onWhatsApp,
    required this.onRenew,
    required this.onTap,
  });

  final _MemberRowVm vm;
  final VoidCallback onWhatsApp;
  final VoidCallback onRenew;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final row = vm.row;
    final today = AppDateUtils.today();
    final end = AppDateUtils.parse(row.endDate);
    final start = AppDateUtils.parse(row.startDate);
    final statusColor = StatusPill.colorFor(vm.status);

    return Dismissible(
      key: ValueKey('member_${row.id}'),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          onWhatsApp();
        } else {
          onRenew();
        }
        return false;
      },
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        decoration: BoxDecoration(
          color: AppColors.statusActive.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(AppColors.radius),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat, color: AppColors.statusActive),
            SizedBox(width: 8),
            Text('WhatsApp',
                style: TextStyle(
                    color: AppColors.statusActive,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(AppColors.radius),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Renew',
                style: TextStyle(
                    color: AppColors.accentHighlight,
                    fontWeight: FontWeight.w600)),
            SizedBox(width: 8),
            Icon(Icons.autorenew, color: AppColors.accentHighlight),
          ],
        ),
      ),
      child: Material(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(AppColors.radius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppColors.radius),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppColors.radius),
              border: Border.all(color: AppColors.borderDark),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppColors.radius),
              child: Container(
                decoration: BoxDecoration(
                  border: Border(left: BorderSide(color: statusColor, width: 3.5)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    // Avatar (44x44) with Barlow Condensed initials
                    MemberAvatar(
                      name: row.name,
                      photoPath: row.photoPath,
                      radius: 22,
                      status: vm.status,
                    ),
                    const SizedBox(width: 12),
                    // Member details
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            row.name,
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
                            '${row.planName ?? 'No plan'} · ${row.memberCode}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondaryDark,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Status badge & Expiry / Due line
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        StatusPill(status: vm.status),
                        const SizedBox(height: 4),
                        if (row.due > 0)
                          DueBadge(text: '₹${row.due} due')
                        else
                          Text(
                            AppFormatters.endsLabel(
                              today: today,
                              startDate: start ?? today,
                              endDate: end,
                            ),
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondaryDark,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final membersListProvider =
    StreamProvider.autoDispose.family<List<MemberListRow>, String>(
        (ref, search) {
  return ref.watch(membersRepositoryProvider).watchMembers(search: search);
});
