// What the overview tests share, on top of library_support.dart.
//
// Fixtures (test/fixtures/7.0.3.10918/overview_*.json): recorded on 2026-11-26
// from a throwaway Radarr 7.0.3.10918 in the dev stack's image, run with
// TZ=Pacific/Auckland, and passed through tool/sanitize_fixture.dart. Public
// titles were added and small made-up files imported by hand, one of them
// upgraded; the quality profile's cutoff was raised so that two movies are
// below it. The free and total bytes of diskspace were replaced by made-up
// numbers before sanitizing, as the recorded ones were those of the recording
// machine. What a test needs beyond the recordings it sets in code.
//
//   id  monitored  file  imported
//    1  yes        yes   once, below cutoff
//    2  yes        no    -
//    3  yes        no    -    (only a cinema date, still to come)
//    4  yes        yes   twice, the second an upgrade
//    5  yes        no    -
//    6  yes        yes   once, below cutoff
//    7  yes        yes   once
//    8  no         no    -    (not in calendar or wanted)
//
// These ids are not those of the library recordings.
//
// Seen on that server:
// - `wanted/missing` and `wanted/cutoff` sort by `movieMetadata.sortTitle`, and
//   descending when no direction is given.
// - Calendar dates are days written as midnight UTC.
//
// The reads themselves (windows, paging, grouping, ordering of imports) are
// shared Servarr behaviour and are tested in packages/servarr; these tests are
// about what Radarr binds to them.

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radarr/radarr_module.dart';

import 'library_support.dart';

extension OverviewHarness on Harness {
  CalendarProvider get calendar =>
      RadarrModule().capability<CalendarProvider>(context) ??
      (throw TestFailure('Radarr has no CalendarProvider'));

  WantedProvider get wanted =>
      RadarrModule().capability<WantedProvider>(context) ??
      (throw TestFailure('Radarr has no WantedProvider'));

  HealthProvider get health =>
      RadarrModule().capability<HealthProvider>(context) ??
      (throw TestFailure('Radarr has no HealthProvider'));

  /// Answers `GET api/v3/[path]` with [body].
  void serve(String path, Object? body) =>
      server.answers['api/v3/$path'] = jsonAnswer(body);

  /// The requests for `api/v3/[path]`.
  List<ServiceRequest> asked(String path) => [
    for (final request in server.requests)
      if (request.path == 'api/v3/$path') request,
  ];

  /// Puts a download of the movie [id] in the queue.
  void enqueue(int id) => server.queue = [
    {...FakeRadarr.recordedQueue().first, 'movieId': id},
  ];
}

Map<String, Object?> object(String name) =>
    fixture(name)! as Map<String, Object?>;
