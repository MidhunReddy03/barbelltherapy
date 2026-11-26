import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/providers/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/app_date_utils.dart';
import '../../core/utils/app_formatters.dart';
import '../../core/utils/phone_utils.dart';
import '../../core/widgets/common_widgets.dart';
import '../../core/widgets/status_pill.dart';
import '../../data/repositories/checkin_repository.dart';
import '../../data/repositories/members_repository.dart';
import '../../domain/membership_status.dart';

/// Check-in screen matching GymDesk App Screens (page_eee71e22.html).
class CheckInScreen extends ConsumerStatefulWidget {
  const CheckInScreen({super.key});

  @override
  ConsumerState<CheckInScreen> createState() => _CheckInScreenState();
}

class _CheckInScreenState extends ConsumerState<CheckInScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  List<MemberListRow> _results = [];
  bool _searching = false;
  int _todayCount = 0;
  List<TodayCheckIn> _today = [];
  CheckInCandidate? _selectedCandidate;
  MembershipStatusResult? _selectedStatus;

  @override
  void initState() {
    super.initState();
    _refreshToday();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refreshToday() async {
    final repo = ref.read(checkInRepositoryProvider);
    final list = await repo.todayList();
    if (!mounted) return;
    setState(() => _today = list);
    final count = await repo.watchTodayCount().first;
    if (!mounted) return;
    setState(() => _todayCount = count);
  }

  void _onQueryChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () async {
      final repo = ref.read(membersRepositoryProvider);
      setState(() => _searching = true);
      try {
        final results = await repo.searchForCheckIn(query, limit: 10);
        if (!mounted) return;
        setState(() => _results = results);
      } finally {
        if (mounted) setState(() => _searching = false);
      }
    });
  }

  Future<void> _selectMember(int memberId) async {
    final repo = ref.read(checkInRepositoryProvider);
    final candidate = await repo.prepare(memberId);
    final today = AppDateUtils.today();
    final end = AppDateUtils.parse(candidate.endDate);
    final start = AppDateUtils.parse(candidate.member.startDate);

    final status = MembershipStatusCalculator.evaluate(
      today: today,
      hasSubscription: end != null,
      startDate: start,
      endDate: end,
      frozenToday: candidate.frozenToday,
    );

    setState(() {
      _selectedCandidate = candidate;
      _selectedStatus = status;
      _results = [];
    });
  }

  Future<void> _recordCheckIn(CheckInCandidate candidate, {required bool wasExpired}) async {
    final repo = ref.read(checkInRepositoryProvider);
    await repo.recordCheckIn(
      memberId: candidate.member.id,
      subscriptionId: candidate.subscriptionId,
      wasExpired: wasExpired,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${candidate.member.name} checked in! 💪')),
    );
    await _refreshToday();
    // Refresh selected candidate status
    await _selectMember(candidate.member.id);
  }

  Future<void> _openQrScanner() async {
    final code = await showDialog<String>(
      context: context,
      builder: (context) {
        String manualCode = '';
        return AlertDialog(
          backgroundColor: AppColors.surfaceDark,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('SCAN MEMBER QR', style: AppTheme.dsp(fontSize: 20)),
          content: SizedBox(
            width: 300,
            height: 320,
            child: Column(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: MobileScanner(
                      onDetect: (capture) {
                        final barcodes = capture.barcodes;
                        for (final b in barcodes) {
                          if (b.rawValue != null && b.rawValue!.isNotEmpty) {
                            Navigator.pop(context, b.rawValue);
                            break;
                          }
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  decoration: const InputDecoration(
                    hintText: 'Or type member code (GYM-0001)',
                    isDense: true,
                  ),
                  onChanged: (v) => manualCode = v.trim(),
                  onSubmitted: (v) => Navigator.pop(context, v.trim()),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondaryDark)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, manualCode.isNotEmpty ? manualCode : null),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent, foregroundColor: AppColors.onAccent),
              child: const Text('Lookup'),
            ),
          ],
        );
      },
    );

    if (code != null && code.isNotEmpty && mounted) {
      final membersRepo = ref.read(membersRepositoryProvider);
      final members = await membersRepo.searchForCheckIn(code, limit: 1);
      if (members.isNotEmpty) {
        await _selectMember(members.first.id);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No member found with code: $code')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 90),
          children: [
            // Top Bar: CHECK-IN + [Today Count Card] matching HTML
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'CHECK-IN',
                  style: AppTheme.dsp(fontSize: 32, fontWeight: FontWeight.w700),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: AppTheme.cardDecoration(),
                  child: Row(
                    children: [
                      Text(
                        '$_todayCount',
                        style: AppTheme.dsp(fontSize: 26, fontWeight: FontWeight.w700, color: AppColors.accentHighlight),
                      ),
                      const SizedBox(width: 6),
                      Text('TODAY', style: AppTheme.cap()),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Search bar & QR Scan Button Row matching HTML
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 52,
                    decoration: AppTheme.cardDecoration(),
                    child: TextField(
                      controller: _searchController,
                      style: const TextStyle(fontSize: 14, color: AppColors.textPrimaryDark),
                      decoration: InputDecoration(
                        hintText: 'Phone or name',
                        hintStyle: const TextStyle(fontSize: 14, color: AppColors.textSecondaryDark),
                        prefixIcon: const Icon(Icons.search, size: 20, color: AppColors.textSecondaryDark),
                        suffixIcon: _searchController.text.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.close, size: 18, color: AppColors.textSecondaryDark),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _results = []);
                                },
                              ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                        contentPadding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      onChanged: _onQueryChanged,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Material(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    onTap: _openQrScanner,
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      width: 52,
                      height: 52,
                      alignment: Alignment.center,
                      child: const Icon(Icons.qr_code_scanner, size: 24, color: AppColors.onAccent),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Search Results Dropdown
            if (_searching) ...[
              const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(color: AppColors.accent))),
            ] else if (_results.isNotEmpty) ...[
              Container(
                decoration: AppTheme.cardDecoration(),
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _results.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final r = _results[i];
                    return ListTile(
                      dense: true,
                      leading: MemberAvatar(name: r.name, photoPath: r.photoPath, radius: 18),
                      title: Text(r.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimaryDark)),
                      subtitle: Text('${PhoneUtils.display(r.phone)} · ${r.memberCode}', style: const TextStyle(fontSize: 12, color: AppColors.textSecondaryDark)),
                      onTap: () {
                        _searchController.clear();
                        _selectMember(r.id);
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Active / Selected Member Check-In Card matching HTML
            if (_selectedCandidate != null && _selectedStatus != null) ...[
              _ActiveCheckInCard(
                candidate: _selectedCandidate!,
                status: _selectedStatus!,
                onCheckIn: () => _recordCheckIn(_selectedCandidate!, wasExpired: _selectedStatus!.status == MembershipStatus.expired),
                onCheckInAnyway: () => _recordCheckIn(_selectedCandidate!, wasExpired: true),
                onDismiss: () => setState(() => _selectedCandidate = null),
              ),
              const SizedBox(height: 14),
            ],

            // Today's Visits Section matching HTML
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("TODAY'S VISITS", style: AppTheme.cap()),
                Text('${_today.length} check-ins', style: const TextStyle(fontSize: 12, color: AppColors.textSecondaryDark)),
              ],
            ),
            const SizedBox(height: 10),

            if (_today.isEmpty) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: EmptyState(
                  icon: Icons.fact_check_outlined,
                  title: 'No visits yet today.',
                  hint: 'Search a member above or scan their QR code to check them in.',
                ),
              ),
            ] else ...[
              ..._today.map((v) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SectionCard(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      child: Row(
                        children: [
                          MemberAvatar(name: v.memberName, photoPath: v.photoPath, radius: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  v.memberName,
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimaryDark),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${v.memberCode}${v.wasExpired ? ' · Expired check-in' : ''}',
                                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondaryDark),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceRaisedDark,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.borderDark),
                            ),
                            child: Text(
                              AppFormatters.time(v.checkedInAt),
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimaryDark),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )),
            ],
          ],
        ),
      ),
    );
  }
}

