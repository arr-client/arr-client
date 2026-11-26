import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../src/l10n/generated/app_localizations.dart';

/// Whether [url], which a server gave, is a web page and so may be opened.
bool isWebPage(Uri url) =>
    (url.isScheme('http') || url.isScheme('https')) && url.host.isNotEmpty;

/// Opens the web page at [url] in the browser, and says so where that fails.
/// Nothing of the app's, no credential or cookie, goes with it.
Future<void> openWebPage(BuildContext context, Uri url) async {
  final messenger = ScaffoldMessenger.of(context);
  final failed = AppLocalizations.of(context).homeLinkFailed('$url');
  var opened = false;
  try {
    opened = await launchUrl(url, mode: LaunchMode.externalApplication);
  } on Exception {
    // Said below.
  }
  if (!opened) messenger.showSnackBar(SnackBar(content: Text(failed)));
}
