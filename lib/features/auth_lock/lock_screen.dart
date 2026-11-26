import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../../core/providers/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/common_widgets.dart';

/// App lock screen (spec 6.1): PIN pad + biometric unlock when available.
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  String _entry = '';
  String? _error;
  bool _checking = false;

  Future<void> _submit() async {
    if (_checking) return;
    setState(() => _checking = true);
    final controller = ref.read(lockedProvider.notifier);
    final ok = await controller.verifyPin(_entry);
    if (!mounted) return;
    if (ok) {
      controller.unlock();
    } else {
      setState(() {
        _error = 'Wrong PIN. Try again.';
        _entry = '';
        _checking = false;
      });
    }
  }

  Future<void> _tryBiometric() async {
    try {
      final auth = LocalAuthentication();
      final canCheck = await auth.canCheckBiometrics;
      final isSupported = await auth.isDeviceSupported();
      if (!canCheck || !isSupported) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Biometric unlock is not available on this device')),
          );
        }
        return;
      }
      final ok = await auth.authenticate(
        localizedReason: 'Unlock GymDesk',
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );
      if (ok && mounted) {
        ref.read(lockedProvider.notifier).unlock();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Biometric unlock failed. Use your PIN.')),
        );
      }
    }
  }

  void _onDigit(String digit) {
    if (_entry.length >= 6) return;
    setState(() {
      _entry += digit;
      _error = null;
    });
    if (_entry.length == 6) {
      // 6-digit PINs submit automatically; shorter PINs use the check button.
      _submit();
    }
  }

  void _onBackspace() {
    if (_entry.isEmpty) return;
    setState(() => _entry = _entry.substring(0, _entry.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.lock_rounded, size: 48, color: AppColors.accent),
                const SizedBox(height: 12),
                Text('GymDesk is locked', style: theme.textTheme.titleLarge),
                const SizedBox(height: 4),
                Text('Enter your PIN to continue',
                    style: theme.textTheme.bodySmall),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(6, (i) {
                    final filled = i < _entry.length;
                    return Container(
                      width: 14,
                      height: 14,
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: filled
                            ? AppColors.accent
                            : Colors.transparent,
                        border: Border.all(
                          color: filled ? AppColors.accent : theme.colorScheme.outline,
                          width: 2,
                        ),
                      ),
                    );
                  }),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!,
                      style: const TextStyle(color: AppColors.statusExpired)),
                ],
                const SizedBox(height: 24),
                _PinPad(
                  onDigit: _onDigit,
                  onBackspace: _onBackspace,
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_entry.isNotEmpty)
                      SecondaryButton(
                        label: 'Clear',
                        onPressed: () => setState(() => _entry = ''),
                      ),
                    const SizedBox(width: 12),
                    PrimaryButton(
                      label: _checking ? 'Checking…' : 'Unlock',
                      onPressed: _entry.length >= 4 && !_checking
                          ? _submit
                          : null,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: _tryBiometric,
                  icon: const Icon(Icons.fingerprint),
                  label: const Text('Unlock with biometrics / device lock'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PinPad extends StatelessWidget {
  const _PinPad({required this.onDigit, required this.onBackspace});

  final void Function(String digit) onDigit;
  final VoidCallback onBackspace;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 260,
      child: Column(
        children: [
          for (final row in [
            ['1', '2', '3'],
            ['4', '5', '6'],
            ['7', '8', '9'],
            ['⌫', '0', ''],
          ])
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final key in row)
                  if (key.isEmpty)
                    const SizedBox(width: 72, height: 60)
                  else
                    SizedBox(
                      width: 72,
                      height: 60,
                      child: TextButton(
                        onPressed: key == '⌫' ? onBackspace : () => onDigit(key),
                        style: TextButton.styleFrom(
                          textStyle: const TextStyle(fontSize: 24),
                        ),
                        child: key == '⌫'
                            ? Icon(Icons.backspace_outlined,
                                color: theme.colorScheme.onSurface)
                            : Text(key),
                      ),
                    ),
              ],
            ),
        ],
      ),
    );
  }
}
