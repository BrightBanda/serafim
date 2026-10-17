import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/providers/link_preview_providers.dart';
import 'package:serafim/src/utils/links.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

/// The preview card under a message with a link. Takes no space until a
/// preview exists, so a link without one just stays a plain tappable link.
class LinkPreviewCard extends ConsumerWidget {
  const LinkPreviewCard({super.key, required this.uri, required this.outgoing});

  final Uri uri;
  final bool outgoing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preview = ref.watch(linkPreviewProvider(uri.toString())).value;
    if (preview == null) return const SizedBox.shrink();

    final fg = outgoing ? Colors.white : AppColors.text;
    final dim = outgoing ? const Color(0xFFDBE4FB) : AppColors.textDim;
    final thumb = preview.imageBytes;

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Semantics(
        link: true,
        label: 'Link preview: ${preview.title ?? preview.domain}',
        child: GestureDetector(
          onTap: () => openLink(uri),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: outgoing ? 0.18 : 0.22),
              border: Border(
                left: BorderSide(
                  color: outgoing ? AppColors.primaryPale : AppColors.tealPale,
                  width: 3,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (thumb != null)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 140),
                    child: Image.memory(
                      thumb,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 7),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        (preview.siteName ?? preview.domain).toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.fieldLabel.copyWith(
                          fontSize: 8,
                          color: dim,
                        ),
                      ),
                      if (preview.title != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          preview.title!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.body.copyWith(
                            color: fg,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            height: 1.3,
                          ),
                        ),
                      ],
                      if (preview.description != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          preview.description!,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.body.copyWith(
                            color: fg.withValues(alpha: 0.82),
                            fontSize: 10.5,
                            height: 1.35,
                          ),
                        ),
                      ],
                      const SizedBox(height: 2),
                      Text(
                        preview.domain,
                        style: AppTextStyles.fieldLabel.copyWith(
                          fontSize: 8,
                          color: dim,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
