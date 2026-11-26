import '../instances/auth_kind.dart';
import 'localized_text.dart';

/// A warning a module attaches to one way of authenticating.
final class AuthNote {
  /// Creates an [AuthNote].
  const AuthNote({
    required this.authKind,
    required this.text,
    this.onlyWithBasicAuth = false,
  });

  /// The way of authenticating it is about.
  final AuthKind authKind;

  /// The warning.
  final LocalizedText text;

  /// Shown only when HTTP basic authentication is filled in.
  final bool onlyWithBasicAuth;
}
