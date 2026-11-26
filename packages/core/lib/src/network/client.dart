/// The HTTP client of one instance (research R4).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import '../instances/auth_kind.dart';
import '../instances/credential.dart';
import '../instances/instance_rules.dart';
import '../instances/profile_repository.dart';
import '../logging/diagnostic_log.dart';
import '../logging/log_level.dart';
import '../logging/secret_redactor.dart';
import '../module/api_key_header.dart';
import '../module/result.dart';
import '../module/service_failure.dart';
import '../platform/local_network_permission.dart';
import '../platform/local_network_permission_state.dart';
import 'connection_settings.dart';
import 'http_error.dart';
import 'http_method.dart';
import 'request_body.dart';
import 'service_http_client.dart';
import 'service_request.dart';
import 'service_response.dart';
import 'trust.dart';

/// How many redirects of a read are followed.
const _maximumRedirects = 5;

const _redirectStatuses = {301, 302, 303, 307, 308};

/// How many times the limit of one step a whole attempt may take. Only an answer
/// that keeps arriving in small pieces gets this far, and a large library over a
/// slow link is not to be cut off.
const _attemptSteps = 10;

/// Sends the requests of one instance to its address, with its credential.
///
/// Redirects are followed only for a read and only within the origin. A read
/// whose connection is lost is tried once more; a write is sent at most once.
/// No proxy is used, so that a credential cannot reach one that the environment
/// names.
///
/// Nothing is written to an https connection before its certificate has been
/// accepted: against `certPin` alone if the settings have one, and else against
/// the system's roots and `customCa`. A pin says which certificate to expect, so
/// a send with one to an http address fails and sends nothing. An authority only
/// adds trust, and is ignored there.
final class InstanceHttpClient implements ServiceHttpClient {
  /// A client of settings of the caller's choosing, loaded for every send.
  ///
  /// [timeout] limits each step of one attempt: connecting, sending, waiting
  /// for the answer and each pause while receiving it. A whole attempt is
  /// limited to ten times that.
  InstanceHttpClient({
    required this._settings,
    required this._apiKeyHeader,
    required this._log,
    required this._localNetwork,
    this._timeout = const Duration(seconds: 30),
  });

  /// A client of a saved instance. Its address and credential are read together
  /// for every send.
  InstanceHttpClient.saved({
    required ProfileRepository profiles,
    required String instanceId,
    required ApiKeyHeader? apiKeyHeader,
    required DiagnosticLog log,
    required LocalNetworkPermission localNetwork,
    Duration timeout = const Duration(seconds: 30),
  }) : this(
         settings: () async {
           final found = await profiles.instanceWithCredential(instanceId);
           return found == null
               ? null
               : ConnectionSettings.saved(found.instance, found.credential);
         },
         apiKeyHeader: apiKeyHeader,
         log: log,
         localNetwork: localNetwork,
         timeout: timeout,
       );

  final Future<ConnectionSettings?> Function() _settings;
  final ApiKeyHeader? _apiKeyHeader;
  final DiagnosticLog _log;
  final LocalNetworkPermission _localNetwork;

  final Duration _timeout;

  // One for each pin and authority, as each pools its connections, and one made
  // under some trust must never be used under another.
  final _clients = <(String?, String?), Dio>{};

  var _closed = false;

  /// Drops every connection. Later sends fail.
  void close() {
    _closed = true;
    for (final client in _clients.values) {
      client.close(force: true);
    }
  }

  @override
  Future<Result<ServiceResponse, HttpError>> send(
    ServiceRequest request,
  ) async {
    final ConnectionSettings? settings;
    try {
      settings = await _settings();
    } catch (error) {
      // The type only: the text of a storage error may quote what it read.
      return _unsent(
        request,
        const Unreachable(),
        'the settings could not be read (${error.runtimeType})',
      );
    }
    if (settings == null) {
      return _unsent(request, const Unreachable(), 'there are no settings');
    }
    return sendWith(settings, request);
  }

