import 'dart:io';
import 'dart:typed_data';

import 'package:photo_manager/photo_manager.dart';
import 'package:serafim/src/utils/image_shrink.dart';

/// What Serafim may read from the phone's media.
enum MediaAccess {
  /// Not on this platform (desktop, tests): use the system picker.
  unavailable,
  denied,

  /// Only what the person chose to share (Android 14 and up).
  limited,
  full;

  bool get canRead => this == limited || this == full;
}

/// Which media a screen is about.
enum MediaFilter {
  /// Photos and videos.
  visual,

  /// Videos only: a chat that can't take pictures.
  videos,
  audio,
}

/// A photo, video or audio file on the phone. Nothing is read until asked for,
/// so a long list costs almost nothing.
abstract class DeviceMedia {
  String get id;
  bool get isVideo;
  bool get isAudio;
  Duration get duration;

  /// Its name, with extension.
  Future<String> name();

  /// A small JPEG to show in a list.
  Future<Uint8List?> thumbnail(int side);

  /// The file itself, or null if it has gone.
  Future<File?> file();

  /// A photo ready to send: shrunk to [maxSide], as JPEG.
  Future<Uint8List?> photoForSending({
    required int maxSide,
    required int quality,
  });
}

/// A folder of media ("Recent", "Camera", …).
class MediaAlbum {
  const MediaAlbum({required this.id, required this.name, this.handle});
  final String id;
  final String name;

  /// What the library needs to read it.
  final Object? handle;
}

/// The phone's media. Abstracted so the screens can be tested without a phone.
abstract interface class MediaLibrary {
  Future<MediaAccess> access(MediaFilter filter);

  /// Shows Android's permission prompt (if Android still allows asking).
  Future<MediaAccess> request(MediaFilter filter);
  Future<void> openSettings();

  /// With [MediaAccess.limited]: lets the person share more.
  Future<void> selectMore(MediaFilter filter);

  /// The first album is everything, newest first.
  Future<List<MediaAlbum>> albums(MediaFilter filter);
  Future<List<DeviceMedia>> page(MediaAlbum album, int page, int size);
}

/// Not on this platform.
class NoMediaLibrary implements MediaLibrary {
  const NoMediaLibrary();
  @override
  Future<MediaAccess> access(MediaFilter filter) async =>
      MediaAccess.unavailable;
  @override
  Future<MediaAccess> request(MediaFilter filter) async =>
      MediaAccess.unavailable;
  @override
  Future<void> openSettings() async {}
  @override
  Future<void> selectMore(MediaFilter filter) async {}
  @override
  Future<List<MediaAlbum>> albums(MediaFilter filter) async => const [];
  @override
  Future<List<DeviceMedia>> page(MediaAlbum album, int page, int size) async =>
      const [];
}

RequestType _typeOf(MediaFilter filter) => switch (filter) {
  MediaFilter.visual => RequestType.common,
  MediaFilter.videos => RequestType.video,
  MediaFilter.audio => RequestType.audio,
};

MediaAccess _accessOf(PermissionState state) => switch (state) {
  PermissionState.authorized => MediaAccess.full,
  PermissionState.limited => MediaAccess.limited,
  _ => MediaAccess.denied,
};

/// The real library, on Android's media store.
class PhoneMediaLibrary implements MediaLibrary {
  const PhoneMediaLibrary();

  static PermissionRequestOption _option(MediaFilter filter) =>
      PermissionRequestOption(
        androidPermission: AndroidPermission(
          type: _typeOf(filter),
          mediaLocation: false,
        ),
      );

  @override
  Future<MediaAccess> access(MediaFilter filter) async => _accessOf(
    await PhotoManager.getPermissionState(requestOption: _option(filter)),
  );

  @override
  Future<MediaAccess> request(MediaFilter filter) async => _accessOf(
    await PhotoManager.requestPermissionExtend(requestOption: _option(filter)),
  );

  @override
  Future<void> openSettings() => PhotoManager.openSetting();

  @override
  Future<void> selectMore(MediaFilter filter) =>
      PhotoManager.presentLimited(type: _typeOf(filter));

  @override
  Future<List<MediaAlbum>> albums(MediaFilter filter) async {
    final paths = await PhotoManager.getAssetPathList(
      type: _typeOf(filter),
      filterOption: FilterOptionGroup(
        orders: [
          const OrderOption(type: OrderOptionType.createDate, asc: false),
        ],
      ),
    );
    return [
      for (final p in paths) MediaAlbum(id: p.id, name: p.name, handle: p),
    ];
  }

  @override
  Future<List<DeviceMedia>> page(MediaAlbum album, int page, int size) async {
    final assets = await (album.handle! as AssetPathEntity).getAssetListPaged(
      page: page,
      size: size,
    );
    return [for (final a in assets) _PhoneMedia(a)];
  }
}

class _PhoneMedia implements DeviceMedia {
  _PhoneMedia(this._asset);
  final AssetEntity _asset;

  @override
  String get id => _asset.id;
  @override
  bool get isVideo => _asset.type == AssetType.video;
  @override
  bool get isAudio => _asset.type == AssetType.audio;
  @override
  Duration get duration => _asset.videoDuration;

  @override
  Future<String> name() => _asset.titleAsync;

  @override
  Future<Uint8List?> thumbnail(int side) =>
      _asset.thumbnailDataWithSize(ThumbnailSize.square(side));

  @override
  Future<File?> file() => _asset.file;

  @override
  Future<Uint8List?> photoForSending({
    required int maxSide,
    required int quality,
  }) async {
    final title = (await _asset.titleAsync).toLowerCase();
    // Our own shrinking can't read HEIC; Android can.
    if (title.endsWith('.heic') || title.endsWith('.heif')) {
      return _asset.thumbnailDataWithSize(
        ThumbnailSize.square(maxSide),
        quality: quality,
      );
    }
    final file = await _asset.file;
    if (file == null) return null;
    return shrinkImage(
      await file.readAsBytes(),
      maxSide: maxSide,
      quality: quality,
    );
  }
}
