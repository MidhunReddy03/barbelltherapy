/// Cross-platform image storage helper.
///
/// On native platforms images are real files in app storage; on web they
/// are base64 data URIs stored in the database itself. Both produce a
/// "stored reference" string that the [AppImage] API understands, so the
/// UI never needs platform checks.

library;

export 'app_image_io.dart' if (dart.library.js_interop) 'app_image_web.dart';
