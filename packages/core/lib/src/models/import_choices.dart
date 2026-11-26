import 'language.dart';
import 'quality.dart';

/// The values a manual import can be corrected to.
final class ImportChoices {
  const ImportChoices({required this.qualities, this.languages = const []});

  final List<Quality> qualities;

  /// Empty where language cannot be corrected.
  final List<Language> languages;
}
