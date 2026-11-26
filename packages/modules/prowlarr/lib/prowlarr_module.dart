/// Prowlarr service module for arr-client.
library;

import 'dart:convert';

import 'package:core/core.dart';
import 'package:flutter/widgets.dart';
import 'package:servarr/servarr.dart';

import 'src/adapters/indexer_search.dart';
import 'src/screens/indexer_screen.dart';
import 'src/screens/prowlarr_source.dart';
import 'src/search_route.dart';

// The app adds its delegate to the others, for the strings of the screens.
export 'src/l10n/generated/prowlarr_localizations.dart'
    show ProwlarrLocalizations;

// Also Prowlarr's `appName` in `system/status`.
const _product = 'Prowlarr';

const _apiPath = 'api/v1';

const _minimumVersion = '1.0';
const _testedVersion = '3.1.0.5799';

// At most nine digits a number, so that each fits an int.
final _versionPattern = RegExp(r'^\d{1,9}(\.\d{1,9})*$');

/// The Prowlarr service.
final class ProwlarrModule implements ServiceModule {
  // One for each connection to an instance, which is its client: the app may
  // build the context anew while a screen is open, as after a rename. The
  // screens' state is kept under it.
  final _sources = Expando<ProwlarrSource>();

  @override
  String get id => 'prowlarr';

  @override
  ModuleDescriptor get descriptor => const ModuleDescriptor(
    displayName: _product,
    // Material's `travel_explore_outlined`; widgets.dart has no named icons.
    icon: IconData(0xf45f, fontFamily: 'MaterialIcons'),
    category: ModuleCategory.indexers,
    authKinds: [AuthKind.apiKey],
    apiKeyHeader: ApiKeyHeader('X-Api-Key'),
    defaultPort: 9696,
    minimumVersion: _minimumVersion,
    testedVersion: _testedVersion,
  );

  @override
  SessionHandler? get sessionHandler => null;

  @override
  ServiceResult<ProbeResult> probe(InstanceContext context) async {
    final answer = await context.http.send(
      ServiceRequest(HttpMethod.get, '$_apiPath/system/status'),
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
  ) => const {CapabilityKind.indexerSearch, CapabilityKind.health};

  @override
  T? capability<T extends Capability>(InstanceContext context) {
    final Capability? found = switch (T) {
      const (IndexerSearchProvider) => ProwlarrIndexerSearchAdapter(
        _client(context),
        context.instance.id,
      ),
      const (HealthProvider) => ServarrHealth(
        _client(context),
        providesDiskSpace: false,
      ),
      _ => null,
    };
    return found as T?;
  }

  @override
  List<ModuleScreen> routes() => [
    ModuleScreen(path: searchPattern, builder: _search),
  ];

  Widget _search(
    BuildContext context,
    InstanceContext instance,
    Map<String, String> parameters,
  ) => IndexerScreen(
    source: _sources[instance.http] ??= ProwlarrSource(
      instanceId: instance.instance.id,
      provider: ProwlarrIndexerSearchAdapter(
        _client(instance),
        instance.instance.id,
      ),
      logger: instance.logger,
    ),
    name: instance.instance.name,
  );
}

// Prowlarr has no queue or history of media, so nothing reads the flag for
// unknown downloads or the ids of a record.
ServarrClient _client(InstanceContext context) => ServarrClient(
  context.http,
  apiPath: _apiPath,
  includeUnknownParameter: '',
  refs: (_) => (item: null, parent: null),
);

ServiceFailure _classify(HttpError error) {
  // ASP.NET Core's host filtering answers before Prowlarr sees the request.
  if (error.response case final response?
      when response.statusCode == 400 &&
          response.text.contains('Invalid Hostname')) {
    return const HostRejected();
  }
  // Every supported Prowlarr has the path, so this is something else.
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
  // Other services of the family answer the same path. The product is judged
  // first: another one's versions mean nothing here.
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
