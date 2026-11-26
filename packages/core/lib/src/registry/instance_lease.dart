/// How the registry hands out an instance's session, and takes it back.
library;

import 'dart:async';

import '../cache/cache_entry.dart';
import '../cache/cache_scope.dart';
import '../cache/cache_snapshot.dart';
import '../models/media_kind.dart';
import '../module/result.dart';
import '../module/service_failure.dart';
import '../module/service_result.dart';
import '../module/session_authenticator.dart';
import '../network/http_error.dart';
import '../network/http_method.dart';
import '../network/service_http_client.dart';
import '../network/service_request.dart';
import '../network/service_response.dart';
import '../session/instance_session.dart';

/// The one [InstanceSession] of an instance as it is saved now.
///
/// It is closed once it is released and nothing holds it. A write holds it, as
/// closing drops every connection and would leave the write's outcome unknown.
final class SessionLink {
  /// [version] tells apart what the instance was saved as. [signsIn] if a read
  /// may have to sign in first. [onClosed] is called when the session has been
  /// closed.
  SessionLink(
    this.session, {
    required this.version,
    required this.signsIn,
    required this.onClosed,
  });

  /// The session.
  final InstanceSession session;

  /// What the instance was saved as when the session was made.
  final String version;

  /// Whether reads hold the session too: cutting off a sign-in would lose a
  /// rejection that has to stop further attempts.
  final bool signsIn;

  /// Called when the session has been closed.
  final void Function(SessionLink link) onClosed;

  var _holds = 0;
  var _released = false;

  /// Uses again a released session that something has kept open.
  void take() => _released = false;

  /// Closes the session, now or when nothing holds it any more.
  void release() {
    _released = true;
    _closeIfIdle();
  }

  /// Keeps the session open until [use] has ended.
  Future<T> hold<T>(Future<T> Function() use) async {
    _holds++;
    try {
      return await use();
    } finally {
      _holds--;
      _closeIfIdle();
    }
  }

  void _closeIfIdle() {
    if (!_released || _holds > 0) return;
    session.close();
    onClosed(this);
  }
}

/// What a module gets to send with, for as long as its instance is in use.
///
/// Once retired, nothing new is sent, and a read under way fails at once with
/// [Unreachable], so that no late answer arrives; it is not sent after a
/// sign-in it was waiting for either. A write or sign-in under way is neither
/// cancelled nor repeated, and its outcome is reported.
final class InstanceLease implements ServiceHttpClient, SessionAuthenticator {
  /// Creates a lease of [link].
  InstanceLease(this.link);

  /// The session leased.
  final SessionLink link;

  final _reads = <Completer<Result<ServiceResponse, HttpError>>>{};
  var _retired = false;
  var _outdated = false;

  static const _cancelled = Err<ServiceResponse, HttpError>(
    HttpError(Unreachable()),
  );

  /// Whether the lease is in use.
  bool get isCurrent => !_retired;

  /// Whether it was retired because the instance was edited or removed.
  bool get isOutdated => _outdated;

  /// Ends the lease. [outdated] if the instance was edited or removed.
  void retire({required bool outdated}) {
    if (_retired) return;
    _retired = true;
    _outdated = outdated;
    for (final read in _reads) {
      read.complete(_cancelled);
    }
    _reads.clear();
    link.release();
  }

  @override
  Future<Result<ServiceResponse, HttpError>> send(ServiceRequest request) {
    if (_retired) return Future.value(_cancelled);
    if (request.method != HttpMethod.get) {
      return link.hold(() => link.session.send(request));
    }
    final read = Completer<Result<ServiceResponse, HttpError>>();
    _reads.add(read);
    Future<Result<ServiceResponse, HttpError>> ask() =>
        link.session.send(request, abandoned: () => _retired);
    final sent = link.signsIn ? link.hold(ask) : ask();
    // Neither completes it if retiring has done so.
    unawaited(
      sent.then(
        (result) {
          if (_reads.remove(read)) read.complete(result);
        },
        onError: (Object error, StackTrace stackTrace) {
          if (_reads.remove(read)) read.completeError(error, stackTrace);
        },
      ),
    );
    return read.future;
  }

  @override
  ServiceResult<void> login() => _retired
      ? Future.value(const Err(Unreachable()))
      : link.hold(link.session.login);
}

/// The cache of a leased instance. Once the instance has been edited or
/// removed, what a module still has from before is not stored.
final class LeasedCache implements CacheScope {
  /// The cache [_cache] as long as [_lease] is not outdated.
  LeasedCache(this._cache, this._lease);

  final CacheScope _cache;
  final InstanceLease _lease;

  @override
  Future<CacheSnapshot?> read(MediaKind kind, {int? parentRemoteId}) =>
      _cache.read(kind, parentRemoteId: parentRemoteId);

  @override
  Future<CacheEntry?> entry(MediaKind kind, int remoteId) =>
      _cache.entry(kind, remoteId);

  @override
  Future<void> replace(
    MediaKind kind,
    List<CacheEntry> entries, {
    int? parentRemoteId,
  }) => _write(
    () => _cache.replace(kind, entries, parentRemoteId: parentRemoteId),
  );

  @override
  Future<void> put(CacheEntry entry) => _write(() => _cache.put(entry));

  @override
  Future<void> remove(MediaKind kind, int remoteId) =>
      _write(() => _cache.remove(kind, remoteId));

  Future<void> _write(Future<void> Function() write) =>
      _lease.isOutdated ? Future.value() : write();
}