  /// [send] with the settings given, which are not loaded. For a caller that
  /// has to know which settings an answer is for.
  Future<Result<ServiceResponse, HttpError>> sendWith(
    ConnectionSettings settings,
    ServiceRequest request,
  ) async {
    // Before anything uses it, or can log it.
    _log.addCredential(settings.credential);

    if (_closed) {
      return _unsent(request, const Unreachable(), 'the client is closed');
    }
    final url = settings.url;
    if (!(url.isScheme('http') || url.isScheme('https')) ||
        url.host.isEmpty ||
        url.userInfo.isNotEmpty) {
      return _unsent(request, const Unreachable(), 'the address is not usable');
    }
    // Fails closed: there is no certificate to check against the pin.
    if (!url.isScheme('https') && settings.certPin != null) {
      return _unsent(
        request,
        const Unreachable(),
        'a certificate pin needs https',
      );
    }
    final headers = _headers(request, settings);
    if (headers == null) {
      return _unsent(request, const Validation([]), 'a header cannot be sent');
    }
    final Dio client;
    try {
      client = _clientFor(settings);
    } on TlsException {
      return _unsent(
        request,
        const Unreachable(),
        'the certificate authority cannot be read',
      );
    }
    return _exchange(
      client,
      request,
      settings,
      _address(url, request),
      headers,
      _encodeBody(request.body),
    );
  }

  /// The client of the trust that [settings] ask for.
  Dio _clientFor(ConnectionSettings settings) {
    final certPin = settings.certPin;
    // A pin alone decides, and http has no certificate: the authority is then
    // not even read.
    final customCa = certPin == null && settings.url.isScheme('https')
        ? settings.customCa
        : null;
    return _clients[(certPin, customCa)] ??= _newDio(
      _timeout,
      newHttpClient(certPin: certPin, customCa: customCa),
    );
  }

  /// Sends, following redirects and retrying as the rules allow.
  Future<Result<ServiceResponse, HttpError>> _exchange(
    Dio client,
    ServiceRequest request,
    ConnectionSettings settings,
    Uri address,
    Map<String, String> headers,
    Uint8List? body,
  ) async {
    final isRead = request.method == HttpMethod.get;
    var uri = address;
    var redirects = 0;
    var retried = false;
    while (true) {
      final ServiceResponse response;
      try {
        response = await _attempt(client, request.method, uri, headers, body);
      } on DioException catch (error) {
        // Nothing was sent, so this holds for a write too.
        if (error.error case CertificateRefusal(:final failure)) {
          return _failed(request, failure, cause: 'nothing sent');
        }
        final fault = _faultOf(error);
        if (fault == _Fault.lost && isRead && !retried) {
          retried = true;
          continue;
        }
        return _failed(
          request,
          await _failureOfFault(fault, uri.host, isRead: isRead),
          cause: '${fault.name}, ${error.error.runtimeType}',
        );
      }

      if (!_redirectStatuses.contains(response.statusCode)) {
        final failure = _failureOfResponse(
          response,
          settings.credential,
          isRead: isRead,
        );
        return failure == null
            ? Ok(response)
            : _failed(request, failure, response: response);
      }

      final target = _target(uri, response);
      if (target == null) {
        return _failed(request, const Redirected(), response: response);
      }
      if (isOtherOrigin(address, target)) {
        final host = target.host.isEmpty ? null : target.host;
        return _failed(request, Redirected(host: host), response: response);
      }
      // Sending a write on would send it a second time.
      if (!isRead || redirects == _maximumRedirects) {
        return _failed(request, const Redirected(), response: response);
      }
      redirects++;
      // User information would replace the basic authentication.
      uri = target.replace(userInfo: '').removeFragment();
    }
  }

  Future<ServiceResponse> _attempt(
    Dio client,
    HttpMethod method,
    Uri uri,
    Map<String, String> headers,
    Uint8List? body,
  ) async {
    final cancel = CancelToken();
    final deadline = Timer(_timeout * _attemptSteps, cancel.cancel);
    try {
      final response = await client.requestUri<Uint8List>(
        uri,
        data: body,
        cancelToken: cancel,
        // A copy, as dio adds to it.
        options: Options(
          method: method.name.toUpperCase(),
          headers: {...headers},
        ),
      );
      return ServiceResponse(
        statusCode: response.statusCode!,
        headers: response.headers.map,
        bytes: response.data ?? Uint8List(0),
      );
    } finally {
      deadline.cancel();
    }
  }

