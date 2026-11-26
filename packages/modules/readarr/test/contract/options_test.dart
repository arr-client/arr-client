// The profiles, root folders and tags of a server. Books have metadata profiles
// as well as quality profiles (story 8, scenario 3).

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

List<(ServerOptionKind, int, String)> _summary(List<ServerOption> options) => [
  for (final option in options) (option.kind, option.id, option.label),
];

void main() {
  test('reads quality and metadata profiles, folders and tags', () async {
    final harness = Harness();

    final options = await ok(harness.library.options());

    expect(
      _summary(options),
      unorderedEquals([
        for (final profile in records('qualityprofile'))
          (ServerOptionKind.qualityProfile, profile['id'], profile['name']),
        for (final profile in records('metadataprofile'))
          (ServerOptionKind.metadataProfile, profile['id'], profile['name']),
        for (final folder in records('rootfolder'))
          (ServerOptionKind.rootFolder, folder['id'], folder['path']),
        for (final tag in records('tag'))
          (ServerOptionKind.tag, tag['id'], tag['label']),
      ]),
    );
    expect(
      options
          .singleWhere((option) => option.kind == ServerOptionKind.rootFolder)
          .freeSpace,
      records('rootfolder').single['freeSpace'],
    );
  });

  test('keeps them for offline use', () async {
    final harness = Harness();
    expect(await ok(harness.library.cachedOptions()), isNull);
    final options = await ok(harness.library.options());
    harness.server
      ..requests.clear()
      ..goOffline();

    final cached = await ok(harness.library.cachedOptions());

    expect(_summary(cached!.value), _summary(options));
    expect(harness.server.requests, isEmpty);
  });

  for (final path in [
    'qualityprofile',
    'metadataprofile',
    'rootfolder',
    'tag',
  ]) {
    test('fails, and keeps nothing, without $path', () async {
      final harness = Harness();
      harness.server.overrides[path] = FakeReadarr.body('', status: 500);

      expect(await failureOf(harness.library.options()), isA<ServerError>());
      expect(await ok(harness.library.cachedOptions()), isNull);
    });
  }
}
