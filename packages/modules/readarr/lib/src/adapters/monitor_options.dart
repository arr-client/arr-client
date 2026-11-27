import 'package:core/core.dart';

import '../l10n/generated/readarr_localizations.dart';

/// What Readarr's own web UI offers to monitor, for an author being added
/// (`addOptions.monitor`) and for one the server has (`bookshelf`).
final readarrMonitorOptions = List<MonitorOption>.unmodifiable([
  _option('all', (strings) => strings.monitorAll),
  _option('future', (strings) => strings.monitorFuture),
  _option('missing', (strings) => strings.monitorMissing),
  _option('existing', (strings) => strings.monitorExisting),
  _option('first', (strings) => strings.monitorFirst),
  _option('latest', (strings) => strings.monitorLatest),
  _option('none', (strings) => strings.monitorNone),
]);

MonitorOption _option(
  String id,
  String Function(ReadarrLocalizations strings) label,
) => MonitorOption(
  id: id,
  label: (context) => label(ReadarrLocalizations.of(context)),
);
