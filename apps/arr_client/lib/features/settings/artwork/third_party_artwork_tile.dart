/// Whether artwork is loaded from public hosts (SC-007, research R10).
library;

import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/providers.dart';
import '../../../src/l10n/generated/app_localizations.dart';

/// The switch of Settings for artwork of public hosts, with what it means.
class ThirdPartyArtworkTile extends ConsumerWidget {
  const ThirdPartyArtworkTile({required this.contentPadding, super.key});

  final EdgeInsetsGeometry contentPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppLocalizations.of(context);
    return SwitchListTile(
      contentPadding: contentPadding,
      secondary: const Icon(Icons.image_outlined),
      title: Text(strings.thirdPartyArtwork),
      subtitle: Text(strings.thirdPartyArtworkExplanation),
      value: ref.watch(
        preferencesProvider.select((value) => value.loadThirdPartyArtwork),
      ),
      onChanged: (value) => unawaited(_set(context, ref, value)),
    );
  }

  Future<void> _set(BuildContext context, WidgetRef ref, bool value) async {
    final strings = AppLocalizations.of(context);
    final services = ref.read(appServicesProvider);
    final messenger = ScaffoldMessenger.of(context);
    try {
      // The app follows what is saved.
      await services.preferences.setLoadThirdPartyArtwork(value);
    } catch (error) {
      // The type only, as everywhere in the log.
      services.log.log(
        LogLevel.warning,
        'The artwork setting could not be saved (${error.runtimeType})',
      );
      if (messenger.mounted) {
        messenger.showSnackBar(SnackBar(content: Text(strings.changeFailed)));
      }
    }
  }
}
