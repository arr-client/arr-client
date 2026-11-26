/// Radarr service module for arr-client.
library;

import 'dart:convert';

import 'package:core/core.dart';
import 'package:flutter/widgets.dart';
import 'package:servarr/servarr.dart';

import 'src/adapters/library.dart';
import 'src/adapters/lookup.dart';
import 'src/adapters/overview.dart';
import 'src/api/radarr_api.dart';

// The app adds its delegate to the others, for the names the module supplies.
export 'src/l10n/generated/radarr_localizations.dart' show RadarrLocalizations;

// Also Radarr's `appName` in `system/status`.
const _product = 'Radarr';

const _minimumVersion = '5.6';
const _testedVersion = '7.0.3.10918';

// At most nine digits a number, so that each fits an int.
final _versionPattern = RegExp(r'^\d{1,9}(\.\d{1,9})*$');

/// The Radarr service.
final class RadarrModule implements ServiceModule {
  @override
  String get id => 'radarr';

  @override
  ModuleDescriptor get descriptor => const ModuleDescriptor(
    displayName: _product,
    // Material's `movie_outlined`; widgets.dart has no named icons.
    icon: IconData(0xf1f5, fontFamily: 'MaterialIcons'),
    category: ModuleCategory.movies,
    authKinds: [AuthKind.apiKey],
    apiKeyHeader: ApiKeyHeader('X-Api-Key'),
    defaultPort: 7878,
    minimumVersion: _minimumVersion,
    testedVersion: _testedVersion,
  );

  @override
  SessionHandler? get sessionHandler => null;

  @override
  ServiceResult<ProbeResult> probe(InstanceContext context) async {
    final answer = await context.http.send(
      ServiceRequest(HttpMethod.get, 'api/v3/system/status'),
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
    CapabilityKind.queue,
    CapabilityKind.history,
    CapabilityKind.wanted,
    CapabilityKind.calendar,
    CapabilityKind.health,
  };

  @override
  T? capability<T extends Capability>(InstanceContext context) {
    final Capability? found = switch (T) {
      const (LibraryProvider) => RadarrLibraryAdapter(
        RadarrApi(context),
        context,
      ),
      const (LookupProvider) => RadarrLookupAdapter(
        RadarrApi(context),
        context.instance.id,
      ),
      const (QueueProvider) => RadarrQueueAdapter(RadarrApi(context)),
      const (HistoryProvider) => RadarrHistoryAdapter(RadarrApi(context)),
      const (CalendarProvider) => RadarrCalendarAdapter(
        RadarrApi(context),
        context.instance.id,
      ),
      const (WantedProvider) => RadarrWantedAdapter(
        RadarrApi(context),
        context.instance.id,
      ),
      // Nothing here is Radarr's own: health and disk space are the family's.
      const (HealthProvider) => ServarrHealth(RadarrApi(context).shared),
      _ => null,
    };
    return found as T?;
  }

  @override
  List<ModuleScreen> routes() => const [];
}

ServiceFailure _classify(HttpError error) {
  // Radarr refuses a host name outside its allowed hosts with a 400 page.
  if (error.response case final response?
      when response.statusCode == 400 &&
          response.text.contains('Invalid Hostname')) {
    return const HostRejected();
  }
  // Every supported Radarr has the path, so this is something else.
  if (error.failure is NotFound) return const WrongService();
  return error.failure;
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
  // Other services of the family answer the same path.
  if (status is! Map<String, Object?> || status['appName'] != _product) {
    return const Err(WrongService());
  }

  final version = status['version'];
  if (version is! String || !_versionPattern.hasMatch(version)) {
    return const Err(MalformedResponse());
  }
  if (_compareVersions(version, _minimumVersion) < 0) {
    return Err(UnsupportedVersion(version: version));
  }
  return Ok(
    ProbeResult(
      product: _product,
      version: version,
      newerThanTested: _compareVersions(version, _testedVersion) > 0,
    ),
  );
}

/// Compares dotted versions number by number; a missing number is zero.
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
