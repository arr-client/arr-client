/// How an instance authenticates. Names are persisted.
enum AuthKind {
  /// An API key sent in a header.
  apiKey,

  /// A user name and password of the service.
  userPassword,

  /// An account of a media server the service trusts.
  mediaServerAccount,

  /// No authentication.
  none,
}
