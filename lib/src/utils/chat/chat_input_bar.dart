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
    this.attachBusy = false,
    this.replyPreview,
    this.onStickers,
    this.stickersOpen = false,
    this.onContentInserted,
    this.focusNode,
    this.trailing,
    this.recordingStrip,
  });

  /// Shown instead of the text field while a voice note is being recorded.
  final Widget? recordingStrip;

  /// Shows a sticker button that opens/closes the sticker panel.
  final VoidCallback? onStickers;
  final bool stickersOpen;

  /// GIFs, stickers and images inserted from the keyboard (e.g. Gboard).
  final ValueChanged<KeyboardInsertedContent>? onContentInserted;

  final FocusNode? focusNode;

  /// Shown instead of Send while the field is empty (the mic button).
  final Widget? trailing;

  /// What the keyboard may insert.
  static const insertableMimeTypes = [
    'image/gif',
    'image/png',
    'image/webp',
    'image/jpeg',
  ];

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

  /// A photo is being prepared or sent: the attach button shows a spinner and
  /// ignores taps.
  final bool attachBusy;

  @override
  Widget build(BuildContext context) {
    final bar = Container(
      // The extra bottom padding lifts the bar clear of the screen edge.
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 20),
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
            // Kept while recording: removing it would shift the row and
            // rebuild the mic button, ending the hold gesture.
            if (onAttach != null) ...[
              GestureDetector(
                onTap: attachBusy
                    ? null
                    : attachDisabledReason == null
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
                  child: attachBusy
                      ? Center(
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.primary,
                            ),
                          ),
                        )
                      : Icon(
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
            if (recordingStrip != null)
              Expanded(child: recordingStrip!)
            else
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
                    focusNode: focusNode,
                    contentInsertionConfiguration: onContentInserted == null
                        ? null
                        : ContentInsertionConfiguration(
                            allowedMimeTypes: insertableMimeTypes,
                            onContentInserted: onContentInserted!,
                          ),
                    minLines: 1,
                    maxLines: 3,
                    keyboardType: TextInputType.multiline,
                    style: AppTextStyles.fieldInput.copyWith(fontSize: 11),
                    cursorColor: AppColors.primary,
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      suffixIconConstraints: const BoxConstraints(
                        minWidth: 24,
                        minHeight: 20,
                      ),
                      suffixIcon: onStickers == null
                          ? null
                          : Semantics(
                              button: true,
                              label: stickersOpen
                                  ? 'Show keyboard'
                                  : 'Stickers',
                              child: GestureDetector(
                                onTap: onStickers,
                                child: Icon(
                                  stickersOpen
                                      ? Icons.keyboard_alt_outlined
                                      : Icons.emoji_emotions_outlined,
                                  size: 18,
                                  color: stickersOpen
                                      ? AppColors.primaryPale
                                      : AppColors.textDim,
                                ),
                              ),
                            ),
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
            _SendOrIdle(
              controller: controller,
              idle: trailing,
              recording: recordingStrip != null,
              send: GestureDetector(
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
            ),
          ],
        ),
      ),
    );

    // The bar is ALWAYS the second child of the same Column, with a key. The
    // reply preview appearing above it (or going away) must never rebuild the
    // text field: that dropped its focus, and with it the keyboard, every time
    // a reply started after the first one.
    final reply = replyPreview;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (reply != null)
          KeyedSubtree(
            key: const ValueKey('reply-preview'),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
              decoration: BoxDecoration(
                color: AppColors.paperRaised,
                border: Border(
                  top: BorderSide(color: AppColors.line, width: 2),
                ),
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
          ),
        KeyedSubtree(key: const ValueKey('input-bar'), child: bar),
      ],
    );
  }
}

/// Send when there is something typed; otherwise [idle] (the mic). While
/// recording it is always [idle], which then acts as the send button.
class _SendOrIdle extends StatelessWidget {
  const _SendOrIdle({
    required this.controller,
    required this.idle,
    required this.recording,
    required this.send,
  });

  final TextEditingController? controller;
  final Widget? idle;
  final bool recording;
  final Widget send;

  @override
  Widget build(BuildContext context) {
    final idle = this.idle;
    final controller = this.controller;
    if (idle == null || controller == null) return send;
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (_, value, __) =>
          recording || value.text.trim().isEmpty ? idle : send,
    );
  }
}
