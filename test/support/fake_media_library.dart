import 'dart:io';
import 'dart:typed_data';

import 'package:serafim/src/data/services/media_library.dart';

/// A one-pixel PNG, so thumbnails really decode.
final Uint8List onePixel = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49,
  0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06,
  0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44,
  0x41, 0x54, 0x78, 0x9C, 0x63, 0xF8, 0xCF, 0xC0, 0xF0, 0x1F, 0x00, 0x05, 0x00,
  0x01, 0xFF, 0x89, 0x99, 0x3D, 0x1D, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E,
  0x44, 0xAE, 0x42, 0x60, 0x82,
]);

class FakeMedia implements DeviceMedia {
  FakeMedia(this.id, {this.isVideo = false, this.isAudio = false});

  @override
  final String id;
  @override
  final bool isVideo;
  @override
  final bool isAudio;
  @override
  Duration get duration => const Duration(minutes: 1, seconds: 5);
  @override
  Future<String> name() async => '$id.${isAudio ? 'mp3' : 'jpg'}';
  @override
  Future<Uint8List?> thumbnail(int side) async => onePixel;
  @override
  Future<File?> file() async => null;
  @override
  Future<Uint8List?> photoForSending({
    required int maxSide,
    required int quality,
  }) async => onePixel;
}

List<FakeMedia> fakeItems(int count, {bool audio = false}) => [
  for (var i = 0; i < count; i++) FakeMedia('m$i', isAudio: audio),
];

class FakeLibrary implements MediaLibrary {
  FakeLibrary({
    this.items = const [],
    this.current = MediaAccess.full,
    this.afterRequest = MediaAccess.full,
    this.albumNames = const ['Recent'],
  });

  List<DeviceMedia> items;
  MediaAccess current;
  MediaAccess afterRequest;
  List<String> albumNames;
  int requests = 0;
  int settingsOpened = 0;
  int selectMoreCalls = 0;
  final pagesAsked = <int>[];

  @override
  Future<MediaAccess> access(MediaFilter filter) async => current;
  @override
  Future<MediaAccess> request(MediaFilter filter) async {
    requests++;
    return current = afterRequest;
  }

  @override
  Future<void> openSettings() async => settingsOpened++;
  @override
  Future<void> selectMore(MediaFilter filter) async => selectMoreCalls++;
  @override
  Future<List<MediaAlbum>> albums(MediaFilter filter) async => [
    for (final n in albumNames) MediaAlbum(id: n, name: n),
  ];
  @override
  Future<List<DeviceMedia>> page(MediaAlbum album, int page, int size) async {
    pagesAsked.add(page);
    final start = page * size;
    if (start >= items.length) return const [];
    final end = start + size > items.length ? items.length : start + size;
    return items.sublist(start, end);
  }
}
