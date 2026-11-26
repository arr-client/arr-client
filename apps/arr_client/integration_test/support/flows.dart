/// What a user does in more than one test, through the screens.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'harness.dart';

extension Flows on AppHarness {
  /// From Home on a first launch, or from the list of services, to the form
  /// that adds a service of the kind [service].
  Future<void> openAddForm(String service) async {
    await tap(find.text(strings.addService));
    await tap(find.widgetWithText(ListTile, service));
    await waitFor(find.byKey(const ValueKey('address')));
  }

  /// Fills in the form that is open, with an API key.
  Future<void> fillForm({String? address, String? apiKey, String? name}) async {
    if (address != null) await enter('address', address);
    if (apiKey != null) await enter('apiKey', apiKey);
    if (name != null) await enter('name', name);
  }

  /// Tests what the form holds and waits for a result titled [expected].
  Future<void> testConnection(String expected) async {
    final first = button(strings.formTest);
    await tap(first.evaluate().isEmpty ? button(strings.formTestAgain) : first);
    await waitFor(find.text(expected));
  }

  /// Presses [label] in the form and waits for the form to close.
  Future<void> closeForm(String label) async {
    await tap(button(label));
    await waitUntilGone(find.byKey(const ValueKey('address')));
  }

  /// Adds a service of the kind [service], whose test is expected to find
  /// [product] and [version].
  Future<void> addService(
    String service, {
    required String address,
    required String apiKey,
    required String version,
    String? name,
  }) async {
    await openAddForm(service);
    await fillForm(address: address, apiKey: apiKey, name: name);
    await testConnection(strings.testPassed(service, version));
    await closeForm(strings.formAdd);
  }

  /// To the primary destination [label].
  Future<void> goTo(String label) => tap(destination(label));

  /// To the list of services of the active profile.
  Future<void> openServices() async {
    // The second tap leaves a page of More that was left open.
    await goTo(strings.navMore);
    await goTo(strings.navMore);
    await tap(find.widgetWithText(ListTile, strings.moreServices));
    await waitFor(find.byTooltip(strings.manageProfiles));
  }

  /// Opens the form of the service [name] from the list of services.
  Future<void> editService(String name) async {
    // The row can say the name twice: of the service and of its kind.
    await tap(find.widgetWithText(ListTile, name).first);
    await waitFor(find.byKey(const ValueKey('address')));
  }

  /// Chooses [action] for the service [name] in the list of services.
  Future<void> serviceAction(String name, String action) async {
    await tap(find.byTooltip(strings.serviceOptions(name)));
    await tap(find.text(action));
  }

  /// Chooses [action] for the profile [name] in the list of profiles.
  Future<void> profileAction(String name, String action) async {
    await tap(find.byTooltip(strings.profileOptions(name)));
    await tap(find.text(action));
  }

  /// Switches to the profile [name] with the switcher on Home.
  Future<void> switchProfile(String name) async {
    await goTo(strings.navHome);
    await tap(find.byTooltip(strings.chooseProfile));
    await tap(
      find.ancestor(
        of: find.text(name),
        matching: find.byWidgetPredicate(
          (widget) => widget is CheckedPopupMenuItem,
        ),
      ),
    );
    await waitFor(activeProfile(name));
  }

  /// The name of the active profile on Home.
  Finder activeProfile(String name) => find.descendant(
    of: find.byTooltip(strings.chooseProfile),
    matching: find.text(name),
  );
}
