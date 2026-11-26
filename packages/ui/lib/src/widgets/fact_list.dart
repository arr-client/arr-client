import 'package:material_ui/material_ui.dart';

/// Named values, one under the other. The caller leaves out missing ones.
class FactList extends StatelessWidget {
  /// Creates a [FactList].
  const FactList(this.facts, {super.key});

  /// Each localized name and its value.
  final List<(String, String)> facts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (name, value) in facts)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: MergeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(value),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
