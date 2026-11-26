/// Whether the operating system lets the app reach a host.
enum LocalNetworkPermissionState {
  /// The host is not on the local network, or the system asks for nothing.
  notRequired,

  /// Permission is held.
  granted,

  /// Permission is missing.
  denied,
}
