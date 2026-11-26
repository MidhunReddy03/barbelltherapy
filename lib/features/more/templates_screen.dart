import 'package:drift/drift.dart' hide Column;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/providers/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common_widgets.dart';
import '../../data/database.dart';
import '../../domain/enums.dart';
import '../../domain/template_engine.dart';

/// Message templates editor matching GymDesk App Screens (page_c0f0451f.html).
class TemplatesScreen extends ConsumerStatefulWidget {
  const TemplatesScreen({super.key});

  @override
  ConsumerState<TemplatesScreen> createState() => _TemplatesScreenState();
}

class _TemplatesScreenState extends ConsumerState<TemplatesScreen> {
  MessageType _selectedType = MessageType.expiry_3;
  String _language = 'en';
  final _bodyController = TextEditingController();
  int? _currentTemplateId;
  bool _loading = true;

  final _typeOptions = const [
    (MessageType.expiry_7, 'Expiry 7 days'),
    (MessageType.expiry_3, 'Expiry 3 days'),
    (MessageType.expiry_1, 'Expiry tomorrow'),
    (MessageType.expiry_0, 'Expiry today'),
    (MessageType.expired_3, 'Expired 3 days'),
    (MessageType.expired_7, 'Expired 7 days'),
    (MessageType.dues_weekly, 'Weekly dues'),
    (MessageType.welcome, 'Welcome'),
    (MessageType.receipt, 'Receipt'),
    (MessageType.inactivity, 'Come back'),
  ];

  final _tokens = const [
    '{name}',
    '{plan}',
    '{end_date}',
    '{days_left}',
    '{amount_due}',
    '{gym_name}',
    '{gym_phone}',
    '{member_code}',
  ];

  @override
  void initState() {
    super.initState();
    _loadTemplate();
  }

  @override
  void dispose() {
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _loadTemplate() async {
    setState(() => _loading = true);
    final repo = ref.read(remindersRepositoryProvider);
    final langCode = _language == 'te' ? LanguageCode.te : LanguageCode.en;
    final tmpl = await repo.templateFor(_selectedType, langCode);
    if (tmpl != null) {
      _currentTemplateId = tmpl.$1;
      _bodyController.text = tmpl.$2;
    } else {
      _currentTemplateId = null;
      _bodyController.text = '';
    }
    if (mounted) setState(() => _loading = false);
  }

  String _renderPreview() {
    final values = {
      'name': 'Sneha Reddy',
      'plan': 'Quarterly Plan',
      'end_date': '18 Nov 2026',
      'days_left': _selectedType.expiryOffset != null && _selectedType.expiryOffset! >= 0
          ? '${_selectedType.expiryOffset}'
          : '3',
      'amount_due': '500',
      'gym_name': 'Iron Pulse Gym',
      'gym_phone': '9876543210',
      'member_code': 'GYM-0042',
    };
    return TemplateEngine.render(_bodyController.text, values);
  }

  void _insertToken(String token) {
    final text = _bodyController.text;
    final selection = _bodyController.selection;
    if (selection.start >= 0) {
      final newText = text.replaceRange(selection.start, selection.end, token);
      _bodyController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: selection.start + token.length),
      );
    } else {
      _bodyController.text = '$text $token';
    }
    setState(() {});
  }

  Future<void> _save() async {
    final text = _bodyController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Template text cannot be empty.')),
      );
      return;
    }
    final db = ref.read(databaseProvider);
    if (_currentTemplateId != null) {
      await (db.update(db.templates)..where((t) => t.id.equals(_currentTemplateId!)))
          .write(TemplatesCompanion(body: Value(text)));
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Template saved successfully! ✓')),
    );
  }

  Future<void> _resetToDefault() async {
    final db = ref.read(databaseProvider);
    // Find initial seed template
    final rows = await (db.select(db.templates)
          ..where((t) => t.key.equals(_selectedType.name) & t.language.equals(_language)))
        .get();
    if (rows.isNotEmpty) {
      setState(() => _bodyController.text = rows.first.body);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
            : Stack(
                children: [
                  ListView(
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
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'MESSAGE TEMPLATES',
                                  style: AppTheme.dsp(fontSize: 26, fontWeight: FontWeight.w700),
                                ),
                                const Text(
                                  'Edit the wording, English or Telugu',
                                  style: TextStyle(fontSize: 12, color: AppColors.textSecondaryDark),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Horizontal Scrollable Category Chips matching HTML
                      SizedBox(
                        height: 38,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _typeOptions.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (context, i) {
                            final (type, label) = _typeOptions[i];
                            final isSelected = _selectedType == type;
                            return InkWell(
                              onTap: () {
                                setState(() => _selectedType = type);
                                _loadTemplate();
                              },
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
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
                          },
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Template label & Language Toggle Pill matching HTML
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('TEMPLATE', style: AppTheme.cap()),
                          Container(
                            height: 36,
                            padding: const EdgeInsets.all(3),
                            decoration: AppTheme.cardDecoration(),
                            child: Row(
                              children: [
                                _LangToggle(
                                  label: 'English',
                                  isSelected: _language == 'en',
                                  onTap: () {
                                    setState(() => _language = 'en');
                                    _loadTemplate();
                                  },
                                ),
                                _LangToggle(
                                  label: 'తెలుగు',
                                  isSelected: _language == 'te',
                                  onTap: () {
                                    setState(() => _language = 'te');
                                    _loadTemplate();
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // Editable Text Box with Accent Border matching HTML
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.surfaceDark,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.accent, width: 1.5),
                        ),
                        padding: const EdgeInsets.all(14),
                        child: TextField(
                          controller: _bodyController,
                          maxLines: 4,
                          style: const TextStyle(fontSize: 14, height: 1.6, color: AppColors.textPrimaryDark),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            filled: false,
                            contentPadding: EdgeInsets.zero,
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Token chips matching HTML
                      Text('INSERT VARIABLE TOKEN', style: AppTheme.cap()),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: _tokens.map((tok) {
                          return InkWell(
                            onTap: () => _insertToken(tok),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceRaisedDark,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppColors.borderDark),
                              ),
                              child: Text(
                                tok,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFFE8B08C),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),

                      // Live preview card matching HTML
                      SectionCard(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('LIVE PREVIEW · SAMPLE MEMBER SNEHA REDDY', style: AppTheme.cap()),
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
                                _renderPreview(),
                                style: const TextStyle(
                                  fontSize: 13,
                                  height: 1.55,
                                  color: AppColors.whatsappText,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  // Bottom Action Buttons matching HTML:
                  // Reset to default (#282C31) and Save template (#D98A5B)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      decoration: const BoxDecoration(
                        color: AppColors.surfaceDark,
                        border: Border(top: BorderSide(color: AppColors.borderDark)),
                      ),
                      padding: const EdgeInsets.fromLTRB(18, 14, 18, 20),
                      child: Row(
                        children: [
                          Expanded(
                            child: SecondaryButton(
                              label: 'Reset to default',
                              height: 52,
                              onPressed: _resetToDefault,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: PrimaryButton(
                              label: 'Save template',
                              height: 52,
                              onPressed: _save,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _LangToggle extends StatelessWidget {
  const _LangToggle({required this.label, required this.isSelected, required this.onTap});

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? AppColors.onAccent : AppColors.textSecondaryDark,
          ),
        ),
      ),
    );
  }
}

