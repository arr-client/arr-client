/// The combined queue (spec story 4, scenarios 1 to 3).
library;

import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/support.dart';
import 'support.dart';

const interval = Duration(seconds: 4);

void main() {
  late QueueModule module;
  late TestApp app;
  late FakeQueue films;

  /// The app with one instance, "Films", and more if named, not yet on screen.
  Future<void> start(
    WidgetTester tester, {
    List<String> others = const [],
    Size size = const Size(400, 800),
  }) async {
    useScreen(tester, size);
    module = QueueModule();
    films = module.of('Films');
    app = await TestApp.start(tester, modules: [module]);
    for (final name in ['Films', ...others]) {
      await app.add(module, name);
    }
  }

  /// Shows the queue.
  Future<void> open(WidgetTester tester) async {
    await app.pump(tester);
    await go(tester, 'Activity');
  }

  Finder button(String label) => find.ancestor(
    of: find.text(label),
    matching: find.bySubtype<ButtonStyleButton>(),
  );

  bool enabled(WidgetTester tester, String label) =>
      tester.widget<ButtonStyleButton>(button(label)).enabled;

  /// Opens the details of [title] and presses its remove button.
  Future<void> askToRemove(WidgetTester tester, String title) async {
    await tester.tap(find.text(title));
    await step(tester);
    await tester.ensureVisible(button('Remove from queue'));
    await step(tester);
    await tester.tap(button('Remove from queue'));
    await step(tester);
  }

  Future<void> tick(WidgetTester tester, String choice) async {
    await tester.ensureVisible(find.text(choice));
    await step(tester);
    await tester.tap(find.text(choice));
    await step(tester);
  }

  Future<void> confirm(WidgetTester tester, String label) async {
    await tester.tap(
      find.descendant(of: find.byType(AlertDialog), matching: find.text(label)),
    );
    await step(tester);
  }

  testWidgets('lists the entries of every instance with what is known', (
    tester,
  ) async {
    await start(tester, others: ['Shows']);
    films.items = [entry(1, 'A film')];
    module.of('Shows').items = [
      entry(
        1,
        'An episode',
        trackedState: TrackedState.importBlocked,
        status: QueueStatus.completed,
        severity: QueueSeverity.warning,
        messages: ['No files found are eligible for import'],
      ),
    ];

    await open(tester);

    expect(find.text('A film'), findsOneWidget);
    expect(find.text('Downloading'), findsOneWidget);
    expect(find.text('50% · 1.5 GiB left · 5 min remaining'), findsWidgets);
    expect(find.text('WEBDL-1080p · Torrents · Films'), findsOneWidget);
    expect(find.text('An episode'), findsOneWidget);
    expect(find.text('Warning · Import blocked'), findsOneWidget);
    expect(find.text('No files found are eligible for import'), findsOneWidget);
    expect(find.text('WEBDL-1080p · Torrents · Shows'), findsOneWidget);
    await app.stop(tester);
  });

  testWidgets('says when nothing is queued', (tester) async {
    await start(tester);

    await open(tester);

    expect(find.text('Nothing is in the queue.'), findsOneWidget);
    await app.stop(tester);
  });

  testWidgets('reads again every few seconds, only while visible', (
    tester,
  ) async {
    await start(tester);
    films.items = [entry(1, 'A film')];
    await app.pump(tester);
    await tester.pump(interval * 3);
    expect(films.reads, 0, reason: 'Activity was never opened');

    await go(tester, 'Activity');
    expect(films.reads, 1);
    await tester.pump(interval);
    await tester.pump(interval);
    expect(films.reads, 3);

    await go(tester, 'More');
    await tester.pump(interval * 3);
    expect(films.reads, 3, reason: 'another destination');

    await go(tester, 'Activity');
    expect(films.reads, 4, reason: 'read at once on return');

    await tester.tap(find.text('History'));
    await step(tester);
    final onHistory = films.reads;
    await tester.pump(interval * 3);
    expect(films.reads, onHistory, reason: 'another tab');

    await tester.tap(find.text('Queue'));
    await step(tester);
    expect(films.reads, onHistory + 1);
    await app.stop(tester);
    final stopped = films.reads;
    await tester.pump(interval * 3);
    expect(films.reads, stopped);
  });

  testWidgets('stops under another page, not under a dialog', (tester) async {
    await start(tester);
    films.items = [entry(1, 'A film')];
    await open(tester);

    await tester.tap(find.text('Select'));
    await step(tester);
    await tester.tap(find.text('A film'));
    await step(tester);
    await tester.tap(button('Remove selected'));
    await step(tester);
    var reads = films.reads;
    await tester.pump(interval);
    expect(films.reads, reads + 1, reason: 'a dialog covers nothing');
    await confirm(tester, 'Cancel');

    unawaited(app.services.navigator.router!.push<void>('/search'));
    await step(tester);
    reads = films.reads;
    await tester.pump(interval * 3);
    expect(films.reads, reads);

    app.services.navigator.router!.pop();
    await step(tester);
    expect(films.reads, reads + 1);
    await app.stop(tester);
  });

  testWidgets('stops in the background and catches up on return', (
    tester,
  ) async {
    await start(tester);
    films.items = [entry(1, 'A film', status: QueueStatus.delayed)];
    await open(tester);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    var reads = films.reads;
    await tester.pump(interval);
    expect(films.reads, reads + 1, reason: 'inactive is still on screen');

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await step(tester);
    reads = films.reads;
    await tester.pump(interval * 5);
    expect(films.reads, reads);

    // What was read before is marked until it has been read again.
    films.readGate = Completer();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await step(tester);
    expect(films.reads, reads + 1);
    expect(find.textContaining('Saved data from'), findsOneWidget);
    expect(enabled(tester, 'Grab now'), isFalse);

    films.readGate!.complete();
    await step(tester);
    expect(find.textContaining('Saved data from'), findsNothing);
    expect(enabled(tester, 'Grab now'), isTrue);
    await app.stop(tester);
  });

  testWidgets('a failing instance hides nothing and its entries go stale', (
    tester,
  ) async {
    await start(tester, others: ['Shows']);
    films.items = [entry(1, 'A film', status: QueueStatus.delayed)];
    final shows = module.of('Shows')..failure = const Unreachable();

    await open(tester);

    expect(find.text('A film'), findsOneWidget);
    expect(find.text('Shows'), findsOneWidget);
    expect(find.textContaining('did not answer'), findsOneWidget);
    expect(enabled(tester, 'Grab now'), isTrue);

    shows
      ..failure = null
      ..items = [entry(2, 'An episode')];
    await tester.tap(button('Retry'));
    await step(tester);
    expect(find.text('An episode'), findsOneWidget);
    expect(find.textContaining('did not answer'), findsNothing);

    films.failure = const ServerError(statusCode: 500);
    await tester.pump(interval);
    await step(tester);
    expect(find.text('A film'), findsOneWidget, reason: 'kept');
    expect(find.textContaining('Saved data from'), findsOneWidget);
    expect(find.textContaining('error 500'), findsOneWidget);
    expect(enabled(tester, 'Grab now'), isFalse);

    await tester.tap(find.text('Select'));
    await step(tester);
    await tester.tap(find.text('A film'));
    await step(tester);
    expect(enabled(tester, 'Remove selected'), isFalse);
    await app.stop(tester);
  });

  testWidgets('a failing instance is asked less often', (tester) async {
    await start(tester);
    films.failure = const Unreachable();
    await open(tester);
    expect(films.reads, 1);

    await tester.pump(interval);
    expect(films.reads, 1);
    await tester.pump(interval);
    expect(films.reads, 2);
    await app.stop(tester);
  });

  testWidgets('a slow instance holds up nobody and is not asked twice', (
    tester,
  ) async {
    await start(tester, others: ['Shows']);
    films.items = [entry(1, 'A film')];
    final shows = module.of('Shows')..readGate = Completer();

    await open(tester);
    await tester.pump(interval);
    await tester.pump(interval);

    expect(find.text('A film'), findsOneWidget);
    expect(films.reads, 3);
    expect(shows.reads, 1);
    shows.readGate!.complete();
    await step(tester);
    await app.stop(tester);
  });

  testWidgets('an instance whose sign-in was rejected is not read', (
    tester,
  ) async {
    await start(tester);
    final id = app.services.registry.scope!.instances.single.instance.id;
    await app.services.profiles.markAuthFailed(id);
    await app.services.registry.refresh();

    await open(tester);
    await tester.pump(interval * 10);

    expect(films.reads, 0);
    expect(find.textContaining('sign-in was rejected'), findsOneWidget);

    await app.services.profiles.retryAuth(id);
    await app.services.registry.refresh();
    await step(tester);
    expect(films.reads, 1);
    await app.stop(tester);
  });

  testWidgets('details give every reason in full', (tester) async {
    await start(tester);
    films.items = [
      entry(
        1,
        'A film',
        status: QueueStatus.completed,
        trackedState: TrackedState.importPending,
        severity: QueueSeverity.warning,
        needsManualImport: true,
        messages: ['The first reason', 'The second reason'],
      ),
    ];
    await open(tester);

    await tester.tap(find.text('A film'));
    await step(tester);

    expect(find.text('Queue entry'), findsOneWidget);
    expect(find.text('The first reason'), findsOneWidget);
    expect(find.text('The second reason'), findsOneWidget);
    expect(find.textContaining('waiting for a manual import'), findsOneWidget);
    expect(find.text('Torrent'), findsOneWidget);
    final reads = films.reads;
    await tester.pump(interval);
    expect(films.reads, reads + 1, reason: 'details are read too');

    films.items = [];
    await tester.pump(interval);
    await step(tester);
    expect(find.text('This entry is no longer in the queue.'), findsOneWidget);
    await app.stop(tester);
  });

  testWidgets('a removal is confirmed with what it does, then sent once', (
    tester,
  ) async {
    await start(tester);
    films
      ..items = [entry(1, 'A film', status: QueueStatus.failed)]
      ..writeGate = Completer();
    await open(tester);

    await askToRemove(tester, 'A film');

    expect(find.text('Remove from the queue?'), findsOneWidget);
    expect(find.textContaining('cannot be undone'), findsOneWidget);
    expect(
      find.text(
        'The download and its files are deleted from the download client.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('may be grabbed again'), findsOneWidget);
    expect(find.text('Search for a replacement'), findsNothing);
    await tick(tester, 'Block this release');
    expect(find.textContaining('added to the blocklist'), findsOneWidget);
    expect(
      find.textContaining('settings may still prevent that'),
      findsOneWidget,
    );

    await confirm(tester, 'Remove from queue');

    expect(films.writes, ['remove 1 client=true blocklist=true search=true']);
    expect(find.byType(SnackBar), findsNothing, reason: 'not yet accepted');
    expect(
      tester.widget<OutlinedButton>(find.byType(OutlinedButton)).enabled,
      isFalse,
    );

    films.items = [];
    films.writeGate!.complete();
    await step(tester);

    expect(find.text('Films accepted the removal.'), findsOneWidget);
    expect(find.text('This entry is no longer in the queue.'), findsOneWidget);
    expect(films.writes, hasLength(1));
    await app.stop(tester);
  });

  testWidgets('cancelling a removal sends nothing', (tester) async {
    await start(tester);
    films.items = [entry(1, 'A film')];
    await open(tester);

    await askToRemove(tester, 'A film');
    await confirm(tester, 'Cancel');

    expect(films.writes, isEmpty);
    await app.stop(tester);
  });

  testWidgets('the choices not taken are sent and described', (tester) async {
    await start(tester);
    films.items = [entry(1, 'A film')];
    await open(tester);
    await askToRemove(tester, 'A film');

    await tick(tester, 'Remove from the download client');
    expect(find.textContaining('stays in the download client'), findsOneWidget);
    await tick(tester, 'Block this release');
    await tick(tester, 'Search for a replacement');
    expect(find.text('No replacement search is asked for.'), findsOneWidget);
    await confirm(tester, 'Remove from queue');

    expect(films.writes, ['remove 1 client=false blocklist=true search=false']);
    await app.stop(tester);
  });

  testWidgets('an unknown outcome is reported, read again and not resent', (
    tester,
  ) async {
    await start(tester);
    films
      ..items = [entry(1, 'A film')]
      ..answer = const Err(OutcomeUnknown());
    await open(tester);
    await askToRemove(tester, 'A film');
    final reads = films.reads;

    await confirm(tester, 'Remove from queue');
    await tester.pump(const Duration(minutes: 1));

    expect(
      find.textContaining('Films: The change may or may not have reached'),
      findsOneWidget,
    );
    expect(films.reads, greaterThan(reads));
    expect(films.writes, hasLength(1));
    await app.stop(tester);
  });

  testWidgets('a refused removal says why and is not sent again', (
    tester,
  ) async {
    await start(tester);
    films
      ..items = [entry(1, 'A film')]
      ..answer = const Err(Forbidden());
    await open(tester);
    await askToRemove(tester, 'A film');

    await confirm(tester, 'Remove from queue');
    await tester.pump(const Duration(minutes: 1));

    expect(find.textContaining('Films: The server does not allow'), findsOne);
    expect(find.textContaining('accepted'), findsNothing);
    expect(films.writes, hasLength(1));
    await app.stop(tester);
  });

  testWidgets('several instances are removed from in one confirmation', (
    tester,
  ) async {
    await start(tester, others: ['Shows']);
    films.items = [entry(1, 'A film')];
    final shows = module.of('Shows')
      ..items = [
        // One download, three entries.
        entry(1, 'Season pack', downloadId: 'pack'),
        entry(2, 'Season pack', downloadId: 'pack'),
        entry(3, 'Season pack', downloadId: 'pack'),
      ]
      ..answer = const Err(Unreachable());
    await open(tester);

    await tester.tap(find.text('Select'));
    await step(tester);
    await tester.tap(find.text('A film'));
    await tester.tap(find.text('Season pack').at(0));
    await tester.tap(find.text('Season pack').at(1));
    await step(tester);
    expect(find.text('3 selected'), findsOneWidget);
    await tester.tap(button('Remove selected'));
    await step(tester);

    expect(find.text('Remove 3 entries from the queue?'), findsOneWidget);
    expect(
      find.text('A film (Films)\nSeason pack (Shows)\nSeason pack (Shows)'),
      findsOneWidget,
    );
    expect(
      find.textContaining('1 other queue entry shares a download'),
      findsOneWidget,
    );
    await confirm(tester, 'Remove 3 entries');

    expect(films.writes, ['remove 1 client=true blocklist=false search=false']);
    expect(shows.writes, [
      'removeMany [1, 2] client=true blocklist=false search=false',
    ]);
    expect(find.textContaining('Shows: The server did not answer'), findsOne);
    expect(find.text('Select'), findsOneWidget, reason: 'no longer selecting');
    await app.stop(tester);
  });

  testWidgets('says what removing many does before naming them', (
    tester,
  ) async {
    await start(tester, size: const Size(360, 800));
    films.items = [
      for (var i = 1; i <= 12; i++)
        entry(i, 'A film with a long release name $i 1080p WEB-DL group'),
    ];
    await open(tester);
    await tester.tap(find.text('Select'));
    await step(tester);
    for (var i = 1; i <= 3; i++) {
      await tester.tap(find.textContaining('release name $i 1080p'));
    }
    await step(tester);
    await tester.tap(button('Remove selected'));
    await step(tester);

    final view = tester.getRect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(SingleChildScrollView),
      ),
    );
    final consequence = tester.getRect(find.textContaining('cannot be undone'));
    expect(consequence.top, greaterThanOrEqualTo(view.top));
    expect(consequence.bottom, lessThanOrEqualTo(view.bottom));
    expect(find.text('3 entries, listed below'), findsOneWidget);
    await app.stop(tester);
  });

  testWidgets('long press selects and back stops selecting', (tester) async {
    await start(tester);
    films.items = [entry(1, 'A film')];
    await open(tester);

    await tester.longPress(find.text('A film'));
    await step(tester);
    expect(find.text('1 selected'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await step(tester);
    expect(find.text('1 selected'), findsNothing);
    expect(find.text('A film'), findsOneWidget);
    await app.stop(tester);
  });

  testWidgets('entries that leave while confirming are not sent', (
    tester,
  ) async {
    await start(tester);
    films.items = [entry(1, 'A film')];
    await open(tester);
    await askToRemove(tester, 'A film');

    films.items = [];
    await tester.pump(interval);
    await step(tester);
    await confirm(tester, 'Remove from queue');

    expect(films.writes, isEmpty);
    expect(find.textContaining('nothing was sent'), findsOneWidget);
    await app.stop(tester);
  });

  testWidgets('nothing is sent for a service removed while confirming', (
    tester,
  ) async {
    await start(tester, others: ['Shows']);
    films.items = [entry(1, 'A film')];
    await open(tester);
    await tester.longPress(find.text('A film'));
    await step(tester);
    await tester.tap(button('Remove selected'));
    await step(tester);

    final id = app.services.registry.scope!.instances.first.instance.id;
    await app.services.profiles.deleteInstance(id);
    await app.services.registry.refresh();
    await step(tester);
    await confirm(tester, 'Remove from queue');

    expect(films.writes, isEmpty);
    expect(
      find.text(
        'Films: nothing was sent, as the service was changed meanwhile.',
      ),
      findsOneWidget,
    );
    await app.stop(tester);
  });

  testWidgets('a waiting release has nothing to remove from a client', (
    tester,
  ) async {
    await start(tester);
    films.items = [entry(1, 'A film', status: QueueStatus.delayed)];
    await open(tester);
    expect(find.text('Grabbed in 5 min'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);

    await askToRemove(tester, 'A film');

    expect(find.textContaining('Nothing has been downloaded'), findsOneWidget);
    expect(find.text('Remove from the download client'), findsNothing);
    await tick(tester, 'Block this release');
    expect(find.text('Search for a replacement'), findsNothing);
    await confirm(tester, 'Remove from queue');
    expect(films.writes, ['remove 1 client=false blocklist=true search=false']);
    await app.stop(tester);
  });

  QueueItem waiting(int id, {String title = 'Delayed pack', int series = 1}) =>
      entry(
        id,
        title,
        status: QueueStatus.delayed,
        parent: ItemRef(
          instanceId: 'films',
          kind: MediaKind.series,
          remoteId: series,
        ),
      );

  testWidgets('removing one episode of a waiting pack says all go', (
    tester,
  ) async {
    await start(tester);
    films
      ..items = [waiting(1), waiting(2)]
      ..writeGate = Completer();
    await open(tester);

    await tester.tap(find.text('Delayed pack').first);
    await step(tester);
    expect(
      find.text('1 other queue entry waits for the same release.'),
      findsOneWidget,
    );
    expect(find.textContaining('shares'), findsNothing);
    await tester.ensureVisible(button('Remove from queue'));
    await step(tester);
    await tester.tap(button('Remove from queue'));
    await step(tester);
    expect(
      find.textContaining(
        '1 other queue entry waits for the same release as this selection',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('shares a download'), findsNothing);
    await confirm(tester, 'Remove from queue');
    expect(films.writes, [
      'remove 1 client=false blocklist=false search=false',
    ]);

    // The other episode's entry is busy too.
    app.services.navigator.router!.pop();
    await step(tester);
    for (final grab in tester.widgetList<TextButton>(button('Grab now'))) {
      expect(grab.enabled, isFalse);
    }
    films.writeGate!.complete();
    await step(tester);
    await app.stop(tester);
  });

  testWidgets('a waiting pack is named once among several removals', (
    tester,
  ) async {
    await start(tester);
    films.items = [
      waiting(1),
      waiting(2),
      // The same title for another series is another release.
      waiting(3, series: 2),
      entry(4, 'A film'),
    ];
    await open(tester);

    await tester.tap(find.text('Select'));
    await step(tester);
    for (var i = 0; i < 3; i++) {
      final row = find.text('Delayed pack').at(i);
      await tester.ensureVisible(row);
      await step(tester);
      await tester.tap(row);
    }
    await tester.ensureVisible(find.text('A film'));
    await step(tester);
    await tester.tap(find.text('A film'));
    await step(tester);
    await tester.ensureVisible(button('Remove selected'));
    await step(tester);
    await tester.tap(button('Remove selected'));
    await step(tester);

    expect(find.textContaining('removed with it'), findsNothing);
    expect(
      find.text('Waiting releases get no replacement search.'),
      findsNothing,
    );
    await tick(tester, 'Block this release');
    expect(
      find.text('Waiting releases get no replacement search.'),
      findsOneWidget,
    );
    expect(find.textContaining('only if the server grabbed it'), findsOne);
    await confirm(tester, 'Remove 4 entries');

    expect(films.writes, [
      'removeMany [1, 3, 4] client=true blocklist=true search=true',
    ]);
    await app.stop(tester);
  });

  testWidgets('a waiting pack cannot be grabbed twice', (tester) async {
    await start(tester);
    films
      ..items = [waiting(1), waiting(2)]
      ..writeGate = Completer();
    await open(tester);

    await tester.tap(button('Grab now').first);
    await step(tester);

    for (final grab in tester.widgetList<TextButton>(button('Grab now'))) {
      expect(grab.enabled, isFalse);
    }
    films.writeGate!.complete();
    await step(tester);
    expect(films.writes, ['grab 1']);
    await app.stop(tester);
  });

  for (final latched in [true, false]) {
    testWidgets('Retry after a rejected sign-in tries once ($latched)', (
      tester,
    ) async {
      await start(tester);
      films.failure = const AuthFailed();
      final id = app.services.registry.scope!.instances.single.instance.id;
      if (latched) {
        await app.services.profiles.markAuthFailed(id);
        await app.services.registry.refresh();
      }
      await open(tester);
      final reads = films.reads;
      expect(reads, latched ? 0 : 1);

      films
        ..failure = null
        ..items = [entry(1, 'A film')];
      await tester.tap(button('Retry'));
      await step(tester);

      expect(films.reads, reads + 1);
      expect(find.text('A film'), findsOneWidget);
      final saved = await tester.runAsync(
        () => app.services.profiles.instance(id),
      );
      expect(saved!.authFailed, isFalse);
      await app.stop(tester);
    });
  }

  testWidgets('grabs a delayed entry once', (tester) async {
    await start(tester);
    films
      ..items = [
        entry(1, 'A film', status: QueueStatus.delayed),
        entry(2, 'Another'),
      ]
      ..writeGate = Completer();
    await open(tester);
    expect(find.text('Grab now'), findsOneWidget);

    await tester.tap(button('Grab now'));
    await step(tester);
    expect(enabled(tester, 'Grab now'), isFalse);
    await tester.tap(button('Grab now'));
    expect(find.byType(SnackBar), findsNothing);
    films.writeGate!.complete();
    await step(tester);

    expect(films.writes, ['grab 1']);
    expect(find.text('Films accepted the grab.'), findsOneWidget);
    await app.stop(tester);
  });

  testWidgets('an answer from before a change is not shown after it', (
    tester,
  ) async {
    await start(tester);
    films.items = [entry(1, 'A film', status: QueueStatus.delayed)];
    await open(tester);

    // A read that began before the grab and still holds the old entry.
    final old = films.readGate = Completer();
    await tester.pump(interval);
    final reads = films.reads;
    await tester.tap(button('Grab now'));
    await step(tester);
    expect(enabled(tester, 'Grab now'), isFalse, reason: 'not read since');
    films.readGate = null;
    old.complete();
    await step(tester);

    expect(films.reads, reads + 1);
    expect(enabled(tester, 'Grab now'), isTrue);
    await app.stop(tester);
  });

  testWidgets('pulling down reads again', (tester) async {
    await start(tester);
    films.items = [entry(1, 'A film')];
    await open(tester);
    final reads = films.reads;

    await tester.fling(find.text('A film'), const Offset(0, 400), 1000);
    await step(tester);
    await step(tester);

    expect(films.reads, reads + 1);
    await app.stop(tester);
  });

  testWidgets('another profile does not see the entries', (tester) async {
    await start(tester);
    films.items = [entry(1, 'A film')];
    final away = await app.addProfile('Away');
    await app.add(module, 'Elsewhere', profileId: away);
    module.of('Elsewhere').items = [entry(1, 'Another film')];
    await open(tester);

    await app.services.registry.switchTo(away);
    await step(tester);
    await go(tester, 'Activity');

    expect(find.text('A film'), findsNothing);
    expect(find.text('Another film'), findsOneWidget);
    await app.stop(tester);
  });

  for (final size in [const Size(320, 568), const Size(800, 400)]) {
    testWidgets('is usable at 200% text on $size', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final semantics = tester.ensureSemantics();
      await start(tester, others: ['Shows'], size: size);
      films.items = [
        entry(
          1,
          'A film with a very long release name 2026 1080p WEB-DL group',
          status: QueueStatus.delayed,
          severity: QueueSeverity.error,
          messages: ['A long reason that has to wrap over several lines'],
        ),
      ];
      module.of('Shows').failure = const Unreachable();
      await app.pump(tester);
      app.services.navigator.router!.go('/activity');
      await step(tester);

      expect(tester.takeException(), isNull);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      final title = find.textContaining('A film with');
      await tester.scrollUntilVisible(
        title,
        100,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await step(tester);
      await tester.tap(title);
      await step(tester);
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        button('Remove from queue'),
        100,
        scrollable: find.byType(Scrollable).last,
      );
      await step(tester);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await tester.tap(button('Remove from queue'));
      await step(tester);
      expect(tester.takeException(), isNull);
      await tick(tester, 'Block this release');
      expect(tester.takeException(), isNull);
      semantics.dispose();
      await app.stop(tester);
    });
  }
}
