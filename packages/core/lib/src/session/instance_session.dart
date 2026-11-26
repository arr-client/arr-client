import '../instances/auth_kind.dart';
import '../instances/credential.dart';
import '../instances/instance_rules.dart';
import '../instances/profile_repository.dart';
import '../logging/diagnostic_log.dart';
import '../logging/log_level.dart';
import '../module/api_key_header.dart';
import '../module/result.dart';
import '../module/service_failure.dart';
import '../module/service_result.dart';
import '../module/session_authenticator.dart';
import '../module/session_handler.dart';
import '../network/client.dart';
import '../network/connection_settings.dart';
import '../network/http_error.dart';
import '../network/http_method.dart';
import '../network/service_http_client.dart';
import '../network/service_request.dart';
import '../network/service_response.dart';
import '../platform/local_network_permission.dart';

/// The HTTP client of a saved instance, which keeps its session and honours
/// `Instance.authFailed`. Every request that authenticates with a saved
/// instance goes through one.
///
/// While the instance is latched nothing is sent: [send] and [login] fail with
/// [AuthFailed]. A rejected login latches it, and so does an [AuthFailed]
/// answer that the module does not take for an expired session. A rejection of
/// an address or credential that has been edited meanwhile does not.
///
/// For a user name and password the session is kept in the instance's
/// credential. Without one, signing in comes before the request. When the
/// module says it has expired, a read signs in and is sent once more. A write
/// is never sent again; its session is discarded, so that the next request
/// signs in.
///
/// A server can refuse a request however new the session is, for want of a
/// permission or because a proxy drops the cookie, and the password must not be
/// sent at the rate of polling. So an expired session is signed in again at most
/// once in [reloginInterval], and a path that refused a new session causes no
/// sign-in until it has succeeded or [refusedRetryInterval] has passed. Until
/// then such a read fails with the server's answer.
///
/// Make one for each instance and isolate. The latch and the session are read
/// from storage for every request, so another isolate, with its own database
/// connection, honours and uses what this one stored. Only requests of one
/// object share a sign-in: two isolates that find no session at the same time
/// may each try to sign in once before the instance is latched.
final class InstanceSession implements ServiceHttpClient, SessionAuthenticator {
  /// [handler] is the module's `sessionHandler` and [apiKeyHeader] its
  /// descriptor's. [timeout] is that of [InstanceHttpClient]. [now] times the
  /// sign-ins.
  InstanceSession({
    required ProfileRepository profiles,
    required String instanceId,
    required this._handler,
    required ApiKeyHeader? apiKeyHeader,
    required DiagnosticLog log,
    required LocalNetworkPermission localNetwork,
    Duration timeout = const Duration(seconds: 30),
    this._now = DateTime.now,
  }) : _profiles = profiles,
       _instanceId = instanceId,
       _log = log,
       _client = InstanceHttpClient.saved(
         profiles: profiles,
         instanceId: instanceId,
         apiKeyHeader: apiKeyHeader,
         log: log,
         localNetwork: localNetwork,
         timeout: timeout,
       );

  /// The least time between two sign-ins made because a session expired. Short,
  /// as a session that has really expired waits for it too.
  static const reloginInterval = Duration(minutes: 1);

  /// How long a path that refused a new session causes no sign-in.
  static const refusedRetryInterval = Duration(minutes: 10);

  final DateTime Function() _now;
  final ProfileRepository _profiles;
  final String _instanceId;
  final SessionHandler? _handler;
  final DiagnosticLog _log;
  final InstanceHttpClient _client;

  ServiceResult<void>? _signingIn;

  /// A rejection that could not be stored. Nothing is sent until it is.
  InstanceAccess? _unrecorded;

  /// When an expired session was last signed in again.
  DateTime? _renewedAt;

  /// By path, when it last refused a new session.
  final _refused = <String, DateTime>{};

  /// Drops every connection. Later sends fail.
  void close() => _client.close();

  @override
  ServiceResult<void> login() => _signIn(replace: true);

  @override
  Future<Result<ServiceResponse, HttpError>> send(
    ServiceRequest request,
  ) async {
    InstanceAccess used;
    switch (await _access()) {
      case Ok(:final value):
        used = value;
      case Err(:final error):
        return Err(HttpError(error));
    }
    final handler = _signsIn(used) ? _handler : null;
    if (handler != null && used.credential?.sessionCookie == null) {
      switch (await _renew(null)) {
        case Ok(:final value):
          used = value;
        case Err(:final error):
          return Err(HttpError(error));
      }
    }

    final result = await _sendAs(used, request);
    if (handler == null || !_isExpired(handler, result)) {
      // Only a success shows that the path is no longer refused.
      if (result is Ok) _refused.remove(request.path);
      return _settle(used, result);
    }
    if (request.method != HttpMethod.get) {
      await _discard(used);
      return result;
    }
    if (_isWithin(refusedRetryInterval, _refused[request.path])) return result;
    final stale = used.credential?.sessionCookie;
    // Too soon to sign in again, but another may have done so meanwhile. A
    // sign-in under way is waited for.
    final tooSoon =
        _signingIn == null && _isWithin(reloginInterval, _renewedAt);
    switch (tooSoon ? await _access() : await _renew(stale)) {
      case Ok(:final value):
        used = value;
      case Err(:final error):
        return Err(HttpError(error));
    }
    final session = used.credential?.sessionCookie;
    if (session == null || session == stale) return result;
    final repeated = await _sendAs(used, request);
    if (!_isExpired(handler, repeated)) return _settle(used, repeated);
    // The sign-in was accepted, so this refuses the request, not the account.
    _refused[request.path] = _now();
    return repeated;
  }

