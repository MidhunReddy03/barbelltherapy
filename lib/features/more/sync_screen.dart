import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/providers/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common_widgets.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/sync/cloud_sync_service.dart';

/// Multi-device Cloud Sync settings screen (syncs across 2+ phones & Website).
class SyncScreen extends ConsumerStatefulWidget {
  const SyncScreen({super.key});

  @override
  ConsumerState<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends ConsumerState<SyncScreen> {
  final _serverCtrl = TextEditingController();
  final _workspaceCtrl = TextEditingController();
  final _passcodeCtrl = TextEditingController();
  bool _obscure = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final all = await ref.read(settingsRepositoryProvider).getAll();
    final service = ref.read(cloudSyncServiceProvider);
    if (!mounted) return;
    setState(() {
      _serverCtrl.text =
          all[SettingKeys.syncServerUrl] ?? service.resolveDefaultUrl();
      _workspaceCtrl.text = all[SettingKeys.syncWorkspaceId] ?? 'barbell-therapy';
      _passcodeCtrl.text = all[SettingKeys.syncPasscode] ?? '';
    });
  }

  @override
  void dispose() {
    _serverCtrl.dispose();
    _workspaceCtrl.dispose();
    _passcodeCtrl.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final ws = _workspaceCtrl.text.trim();
    final pass = _passcodeCtrl.text.trim();
    final url = _serverCtrl.text.trim();
    if (ws.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gym Sync ID must be at least 3 characters.')),
      );
      return;
    }
    if (pass.length < 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sync passcode must be at least 4 characters.')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final status = await ref.read(cloudSyncServiceProvider).connect(
            serverUrl: url,
            workspaceId: ws,
            passcode: pass,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Synced "${status.workspaceId}" (v${status.version})! ✓',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sync error: ${e.toString().replaceFirst("Exception: ", "")}')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _syncNow() async {
    setState(() => _busy = true);
    try {
      await ref.read(cloudSyncServiceProvider).syncNow(pushLocalChanges: true);
      final st = ref.read(cloudSyncServiceProvider).currentStatus;
      if (!mounted) return;
      if (st.lastError != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sync failed: ${st.lastError}')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Synced successfully (v${st.version})! ✓')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    await ref.read(cloudSyncServiceProvider).disconnect();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Disconnected from Cloud Sync.')),
    );
  }

  String _formatLastSynced(String? iso) {
    if (iso == null) return 'Never';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    return DateFormat('d MMM, h:mm a').format(dt.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(syncStatusProvider).value ??
        const SyncStatus(connected: false);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 90),
          children: [
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: AppColors.textPrimaryDark),
                  onPressed: () => context.pop(),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'CLOUD SYNC',
                    style: AppTheme.dsp(fontSize: 26, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Status Banner
            SectionCard(
              borderColor: status.connected
                  ? AppColors.statusActive
                  : AppColors.borderDark,
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    status.syncing
                        ? Icons.sync
                        : (status.connected ? Icons.cloud_done : Icons.cloud_off),
                    color: status.connected
                        ? AppColors.statusActive
                        : AppColors.textSecondaryDark,
                    size: 28,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          status.connected
                              ? 'SYNC ACTIVE · ${status.workspaceId?.toUpperCase()}'
                              : 'NOT CONNECTED',
                          style: AppTheme.cap(
                            color: status.connected
                                ? AppColors.statusActive
                                : AppColors.textSecondaryDark,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          status.connected
                              ? 'Version ${status.version} · Last synced: ${_formatLastSynced(status.lastSyncedAt)}'
                              : 'Connect your phones and website to sync members, plans & payments automatically.',
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: AppColors.textSecondaryDark,
                          ),
                        ),
                        if (status.lastError != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Last error: ${status.lastError}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.statusExpired,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Credentials Card
            SectionCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('WORKSPACE CREDENTIALS', style: AppTheme.cap()),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _workspaceCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Gym Sync ID',
                      hintText: 'e.g. barbell-therapy',
                      prefixIcon: Icon(Icons.badge_outlined, size: 20),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passcodeCtrl,
                    obscureText: _obscure,
                    decoration: InputDecoration(
                      labelText: 'Sync Passcode (4+ characters)',
                      prefixIcon: const Icon(Icons.lock_outline, size: 20),
                      suffixIcon: IconButton(
                        icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _serverCtrl,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: 'Sync Server URL',
                      hintText: 'https://barbell-therapy.onrender.com',
                      prefixIcon: Icon(Icons.link, size: 20),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_busy || status.syncing)
                    const Center(child: CircularProgressIndicator())
                  else ...[
                    PrimaryButton(
                      label: status.connected ? 'Reconnect / Update' : 'Connect & Sync',
                      icon: Icons.cloud_upload_outlined,
                      expanded: true,
                      onPressed: _connect,
                    ),
                    if (status.connected) ...[
                      const SizedBox(height: 10),
                      SecondaryButton(
                        label: 'Sync Now',
                        icon: Icons.sync,
                        expanded: true,
                        onPressed: _syncNow,
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: TextButton(
                          onPressed: _disconnect,
                          child: const Text(
                            'Disconnect Sync',
                            style: TextStyle(color: AppColors.statusExpired),
                          ),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),

            // How it works Card
            SectionCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('HOW TO SYNC 2 PHONES + WEBSITE', style: AppTheme.cap()),
                  const SizedBox(height: 10),
                  const Text(
                    '1. On your first device, enter a Gym Sync ID (e.g. barbell-therapy) and a Sync Passcode, then tap "Connect & Sync".\n'
                    '2. On your second phone and on barbell-therapy.onrender.com, enter the exact same Gym Sync ID and Passcode.\n'
                    '3. All enrollments, payments, plans, freezes, and settings will now sync automatically across all devices — while still working offline.',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.55,
                      color: AppColors.textSecondaryDark,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
