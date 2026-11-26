import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../src/l10n/generated/app_localizations.dart';
import 'home_data.dart';
import 'home_section.dart';
import 'open_link.dart';

/// The problems the servers report, read only: each with the server's message
/// and, where it gives one, its help page. Errors come first, and all of them
/// are listed.
class HealthSection extends ConsumerWidget {
  const HealthSection({super.key});

  static const _order = [
    HealthLevel.error,
    HealthLevel.warning,
    HealthLevel.unknown,
    HealthLevel.notice,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppLocalizations.of(context);
    final answers = ref.watch(healthProvider);
    if (answers == null || answers.isEmpty) return const SliverToBoxAdapter();
    final issues = [
      for (final level in _order)
        for (final answer in answers)
          for (final issue in answer.value ?? const <HealthIssue>[])
            if (issue.level == level) (answer.name, issue),
    ];

    return HomeSection(
      title: strings.homeHealth,
      children: [
        ...homeServiceStates(
          context,
          answers,
          onRetry: (id) => unawaited(
            ref.read(healthProvider.notifier).reload(instanceId: id),
          ),
        ),
        for (final (service, issue) in issues)
          _IssueTile(
            issue: issue,
            service: answers.length > 1 ? service : null,
          ),
        if (issues.isEmpty && answers.anyRead)
          HomeNote(
            answers.allRead
                ? strings.homeNoProblems
                : strings.homeNoProblemsKnown,
          ),
      ],
    );
  }
}

class _IssueTile extends StatelessWidget {
  const _IssueTile({required this.issue, required this.service});

  final HealthIssue issue;

  /// Whose it is, where there is more than one.
  final String? service;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final (icon, color, level) = switch (issue.level) {
      HealthLevel.error => (
        Icons.error_outline,
        colors.error,
        strings.homeHealthError,
      ),
      HealthLevel.warning => (
        Icons.warning_amber_outlined,
        colors.tertiary,
        strings.homeHealthWarning,
      ),
      HealthLevel.notice => (
        Icons.info_outline,
        colors.onSurfaceVariant,
        strings.homeHealthNotice,
      ),
      HealthLevel.unknown => (
        Icons.help_outline,
        colors.onSurfaceVariant,
        strings.homeHealthUnknown,
      ),
    };
    final url = issue.helpUrl;
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(issue.message),
      subtitle: Text([level, ?service].join(' · ')),
      trailing: url == null || !isWebPage(url)
          ? null
          : IconButton(
              icon: const Icon(Icons.open_in_new),
              tooltip: strings.homeHealthHelp(issue.message),
              onPressed: () => unawaited(openWebPage(context, url)),
            ),
    );
  }
}