  /// Whether [time] is less than [interval] ago. A clock set back counts by how
  /// far, so that it cannot block for longer.
  bool _isWithin(Duration interval, DateTime? time) =>
      time != null && _now().difference(time).abs() < interval;

  /// What to authenticate with now, or why nothing may be sent.
  Future<Result<InstanceAccess, ServiceFailure>> _access() async {
    if (_unrecorded case final rejected?) {
      await _reject(rejected);
      return const Err(AuthFailed());
    }
    final InstanceAccess? found;
    try {
      found = await _profiles.instanceWithCredential(_instanceId);
    } catch (error) {
      _warn('The settings could not be read', error);
      return const Err(Unreachable());
    }
    if (found == null) return const Err(Unreachable());
    if (found.instance.authFailed) return const Err(AuthFailed());
    return Ok(found);
  }

  static bool _signsIn(InstanceAccess access) =>
      switch (access.instance.authKind) {
        AuthKind.userPassword || AuthKind.mediaServerAccount => true,
        AuthKind.apiKey || AuthKind.none => false,
      };

  Future<Result<ServiceResponse, HttpError>> _sendAs(
    InstanceAccess access,
    ServiceRequest request,
  ) => _client.sendWith(
    ConnectionSettings.saved(access.instance, access.credential),
    request,
  );

  /// Gets a session other than [stale] for a request that is yet to be sent.
  Future<Result<InstanceAccess, ServiceFailure>> _renew(String? stale) async {
    if (await _signIn(stale: stale) case Err(:final error)) {
      // The request was not sent, whatever became of the login.
      return Err(error is OutcomeUnknown ? const Unreachable() : error);
    }
    final access = await _access();
    return switch (access) {
      // Discarded again already, so there is nothing to send with.
      Ok(:final value) when value.credential?.sessionCookie == null =>
        const Err(Unreachable()),
      _ => access,
    };
  }

  /// Signs in, or waits for the sign-in under way. Unless [replace], a stored
  /// session other than [stale] will do.
  ServiceResult<void> _signIn({bool replace = false, String? stale}) =>
      _signingIn ??= _attemptSignIn(
        replace: replace,
        stale: stale,
      ).whenComplete(() => _signingIn = null);

  ServiceResult<void> _attemptSignIn({
    required bool replace,
    required String? stale,
  }) async {
    final InstanceAccess used;
    switch (await _access()) {
      case Ok(:final value):
        used = value;
      case Err(:final error):
        return Err(error);
    }
    final handler = _handler;
    if (handler == null || !_signsIn(used)) {
      throw StateError('The instance has no sign-in');
    }
    final cookie = used.credential?.sessionCookie;
    // Another isolate, or an earlier request, has signed in already.
    if (!replace && cookie != null && cookie != stale) return const Ok(null);
    final credential = withSession(used.credential ?? const Credential(), null);
    // Nothing to try, for example after the platform erased what was stored.
    if (credential.username == null && credential.password == null) {
      return const Err(AuthFailed());
    }

    // Counted whatever comes of it, as the password is sent.
    if (stale != null) _renewedAt = _now();

    final Result<String, ServiceFailure> answer;
    try {
      answer = await handler.login(
        authKind: used.instance.authKind,
        credential: credential,
        http: _LoginClient(
          _client,
          ConnectionSettings.saved(used.instance, credential),
        ),
      );
    } catch (error) {
      _warn('Signing in failed', error);
      return const Err(MalformedResponse());
    }
    switch (answer) {
      case Err(:final error):
        // Before the sign-in ends, so that nothing waiting for it tries again.
        if (error is AuthFailed) await _reject(used);
        return Err(error);
      case Ok(value: final session):
        if (session.isEmpty) return const Err(MalformedResponse());
        try {
          return await _profiles.saveSession(used, session)
              ? const Ok(null)
              // Edited meanwhile: the next request signs in to what is there.
              : const Err(Unreachable());
        } catch (error) {
          _warn('A session could not be stored', error);
          return const Err(Unreachable());
        }
    }
  }

  bool _isExpired(
    SessionHandler handler,
    Result<ServiceResponse, HttpError> result,
  ) {
    final response = switch (result) {
      Ok(:final value) => value,
      Err(:final error) => error.response,
    };
    return response != null && handler.isSessionExpired(response);
  }

  /// Latches the instance if [result] is a rejection.
  Future<Result<ServiceResponse, HttpError>> _settle(
    InstanceAccess used,
    Result<ServiceResponse, HttpError> result,
  ) async {
    if (result case Err(error: HttpError(failure: AuthFailed()))) {
      await _reject(used);
    }
    return result;
  }

  Future<void> _reject(InstanceAccess used) async {
    try {
      await _profiles.rejectAuth(used);
      _unrecorded = null;
    } catch (error) {
      _unrecorded = used;
      _warn('A rejected sign-in could not be recorded', error);
    }
  }

  Future<void> _discard(InstanceAccess used) async {
    try {
      await _profiles.dropSession(used);
    } catch (error) {
      _warn('An expired session could not be discarded', error);
    }
  }

  // The type only: the text of an error may quote a secret.
  void _warn(String message, Object error) =>
      _log.log(LogLevel.warning, '$message (${error.runtimeType})');
}

/// What a [SessionHandler] signs in over: one address and credential, however
/// the instance is edited meanwhile, and no session.
final class _LoginClient implements ServiceHttpClient {
  _LoginClient(this._client, this._settings);

  final InstanceHttpClient _client;
  final ConnectionSettings _settings;

  @override
  Future<Result<ServiceResponse, HttpError>> send(ServiceRequest request) =>
      _client.sendWith(_settings, request);
}
