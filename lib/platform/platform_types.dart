enum NotificationAccess { granted, denied, notAsked, unsupported }

enum SyncPermission { granted, prompt, denied }

typedef StorageEstimate = ({int usage, int quota});

/// A JSON file outside the browser (e.g. in a OneDrive/Dropbox/Google Drive
/// folder) that mirrors the planner's data.
abstract class SyncFile {
  String get name;

  Future<SyncPermission> permission();

  /// Asks for read/write access. Must be called from a user gesture.
  Future<bool> requestPermission();

  Future<({String text, int lastModified})> read();

  Future<void> write(String text);
}
