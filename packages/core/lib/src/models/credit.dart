import 'media_image.dart';

/// A person in a cast or crew.
final class Credit {
  /// Creates a [Credit].
  const Credit({
    required this.person,
    required this.role,
    this.character,
    this.image,
  });

  /// The person's name.
  final String person;

  /// Their job or part.
  final String role;

  /// The character played.
  final String? character;

  /// Their picture.
  final MediaImage? image;
}
