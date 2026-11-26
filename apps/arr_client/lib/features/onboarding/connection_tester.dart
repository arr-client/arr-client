/// Testing a connection without saving it.
library;

import 'package:core/core.dart';

/// What a test connects to and with. Holds secrets: never log it.
final class ConnectionInput {
  const ConnectionInput({
    required this.url,
    required this.authKind,
    required this.credential,
    this.certPin,
    this.customCa,
  });

  final Uri url;
  final AuthKind authKind;
  final Credential credential;

  /// SHA-256 of a certificate the user accepted for [url].
  final String? certPin;

  /// A private certificate authority, PEM.
  final String? customCa;
}

/// Asks the user whether to go on to the system's local network prompt.
typedef ExplainLocalNetwork = Future<bool> Function();

/// One test of one service, with a client of its own. Saves nothing.
final class ConnectionTest {
  ConnectionTest({
    required this.module,
    required this.input,
    required this._log,
    required this._localNetwork,
    required this._artwork,
    required this._cache,
    required this._navigator,
    this._timeout = const Duration(seconds: 15),
  });

  /// The instance id of what is not saved.
  static const _unsavedId = 'unsaved';

  final ServiceModule module;
  final ConnectionInput input;
  final DiagnosticLog _log;
  final LocalNetworkPermission _localNetwork;
  final ArtworkCache _artwork;
  final CacheRepository _cache;
  final AppNavigator _navigator;
  final Duration _timeout;

  InstanceHttpClient? _client;
  var _cancelled = false;

  static const _abandoned = Err<ProbeResult, ServiceFailure>(Unreachable());

  /// Gives up: drops the connection, and nothing more is sent.
  void cancel() {
    _cancelled = true;
    _client?.close();
  }

  /// Verifies the service type and version at the address.
  ///
  /// If the local network permission is needed and missing, [explain] is asked
  /// before the system prompts. A sign-in kind signs in once first.
  Future<Result<ProbeResult, ServiceFailure>> run(
    ExplainLocalNetwork explain,
  ) async {
    try {
      if (!await _mayUseNetwork(explain)) {
        return const Err(PermissionDenied());
      }
      if (_cancelled) return _abandoned;

      var credential = input.credential;
      final handler = module.sessionHandler;
      final signsIn = switch (input.authKind) {
        AuthKind.userPassword || AuthKind.mediaServerAccount => true,
        AuthKind.apiKey || AuthKind.none => false,
      };
      if (signsIn && handler != null) {
        final http = _StatusClient(_open(credential));
        final login = await handler.login(
          authKind: input.authKind,
          credential: credential,
          http: http,
        );
        _client?.close();
        switch (login) {
          case Ok(:final value):
            _log.addCredential(Credential(sessionCookie: value));
            credential = _withSession(credential, value);
          case Err(:final error):
            return Err(_ofSignIn(error, http.status));
        }
        if (_cancelled) return _abandoned;
      }
      return await module.probe(_context(_open(credential)));
    } catch (error) {
      // The type only: the text may quote an address or a secret.
      _log.log(
        LogLevel.error,
        'A connection test failed (${error.runtimeType})',
      );
      return const Err(MalformedResponse());
    } finally {
      _client?.close();
    }
  }

  /// A sign-in changes nothing on the server, so that its outcome is unknown
  /// only means that it failed (as `InstanceSession` has it).
  static ServiceFailure _ofSignIn(ServiceFailure failure, int? status) =>
      switch ((failure, status)) {
        (OutcomeUnknown(), 502 || 504) => ServerError(statusCode: status),
        (OutcomeUnknown(), _) => const Unreachable(),
        _ => failure,
      };

  Future<bool> _mayUseNetwork(ExplainLocalNetwork explain) async {
    final host = input.url.host;
    try {
      if (await _localNetwork.status(host) !=
          LocalNetworkPermissionState.denied) {
        return true;
      }
      if (_cancelled || !await explain() || _cancelled) return false;
      return await _localNetwork.request(host) !=
          LocalNetworkPermissionState.denied;
    } catch (error) {
      // The connection itself will tell.
      _log.log(
        LogLevel.warning,
        'Local network permission unknown (${error.runtimeType})',
      );
      return true;
    }
  }

  InstanceHttpClient _open(Credential credential) {
    final settings = ConnectionSettings(
      url: input.url,
      authKind: input.authKind,
      credential: credential,
      certPin: input.certPin,
      customCa: input.customCa,
    );
    final client = _client = InstanceHttpClient(
      settings: () async => settings,
      apiKeyHeader: module.descriptor.apiKeyHeader,
      log: _log,
      localNetwork: _localNetwork,
      timeout: _timeout,
    );
    if (_cancelled) client.close();
    return client;
  }

  InstanceContext _context(ServiceHttpClient http) {
    final now = DateTime.now().toUtc();
    return InstanceContext(
      instance: Instance(
        id: _unsavedId,
        profileId: _unsavedId,
        name: module.descriptor.displayName,
        serviceType: module.id,
        url: input.url,
        authKind: input.authKind,
        certPin: input.certPin,
        customCa: input.customCa,
        createdAt: now,
        updatedAt: now,
      ),
      http: http,
      // A probe reads neither artwork nor the cache.
      artwork: _artwork.loaderFor(_unsavedId, http),
      cache: _cache.scope(_unsavedId),
      navigator: _navigator,
      logger: _log,
    );
  }

  static Credential _withSession(Credential credential, String cookie) =>
      Credential(
        apiKey: credential.apiKey,
        username: credential.username,
        password: credential.password,
        basicUser: credential.basicUser,
        basicPassword: credential.basicPassword,
        customHeaders: credential.customHeaders,
        sessionCookie: cookie,
      );
}

/// Remembers the status of the last answer, which a [SessionHandler] does not
/// pass on with its failure.
final class _StatusClient implements ServiceHttpClient {
  _StatusClient(this._client);

  final ServiceHttpClient _client;

  int? status;

  @override
  Future<Result<ServiceResponse, HttpError>> send(
    ServiceRequest request,
  ) async {
    final result = await _client.send(request);
    status = switch (result) {
      Ok(:final value) => value.statusCode,
      Err(:final error) => error.response?.statusCode,
    };
    return result;
  }
}
