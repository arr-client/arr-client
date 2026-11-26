import 'package:material_ui/material_ui.dart';

/// One titled part of Home, as a sliver. The title is a heading for screen
/// readers, and every row stays a thing of its own to them.
class HomeSection extends StatelessWidget {
  const HomeSection({required this.title, required this.children, super.key});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    // The margin of the rows below, so that the title lines up with them.
    final margin = ListTileTheme.of(context).contentPadding ?? EdgeInsets.zero;
    return SliverList.list(
      children: [
        Padding(
          padding: margin.add(const EdgeInsets.only(top: 16, bottom: 8)),
          child: Semantics(
            header: true,
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
        ),
        ...children,
      ],
    );
  }
}
