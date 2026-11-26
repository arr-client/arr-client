// What the user can do on the movie screen (spec story 5), over the module's
// own adapters and a Radarr that answers by method. The allow-list refuses any
// write Radarr is not meant to get.

import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:radarr/radarr_module.dart';
import 'package:ui/ui.dart';

import '../contract/library_support.dart';
import '../contract/manage_support.dart';

const _path = '/media/movies/voyage/voyage.mkv';

/// The library's reads, and writes by method and path as given in [routes]. A
/// request in [held] is answered once its completer is.
class _Radarr extends FakeRadarr {
  final routes = <String, Result<ServiceResponse, HttpError>>{};
  final held = <String, Completer<void>>{};

  @override
  Future<Result<ServiceResponse, HttpError>> send(
    ServiceRequest request,
  ) async {
    final key = asked(request);
    final answer = await super.send(request);
    await held[key]?.future;
    return down ??
        routes[key] ??
        (request.method == HttpMethod.get
            ? answer
            : failedAnswer(const NotFound(), status: 404));
  }

  List<String> get writes => [
    for (final request in requests)
      if (request.method != HttpMethod.get) asked(request),
  ];

  int count(String key) =>
      requests.where((request) => asked(request) == key).length;
}

/// Notes the flows asked for; each stays open until [closed] completes.
class _Navigator extends Fake implements AppNavigator {
  final opened = <(String, Object)>[];
  // Made when first used, so that it completes in the test's own zone.
  late final closed = Completer<void>();

  Future<void> _open(String flow, Object of) {
    opened.add((flow, of));
    return closed.future;
  }

  @override
  Future<void> openReleases(MediaTarget target) => _open('releases', target);

  @override
  Future<void> openEdit(ItemRef ref) => _open('edit', ref);

  @override
  Future<void> openDelete(ItemRef ref) => _open('delete', ref);
}

class _NoArtwork implements ArtworkLoader {
  @override
  ImageProvider<Object>? image(MediaImage image) => null;
}

Map<String, Object?> _movie({bool monitored = true}) => {
  ...fixture('movie_1')! as Map<String, Object?>,
  'title': 'The Long Voyage Home',
  'monitored': monitored,
};

Map<String, Object?> _file() => {
  ...records(fixture('moviefile')).singleWhere((file) => file['movieId'] == 1),
  'path': _path,
};

Map<String, Object?> _command(String status, {String result = 'unknown'}) => {
  ...manageObject('manage_command_search'),
  'status': status,
  'result': result,
};

_Radarr _server() => _Radarr()
  ..answers['api/v3/movie/1'] = jsonAnswer(_movie())
  ..answers['api/v3/moviefile'] = jsonAnswer([_file()])
  ..routes['PUT movie/1'] = replyJson(_movie(), status: 202)
  ..routes['POST command'] = replyJson(_command('queued'), status: 201)
  ..routes['DELETE moviefile/${_file()['id']}'] = reply('');

