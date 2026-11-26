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
  library<LibraryProvider>(),
  lookup<LookupProvider>(),
  command<CommandProvider>(),
  release<ReleaseProvider>(),
  queue<QueueProvider>(),
  history<HistoryProvider>(),
  wanted<WantedProvider>(),
  calendar<CalendarProvider>(),
  health<HealthProvider>(),
  indexerSearch<IndexerSearchProvider>(),
  downloadProgress<DownloadProgressProvider>(),
  discovery<DiscoveryProvider>(),
  request<RequestProvider>(),
  subtitle<SubtitleProvider>();

  /// [module]'s implementation of this capability for one instance.
  T? of(ServiceModule module, InstanceContext context) =>
      module.capability<T>(context);
}
