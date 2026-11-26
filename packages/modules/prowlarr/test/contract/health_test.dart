// Prowlarr's health, read only. It reports no disk space
// (contracts/module-contract.md).

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  test('reads the problems the server reports', () async {
    final harness = Harness();

    final issues = await succeed(harness.health.health());

    final wire = records(fixture('health')).single;
    final issue = issues.single;
    expect(issue.source, 'IndexerStatusCheck');
    expect(issue.level, HealthLevel.warning);
    expect(issue.message, wire['message']);
    expect(issue.helpUrl, Uri.parse(wire['wikiUrl']! as String));
    final request = harness.server.requests.single;
    expect(asked(request), 'GET health');
    expect(request.query, isEmpty);
    expect(request.body, isNull);
  });

  test('reports no disk space and asks nothing for it', () async {
    final harness = Harness();

    expect(harness.health.providesDiskSpace, isFalse);
    expect(await succeed(harness.health.diskSpace()), isEmpty);
    expect(harness.server.requests, isEmpty);
  });

  test('passes a failure on, asking once', () async {
    const failure = Unreachable();
    final harness = Harness()..server.down = failedAnswer(failure);

    expect(await failureOf(harness.health.health()), same(failure));
    expect(harness.server.requests, hasLength(1));
  });
}
