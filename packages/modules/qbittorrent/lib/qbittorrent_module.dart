/// qBittorrent service module for arr-client. It signs in and reads, and
/// changes nothing (FR-031).
library;

import 'package:core/core.dart';
import 'package:flutter/widgets.dart';

import 'src/adapters/probe.dart';
import 'src/adapters/progress.dart';
import 'src/api/session_handler.dart';
import 'src/l10n/texts.dart';

// The app adds the delegate to its own, for the texts the module supplies.
export 'src/l10n/generated/qbittorrent_localizations.dart'
    show QbittorrentLocalizations;

const _product = 'qBittorrent';

const _descriptor = ModuleDescriptor(
  displayName: _product,
  // Material's `download_outlined`; widgets.dart has no named icons.
  icon: IconData(0xeff2, fontFamily: 'MaterialIcons'),
  category: ModuleCategory.downloadClient,
  // API keys exist from 5.2.
  authKinds: [AuthKind.apiKey, AuthKind.userPassword],
  // A wrong key gets 403, not 401.
  apiKeyHeader: ApiKeyHeader(
    'Authorization',
    prefix: 'Bearer ',
    rejectionStatus: 403,
  ),
  defaultPort: 8080,
  minimumVersion: '4.4',
  // The version of the dev stack and of the recorded fixtures.
  testedVersion: '5.3.1',
  authNotes: [
    AuthNote(
      authKind: AuthKind.apiKey,
      onlyWithBasicAuth: true,
      text: apiKeyBasicAuthNote,
    ),
    AuthNote(
      authKind: AuthKind.userPassword,
      onlyWithBasicAuth: true,
      text: passwordBasicAuthNote,
    ),
  ],
);

/// The qBittorrent service.
final class QbittorrentModule implements ServiceModule {
  @override
  String get id => 'qbittorrent';

  @override
  ModuleDescriptor get descriptor => _descriptor;

  @override
  SessionHandler? get sessionHandler => const QbittorrentSessionHandler();

  @override
  ServiceResult<ProbeResult> probe(InstanceContext context) => probeQbittorrent(
    context,
    product: _product,
    minimumVersion: _descriptor.minimumVersion,
    testedVersion: _descriptor.testedVersion,
  );

  // Every supported version, and every identity, may read the torrents.
  @override
  Set<CapabilityKind> capabilitiesFor(
    ProbeResult probe,
    SessionInfo? session,
  ) => const {CapabilityKind.downloadProgress};

  @override
  T? capability<T extends Capability>(InstanceContext context) {
    final Capability? found = switch (T) {
      const (DownloadProgressProvider) => QbittorrentProgressAdapter(context),
      _ => null,
    };
    return found as T?;
  }

  @override
  List<ModuleScreen> routes() => const [];
}
