import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/data/models/sticker_collection.dart';
import 'package:serafim/src/providers/sticker_providers.dart';
import 'package:serafim/src/utils/stickers/collection_sheets.dart';
import 'package:serafim/src/utils/stickers/sticker_packs.dart';
import 'package:serafim/src/utils/stickers/sticker_view.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

/// The panel under the composer: recently used stickers, one tab per pack,
/// then one tab per collection (stickers, GIFs, videos and audio the person
/// saved), and a button to start a new collection.
///
/// Tapping something does not send it: the parent shows what can be done
/// with it (send, save to a collection, remove).
class StickerPicker extends ConsumerStatefulWidget {
  const StickerPicker({
    super.key,
    required this.onPick,
    this.onSave,
    this.onPickItem,
    this.height = 260,
  });

  /// A sticker (pack/name) was tapped.
  final ValueChanged<String> onPick;

  /// A sticker was long-pressed: save it to a collection.
  final ValueChanged<String>? onSave;

  /// A saved GIF, video or audio file was tapped in a collection.
  final ValueChanged<StickerCollectionItem>? onPickItem;

  final double height;

  @override
  ConsumerState<StickerPicker> createState() => _StickerPickerState();
}

class _StickerPickerState extends ConsumerState<StickerPicker> {
  // -1 = recent, 0..packCount-1 = packs, packCount.. = collections.
  int _tab = -1;

  @override
  void initState() {
    super.initState();
    // Open on the first pack when nothing has been used yet.
    if (ref.read(recentStickersProvider).isEmpty) _tab = 0;
  }

  int get _packCount => stickerPacks.length;

  Future<void> _createCollection() async {
    final name = await askCollectionName(context, ref);
    if (name == null || name.isEmpty || !mounted) return;
    final collection = ref
        .read(stickerCollectionsProvider.notifier)
        .createCollection(name);
    final collections = ref.read(stickerCollectionsProvider);
    setState(() => _tab = _packCount + collections.indexOf(collection));
  }

  @override
  Widget build(BuildContext context) {
    final collections = ref.watch(stickerCollectionsProvider);
    final recent = ref.watch(recentStickersProvider);
    // A collection can disappear underneath us (account switch).
    final tab = _tab >= _packCount + collections.length ? 0 : _tab;
    final collection = tab >= _packCount ? collections[tab - _packCount] : null;

    final String label;
    final Widget body;
    if (collection != null) {
      label = collection.name.toUpperCase();
      body = collection.isEmpty
          ? _Empty(
              'Nothing here yet. Long-press a sticker, or save a GIF, video '
              'or audio from a chat.',
            )
          : _Grid(
              count: collection.items.length,
              builder: (i) => _CollectionTile(
                item: collection.items[i],
                onTap: () {
                  final item = collection.items[i];
                  if (item.isSticker) {
                    widget.onPick(item.stickerId!);
                  } else {
                    widget.onPickItem?.call(item);
                  }
                },
              ),
            );
    } else {
      final ids = tab < 0
          ? recent
          : [for (final s in stickerPacks[tab].stickers) s.id];
      label = tab < 0 ? 'RECENT' : stickerPacks[tab].name.toUpperCase();
      body = ids.isEmpty
          ? const _Empty('Stickers you send show up here.')
          : _Grid(
              count: ids.length,
              builder: (i) => GestureDetector(
                onTap: () => widget.onPick(ids[i]),
                onLongPress: widget.onSave == null
                    ? null
                    : () => widget.onSave!(ids[i]),
                child: StickerView(stickerId: ids[i], size: 72),
              ),
            );
    }

    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: AppColors.paperAlt,
        border: Border(top: BorderSide(color: AppColors.line, width: 2)),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                _TabButton(
                  label: 'Recent stickers',
                  selected: tab < 0,
                  onTap: () => setState(() => _tab = -1),
                  child: Icon(
                    Icons.history,
                    size: 18,
                    color: AppColors.textDim,
                  ),
                ),
                for (var i = 0; i < _packCount; i++)
                  _TabButton(
                    label: stickerPacks[i].name,
                    selected: tab == i,
                    onTap: () => setState(() => _tab = i),
                    child: StickerView(
                      stickerId: stickerPacks[i].stickers.first.id,
                      size: 26,
                    ),
                  ),
                for (var i = 0; i < collections.length; i++)
                  _TabButton(
                    label: collections[i].name,
                    selected: tab == _packCount + i,
                    wide: true,
                    onTap: () => setState(() => _tab = _packCount + i),
                  ),
                SizedBox(
                  width: 44,
                  height: 38,
                  child: IconButton(
                    key: const ValueKey('add-sticker-collection'),
                    tooltip: 'New collection',
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
            child: Text(label, style: AppTextStyles.fieldLabel),
          ),
          Expanded(child: body),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.selected,
    required this.onTap,
    this.child,
    this.wide = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// The icon; collections show their [label] instead.
  final Widget? child;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: wide ? 88 : 52,
          height: 38,
          alignment: Alignment.center,
          padding: wide ? const EdgeInsets.symmetric(horizontal: 6) : null,
          decoration: BoxDecoration(
            color: selected ? AppColors.paperRaised : Colors.transparent,
            border: Border(
              bottom: BorderSide(
                color: selected ? AppColors.primary : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child:
              child ??
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.fieldLabel.copyWith(
                  color: selected ? AppColors.primary : AppColors.textDim,
                ),
              ),
        ),
      ),
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({required this.count, required this.builder});

  final int count;
  final Widget Function(int index) builder;

  @override
  Widget build(BuildContext context) => GridView.builder(
    padding: const EdgeInsets.all(10),
    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 80,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
    ),
    itemCount: count,
    itemBuilder: (_, i) => builder(i),
  );
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: AppTextStyles.smallDim,
      ),
    ),
  );
}

/// One saved item: the sticker itself, the GIF playing, or a labelled tile
/// for a video or audio file.
class _CollectionTile extends ConsumerWidget {
  const _CollectionTile({required this.item, required this.onTap});

  final StickerCollectionItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Widget content;
    if (item.isSticker) {
      content = StickerView(stickerId: item.stickerId!, size: 72);
    } else if (item.isGif) {
      final dir = ref.watch(savedMediaDirProvider).value;
      content = dir == null || item.file == null
          ? _FileTile(icon: Icons.gif_outlined, label: 'GIF')
          : Image.file(
              File('$dir/${item.file}'),
              fit: BoxFit.contain,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) =>
                  _FileTile(icon: Icons.broken_image_outlined, label: 'GIF'),
            );
    } else {
      content = _FileTile(
        icon: item.isVideo ? Icons.movie_outlined : Icons.audiotrack_outlined,
        label: collectionItemLabel(item),
      );
    }
    return Semantics(
      button: true,
      label: collectionItemLabel(item),
      child: GestureDetector(onTap: onTap, child: content),
    );
  }
}

class _FileTile extends StatelessWidget {
  const _FileTile({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: AppColors.paperRaised,
      border: Border.all(color: AppColors.lineSoft, width: 1.5),
    ),
    padding: const EdgeInsets.all(4),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 26, color: AppColors.textDim),
        const SizedBox(height: 4),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.smallDim,
        ),
      ],
    ),
  );
}
