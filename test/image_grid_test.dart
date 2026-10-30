import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:serafim/src/utils/image_shrink.dart';

Uint8List _photo(int red, int green, int blue) => Uint8List.fromList(
  img.encodePng(
    img.Image(
      width: 20,
      height: 20,
      numChannels: 3,
      backgroundColor: img.ColorRgb8(red, green, blue),
    ),
  ),
);

void main() {
  test('four photos compose into a two-column, two-row grid', () async {
    final bytes = await composeImageGrid(
      [
        _photo(255, 0, 0),
        _photo(0, 255, 0),
        _photo(0, 0, 255),
        _photo(0, 0, 0),
      ],
      maxSide: 120,
      quality: 90,
    );
    final decoded = img.decodeImage(bytes)!;

    expect(decoded.width, 120);
    expect(decoded.height, 120);
  });

  test('six photos compose into the full two-column, three-row grid', () async {
    final bytes = await composeImageGrid(
      [
        _photo(255, 0, 0),
        _photo(0, 255, 0),
        _photo(0, 0, 255),
        _photo(0, 0, 0),
        _photo(255, 255, 0),
        _photo(255, 0, 255),
      ],
      maxSide: 120,
      quality: 90,
    );
    final decoded = img.decodeImage(bytes)!;

    expect(decoded.width, lessThan(decoded.height));
    expect(decoded.height, 120);
  });

  test('multi-photo grid rejects unsupported counts', () async {
    await expectLater(
      composeImageGrid([_photo(255, 0, 0)], maxSide: 120),
      throwsArgumentError,
    );
  });
}
