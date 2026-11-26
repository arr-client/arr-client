/// How a service expects its API key, so the core client can send it.
final class ApiKeyHeader {
  /// Creates an [ApiKeyHeader].
  const ApiKeyHeader(this.name, {this.prefix = ''});

  /// The header's name, for example `X-Api-Key` or `Authorization`.
  final String name;

  /// Put before the key in the value, for example `Bearer `.
  final String prefix;
}
