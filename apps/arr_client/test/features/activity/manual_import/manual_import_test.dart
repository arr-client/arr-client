/// Manual import (spec story 4, scenario 4).
library;

import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/support.dart';
import '../queue/support.dart';
import 'support.dart';

void main() {
  late ImportModule module;
  late TestApp app;
  late FakeImportQueue queue;

  Future<void> start(
    WidgetTester tester, {
    MediaKind kind = MediaKind.movie,
    Size size = const Size(400, 1400),
  }) async {
    useScreen(tester, size);
    module = ImportModule(kind: kind);
    queue = module.queue;
    app = await TestApp.start(tester, modules: [module]);
    module.instanceId = await app.add(module, 'Films');
    queue.items = [
      entry(
        1,
        'A.Download',
        status: QueueStatus.completed,
        trackedState: TrackedState.importBlocked,
        severity: QueueSeverity.warning,
        needsManualImport: true,
      ),
    ];
    if (kind == MediaKind.movie) {
      module.films.items = [
        movie(module.ref(1), 'Alpha'),
        movie(module.ref(2), 'Beta'),
      ];
    } else {
      module.films.items = [
        show(module.ref(1), 'Gamma'),
        show(module.ref(2), 'Delta'),
      ];
      module.films.episodes[1] = [
        episode(module.ref(11, MediaKind.episode), 1, 1, 'Pilot'),
        episode(module.ref(12, MediaKind.episode), 1, 2, 'Second'),
        episode(module.ref(21, MediaKind.episode), 2, 1, 'Return'),
      ];
      module.films.episodes[2] = [
        episode(module.ref(31, MediaKind.episode), 1, 1, 'Opening'),
      ];
    }
  }

  Finder button(String label) => find.ancestor(
    of: find.text(label),
    matching: find.bySubtype<ButtonStyleButton>(),
  );

  bool enabled(WidgetTester tester, String label) =>
      tester.widget<ButtonStyleButton>(button(label)).enabled;

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await step(tester);
    await tester.tap(finder);
    await step(tester);
  }

  /// Opens the manual import of the queue entry.
  Future<void> open(WidgetTester tester) async {
    await app.pump(tester);
    await go(tester, 'Activity');
    await tap(tester, find.text('A.Download'));
    await tap(tester, button('Import files'));
  }

  Finder inDialog(String text) =>
      find.descendant(of: find.byType(Dialog), matching: find.text(text));

  /// The checkbox of the file [name].
  CheckboxListTile box(WidgetTester tester, String name) => tester.widget(
    find.ancestor(of: find.text(name), matching: find.byType(CheckboxListTile)),
  );

  /// Selects every ready file and presses the import button.
  Future<void> askToImport(WidgetTester tester, [int count = 1]) async {
    await tap(tester, button('Select all ready'));
    await tap(tester, button('Import $count file${count == 1 ? '' : 's'}'));
  }

  Future<void> confirm(WidgetTester tester, [int count = 1]) =>
      tap(tester, inDialog('Import $count file${count == 1 ? '' : 's'}'));

  testWidgets('shows the files with the server\'s matches and rejections', (
    tester,
  ) async {
    await start(tester);
    queue.files = [
      candidate(
        'alpha.mkv',
        match: module.ref(1),
        rejections: ['Not an upgrade'],
      ),
      candidate('mystery.mkv'),
    ];

    await open(tester);

    expect(find.text('alpha.mkv'), findsOneWidget);
    expect(find.text('/downloads/pack/alpha.mkv'), findsOneWidget);
    expect(find.text('Alpha (2020)'), findsOneWidget);
    expect(find.text('WEBDL-1080p'), findsNWidgets(2));
    expect(find.text('English'), findsNWidgets(2));
    expect(find.text('Not an upgrade'), findsOneWidget);
    expect(find.text('Not matched'), findsOneWidget);
    expect(find.text('Choose a movie to import this file.'), findsOneWidget);
    expect(box(tester, 'mystery.mkv').onChanged, isNull);
    expect(box(tester, 'alpha.mkv').value, isFalse);
    expect(enabled(tester, 'Import selected files'), isFalse);
    await app.stop(tester);
  });

  testWidgets('is only offered for entries that need it', (tester) async {
    await start(tester);
    queue.items = [entry(1, 'A.Download')];
    await app.pump(tester);
    await go(tester, 'Activity');
    await tap(tester, find.text('A.Download'));

    expect(find.text('Import files'), findsNothing);
    await app.stop(tester);
  });

  testWidgets('says what will happen and sends nothing without a yes', (
    tester,
  ) async {
    await start(tester);
    queue.files = [
      candidate(
        'alpha.mkv',
        match: module.ref(1),
        rejections: ['Not an upgrade'],
      ),
      candidate('again.mkv', match: module.ref(1)),
    ];
    await open(tester);

    await tap(tester, find.text('alpha.mkv'));
    await tap(tester, find.text('again.mkv'));
    await tap(tester, button('Import 2 files'));

    expect(find.text('Import 2 files?'), findsOneWidget);
    expect(find.text('2 files on Films'), findsOneWidget);
    expect(
      find.textContaining('alpha.mkv\nAlpha (2020)\nWEBDL-1080p · English'),
      findsOneWidget,
    );
    expect(find.textContaining('Films moves or copies'), findsOneWidget);
    expect(find.textContaining('may replace a file'), findsOneWidget);
    expect(find.textContaining('rejected 1 of these'), findsOneWidget);
    expect(find.textContaining('Some share a match'), findsOneWidget);

    await tap(tester, inDialog('Cancel'));

    expect(queue.imports, isEmpty);
    await app.stop(tester);
  });

  testWidgets('imports the selected files once and follows the command', (
    tester,
  ) async {
    await start(tester);
    queue
      ..files = [
        candidate('alpha.mkv', match: module.ref(1)),
        candidate('beta.mkv', match: module.ref(2)),
      ]
      ..importGate = Completer<void>();
    module.commands.status = CommandStatus.started;
    await open(tester);

    await tap(tester, find.text('beta.mkv'));
    await tap(tester, button('Import 1 file'));
    await confirm(tester);

    expect(find.text('Films accepted the import.'), findsNothing);
    expect(find.bySemanticsLabel('Sending the import'), findsOneWidget);

    queue.importGate!.complete();
    await step(tester);

    expect(queue.imports.single.map((c) => c.path), [
      '/downloads/pack/beta.mkv',
    ]);
    expect(find.text('Films accepted the import.'), findsOneWidget);
    expect(
      find.text('Films accepted the import and has not finished it.'),
      findsOneWidget,
    );
    expect(box(tester, 'beta.mkv').onChanged, isNull, reason: 'running');

    final reads = queue.fileReads;
    queue.files = [candidate('alpha.mkv', match: module.ref(1))];
    module.commands.status = CommandStatus.completed;
    await tester.pump(const Duration(seconds: 2));
    await step(tester);

    expect(
      find.textContaining('Films reports that the import finished.'),
      findsOneWidget,
    );
    expect(queue.fileReads, reads + 1);
    expect(find.text('beta.mkv'), findsNothing);
    final commandReads = module.commands.reads;
    await tester.pump(const Duration(seconds: 10));
    expect(module.commands.reads, commandReads);
    expect(queue.imports, hasLength(1));
    await app.stop(tester);
  });

  testWidgets('says when the server reports a failed import', (tester) async {
    await start(tester);
    queue.files = [candidate('alpha.mkv', match: module.ref(1))];
    module.commands
      ..status = CommandStatus.failed
      ..message = 'Disk full';
    await open(tester);
    await askToImport(tester);
    await confirm(tester);
    await tester.pump(const Duration(seconds: 2));
    await step(tester);

    expect(
      find.text('Films reports that the import failed.\nDisk full'),
      findsOneWidget,
    );
    await app.stop(tester);
  });

  testWidgets('asks for the progress again only when told after a failure', (
    tester,
  ) async {
    await start(tester);
    queue.files = [candidate('alpha.mkv', match: module.ref(1))];
    module.commands.failure = const Unreachable();
    await open(tester);
    await askToImport(tester);
    await confirm(tester);
    await tester.pump(const Duration(seconds: 2));
    await step(tester);

    expect(
      find.textContaining('The progress of the import could not be read.'),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 10));
    expect(module.commands.reads, 1);

    module.commands.failure = const NotFound();
    await tap(tester, button('Check progress again'));

    expect(
      find.textContaining('does not say whether the import succeeded'),
      findsOneWidget,
    );
    expect(queue.imports, hasLength(1));
    await app.stop(tester);
  });

  testWidgets('reports an unknown outcome and does not send again', (
    tester,
  ) async {
    await start(tester);
    queue
      ..files = [candidate('alpha.mkv', match: module.ref(1))]
      ..importFailure = const OutcomeUnknown();
    await open(tester);
    await askToImport(tester);
    final reads = queue.fileReads;
    await confirm(tester);
    await tester.pump(const Duration(seconds: 30));

    expect(queue.imports, hasLength(1));
    expect(queue.fileReads, reads + 1);
    expect(
      find.textContaining('It is not known whether Films received the import.'),
      findsOneWidget,
    );
    expect(find.text('Films accepted the import.'), findsNothing);

    await askToImport(tester);
    expect(
      find.textContaining('The last import may have arrived.'),
      findsOneWidget,
    );
    await app.stop(tester);
  });

  testWidgets('has a chosen movie evaluated before it can be imported', (
    tester,
  ) async {
    await start(tester);
    queue.files = [candidate('mystery.mkv')];
    await open(tester);

    await tap(tester, find.text('Not matched'));
    await tester.enterText(find.byType(TextField), 'bet');
    await step(tester);
    expect(inDialog('Alpha (2020)'), findsNothing);
    await tap(tester, inDialog('Beta (2020)'));

    expect(queue.reprocessed.single.matchedRef, module.ref(2));
    expect(find.text('Beta (2020)'), findsOneWidget);
    await askToImport(tester);
    await confirm(tester);
    expect(queue.imports.single.single.matchedRef, module.ref(2));
    await app.stop(tester);
  });

  testWidgets('corrects quality and language', (tester) async {
    await start(tester);
    queue.files = [candidate('alpha.mkv', match: module.ref(1))];
    await open(tester);

    await tap(tester, find.text('WEBDL-1080p'));
    await tap(tester, inDialog('Bluray-1080p'));
    await tap(tester, find.text('English'));
    await tap(tester, inDialog('German'));
    await tap(tester, inDialog('English'));
    await tap(tester, inDialog('Use selection'));

    expect(queue.reprocessed, hasLength(2));
    await askToImport(tester);
    await confirm(tester);
    final sent = queue.imports.single.single;
    expect(sent.quality?.id, 7);
    expect(sent.languages.map((l) => l.id), [4]);
    await app.stop(tester);
  });

  testWidgets('keeps a correction that the server cannot check', (
    tester,
  ) async {
    await start(tester);
    queue
      ..files = [
        candidate(
          'alpha.mkv',
          match: module.ref(1),
          rejections: ['Unknown movie'],
        ),
      ]
      ..reprocessFailure = const ServerError(statusCode: 500);
    await open(tester);

    await tap(tester, find.text('Alpha (2020)'));
    await tap(tester, inDialog('Beta (2020)'));
    await tester.pump(const Duration(seconds: 30));

    expect(queue.reprocessed, hasLength(1), reason: 'not sent again');
    expect(find.text('Beta (2020)'), findsOneWidget);
    expect(find.text('Rejected before the correction:'), findsOneWidget);
    expect(find.text('Unknown movie'), findsOneWidget);
    expect(
      find.textContaining('The server could not check this correction.'),
      findsOneWidget,
    );
    expect(enabled(tester, 'Select all ready'), isFalse);
    await tap(tester, find.text('alpha.mkv'));
    await tap(tester, button('Import 1 file'));
    expect(find.textContaining('rejected 1 of these'), findsOneWidget);
    expect(
      find.textContaining('Rejected before the correction:\nUnknown movie'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Some corrections are unchecked.'),
      findsOneWidget,
    );
    await app.stop(tester);
  });

  testWidgets('wants new episodes after the series changes', (tester) async {
    await start(tester, kind: MediaKind.series);
    queue.files = [
      candidate('one.mkv', match: module.ref(1), episodeIds: [11]),
    ];
    await open(tester);
    expect(find.text('S01E01 · Pilot'), findsOneWidget);
    await tap(tester, button('Select all ready'));

    await tap(tester, find.text('Gamma'));
    await tap(tester, inDialog('Delta'));

    expect(queue.reprocessed, isEmpty, reason: 'no episodes yet');
    expect(find.text('None chosen'), findsOneWidget);
    expect(find.text('Choose episodes to import this file.'), findsOneWidget);
    expect(box(tester, 'one.mkv').value, isFalse);
    expect(box(tester, 'one.mkv').onChanged, isNull);

    await tap(tester, find.text('None chosen'));
    await tap(tester, inDialog('S01E01 · Opening'));
    await tap(tester, inDialog('Use selection'));

    expect(queue.reprocessed.single.matchedRef, module.ref(2));
    expect(queue.reprocessed.single.episodeIds, [31]);
    expect(find.text('S01E01 · Opening'), findsOneWidget);
    await app.stop(tester);
  });

  testWidgets('takes episodes of one season only', (tester) async {
    await start(tester, kind: MediaKind.series);
    queue.files = [candidate('one.mkv', match: module.ref(1))];
    await open(tester);

    await tap(tester, find.text('None chosen'));
    await tap(tester, inDialog('S01E01 · Pilot'));
    await tap(tester, inDialog('S01E02 · Second'));
    await tap(tester, inDialog('S02E01 · Return'));
    await tap(tester, inDialog('Use selection'));

    expect(queue.reprocessed.single.episodeIds, [21]);
    await app.stop(tester);
  });

  testWidgets('says when the evaluation drops the episodes', (tester) async {
    await start(tester, kind: MediaKind.series);
    queue
      ..files = [
        candidate('one.mkv', match: module.ref(1), episodeIds: [11]),
      ]
      ..evaluate = (sent) => candidate('one.mkv', match: sent.matchedRef);
    await open(tester);
    await tap(tester, button('Select all ready'));

    await tap(tester, find.text('WEBDL-1080p'));
    await tap(tester, inDialog('Bluray-1080p'));

    expect(find.textContaining('The server kept no episodes.'), findsOneWidget);
    expect(box(tester, 'one.mkv').value, isFalse);
    expect(enabled(tester, 'Import selected files'), isFalse);
    await app.stop(tester);
  });

  testWidgets('shows loading failures, stale files and nothing to import', (
    tester,
  ) async {
    await start(tester);
    queue.filesFailure = const Unreachable();
    await open(tester);
    expect(find.text('Retry'), findsOneWidget);

    queue
      ..filesFailure = null
      ..files = [candidate('alpha.mkv', match: module.ref(1))];
    await tap(tester, button('Retry'));
    await tap(tester, button('Select all ready'));
    expect(enabled(tester, 'Import 1 file'), isTrue);

    queue.filesFailure = const Unreachable();
    await tap(tester, find.byTooltip('Reload the files'));
    expect(find.text('alpha.mkv'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(enabled(tester, 'Import 1 file'), isFalse);
    expect(box(tester, 'alpha.mkv').onChanged, isNull);

    queue
      ..filesFailure = null
      ..files = [];
    await tap(tester, button('Retry'));
    expect(
      find.text('No files of this download are waiting for import.'),
      findsOneWidget,
    );
    await app.stop(tester);
  });

  testWidgets('does not offer an import while the library cannot be read', (
    tester,
  ) async {
    await start(tester);
    queue.files = [candidate('alpha.mkv', match: module.ref(1))];
    module.films.failure = const Unreachable();
    await open(tester);

    expect(find.text('Name not loaded'), findsOneWidget);
    expect(box(tester, 'alpha.mkv').onChanged, isNull);

    module.films.failure = null;
    await tap(tester, button('Try loading again'));

    expect(find.text('Alpha (2020)'), findsOneWidget);
    expect(box(tester, 'alpha.mkv').onChanged, isNotNull);
    await app.stop(tester);
  });

  testWidgets('works with large text and labels its controls', (tester) async {
    final semantics = tester.ensureSemantics();
    await start(tester, kind: MediaKind.series, size: const Size(360, 700));
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    queue.files = [
      candidate(
        'a.very.long.release.name.S01E01.1080p.WEB-DL.mkv',
        match: module.ref(1),
        episodeIds: [11],
        rejections: ['Not an upgrade for existing episode file(s)'],
      ),
    ];
    await open(tester);
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));

    await tap(tester, find.byType(Checkbox));
    await tap(tester, button('Import 1 file'));
    expect(find.byType(AlertDialog), findsOneWidget);
    await tap(tester, inDialog('Cancel'));

    final series = find.text('Gamma');
    await tester.scrollUntilVisible(
      series,
      -100,
      scrollable: find.byType(Scrollable).first,
    );
    await tap(tester, series);
    await tap(tester, find.byTooltip('Cancel'));
    final episodes = find.text('S01E01 · Pilot');
    await tap(tester, episodes);
    expect(find.text('Choose episodes'), findsOneWidget);
    await tap(tester, find.byTooltip('Cancel'));

    expect(tester.takeException(), isNull);
    expect(queue.reprocessed, isEmpty);
    semantics.dispose();
    await app.stop(tester);
  });

  testWidgets('does not select rejected files with the others', (tester) async {
    await start(tester);
    queue.files = [
      candidate(
        'alpha.mkv',
        match: module.ref(1),
        rejections: ['Not an upgrade'],
      ),
      candidate('beta.mkv', match: module.ref(2)),
    ];
    await open(tester);

    await tap(tester, button('Select all ready'));

    expect(box(tester, 'alpha.mkv').value, isFalse);
    expect(box(tester, 'beta.mkv').value, isTrue);
    await app.stop(tester);
  });

  testWidgets('shows what will happen without scrolling on a phone', (
    tester,
  ) async {
    await start(tester, size: const Size(360, 800));
    queue.files = [
      for (var i = 1; i <= 6; i++)
        candidate(
          'a.long.release.name.part$i.1080p.WEB-DL.mkv',
          match: module.ref(1),
          rejections: ['Not an upgrade for existing movie file'],
        ),
    ];
    await open(tester);
    for (var i = 1; i <= 6; i++) {
      await tap(
        tester,
        find.text('a.long.release.name.part$i.1080p.WEB-DL.mkv'),
      );
    }

    await tap(tester, button('Import 6 files'));

    final view = tester.getRect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(SingleChildScrollView),
      ),
    );
    final warnings = tester.getRect(find.textContaining('moves or copies'));
    final text = tester
        .widget<Text>(find.textContaining('moves or copies'))
        .data!;
    expect(text, contains('This cannot be undone.'));
    expect(text, contains('rejected 6 of these'));
    expect(text, contains('Some share a match'));
    expect(warnings.top, greaterThanOrEqualTo(view.top));
    expect(warnings.bottom, lessThanOrEqualTo(view.bottom));
    await app.stop(tester);
  });

  testWidgets('reads the episodes again with the files', (tester) async {
    await start(tester, kind: MediaKind.series);
    queue.files = [
      candidate('one.mkv', match: module.ref(1), episodeIds: [11]),
    ];
    await open(tester);
    expect(find.text('S01E01 \u00b7 Pilot'), findsOneWidget);

    module.films.episodes[1] = [
      episode(module.ref(11, MediaKind.episode), 1, 1, 'Renamed'),
    ];
    await tap(tester, find.byTooltip('Reload the files'));

    expect(find.text('S01E01 \u00b7 Renamed'), findsOneWidget);
    await app.stop(tester);
  });
}