void main() {
  late _Radarr server;
  late Harness harness;
  late _Navigator navigator;

  setUp(() {
    server = _server();
    navigator = _Navigator();
  });

  Future<void> pump(
    WidgetTester tester, {
    Size size = const Size(400, 4000),
    double textScale = 1,
    ThemeData? theme,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final context = harness.context;
    final instance = InstanceContext(
      instance: context.instance,
      http: context.http,
      artwork: _NoArtwork(),
      navigator: navigator,
      cache: context.cache,
      logger: context.logger,
    );
    final screen = RadarrModule().routes().single;
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        child: MaterialApp(
          theme: theme ?? ArrTheme.light(),
          localizationsDelegates: const [
            RadarrLocalizations.delegate,
            ...uiLocalizationsDelegates,
          ],
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Builder(
            builder: (context) =>
                screen.builder(context, instance, {'movieId': '1'}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester) async {
    harness = Harness(server);
    await pump(tester);
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

  SwitchListTile toggle(WidgetTester tester) =>
      tester.widget(find.byType(SwitchListTile));

  ButtonStyleButton button(WidgetTester tester, String label) => tester.widget(
    find.ancestor(
      of: find.text(label),
      matching: find.bySubtype<ButtonStyleButton>(),
    ),
  );

  group('monitoring', () {
    testWidgets('shows the new value at once, and success only once the '
        'server has accepted it', (tester) async {
      final answered = server.held['PUT movie/1'] = Completer<void>();
      await open(tester);

      await tester.tap(find.byType(SwitchListTile));
      await step(tester);

      expect(toggle(tester).value, isFalse);
      expect(toggle(tester).onChanged, isNull);
      expect(find.text('The movie is no longer monitored'), findsNothing);

      server.answers['api/v3/movie/1'] = jsonAnswer(_movie(monitored: false));
      answered.complete();
      await tester.pumpAndSettle();

      expect(find.text('The movie is no longer monitored'), findsOneWidget);
      expect(toggle(tester).value, isFalse);
      expect(toggle(tester).onChanged, isNotNull);
      expect(server.writes, ['PUT movie/1']);
      final sent = server.requests.singleWhere(
        (request) => request.method == HttpMethod.put,
      );
      expect(sentBody(sent), {..._movie(), 'monitored': false});
    });

    testWidgets('returns when the server rejects it, and says why', (
      tester,
    ) async {
      server.routes['PUT movie/1'] = failedAnswer(
        const Validation(['Path is in use']),
        status: 400,
      );
      await open(tester);

      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();

      expect(toggle(tester).value, isTrue);
      expect(toggle(tester).onChanged, isNotNull);
      expect(find.textContaining('Path is in use'), findsOneWidget);
      expect(server.writes, ['PUT movie/1']);
    });

    testWidgets('with an unknown outcome, reads the movie and does not send '
        'again', (tester) async {
      server.routes['PUT movie/1'] = failedAnswer(const OutcomeUnknown());
      await open(tester);
      final reads = server.count('GET movie/1');

      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();

      expect(find.textContaining('may or may not'), findsOneWidget);
      expect(server.writes, ['PUT movie/1']);
      // One read to build the write, and one for the real state.
      expect(server.count('GET movie/1'), reads + 2);
      expect(toggle(tester).value, isTrue);
    });

    testWidgets('keeps an accepted value when the movie cannot be read after', (
      tester,
    ) async {
      final answered = server.held['PUT movie/1'] = Completer<void>();
      await open(tester);
      await tester.tap(find.byType(SwitchListTile));
      await step(tester);

      // The write succeeds; the read after it does not.
      server.routes['GET movie/1'] = failedAnswer(const Unreachable());
      answered.complete();
      await tester.pumpAndSettle();

      expect(find.textContaining('Saved data'), findsOneWidget);
      expect(toggle(tester).value, isFalse);
      expect(toggle(tester).onChanged, isNull);

      // A later read has the last word.
      server.routes.remove('GET movie/1');
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(toggle(tester).value, isTrue);
    });
  });

  group('server tasks', () {
    testWidgets('searches, follows the task and stops once it has ended', (
      tester,
    ) async {
      await open(tester);

      await tester.tap(find.text('Search automatically'));
      await step(tester);

      expect(find.text('Search started'), findsOneWidget);
      expect(find.text('Automatic search: waiting to start'), findsOneWidget);
      expect(button(tester, 'Search automatically').onPressed, isNull);
      final sent = server.requests.singleWhere(
        (request) => request.method == HttpMethod.post,
      );
      expect(sentBody(sent), {
        'name': 'MoviesSearch',
        'movieIds': [1],
      });

      server.routes['GET command/9'] = replyJson(_command('started'));
      await step(tester, const Duration(seconds: 3));
      expect(find.text('Automatic search: running'), findsOneWidget);

      final reads = server.count('GET movie/1');
      server.routes['GET command/9'] = replyJson(
        _command('completed', result: 'successful'),
      );
      await step(tester, const Duration(seconds: 3));
      await tester.pumpAndSettle();

      expect(find.text('Automatic search: finished'), findsOneWidget);
      expect(button(tester, 'Search automatically').onPressed, isNotNull);
      expect(server.count('GET movie/1'), reads + 1);
      await tester.pump(const Duration(minutes: 1));
      expect(server.count('GET command/9'), 2);
      expect(server.writes, ['POST command']);
    });

    for (final (entry, body, task, message) in [
      (
        'Refresh metadata',
        {
          'name': 'RefreshMovie',
          'movieIds': [1],
        },
        'Metadata refresh',
        'Metadata refresh started',
      ),
      (
        'Rescan files',
        {'name': 'RescanMovie', 'movieId': 1},
        'File rescan',
        'File rescan started',
      ),
    ]) {
      testWidgets('$entry starts its task and shows how it ends', (
        tester,
      ) async {
        server.routes['GET command/9'] = replyJson(_command('failed'));
        await open(tester);

        await choose(tester, entry);

        expect(find.text(message), findsOneWidget);
        final sent = server.requests.singleWhere(
          (request) => request.method == HttpMethod.post,
        );
        expect(sentBody(sent), body);

        await step(tester, const Duration(seconds: 3));
        await tester.pumpAndSettle();
        expect(find.text('$task: failed'), findsOneWidget);
      });
    }

    testWidgets('a refused task says why and can be started again', (
      tester,
    ) async {
      server.routes['POST command'] = failedAnswer(
        const ServerError(statusCode: 500),
        status: 500,
      );
      await open(tester);

      await tester.tap(find.text('Search automatically'));
      await tester.pumpAndSettle();

      expect(find.textContaining('error 500'), findsOneWidget);
      expect(find.textContaining('Automatic search:'), findsNothing);
      expect(find.text('Search started'), findsNothing);
      expect(button(tester, 'Search automatically').onPressed, isNotNull);
      expect(server.writes, ['POST command']);
    });

    testWidgets('gives up on a task it cannot read, after three tries', (
      tester,
    ) async {
      server.routes['GET command/9'] = failedAnswer(const Unreachable());
      await open(tester);
      await tester.tap(find.text('Search automatically'));
      await step(tester);

      for (var i = 0; i < 3; i++) {
        await step(tester, const Duration(seconds: 3));
      }
      await tester.pumpAndSettle();

      expect(
        find.text('Automatic search: progress could not be read'),
        findsOneWidget,
      );
      expect(find.textContaining('did not answer'), findsOneWidget);
      await tester.pump(const Duration(minutes: 1));
      expect(server.count('GET command/9'), 3);
      expect(button(tester, 'Search automatically').onPressed, isNotNull);
    });

    testWidgets('does not read a task while the app is out of sight', (
      tester,
    ) async {
      server.routes['GET command/9'] = replyJson(_command('started'));
      await open(tester);
      await tester.tap(find.text('Search automatically'));
      await step(tester);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(minutes: 1));
      expect(server.count('GET command/9'), 0);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await step(tester, const Duration(seconds: 3));
      expect(server.count('GET command/9'), 1);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('stops following a task when the screen is left', (
      tester,
    ) async {
      server.routes['GET command/9'] = replyJson(_command('started'));
      await open(tester);
      await tester.tap(find.text('Search automatically'));
      await step(tester);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(minutes: 1));

      expect(server.count('GET command/9'), 0);
    });
  });

  group('flows of the app', () {
    for (final (name, flow, argument) in [
      ('Interactive search', 'releases', MediaTarget(movieRef(1))),
      ('Edit movie', 'edit', movieRef(1)),
      ('Delete movie', 'delete', movieRef(1)),
    ]) {
      testWidgets('$name opens it and reads the movie when it closes', (
        tester,
      ) async {
        await open(tester);

        if (flow == 'releases') {
          await tester.tap(find.text(name));
          await step(tester);
        } else {
          await choose(tester, name);
        }

        expect(navigator.opened, [(flow, argument)]);
        final reads = server.count('GET movie/1');
        navigator.closed.complete();
        await tester.pumpAndSettle();
        expect(server.count('GET movie/1'), reads + 1);
        expect(server.writes, isEmpty);
      });
    }

    testWidgets('a movie deleted by the flow is shown as gone', (tester) async {
      await open(tester);
      await choose(tester, 'Delete movie');

      server.answers['api/v3/movie/1'] = failedAnswer(
        const NotFound(),
        status: 404,
      );
      navigator.closed.complete();
      await tester.pumpAndSettle();

      expect(
        find.text('This item no longer exists on the server.'),
        findsOneWidget,
      );
      expect(find.byTooltip('More actions'), findsNothing);
    });
  });

  group('deleting the file', () {
    final delete = 'DELETE moviefile/${_file()['id']}';

    Future<void> ask(WidgetTester tester) async {
      await tester.tap(find.text('Delete file'));
      await tester.pumpAndSettle();
    }

    Future<void> confirm(WidgetTester tester) async {
      await tester.tap(find.widgetWithText(FilledButton, 'Delete file'));
      await tester.pumpAndSettle();
    }

    testWidgets('asks first, naming the file; cancelling sends nothing', (
      tester,
    ) async {
      await open(tester);

      await ask(tester);

      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(_path),
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('this file of The Long Voyage Home'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(server.writes, isEmpty);
    });

    testWidgets('deletes once, and reads the files again', (tester) async {
      await open(tester);
      await ask(tester);
      server.answers['api/v3/moviefile'] = jsonAnswer(<Object>[]);
      server.answers['api/v3/movie/1'] = jsonAnswer({
        ..._movie(),
        'movieFile': null,
        'hasFile': false,
      });

      await confirm(tester);

      expect(server.writes, [delete]);
      expect(find.text('The file was deleted'), findsOneWidget);
      expect(find.text('No file'), findsOneWidget);
    });

    testWidgets('with an unknown outcome, says so, looks and does not send '
        'again', (tester) async {
      server.routes[delete] = failedAnswer(const OutcomeUnknown());
      await open(tester);
      final reads = server.count('GET moviefile');
      await ask(tester);

      await confirm(tester);

      expect(find.textContaining('may or may not'), findsOneWidget);
      expect(find.text('The file was deleted'), findsNothing);
      expect(server.writes, [delete]);
      expect(server.count('GET moviefile'), reads + 1);
    });

    testWidgets('a refusal says why and leaves the file', (tester) async {
      server.routes[delete] = failedAnswer(const Forbidden(), status: 403);
      await open(tester);
      await ask(tester);

      await confirm(tester);

      expect(find.textContaining('does not allow'), findsOneWidget);
      expect(find.text(_path), findsOneWidget);
      expect(button(tester, 'Delete file').onPressed, isNotNull);
      expect(server.writes, [delete]);
    });

    testWidgets('deletes nothing when the file changed meanwhile', (
      tester,
    ) async {
      await open(tester);
      await ask(tester);
      server.answers['api/v3/moviefile'] = jsonAnswer([
        {..._file(), 'id': 99, 'path': '/media/movies/voyage/better.mkv'},
      ]);
      // The screen behind the dialog is read again.
      final refresh = tester.widget<RefreshIndicator>(
        find.byType(RefreshIndicator, skipOffstage: false),
      );
      await refresh.onRefresh();
      await tester.pumpAndSettle();

      await confirm(tester);

      expect(server.writes, isEmpty);
      expect(find.textContaining('Nothing was deleted'), findsOneWidget);
    });

    testWidgets('is not offered for a file that was not listed', (
      tester,
    ) async {
      server.answers['api/v3/moviefile'] = failedAnswer(
        const ServerError(statusCode: 500),
        status: 500,
      );

      await open(tester);

      expect(button(tester, 'Delete file').onPressed, isNull);
    });
  });

  testWidgets('with saved data only, nothing can be changed', (tester) async {
    harness = Harness(server);
    await succeed(harness.library.item(movieRef(1)));
    server.down = failedAnswer(const Unreachable());

    await pump(tester);

    expect(toggle(tester).onChanged, isNull);
    for (final label in [
      'Search automatically',
      'Interactive search',
      'Delete file',
    ]) {
      expect(button(tester, label).onPressed, isNull, reason: label);
    }
    await tester.tap(find.byTooltip('More actions'));
    await tester.pumpAndSettle();
    expect(find.text('Edit movie'), findsNothing);
  });

  for (final (name, theme) in [
    ('light', ArrTheme.light()),
    ('dark', ArrTheme.dark()),
  ]) {
    testWidgets('the actions fit a small phone at 200% text, $name', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      server.routes['GET command/9'] = replyJson(
        _command('completed', result: 'successful'),
      );
      harness = Harness(server);
      await pump(
        tester,
        size: const Size(320, 640),
        textScale: 2,
        theme: theme,
      );
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
          scrollable: find.byType(Scrollable).first,
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
      ScaffoldMessenger.of(tester.element(find.byType(ListView)))
          .removeCurrentSnackBar();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete file'));
      await tester.pumpAndSettle();
      await meetsGuidelines();
      semantics.dispose();
    });
  }
}
