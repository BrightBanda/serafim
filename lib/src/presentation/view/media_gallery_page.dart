import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/data/services/media_library.dart';
import 'package:serafim/src/providers/media_library_providers.dart';
import 'package:serafim/src/utils/app_top_bar.dart';
import 'package:serafim/src/utils/media_picker/media_widgets.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

/// Popped when the person would rather use the system's file browser.
const browseFiles = 'browse-files';

/// The phone's photos and videos, inside Serafim, so the app is never in the
/// background where Android may close it. Pops the chosen [DeviceMedia] list,
/// or [browseFiles].
class MediaGalleryPage extends ConsumerStatefulWidget {
  const MediaGalleryPage({super.key, required this.filter});

  final MediaFilter filter;

  static const pageSize = 60;

  @override
  ConsumerState<MediaGalleryPage> createState() => _MediaGalleryPageState();
}

class _MediaGalleryPageState extends ConsumerState<MediaGalleryPage> {
  final _selection = MediaSelection();
  final _scroll = ScrollController();
  MediaAccess? _access;
  List<MediaAlbum> _albums = const [];
  MediaAlbum? _album;
  final List<DeviceMedia> _items = [];
  int _nextPage = 0;
  bool _loading = false;
  bool _atEnd = false;

  MediaLibrary get _library => ref.read(mediaLibraryProvider);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_nearEnd);
    _start();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final access = await _library.access(widget.filter);
    final albums = access.canRead
        ? await _library.albums(widget.filter)
        : const <MediaAlbum>[];
    if (!mounted) return;
    setState(() {
      _access = access;
      _albums = albums;
      _album = null;
    });
    if (albums.isNotEmpty) await _open(albums.first);
  }

  Future<void> _open(MediaAlbum album) async {
    setState(() {
      _album = album;
      _items.clear();
      _nextPage = 0;
      _atEnd = false;
    });
    await _loadMore();
  }

  void _nearEnd() {
    if (_scroll.position.extentAfter < 600) _loadMore();
  }

  Future<void> _loadMore() async {
    final album = _album;
    if (_loading || _atEnd || album == null) return;
    _loading = true;
    try {
      final more = await _library.page(
        album,
        _nextPage,
        MediaGalleryPage.pageSize,
      );
      if (!mounted || _album != album) return;
      setState(() {
        _items.addAll(more);
        _nextPage++;
        _atEnd = more.length < MediaGalleryPage.pageSize;
      });
    } finally {
      _loading = false;
    }
  }

  Future<void> _selectMore() async {
    await _library.selectMore(widget.filter);
    if (mounted) await _start();
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
    final chosen = _selection.items.length;
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppTopBar(
        title: 'GALLERY',
        onBack: () => Navigator.of(context).pop(),
        trailing: TextButton(
          key: const ValueKey('gallery-browse'),
          onPressed: () => Navigator.of(context).pop(browseFiles),
          child: Text('Browse files', style: AppTextStyles.linkText),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_albums.length > 1)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: DropdownButton<MediaAlbum>(
                  key: const ValueKey('gallery-album'),
                  value: _album,
                  isExpanded: true,
                  dropdownColor: AppColors.paperAlt,
                  underline: const SizedBox.shrink(),
                  style: AppTextStyles.body,
                  items: [
                    for (final a in _albums)
                      DropdownMenuItem(value: a, child: Text(a.name)),
                  ],
                  onChanged: (a) {
                    if (a != null) _open(a);
                  },
                ),
              ),
            if (_access == MediaAccess.limited)
              ListTile(
                key: const ValueKey('gallery-select-more'),
                dense: true,
                leading: Icon(
                  Icons.add_photo_alternate_outlined,
                  color: AppColors.primaryPale,
                ),
                title: Text(
                  'You chose which photos Serafim can see.',
                  style: AppTextStyles.smallDim,
                ),
                trailing: Text('Select more', style: AppTextStyles.linkText),
                onTap: _selectMore,
              ),
            Expanded(
              child: _access == null
                  ? const SizedBox.shrink()
                  : _items.isEmpty && _atEnd || !_access!.canRead
                  ? Center(
                      child: Text(
                        'Nothing to show here.',
                        style: AppTextStyles.smallDim,
                      ),
                    )
                  : GridView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.all(2),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            mainAxisSpacing: 2,
                            crossAxisSpacing: 2,
                          ),
                      itemCount: _items.length,
                      itemBuilder: (_, i) => MediaThumb(
                        media: _items[i],
                        position: _selection.positionOf(_items[i]),
                        onTap: () => _toggle(_items[i]),
                      ),
                    ),
            ),
            if (chosen > 0)
              Padding(
                padding: const EdgeInsets.all(10),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: const ValueKey('gallery-send'),
                    onPressed: () => Navigator.of(
                      context,
                    ).pop(List<DeviceMedia>.of(_selection.items)),
                    child: Text('SEND $chosen'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
