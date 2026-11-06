import 'dart:math' as math;

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

  /// How many are loaded at a time, as it is scrolled.
  static const pageSize = 40;

  @override
  ConsumerState<RecentMediaStrip> createState() => _RecentMediaStripState();
}

class _RecentMediaStripState extends ConsumerState<RecentMediaStrip> {
  MediaAccess? _access;
  bool _refused = false;
  List<DeviceMedia> _items = const [];
  final _selection = MediaSelection();
  final _scroll = ScrollController();
  MediaAlbum? _album;
  int _nextPage = 0;
  bool _loadingMore = false;
  bool _atEnd = false;

  MediaLibrary get _library => ref.read(mediaLibraryProvider);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 300) _loadMore();
    });
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadMore() async {
    final album = _album;
    if (_loadingMore || _atEnd || album == null) return;
    _loadingMore = true;
    try {
      final more = await _library.page(
        album,
        _nextPage,
        RecentMediaStrip.pageSize,
      );
      if (!mounted) return;
      setState(() {
        _items = [..._items, ...more];
        _nextPage++;
        _atEnd = more.length < RecentMediaStrip.pageSize;
      });
    } catch (_) {
      // Scrolling again retries.
    } finally {
      _loadingMore = false;
    }
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
          _album = albums.first;
          items = await _library.page(
            albums.first,
            0,
            RecentMediaStrip.pageSize,
          );
          _nextPage = 1;
          _atEnd = items.length < RecentMediaStrip.pageSize;
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
        // Up and down, like the gallery; the height leaves the options above
        // in view.
        SizedBox(
          height: math.min(340, MediaQuery.sizeOf(context).height * 0.42),
          child: GridView.builder(
            controller: _scroll,
            padding: EdgeInsets.zero,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 3,
              crossAxisSpacing: 3,
            ),
            itemCount: _items.length,
            itemBuilder: (_, i) => MediaThumb(
              media: _items[i],
              position: _selection.positionOf(_items[i]),
              onTap: () => _toggle(_items[i]),
            ),
          ),
        ),
      ],
    );
  }
}