  /// The headers of [request], or null if one of them cannot be sent.
  Map<String, String>? _headers(
    ServiceRequest request,
    ConnectionSettings settings,
  ) {
    final credential = settings.credential;
    final headers = <String, String>{
      if (request.body case final body?)
        'content-type': switch (body) {
          JsonBody() => 'application/json; charset=utf-8',
          FormBody() => 'application/x-www-form-urlencoded',
        },
    };
    final cookies = <String>[];
    var valid = true;
    void add(String name, String value) {
      valid = valid && isValidHeaderName(name) && _isSendable(value);
      final key = name.toLowerCase();
      if (key == 'cookie') {
        cookies.add(value);
      } else {
        headers[key] = value;
      }
    }

    request.headers.forEach(add);
    credential.customHeaders.forEach(add);
    if (hasBasicAuth(credential)) {
      final login =
          '${credential.basicUser ?? ''}:${credential.basicPassword ?? ''}';
      add('authorization', 'Basic ${base64Encode(utf8.encode(login))}');
    }
    final apiKeyHeader = _apiKeyHeader;
    final apiKey = credential.apiKey;
    if (settings.authKind == AuthKind.apiKey &&
        apiKeyHeader != null &&
        apiKey != null) {
      add(apiKeyHeader.name, '${apiKeyHeader.prefix}$apiKey');
    }
    if (credential.sessionCookie case final session?) add('cookie', session);
    if (cookies.isNotEmpty) headers['cookie'] = cookies.join('; ');
    return valid ? headers : null;
  }

  /// Why a response is not a success, or null if it is one. Redirects are
  /// dealt with before.
  ServiceFailure? _failureOfResponse(
    ServiceResponse response,
    Credential credential, {
    required bool isRead,
  }) => switch (response.statusCode) {
    >= 200 && < 300 => _isWebPage(response) ? const ProxyInterception() : null,
    // ASP.NET Core's host filtering, which the Servarr services run on.
    400 when response.text.contains('Invalid Hostname') => const HostRejected(),
    400 || 422 => Validation(_messages(response, credential)),
    401 => const AuthFailed(),
    403 => const Forbidden(),
    404 => const NotFound(),
    409 => const Conflict(),
    421 => const HostRejected(),
    // A gateway cannot say whether the server behind it did the work.
    502 || 504 when !isRead => const OutcomeUnknown(),
    final status => ServerError(statusCode: status),
  };

  Future<ServiceFailure> _failureOfFault(
    _Fault fault,
    String host, {
    required bool isRead,
  }) async {
    // A denied permission looks like a timeout (research R6).
    if ((fault == _Fault.connectTimeout || fault == _Fault.timeout) &&
        await _isDenied(host)) {
      return const PermissionDenied();
    }
    return switch (fault) {
      _Fault.dns => const DnsFailure(),
      _Fault.notConnected || _Fault.connectTimeout => const Unreachable(),
      // From here on the request may have arrived.
      _ when !isRead => const OutcomeUnknown(),
      _Fault.timeout || _Fault.overdue || _Fault.lost => const Unreachable(),
      _Fault.malformed => const MalformedResponse(),
    };
  }

  Future<bool> _isDenied(String host) async {
    try {
      return await _localNetwork.status(host) ==
          LocalNetworkPermissionState.denied;
    } catch (error) {
      _log.log(
        LogLevel.warning,
        'Local network permission unknown (${error.runtimeType})',
      );
      return false;
    }
  }

  Result<ServiceResponse, HttpError> _unsent(
    ServiceRequest request,
    ServiceFailure failure,
    String reason,
  ) => _failed(request, failure, cause: 'nothing sent, $reason');

  /// Records a failure, without address, headers or the text of any error.
  Result<ServiceResponse, HttpError> _failed(
    ServiceRequest request,
    ServiceFailure failure, {
    ServiceResponse? response,
    String? cause,
  }) {
    _log.log(
      LogLevel.warning,
      [
        'HTTP ${request.method.name} failed: ${failure.runtimeType}',
        if (response != null) 'status ${response.statusCode}',
        ?cause,
      ].join(', '),
    );
    return Err(HttpError(failure, response: response));
  }
}

/// Where an attempt that got no complete answer stopped.
enum _Fault {
  /// The name was not resolved.
  dns,

  /// No connection, so nothing was sent.
  notConnected,

  /// No connection in time, so nothing was sent.
  connectTimeout,

  /// Connected, then no answer in time.
  timeout,

  /// The whole attempt took too long. Not a [timeout], as an answer that keeps
  /// arriving is no sign of a missing permission, and the read is not repeated.
  overdue,

  /// Connected, then the connection ended.
  lost,

  /// An answer that is not HTTP or cannot be decoded.
  malformed,
}

