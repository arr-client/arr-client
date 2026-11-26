// A Sonarr that also answers the reads of the overview, on top of support.dart.
//
// Fixtures (`overview_*.json`): recorded on 2026-11-26 from a throwaway Sonarr
// 4.0.20.3014 in the dev stack's image, run with TZ=Pacific/Auckland, and
// passed through tool/sanitize_fixture.dart. Two public series were added and
// made-up files imported by hand: one episode and later an upgrade of it, three
// episodes of a season as a pack, and one file holding two episodes. The quality
// profile was given a cutoff so that something is below it. The free and total
// bytes of diskspace were then replaced by made-up numbers, as the recorded ones
// were those of the recording machine. wanted/missing is the first three of 76.
// What a test needs beyond the recordings it changes.
//
// The server answers as Sonarr does: `series` and `episode` are embedded only
// when asked for, the calendar holds monitored episodes airing within `start`
// and `end` unless `unmonitored` is set, and `history/since` is oldest first.

import 'dart:convert';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const _paths = {
  'calendar',
  'history',
  'history/since',
  'wanted/missing',
  'wanted/cutoff',
  'health',
  'diskspace',
};

class FakeOverview extends FakeSonarr {
  /// The releases of The Bear's season 5, all at one instant, and two weekly
  /// ones of Slow Horses.
  final calendar = records('overview_calendar');

  /// The imports, oldest first.
  final imports = records('overview_history_since');

  final missing = pageRecords('overview_wanted_missing');
  final cutoff = pageRecords('overview_wanted_cutoff');
  final healthIssues = records('overview_health');
  final disks = records('overview_diskspace');

  /// Puts a download of the episode [id] in the queue, which otherwise holds
  /// none of the overview's episodes.
  void enqueue(int id) => queue.add({...queue.last, 'id': id, 'episodeId': id});

  /// Fails every read of [path], below `api/v3/`.
  void breaks(String path, {int status = 500}) =>
      overrides[path] = FakeSonarr.body('{}', status: status);

  /// The requests for [path], below `api/v3/`.
  List<ServiceRequest> asked(String path) => [
    for (final request in requests)
      if (request.path == 'api/v3/$path') request,
  ];

  @override
  Future<Result<ServiceResponse, HttpError>> send(
    ServiceRequest request,
  ) async {
    final path = request.path.substring('api/v3/'.length);
    // The history of one episode is the library's.
    if (!_paths.contains(path) || request.query.containsKey('episodeId')) {
      return super.send(request);
    }
    requests.add(request);
    if (request.method != HttpMethod.get) {
      throw StateError('The overview only reads');
    }
    return always ??
        overrides[path] ??
        FakeSonarr.body(jsonEncode(_overview(path, request.query)));
  }

  Object _overview(String path, Map<String, List<String>> query) {
    String? one(String name) => query[name]?.single;

    /// Copies of [all] without what was not asked for.
    List<Map<String, Object?>> embedded(Iterable<Map<String, Object?>> all) => [
      for (final record in all)
        {...record}..removeWhere(
          (key, _) =>
              (key == 'series' && one('includeSeries') != 'true') ||
              (key == 'episode' && one('includeEpisode') != 'true'),
        ),
    ];

    // The server takes the number or the word.
    Iterable<Map<String, Object?>> ofType() => imports.where(
      (record) => switch (one('eventType')) {
        null => true,
        '3' || 'downloadFolderImported' =>
          record['eventType'] == 'downloadFolderImported',
        _ => false,
      },
    );

    DateTime? date(Map<String, Object?> record, String field) =>
        DateTime.tryParse('${record[field]}');

    Map<String, Object?> page(List<Map<String, Object?>> all) {
      final number = int.parse(one('page') ?? '1');
      final size = int.parse(one('pageSize') ?? '10');
      return {
        'page': number,
        'pageSize': size,
        'totalRecords': all.length,
        'records': all.skip((number - 1) * size).take(size).toList(),
      };
    }

    switch (path) {
      case 'calendar':
        final start = DateTime.parse(one('start')!);
        final end = DateTime.parse(one('end')!);
        return embedded(
          calendar.where((record) {
            if (record['monitored'] == false && one('unmonitored') != 'true') {
              return false;
            }
            // A record without a date is kept, for a test to serve one.
            final aired = date(record, 'airDateUtc');
            return aired == null ||
                (!aired.isBefore(start) && !aired.isAfter(end));
          }),
        );
      case 'history/since':
        final since = DateTime.parse(one('date')!);
        return embedded(
          ofType().where(
            (record) => date(record, 'date')?.isBefore(since) != true,
          ),
        );
      case 'history':
        final newestFirst = ofType().toList()
          ..sort((a, b) => '${b['date']}'.compareTo('${a['date']}'));
        return page(embedded(newestFirst));
      case 'wanted/missing':
        return page(embedded(missing));
      case 'wanted/cutoff':
        return page(embedded(cutoff));
      case 'health':
        return healthIssues;
      default:
        return disks;
    }
  }
}

/// The series and episode titles of [record], replaced by readable ones.
void rename(Map<String, Object?> record, String series, String episode) {
  // A calendar or wanted record is the episode itself.
  final about = switch (record['episode']) {
    final Map<String, Object?> embedded => {...embedded},
    _ => record,
  };
  about['title'] = episode;
  if (!identical(about, record)) record['episode'] = about;
  record['series'] = {
    ...record['series']! as Map<String, Object?>,
    'title': series,
  };
}

/// What the title of an episode among other series' episodes must hold: the
/// series, then the episode's number as `S06E01`, then its own title.
Matcher titled(String series, String number, String episode) => matches(
  RegExp(
    '^${RegExp.escape(series)}\\b.*\\b$number\\b.*${RegExp.escape(episode)}\$',
  ),
);
