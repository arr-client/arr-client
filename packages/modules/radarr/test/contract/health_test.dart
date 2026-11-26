// Radarr's health and disk space, read only (spec story 6 scenario 3, FR-024).

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'library_support.dart';
import 'overview_support.dart';

Harness _harness() => Harness()
  ..serve('health', fixture('overview_health'))
  ..serve('diskspace', fixture('overview_diskspace'));

void main() {
  test('reads the problems the server reports', () async {
    final harness = _harness();

    final issues = await succeed(harness.health.health());

    final wire = records(fixture('overview_health'));
    expect(issues.map((issue) => (issue.source, issue.level)), [
      ('IndexerRssCheck', HealthLevel.error),
      ('DownloadClientCheck', HealthLevel.warning),
      ('IndexerSearchCheck', HealthLevel.warning),
    ]);
    expect(
      issues.map((issue) => issue.message),
      wire.map((issue) => issue['message']),
    );
    expect(
      issues.map((issue) => issue.helpUrl),
      wire.map((issue) => Uri.parse(issue['wikiUrl']! as String)),
    );
    final request = harness.server.requests.single;
    expect(request.method, HttpMethod.get);
    expect(request.path, 'api/v3/health');
    expect(request.query, isEmpty);
    expect(request.body, isNull);
  });

  test('reads the disk space', () async {
    final harness = _harness();

    expect(harness.health.providesDiskSpace, isTrue);
    final disks = await succeed(harness.health.diskSpace());

    final wire = records(fixture('overview_diskspace'));
    expect(disks.map((disk) => (disk.path, disk.free, disk.total)), [
      (wire[0]['path'], 80000000000, 250000000000),
      (wire[1]['path'], 4000000000, 20000000000),
    ]);
    final request = harness.server.requests.single;
    expect(request.method, HttpMethod.get);
    expect(request.path, 'api/v3/diskspace');
    expect(request.query, isEmpty);
    expect(request.body, isNull);
  });

  test('passes a failure on, asking once', () async {
    for (final read in [
      (Harness harness) => harness.health.health(),
      (Harness harness) => harness.health.diskSpace(),
    ]) {
      final harness = _harness()
        ..server.down = failedAnswer(const Unreachable());

      expect(await failureOf(read(harness)), isA<Unreachable>());
      expect(harness.server.requests, hasLength(1));
    }
  });
}
