import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:serafim/src/data/services/media_library.dart';
import 'package:serafim/src/presentation/view/media_gallery_page.dart'
    show browseFiles;
import 'package:serafim/src/providers/media_library_providers.dart';
import 'package:serafim/src/utils/app_top_bar.dart';
import 'package:serafim/src/utils/media_picker/media_widgets.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

/// The audio files on the phone, inside Serafim. Tap one to send it; the play
/// button checks it first. Pops the [DeviceMedia], or [browseFiles].
class AudioLibraryPage extends ConsumerStatefulWidget {
  const AudioLibraryPage({super.key});

  @override
  ConsumerState<AudioLibraryPage> createState() => _AudioLibraryPageState();
}

class _AudioLibraryPageState extends ConsumerState<AudioLibraryPage> {
  List<DeviceMedia>? _items;
  AudioPlayer? _player;
  String? _playing;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final library = ref.read(mediaLibraryProvider);
    final albums = await library.albums(MediaFilter.audio);
    final items = albums.isEmpty
        ? const <DeviceMedia>[]
        : await library.page(albums.first, 0, 500);
    if (mounted) setState(() => _items = items);
  }

  Future<void> _togglePreview(DeviceMedia m) async {
    final player = _player ??= AudioPlayer();
    if (_playing == m.id) {
      await player.stop();
      if (mounted) setState(() => _playing = null);
      return;
    }
    setState(() => _playing = m.id);
    try {
      final file = await m.file();
      if (file == null || !mounted) return;
      await player.stop();
      await player.setFilePath(file.path);
      // Not awaited: this only finishes when the sound does.
      player.play().whenComplete(() {
        if (mounted && _playing == m.id) setState(() => _playing = null);
      }).ignore();
    } catch (_) {
      if (mounted) {
        setState(() => _playing = null);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("That file can't be played.")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppTopBar(
        title: 'AUDIO',
        onBack: () => Navigator.of(context).pop(),
        trailing: TextButton(
          key: const ValueKey('audio-browse'),
          onPressed: () => Navigator.of(context).pop(browseFiles),
          child: Text('Browse files', style: AppTextStyles.linkText),
        ),
      ),
      body: SafeArea(
        child: items == null
            ? const SizedBox.shrink()
            : items.isEmpty
            ? Center(
                child: Text(
                  'No audio files found.',
                  style: AppTextStyles.smallDim,
                ),
              )
            : ListView.builder(
                itemCount: items.length,
                itemBuilder: (_, i) => _AudioRow(
                  media: items[i],
                  playing: _playing == items[i].id,
                  onPreview: () => _togglePreview(items[i]),
                  onChoose: () => Navigator.of(context).pop(items[i]),
                ),
              ),
      ),
    );
  }
}

class _AudioRow extends StatefulWidget {
  const _AudioRow({
    required this.media,
    required this.playing,
    required this.onPreview,
    required this.onChoose,
  });

  final DeviceMedia media;
  final bool playing;
  final VoidCallback onPreview;
  final VoidCallback onChoose;

  @override
  State<_AudioRow> createState() => _AudioRowState();
}

class _AudioRowState extends State<_AudioRow> {
  late final _name = widget.media.name();

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: ValueKey('audio-${widget.media.id}'),
      onTap: widget.onChoose,
      leading: IconButton(
        key: ValueKey('audio-play-${widget.media.id}'),
        tooltip: widget.playing ? 'Stop' : 'Play',
        icon: Icon(
          widget.playing ? Icons.stop_rounded : Icons.play_arrow_rounded,
          color: AppColors.primaryPale,
        ),
        onPressed: widget.onPreview,
      ),
      title: FutureBuilder<String>(
        future: _name,
        builder: (_, snap) => Text(
          snap.data ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.body,
        ),
      ),
      subtitle: Text(
        formatMediaDuration(widget.media.duration),
        style: AppTextStyles.smallDim,
      ),
      trailing: Icon(Icons.send_rounded, size: 18, color: AppColors.textDim),
    );
  }
}
