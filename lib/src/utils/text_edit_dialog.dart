import 'package:flutter/material.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

/// Asks for a piece of text (a name, a message, some rules) with Cancel and
/// Save. Returns what was saved, or null if the person cancelled.
///
/// [validate] returns a message to show under the field, or null when the
/// text is fine. [onSave], if given, does the saving while the dialog stays
/// open with a spinner: it returns null on success (the dialog closes) or a
/// message to show (the dialog stays, with the text still there). While it
/// runs the dialog cannot be closed, so its answer always lands somewhere.
///
/// The dialog owns its text controller and releases it only once it has
/// finished closing — releasing it as soon as `showDialog` returns breaks the
/// field still on screen during the closing animation.
Future<String?> showTextEditDialog(
  BuildContext context, {
  required String title,
  required String initial,
  int? maxLength,
  int maxLines = 1,
  String? hint,
  TextStyle? titleStyle,
  ShapeBorder? shape,
  TextStyle? actionStyle,
  String? Function(String text)? validate,
  Future<String?> Function(String text)? onSave,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => TextEditDialog(
      title: title,
      initial: initial,
      maxLength: maxLength,
      maxLines: maxLines,
      hint: hint,
      titleStyle: titleStyle,
      shape: shape,
      actionStyle: actionStyle,
      validate: validate,
      onSave: onSave,
    ),
  );
}

/// The dialog behind [showTextEditDialog].
class TextEditDialog extends StatefulWidget {
  const TextEditDialog({
    super.key,
    required this.title,
    required this.initial,
    this.maxLength,
    this.maxLines = 1,
    this.hint,
    this.titleStyle,
    this.shape,
    this.actionStyle,
    this.validate,
    this.onSave,
  });

  final String title;
  final String initial;
  final int? maxLength;
  final int maxLines;
  final String? hint;
  final TextStyle? titleStyle;
  final ShapeBorder? shape;
  final TextStyle? actionStyle;
  final String? Function(String text)? validate;
  final Future<String?> Function(String text)? onSave;

  @override
  State<TextEditDialog> createState() => _TextEditDialogState();
}

class _TextEditDialogState extends State<TextEditDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return; // A second tap while the first is saving.
    final text = _controller.text;
    final invalid = widget.validate?.call(text);
    if (invalid != null) {
      setState(() => _error = invalid);
      return;
    }
    final onSave = widget.onSave;
    if (onSave == null) {
      Navigator.of(context).pop(text);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final failure = await onSave(text);
    if (!mounted) return;
    if (failure == null) {
      Navigator.of(context).pop(text);
    } else {
      setState(() {
        _saving = false;
        _error = failure;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        backgroundColor: AppColors.paperAlt,
        shape: widget.shape,
        title: Text(
          widget.title,
          style:
              widget.titleStyle ??
              AppTextStyles.displayHeading.copyWith(fontSize: 20),
        ),
        content: TextField(
          controller: _controller,
          autofocus: true,
          enabled: !_saving,
          maxLength: widget.maxLength,
          maxLines: widget.maxLines,
          minLines: 1,
          style: AppTextStyles.fieldInput,
          cursorColor: AppColors.primary,
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          decoration: InputDecoration(
            hintText: widget.hint,
            errorText: _error,
            errorMaxLines: 3,
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            child: Text('Cancel', style: widget.actionStyle),
          ),
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primary,
                    ),
                  )
                : Text('Save', style: widget.actionStyle),
          ),
        ],
      ),
    );
  }
}
