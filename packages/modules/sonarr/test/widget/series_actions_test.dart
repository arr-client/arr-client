// What the user can do on the series, season and episode screens (spec story
// 5), over the module's own adapters and the recorded server.

import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../contract/manage_support.dart';
import '../contract/support.dart';
import 'support.dart';

/// A [ManageServer] that holds the answer to a request in [held], named by its
/// method and path, until the completer completes.
class _Server extends ManageServer {
  final held = <String, Completer<void>>{};

  /// Whether reading the series fails.
  bool seriesFails = false;

  /// What every write of a file gets, if set.
  Result<ServiceResponse, HttpError>? deleteAnswer;

  @override
  Future<Result<ServiceResponse, HttpError>> send(
    ServiceRequest request,
  ) async {
    final failed = seriesFails && _name(request) == 'get series/1';
    final answer = await super.send(request);
    await held[_name(request)]?.future;
    if (failed) return FakeSonarr.body('', status: 500);
    return request.method == HttpMethod.delete
        ? deleteAnswer ?? answer
        : answer;
  }

  static String _name(ServiceRequest request) =>
      '${request.method.name} ${request.path.replaceFirst('api/v3/', '')}';

  List<String> get written => [for (final request in writes) _name(request)];

  int count(String name) =>
      requests.where((request) => _name(request) == name).length;

  /// Episode 13, which has a file.
  Map<String, Object?> get episode13 => byId(episodes[1]!, 13);
}

final _series = ModuleRoute(instanceId: instanceId, path: 'sonarr/series/1');

ModuleRoute _season(int number) => ModuleRoute(
  instanceId: instanceId,
  path: 'sonarr/series/1/seasons/$number',
);

const _episode = ModuleRoute(
  instanceId: instanceId,
  path: 'sonarr/episodes/13',
);

const _path = '/redacted/61.mkv';

