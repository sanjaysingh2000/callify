import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

class ProfileImageCompressor {
  static const int maxEncodedBytes = 96 * 1024;
  static const int maxDimension = 512;

  static String compressToBase64(Uint8List input) {
    final decoded = img.decodeImage(input);
    if (decoded == null) {
      throw const FormatException(
        'The selected file is not a supported image.',
      );
    }

    final oriented = img.bakeOrientation(decoded);
    final longestSide = math.max(oriented.width, oriented.height);
    var dimension = math.min(maxDimension, longestSide);

    for (var attempt = 0; attempt < 10; attempt++) {
      final scale = dimension / longestSide;
      final width = math.max(1, (oriented.width * scale).round());
      final height = math.max(1, (oriented.height * scale).round());
      final resized = img.copyResize(oriented, width: width, height: height);
      final quality = math.max(45, 78 - attempt * 5);
      final compressed = img.encodeJpg(resized, quality: quality);
      if (compressed.length <= maxEncodedBytes) {
        return base64Encode(compressed);
      }

      dimension = (dimension * 0.8).round();
    }

    throw StateError(
      'Could not compress this photo enough. Please choose another image.',
    );
  }
}
