import '../../models/bulk_edit.dart';
import '../../models/credit.dart';
import '../../models/item_edit.dart';
import '../../models/item_ref.dart';
import '../../models/library_item.dart';
import '../../models/media_file.dart';
import '../../models/media_kind.dart';
import '../../models/media_target.dart';
import '../../models/monitor_option.dart';
import '../../models/server_option.dart';
import '../capability.dart';
import '../module_route.dart';
import '../service_result.dart';

/// Browsing and managing a library.
abstract interface class LibraryProvider implements Capability {
  /// The kind of the top-level items.
  MediaKind get itemKind;

  /// What [applyMonitorOption] accepts; empty where the service has none.
  List<MonitorOption> get monitorOptions;

  ServiceResult<List<LibraryItem>> list();

  /// The contract's `get`.
  ServiceResult<LibraryItem> item(ItemRef ref);

  /// For example a series' episodes or an artist's albums.
  ServiceResult<List<LibraryItem>> children(ItemRef parent);

  ServiceResult<List<MediaFile>> files(ItemRef ref);

  ServiceResult<List<ServerOption>> options();

  /// Empty where the server provides none.
  ServiceResult<List<Credit>> credits(ItemRef ref);

  ServiceResult<void> setMonitored(MediaTarget target, bool monitored);

  ServiceResult<void> applyMonitorOption(ItemRef ref, String optionId);

  /// Applies only the fields set in [changes] to the current server state.
  ServiceResult<void> edit(ItemRef ref, ItemEdit changes);

  ServiceResult<void> bulkEdit(List<ItemRef> refs, BulkEdit changes);

  ServiceResult<void> delete(
    ItemRef ref, {
    required bool deleteFiles,
    required bool addImportExclusion,
  });

  ServiceResult<void> deleteFile(MediaFile file);

  ModuleRoute detailRoute(ItemRef ref);
}
