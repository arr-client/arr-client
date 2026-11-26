import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import 'active_downloads_section.dart';
import 'areas_section.dart';
import 'disk_space_section.dart';
import 'downloaded_today_section.dart';
import 'health_section.dart';
import 'home_freshness.dart';
import 'recently_added_section.dart';
import 'refresh_home.dart';
import 'services_section.dart';
import 'upcoming_section.dart';

/// Home of a profile that has instances: a list of sections
/// (contracts/navigation.md). Each is a sliver that watches what it shows, and
/// is there only if a service provides it, so that one loads, fails and is
/// retried without waiting for another.
class HomeOverview extends ConsumerWidget {
  const HomeOverview({required this.instances, super.key});

  /// All of the active profile, in their order.
  final List<Instance> instances;

  @override
  Widget build(BuildContext context, WidgetRef ref) => LayoutBuilder(
    builder: (context, constraints) => ListTileTheme.merge(
      contentPadding: EdgeInsets.symmetric(
        horizontal: screenMargin(constraints.maxWidth),
      ),
      child: HomeFreshness(
        child: RefreshIndicator(
          onRefresh: () => refreshHome(ref),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverSafeArea(
                top: false,
                sliver: SliverMainAxisGroup(
                  slivers: [
                    const UpcomingSection(),
                    const DownloadedTodaySection(),
                    const RecentlyAddedSection(),
                    const ActiveDownloadsSection(),
                    const HealthSection(),
                    const DiskSpaceSection(),
                    ServicesSection(instances: instances),
                    const AreasSection(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
