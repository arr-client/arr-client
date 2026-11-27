/// Bazarr service module for arr-client.
library;

import 'package:core/core.dart';
import 'package:flutter/widgets.dart';

import 'src/adapters/probe.dart';
import 'src/adapters/subtitles.dart';
import 'src/api/bazarr_api.dart';
import 'src/screens/bazarr_screens.dart';
import 'src/screens/bazarr_source.dart';

// The app adds its delegate to the others, for the strings of the screens.
export 'src/l10n/generated/bazarr_localizations.dart' show BazarrLocalizations;

/// The Bazarr service.
final class BazarrModule implements ServiceModule {
  // One for each connection to an instance, which is its client: the app may
  // build the context anew while a screen is open, as after a rename. The
  // screens' state is kept under it.
  final _sources = Expando<BazarrSource>();

  @override
  String get id => 'bazarr';

  @override
  ModuleDescriptor get descriptor => const ModuleDescriptor(
    displayName: 'Bazarr',
    // Material's `subtitles_outlined`; widgets.dart has no named icons.
    icon: IconData(0xf3fd, fontFamily: 'MaterialIcons'),
    category: ModuleCategory.subtitles,
    authKinds: [AuthKind.apiKey],
    apiKeyHeader: ApiKeyHeader('X-API-KEY'),
    defaultPort: 6767,
    minimumVersion: minimumVersion,
    testedVersion: testedVersion,
  );

  @override
  SessionHandler? get sessionHandler => null;

  @override
  ServiceResult<ProbeResult> probe(InstanceContext context) =>
      probeBazarr(context.http);

  // An API key may use everything, in every supported version.
  @override
  Set<CapabilityKind> capabilitiesFor(
    ProbeResult probe,
    SessionInfo? session,
  ) => const {CapabilityKind.subtitle};

  @override
  T? capability<T extends Capability>(InstanceContext context) {
    final Capability? found = switch (T) {
      const (SubtitleProvider) => _provider(context),
      _ => null,
    };
    return found as T?;
  }

  @override
  List<ModuleScreen> routes() => bazarrScreens(_source);

  BazarrSource _source(InstanceContext context) =>
      _sources[context.http] ??= BazarrSource(
        instanceId: context.instance.id,
        provider: _provider(context),
        logger: context.logger,
      );

  BazarrSubtitleProvider _provider(InstanceContext context) =>
      BazarrSubtitleProvider(BazarrApi(context.http), context.instance.id);
}
