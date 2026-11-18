// Browser integrations (IndexedDB, files, notifications, storage quota),
// with no-op fallbacks for other platforms and for `flutter test`.
export 'platform_stub.dart' if (dart.library.js_interop) 'platform_web.dart';
export 'platform_types.dart';
