import 'dart:async';

import 'package:core/core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../../../src/l10n/generated/app_localizations.dart';

/// Saves what the dialog holds. [copyOf] is the id of the profile to copy, or
/// null.
typedef SaveProfile = Future<Result<void, RuleViolation>> Function(
  String name,
  String? copyOf,
);

/// Asks for the name of a profile and saves it with [save]. Stays open, saying
/// why, while that is refused or fails.
///
/// With [sources], it also asks what to start from: nothing, or a copy of one of
/// them; [copyOf] is chosen at first.
Future<void> showProfileDialog(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  required Logger log,
  required SaveProfile save,
  String name = '',
  List<Profile> sources = const [],
  String? copyOf,
}) => showDialog<void>(
  context: context,
  builder: (context) => _ProfileDialog(
    title: title,
    confirmLabel: confirmLabel,
    log: log,
    save: save,
    name: name,
    sources: sources,
    copyOf: copyOf,
  ),
);

/// The choice of an empty profile; no profile has this id.
const _empty = '';

class _ProfileDialog extends StatefulWidget {
  const _ProfileDialog({
    required this.title,
    required this.confirmLabel,
    required this.log,
    required this.save,
    required this.name,
    required this.sources,
    required this.copyOf,
  });

  final String title;
  final String confirmLabel;
  final Logger log;
  final SaveProfile save;
  final String name;
  final List<Profile> sources;
  final String? copyOf;

  @override
  State<_ProfileDialog> createState() => _ProfileDialogState();
}

class _ProfileDialogState extends State<_ProfileDialog> {
  late final _name = TextEditingController.fromValue(
    TextEditingValue(
      text: widget.name,
      selection: TextSelection(baseOffset: 0, extentOffset: widget.name.length),
    ),
  );
  late var _source = widget.copyOf ?? _empty;
  String Function(AppLocalizations strings)? _problem;
  var _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    final name = _name.text.trim();
    // A rename to the same name.
    if (widget.name.isNotEmpty && name == widget.name) {
      return Navigator.pop(context);
    }
    setState(() => _saving = true);
    String Function(AppLocalizations)? problem;
    try {
      final result = await widget.save(
        name,
        _source == _empty ? null : _source,
      );
      if (result case Err(:final error)) {
        problem = (strings) => switch (error) {
          RuleViolation.nameLength => strings.profileNameLength,
          RuleViolation.nameTaken => strings.profileNameTaken,
          _ => strings.changeFailed,
        };
      }
    } catch (error) {
      // The type only: the text of an error may quote an address or a secret.
      widget.log.log(
        LogLevel.warning,
        'A profile could not be saved (${error.runtimeType})',
      );
      problem = (strings) => strings.changeFailed;
    }
    if (!mounted) return;
    if (problem == null) return Navigator.pop(context);
    setState(() {
      _saving = false;
      _problem = problem;
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    // Not left while saving, so that the outcome is always seen.
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        scrollable: true,
        title: Text(widget.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: strings.profileName,
                errorText: _problem?.call(strings),
                errorMaxLines: 3,
              ),
              // Without this the keyboard closes while the name may be refused.
              onEditingComplete: () => unawaited(_submit()),
            ),
            if (widget.sources.isNotEmpty) ...[
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _source,
                isExpanded: true,
                // Grows with large text and long names.
                itemHeight: null,
                decoration: InputDecoration(
                  labelText: strings.profileStartWith,
                ),
                items: [
                  DropdownMenuItem(
                    value: _empty,
                    child: Text(strings.profileStartEmpty),
                  ),
                  for (final profile in widget.sources)
                    DropdownMenuItem(
                      value: profile.id,
                      child: Text(strings.profileStartCopy(profile.name)),
                    ),
                ],
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _source = value ?? _empty),
              ),
              if (_source != _empty) ...[
                const SizedBox(height: 8),
                Text(strings.profileCopyExplanation),
              ],
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: Text(UiLocalizations.of(context).cancel),
          ),
          FilledButton(
            onPressed: _saving ? null : () => unawaited(_submit()),
            child: Text(widget.confirmLabel),
          ),
        ],
      ),
    );
  }
}
