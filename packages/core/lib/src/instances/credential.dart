/// An instance's secrets. Kept in secure storage only; never logged.
final class Credential {
  /// Creates a [Credential].
  const Credential({
    this.apiKey,
    this.username,
    this.password,
    this.basicUser,
    this.basicPassword,
    this.sessionCookie,
    this.customHeaders = const {},
  });

  /// The service's API key.
  final String? apiKey;

  /// The account to sign in with.
  final String? username;

  /// The password of [username].
  final String? password;

  /// For HTTP basic authentication in front of the service.
  final String? basicUser;

  /// The password of [basicUser].
  final String? basicPassword;

  /// Header name to value.
  final Map<String, String> customHeaders;

  /// The `Cookie` header value of the current session.
  final String? sessionCookie;
}
