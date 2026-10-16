import 'package:flutter/material.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

/// Bottom input bar for the chat thread. UI only — [onSend] fires with
/// whatever plain callback the caller supplies; no message is actually
/// sent or appended to any list from within this widget.
class ChatInputBar extends StatelessWidget {
  const ChatInputBar({
    super.key,
    this.controller,
    this.hintText = 'Speak into the void…',
    this.onSend,
    this.onAttach,
    this.attachDisabledReason,
    this.replyPreview,
  });

  /// Shown above the field while composing a reply.
  final ({String author, String snippet, VoidCallback onCancel})? replyPreview;

  final TextEditingController? controller;
  final String hintText;
  final VoidCallback? onSend;

  /// Shows an attach (image) button when non-null.
  final VoidCallback? onAttach;

  /// When non-null the attach button is dimmed and tapping it explains this
  /// reason instead of picking a file. (The server enforces the rule too.)
  final String? attachDisabledReason;

  @override
  Widget build(BuildContext context) {
    final bar = Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.paperRaised, AppColors.paperAlt],
        ),
        border: Border(top: BorderSide(color: AppColors.line, width: 2)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (onAttach != null) ...[
              GestureDetector(
                onTap: attachDisabledReason == null
                    ? onAttach
                    : () => ScaffoldMessenger.of(context)
                        ..clearSnackBars()
                        ..showSnackBar(
                          SnackBar(content: Text(attachDisabledReason!)),
                        ),
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppColors.paperAlt,
                    border: Border.all(color: AppColors.lineSoft, width: 1.5),
                  ),
                  child: Icon(
                    Icons.attach_file,
                    size: 18,
                    color: attachDisabledReason == null
                        ? AppColors.textDim
                        : AppColors.lineSoft,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.paperAlt,
                  border: Border.all(color: AppColors.lineSoft, width: 1.5),
                ),
                child: TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 3,
                  keyboardType: TextInputType.multiline,
                  style: AppTextStyles.fieldInput.copyWith(fontSize: 11),
                  cursorColor: AppColors.primary,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    hintText: hintText,
                    hintStyle: AppTextStyles.fieldInput.copyWith(
                      color: AppColors.textDim,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onSend,
              child: Container(
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.primary, AppColors.primaryDeep],
                  ),
                  border: Border.all(color: AppColors.line, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.line,
                      offset: Offset(2, 2),
                      blurRadius: 0,
                    ),
                  ],
                ),
                child: Text(
                  'Send',
                  style: AppTextStyles.buttonLabel.copyWith(fontSize: 10),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    final reply = replyPreview;
    if (reply == null) return bar;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
          decoration: BoxDecoration(
            color: AppColors.paperRaised,
            border: Border(top: BorderSide(color: AppColors.line, width: 2)),
          ),
          child: Row(
            children: [
              Container(width: 3, height: 32, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Replying to ${reply.author}',
                      style: AppTextStyles.fieldLabel.copyWith(
                        color: AppColors.primaryPale,
                      ),
                    ),
                    Text(
                      reply.snippet,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.body.copyWith(fontSize: 11),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Cancel reply',
                icon: Icon(Icons.close, size: 18, color: AppColors.textDim),
                onPressed: reply.onCancel,
              ),
            ],
          ),
        ),
        bar,
      ],
    );
  }
}
