/// How what the server names is shown.
library;

import 'package:core/core.dart';
import 'package:ui/ui.dart';

import '../l10n/generated/bazarr_localizations.dart';

/// The code of [language], with what sets it apart. The server names no
/// language for some history entries.
String languageLabel(BazarrLocalizations strings, SubtitleLanguage language) {
  final code = serverText(language.code) ?? strings.unknownLanguage;
  return switch ((language.forced, language.hi)) {
    (true, true) => strings.languageForcedHi(code),
    (true, false) => strings.languageForced(code),
    (false, true) => strings.languageHi(code),
    (false, false) => code,
  };
}

/// The labels of [languages], as one line.
String languageList(
  BazarrLocalizations strings,
  Iterable<SubtitleLanguage> languages,
) => languages.map((language) => languageLabel(strings, language)).join(', ');

final _afterSeparator = RegExp(r'(?<=[/\\])');

/// The whole of [path] as harmless text. Cleaned part by part, so that the
/// length limit of server text cannot cut off the file's name.
String pathText(String path) =>
    path.split(_afterSeparator).map((part) => serverText(part) ?? '').join();
