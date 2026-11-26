import 'dart:convert';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:share_plus/share_plus.dart';

/// Web implementation of [AppImage].
///
/// Browsers have no file system, so stored references are `data:` URIs
/// written into the same text columns (photo_path / qr_path / logo_path).
/// The drift database lives in IndexedDB, so the URIs persist across
/// sessions exactly like file paths do on native (see DECISIONS.md).
class AppImage {
  AppImage._();

  static Widget view(
    String? path, {
    BoxFit fit = BoxFit.cover,
    double? width,
    double? height,
  }) {
    if (path == null || path.isEmpty) return const SizedBox.shrink();
    // Image.network supports data: URIs directly.
    return Image.network(
      path,
      fit: fit,
      width: width,
      height: height,
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
    );
  }

  static bool exists(String? path) {
    if (path == null || path.isEmpty) return false;
    return path.startsWith('data:') || path.startsWith('blob:');
  }

  static Future<Uint8List?> readBytes(String? path) async {
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('data:')) {
      final comma = path.indexOf(',');
      if (comma < 0) return null;
      try {
        return base64Decode(path.substring(comma + 1));
      } catch (_) {
        return null;
      }
    }
    return null; // blob: URLs cannot be re-read in a later session
  }

  static Future<String?> store(
    XFile? picked, {
    required String prefix,
    bool compress = true,
  }) async {
    if (picked == null) return null;
    var bytes = await picked.readAsBytes();

    if (compress) {
      final compressed = await FlutterImageCompress.compressWithList(
        bytes,
        quality: 80,
        minWidth: 512,
        minHeight: 512,
        format: CompressFormat.jpeg,
      );
      bytes = compressed;
      return 'data:image/jpeg;base64,${base64Encode(bytes)}';
    }

    // Lossless (QR / logo): keep the original format bytes.
    final ext = picked.name.split('.').last.toLowerCase();
    final mime = switch (ext) {
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'webp' => 'image/webp',
      'gif' => 'image/gif',
      _ => 'application/octet-stream',
    };
    return 'data:$mime;base64,${base64Encode(bytes)}';
  }

  static Future<void> shareBytes({
    required List<int> bytes,
    required String fileName,
    required String mimeType,
    String? subject,
    String? text,
  }) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            Uint8List.fromList(bytes),
            mimeType: mimeType,
            name: fileName,
          ),
        ],
        subject: subject,
        text: text,
      ),
    );
  }
}
