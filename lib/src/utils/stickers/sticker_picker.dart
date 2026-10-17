import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/providers/sticker_providers.dart';
import 'package:serafim/src/utils/stickers/sticker_packs.dart';
import 'package:serafim/src/utils/stickers/sticker_view.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

/// The panel under the composer: recently used stickers, then one tab per
/// pack. Tapping a sticker sends it.
class StickerPicker extends ConsumerStatefulWidget {
  const StickerPicker({super.key, required this.onPick, this.height = 260});

  final ValueChanged<String> onPick;
  final double height;

  @override
  ConsumerState<StickerPicker> createState() => _StickerPickerState();
}

class _StickerPickerState extends ConsumerState<StickerPicker> {
  int _tab = -1; // -1 = recent

  @override
  void initState() {
    super.initState();
    // Open on the first pack when nothing has been used yet.
    if (ref.read(recentStickersProvider).isEmpty) _tab = 0;
  }

  @override
  Widget build(BuildContext context) {
    final recent = ref.watch(recentStickersProvider);
    final ids = _tab < 0
        ? recent
        : [for (final s in stickerPacks[_tab].stickers) s.id];

    Widget tab(int index, Widget icon, String label) {
      final selected = _tab == index;
      return Semantics(
        button: true,
        selected: selected,
        label: label,
        child: GestureDetector(
          onTap: () => setState(() => _tab = index),
          child: Container(
            width: 46,
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
            child: icon,
          ),
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
          Row(
            children: [
              tab(
                -1,
                Icon(Icons.history, size: 18, color: AppColors.textDim),
                'Recent stickers',
              ),
              for (var i = 0; i < stickerPacks.length; i++)
                tab(
                  i,
                  StickerView(
                    stickerId: stickerPacks[i].stickers.first.id,
                    size: 26,
                  ),
                  stickerPacks[i].name,
                ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Text(
                  _tab < 0 ? 'RECENT' : stickerPacks[_tab].name.toUpperCase(),
                  style: AppTextStyles.fieldLabel,
                ),
              ),
            ],
          ),
          Expanded(
            child: ids.isEmpty
                ? Center(
                    child: Text(
                      'Stickers you send show up here.',
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
                    itemCount: ids.length,
                    itemBuilder: (_, i) => GestureDetector(
                      onTap: () => widget.onPick(ids[i]),
                      child: StickerView(stickerId: ids[i], size: 72),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
