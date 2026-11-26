import 'package:core/core.dart';
import 'package:material_ui/material_ui.dart';

import '../../../src/l10n/generated/app_localizations.dart';

/// The choices of a removal, each saying what it leads to as it now stands.
class RemoveChoices extends StatefulWidget {
  const RemoveChoices({
    required this.initial,
    required this.onChanged,
    required this.hasDownload,
    required this.hasWaiting,
    super.key,
  });

  final RemoveOptions initial;

  final ValueChanged<RemoveOptions> onChanged;

  /// Whether any entry has something in a download client.
  final bool hasDownload;

  /// Whether any entry is a release still held back.
  final bool hasWaiting;

  @override
  State<RemoveChoices> createState() => _RemoveChoicesState();
}

class _RemoveChoicesState extends State<RemoveChoices> {
  late var _removeFromClient = widget.initial.removeFromClient;
  late var _blocklist = widget.initial.blocklist;
  late var _search = widget.initial.searchReplacement;

  void _changed(VoidCallback change) {
    setState(change);
    widget.onChanged(
      RemoveOptions(
        removeFromClient: _removeFromClient,
        blocklist: _blocklist,
        searchReplacement: _search,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    Widget choice({
      required bool value,
      required String title,
      required String effect,
      required void Function(bool value) set,
    }) => CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      value: value,
      title: Text(title),
      subtitle: Text(effect),
      onChanged: (value) => _changed(() => set(value ?? false)),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.hasDownload) ...[
          choice(
            value: _removeFromClient,
            title: strings.queueRemoveFromClient,
            effect: _removeFromClient
                ? strings.queueRemoveFromClientOn
                : strings.queueRemoveFromClientOff,
            set: (value) => _removeFromClient = value,
          ),
          if (widget.hasWaiting) Text(strings.queueWaitingHaveNoDownload),
        ],
        choice(
          value: _blocklist,
          title: strings.queueBlocklist,
          effect: _blocklist
              ? strings.queueBlocklistOn
              : strings.queueBlocklistOff,
          set: (value) => _blocklist = value,
        ),
        // The server makes no choice about this for a release it never grabbed.
        if (_blocklist && widget.hasDownload)
          choice(
            value: _search,
            title: strings.queueSearchReplacement,
            effect: _search
                ? strings.queueSearchReplacementOn
                : strings.queueSearchReplacementOff,
            set: (value) => _search = value,
          ),
      ],
    );
  }
}
