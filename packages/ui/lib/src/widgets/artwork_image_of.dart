import 'package:core/core.dart';
import 'package:flutter/widgets.dart';

/// Tells the widgets below whether artwork of public hosts may be shown, so
/// that those on screen, or kept behind it, ask their loader again when that
/// changes. The app puts one above its navigator.
class ThirdPartyArtworkScope extends InheritedWidget {
  /// Creates a [ThirdPartyArtworkScope].
  const ThirdPartyArtworkScope({
    required this.allowed,
    required super.child,
    super.key,
  });

  /// `Preferences.loadThirdPartyArtwork`.
  final bool allowed;

  @override
  bool updateShouldNotify(ThirdPartyArtworkScope oldWidget) =>
      allowed != oldWidget.allowed;
}

/// What [loader] gives for [image]. A widget gets its artwork through this
/// while it builds, not from the loader directly: it is then built again when
/// the [ThirdPartyArtworkScope] changes, and drops a picture that may no longer
/// be shown.
ImageProvider<Object>? artworkImageOf(
  BuildContext context,
  ArtworkLoader loader,
  MediaImage image,
) {
  context.dependOnInheritedWidgetOfExactType<ThirdPartyArtworkScope>();
  return loader.image(image);
}
