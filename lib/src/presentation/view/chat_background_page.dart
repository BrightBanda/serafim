import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/core/errors/human_error.dart';
import 'package:serafim/src/data/models/chat_wallpaper.dart';
import 'package:serafim/src/providers/wallpaper_providers.dart';
import 'package:serafim/src/utils/app_top_bar.dart';
import 'package:serafim/src/utils/chat/chat_background.dart';
import 'package:serafim/src/utils/chat/chat_bubble.dart';
import 'package:serafim/src/utils/image_picking.dart';
import 'package:serafim/src/utils/serafim_button.dart';
import 'package:serafim/src/utils/settings_widgets.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

void openChatBackgroundPage(BuildContext context, {required String roomId}) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => ChatBackgroundPage(roomId: roomId)),
  );
}

/// Pick a chat's background: the doodle pattern, plain, a preset colour or
/// gradient, or a photo from the gallery — for this chat or for all of them.
class ChatBackgroundPage extends ConsumerStatefulWidget {
  const ChatBackgroundPage({super.key, required this.roomId});

  final String roomId;

  @override
  ConsumerState<ChatBackgroundPage> createState() => _ChatBackgroundPageState();
}

class _ChatBackgroundPageState extends ConsumerState<ChatBackgroundPage> {
  late ChatWallpaper _selected = ref.read(roomWallpaperProvider(widget.roomId));
  bool _applyToAll = false;
  bool _picking = false;
  bool _saving = false;

  void _tell(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(content: Text(message), backgroundColor: AppColors.rust),
      );
  }

  Future<void> _pickFromGallery() async {
    if (_picking) return;
    try {
      final bytes = await pickShrunkImage(
        context,
        maxSide: 1920,
        quality: 82,
        onPicked: () {
          if (mounted) setState(() => _picking = true);
        },
      );
      if (bytes == null) return;
      final path = await ref.read(wallpaperImageStoreProvider).save(bytes);
      if (mounted) setState(() => _selected = ChatWallpaper.image(path));
    } catch (error) {
      _tell(humanError(error, fallback: "Couldn't use that photo."));
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref
          .read(wallpaperProvider.notifier)
          .choose(widget.roomId, _selected, applyToAll: _applyToAll);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      _tell(humanError(error, fallback: "Couldn't save the background."));
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _reset() async {
    await ref.read(wallpaperProvider.notifier).resetRoom(widget.roomId);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final hasOwn = ref.watch(roomHasOwnWallpaperProvider(widget.roomId));

    Widget tile(ChatWallpaper w, String label) => _WallpaperTile(
      label: label,
      selected: _selected == w,
      onTap: () => setState(() => _selected = w),
      child: ChatWallpaperView(wallpaper: w),
    );

    String titleCase(String id) => id[0].toUpperCase() + id.substring(1);

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppTopBar(
        title: 'CHAT BACKGROUND',
        onBack: _saving ? null : () => Navigator.of(context).pop(),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          children: [
            _Preview(wallpaper: _selected),
            const SizedBox(height: 20),
            const SettingsSectionLabel('Patterns'),
            _TileWrap(
              children: [
                tile(ChatWallpaper.doodles, 'Doodles'),
                tile(ChatWallpaper.plain, 'Plain'),
              ],
            ),
            const SizedBox(height: 14),
            const SettingsSectionLabel('Colours'),
            _TileWrap(
              children: [
                for (final id in wallpaperColors.keys)
                  tile(ChatWallpaper.color(id), titleCase(id)),
              ],
            ),
            const SizedBox(height: 14),
            const SettingsSectionLabel('Gradients'),
            _TileWrap(
              children: [
                for (final id in wallpaperGradients.keys)
                  tile(ChatWallpaper.gradient(id), titleCase(id)),
              ],
            ),
            const SizedBox(height: 14),
            const SettingsSectionLabel('Your photo'),
            _TileWrap(
              children: [
                if (_selected.kind == WallpaperKind.image)
                  tile(_selected, 'Chosen'),
                _WallpaperTile(
                  label: _picking ? 'Preparing…' : 'Gallery',
                  selected: false,
                  onTap: _picking ? null : _pickFromGallery,
                  child: ColoredBox(
                    color: AppColors.paperAlt,
                    child: Center(
                      child: _picking
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.primary,
                              ),
                            )
                          : Icon(
                              Icons.add_photo_alternate_outlined,
                              color: AppColors.primaryPale,
                            ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            SettingsSwitchRow(
              title: 'Apply to all chats',
              subtitle:
                  'Use this background everywhere, replacing any '
                  'chat-specific ones.',
              value: _applyToAll,
              onChanged: (v) => setState(() => _applyToAll = v),
            ),
            const SettingsNote(
              'Backgrounds are saved on this device. Photos are dimmed a '
              'little so messages stay easy to read.',
            ),
            SerafimButton(
              label: _saving ? 'Saving…' : 'Set background',
              onPressed: _saving || _picking ? null : _save,
            ),
            if (hasOwn && !_saving) ...[
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: _reset,
                  child: Text(
                    'Use the default background for this chat',
                    style: AppTextStyles.linkText,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A small chat drawn over the chosen background.
class _Preview extends StatelessWidget {
  const _Preview({required this.wallpaper});

  final ChatWallpaper wallpaper;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.line, width: 2),
        boxShadow: [
          BoxShadow(
            color: AppColors.line,
            offset: const Offset(3, 3),
            blurRadius: 0,
          ),
        ],
      ),
      child: ClipRect(
        child: Stack(
          children: [
            Positioned.fill(child: ChatWallpaperView(wallpaper: wallpaper)),
            const Padding(
              padding: EdgeInsets.all(12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ChatBubble(
                    who: 'Sam · 09:41',
                    message: 'How does this look?',
                    side: ChatBubbleSide.incoming,
                  ),
                  SizedBox(height: 8),
                  ChatBubble(
                    who: 'You · 09:42',
                    message: 'Easy to read 👌',
                    side: ChatBubbleSide.outgoing,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TileWrap extends StatelessWidget {
  const _TileWrap({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) =>
      Wrap(spacing: 10, runSpacing: 10, children: children);
}

class _WallpaperTile extends StatelessWidget {
  const _WallpaperTile({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.child,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '$label background',
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 70,
          child: Column(
            children: [
              Container(
                width: 70,
                height: 96,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: selected ? AppColors.primary : AppColors.lineSoft,
                    width: selected ? 3 : 1.5,
                  ),
                ),
                child: ClipRect(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      child,
                      if (selected)
                        Align(
                          alignment: Alignment.topRight,
                          child: Container(
                            margin: const EdgeInsets.all(4),
                            padding: const EdgeInsets.all(2),
                            color: AppColors.primary,
                            child: const Icon(
                              Icons.check,
                              size: 12,
                              color: Colors.white,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.fieldLabel.copyWith(
                  color: selected ? AppColors.primaryPale : AppColors.textDim,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
