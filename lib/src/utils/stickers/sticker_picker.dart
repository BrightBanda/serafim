import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/data/models/sticker_collection.dart';
import 'package:serafim/src/providers/sticker_providers.dart';
import 'package:serafim/src/utils/stickers/sticker_packs.dart';
import 'package:serafim/src/utils/stickers/sticker_view.dart';
import 'package:serafim/src/utils/settled_sheet.dart';
import 'package:serafim/src/utils/text_edit_dialog.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

/// The panel under the composer: recently used stickers, then one tab per
/// pack. Collections also appear as scrollable tabs on the nav bar. Tapping a
/// sticker or GIF lets the person forward, save to a collection, or delete it
/// — it does not send immediately or open full screen.
class StickerPicker extends ConsumerStatefulWidget {
  const StickerPicker({
    super.key,
    required this.onPick,
    this.onSave,
    this.onPickGif,
    this.height = 260,
  });

  /// A sticker id (pack/name) was tapped. The parent shows forward/save/delete
  /// options rather than sending immediately.
  final ValueChanged<String> onPick;

  /// Long-press a sticker to save it to a collection.
  final ValueChanged<String>? onSave;

  /// A saved GIF was tapped: [bytes] are the GIF file bytes, [name] its label.
  final ValueChanged<(Uint8List, String)>? onPickGif;
  final double height;

  @override
  ConsumerState<StickerPicker> createState() => _StickerPickerState();
}

class _StickerPickerState extends ConsumerState<StickerPicker> {
  // -1 = recent, 0..packCount-1 = packs, packCount.. = collections
  int _tab = -1;

  @override
  void initState() {
    super.initState();
    // Open on the first pack when nothing has been used yet.
    if (ref.read(recentStickersProvider).isEmpty) _tab = 0;
  }

  int get _packCount => stickerPacks.length;

  Future<void> _createCollection() async {
    final name = await showTextEditDialog(
      context,
      title: 'New collection',
      initial: '',
      maxLength: 10,
      validate: (value) {
        final trimmed = value.trim();
        if (trimmed.isEmpty) return 'Give the collection a name.';
        if (ref
            .read(stickerCollectionsProvider)
            .any(
              (collection) =>
                  collection.name.toLowerCase() == trimmed.toLowerCase(),
            )) {
          return 'A collection with that name already exists.';
        }
        return null;
      },
    );
    if (name == null || !mounted) return;
    final collection = ref
        .read(stickerCollectionsProvider.notifier)
        .createCollection(name.trim());
    final collections = ref.read(stickerCollectionsProvider);
    setState(() => _tab = _packCount + collections.indexOf(collection));
  }

  List<StickerCollectionItem> get _collectionItems {
    if (_tab < _packCount) return const [];
    final collIndex = _tab - _packCount;
    final collections = ref.read(stickerCollectionsProvider);
    if (collIndex < 0 || collIndex >= collections.length) return const [];
    return collections[collIndex].items;
  }

  /// The sticker ids shown in the grid for the currently selected tab.
  List<String> get _ids {
    final recent = ref.read(recentStickersProvider);
    if (_tab < 0) return recent;
    final packIndex = _tab;
    if (packIndex < _packCount) {
      return [for (final s in stickerPacks[packIndex].stickers) s.id];
    }
    final collIndex = packIndex - _packCount;
    final collections = ref.read(stickerCollectionsProvider);
    if (collIndex < 0 || collIndex >= collections.length) return const [];
    return [
      for (final item in collections[collIndex].items)
        if (item.isSticker) item.stickerId,
    ];
  }

  /// The label shown above the grid for the current tab.
  String get _tabLabel {
    if (_tab < 0) return 'RECENT';
    final packIndex = _tab;
    if (packIndex < _packCount) {
      return stickerPacks[packIndex].name.toUpperCase();
    }
    final collIndex = packIndex - _packCount;
    final collections = ref.read(stickerCollectionsProvider);
    if (collIndex < 0 || collIndex >= collections.length) return '';
    return collections[collIndex].name.toUpperCase();
  }

