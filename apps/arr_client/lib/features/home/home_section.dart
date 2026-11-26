import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../../src/l10n/generated/app_localizations.dart';
import '../calendar/calendar_tiles.dart';
import '../calendar/service_answer.dart';

/// How many rows a section of Home lists before it leaves the rest to the
/// screen it links to.
const homeRowLimit = 5;

/// The margin of the rows of Home, which its other parts line up with.
EdgeInsetsGeometry _margin(BuildContext context) =>
    ListTileTheme.of(context).contentPadding ?? EdgeInsets.zero;

/// One titled part of Home, as a sliver. The title is a heading for screen
/// readers, and every row stays a thing of its own to them.
class HomeSection extends StatelessWidget {
  const HomeSection({required this.title, required this.children, super.key});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SliverList.list(
    children: [
      Padding(
        padding: _margin(context)
            .add(const EdgeInsets.only(top: 16, bottom: 8)),
        child: Semantics(
          header: true,
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
      ),
      ...children,
    ],
  );
}

/// A heading within a section, such as a day.
class HomeSubheading extends StatelessWidget {
  const HomeSubheading(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: _margin(context).add(const EdgeInsets.only(top: 8, bottom: 4)),
    child: Semantics(
      header: true,
      child: Text(text, style: Theme.of(context).textTheme.titleSmall),
    ),
  );
}

/// A quiet line of text, such as that a section has nothing.
class HomeNote extends StatelessWidget {
  const HomeNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: _margin(context).add(const EdgeInsets.symmetric(vertical: 8)),
      child: Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// The button below a section that leads to all of it.
class HomeSectionLink extends StatelessWidget {
  const HomeSectionLink({
    required this.label,
    required this.onPressed,
    super.key,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: TextButton(onPressed: onPressed, child: Text(label)),
    ),
  );
}

/// What a section says of the services it reads from, above what they gave: a
/// notice with a retry for each that failed, a bar for each that has not
/// answered yet, and one while what is shown is read again.
List<Widget> homeServiceStates<T>(
  BuildContext context,
  ServiceAnswers<T> answers, {
  required void Function(String instanceId) onRetry,
}) => [
  for (final answer in answers)
    if (answer.failure != null)
      ServiceNotice<T>(
        key: ValueKey(answer.instanceId),
        answer: answer,
        onRetry: () => onRetry(answer.instanceId),
      )
    else if (answer.loading && answer.value == null)
      Padding(
        key: ValueKey(answer.instanceId),
        padding: _margin(context).add(const EdgeInsets.symmetric(vertical: 8)),
        child: LinearProgressIndicator(
          semanticsLabel: AppLocalizations.of(context)
              .homeLoadingService(answer.name),
        ),
      ),
  if (answers.any((answer) => answer.loading && answer.value != null))
    LinearProgressIndicator(
      semanticsLabel: UiLocalizations.of(context).loading,
    ),
];

/// What the services of one section have given between them.
extension HomeAnswers<T> on ServiceAnswers<T> {
  /// Whether any has given something, without which "nothing" would not be
  /// true.
  bool get anyRead => any((answer) => answer.value != null);

  /// Whether all have given something and none failed since.
  bool get allRead =>
      every((answer) => answer.value != null && answer.failure == null);
}
