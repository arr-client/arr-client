import 'package:material_ui/material_ui.dart';

import '../../src/l10n/generated/app_localizations.dart';

/// The notice of the app's own license, and the licenses of what it is built
/// from, as Flutter collects them from the packages' `LICENSE` files. The
/// repository's `LICENSE` is among them, under `arr_client_workspace`, the name
/// of the workspace's root package.
class LicensesScreen extends StatelessWidget {
  const LicensesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return LicensePage(
      applicationName: strings.appName,
      applicationLegalese: strings.appLegalNotice,
    );
  }
}
