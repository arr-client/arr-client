/// The module's texts, each a `LocalizedText`.
library;

import 'package:flutter/widgets.dart';

import 'generated/qbittorrent_localizations.dart';

String apiKeyBasicAuthNote(BuildContext context) =>
    QbittorrentLocalizations.of(context).apiKeyBasicAuthNote;

String passwordBasicAuthNote(BuildContext context) =>
    QbittorrentLocalizations.of(context).passwordBasicAuthNote;

String unauthorizedHint(BuildContext context) =>
    QbittorrentLocalizations.of(context).unauthorizedHint;

String signInRefusedHint(BuildContext context) =>
    QbittorrentLocalizations.of(context).signInRefusedHint;
