/// Bazarr service module for arr-client.
library;

import 'package:core/core.dart';
import 'package:flutter/widgets.dart';

import 'src/adapters/probe.dart';
import 'src/adapters/subtitles.dart';
import 'src/api/bazarr_api.dart';

/// The Bazarr service.
final class BazarrModule implements ServiceModule {
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
      const (SubtitleProvider) => BazarrSubtitleProvider(
        BazarrApi(context.http),
        context.instance.id,
      ),
      _ => null,
    };
    return found as T?;
  }

  // The screens are not built yet.
  @override
  List<ModuleScreen> routes() => const [];
}
