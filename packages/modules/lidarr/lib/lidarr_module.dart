/// Lidarr service module for arr-client.
library;

import 'dart:convert';

import 'package:core/core.dart';
import 'package:flutter/widgets.dart';
import 'package:servarr/servarr.dart';

import 'src/adapters/activity.dart';
import 'src/adapters/library.dart';
import 'src/adapters/lookup.dart';
import 'src/adapters/manage.dart';
import 'src/adapters/overview.dart';
import 'src/api/lidarr_api.dart';

// The app adds the delegate to its own, for the names the module supplies.
export 'src/l10n/generated/lidarr_localizations.dart' show LidarrLocalizations;

const _product = 'Lidarr';

const _descriptor = ModuleDescriptor(
  displayName: _product,
  // Material's `music_note_outlined`; widgets.dart has no named icons.
  icon: IconData(0xf1fb, fontFamily: 'MaterialIcons'),
  category: ModuleCategory.music,
  authKinds: [AuthKind.apiKey],
  apiKeyHeader: ApiKeyHeader('X-Api-Key'),
  defaultPort: 8686,
  minimumVersion: '2.0',
  // The version of the dev stack and of the recorded fixtures.
  testedVersion: '3.1.6.5079',
);

// Few enough digits per part for `int.parse`.
final _versionPattern = RegExp(r'^\d{1,9}(\.\d{1,9})*$');

/// The Lidarr service.
final class LidarrModule implements ServiceModule {
  @override
  String get id => 'lidarr';

  @override
  ModuleDescriptor get descriptor => _descriptor;

  /// Lidarr takes an API key and keeps no session.
  @override
  SessionHandler? get sessionHandler => null;

  @override
  ServiceResult<ProbeResult> probe(InstanceContext context) async {
    final answer = await context.http.send(
      ServiceRequest(HttpMethod.get, 'api/v1/system/status'),
    );
    return switch (answer) {
      Ok(:final value) => _readStatus(value),
      Err(:final error) => Err(_classify(error)),
    };
  }

  // An API key may use everything, in every supported version.
  @override
  Set<CapabilityKind> capabilitiesFor(
    ProbeResult probe,
    SessionInfo? session,
  ) => const {
    CapabilityKind.library,
    CapabilityKind.lookup,
    CapabilityKind.command,
    CapabilityKind.release,
    CapabilityKind.queue,
    CapabilityKind.history,
    CapabilityKind.calendar,
    CapabilityKind.wanted,
    CapabilityKind.health,
  };

  @override
  T? capability<T extends Capability>(InstanceContext context) {
    final Capability? found = switch (T) {
      const (LibraryProvider) => LidarrLibraryAdapter(
        LidarrApi(context),
        context.cache,
      ),
      const (LookupProvider) => LidarrLookupAdapter(LidarrApi(context)),
      const (CommandProvider) => LidarrCommandAdapter(LidarrApi(context)),
      const (ReleaseProvider) => LidarrReleaseAdapter(LidarrApi(context)),
      const (QueueProvider) => LidarrQueueAdapter(LidarrApi(context)),
      const (HistoryProvider) => LidarrHistoryAdapter(LidarrApi(context)),
      const (CalendarProvider) => LidarrCalendarAdapter(LidarrApi(context)),
      const (WantedProvider) => LidarrWantedAdapter(LidarrApi(context)),
      const (HealthProvider) => ServarrHealth(LidarrApi(context).shared),
      _ => null,
    };
    return found as T?;
  }

  @override
  List<ModuleScreen> routes() => throw UnimplementedError('T118');
}

ServiceFailure _classify(HttpError error) {
  final response = error.response;
  // ASP.NET Core's host filtering answers before Lidarr sees the request.
  if (response != null &&
      response.statusCode == 400 &&
      response.text.contains('Invalid Hostname')) {
    return const HostRejected();
  }
  return switch (error.failure) {
    // Whatever has no status resource is not Lidarr.
    NotFound() => const WrongService(),
    final failure => failure,
  };
}

Result<ProbeResult, ServiceFailure> _readStatus(ServiceResponse response) {
  final text = response.text.trimLeft();
  // A web page where data was expected, whatever its content type says.
  if (text.startsWith('<')) return const Err(ProxyInterception());

  final Object? status;
  try {
    status = jsonDecode(text);
  } on FormatException {
    return const Err(MalformedResponse());
  }

  // The product is judged first: another one's versions mean nothing here.
  if (status is! Map<String, Object?> || status['appName'] != _product) {
    return const Err(WrongService());
  }
  final version = status['version'];
  if (version is! String || !_versionPattern.hasMatch(version)) {
    return const Err(MalformedResponse());
  }
  if (_compareVersions(version, _descriptor.minimumVersion) < 0) {
    return Err(UnsupportedVersion(version: version));
  }
  return Ok(
    ProbeResult(
      product: _product,
      version: version,
      newerThanTested: _compareVersions(version, _descriptor.testedVersion) > 0,
    ),
  );
}

/// Compares dotted versions part by part as numbers; a missing part is zero.
int _compareVersions(String a, String b) {
  final left = a.split('.').map(int.parse).toList();
  final right = b.split('.').map(int.parse).toList();
  for (var i = 0; i < left.length || i < right.length; i++) {
    final order = (i < left.length ? left[i] : 0).compareTo(
      i < right.length ? right[i] : 0,
    );
    if (order != 0) return order;
  }
  return 0;
}
