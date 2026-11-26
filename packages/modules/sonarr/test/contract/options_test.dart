// Quality profiles, root folders and tags.

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  Future<List<ServerOption>> options(Harness harness, ServerOptionKind kind) =>
      ok(harness.library.options()).then(
        (all) => [
          for (final option in all)
            if (option.kind == kind) option,
        ],
      );

  test('quality profiles', () async {
    final harness = Harness();

    final found = await options(harness, ServerOptionKind.qualityProfile);

    expect(found.map((o) => (o.id, o.label, o.freeSpace)), [
      for (final profile in harness.server.qualityProfiles)
        (profile['id'], profile['name'], null),
    ]);
  });

  test('root folders, with their free space', () async {
    final harness = Harness();

    final found = await options(harness, ServerOptionKind.rootFolder);

    final folder = found.single;
    expect(folder.id, 1);
    expect(folder.label, harness.server.rootFolders.single['path']);
    expect(folder.freeSpace, 3487289344);
  });

  test('tags', () async {
    final harness = Harness();

    final found = await options(harness, ServerOptionKind.tag);

    expect(found.single.id, 1);
    expect(found.single.label, harness.server.tags.single['label']);
    expect(found.single.freeSpace, isNull);
  });

  test('nothing but these three kinds', () async {
    final all = await ok(Harness().library.options());

    expect(all.map((o) => o.kind).toSet(), {
      ServerOptionKind.qualityProfile,
      ServerOptionKind.rootFolder,
      ServerOptionKind.tag,
    });
  });

  for (final path in ['qualityprofile', 'rootfolder', 'tag']) {
    test('fails as a whole when $path does', () async {
      final harness = Harness();
      harness.server.overrides[path] = FakeSonarr.body('', status: 401);

      expect(await failureOf(harness.library.options()), isA<AuthFailed>());
    });
  }

  test('what was read is saved, and read back without asking', () async {
    final harness = Harness();
    expect(await ok(harness.library.cachedOptions()), isNull);
    final read = await ok(harness.library.options());
    harness.server.goOffline();
    await failureOf(harness.library.options());
    final asked = harness.server.requests.length;

    final saved = await ok(harness.library.cachedOptions());

    expect(
      saved!.value.map((o) => (o.kind, o.id, o.label)),
      read.map((o) => (o.kind, o.id, o.label)),
    );
    expect(harness.server.requests, hasLength(asked));
  });
}
