// The module's screens over the recorded server, routed as the app routes them.

import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lidarr/lidarr_module.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../contract/support.dart';

class _NoArtwork implements ArtworkLoader {
  @override
  ImageProvider<Object>? image(MediaImage image) => null;
}

/// Records what the screens ask the app to open.
class RecordingNavigator extends Fake implements AppNavigator {
  final histories = <ItemRef>[];

  /// The other flows asked for; each stays open until [closed] completes.
  final opened = <(String, Object)>[];

  // Made when first used, so that it completes in the test's own zone.
  late final closed = Completer<void>();

  @override
  Future<void> openHistory(ItemRef ref) async => histories.add(ref);

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

/// The app around the module's screens.
class Screens {
  Screens({FakeLidarr? server, ArtworkLoader? artwork})
    : navigator = RecordingNavigator() {
    harness = Harness(
      server: server,
      artwork: artwork ?? _NoArtwork(),
      navigator: navigator,
    );
  }

  final RecordingNavigator navigator;
  late final Harness harness;

  /// The slots the screens have declared.
  final slots = <DetailSlot>{};

  final _module = LidarrModule();
  GoRouter? _router;

  /// The theme of the app, set before the first screen is shown.
  ThemeData theme = ArrTheme.light();

  FakeLidarr get server => harness.server;

  /// What the app's preference for artwork of public hosts says.
  final artworkAllowed = ValueNotifier(true);

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
            theme: theme,
            localizationsDelegates: const [
              LidarrLocalizations.delegate,
              ...uiLocalizationsDelegates,
            ],
            supportedLocales: LidarrLocalizations.supportedLocales,
            routerConfig: router,
            builder: (context, child) => ValueListenableBuilder(
              valueListenable: artworkAllowed,
              builder: (context, allowed, _) => ThirdPartyArtworkScope(
                allowed: allowed,
                child: MediaQuery(
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
