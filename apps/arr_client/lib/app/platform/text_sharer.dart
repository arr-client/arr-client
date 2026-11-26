import 'package:flutter/services.dart';

/// Hands text to the system's share sheet, where the user chooses what receives
/// it, or nothing.
abstract interface class TextSharer {
  /// Throws if the share sheet cannot be opened.
  Future<void> share(String text);
}

/// [TextSharer] for Android, answered by `MainActivity`.
final class SystemTextSharer implements TextSharer {
  const SystemTextSharer();

  static const channel = MethodChannel('io.github.arrclient.app/share');

  @override
  Future<void> share(String text) =>
      channel.invokeMethod<void>('shareText', text);
}
