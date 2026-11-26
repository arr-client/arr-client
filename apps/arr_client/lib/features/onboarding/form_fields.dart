/// The inputs of the add and edit form.
library;

import 'package:material_ui/material_ui.dart';

import '../../src/l10n/generated/app_localizations.dart';

/// A text field for something typed exactly: no correction, suggestions or
/// capitals. A [secret] one is hidden until the user asks to see it.
class EntryField extends StatefulWidget {
  const EntryField({
    required this.controller,
    required this.label,
    required this.onChanged,
    this.secret = false,
    this.helper,
    this.errorText,
    this.validator,
    this.keyboardType,
    this.textInputAction = TextInputAction.next,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final ValueChanged<String> onChanged;
  final bool secret;
  final String? helper;

  /// An error from elsewhere than [validator].
  final String? errorText;
  final FormFieldValidator<String>? validator;
  final TextInputType? keyboardType;
  final TextInputAction textInputAction;

  @override
  State<EntryField> createState() => _EntryFieldState();
}

class _EntryFieldState extends State<EntryField> {
  var _shown = false;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return TextFormField(
      controller: widget.controller,
      onChanged: widget.onChanged,
      validator: widget.validator,
      forceErrorText: widget.errorText,
      obscureText: widget.secret && !_shown,
      autocorrect: false,
      enableSuggestions: false,
      enableIMEPersonalizedLearning: !widget.secret,
      keyboardType: widget.secret
          ? TextInputType.visiblePassword
          : widget.keyboardType,
      textInputAction: widget.textInputAction,
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        labelText: widget.label,
        helperText: widget.helper,
        helperMaxLines: 5,
        errorMaxLines: 5,
        suffixIcon: widget.secret
            ? IconButton(
                icon: Icon(
                  _shown
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
                tooltip: _shown
                    ? strings.formHide(widget.label)
                    : strings.formShow(widget.label),
                onPressed: () => setState(() => _shown = !_shown),
              )
            : null,
      ),
    );
  }
}

/// A heading of a part of the form.
class FormHeading extends StatelessWidget {
  const FormHeading(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );
}

/// A remark under the fields it is about.
class FormNote extends StatelessWidget {
  const FormNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: Icon(
            Icons.info_outline,
            size: 20,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
