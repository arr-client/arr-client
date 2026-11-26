/// The paths of the app's own routes. Module screens have theirs from
/// `ModuleRoute`.
library;

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

/// A shared flow about an item of one instance. No module's paths can collide
/// with these, as theirs start with the module's id.
enum InstanceFlow { releases, edit, delete, history }

/// Where [flow] is for an instance.
String instanceFlowLocation(String instanceId, InstanceFlow flow) =>
    Uri(path: '/instances/$instanceId/${flow.name}').toString();

/// Where the entry [queueId] of an instance's queue is. No module's paths can
/// collide with it, as theirs start with the module's id.
String queueEntryLocation(String instanceId, int queueId) =>
    Uri(path: '/instances/$instanceId/queue/$queueId').toString();
