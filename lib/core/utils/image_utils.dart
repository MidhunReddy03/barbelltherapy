import 'dart:io';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';

/// Photo picking/compression helpers (spec 6.4: max 512x512, ~100 KB JPEG,
/// stored in app storage so gallery changes can't break it).
class ImageUtils {
  ImageUtils._();

  /// Copies [source] into the app documents `images/` folder, compressed to
  /// max 512 px on the long side at quality 80. Returns the new path, or
  /// null when [source] is null.
  static Future<String?> copyCompressedToAppStorage(String? source,
      {String prefix = 'member'}) async {
    if (source == null || source.isEmpty) return null;
    final docs = await getApplicationDocumentsDirectory();
    final imagesDir = Directory('${docs.path}${Platform.pathSeparator}images');
    if (!imagesDir.existsSync()) imagesDir.createSync(recursive: true);
    final target =
        '${imagesDir.path}${Platform.pathSeparator}${prefix}_${DateTime.now().millisecondsSinceEpoch}.jpg';

    final compressed = await FlutterImageCompress.compressAndGetFile(
      source,
      target,
      quality: 80,
      minWidth: 512,
      minHeight: 512,
      format: CompressFormat.jpeg,
    );
    if (compressed != null) return compressed.path;

    // Compression can fail on some formats — fall back to a plain copy.
    final fallback = File(target);
    await File(source).copy(fallback.path);
    return target;
  }
}
