import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/providers/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/app_image.dart';
import '../../core/widgets/common_widgets.dart';
import '../../data/database.dart';
import '../../data/repositories/settings_repository.dart';
import '../../domain/enums.dart';

/// Offline Backup & Restore hub with Gmail Backup and Retrieval support.
class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  final TextEditingController _gmailController = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadSavedEmail();
  }

  @override
  void dispose() {
    _gmailController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedEmail() async {
    final email = await ref.read(settingsRepositoryProvider).get(SettingKeys.backupEmail);
    if (email != null && mounted) {
      setState(() => _gmailController.text = email);
    }
  }

  Future<Uint8List?> _buildZipBytes() async {
    final db = ref.read(databaseProvider);

    // Dump all tables to JSON
    final members = await db.select(db.members).get();
    final plans = await db.select(db.plans).get();
    final addons = await db.select(db.addons).get();
    final subscriptions = await db.select(db.subscriptions).get();
    final subAddons = await db.select(db.subscriptionAddons).get();
    final payments = await db.select(db.payments).get();
    final freezes = await db.select(db.freezes).get();
    final checkins = await db.select(db.checkins).get();
    final messageLog = await db.select(db.messageLog).get();
    final templates = await db.select(db.templates).get();
    final settings = await db.select(db.settingsEntries).get();

    final data = {
      'version': 1,
      'createdAt': DateTime.now().toIso8601String(),
      'members': members.map((m) => m.toJson()).toList(),
      'plans': plans.map((p) => p.toJson()).toList(),
      'addons': addons.map((a) => a.toJson()).toList(),
      'subscriptions': subscriptions.map((s) => s.toJson()).toList(),
      'subscriptionAddons': subAddons.map((a) => a.toJson()).toList(),
      'payments': payments.map((p) => p.toJson()).toList(),
      'freezes': freezes.map((f) => f.toJson()).toList(),
      'checkins': checkins.map((c) => c.toJson()).toList(),
      'messageLog': messageLog.map((m) => m.toJson()).toList(),
      'templates': templates.map((t) => t.toJson()).toList(),
      'settings': settings.map((s) => s.toJson()).toList(),
    };

    final jsonString = jsonEncode(data);
    final jsonBytes = utf8.encode(jsonString);

    // Encode into ZIP
    final archive = Archive();
    archive.addFile(ArchiveFile('gymdesk_database.json', jsonBytes.length, jsonBytes));
    final zipList = ZipEncoder().encode(archive);
    return zipList != null ? Uint8List.fromList(zipList) : null;
  }

  Future<void> _sendBackupToGmail() async {
    final email = _gmailController.text.trim();
    if (email.isEmpty || !email.contains('@') || !email.contains('.')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid Gmail address (e.g. gymowner@gmail.com).')),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      // Save email for next time
      await ref.read(settingsRepositoryProvider).set(SettingKeys.backupEmail, email);
      final gymName = ref.read(gymNameProvider);

      final zipBytes = await _buildZipBytes();
      if (zipBytes != null) {
        final dateStr = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
        final displayDate = DateFormat('d MMM yyyy, h:mm a').format(DateTime.now());
        final filename = 'GymDesk_Backup_$dateStr.zip';

        final bodyText = '''GymDesk Offline Database Backup
Gym: $gymName
Date: $displayDate
Recipient: $email

HOW TO RETRIEVE AND RESTORE YOUR DATA:
1. Download the attached file "$filename" to your phone.
2. Open GymDesk app on your device.
3. Go to More > Backup & Restore.
4. Tap "Restore from Backup Archive" and select the downloaded .zip file.
All your members, plans, payments, and history will be restored.''';

        await AppImage.shareBytes(
          bytes: zipBytes,
          fileName: filename,
          mimeType: 'application/zip',
          subject: '[GymDesk Backup] $gymName - $displayDate',
          text: bodyText,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Backup ready! Choose Gmail to send to $email ✓')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Backup failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createBackup() async {
    setState(() => _busy = true);
    try {
      final zipBytes = await _buildZipBytes();
      if (zipBytes != null) {
        final dateStr = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
        final filename = 'GymDesk_Backup_$dateStr.zip';

        await AppImage.shareBytes(
          bytes: zipBytes,
          fileName: filename,
          mimeType: 'application/zip',
          subject: 'GymDesk Backup',
          text: 'Offline database backup snapshot ($filename)',
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Backup archive created and ready to save/share! ✓')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Backup failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restoreBackup() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip', 'json'],
    );

    if (files.isEmpty) return;
    final file = files.first;
    final bytes = await file.readAsBytes();
    if (!mounted) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        title: Text('RESTORE DATA', style: AppTheme.dsp(fontSize: 20, color: AppColors.statusExpiring)),
        content: const Text(
          'Restoring will replace current app data with the contents of this backup file. Are you sure you want to proceed?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.statusExpiring, foregroundColor: Colors.black),
            child: const Text('Confirm Restore'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() => _busy = true);
    try {
      String jsonStr = '';
      if (file.extension == 'zip') {
        final archive = ZipDecoder().decodeBytes(bytes);
        final jsonFile = archive.firstWhere((f) => f.name.endsWith('.json'));
        jsonStr = utf8.decode(jsonFile.content as List<int>);
      } else {
        jsonStr = utf8.decode(bytes);
      }

      final Map<String, dynamic> data = jsonDecode(jsonStr) as Map<String, dynamic>;
      final db = ref.read(databaseProvider);

      await db.transaction(() async {
        // Clear tables
        await db.delete(db.checkins).go();
        await db.delete(db.messageLog).go();
        await db.delete(db.freezes).go();
        await db.delete(db.payments).go();
        await db.delete(db.subscriptionAddons).go();
        await db.delete(db.subscriptions).go();
        await db.delete(db.members).go();
        await db.delete(db.plans).go();
        await db.delete(db.addons).go();
        await db.delete(db.templates).go();
        await db.delete(db.settingsEntries).go();

        // Restore plans
        final plans = (data['plans'] as List? ?? []);
        for (final p in plans) {
          final map = p as Map<String, dynamic>;
          await db.into(db.plans).insert(PlansCompanion(
                id: Value(map['id'] as int),
                name: Value(map['name'] as String),
                durationMonths: Value(map['durationMonths'] as int),
                price: Value(map['price'] as int),
                isActive: Value((map['isActive'] as bool?) ?? true),
                sortOrder: Value((map['sortOrder'] as int?) ?? 0),
              ));
        }

        // Restore members
        final members = (data['members'] as List? ?? []);
        for (final m in members) {
          final map = m as Map<String, dynamic>;
          await db.into(db.members).insert(MembersCompanion(
                id: Value(map['id'] as int),
                memberCode: Value(map['memberCode'] as String),
                name: Value(map['name'] as String),
                phone: Value(map['phone'] as String),
                age: Value(map['age'] as int?),
                gender: Value(map['gender'] as String?),
                photoPath: Value(map['photoPath'] as String?),
                joinedOn: Value(map['joinedOn'] as String),
                notes: Value(map['notes'] as String?),
                isArchived: Value((map['isArchived'] as bool?) ?? false),
                createdAt: Value(DateTime.parse(map['createdAt'] as String)),
              ));
        }

        // Restore subscriptions
        final subs = (data['subscriptions'] as List? ?? []);
        for (final s in subs) {
          final map = s as Map<String, dynamic>;
          await db.into(db.subscriptions).insert(SubscriptionsCompanion(
                id: Value(map['id'] as int),
                memberId: Value(map['memberId'] as int),
                planId: Value(map['planId'] as int),
                planNameSnapshot: Value(map['planNameSnapshot'] as String),
                planPriceSnapshot: Value(map['planPriceSnapshot'] as int),
                startDate: Value(map['startDate'] as String),
                originalEndDate: Value(map['originalEndDate'] as String),
                endDate: Value(map['endDate'] as String),
                admissionFee: Value((map['admissionFee'] as int?) ?? 0),
                discountType: Value(DiscountType.values.firstWhere((e) => e.name == map['discountType'])),
                discountValue: Value((map['discountValue'] as int?) ?? 0),
                totalAmount: Value(map['totalAmount'] as int),
                statusOverride: Value(map['statusOverride'] as String?),
                cancelReason: Value(map['cancelReason'] as String?),
                createdAt: Value(DateTime.parse(map['createdAt'] as String)),
              ));
        }

        // Restore payments
        final payments = (data['payments'] as List? ?? []);
        for (final py in payments) {
          final map = py as Map<String, dynamic>;
          await db.into(db.payments).insert(PaymentsCompanion(
                id: Value(map['id'] as int),
                subscriptionId: Value(map['subscriptionId'] as int?),
                memberId: Value(map['memberId'] as int),
                amount: Value(map['amount'] as int),
                mode: Value(PaymentMode.values.firstWhere((e) => e.name == map['mode'])),
                paidOn: Value(map['paidOn'] as String),
                note: Value(map['note'] as String?),
                voided: Value((map['voided'] as bool?) ?? false),
                voidReason: Value(map['voidReason'] as String?),
                createdAt: Value(DateTime.parse(map['createdAt'] as String)),
              ));
        }

        // Restore settings
        final settingsList = (data['settings'] as List? ?? []);
        for (final st in settingsList) {
          final map = st as Map<String, dynamic>;
          await db.into(db.settingsEntries).insertOnConflictUpdate(SettingsEntriesCompanion(
                key: Value(map['key'] as String),
                value: Value(map['value'] as String?),
              ));
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Database restored successfully! ✓')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Restore error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: SafeArea(
        child: _busy
            ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
            : ListView(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 100),
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
                        'BACKUP & RESTORE',
                        style: AppTheme.dsp(fontSize: 26, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // 1. Gmail Backup Card
                  SectionCard(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.mark_email_read_outlined, size: 22, color: AppColors.accentHighlight),
                            const SizedBox(width: 8),
                            Text('BACKUP TO GMAIL', style: AppTheme.cap(color: AppColors.accentHighlight)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Send a full database snapshot directly to your Gmail inbox so your gym records are securely archived and easily accessible anytime.',
                          style: TextStyle(fontSize: 13, height: 1.4, color: AppColors.textSecondaryDark),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _gmailController,
                          keyboardType: TextInputType.emailAddress,
                          style: const TextStyle(fontSize: 14, color: AppColors.textPrimaryDark),
                          decoration: InputDecoration(
                            labelText: 'Gmail Address',
                            hintText: 'e.g. gymowner@gmail.com',
                            prefixIcon: const Icon(Icons.email_outlined, color: AppColors.textSecondaryDark, size: 20),
                            filled: true,
                            fillColor: AppColors.surfaceRaisedDark,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: AppColors.borderDark),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        PrimaryButton(
                          label: 'Send Backup to Gmail',
                          icon: Icons.send_rounded,
                          expanded: true,
                          onPressed: _sendBackupToGmail,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // 2. Retrieval Guide Card
                  SectionCard(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.history_toggle_off, size: 20, color: AppColors.statusActive),
                            const SizedBox(width: 8),
                            Text('HOW TO RETRIEVE FROM GMAIL', style: AppTheme.cap(color: AppColors.statusActive)),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _StepItem(
                          step: '1',
                          text: 'Open Gmail on your phone or new device and find the email with subject "[GymDesk Backup]".',
                        ),
                        const SizedBox(height: 8),
                        _StepItem(
                          step: '2',
                          text: 'Download the attached .zip backup file to your phone.',
                        ),
                        const SizedBox(height: 8),
                        _StepItem(
                          step: '3',
                          text: 'Tap "Restore from Backup Archive" below and select the downloaded file to restore all your records.',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // 3. Manual Backup / Restore Operations Card
                  SectionCard(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('MANUAL ARCHIVE & RESTORE', style: AppTheme.cap()),
                        const SizedBox(height: 12),
                        SecondaryButton(
                          label: 'Create Backup Archive (.zip)',
                          icon: Icons.archive_outlined,
                          expanded: true,
                          onPressed: _createBackup,
                        ),
                        const SizedBox(height: 12),
                        PrimaryButton(
                          label: 'Restore from Backup Archive',
                          icon: Icons.unarchive_outlined,
                          expanded: true,
                          onPressed: _restoreBackup,
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

class _StepItem extends StatelessWidget {
  const _StepItem({required this.step, required this.text});

  final String step;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: const BoxDecoration(
            color: Color(0x248DBB9A),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            step,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.statusActive),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 12.5, height: 1.4, color: AppColors.textSecondaryDark),
          ),
        ),
      ],
    );
  }
}
