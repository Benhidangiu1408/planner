import 'package:shared_preferences/shared_preferences.dart';

/// Where the planner's JSON document is kept.
abstract class PlannerStorage {
  /// Short name shown in Settings.
  String get label;

  Future<String?> read();
  Future<void> write(String data);

  /// Keeps a copy of data that couldn't be parsed, so it is never lost.
  Future<void> keepAside(String data);
}

/// localStorage on the web (about 5 MB), in-memory in tests.
/// Used when IndexedDB isn't available, and as the migration source.
class PrefsStorage implements PlannerStorage {
  PrefsStorage(this._prefs);

  static const key = 'planner.data.v1';

  final SharedPreferences _prefs;

  @override
  String get label => 'Local storage';

  @override
  Future<String?> read() async => _prefs.getString(key);

  @override
  Future<void> write(String data) => _prefs.setString(key, data);

  @override
  Future<void> keepAside(String data) => _prefs.setString('$key.unreadable', data);
}
