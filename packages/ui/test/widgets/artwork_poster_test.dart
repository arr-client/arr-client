// The poster follows the preference for artwork of public hosts.

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

/// Has every picture, while allowed.
class _Pictures implements ArtworkLoader {
  var allowed = true;

  @override
  ImageProvider<Object>? image(MediaImage image) =>
      allowed ? const AssetImage('picture') : null;
}

void main() {
  testWidgets('drops its picture when it may no longer be shown', (
    tester,
  ) async {
    final loader = _Pictures();
    // The same widget throughout: only the scope tells it to ask again.
    final poster = ArtworkPoster(
      kind: MediaKind.movie,
      images: const [MediaImage(type: MediaImageType.poster)],
      artwork: loader,
      width: 100,
    );
    Future<void> pump({required bool allowed}) {
      loader.allowed = allowed;
      return tester.pumpWidget(
        MaterialApp(
          home: ThirdPartyArtworkScope(allowed: allowed, child: poster),
        ),
      );
    }

    await pump(allowed: true);
    expect(find.byType(Image), findsOneWidget);

    await pump(allowed: false);
    expect(find.byType(Image), findsNothing);
    expect(find.byIcon(Icons.movie_outlined), findsOneWidget);

    await pump(allowed: true);
    expect(find.byType(Image), findsOneWidget);
    // The asset does not exist, which the poster takes as any other failure.
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
