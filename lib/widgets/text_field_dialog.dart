import 'package:flutter/material.dart';

/// A single-field dialog that owns its [TextEditingController].
///
/// The crash this fixes (Nov 21, C1–C8): a controller created in the
/// calling method, passed into a dialog [TextField], and disposed
/// right after `await showDialog` returns — but the field is still
/// mounted during the exit animation, so it rebuilds against the
/// disposed controller and throws, then trips the framework's
/// `_dependents.isEmpty` assertion (red screen). Here the controller
/// is created in [State.initState] and disposed in [State.dispose],
/// so it lives exactly as long as the dialog subtree.
///
/// The [actions] builder receives a getter for the current field text,
/// so Confirm buttons can pop with it, e.g.
/// `FilledButton(onPressed: () => Navigator.of(context).pop(text().trim()), ...)`.
/// When an action needs the text *and* pops with something else (the
/// new-program choice), capture it in a closure variable inside the
/// action handler — the controller is gone once the dialog returns.
///
/// Set [stackedActions] for a multi-action dialog (the new-program
/// dialogs): the actions are stacked full-width inside the content in
/// decision order — last action is Cancel — with the same named gaps
/// as [MixConflictDialog] (body→actions 24, between actions 12,
/// before Cancel 8) and explicit title/content padding, instead of
/// `AlertDialog.actions` defaults, which glue the buttons together.
class TextFieldDialog extends StatefulWidget {
  /// Gap between the body text and the first button. The decision
  /// needs air after the explanation.
  static const double bodyToActionsGap = 24;

  /// Gap between the main actions. They are full-width, so they need
  /// a real gap or they read as one block.
  static const double actionGap = 12;

  /// Gap before Cancel. It is the quiet way out, so it sits a little
  /// closer to the actions than they sit to each other.
  static const double cancelGap = 8;

  const TextFieldDialog({
    super.key,
    required this.title,
    this.body,
    this.labelText,
    this.hintText,
    this.initialValue = '',
    this.keyboardType,
    this.obscureText = false,
    this.autofillHints,
    this.textInputAction,
    this.onSubmitted,
    this.autofocus = true,
    this.stackedActions = false,
    required this.actions,
  });

  /// Dialog title.
  final Widget title;

  /// Optional content shown under the field.
  final Widget? body;

  /// Label for the text field.
  final String? labelText;

  /// Optional hint inside the text field.
  final String? hintText;

  /// Starting text. Defaults to empty.
  final String initialValue;

  /// Keyboard type for the field.
  final TextInputType? keyboardType;

  /// Whether the field hides its text (passwords).
  final bool obscureText;

  /// Autofill hints for the field (e.g. [AutofillHints.password]).
  final Iterable<String>? autofillHints;

  /// Action button on the keyboard (e.g. done). Pairs with
  /// [onSubmitted].
  final TextInputAction? textInputAction;

  /// Called with the current text when the keyboard action fires.
  final ValueChanged<String>? onSubmitted;

  /// Whether the field takes focus when the dialog opens.
  final bool autofocus;

  /// Stack the actions full-width inside the content (decision order,
  /// Cancel last) instead of using `AlertDialog.actions`.
  final bool stackedActions;

  /// The dialog's actions. Receives the dialog [BuildContext] and a
  /// getter for the field's current text.
  final List<Widget> Function(BuildContext context, String Function() text)
      actions;

  @override
  State<TextFieldDialog> createState() => _TextFieldDialogState();
}

class _TextFieldDialogState extends State<TextFieldDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  TextField _field() {
    return TextField(
      controller: _controller,
      autofocus: widget.autofocus,
      keyboardType: widget.keyboardType,
      obscureText: widget.obscureText,
      autofillHints: widget.autofillHints,
      textInputAction: widget.textInputAction,
      decoration: InputDecoration(
        labelText: widget.labelText,
        hintText: widget.hintText,
      ),
      onSubmitted: widget.onSubmitted,
    );
  }

  @override
  Widget build(BuildContext context) {
    String text() => _controller.text;
    if (!widget.stackedActions) {
      return AlertDialog(
        title: widget.title,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _field(),
            if (widget.body != null) ...[
              const SizedBox(height: 16),
              widget.body!,
            ],
          ],
        ),
        actions: widget.actions(context, text),
      );
    }
    // Stacked actions: title, body and buttons live in one Column
    // with a named gap between each pair, and the dialog's own
    // paddings are set explicitly — same structure as
    // MixConflictDialog. The last action is Cancel.
    final built = widget.actions(context, text);
    final children = <Widget>[
      _field(),
      if (widget.body != null) ...[
        const SizedBox(height: 16),
        widget.body!,
      ],
    ];
    for (var i = 0; i < built.length; i++) {
      final gap = i == 0
          ? TextFieldDialog.bodyToActionsGap
          : i == built.length - 1
              ? TextFieldDialog.cancelGap
              : TextFieldDialog.actionGap;
      children.add(SizedBox(height: gap));
      children.add(SizedBox(width: double.infinity, child: built[i]));
    }
    return AlertDialog(
      title: widget.title,
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }
}
