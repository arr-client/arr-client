/// The first step of adding: which service it is.
library;

import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/navigation/locations.dart';
import '../../app/providers.dart';
import '../../src/l10n/generated/app_localizations.dart';

/// Lists the registered modules. Closes with the id of the instance added.
class ServicePickerScreen extends ConsumerWidget {
  const ServicePickerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppLocalizations.of(context);
    final modules = ref.watch(appServicesProvider).modules.modules;

    Future<void> add(ServiceModule module) async {
      final saved = await context.push<String>(
        addServiceFormLocation(module.id),
      );
      if (saved == null || !context.mounted) return;
      context.canPop() ? context.pop(saved) : context.go('/');
    }

    return Scaffold(
      appBar: AppBar(title: Text(strings.addService)),
      body: ListView(
        children: [
          for (final module in modules)
            ListTile(
              leading: Icon(module.descriptor.icon),
              title: Text(module.descriptor.displayName),
              subtitle: Text(_category(strings, module.descriptor.category)),
              onTap: () => unawaited(add(module)),
            ),
        ],
      ),
    );
  }

  static String _category(AppLocalizations strings, ModuleCategory category) =>
      switch (category) {
        ModuleCategory.movies => strings.categoryMovies,
        ModuleCategory.series => strings.categorySeries,
        ModuleCategory.music => strings.categoryMusic,
        ModuleCategory.books => strings.categoryBooks,
        ModuleCategory.subtitles => strings.categorySubtitles,
        ModuleCategory.indexers => strings.categoryIndexers,
        ModuleCategory.requests => strings.categoryRequests,
        ModuleCategory.downloadClient => strings.categoryDownloadClient,
      };
}
