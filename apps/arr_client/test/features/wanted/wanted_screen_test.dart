import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support.dart';

Finder _searchButton(String title) => find.byTooltip('Search for $title');

Finder get _searchAll => find.text('Search all');

void main() {
  testWidgets('lists each service apart, in its server order', (tester) async {
    final wanted = await WantedHarness.start(tester);
    wanted.server('Films').missing = [
      [wanted.movie('Films', 2, title: 'Zulu'), wanted.movie('Films', 1)],
    ];
    wanted.server('Shows').missing = [
      [wanted.episode('Shows', 3)],
    ];
    await wanted.pump(tester);

    final order = [
      for (final text in ['Films', 'Zulu', 'Film 1', 'Shows', 'The Show'])
        tester.getTopLeft(find.text(text)).dy,
    ];
    expect(order, [...order]..sort());
    expect(find.text('S01E03 · Pilot'), findsOneWidget);
    expect(find.textContaining('Aired '), findsOneWidget);
    // What the whole list is goes without saying.
    expect(find.text('Missing'), findsOneWidget);
    await wanted.stop(tester);
  });

  testWidgets('shows the cutoff unmet list in its own tab', (tester) async {
    final wanted = await WantedHarness.start(tester, names: ['Films']);
    wanted.server('Films').cutoff = [
      [wanted.movie('Films', 5, state: ItemState.downloaded)],
    ];
    await wanted.pump(tester);
    expect(find.text('Nothing is missing.'), findsOneWidget);

    await tester.tap(find.text('Cutoff unmet'));
    await tester.pumpAndSettle();
    expect(find.text('Film 5'), findsOneWidget);
    await wanted.stop(tester);
  });

  testWidgets('reads a further page when asked', (tester) async {
    final wanted = await WantedHarness.start(tester, names: ['Films']);
    final server = wanted.server('Films')
      ..missing = [
        [wanted.movie('Films', 1)],
        // The list moved between the pages.
        [wanted.movie('Films', 1), wanted.movie('Films', 2)],
      ];
    await wanted.pump(tester);
    expect(find.text('Film 2'), findsNothing);

    await tester.tap(find.text('Show more'));
    await tester.pumpAndSettle();
    expect(find.text('Film 1'), findsOneWidget);
    expect(find.text('Film 2'), findsOneWidget);
    expect(find.text('Show more'), findsNothing);
    expect(server.reads, [1, 2]);

    // Reading again keeps both pages.
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    expect(server.reads, [1, 2, 1, 2]);
    expect(find.text('Film 2'), findsOneWidget);
    await wanted.stop(tester);
  });

  testWidgets('one service failing leaves the others, with a retry', (
    tester,
  ) async {
    final wanted = await WantedHarness.start(tester);
    wanted.server('Films').failure = const Unreachable();
    wanted.server('Shows').missing = [
      [wanted.episode('Shows', 1)],
    ];
    await wanted.pump(tester);
    expect(find.text('The Show'), findsOneWidget);
    expect(find.textContaining('did not answer'), findsOneWidget);
    expect(find.text('Nothing is missing.'), findsNothing);

    wanted.server('Films')
      ..failure = null
      ..missing = [
        [wanted.movie('Films', 1)],
      ];
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Film 1'), findsOneWidget);
    await wanted.stop(tester);
  });

  testWidgets('a search for one item is sent once, naming it', (tester) async {
    final wanted = await WantedHarness.start(tester, names: ['Films']);
    final server = wanted.server('Films')
      ..missing = [
        [wanted.movie('Films', 7), wanted.movie('Films', 8)],
      ]
      ..sending = Completer<void>();
    await wanted.pump(tester);

    await tester.tap(_searchButton('Film 7'));
    await step(tester);
    // No second search while the first waits for its answer.
    await tester.tap(_searchButton('Film 8'));
    await step(tester);
    expect(server.searches, [
      [7],
    ]);

    server.sending!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Films accepted a search for Film 7.'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    await wanted.stop(tester);
  });

  testWidgets('searches for the selected items, one command a service', (
    tester,
  ) async {
    final wanted = await WantedHarness.start(tester);
    wanted.server('Films').missing = [
      [wanted.movie('Films', 1), wanted.movie('Films', 2)],
    ];
    wanted.server('Shows').missing = [
      [wanted.episode('Shows', 3)],
    ];
    await wanted.pump(tester);

    await tester.tap(find.text('Select'));
    await tester.pump();
    expect(_searchAll, findsNothing);
    await tester.tap(find.text('Film 2'));
    await tester.tap(find.text('The Show'));
    await tester.pump();
    expect(find.text('2 selected'), findsOneWidget);
    await tester.tap(find.text('Search selected'));
    await tester.pumpAndSettle();
    expect(find.text('Search for 2 items?'), findsOneWidget);
    expect(wanted.server('Films').searches, isEmpty);
    await tester.tap(find.text('Search for 2 items'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Films accepted a search for Film 2.\n'
        'Shows accepted a search for The Show S01E03.',
      ),
      findsOneWidget,
    );
    expect(wanted.server('Films').searches, [
      [2],
    ]);
    expect(wanted.server('Shows').searches, [
      [3],
    ]);
    expect(find.text('2 selected'), findsNothing);
    await wanted.stop(tester);
  });

  testWidgets('sends nothing when the selection is not confirmed', (
    tester,
  ) async {
    final wanted = await WantedHarness.start(
      tester,
      names: ['Films'],
      size: const Size(400, 2000),
    );
    final server = wanted.server('Films')
      ..missing = [
        [for (var id = 1; id <= 11; id++) wanted.movie('Films', id)],
      ];
    await wanted.pump(tester);
    await tester.tap(find.text('Select'));
    await tester.pump();
    for (var id = 1; id <= 11; id++) {
      await tester.tap(find.text('Film $id'));
      await tester.pump();
    }
    await tester.tap(find.text('Search selected'));
    await tester.pumpAndSettle();
    expect(find.text('Search for 11 items?'), findsOneWidget);
    expect(find.text('11 items on Films'), findsOneWidget);

    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();
    expect(server.searches, isEmpty);

    await tester.tap(find.text('Search selected'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Search for 11 items'));
    await tester.pumpAndSettle();
    expect(server.searches.single, [for (var id = 1; id <= 11; id++) id]);
    await wanted.stop(tester);
  });

  testWidgets('search all reads every page and names every item', (
    tester,
  ) async {
    final wanted = await WantedHarness.start(tester, names: ['Films']);
    final server = wanted.server('Films')
      ..missing = [
        [wanted.movie('Films', 1)],
        [wanted.movie('Films', 2, state: ItemState.unreleased)],
        [wanted.movie('Films', 3, state: ItemState.downloading)],
      ];
    await wanted.pump(tester);

    await tester.tap(_searchAll);
    await tester.pumpAndSettle();
    expect(find.text('Search all missing?'), findsOneWidget);
    expect(find.text('3 items on Films'), findsOneWidget);
    expect(find.textContaining('1 not released yet.'), findsOneWidget);
    expect(find.textContaining('1 already downloading.'), findsOneWidget);
    expect(server.searches, isEmpty);

    await tester.tap(find.text('Search for 3 items'));
    await tester.pumpAndSettle();
    expect(server.searches, [
      [1, 2, 3],
    ]);
    expect(find.text('Films accepted a search for 3 items.'), findsOneWidget);
    await wanted.stop(tester);
  });

  testWidgets('search all sends nothing when cancelled', (tester) async {
    final wanted = await WantedHarness.start(tester, names: ['Films']);
    final server = wanted.server('Films')
      ..missing = [
        [wanted.movie('Films', 1)],
      ];
    await wanted.pump(tester);

    // At the confirmation.
    await tester.tap(_searchAll);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // While the list is still being read.
    final held = server.held = Completer<void>();
    await tester.tap(_searchAll);
    await step(tester);
    expect(find.text('Reading the whole list'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await step(tester);
    held.complete();
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Film 1'), findsOneWidget);
    expect(server.searches, isEmpty);
    await wanted.stop(tester);
  });

  testWidgets('search all sends nothing if a page cannot be read', (
    tester,
  ) async {
    final wanted = await WantedHarness.start(tester, names: ['Films']);
    final server = wanted.server('Films')
      ..missing = [
        [wanted.movie('Films', 1)],
        [wanted.movie('Films', 2)],
      ]
      ..failingPage = 2;
    await wanted.pump(tester);

    await tester.tap(_searchAll);
    await tester.pumpAndSettle();
    expect(find.textContaining('Films: nothing was searched'), findsOneWidget);
    expect(server.searches, isEmpty);
    await wanted.stop(tester);
  });

  testWidgets('an unknown outcome is reported and nothing is sent again', (
    tester,
  ) async {
    final wanted = await WantedHarness.start(tester, names: ['Films']);
    final server = wanted.server('Films')
      ..missing = [
        [wanted.movie('Films', 1)],
      ]
      ..answer = const Err(OutcomeUnknown());
    await wanted.pump(tester);
    final reads = server.reads.length;

    await tester.tap(_searchButton('Film 1'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('may or may not have started. It was not sent again'),
      findsOneWidget,
    );
    await tester.pump(const Duration(minutes: 1));
    expect(server.searches, hasLength(1));
    // The list is read again.
    expect(server.reads.length, greaterThan(reads));
    await wanted.stop(tester);
  });

  testWidgets('offers no search to a service that takes no commands', (
    tester,
  ) async {
    final wanted = await WantedHarness.start(
      tester,
      names: ['Films'],
      commands: false,
    );
    wanted.server('Films').missing = [
      [wanted.movie('Films', 1)],
    ];
    await wanted.pump(tester);

    expect(find.text('Film 1'), findsOneWidget);
    expect(_searchAll, findsNothing);
    expect(find.text('Select'), findsNothing);
    expect(_searchButton('Film 1'), findsNothing);
    await wanted.stop(tester);
  });

  testWidgets('fits large text and labels its controls', (tester) async {
    final semantics = tester.ensureSemantics();
    final wanted = await WantedHarness.start(
      tester,
      size: const Size(320, 640),
    );
    wanted.server('Films').missing = [
      [wanted.movie('Films', 1, title: 'A very long title that has to wrap')],
      [
        wanted.movie('Films', 2, state: ItemState.unreleased),
        wanted.movie('Films', 3, state: ItemState.downloading),
      ],
    ];
    wanted.server('Shows').missing = [
      [wanted.episode('Shows', 1, title: 'Another long episode title here')],
    ];
    await wanted.pump(tester, textScale: 2);
    expect(tester.takeException(), isNull);
    expect(find.bySemanticsLabel('Search all items of Films'), findsOneWidget);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

    await tester.tap(find.text('Select'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await tester.tap(_searchAll.first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('3 items on Films'), findsOneWidget);
    // What is out of the ordinary comes first.
    expect(
      find.textContaining(
        RegExp(r'^1 not released yet\.\n1 already downloading\.\n\n'),
      ),
      findsOneWidget,
    );
    semantics.dispose();
    await wanted.stop(tester);
  });

  testWidgets('one message says how the search went on every service', (
    tester,
  ) async {
    final wanted = await WantedHarness.start(tester);
    wanted.server('Films')
      ..missing = [
        [wanted.movie('Films', 1)],
      ]
      ..answer = const Err(OutcomeUnknown());
    wanted.server('Shows').missing = [
      [wanted.episode('Shows', 3)],
    ];
    await wanted.pump(tester);
    await tester.tap(find.text('Select'));
    await tester.pump();
    await tester.tap(find.text('Film 1'));
    await tester.tap(find.text('The Show'));
    await tester.pump();
    await tester.tap(find.text('Search selected'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Search for 2 items'));
    await tester.pumpAndSettle();

    final message = find.textContaining('may or may not have started');
    expect(message, findsOneWidget);
    expect(
      tester.widget<Text>(message).data,
      contains('Shows accepted a search for The Show S01E03.'),
    );
    expect(wanted.server('Films').searches, hasLength(1));
    await wanted.stop(tester);
  });

  testWidgets('Back leaves only the selection of the tab on screen', (
    tester,
  ) async {
    final wanted = await WantedHarness.start(tester, names: ['Films']);
    wanted.server('Films')
      ..missing = [
        [wanted.movie('Films', 1)],
      ]
      ..cutoff = [
        [wanted.movie('Films', 2, state: ItemState.downloaded)],
      ];
    await wanted.pump(tester);
    await tester.tap(find.text('Select'));
    await tester.pump();
    await tester.tap(find.text('Film 1'));
    await tester.pump();

    await tester.tap(find.text('Cutoff unmet'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select'));
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Select'), findsOneWidget);

    await tester.tap(find.text('Missing'));
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsNothing);
    await wanted.stop(tester);
  });

  testWidgets('an item found gone leaves the list, with its series', (
    tester,
  ) async {
    final wanted = await WantedHarness.start(tester);
    wanted.server('Films').missing = [
      [wanted.movie('Films', 1), wanted.movie('Films', 2)],
    ];
    wanted.server('Shows').missing = [
      [wanted.episode('Shows', 3)],
    ];
    await wanted.pump(tester);

    await wanted.removed('Films', MediaKind.movie, 1);
    await wanted.removed('Shows', MediaKind.series, 9);
    await tester.pumpAndSettle();
    expect(find.text('Film 1'), findsNothing);
    expect(find.text('Film 2'), findsOneWidget);
    expect(find.text('The Show'), findsNothing);
    await wanted.stop(tester);
  });

  testWidgets('a read under way does not bring a gone item back', (
    tester,
  ) async {
    final wanted = await WantedHarness.start(tester, names: ['Films']);
    final server = wanted.server('Films')
      ..missing = [
        [wanted.movie('Films', 1), wanted.movie('Films', 2)],
      ];
    await wanted.pump(tester);
    final held = server.held = Completer<void>();
    await tester.tap(find.byTooltip('Refresh'));
    await step(tester);

    await wanted.removed('Films', MediaKind.movie, 2);
    await step(tester);
    held.complete();
    await tester.pumpAndSettle();
    expect(find.text('Film 1'), findsOneWidget);
    expect(find.text('Film 2'), findsNothing);
    await wanted.stop(tester);
  });

  testWidgets('search all leaves out what went before it was confirmed', (
    tester,
  ) async {
    final wanted = await WantedHarness.start(tester, names: ['Films']);
    final server = wanted.server('Films')
      ..missing = [
        [wanted.movie('Films', 1), wanted.movie('Films', 2)],
      ];
    await wanted.pump(tester);
    await tester.tap(_searchAll);
    await tester.pumpAndSettle();

    await wanted.removed('Films', MediaKind.movie, 2);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Search for 2 items'));
    await tester.pumpAndSettle();
    expect(server.searches, [
      [1],
    ]);
    await wanted.stop(tester);
  });
}
