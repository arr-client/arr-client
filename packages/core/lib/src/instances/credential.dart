/// An instance's secrets. Kept in secure storage only; never logged.
final class Credential {
  const Credential({
    this.apiKey,
    this.username,
    this.password,
    this.basicUser,
    this.basicPassword,
    this.sessionCookie,
    this.customHeaders = const {},
  });

  final String? apiKey;

  final String? username;

  final String? password;

  /// For HTTP basic authentication in front of the service.
  final String? basicUser;

  final String? basicPassword;

  /// Header name to value.
  final Map<String, String> customHeaders;

  final String? sessionCookie;
}
