// The module's screens over the recorded server, routed as the app routes them.

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sonarr/sonarr_module.dart';
import 'package:ui/ui.dart';

import '../contract/support.dart';

class _NoArtwork implements ArtworkLoader {
  @override
  ImageProvider<Object>? image(MediaImage image) => null;
}

/// Records what the screens ask the app to open.
class RecordingNavigator extends Fake implements AppNavigator {
  final histories = <ItemRef>[];

  @override
  Future<void> openHistory(ItemRef ref) async => histories.add(ref);
}

/// The app around the module's screens.
class Screens {
  Screens({FakeSonarr? server}) : navigator = RecordingNavigator() {
    harness = Harness(
      server: server,
      artwork: _NoArtwork(),
      navigator: navigator,
    );
  }

  final RecordingNavigator navigator;
  late final Harness harness;

  /// The slots the screens have declared.
  final slots = <DetailSlot>{};

  final _module = SonarrModule();
  GoRouter? _router;

  FakeSonarr get server => harness.server;

  /// Shows the screen of [route], above an empty first page.
  Future<void> open(
    WidgetTester tester,
    ModuleRoute route, {
    double textScale = 1,
    bool settle = true,
  }) async {
    await show(tester, route.location, textScale: textScale);
    if (settle) await tester.pumpAndSettle();
  }

  Future<void> show(
    WidgetTester tester,
    String location, {
    double textScale = 1,
  }) async {
    var router = _router;
    if (router == null) {
      router = _router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (context, state) => const Scaffold()),
          for (final screen in _module.routes())
            GoRoute(
              path: '/instances/:instanceId/${screen.path}',
              builder: (context, state) => screen.builder(
                context,
                harness.context,
                {...state.pathParameters, ...state.uri.queryParameters},
              ),
            ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          child: MaterialApp.router(
            theme: ArrTheme.light(),
            localizationsDelegates: const [
              SonarrLocalizations.delegate,
              ...uiLocalizationsDelegates,
            ],
            supportedLocales: SonarrLocalizations.supportedLocales,
            routerConfig: router,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(textScale)),
              child: DetailSlotScope(
                builder: (context, slot) {
                  slots.add(slot);
                  return const SizedBox.shrink();
                },
                child: child!,
              ),
            ),
          ),
        ),
      );
    }
    router.push<void>(location).ignore();
    await tester.pump();
  }

  /// Leaves the screen shown.
  Future<void> back(WidgetTester tester) async {
    _router!.pop();
    await tester.pumpAndSettle();
  }
}

/// Brings [finder] into view on the screen in front.
Future<void> scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.pumpAndSettle();
}