  /// Whether a sticker id is already saved in the currently selected
  /// collection tab (so we can show a checkmark).
  bool _isSavedInCollection(String id) {
    if (_tab < _packCount) return false;
    final collIndex = _tab - _packCount;
    final collections = ref.read(stickerCollectionsProvider);
    if (collIndex < 0 || collIndex >= collections.length) return false;
    return collections[collIndex].items.any(
      (i) => i.isSticker && i.stickerId == id,
    );
  }

  Widget _tabButton({
    required int index,
    required Widget icon,
    required String label,
    required bool selected,
    bool showLabel = false,
    VoidCallback? onTap,
  }) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        onTap: onTap ?? () => setState(() => _tab = index),
        child: Container(
          width: showLabel ? 88 : 52,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.paperRaised : Colors.transparent,
            border: Border(
              bottom: BorderSide(
                color: selected ? AppColors.primary : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: showLabel
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    label.length > 10 ? label.substring(0, 10) : label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.fieldLabel.copyWith(
                      color: selected ? AppColors.primary : AppColors.textDim,
                    ),
                  ),
                )
              : icon,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final collections = ref.watch(stickerCollectionsProvider);

    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: AppColors.paperAlt,
        border: Border(top: BorderSide(color: AppColors.line, width: 2)),
      ),
      child: Column(
        children: [
          // Scrollable nav bar: recent, packs, then collections.
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                _tabButton(
                  index: -1,
                  icon: Icon(Icons.history, size: 18, color: AppColors.textDim),
                  label: 'Recent stickers',
                  selected: _tab < 0,
                ),
                for (var i = 0; i < _packCount; i++)
                  _tabButton(
                    index: i,
                    icon: StickerView(
                      stickerId: stickerPacks[i].stickers.first.id,
                      size: 26,
                    ),
                    label: stickerPacks[i].name,
                    selected: _tab == i,
                  ),
                for (var i = 0; i < collections.length; i++)
                  _tabButton(
                    index: _packCount + i,
                    icon: const SizedBox.shrink(),
                    label: collections[i].name,
                    selected: _tab == _packCount + i,
                    showLabel: true,
                  ),
                _tabButton(
                  index: _tab,
                  icon: Icon(
                    Icons.collections_bookmark_outlined,
                    size: 18,
                    color: AppColors.textDim,
                  ),
                  label: 'Browse collections',
                  selected: false,
                  onTap: _showCollectionsSheet,
                ),
                SizedBox(
                  width: 44,
                  height: 38,
                  child: IconButton(
                    key: const ValueKey('add-sticker-collection'),
                    tooltip: 'Add collection',
                    padding: EdgeInsets.zero,
                    iconSize: 20,
                    color: AppColors.primary,
                    onPressed: _createCollection,
                    icon: const Icon(Icons.add),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Text(_tabLabel, style: AppTextStyles.fieldLabel),
          ),
          Expanded(
            child: _tab >= _packCount && _collectionItems.isNotEmpty
                ? GridView.builder(
                    padding: const EdgeInsets.all(10),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 80,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                        ),
                    itemCount: _collectionItems.length,
                    itemBuilder: (_, i) {
                      final item = _collectionItems[i];
                      return GestureDetector(
                        key: ValueKey(
                          'sticker-collection-item-${item.name ?? item.stickerId}-$i',
                        ),
                        onTap: () {
                          if (item.isSticker) {
                            widget.onPick(item.stickerId);
                          } else if (item.gifBytesBase64 != null &&
                              widget.onPickGif != null) {
                            widget.onPickGif!((
                              base64Decode(item.gifBytesBase64!),
                              item.name ?? 'GIF',
                            ));
                          }
                        },
                        child: item.isSticker
                            ? StickerView(stickerId: item.stickerId, size: 72)
                            : item.gifBytesBase64 != null
                            ? Image.memory(
                                base64Decode(item.gifBytesBase64!),
                                fit: BoxFit.contain,
                              )
                            : Center(
                                child: Text(
                                  'GIF',
                                  style: AppTextStyles.fieldLabel,
                                ),
                              ),
                      );
                    },
                  )
                : _ids.isEmpty
                ? Center(
                    child: Text(
                      _tab < 0
                          ? 'Stickers you send show up here.'
                          : 'This collection is empty.',
                      style: AppTextStyles.smallDim,
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.all(10),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 80,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                        ),
                    itemCount: _ids.length,
                    itemBuilder: (_, i) {
                      final id = _ids[i];
                      final alreadySaved = _isSavedInCollection(id);
                      return GestureDetector(
                        onTap: () => widget.onPick(id),
                        onLongPress: widget.onSave != null
                            ? () => widget.onSave!(id)
                            : null,
                        child: Stack(
                          children: [
                            StickerView(stickerId: id, size: 72),
                            if (alreadySaved)
                              Positioned(
                                right: 2,
                                top: 2,
                                child: Container(
                                  width: 16,
                                  height: 16,
                                  decoration: BoxDecoration(
                                    color: AppColors.primary,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.check,
                                    size: 10,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// Shows a bottom sheet with this account's sticker collections.
  void _showCollectionsSheet() {
    final collections = ref.read(stickerCollectionsProvider);
    showSettledSheet<void>(
      context: context,
      backgroundColor: AppColors.paperAlt,
      shape: const RoundedRectangleBorder(),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Collections',
                style: AppTextStyles.displayHeading.copyWith(fontSize: 18),
              ),
              const SizedBox(height: 12),
              if (collections.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'No collections yet. Save a sticker or GIF to create one.',
                    style: AppTextStyles.smallDim,
                  ),
                )
              else ...[
                const SizedBox(height: 8),
                ...[
                  for (final c in collections)
                    ListTile(
                      leading: Icon(
                        Icons.collections_bookmark,
                        size: 20,
                        color: AppColors.text,
                      ),
                      title: Text(
                        c.name,
                        style: AppTextStyles.body.copyWith(
                          color: AppColors.text,
                        ),
                      ),
                      subtitle: Text(
                        '${c.items.length} saved'
                        '${c.items.any((i) => i.isGif) ? ' (incl. GIFs)' : ''}',
                        style: AppTextStyles.smallDim.copyWith(
                          color: AppColors.textDim,
                        ),
                      ),
                      onTap: () {
                        Navigator.pop(ctx);
                        _showCollectionItems(ctx, c);
                      },
                    ),
                ],
              ],
            ],
          ),
        );
      },
    );
  }

  /// Shows a bottom sheet with the saved items in [collection].
  void _showCollectionItems(BuildContext ctx, StickerCollection collection) {
    showSettledSheet<void>(
      context: context,
      backgroundColor: AppColors.paperAlt,
      shape: const RoundedRectangleBorder(),
      builder: (_) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                collection.name,
                style: AppTextStyles.displayHeading.copyWith(fontSize: 18),
              ),
              const SizedBox(height: 12),
              if (collection.items.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'This collection is empty.',
                    style: AppTextStyles.smallDim,
                  ),
                )
              else ...[
                const SizedBox(height: 8),
                SizedBox(
                  height: 100,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: collection.items.length,
                    itemBuilder: (_, i) {
                      final item = collection.items[i];
                      return GestureDetector(
                        onTap: () {
                          Navigator.pop(context);
                          if (item.isSticker) {
                            widget.onPick(item.stickerId);
                          } else if (item.isGif &&
                              item.gifBytesBase64 != null &&
                              widget.onPickGif != null) {
                            final bytes = base64Decode(item.gifBytesBase64!);
                            widget.onPickGif!((bytes, item.name ?? ''));
                          }
                        },
                        child: Container(
                          width: 80,
                          margin: const EdgeInsets.only(right: 8),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  color: AppColors.paperRaised,
                                  border: Border.all(
                                    color: AppColors.lineSoft,
                                    width: 1.5,
                                  ),
                                ),
                                child: item.isSticker
                                    ? StickerView(
                                        stickerId: item.stickerId,
                                        size: 64,
                                      )
                                    : item.gifBytesBase64 != null
                                    ? Image.memory(
                                        base64Decode(item.gifBytesBase64!),
                                        fit: BoxFit.contain,
                                      )
                                    : Center(
                                        child: Text(
                                          'GIF',
                                          style: AppTextStyles.fieldLabel,
                                        ),
                                      ),
                              ),
                              const SizedBox(height: 4),
                              SizedBox(
                                width: 72,
                                child: Text(
                                  item.name ?? item.stickerId,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyles.smallDim.copyWith(
                                    color: AppColors.textDim,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
