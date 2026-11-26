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
  const InstanceContext({
    required this.instance,
    required this.http,
    required this.artwork,
    required this.navigator,
    required this.cache,
    required this.logger,
    this.session,
  });

  final Instance instance;

  /// Configured with the instance's address, authentication, certificate trust
  /// and redaction. For session-based authentication it also holds the session
  /// and signs in again when it expires.
  final ServiceHttpClient http;

  final ArtworkLoader artwork;

  final AppNavigator navigator;

  final CacheScope cache;

  final Logger logger;

  /// Present when the instance uses session-based authentication.
  final SessionAuthenticator? session;
}
