import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;
import 'package:serafim/src/data/models/app_settings.dart';

/// Downscales and re-encodes [bytes] as JPEG so images stay small enough to
/// relay over the socket and keep in the local database.
///
/// Runs in a background isolate. If the bytes cannot be decoded, they are
/// returned untouched rather than failing the send.
Future<Uint8List> shrinkImage(
  Uint8List bytes, {
  int maxSide = 1280,
  int quality = 75,
}) {
  return compute(_shrink, (bytes: bytes, maxSide: maxSide, quality: quality));
}

Uint8List _shrink(({Uint8List bytes, int maxSide, int quality}) args) {
  final decoded = img.decodeImage(args.bytes);
  if (decoded == null) return args.bytes;

  final oriented = img.bakeOrientation(decoded);
  final longest = oriented.width > oriented.height
      ? oriented.width
      : oriented.height;

  final resized = longest > args.maxSide
      ? img.copyResize(
          oriented,
          width: oriented.width >= oriented.height ? args.maxSide : null,
          height: oriented.height > oriented.width ? args.maxSide : null,
          interpolation: img.Interpolation.average,
        )
      : oriented;

  final encoded = Uint8List.fromList(
    img.encodeJpg(resized, quality: args.quality),
  );
  // Never return something bigger than what we were given.
  return encoded.length < args.bytes.length ? encoded : args.bytes;
}

/// Largest keyboard GIF/sticker sent as-is (base64 must stay under the
/// server's ~3 MB relay limit).
const maxRawInsertBytes = 2 * 1024 * 1024;

/// Readies an image inserted from the keyboard for sending. GIFs, WebP and
/// PNG (animated or transparent stickers) go as they are when small enough;
/// JPEGs, and too-large PNGs, are shrunk. Returns null when it can't be sent.
Future<Uint8List?> prepareInsertedImage(
  Uint8List bytes,
  String mimeType, {
  required ImageQuality quality,
}) async {
  final keepAsIs =
      mimeType == 'image/gif' ||
      mimeType == 'image/webp' ||
      mimeType == 'image/png';
  if (keepAsIs && bytes.length <= maxRawInsertBytes) return bytes;
  if (mimeType == 'image/gif' || mimeType == 'image/webp') return null;
  final shrunk = await shrinkImage(
    bytes,
    maxSide: quality.maxSide,
    quality: quality.jpegQuality,
  );
  return shrunk.length <= maxRawInsertBytes ? shrunk : null;
}
