import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../../../app/providers.dart';
import '../../../src/l10n/generated/app_localizations.dart';
import 'change_instance.dart';

typedef _Problem = String Function(AppLocalizations strings);

/// Asks for a new name of [instance] and saves it. Stays open, saying why, while
/// the name is refused.
Future<void> showRenameInstanceDialog(
  BuildContext context,
  WidgetRef ref,
  Instance instance,
) {
  final services = ref.read(appServicesProvider);
  Future<_Problem?> save(String name) async {
    try {
      final refused = await changeInstance(
        services.profiles,
        instance.id,
        name: name,
      );
      return switch (refused) {
        null => null,
        RuleViolation.nameLength => (
          AppLocalizations strings,
        ) => strings.serviceNameLength,
        RuleViolation.nameTaken => (
          AppLocalizations strings,
        ) => strings.serviceNameTaken,
        _ => (AppLocalizations strings) => strings.changeFailed,
      };
    } catch (error) {
      services.log.log(
        LogLevel.warning,
        'A service could not be renamed (${error.runtimeType})',
      );
      return (AppLocalizations strings) => strings.changeFailed;
    }
  }

  return showDialog<void>(
    context: context,
    builder: (context) => _RenameDialog(name: instance.name, save: save),
  );
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.name, required this.save});

  final String name;

  /// Null once the name is saved, and otherwise why it was not.
  final Future<_Problem?> Function(String name) save;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _controller = TextEditingController.fromValue(
    TextEditingValue(
      text: widget.name,
      selection: TextSelection(baseOffset: 0, extentOffset: widget.name.length),
    ),
  );
  _Problem? _problem;
  var _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    final name = _controller.text.trim();
    if (name == widget.name) return Navigator.pop(context);
    setState(() => _saving = true);
    final problem = await widget.save(name);
    // Cancelled meanwhile.
    if (!mounted || !(ModalRoute.isCurrentOf(context) ?? false)) return;
    if (problem == null) return Navigator.pop(context);
    setState(() {
      _saving = false;
      _problem = problem;
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return AlertDialog(
      scrollable: true,
      title: Text(strings.renameServiceTitle),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          labelText: strings.serviceName,
          errorText: _problem?.call(strings),
          errorMaxLines: 3,
        ),
        // Without this the keyboard closes while the name may be refused.
        onEditingComplete: _submit,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(UiLocalizations.of(context).cancel),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: Text(strings.save),
        ),
      ],
    );
  }
}
