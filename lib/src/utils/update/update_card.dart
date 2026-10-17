import 'package:flutter/material.dart';
import 'package:serafim/src/data/models/app_update.dart';
import 'package:serafim/src/utils/chat/chat_time.dart';
import 'package:serafim/src/utils/serafim_mark.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';
import 'package:serafim/src/utils/update/update_flow_panel.dart';

/// An update announcement in the official chat: version, size, changelog and
/// the Update button (or "Installed").
class UpdateCard extends StatefulWidget {
  const UpdateCard({super.key, required this.update, this.onLongPress});

  final AppUpdate update;
  final VoidCallback? onLongPress;

  @override
  State<UpdateCard> createState() => _UpdateCardState();
}

class _UpdateCardState extends State<UpdateCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final u = widget.update;
    final long =
        u.changelog.length > 240 || '\n'.allMatches(u.changelog).length > 5;

    return GestureDetector(
      onLongPress: widget.onLongPress,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.86,
        ),
        decoration: BoxDecoration(
          color: AppColors.paperRaised,
          border: Border.all(color: AppColors.line, width: 2),
          boxShadow: [
            BoxShadow(
              color: AppColors.line,
              offset: const Offset(3, 3),
              blurRadius: 0,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.primary, AppColors.primaryDeep],
                ),
              ),
              child: Row(
                children: [
                  const SerafimMark(size: 32),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Serafim ${u.versionName}',
                          style: AppTextStyles.displayHeading.copyWith(
                            fontSize: 20,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          [
                            'UPDATE',
                            if (u.sizeBytes > 0) formatBytes(u.sizeBytes),
                            if (u.publishedAt != null)
                              formatChatListTime(context, u.publishedAt!),
                          ].join(' · '),
                          style: AppTextStyles.fieldLabel.copyWith(
                            color: const Color(0xFFDBE4FB),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (u.mandatory)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      color: AppColors.rust,
                      child: Text(
                        'REQUIRED',
                        style: AppTextStyles.fieldLabel.copyWith(
                          color: Colors.white,
                          fontSize: 8.5,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text("WHAT'S NEW", style: AppTextStyles.eyebrow),
                  const SizedBox(height: 4),
                  Text(
                    u.changelog.isEmpty
                        ? 'Fixes and improvements.'
                        : u.changelog,
                    maxLines: _expanded || !long ? null : 6,
                    overflow: _expanded || !long ? null : TextOverflow.fade,
                    style: AppTextStyles.body.copyWith(color: AppColors.text),
                  ),
                  if (long)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () => setState(() => _expanded = !_expanded),
                        child: Text(
                          _expanded ? 'Show less' : 'Show more',
                          style: AppTextStyles.linkText,
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  UpdateFlowPanel(update: u),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
