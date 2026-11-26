import 'media_image.dart';

/// A person in a cast or crew.
final class Credit {
  const Credit({
    required this.person,
    required this.role,
    this.character,
    this.image,
  });

  final String person;

  final String role;

  final String? character;

  final MediaImage? image;
}
