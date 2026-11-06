import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/data/services/media_library.dart';
import 'package:serafim/src/providers/media_library_providers.dart';
import 'package:serafim/src/utils/media_picker/media_widgets.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

/// The newest photos and videos, in the paperclip sheet. Empty where there is
/// no library to read.
class RecentMediaStrip extends ConsumerStatefulWidget {
  const RecentMediaStrip({
    super.key,
    required this.filter,
    required this.onSend,
    required this.onSeeAll,
  });

  final MediaFilter filter;
  final ValueChanged<List<DeviceMedia>> onSend;
  final VoidCallback onSeeAll;

  /// How many are loaded here: Gallery has the rest.
  static const count = 30;

  @override
  ConsumerState<RecentMediaStrip> createState() => _RecentMediaStripState();
}

class _RecentMediaStripState extends ConsumerState<RecentMediaStrip> {
  MediaAccess? _access;
  bool _refused = false;
  List<DeviceMedia> _items = const [];
  final _selection = MediaSelection();

  MediaLibrary get _library => ref.read(mediaLibraryProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool ask = false}) async {
    try {
      final access = ask
          ? await _library.request(widget.filter)
          : await _library.access(widget.filter);
      var items = const <DeviceMedia>[];
      if (access.canRead) {
        final albums = await _library.albums(widget.filter);
        if (albums.isNotEmpty) {
          items = await _library.page(albums.first, 0, RecentMediaStrip.count);
        }
      }
      if (!mounted) return;
      setState(() {
        _access = access;
        _refused = ask && !access.canRead;
        _items = items;
      });
    } catch (_) {
      if (mounted) setState(() => _access = MediaAccess.unavailable);
    }
  }

  void _toggle(DeviceMedia m) {
    final fits = _selection.toggle(m);
    setState(() {});
    if (!fits) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(
            content: Text('You can send $maxMediaPick at a time.'),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final access = _access;
    if (access == null || access == MediaAccess.unavailable) {
      return const SizedBox.shrink();
    }
    if (!access.canRead) {
      return MediaAccessCard(
        key: const ValueKey('recent-access'),
        text: 'Allow access to see your recent photos here.',
        refused: _refused,
        onAllow: () => _load(ask: true),
        onSettings: _library.openSettings,
      );
    }
    if (_items.isEmpty) return const SizedBox.shrink();
    final chosen = _selection.items.length;
    return Column(
      key: const ValueKey('recent-strip'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('RECENT', style: AppTextStyles.fieldLabel),
            const Spacer(),
            if (chosen > 0)
              FilledButton(
                key: const ValueKey('recent-send'),
                onPressed: () => widget.onSend(List.of(_selection.items)),
                child: Text('SEND $chosen'),
              )
            else
              TextButton(
                key: const ValueKey('recent-all'),
                onPressed: widget.onSeeAll,
                child: Text('See all', style: AppTextStyles.linkText),
              ),
          ],
        ),
        SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 4),
            itemBuilder: (_, i) => SizedBox(
              width: 96,
              child: MediaThumb(
                media: _items[i],
                position: _selection.positionOf(_items[i]),
                onTap: () => _toggle(_items[i]),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
