/// The paths of the app's own routes. Module screens have theirs from
/// `ModuleRoute`.
library;

import 'package:core/core.dart';

import 'destinations.dart';

/// Where a destination is.
String destinationLocation(AppDestination destination) => switch (destination) {
  AppDestination.home => '/',
  AppDestination.library => '/library',
  AppDestination.discover => '/discover',
  AppDestination.activity => '/activity',
  AppDestination.more => '/more',
};

/// The path of a page of More, relative to it.
String morePath(MoreEntry entry) => switch (entry) {
  MoreEntry.calendar => 'calendar',
  MoreEntry.wanted => 'wanted',
  MoreEntry.blocklist => 'blocklist',
  MoreEntry.subtitles => 'subtitles',
  MoreEntry.indexerSearch => 'indexer-search',
  MoreEntry.services => 'services',
  MoreEntry.settings => 'settings',
};

/// Where a page of More is.
String moreLocation(MoreEntry entry) =>
    '${destinationLocation(AppDestination.more)}/${morePath(entry)}';

/// The app-wide search.
const searchLocation = '/search';

/// The add flow, in which the instance is still to be chosen.
const addLocation = '/add';

/// The form that adds a service to the active profile.
const addInstanceLocation = '/services/add';

/// The path of the form that edits a saved service, enabled or not and of any
/// profile, with the parameter `instanceId`. It is not under `/instances/`,
/// whose routes only show an instance that can be used.
const editInstancePath = '/services/:instanceId/edit';

/// Where the form that edits [instanceId] is.
String editInstanceLocation(String instanceId) =>
    Uri(path: '/services/$instanceId/edit').toString();

/// Where the form that adds a service of [serviceType] is, once chosen.
String addServiceFormLocation(String serviceType) =>
    '$addInstanceLocation/$serviceType';

/// The path, under an instance, of the page that stands for an item's screen
/// until its module has one. Module paths start with the module's id.
const itemPlaceholderPath = 'item';

/// Where that page is for the item called [title].
String itemPlaceholderLocation(String instanceId, String title) => Uri(
  path: '/instances/$instanceId/$itemPlaceholderPath',
  queryParameters: {'title': title},
).toString();

/// Where profiles are managed.
const profilesLocation = '/profiles';

/// A shared flow about an item of one instance. No module's paths can collide
/// with these, as theirs start with the module's id.
enum InstanceFlow { releases, edit, delete, history }

/// Where [flow] is for an instance.
String instanceFlowLocation(String instanceId, InstanceFlow flow) =>
    Uri(path: '/instances/$instanceId/${flow.name}').toString();

/// Where the history of [ref] is.
String itemHistoryLocation(ItemRef ref) => Uri(
  path: instanceFlowLocation(ref.instanceId, InstanceFlow.history),
  queryParameters: _itemQuery(ref),
).toString();

/// Where the release search for [target] is.
String releasesLocation(MediaTarget target) => Uri(
  path: instanceFlowLocation(target.item.instanceId, InstanceFlow.releases),
  queryParameters: {
    ..._itemQuery(target.item),
    if (target.seasonNumber case final number?) 'season': '$number',
  },
).toString();

/// What the query of a [releasesLocation] names, or null if it names nothing.
/// A season that cannot be read is not left out, which would widen the search.
MediaTarget? releaseTarget(String instanceId, Map<String, String> query) {
  final item = itemQueryRef(instanceId, query);
  if (item == null) return null;
  final season = query['season'];
  if (season == null) return MediaTarget(item);
  final number = int.tryParse(season);
  return number == null ? null : MediaTarget(item, seasonNumber: number);
}

Map<String, String> _itemQuery(ItemRef ref) => {
  'kind': ref.kind.name,
  'item': '${ref.remoteId}',
};

/// The item that the query of an [itemHistoryLocation] or a [releasesLocation]
/// names, or null if it names none.
ItemRef? itemQueryRef(String instanceId, Map<String, String> query) {
  final kind = MediaKind.values.asNameMap()[query['kind']];
  final id = int.tryParse(query['item'] ?? '');
  return kind == null || id == null
      ? null
      : ItemRef(instanceId: instanceId, kind: kind, remoteId: id);
}

/// Where the entry [queueId] of an instance's queue is. No module's paths can
/// collide with it, as theirs start with the module's id.
String queueEntryLocation(String instanceId, int queueId) =>
    Uri(path: '/instances/$instanceId/queue/$queueId').toString();
