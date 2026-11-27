// Health and disk space.

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  test('reports the problems of the server', () async {
    final harness = Harness();

    final issues = await ok(harness.health.health());

    expect(harness.asked, [line(HttpMethod.get, 'health')]);
    final raw = records('overview_health');
    expect(issues.map((issue) => issue.source), raw.map((r) => r['source']));
    expect(issues.single.level, HealthLevel.error);
    expect(issues.single.message, raw.single['message']);
    expect(issues.single.helpUrl, Uri.parse(raw.single['wikiUrl']! as String));
  });

  test('reports the disk space', () async {
    final harness = Harness();

    expect(harness.health.providesDiskSpace, isTrue);
    final disks = await ok(harness.health.diskSpace());

    expect(harness.asked, [line(HttpMethod.get, 'diskspace')]);
    final raw = records('overview_diskspace');
    expect(disks.map((disk) => disk.path), raw.map((r) => r['path']));
    expect(disks.map((disk) => disk.free), raw.map((r) => r['freeSpace']));
    expect(disks.map((disk) => disk.total), raw.map((r) => r['totalSpace']));
  });

  test('passes a failure on', () async {
    final harness = Harness()..server.goOffline();

    expect(await failureOf(harness.health.health()), isA<Unreachable>());
    expect(await failureOf(harness.health.diskSpace()), isA<Unreachable>());
  });
}
