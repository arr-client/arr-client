import '../../cache/cached.dart';
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
///
/// [list], [item] and [children] store what they fetch in the instance's cache.
/// The `cached` reads return it without any network request, for offline and
/// first display. They complete with null if it was never fetched.
abstract interface class LibraryProvider implements Capability {
  /// The kind of the top-level items.
  MediaKind get itemKind;

  /// What [applyMonitorOption] accepts; empty where the service has none.
  List<MonitorOption> get monitorOptions;

  /// All top-level items, from the server.
  ServiceResult<List<LibraryItem>> list();

  /// The contract's `get`.
  ServiceResult<LibraryItem> item(ItemRef ref);

  /// For example a series' episodes or an artist's albums.
  ServiceResult<List<LibraryItem>> children(ItemRef parent);

  /// What [list] last fetched.
  ServiceResult<Cached<List<LibraryItem>>?> cachedList();

  /// The item as last fetched.
  ServiceResult<Cached<LibraryItem>?> cachedItem(ItemRef ref);

  /// What [children] last fetched.
  ServiceResult<Cached<List<LibraryItem>>?> cachedChildren(ItemRef parent);

  /// The files of an item.
  ServiceResult<List<MediaFile>> files(ItemRef ref);

  /// Profiles, root folders and tags.
  ServiceResult<List<ServerOption>> options();

  /// Empty where the server provides none.
  ServiceResult<List<Credit>> credits(ItemRef ref);

  /// Turns monitoring of [target] on or off.
  ServiceResult<void> setMonitored(MediaTarget target, bool monitored);

  /// Applies one of [monitorOptions].
  ServiceResult<void> applyMonitorOption(ItemRef ref, String optionId);

  /// Applies only the fields set in [changes] to the current server state.
  ServiceResult<void> edit(ItemRef ref, ItemEdit changes);

  /// Changes several items.
  ServiceResult<void> bulkEdit(List<ItemRef> refs, BulkEdit changes);

  /// Deletes an item.
  ServiceResult<void> delete(
    ItemRef ref, {
    required bool deleteFiles,
    required bool addImportExclusion,
  });

  /// Deletes one file of an item.
  ServiceResult<void> deleteFile(MediaFile file);

  /// The screen of an item.
  ModuleRoute detailRoute(ItemRef ref);
}
