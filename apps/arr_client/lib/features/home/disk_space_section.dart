import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../../src/l10n/generated/app_localizations.dart';
import 'home_data.dart';
import 'home_section.dart';

/// The free space of the disks of each server that reports them.
class DiskSpaceSection extends ConsumerWidget {
  const DiskSpaceSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppLocalizations.of(context);
    final answers = ref.watch(diskSpaceProvider);
    if (answers == null || answers.isEmpty) return const SliverToBoxAdapter();

    return HomeSection(
      title: strings.homeDiskSpace,
      children: [
        ...homeServiceStates(
          context,
          answers,
          onRetry: (id) => unawaited(
            ref.read(diskSpaceProvider.notifier).reload(instanceId: id),
          ),
        ),
        for (final answer in answers)
          if (answer.value case final disks?) ...[
            if (answers.length > 1) HomeSubheading(answer.name),
            for (final disk in disks) _DiskTile(disk: disk),
            if (disks.isEmpty) HomeNote(strings.homeNoDisks),
          ],
      ],
    );
  }
}

class _DiskTile extends StatelessWidget {
  const _DiskTile({required this.disk});

  final DiskSpace disk;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    // A server that does not know the size gives 0: no bar is drawn then.
    final used = disk.total > 0
        ? ((disk.total - disk.free) / disk.total).clamp(0.0, 1.0)
        : null;
    return MergeSemantics(
      child: ListTile(
        leading: const Icon(Icons.storage_outlined),
        title: Text(disk.path),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              used == null
                  ? strings.homeDiskFree(formatBytes(context, disk.free))
                  : strings.homeDiskFreeOf(
                      formatBytes(context, disk.free),
                      formatBytes(context, disk.total),
                    ),
            ),
            if (used != null) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: used,
                semanticsLabel: strings.homeDiskUsed,
                semanticsValue: NumberFormat.percentPattern(
                  Localizations.localeOf(context).toString(),
                ).format(used),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