void main() {
  late _Server server;
  late Screens screens;

  setUp(() {
    server = _Server();
    screens = Screens(server: server);
  });

  void size(WidgetTester tester, [Size size = const Size(400, 4000)]) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<void> open(WidgetTester tester, ModuleRoute route) async {
    size(tester);
    await screens.open(tester, route);
  }

  // Progress indicators never settle.
  Future<void> step(
    WidgetTester tester, [
    Duration duration = const Duration(milliseconds: 500),
  ]) async {
    await tester.pump();
    await tester.pump(duration);
    await tester.pump();
  }

  Future<void> choose(WidgetTester tester, String entry) async {
    await tester.tap(find.byTooltip('More actions'));
    await step(tester);
    await tester.tap(find.text(entry));
    await step(tester);
  }

  /// The screen's own scroll view: a message of an outcome scrolls too.
  Finder page() => find
      .descendant(
        of: find.byType(CustomScrollView),
        matching: find.byType(Scrollable),
      )
      .first;

  SwitchListTile toggle(WidgetTester tester) =>
      tester.widget(find.byType(SwitchListTile));

  ButtonStyleButton button(WidgetTester tester, String label) => tester.widget(
    find.ancestor(
      of: find.text(label),
      matching: find.bySubtype<ButtonStyleButton>(),
    ),
  );

  Object? posted() => sentBody(
    server.writes.singleWhere((request) => request.method == HttpMethod.post),
  );

  /// Has the command [fixture] answered with [status] when it is read.
  void command(String fixture, String status, {String result = 'unknown'}) {
    server.command = {...record(fixture), 'status': status, 'result': result};
  }

  group('monitoring', () {
    testWidgets('a series shows the new value at once, and success only once '
        'the server has accepted it', (tester) async {
      final answered = server.held['put series/1'] = Completer<void>();
      await open(tester, _series);
      expect(toggle(tester).value, isTrue);

      await tester.tap(find.byType(SwitchListTile));
      await step(tester);

      expect(toggle(tester).value, isFalse);
      expect(toggle(tester).onChanged, isNull);
      expect(find.text('The series is no longer monitored'), findsNothing);

      server.series.first['monitored'] = false;
      server.item['monitored'] = false;
      answered.complete();
      await tester.pumpAndSettle();

      expect(find.text('The series is no longer monitored'), findsOneWidget);
      expect(toggle(tester).value, isFalse);
      expect(toggle(tester).onChanged, isNotNull);
      expect(server.written, ['put series/1']);
      expect(
        (sentBody(server.writes.single)! as Map<String, Object?>)['monitored'],
        isFalse,
      );
    });

    for (final number in [0, 1]) {
      testWidgets('season $number is written as part of its series, which is '
          'read again with the episodes', (tester) async {
        await open(tester, _season(number));
        final was = toggle(tester).value;
        final episodes = server.count('get episode');

        await tester.tap(find.byType(SwitchListTile));
        await tester.pumpAndSettle();

        final sent = sentBody(server.writes.single)! as Map<String, Object?>;
        expect(
          {
            for (final season in sent['seasons']! as List<Object?>)
              if (season case {
                'seasonNumber': final int n,
                'monitored': final bool monitored,
              })
                n: monitored,
          }[number],
          !was,
        );
        expect(server.count('get episode'), episodes + 1);
        expect(find.textContaining('The season is'), findsOneWidget);
      });
    }

    testWidgets('an episode is written on its own, and the season beneath is '
        'read again', (tester) async {
      await open(tester, _season(1));
      await screens.open(tester, _episode);
      final lists = server.count('get series/1');
      server.episode13['monitored'] = false;

      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();

      expect(server.written, ['put episode/monitor']);
      expect(sentBody(server.writes.single), {
        'episodeIds': [13],
        'monitored': false,
      });
      expect(find.text('The episode is no longer monitored'), findsOneWidget);
      expect(toggle(tester).value, isFalse);
      // The series and its episodes of the season screen.
      expect(server.count('get series/1'), greaterThan(lists));
    });

    testWidgets('the screen beneath is read again although the episode was '
        'left before the answer', (tester) async {
      final answered = server.held['put episode/monitor'] = Completer<void>();
      await open(tester, _season(1));
      await screens.open(tester, _episode);
      await tester.tap(find.byType(SwitchListTile));
      await step(tester);
      await screens.back(tester);
      final episodes = server.count('get episode');

      answered.complete();
      await tester.pumpAndSettle();

      expect(server.count('get episode'), greaterThan(episodes));
    });

    for (final (name, route) in [('series', _series), ('season', _season(1))]) {
      testWidgets('an episode screen beneath is read again after a change of '
          'the $name above it', (tester) async {
        await open(tester, _episode);
        await screens.open(tester, _series);
        if (route != _series) await screens.open(tester, route);
        final reads = server.count('get episode');
        server.episode13['monitored'] = false;

        await tester.tap(find.byType(SwitchListTile));
        await tester.pumpAndSettle();
        expect(server.count('get episode'), greaterThan(reads));
        await screens.back(tester);
        if (route != _series) await screens.back(tester);

        expect(find.text('Season 1, episode 1'), findsNWidgets(2));
        expect(toggle(tester).value, isFalse);
      });
    }

    testWidgets('returns when the server rejects it, and says why', (
      tester,
    ) async {
      server.writeAnswer = FakeSonarr.body(
        '[{"errorMessage": "Path is in use"}]',
        status: 400,
        write: true,
      );
      await open(tester, _series);

      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();

      expect(toggle(tester).value, isTrue);
      expect(toggle(tester).onChanged, isNotNull);
      expect(find.textContaining('Path is in use'), findsOneWidget);
      expect(server.written, ['put series/1']);
    });

    testWidgets(
      'with an unknown outcome, reads again and does not send again',
      (tester) async {
        server.writeAnswer = const Err(HttpError(OutcomeUnknown()));
        await open(tester, _episode);
        final reads = server.count('get episode');

        await tester.tap(find.byType(SwitchListTile));
        await tester.pumpAndSettle();

        expect(find.textContaining('may or may not'), findsOneWidget);
        expect(server.written, ['put episode/monitor']);
        expect(server.count('get episode'), reads + 1);
        expect(toggle(tester).value, isTrue);
      },
    );
  });

  testWidgets('a season says why nothing can be changed when only its series '
      'cannot be read', (tester) async {
    await open(tester, _season(1));
    await screens.back(tester);
    // The episodes are answered after the series has failed.
    final episodes = server.held['get episode'] = Completer<void>();
    server.seriesFails = true;
    await screens.open(tester, _season(1), settle: false);
    await step(tester);
    server.seriesFails = false;
    episodes.complete();
    await tester.pumpAndSettle();

    expect(find.textContaining('Saved data from'), findsOneWidget);
    expect(find.textContaining('error 500'), findsOneWidget);
    expect(toggle(tester).onChanged, isNull);
    expect(button(tester, 'Search automatically').onPressed, isNull);
    expect(button(tester, 'Interactive search').onPressed, isNull);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Saved data from'), findsNothing);
    expect(toggle(tester).onChanged, isNotNull);
  });

  group('server tasks', () {
    for (final (name, route, fixture, body) in [
      (
        'a series',
        _series,
        'manage_command_search_series',
        {'name': 'SeriesSearch', 'seriesId': 1},
      ),
      (
        'season 0',
        _season(0),
        'manage_command_search_season',
        {'name': 'SeasonSearch', 'seriesId': 1, 'seasonNumber': 0},
      ),
      (
        'an episode',
        _episode,
        'manage_command_search_episode',
        {
          'name': 'EpisodeSearch',
          'episodeIds': [13],
        },
      ),
    ]) {
      testWidgets('searches $name and follows the task to its end', (
        tester,
      ) async {
        command(fixture, 'started');
        await open(tester, route);

        await tester.tap(find.text('Search automatically'));
        await step(tester);

        expect(posted(), body);
        expect(find.text('Search started'), findsOneWidget);
        expect(find.text('Automatic search: waiting to start'), findsOneWidget);
        expect(button(tester, 'Search automatically').onPressed, isNull);

        await step(tester, const Duration(seconds: 3));
        expect(find.text('Automatic search: running'), findsOneWidget);

        command(fixture, 'completed', result: 'successful');
        await step(tester, const Duration(seconds: 3));
        await tester.pumpAndSettle();
        expect(find.text('Automatic search: finished'), findsOneWidget);
        expect(button(tester, 'Search automatically').onPressed, isNotNull);
        expect(server.written, ['post command']);
      });
    }

    for (final (entry, fixture, body, task) in [
      (
        'Refresh metadata',
        'manage_command_refresh',
        {
          'name': 'RefreshSeries',
          'seriesIds': [1],
        },
        'Metadata refresh',
      ),
      (
        'Rescan files',
        'manage_command_rescan',
        {'name': 'RescanSeries', 'seriesId': 1},
        'File rescan',
      ),
    ]) {
      testWidgets('$entry of a series starts its task', (tester) async {
        command(fixture, 'failed');
        await open(tester, _series);

        await choose(tester, entry);

        expect(posted(), body);
        expect(find.text('$task started'), findsOneWidget);
        await step(tester, const Duration(seconds: 3));
        await tester.pumpAndSettle();
        expect(find.text('$task: failed'), findsOneWidget);
      });
    }

    testWidgets('a refused task says why and can be started again', (
      tester,
    ) async {
      server.writeAnswer = FakeSonarr.body('', status: 500, write: true);
      await open(tester, _season(1));

      await tester.tap(find.text('Search automatically'));
      await tester.pumpAndSettle();

      expect(find.textContaining('error 500'), findsOneWidget);
      expect(find.textContaining('Automatic search:'), findsNothing);
      expect(button(tester, 'Search automatically').onPressed, isNotNull);
      expect(server.written, ['post command']);
    });

    testWidgets('is not read while another page covers the screen', (
      tester,
    ) async {
      command('manage_command_search_series', 'started');
      await open(tester, _series);
      await tester.tap(find.text('Search automatically'));
      await step(tester);

      await screens.show(tester, _season(1).location);
      await step(tester);
      await tester.pump(const Duration(minutes: 1));
      expect(server.count('get command/7'), 0);

      // The progress bar of the screen beneath never settles.
      Navigator.of(tester.element(find.byType(Scaffold).last)).pop();
      await step(tester);
      await step(tester, const Duration(seconds: 3));
      expect(server.count('get command/7'), 1);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('is still followed once its controls are scrolled away', (
      tester,
    ) async {
      command('manage_command_search_series', 'started');
      size(tester, const Size(400, 500));
      await screens.open(tester, _series);
      await tester.ensureVisible(find.text('Search automatically'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Search automatically'));
      await step(tester);

      final scrollable = page();
      await tester.drag(scrollable, const Offset(0, -3000));
      await step(tester);
      expect(find.byType(SwitchListTile), findsNothing);
      await step(tester, const Duration(seconds: 3));
      expect(server.count('get command/7'), 1);

      await tester.drag(scrollable, const Offset(0, 3000));
      await step(tester);
      await tester.scrollUntilVisible(
        find.text('Automatic search: running'),
        100,
        scrollable: scrollable,
      );
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('what each level offers', () {
    testWidgets('a series has no interactive search', (tester) async {
      await open(tester, _series);

      expect(find.text('Search automatically'), findsOneWidget);
      expect(find.text('Interactive search'), findsNothing);
      expect(find.byTooltip('More actions'), findsOneWidget);
    });

    for (final (name, route) in [
      ('season', _season(1)),
      ('episode', _episode),
    ]) {
      testWidgets('the $name screen has no menu', (tester) async {
        await open(tester, route);

        expect(find.text('Interactive search'), findsOneWidget);
        expect(find.byTooltip('More actions'), findsNothing);
      });
    }
  });

  group('flows of the app', () {
    for (final (name, route, target) in [
      ('season 0', _season(0), MediaTarget(seriesRef(1), seasonNumber: 0)),
      ('season 2', _season(2), MediaTarget(seriesRef(1), seasonNumber: 2)),
      ('an episode', _episode, MediaTarget(episodeRef(13))),
    ]) {
      testWidgets('interactive search of $name asks for just that, and reads '
          'again when closed', (tester) async {
        await open(tester, route);

        await tester.tap(find.text('Interactive search'));
        await step(tester);

        expect(screens.navigator.opened, [('releases', target)]);
        final requests = server.requests.length;
        screens.navigator.closed.complete();
        await tester.pumpAndSettle();
        expect(server.requests.length, greaterThan(requests));
        expect(server.written, isEmpty);
      });
    }

    for (final (entry, flow) in [
      ('Edit series', 'edit'),
      ('Delete series', 'delete'),
    ]) {
      testWidgets('$entry opens its flow and reads the series when it closes', (
        tester,
      ) async {
        await open(tester, _series);

        await choose(tester, entry);

        expect(screens.navigator.opened, [(flow, seriesRef(1))]);
        final reads = server.count('get series/1');
        final episodes = server.count('get episode');
        screens.navigator.closed.complete();
        await tester.pumpAndSettle();
        // One for the series, and one with its episodes.
        expect(server.count('get series/1'), reads + 2);
        expect(server.count('get episode'), episodes + 1);
        expect(server.written, isEmpty);
      });
    }

    testWidgets('a series deleted by the flow is shown as gone', (
      tester,
    ) async {
      await open(tester, _series);
      await choose(tester, 'Delete series');

      server.overrides['series/1'] = FakeSonarr.body('', status: 404);
      screens.navigator.closed.complete();
      await tester.pumpAndSettle();

      expect(
        find.text('This item no longer exists on the server.'),
        findsOneWidget,
      );
      expect(find.byTooltip('More actions'), findsNothing);
    });
  });

  group('deleting a file', () {
    const delete = 'delete episodefile/1';

    Future<void> ask(WidgetTester tester) async {
      await open(tester, _episode);
      await tester.tap(find.text('Delete file'));
      await tester.pumpAndSettle();
    }

    Future<void> confirm(WidgetTester tester) async {
      await tester.tap(find.widgetWithText(FilledButton, 'Delete file'));
      await tester.pumpAndSettle();
    }

    void remove() {
      server.episode13
        ..remove('episodeFile')
        ..['hasFile'] = false
        ..['episodeFileId'] = 0;
    }

    testWidgets('asks first, naming the file; cancelling sends nothing', (
      tester,
    ) async {
      await ask(tester);

      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(_path),
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('this file of redacted-1, Season 1, episode 1.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(server.written, isEmpty);
    });

    testWidgets('deletes once, and reads the episode again', (tester) async {
      await ask(tester);
      remove();

      await confirm(tester);

      expect(server.written, [delete]);
      expect(find.text('The file was deleted'), findsOneWidget);
      expect(find.text('No file'), findsOneWidget);
    });

    testWidgets('with an unknown outcome, says so, looks and does not send '
        'again', (tester) async {
      server.deleteAnswer = const Err(HttpError(OutcomeUnknown()));
      await ask(tester);
      final reads = server.count('get episode');

      await confirm(tester);

      expect(find.textContaining('may or may not'), findsOneWidget);
      expect(find.text('The file was deleted'), findsNothing);
      expect(server.written, [delete]);
      expect(server.count('get episode'), reads + 1);
    });

    testWidgets('a refusal says why and leaves the file', (tester) async {
      server.deleteAnswer = FakeSonarr.body('', status: 403, write: true);
      await ask(tester);

      await confirm(tester);

      expect(find.textContaining('does not allow'), findsOneWidget);
      expect(find.text(_path), findsOneWidget);
      expect(button(tester, 'Delete file').onPressed, isNotNull);
      expect(server.written, [delete]);
    });

    testWidgets('deletes nothing when the file changed meanwhile', (
      tester,
    ) async {
      await ask(tester);
      server.episode13['episodeFile'] = {
        ...server.episode13['episodeFile']! as Map<String, Object?>,
        'id': 99,
        'path': '/redacted/better.mkv',
      };
      // The screen behind the dialog is read again.
      await tester
          .widget<RefreshIndicator>(
            find.byType(RefreshIndicator, skipOffstage: false),
          )
          .onRefresh();
      await tester.pumpAndSettle();

      await confirm(tester);

      expect(server.written, isEmpty);
      expect(find.textContaining('Nothing was deleted'), findsOneWidget);
    });
  });

  for (final (name, route) in [
    ('series', _series),
    ('season', _season(1)),
    ('episode', _episode),
  ]) {
    testWidgets('with saved data only, nothing on the $name screen can be '
        'changed', (tester) async {
      await open(tester, route);
      await screens.back(tester);
      server.goOffline();

      await screens.open(tester, route);

      expect(toggle(tester).onChanged, isNull);
      for (final label in [
        'Search automatically',
        if (name != 'series') 'Interactive search',
        if (name == 'episode') 'Delete file',
      ]) {
        expect(button(tester, label).onPressed, isNull, reason: label);
      }
      if (name == 'series') {
        await tester.tap(find.byTooltip('More actions'));
        await tester.pumpAndSettle();
        expect(find.text('Edit series'), findsNothing);
      }
    });
  }

  for (final (name, theme) in [
    ('light', ArrTheme.light()),
    ('dark', ArrTheme.dark()),
  ]) {
    testWidgets('the actions fit a small phone at 200% text, $name', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      command(
        'manage_command_search_episode',
        'completed',
        result: 'successful',
      );
      screens.theme = theme;
      size(tester, const Size(320, 640));
      await screens.open(tester, _episode, textScale: 2);

      Future<void> meetsGuidelines() async {
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        expect(tester.takeException(), isNull);
      }

      Future<void> show(String text) async {
        await tester.scrollUntilVisible(
          find.text(text),
          200,
          scrollable: page(),
        );
        await tester.ensureVisible(find.text(text));
        await step(tester);
      }

      await show('Search automatically');
      await tester.tap(find.text('Search automatically'));
      await step(tester);
      await step(tester, const Duration(seconds: 3));
      await tester.pumpAndSettle();
      await show('Automatic search: finished');
      await meetsGuidelines();

      await show('Delete file');
      await meetsGuidelines();
      // The message of the search would cover the button.
      ScaffoldMessenger.of(tester.element(find.text('Delete file')))
          .removeCurrentSnackBar();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete file'));
      await tester.pumpAndSettle();
      await meetsGuidelines();
      semantics.dispose();
    });
  }
}
