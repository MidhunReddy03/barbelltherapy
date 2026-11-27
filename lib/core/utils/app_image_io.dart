import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'image_utils.dart';

/// Native (Android / iOS / desktop) implementation of [AppImage].
///
/// Images are stored as real files under the app documents `images/`
/// folder; stored references are file paths.
class AppImage {
  AppImage._();

  static Uint8List? _decodeDataUri(String path) {
    final comma = path.indexOf(',');
    if (comma < 0) return null;
    try {
      return base64Decode(path.substring(comma + 1));
    } catch (_) {
      return null;
    }
  }

  /// Displays the stored image, or an empty box when unavailable.
  static Widget view(
    String? path, {
    BoxFit fit = BoxFit.cover,
    double? width,
    double? height,
  }) {
    if (path == null || path.isEmpty) return const SizedBox.shrink();
    if (path.startsWith('data:')) {
      final bytes = _decodeDataUri(path);
      if (bytes == null) return const SizedBox.shrink();
      return Image.memory(
        bytes,
        fit: fit,
        width: width,
        height: height,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      );
    }
    return Image.file(
      File(path),
      fit: fit,
      width: width,
      height: height,
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
    );
  }

  /// Synchronous existence check for a stored reference.
  static bool exists(String? path) {
    if (path == null || path.isEmpty) return false;
    if (path.startsWith('data:')) return _decodeDataUri(path) != null;
    return File(path).existsSync();
  }

  /// Reads the bytes behind a stored reference (logo embedding, PDFs).
  static Future<Uint8List?> readBytes(String? path) async {
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('data:')) return _decodeDataUri(path);
    try {
      return await File(path).readAsBytes();
    } catch (_) {
      return null;
    }
  }

  /// Persists a freshly picked image and returns the stored reference.
  ///
  /// [compress] compresses photos to 512 px / quality 80. QR codes and
  /// logos must be stored losslessly: pass `compress: false`.
  static Future<String?> store(
    XFile? picked, {
    required String prefix,
    bool compress = true,
  }) async {
    if (picked == null) return null;
    if (compress) {
      return ImageUtils.copyCompressedToAppStorage(picked.path, prefix: prefix);
    }
    // Lossless copy (QR / logo), same behaviour the onboarding screen had.
    final docs = await getApplicationDocumentsDirectory();
    final imagesDir = Directory('${docs.path}${Platform.pathSeparator}images');
    if (!imagesDir.existsSync()) imagesDir.createSync(recursive: true);
    final ext = picked.name.split('.').last.toLowerCase();
    final safeExt = (ext.length <= 5 && ext.isNotEmpty) ? ext : 'jpg';
    final target = File(
        '${imagesDir.path}${Platform.pathSeparator}${prefix}_${DateTime.now().millisecondsSinceEpoch}.$safeExt');
    await File(picked.path).copy(target.path);
    return target.path;
  }

  /// Shares arbitrary bytes (PNG card, PDF receipt) via the system share
  /// sheet.
  static Future<void> shareBytes({
    required List<int> bytes,
    required String fileName,
    required String mimeType,
    String? subject,
    String? text,
  }) async {
    final dir = await Directory.systemTemp.createTemp('gymdesk_share');
    final file = File(
        '${dir.path}${Platform.pathSeparator}$fileName');
    await file.writeAsBytes(bytes);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: mimeType)],
        subject: subject,
        text: text,
      ),
    );
  }
}
