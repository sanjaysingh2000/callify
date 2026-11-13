import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:quick_call/features/profile/data/profile_image_compressor.dart';

void main() {
  test('compresses profile images under the encoded byte limit', () {
    final source = img.Image(width: 1200, height: 900);
    img.fill(source, color: img.ColorRgb8(180, 120, 90));

    final compressedBase64 = ProfileImageCompressor.compressToBase64(
      img.encodePng(source),
    );
    final compressedBytes = base64Decode(compressedBase64);
    final decoded = img.decodeImage(compressedBytes);

    expect(compressedBytes.length, lessThanOrEqualTo(96 * 1024));
    expect(decoded, isNotNull);
    expect(decoded!.width, lessThanOrEqualTo(512));
    expect(decoded.height, lessThanOrEqualTo(512));
  });

  test('rejects unsupported image data', () {
    expect(
      () => ProfileImageCompressor.compressToBase64(
        Uint8List.fromList([1, 2, 3]),
      ),
      throwsFormatException,
    );
  });
}
