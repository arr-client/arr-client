import 'package:material_ui/material_ui.dart';

import '../../src/l10n/generated/app_localizations.dart';

/// The notice of the app's own license, and the licenses of what it is built
/// from, as Flutter collects them from the packages' `LICENSE` files.
///
/// For the repository, the workspace's root package, Flutter reads `NOTICES`
/// there instead: the app's license under `arr-client`, and the notices of the
/// Android libraries, which no Dart package carries.
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
