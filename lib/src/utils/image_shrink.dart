import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;

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

  final encoded = Uint8List.fromList(img.encodeJpg(resized, quality: args.quality));
  // Never return something bigger than what we were given.
  return encoded.length < args.bytes.length ? encoded : args.bytes;
}
