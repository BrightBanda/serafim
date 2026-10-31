import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/core/errors/human_error.dart';
import 'package:serafim/src/data/models/sticker_collection.dart';
import 'package:serafim/src/providers/sticker_providers.dart';
import 'package:serafim/src/utils/settled_sheet.dart';
import 'package:serafim/src/utils/stickers/sticker_packs.dart';
import 'package:serafim/src/utils/text_edit_dialog.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

/// What to call a collection item in sheets and messages.
String collectionItemLabel(StickerCollectionItem item) {
  if (item.isSticker) {
    return stickerById(item.stickerId!)?.name ?? item.stickerId!;
  }
  final name = item.name?.trim();
  if (name != null && name.isNotEmpty) return name;
  return switch (item.kind) {
    StickerCollectionItemKind.video => 'Video',
    StickerCollectionItemKind.audio => 'Audio',
    _ => 'GIF',
  };
}

/// Asks for a new collection's name (unique, at most 10 characters).
Future<String?> askCollectionName(BuildContext context, WidgetRef ref) async {
  final name = await showTextEditDialog(
    context,
    title: 'New collection',
    initial: '',
    maxLength: 10,
    validate: (value) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return 'Give the collection a name.';
      if (ref.read(stickerCollectionsProvider.notifier).nameTaken(trimmed)) {
        return 'A collection with that name already exists.';
      }
      return null;
    },
  );
  return name?.trim();
}

/// Lets the person pick a collection for [pending] (or make a new one) and
/// saves it there. Returns what to tell them, or null if they backed out.
Future<String?> showSaveToCollectionSheet(
  BuildContext context,
  WidgetRef ref,
  PendingCollectionItem pending,
) async {
  const createNew = '\u0000new';
  final key = pending.item.key;
  final choice = await showSettledSheet<String>(
    context: context,
    backgroundColor: AppColors.paperAlt,
    shape: const RoundedRectangleBorder(),
    builder: (ctx) {
      final collections = ref.read(stickerCollectionsProvider);
      return SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Text(
                'Save “${collectionItemLabel(pending.item)}”',
                style: AppTextStyles.displayHeading.copyWith(fontSize: 18),
              ),
              const SizedBox(height: 12),
              if (collections.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'No collections yet. Create one below.',
                    style: AppTextStyles.smallDim,
                  ),
                )
              else ...[
                for (final c in collections)
                  ListTile(
                    leading: Icon(
                      Icons.collections_bookmark,
                      size: 20,
                      color: AppColors.text,
                    ),
                    title: Text(
                      c.name,
                      style: AppTextStyles.body.copyWith(color: AppColors.text),
                    ),
                    trailing: c.contains(key)
                        ? Icon(Icons.check, color: AppColors.primary, size: 20)
                        : null,
                    onTap: () => Navigator.pop(ctx, c.id),
                  ),
                const Divider(height: 1),
              ],
              ListTile(
                leading: Icon(
                  Icons.add_circle_outline,
                  size: 20,
                  color: AppColors.primary,
                ),
                title: Text(
                  'Create new collection',
                  style: AppTextStyles.body.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                onTap: () => Navigator.pop(ctx, createNew),
              ),
            ],
          ),
        ),
      );
    },
  );
  if (choice == null || !context.mounted) return null;

  final notifier = ref.read(stickerCollectionsProvider.notifier);
  try {
    if (choice == createNew) {
      final name = await askCollectionName(context, ref);
      if (name == null || name.isEmpty) return null;
      await notifier.addToNew(name, pending);
      return 'Saved to “$name”';
    }
    final collection = ref
        .read(stickerCollectionsProvider)
        .where((c) => c.id == choice)
        .firstOrNull;
    if (collection == null) return null;
    final added = await notifier.add(collection.id, pending);
    return added
        ? 'Saved to “${collection.name}”'
        : 'Already in “${collection.name}”';
  } catch (error) {
    return humanError(error, fallback: "Couldn't save that.");
  }
}
