import 'imported_setting.dart';

/// A setting that an import would change.
final class PreferenceChange {
  /// Creates a [PreferenceChange].
  const PreferenceChange({
    required this.setting,
    required this.from,
    required this.to,
  });

  /// Which one.
  final ImportedSetting setting;

  /// Its value now, of the type of the `Preferences` field.
  final Object from;

  /// Its value after the import.
  final Object to;
}
