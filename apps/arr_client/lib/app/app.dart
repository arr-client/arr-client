import 'dart:async';

import 'package:core/core.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../src/l10n/generated/app_localizations.dart';
import 'composition.dart';
import 'localization.dart';
import 'navigation/router.dart';
import 'providers.dart';

/// Root widget of the running app.
class ArrClientApp extends StatefulWidget {
  const ArrClientApp({required this.services, super.key});

  /// What the app runs on. Whoever made it closes it.
  final AppServices services;

  @override
  State<ArrClientApp> createState() => _ArrClientAppState();
}

class _ArrClientAppState extends State<ArrClientApp> {
  late final GoRouter _router = createRouter(widget.services.modules);
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    widget.services.navigator.router = _router;
    _lifecycle = AppLifecycleListener(
      onResume: () => unawaited(widget.services.resume()),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    widget.services.navigator.router = null;
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ProviderScope(
    overrides: [appServicesProvider.overrideWithValue(widget.services)],
    // A failed read is shown, not repeated behind the user's back.
    retry: (_, _) => null,
    child: Consumer(
      builder: (context, ref, _) {
        final preferences = ref.watch(preferencesProvider);
        return DynamicColorBuilder(
          builder: (light, dark) => MaterialApp.router(
            theme: ArrTheme.light(
              dynamicScheme: preferences.dynamicColor ? light : null,
            ),
            darkTheme: ArrTheme.dark(
              dynamicScheme: preferences.dynamicColor ? dark : null,
              trueBlack: preferences.trueBlack,
            ),
            themeMode: switch (preferences.themeMode) {
              AppThemeMode.system => ThemeMode.system,
              AppThemeMode.light => ThemeMode.light,
              AppThemeMode.dark => ThemeMode.dark,
            },
            localizationsDelegates: appLocalizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: _router,
            // Above the navigator, so that every screen is told.
            builder: (context, child) => ThirdPartyArtworkScope(
              allowed: preferences.loadThirdPartyArtwork,
              child: child!,
            ),
          ),
        );
      },
    ),
  );
}
