import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'core/providers/providers.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

class GymDeskApp extends ConsumerStatefulWidget {
  const GymDeskApp({super.key});

  @override
  ConsumerState<GymDeskApp> createState() => _GymDeskAppState();
}

class _GymDeskAppState extends ConsumerState<GymDeskApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(() => ref.read(cloudSyncServiceProvider).init());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = ref.read(lockedProvider.notifier);
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        controller.onAppPaused();
        break;
      case AppLifecycleState.resumed:
        controller.onAppResumed();
        ref.read(cloudSyncServiceProvider).syncNow(pushLocalChanges: false);
        break;
      case AppLifecycleState.inactive:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final webPreset = ref.watch(webThemePresetProvider);
    // Router rebuilds on lock/onboarding changes and re-evaluates redirects.
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Barbell Therapy',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: kIsWeb ? AppTheme.darkForWeb(webPreset) : AppTheme.dark(),
      themeMode: themeMode,
      routerConfig: router,
      builder: (context, child) {
        // Global error boundary: render a friendly fallback for widget
        // build errors instead of crashing (spec 9).
        ErrorWidget.builder = (details) {
          if (kReleaseMode) {
            return Material(
              color: const Color(0xFF0F1115),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Something went wrong here. Please reopen the app.\n'
                    'Your data is safe on this device.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      color: const Color(0xFFF2F4F7),
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            );
          }
          return ErrorWidget(details.exception);
        };
        if (!kIsWeb) {
          return child ?? const SizedBox.shrink();
        }
        return Container(
          color: webPreset.bg,
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