/// Selected Member Check-In card matching HTML design (border: 1.5px solid statusColor, rounded 18px).
class _ActiveCheckInCard extends StatelessWidget {
  const _ActiveCheckInCard({
    required this.candidate,
    required this.status,
    required this.onCheckIn,
    required this.onCheckInAnyway,
    required this.onDismiss,
  });

  final CheckInCandidate candidate;
  final MembershipStatusResult status;
  final VoidCallback onCheckIn;
  final VoidCallback onCheckInAnyway;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final statusColor = StatusPill.colorFor(status.status);
    final bannerBg = statusColor.withValues(alpha: 0.15);

    String bannerText;
    switch (status.status) {
      case MembershipStatus.active:
        bannerText = 'ACTIVE MEMBERSHIP · CHECK-IN PERMITTED';
        break;
      case MembershipStatus.expiringSoon:
        bannerText = 'EXPIRING SOON (${status.daysLeft} DAYS LEFT)';
        break;
      case MembershipStatus.expired:
        bannerText = 'MEMBERSHIP EXPIRED · RENEWAL REQUIRED';
        break;
      case MembershipStatus.frozen:
        bannerText = 'MEMBERSHIP FROZEN · OVERRIDE REQUIRED';
        break;
      case MembershipStatus.upcoming:
        bannerText = 'STARTS SOON';
        break;
      case MembershipStatus.noPlan:
        bannerText = 'NO ACTIVE PLAN';
        break;
    }

