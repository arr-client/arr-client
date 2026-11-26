import 'package:core/core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

/// A title with its year, which tells two items of one name apart.
String itemName(LibraryItem item) => switch (item.year) {
  // A year is a name, not a quantity: no grouping.
  final year? => '${item.title} ($year)',
  null => item.title,
};

/// What went wrong, marked by an icon as well as colour and announced.
class Problem extends StatelessWidget {
  const Problem(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
      const SizedBox(width: 8),
      Expanded(child: Semantics(liveRegion: true, child: Text(message))),
    ],
  );
}

/// Shown while the server is asked what the flow needs.
class Waiting extends StatelessWidget {
  const Waiting({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Center(
      heightFactor: 1,
      child: CircularProgressIndicator(
        semanticsLabel: UiLocalizations.of(context).loading,
      ),
    ),
  );
}

/// What to say about a failed read or change of an item.
String itemFailure(BuildContext context, ServiceFailure failure) =>
    failure is NotFound
    ? UiLocalizations.of(context).itemGone
    : failureMessage(context, failure);
