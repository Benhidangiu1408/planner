import 'package:shared_preferences/shared_preferences.dart';

import '../data/storage.dart';
import 'platform_types.dart';

Future<PlannerStorage> openDefaultStorage() async =>
    PrefsStorage(await SharedPreferences.getInstance());

// Files
bool get supportsFiles => false;

Future<void> downloadTextFile(String fileName, String content) async =>
    throw UnsupportedError('File download is only available on the web.');

Future<String?> pickTextFile() async => null;

// Storage quota / persistence
Future<StorageEstimate?> storageEstimate() async => null;
Future<bool?> isStoragePersisted() async => null;
Future<bool> requestPersistentStorage() async => false;

// Notifications
NotificationAccess notificationAccess() => NotificationAccess.unsupported;
Future<NotificationAccess> requestNotificationAccess() async => NotificationAccess.unsupported;
bool showSystemNotification(String title, String body) => false;

// Sync file
bool get supportsSyncFile => false;
Future<SyncFile?> createSyncFile() async => null;
Future<SyncFile?> openSyncFile() async => null;
Future<SyncFile?> restoreSyncFile() async => null;
Future<void> forgetSyncFile() async {}
