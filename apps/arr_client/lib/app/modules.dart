/// The service modules the app is built with. A module is registered here and
/// nowhere else (contracts/module-contract.md rule 8).
library;

import 'package:core/core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:prowlarr/prowlarr_module.dart';
import 'package:qbittorrent/qbittorrent_module.dart';
import 'package:radarr/radarr_module.dart';
import 'package:seerr/seerr_module.dart';
import 'package:sonarr/sonarr_module.dart';

/// One of each module, in the order the app lists them.
List<ServiceModule> serviceModules() => [
  RadarrModule(),
  SonarrModule(),
  QbittorrentModule(),
  ProwlarrModule(),
  SeerrModule(),
];

/// The strings of the modules: their labels and hints throw without these.
const List<LocalizationsDelegate<Object?>> moduleLocalizationsDelegates = [
  RadarrLocalizations.delegate,
  SonarrLocalizations.delegate,
  QbittorrentLocalizations.delegate,
  ProwlarrLocalizations.delegate,
  SeerrLocalizations.delegate,
];
