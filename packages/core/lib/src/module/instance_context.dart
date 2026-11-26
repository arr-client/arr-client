import '../artwork/artwork_loader.dart';
import '../cache/cache_scope.dart';
import '../instances/instance.dart';
import '../logging/logger.dart';
import '../network/service_http_client.dart';
import 'app_navigator.dart';
import 'session_authenticator.dart';

/// Everything a module may use for one instance. Modules never create HTTP
/// clients or read secure storage themselves.
final class InstanceContext {
  /// Creates an [InstanceContext].
  const InstanceContext({
    required this.instance,
    required this.http,
    required this.artwork,
    required this.navigator,
    required this.cache,
    required this.logger,
    this.session,
  });

  /// The instance served.
  final Instance instance;

  /// Configured with the instance's address, authentication, certificate trust
  /// and redaction. For session-based authentication it also holds the session
  /// and signs in again when it expires.
  final ServiceHttpClient http;

  /// Loads the instance's artwork.
  final ArtworkLoader artwork;

  /// Opens shared flows of the app.
  final AppNavigator navigator;

  /// The instance's cache.
  final CacheScope cache;

  /// The diagnostic log.
  final Logger logger;

  /// Present when the instance uses session-based authentication.
  final SessionAuthenticator? session;
}
