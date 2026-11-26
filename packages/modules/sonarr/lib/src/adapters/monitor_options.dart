import 'package:core/core.dart';

import '../l10n/generated/sonarr_localizations.dart';

/// What Sonarr's own web UI offers to monitor, for a series being added
/// (`addOptions.monitor`) and for one the server has (`seasonpass`).
final sonarrMonitorOptions = List<MonitorOption>.unmodifiable([
  _option('all', (strings) => strings.monitorAll),
  _option('future', (strings) => strings.monitorFuture),
  _option('missing', (strings) => strings.monitorMissing),
  _option('existing', (strings) => strings.monitorExisting),
  _option('recent', (strings) => strings.monitorRecent),
  _option('pilot', (strings) => strings.monitorPilot),
  _option('firstSeason', (strings) => strings.monitorFirstSeason),
  _option('lastSeason', (strings) => strings.monitorLastSeason),
  _option('monitorSpecials', (strings) => strings.monitorSpecials),
  _option('unmonitorSpecials', (strings) => strings.unmonitorSpecials),
  _option('none', (strings) => strings.monitorNone),
]);

MonitorOption _option(
  String id,
  String Function(SonarrLocalizations strings) label,
) => MonitorOption(
  id: id,
  label: (context) => label(SonarrLocalizations.of(context)),
);
