import 'package:core/core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import 'areas_section.dart';
import 'services_section.dart';

/// Home of a profile that has instances: a list of sections
/// (contracts/navigation.md). Each is a sliver that watches what it shows, so
/// that more of them go in without waiting for one another.
class HomeOverview extends StatelessWidget {
  const HomeOverview({required this.instances, super.key});

  /// All of the active profile, in their order.
  final List<Instance> instances;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => ListTileTheme.merge(
      contentPadding: EdgeInsets.symmetric(
        horizontal: screenMargin(constraints.maxWidth),
      ),
      child: CustomScrollView(
        slivers: [
          SliverSafeArea(
            top: false,
            sliver: SliverMainAxisGroup(
              slivers: [
                ServicesSection(instances: instances),
                const AreasSection(),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
