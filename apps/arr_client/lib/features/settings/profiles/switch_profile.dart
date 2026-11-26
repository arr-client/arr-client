import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/providers.dart';
import '../../../src/l10n/generated/app_localizations.dart';

/// Makes [profileId] the active profile because the user asked to, and says so
/// if it cannot. Nothing else switches profile.
Future<void> switchProfile(
  BuildContext context,
  WidgetRef ref,
  String profileId,
) async {
  final services = ref.read(appServicesProvider);
  // Taken now: what was pressed may be gone as soon as the switch begins.
  final messenger = ScaffoldMessenger.of(context);
  final failed = AppLocalizations.of(context).switchFailed;
  try {
    await services.registry.switchTo(profileId);
  } catch (error) {
    // The type only: the text of an error may quote an address or a secret.
    services.log.log(
      LogLevel.warning,
      'The profile could not be switched (${error.runtimeType})',
    );
    if (messenger.mounted) {
      messenger.showSnackBar(SnackBar(content: Text(failed)));
    }
  }
}
