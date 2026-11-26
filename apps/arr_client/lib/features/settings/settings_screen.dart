/// The app's settings (spec story 13, scenarios 4 and 5; story 2, scenario 8).
library;

import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../../app/navigation/locations.dart';
import '../../app/providers.dart';
import '../../src/l10n/generated/app_localizations.dart';
import 'storage/clear_cache_tile.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final mode = ref.watch(preferencesProvider).themeMode;
    return Scaffold(
      appBar: AppBar(title: Text(strings.moreSettings)),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final padding = EdgeInsets.symmetric(
            horizontal: screenMargin(constraints.maxWidth),
          );
          return ListView(
            children: [
              Padding(
                padding: padding.add(const EdgeInsets.only(top: 16, bottom: 8)),
                child: Semantics(
                  header: true,
                  child: Text(
                    strings.settingsTheme,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ),
              RadioGroup<AppThemeMode>(
                groupValue: mode,
                onChanged: (chosen) {
                  if (chosen != null) {
                    unawaited(_setTheme(context, ref, chosen));
                  }
                },
                child: Column(
                  children: [
                    for (final value in AppThemeMode.values)
                      RadioListTile<AppThemeMode>(
                        contentPadding: padding,
                        value: value,
                        title: Text(switch (value) {
                          AppThemeMode.system => strings.themeSystem,
                          AppThemeMode.light => strings.themeLight,
                          AppThemeMode.dark => strings.themeDark,
                        }),
                      ),
                  ],
                ),
              ),
              const Divider(),
              ClearCacheTile(contentPadding: padding),
              ListTile(
                contentPadding: padding,
                leading: const Icon(Icons.article_outlined),
                title: Text(strings.diagnosticLog),
                subtitle: Text(strings.diagnosticLogSummary),
                onTap: () => context.go(diagnosticLogLocation),
              ),
              ListTile(
                contentPadding: padding,
                leading: const Icon(Icons.gavel_outlined),
                title: Text(strings.licenses),
                onTap: () => context.go(licensesLocation),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _setTheme(
    BuildContext context,
    WidgetRef ref,
    AppThemeMode mode,
  ) async {
    final strings = AppLocalizations.of(context);
    final services = ref.read(appServicesProvider);
    final messenger = ScaffoldMessenger.of(context);
    try {
      // The app follows what is saved.
      await services.preferences.setThemeMode(mode);
    } catch (error) {
      // The type only, as everywhere in the log.
      services.log.log(
        LogLevel.warning,
        'The theme could not be saved (${error.runtimeType})',
      );
      if (messenger.mounted) {
        messenger.showSnackBar(SnackBar(content: Text(strings.changeFailed)));
      }
    }
  }
}