    final end = AppDateUtils.parse(candidate.endDate);
    final detail = end != null
        ? 'Valid till ${AppFormatters.date(end)}'
        : 'Joined ${candidate.member.joinedOn}';

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: statusColor, width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Banner at top of card
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: bannerBg,
            child: Row(
              children: [
                Icon(
                  status.status == MembershipStatus.active
                      ? Icons.check_circle_outline
                      : status.status == MembershipStatus.expired
                          ? Icons.error_outline
                          : Icons.info_outline,
                  size: 18,
                  color: statusColor,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    bannerText,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: statusColor),
                  ),
                ),
                InkWell(
                  onTap: onDismiss,
                  child: const Icon(Icons.close, size: 18, color: AppColors.textSecondaryDark),
                ),
              ],
            ),
          ),

          // Member Info
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // 64x64 Avatar Circle with initials
                MemberAvatar(
                  name: candidate.member.name,
                  photoPath: candidate.member.photoPath,
                  radius: 32,
                  status: status.status,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        candidate.member.name.toUpperCase(),
                        style: AppTheme.dsp(fontSize: 26, fontWeight: FontWeight.w700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        candidate.member.planName ?? 'No plan assigned',
                        style: const TextStyle(fontSize: 13, color: AppColors.textSecondaryDark),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        detail,
                        style: const TextStyle(fontSize: 13, color: Color(0xFFC9C4BA)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Action Buttons matching HTML
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (candidate.alreadyCheckedInToday) ...[
                  Container(
                    height: 52,
                    decoration: BoxDecoration(
                      color: const Color(0x268DBB9A),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.check_circle, size: 20, color: AppColors.statusActive),
                        const SizedBox(width: 8),
                        Text(
                          'Checked in today at ${candidate.lastCheckInToday != null ? AppFormatters.time(candidate.lastCheckInToday!) : "earlier"}',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.statusActive),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: onCheckIn,
                    style: OutlinedButton.styleFrom(
                      backgroundColor: AppColors.surfaceRaisedDark,
                      foregroundColor: AppColors.textPrimaryDark,
                      side: const BorderSide(color: AppColors.borderDark),
                      minimumSize: const Size(0, 46),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Add second visit today'),
                  ),
                ] else if (status.status == MembershipStatus.expired || status.status == MembershipStatus.frozen) ...[
                  PrimaryButton(
                    label: 'Check in anyway (override)',
                    height: 52,
                    onPressed: onCheckInAnyway,
                  ),
                ] else ...[
                  ElevatedButton(
                    onPressed: onCheckIn,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.statusActive,
                      foregroundColor: const Color(0xFF17191C),
                      elevation: 0,
                      minimumSize: const Size(0, 56),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                    ),
                    child: const Text('Check in'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
