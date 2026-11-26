import 'capabilities/calendar_provider.dart';
import 'capabilities/command_provider.dart';
import 'capabilities/discovery_provider.dart';
import 'capabilities/download_progress_provider.dart';
import 'capabilities/health_provider.dart';
import 'capabilities/history_provider.dart';
import 'capabilities/indexer_search_provider.dart';
import 'capabilities/library_provider.dart';
import 'capabilities/lookup_provider.dart';
import 'capabilities/queue_provider.dart';
import 'capabilities/release_provider.dart';
import 'capabilities/request_provider.dart';
import 'capabilities/subtitle_provider.dart';
import 'capabilities/wanted_provider.dart';
import 'capability.dart';
import 'instance_context.dart';
import 'service_module.dart';

/// Identifies a capability without building it. The [name] of each value is
/// persisted with the last probe, so values are never renamed.
enum CapabilityKind<T extends Capability> {
  /// [LibraryProvider].
  library<LibraryProvider>(),

  /// [LookupProvider].
  lookup<LookupProvider>(),

  /// [CommandProvider].
  command<CommandProvider>(),

  /// [ReleaseProvider].
  release<ReleaseProvider>(),

  /// [QueueProvider].
  queue<QueueProvider>(),

  /// [HistoryProvider].
  history<HistoryProvider>(),

  /// [WantedProvider].
  wanted<WantedProvider>(),

  /// [CalendarProvider].
  calendar<CalendarProvider>(),

  /// [HealthProvider].
  health<HealthProvider>(),

  /// [IndexerSearchProvider].
  indexerSearch<IndexerSearchProvider>(),

  /// [DownloadProgressProvider].
  downloadProgress<DownloadProgressProvider>(),

  /// [DiscoveryProvider].
  discovery<DiscoveryProvider>(),

  /// [RequestProvider].
  request<RequestProvider>(),

  /// [SubtitleProvider].
  subtitle<SubtitleProvider>();

  /// [module]'s implementation of this capability for one instance.
  T? of(ServiceModule module, InstanceContext context) =>
      module.capability<T>(context);
}
