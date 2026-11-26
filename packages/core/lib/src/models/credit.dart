import 'credit_type.dart';
import 'media_image.dart';

/// A person in a cast or crew.
final class Credit {
  /// Creates a [Credit].
  const Credit({
    required this.person,
    required this.type,
    this.role,
    this.character,
    this.image,
  });

  /// The person's name.
  final String person;

  /// Cast or crew.
  final CreditType type;

  /// Their job, in the server's words; null where it gives none. A screen
  /// supplies its own label from [type].
  final String? role;

  /// The character played.
  final String? character;

  /// Their picture.
  final MediaImage? image;
}
