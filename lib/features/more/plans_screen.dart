import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/providers/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/common_widgets.dart';
import '../../data/database.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../domain/enums.dart';

/// Plans & Add-ons manager (spec 6.6). Plan price changes never affect
/// existing subscriptions (price snapshots at creation time).
class PlansScreen extends ConsumerWidget {
  const PlansScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final repo = ref.watch(catalogRepositoryProvider);
    final plansAsync = ref.watch(allPlansProvider);
    final addonsAsync = ref.watch(allAddonsProvider);
    final presetsAsync = ref.watch(discountPresetsProvider);
    final admissionFee =
        ref.watch(admissionFeeDefaultProvider).value ?? 0;

    return Scaffold(
      appBar: AppBar(title: const Text('Plans & Add-ons')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(child: Text('Plans', style: theme.textTheme.titleLarge)),
              IconButton(
                tooltip: 'Reorder mode',
                icon: const Icon(Icons.reorder),
                onPressed: () => _reorderPlans(context, ref, repo),
              ),
            ],
          ),
          const SizedBox(height: 4),
          plansAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Error: $e'),
            data: (plans) => plans.isEmpty
                ? const EmptyState(
                    icon: Icons.card_membership_outlined,
                    title: 'No plans yet.',
                    hint: 'Add your first plan below.',
                  )
                : Column(
                    children: [
                      for (final plan in plans)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: SectionCard(
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(plan.name,
                                          style:
                                              theme.textTheme.titleMedium),
                                      Text(
                                        '${plan.durationMonths} month${plan.durationMonths > 1 ? 's' : ''}'
                                        '${plan.isActive ? '' : ' · INACTIVE (hidden from enroll)'}',
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                          color: plan.isActive
                                              ? null
                                              : AppColors.statusExpired,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  '₹${plan.price}',
                                  style: theme.textTheme.titleMedium
                                      ?.copyWith(color: AppColors.accent),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined),
                                  onPressed: () => _editPlanDialog(
                                      context, ref, repo, plan),
                                ),
                                IconButton(
                                  tooltip: plan.isActive
                                      ? 'Deactivate'
                                      : 'Activate',
                                  icon: Icon(
                                    plan.isActive
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                  ),
                                  onPressed: () => repo
                                      .setPlanActive(plan.id, !plan.isActive),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 8),
          PrimaryButton(
            label: 'Add plan',
            icon: Icons.add,
            onPressed: () => _editPlanDialog(context, ref, repo, null),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                  child: Text('Add-ons', style: theme.textTheme.titleLarge)),
            ],
          ),
          const SizedBox(height: 4),
          addonsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Error: $e'),
            data: (addons) => addons.isEmpty
                ? const Text('No add-ons yet.',
                    style: TextStyle(fontStyle: FontStyle.italic))
                : Column(
                    children: [
                      for (final addon in addons)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: SectionCard(
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(addon.name,
                                          style:
                                              theme.textTheme.titleMedium),
                                      Text(
                                        '${addon.billing == AddonBilling.per_plan ? 'Per plan' : 'One time'}'
                                        '${addon.isActive ? '' : ' · INACTIVE'}',
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                          color: addon.isActive
                                              ? null
                                              : AppColors.statusExpired,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Text('₹${addon.price}',
                                    style: theme.textTheme.titleMedium),
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined),
                                  onPressed: () => _editAddonDialog(
                                      context, ref, repo, addon),
                                ),
                                IconButton(
                                  tooltip: addon.isActive
                                      ? 'Deactivate'
                                      : 'Activate',
                                  icon: Icon(
                                    addon.isActive
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                  ),
                                  onPressed: () => repo
                                      .setAddonActive(addon.id, !addon.isActive),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 8),
          PrimaryButton(
            label: 'Add add-on',
            icon: Icons.add,
            onPressed: () => _editAddonDialog(context, ref, repo, null),
          ),
          const SizedBox(height: 24),
          Text('Enroll defaults', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('Default admission fee',
                          style: theme.textTheme.bodyMedium),
                    ),
                    Text('₹$admissionFee',
                        style: theme.textTheme.titleMedium),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      onPressed: () =>
                          _editAdmissionFee(context, ref, admissionFee),
                    ),
                  ],
                ),
                const Divider(height: 24),
                Text('Discount presets ("Offers")',
                    style: theme.textTheme.bodyMedium),
                Text(
                  'One-tap discounts in the enroll screen.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                presetsAsync.maybeWhen(
                  loading: () => const SizedBox(),
                  orElse: () {
                    final presets =
                        presetsAsync.value ?? const <DiscountPreset>[];
                    return Column(
                      children: [
                        if (presets.isEmpty)
                          Text('No presets yet.',
                              style: theme.textTheme.bodySmall),
                        for (final preset in presets)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            title: Text(preset.name),
                            subtitle: Text(
                              preset.type == DiscountType.flat
                                  ? '₹${preset.value} off'
                                  : '${preset.value}% off',
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () async {
                                final current =
                                    await repo.discountPresets();
                                current.remove(preset);
                                await repo.saveDiscountPresets(current);
                              },
                            ),
                          ),
                      ],
                    );
                  },
                ),
                TextButton.icon(
                  onPressed: () =>
                      _editPresetDialog(context, ref, repo, null),
                  icon: const Icon(Icons.add),
                  label: const Text('Add preset'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _reorderPlans(
      BuildContext context, WidgetRef ref, CatalogRepository repo) async {
    final plans = await repo.watchAllPlans().first;
    if (!context.mounted) return;
    final ordered = List<Plan>.from(plans);
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Reorder plans'),
          content: SizedBox(
            width: double.maxFinite,
            child: ReorderableListView(
              shrinkWrap: true,
              children: [
                for (final plan in ordered)
                  ListTile(
                    key: ValueKey(plan.id),
                    title: Text(plan.name),
                    trailing: const Icon(Icons.drag_handle),
                  ),
              ],
              onReorderItem: (oldIndex, newIndex) {
                setState(() {
                  final item = ordered.removeAt(oldIndex);
                  ordered.insert(newIndex, item);
                });
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save order'),
            ),
          ],
        ),
      ),
    );
    if (result == true) {
      await repo.reorderPlans(ordered.map((p) => p.id).toList());
    }
  }

  Future<void> _editPlanDialog(
    BuildContext context,
    WidgetRef ref,
    CatalogRepository repo,
    Plan? plan,
  ) async {
    final nameController = TextEditingController(text: plan?.name ?? '');
    final priceController =
        TextEditingController(text: plan == null ? '' : '${plan.price}');
    int duration = plan?.durationMonths ?? 1;
    final formKey = GlobalKey<FormState>();

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(plan == null ? 'Add plan' : 'Edit plan'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Plan name'),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Name is required' : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: priceController,
                  keyboardType: TextInputType.number,
                  decoration:
                      const InputDecoration(labelText: 'Price ₹'),
                  validator: (v) => int.tryParse(v ?? '') == null
                      ? 'Enter a number'
                      : null,
                ),
                const SizedBox(height: 8),
                SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 1, label: FittedBox(fit: BoxFit.scaleDown, child: Text('1 mo', maxLines: 1))),
                    ButtonSegment(value: 3, label: FittedBox(fit: BoxFit.scaleDown, child: Text('3 mo', maxLines: 1))),
                    ButtonSegment(value: 6, label: FittedBox(fit: BoxFit.scaleDown, child: Text('6 mo', maxLines: 1))),
                    ButtonSegment(value: 12, label: FittedBox(fit: BoxFit.scaleDown, child: Text('12 mo', maxLines: 1))),
                  ],
                  selected: {duration},
                  onSelectionChanged: (s) => setState(() => duration = s.first),
                ),
                TextButton(
                  onPressed: () async {
                    final picked = await _customDurationDialog(context, duration);
                    if (picked != null) setState(() => duration = picked);
                  },
                  child: const Text('Custom duration…'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (!(formKey.currentState?.validate() ?? false)) return;
                final name = nameController.text.trim();
                final price = int.parse(priceController.text);
                if (plan == null) {
                  await repo.addPlan(
                      name: name, durationMonths: duration, price: price);
                } else {
                  await repo.updatePlan(
                      id: plan.id,
                      name: name,
                      durationMonths: duration,
                      price: price);
                }
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<int?> _customDurationDialog(
      BuildContext context, int current) async {
    final controller = TextEditingController(text: '$current');
    return showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Custom duration'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Months'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final v = int.tryParse(controller.text);
              if (v != null && v > 0 && v <= 60) Navigator.pop(context, v);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _editAddonDialog(
    BuildContext context,
    WidgetRef ref,
    CatalogRepository repo,
    Addon? addon,
  ) async {
    final nameController = TextEditingController(text: addon?.name ?? '');
    final priceController =
        TextEditingController(text: addon == null ? '' : '${addon.price}');
    var billing = addon?.billing ?? AddonBilling.one_time;
    final formKey = GlobalKey<FormState>();

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(addon == null ? 'Add add-on' : 'Edit add-on'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Name'),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Name is required' : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: priceController,
                  keyboardType: TextInputType.number,
                  decoration:
                      const InputDecoration(labelText: 'Price ₹'),
                  validator: (v) => int.tryParse(v ?? '') == null
                      ? 'Enter a number'
                      : null,
                ),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 'one_time', label: FittedBox(fit: BoxFit.scaleDown, child: Text('One time', maxLines: 1))),
                    ButtonSegment(value: 'per_plan', label: FittedBox(fit: BoxFit.scaleDown, child: Text('Per plan', maxLines: 1))),
                  ],
                  selected: {billing.name},
                  onSelectionChanged: (s) => setState(() {
                    billing = AddonBilling.values
                        .firstWhere((b) => b.name == s.first);
                  }),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (!(formKey.currentState?.validate() ?? false)) return;
                final name = nameController.text.trim();
                final price = int.parse(priceController.text);
                if (addon == null) {
                  await repo.addAddon(
                      name: name, price: price, billing: billing);
                } else {
                  await repo.updateAddon(
                      id: addon.id, name: name, price: price, billing: billing);
                }
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editAdmissionFee(
      BuildContext context, WidgetRef ref, int current) async {
    final controller = TextEditingController(text: '$current');
    final result = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Default admission fee'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Fee ₹ (0 = none)'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final v = int.tryParse(controller.text) ?? 0;
              Navigator.pop(context, v < 0 ? 0 : v);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result != null) {
      await ref
          .read(catalogRepositoryProvider)
          .setAdmissionFeeDefault(result);
    }
  }

  Future<void> _editPresetDialog(
    BuildContext context,
    WidgetRef ref,
    CatalogRepository repo,
    DiscountPreset? preset,
  ) async {
    final nameController = TextEditingController(text: preset?.name ?? '');
    final valueController =
        TextEditingController(text: preset == null ? '' : '${preset.value}');
    var type = preset?.type ?? DiscountType.flat;
    final formKey = GlobalKey<FormState>();

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(preset == null ? 'Add preset' : 'Edit preset'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  decoration:
                      const InputDecoration(labelText: 'Name, e.g. Diwali'),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Name is required' : null,
                ),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 'flat', label: FittedBox(fit: BoxFit.scaleDown, child: Text('₹ off', maxLines: 1))),
                    ButtonSegment(value: 'percent', label: FittedBox(fit: BoxFit.scaleDown, child: Text('% off', maxLines: 1))),
                  ],
                  selected: {type.name},
                  onSelectionChanged: (s) => setState(() {
                    type = DiscountType.values
                        .firstWhere((d) => d.name == s.first);
                  }),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: valueController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                      labelText: type == DiscountType.flat ? '₹ amount' : 'Percent'),
                  validator: (v) => int.tryParse(v ?? '') == null
                      ? 'Enter a number'
                      : null,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (!(formKey.currentState?.validate() ?? false)) return;
                final newPreset = DiscountPreset(
                  name: nameController.text.trim(),
                  type: type,
                  value: int.parse(valueController.text),
                );
                final current = await repo.discountPresets();
                if (preset != null) current.remove(preset);
                current.add(newPreset);
                await repo.saveDiscountPresets(current);
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
