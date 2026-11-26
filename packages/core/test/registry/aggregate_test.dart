/// Reading from every instance at once, each failing on its own (FR-074).
library;

import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../artwork/support.dart';
import 'support.dart';

void main() {
  setUpImages();

  late World world;
  late GatedServer fast;
  late GatedServer slow;
  late String first;
  late String second;

  setUp(() async {
    world = await World.start();
    fast = await GatedServer.start('fast');
    slow = await GatedServer.start('slow');
    slow.hold('health');
    first = await world.add('Slow', slow.url);
    second = await world.add('Fast', fast.url);
  });

  ProfileScope scope() => world.registry.scope!;

  Stream<Aggregate<List<HealthIssue>>> health(ProfileScope scope) =>
      scope.aggregate(CapabilityKind.health, (provider) => provider.health());

  List<String> ids(Aggregate<Object?> aggregate) => [
    for (final part in aggregate.parts) part.instance.instance.id,
  ];

  List<String> messages(Aggregate<List<HealthIssue>> aggregate) => [
    for (final (_, issues) in aggregate.values) issues.single.message,
  ];

  test('gives each answer as it arrives, in the instances\' order', () async {
    final events = StreamIterator(health(scope()));

    expect(await events.moveNext(), isTrue);
    expect(ids(events.current), [first, second]);
    expect(messages(events.current), isEmpty);
    expect(events.current.isComplete, isFalse);

    // The slow one has not answered.
    expect(await events.moveNext(), isTrue);
    expect(messages(events.current), ['fast']);
    expect(events.current.isComplete, isFalse);

    slow.release('health');
    expect(await events.moveNext(), isTrue);
    expect(messages(events.current), ['slow', 'fast']);
    expect(events.current.isComplete, isTrue);
    expect(await events.moveNext(), isFalse);
  });

  test('keeps a failure to its instance', () async {
    await world.profiles.markAuthFailed(first);

    final last = await health(scope()).last;

    expect(messages(last), ['fast']);
    final (instance, failure) = last.failures.single;
    expect(instance.instance.id, first);
    expect(failure, isA<AuthFailed>());
  });

  test('takes a read that throws as that instance\'s failure', () async {
    final last = await scope().aggregate(CapabilityKind.health, (provider) {
      final instance = (provider as FakeHealth).context.instance;
      if (instance.id == first) throw StateError('zq-secret');
      return provider.health();
    }).last;

    expect(messages(last), ['fast']);
    expect(last.failures.single.$2, isA<MalformedResponse>());
    expect(world.log.entries.last.toString(), isNot(contains('zq-secret')));
  });

  test('takes a capability that cannot be built the same way', () async {
    world.radarr.brokenFor = 'Broken';
    final broken = await world.add('Broken', fast.url);
    slow.release('health');

    final last = await health(scope()).last;

    expect(messages(last), ['slow', 'fast']);
    expect(last.failures.single.$1.instance.id, broken);
    expect(last.isComplete, isTrue);
  });

  test('asks only the instances accepted', () async {
    final last = await scope()
        .aggregate(
          CapabilityKind.health,
          (provider) => provider.health(),
          where: (instance, _) => instance.instance.id == second,
        )
        .last;

    expect(ids(last), [second]);
    expect(slow.calls, isEmpty);
  });

  test('is complete at once when there is nothing to ask', () async {
    final events = await scope()
        .aggregate(CapabilityKind.queue, (provider) => provider.queue())
        .toList();

    expect(events.single.parts, isEmpty);
    expect(events.single.isComplete, isTrue);
  });

  test('gives nothing more once the profile is switched', () async {
    final away = await world.profile('Away');
    final events = <Aggregate<List<HealthIssue>>>[];
    final done = Completer<void>();
    health(scope()).listen(events.add, onDone: done.complete);
    await slow.arrival('health');
    await pumpEventQueue();
    final before = events.length;

    await world.registry.switchTo(away);
    // Closes without waiting for the server.
    await done.future;

    expect(events, hasLength(before));
  });

  test('holds nothing back for a listener paused over a switch', () async {
    final away = await world.profile('Away');
    final events = <Aggregate<List<HealthIssue>>>[];
    final done = Completer<void>();
    final subscription = health(
      scope(),
    ).listen(events.add, onDone: done.complete)..pause();
    addTearDown(subscription.cancel);
    slow.release('health');
    await slow.arrival('health');
    await Future<void>.delayed(const Duration(milliseconds: 200));

    await world.registry.switchTo(away);
    subscription.resume();
    await done.future;

    expect(events, isEmpty);
  });

  test('leaves out an instance removed meanwhile', () async {
    final events = health(scope()).toList();
    await slow.arrival('health');

    await world.profiles.deleteInstance(first);
    await world.registry.refresh();

    final last = (await events).last;
    expect(ids(last), [second]);
    expect(last.failures, isEmpty);
    expect(last.isComplete, isTrue);
  });

  test('can be given up by its listener', () async {
    final subscription = health(scope()).listen((_) {});
    await slow.arrival('health');

    await subscription.cancel();
    slow.release('health');
    await pumpEventQueue();
  });
}
