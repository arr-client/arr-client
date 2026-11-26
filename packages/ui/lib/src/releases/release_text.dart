/// What a release says of itself, as harmless text.
library;

import 'package:core/core.dart';
import 'package:flutter/widgets.dart';

import '../format/server_text.dart';
import '../l10n/generated/ui_localizations.dart';

/// The title of [release]. [context] must be below the app's localizations.
String releaseTitle(BuildContext context, Release release) =>
    serverText(release.title) ?? UiLocalizations.of(context).releaseNoTitle;

/// Why [release] was rejected. [context] must be below the app's
/// localizations.
List<String> releaseRejections(BuildContext context, Release release) => [
  for (final reason in release.rejections)
    serverText(reason) ?? UiLocalizations.of(context).releaseReasonMissing,
];

/// The name of the indexer, if it has one.
String? releaseIndexerName(Release release) => serverText(release.indexer);

/// The name of the quality, if it has one.
String? releaseQualityName(Release release) =>
    serverText(release.quality?.name);

/// The names of the languages.
List<String> releaseLanguageNames(Release release) => [
  for (final language in release.languages) ?serverText(language.name),
];
