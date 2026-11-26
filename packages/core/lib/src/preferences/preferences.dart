import 'app_lock.dart';
import 'app_theme_mode.dart';

/// The preferences that apply to the whole app. The defaults are those of a new
/// installation.
final class Preferences {
  /// Creates a [Preferences].
  const Preferences({
    this.activeProfileId,
    this.themeMode = AppThemeMode.system,
    this.trueBlack = false,
    this.dynamicColor = true,
    this.loadThirdPartyArtwork = true,
    this.appLock = const AppLock(),
  });

  /// The profile in use. Null until one is chosen, and after it is deleted.
  final String? activeProfileId;

  /// Light, dark or the device's setting.
  final AppThemeMode themeMode;

  /// Whether dark surfaces are black.
  final bool trueBlack;

  /// Whether colours follow the device's palette.
  final bool dynamicColor;

  /// Whether artwork may be loaded from hosts other than the user's services.
  final bool loadThirdPartyArtwork;

  /// App lock.
  final AppLock appLock;

  @override
  bool operator ==(Object other) =>
      other is Preferences &&
      other.activeProfileId == activeProfileId &&
      other.themeMode == themeMode &&
      other.trueBlack == trueBlack &&
      other.dynamicColor == dynamicColor &&
      other.loadThirdPartyArtwork == loadThirdPartyArtwork &&
      other.appLock == appLock;

  @override
  int get hashCode => Object.hash(
    activeProfileId,
    themeMode,
    trueBlack,
    dynamicColor,
    loadThirdPartyArtwork,
    appLock,
  );
}
