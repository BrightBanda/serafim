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
  });

  final TextEditingController? controller;
  final String hintText;
  final VoidCallback? onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.paperRaised, AppColors.paperAlt],
        ),
        border: Border(top: BorderSide(color: AppColors.line, width: 2)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: AppColors.paperAlt,
                border: Border.all(color: AppColors.lineSoft, width: 1.5),
              ),
              child: TextField(
                controller: controller,
                style: AppTextStyles.fieldInput.copyWith(fontSize: 11),
                cursorColor: AppColors.primary,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  isCollapsed: true,
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
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.primary, AppColors.primaryDeep],
                ),
                border: Border.all(color: AppColors.line, width: 2),
                boxShadow: const [
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
    );
  }
}
