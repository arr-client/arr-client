// Sonarr's health and disk space, and that the module offers the overview.

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonarr/sonarr_module.dart';

import 'overview_support.dart';
import 'support.dart';

void main() {
  test('the module offers calendar, wanted and health', () {
    expect(
      SonarrModule().capabilitiesFor(
        const ProbeResult(
          product: 'Sonarr',
          version: '4.0.20.3014',
          newerThanTested: false,
        ),
        null,
      ),
      containsAll([
        CapabilityKind.calendar,
        CapabilityKind.wanted,
        CapabilityKind.health,
      ]),
    );
  });

  test('lists the problems the server reports', () async {
    final server = FakeOverview();

    final issues = await ok(Harness(server: server).health.health());

    expect(server.requests.single.path, 'api/v3/health');
    expect(issues.map((issue) => (issue.source, issue.level)), [
      ('IndexerSearchCheck', HealthLevel.warning),
      ('DownloadClientCheck', HealthLevel.warning),
      ('IndexerRssCheck', HealthLevel.error),
    ]);
    expect(issues.map((issue) => issue.message), [
      for (final record in server.healthIssues) record['message'],
    ]);
    expect(issues.map((issue) => issue.helpUrl), [
      for (final record in server.healthIssues)
        Uri.parse(record['wikiUrl']! as String),
    ]);
  });

  test('gives the space of each disk', () async {
    final server = FakeOverview();
    final health = Harness(server: server).health;

    expect(health.providesDiskSpace, isTrue);
    final disks = await ok(health.diskSpace());

    expect(server.requests.single.path, 'api/v3/diskspace');
    expect(disks.map((disk) => (disk.path, disk.free, disk.total)), [
      ('/redacted/79', 80000000000, 250000000000),
      ('/redacted/80', 900000000, 4000000000),
    ]);
  });

  for (final path in ['health', 'diskspace']) {
    test('passes a failure of $path on, asking once', () async {
      final server = FakeOverview()..goOffline();
      final health = Harness(server: server).health;

      expect(
        await failureOf<Object>(
          path == 'health' ? health.health() : health.diskSpace(),
        ),
        isA<Unreachable>(),
      );
      expect(server.requests, hasLength(1));
    });
  }
}
