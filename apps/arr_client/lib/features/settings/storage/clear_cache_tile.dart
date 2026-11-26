/// Clearing the cached data (spec story 2, scenario 8; FR-061).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../../../src/l10n/generated/app_localizations.dart';
import 'cache_clear_controller.dart';

/// The entry of Settings that removes the cached data, once confirmed.
class ClearCacheTile extends ConsumerWidget {
  const ClearCacheTile({required this.contentPadding, super.key});

  final EdgeInsetsGeometry contentPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppLocalizations.of(context);
    final clearing = ref.watch(cacheClearProvider);
    return ListTile(
      contentPadding: contentPadding,
      enabled: !clearing,
      leading: const Icon(Icons.delete_outline),
      title: Text(strings.clearCache),
      subtitle: Text(strings.clearCacheSummary),
      trailing: clearing
          ? SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(
                semanticsLabel: strings.clearingCache,
              ),
            )
          : null,
      onTap: () => unawaited(_clear(context, ref)),
    );
  }

  Future<void> _clear(BuildContext context, WidgetRef ref) async {
    final strings = AppLocalizations.of(context);
    // Taken now: Settings may be left while the data is being removed.
    final messenger = ScaffoldMessenger.of(context);
    final controller = ref.read(cacheClearProvider.notifier);
    final confirmed = await showConfirmDialog(
      context,
      title: strings.clearCacheTitle,
      target: strings.clearCacheTarget,
      consequence: [
        strings.clearCacheConsequence,
        strings.clearCacheKept,
      ].join('\n\n'),
      confirmLabel: strings.clearCache,
    );
    if (!confirmed) return;
    final complete = await controller.clear();
    if (messenger.mounted) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            complete ? strings.cacheCleared : strings.clearCacheFailed,
          ),
        ),
      );
    }
  }
}