// dio reports a SocketException as a connection error only when it comes from
// opening the connection, before anything is written.
_Fault _faultOf(DioException exception) => switch (exception) {
  DioException(type: DioExceptionType.connectionTimeout) =>
    _Fault.connectTimeout,
  DioException(
    type: DioExceptionType.sendTimeout || DioExceptionType.receiveTimeout,
  ) =>
    _Fault.timeout,
  // Only the deadline of an attempt cancels.
  DioException(type: DioExceptionType.cancel) => _Fault.overdue,
  DioException(
    type: DioExceptionType.connectionError,
    error: SocketException(:final message),
  ) =>
    message.startsWith('Failed host lookup') ? _Fault.dns : _Fault.notConnected,
  DioException(error: HandshakeException() || CertificateException()) =>
    _Fault.notConnected,
  DioException(error: HttpException(:final message))
      when _unreadable.hasMatch(message) =>
    _Fault.malformed,
  DioException(error: FormatException()) => _Fault.malformed,
  _ => _Fault.lost,
};

// The messages of `dart:io`'s HTTP parser about an answer that is not HTTP. Any
// other HttpException is a connection that failed, and may carry the operating
// system's own text, such as "Connection reset by peer".
final _unreadable = RegExp(
  '^(Invalid |Failed to parse HTTP|Illegal value |Chunk size overflows|'
  'Content-Length |The Content-Length header occurred more than once)|'
  r'exceeds the \d+ size limit$',
);

Dio _newDio(Duration timeout, HttpClient httpClient) =>
    Dio(
        BaseOptions(
          connectTimeout: timeout,
          sendTimeout: timeout,
          receiveTimeout: timeout,
          responseType: ResponseType.bytes,
          // Followed here, by the rules above.
          followRedirects: false,
          validateStatus: (_) => true,
        ),
      )
      ..httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () => httpClient,
      )
      // Content types are set with the other headers.
      ..interceptors.removeImplyContentTypeInterceptor();

/// RFC 3986 percent encoding of everything but the unreserved characters.
String _encode(String text) => Uri.encodeComponent(text).replaceAllMapped(
  RegExp("[!'()*]"),
  (m) => '%${m[0]!.codeUnitAt(0).toRadixString(16).toUpperCase()}',
);

/// The address of [request] under the instance's address [url].
Uri _address(Uri url, ServiceRequest request) {
  final base = url.path.replaceFirst(RegExp(r'/+$'), '');
  final path = request.path.split('/').map(_encode).join('/');
  final query = [
    for (final MapEntry(:key, value: values) in request.query.entries)
      for (final value in values) '${_encode(key)}=${_encode(value)}',
  ].join('&');
  return Uri.parse(
    '${url.scheme}://${url.authority}$base/$path'
    '${query.isEmpty ? '' : '?$query'}',
  );
}

Uint8List? _encodeBody(RequestBody? body) => switch (body) {
  null => null,
  JsonBody(:final value) => utf8.encode(jsonEncode(value)),
  FormBody(:final fields) => utf8.encode(
    [
      for (final MapEntry(:key, :value) in fields.entries)
        '${Uri.encodeQueryComponent(key)}=${Uri.encodeQueryComponent(value)}',
    ].join('&'),
  ),
};

/// Whether [value] has only visible ASCII, spaces and tabs. A line break would
/// add headers, and `dart:io` quotes a value it rejects in its error.
bool _isSendable(String value) => value.codeUnits.every(
  (unit) => unit == 0x09 || (unit >= 0x20 && unit < 0x7f),
);

/// The address a redirect names, or null if it names none that can be read.
Uri? _target(Uri from, ServiceResponse response) {
  final location = response.headers['location']?.firstOrNull;
  if (location == null) return null;
  final reference = Uri.tryParse(location);
  return reference == null ? null : from.resolveUri(reference);
}

bool _isWebPage(ServiceResponse response) {
  final type = response.headers['content-type']?.firstOrNull;
  return type?.split(';').first.trim().toLowerCase() == 'text/html';
}

final _url = RegExp(
  r'''[a-z][a-z0-9+.-]*://[^\s"'<>]+''',
  caseSensitive: false,
);

/// The server's own messages about the values sent, without secrets and URLs.
List<String> _messages(ServiceResponse response, Credential credential) {
  final Object? json;
  try {
    json = jsonDecode(response.text);
  } on FormatException {
    return const [];
  }
  final redactor = SecretRedactor()..addCredential(credential);
  String clean(String message) =>
      redactor.redact(message).replaceAll(_url, SecretRedactor.marker);
  return [
    // Servarr's list of failed rules.
    if (json is List<Object?>)
      for (final entry in json)
        if (entry case {'errorMessage': final String message}) clean(message),
    if (json case {'message': final String message}) clean(message),
  ];
}
