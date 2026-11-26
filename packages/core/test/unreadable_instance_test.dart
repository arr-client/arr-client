/// One instance row that cannot be read must not take the others with it: the
/// app reads them all as it starts.
library;

import 'package:core/core.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'registry/support.dart';

void main() {
  late AppDatabase database;
  late DiagnosticLog log;
  late ProfileRepository profiles;
  late String profile;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    log = DiagnosticLog();
    profiles = ProfileRepository(
      database: database,
      secrets: MemorySecrets(),
      log: log,
      preferences: PreferencesRepository(database),
      modules: [FakeModule('radarr')],
    );
    await profiles.ensureDefaultProfile();
    profile = (await profiles.profiles()).single.id;
  });

  Future<String> add(String name) async {
    final added = await profiles.addInstance(
      profile,
      InstanceDraft(
        name: name,
        serviceType: 'radarr',
        url: Uri.parse('http://server.invalid/$name'),
        authKind: AuthKind.apiKey,
      ),
    );
    return (added as Ok<Instance, RuleViolation>).value.id;
  }

  Future<int> storedRows() async =>
      (await database.customSelect('SELECT id FROM instances').get()).length;

  for (final (what, damage) in [
    ('date', "UPDATE instances SET created_at = 'yesterday' WHERE id = ?"),
    (
      'kind of authentication',
      "UPDATE instances SET auth_kind = 'x' WHERE id = ?",
    ),
    ('address', "UPDATE instances SET url = 'http://[' WHERE id = ?"),
    (
      'kind of link',
      'INSERT INTO instance_links (instance_id, type, target_instance_id) '
          "SELECT id, 'x', id FROM instances WHERE id = ?",
    ),
  ]) {
    test(
      'an instance with an unreadable $what is left out, not lost',
      () async {
        final first = await add('first');
        final bad = await add('bad');
        final last = await add('last');
        await database.customStatement(damage, [bad]);

        for (var read = 0; read < 2; read++) {
          final found = await profiles.instances(profile);
          expect(found.map((instance) => instance.id), [first, last]);
        }

        expect(await storedRows(), 3);
        // Said once, and without what the row holds.
        expect(log.entries.single.message, contains(bad));
        expect(log.export(), isNot(contains('server.invalid')));
      },
    );
  }

  test('an unreadable probe is as if there were none', () async {
    final id = await add('first');
    await database.customStatement(
      "UPDATE instances SET last_probe = '{' WHERE id = ?",
      [id],
    );

    final found = await profiles.instances(profile);

    expect(found.single.lastProbe, isNull);
  });
}
