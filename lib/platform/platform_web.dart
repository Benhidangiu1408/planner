import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web/web.dart' as web;

import '../data/storage.dart';
import 'platform_types.dart';

// ------------------------------------------------------------- IndexedDB

/// Stores the planner in IndexedDB, which allows far more data than
/// localStorage and can hold file handles for the sync file.
class IdbStorage implements PlannerStorage {
  IdbStorage._(this._db);

  static const _dbName = 'planner';
  static const _storeName = 'kv';
  static const _dataKey = 'data';

  final web.IDBDatabase _db;

  static Future<IdbStorage> open() async {
    final request = web.window.indexedDB.open(_dbName, 1);
    request.onupgradeneeded = ((web.Event _) {
      final db = request.result as web.IDBDatabase;
      if (!db.objectStoreNames.contains(_storeName)) db.createObjectStore(_storeName);
    }).toJS;
    final db = await _await(request) as web.IDBDatabase;
    return IdbStorage._(db);
  }

  @override
  String get label => 'IndexedDB';

  Future<JSAny?> getValue(String key) {
    final tx = _db.transaction(_storeName.toJS, 'readonly');
    return _await(tx.objectStore(_storeName).get(key.toJS));
  }

  Future<void> putValue(String key, JSAny? value) {
    final tx = _db.transaction(_storeName.toJS, 'readwrite');
    tx.objectStore(_storeName).put(value, key.toJS);
    return _complete(tx);
  }

  Future<void> deleteValue(String key) {
    final tx = _db.transaction(_storeName.toJS, 'readwrite');
    tx.objectStore(_storeName).delete(key.toJS);
    return _complete(tx);
  }

  @override
  Future<String?> read() async {
    final value = await getValue(_dataKey);
    return value.isA<JSString>() ? (value as JSString).toDart : null;
  }

  @override
  Future<void> write(String data) => putValue(_dataKey, data.toJS);

  @override
  Future<void> keepAside(String data) =>
      putValue('unreadable-${DateTime.now().millisecondsSinceEpoch}', data.toJS);

  static Future<JSAny?> _await(web.IDBRequest request) {
    final completer = Completer<JSAny?>();
    request.onsuccess = ((web.Event _) => completer.complete(request.result)).toJS;
    request.onerror = ((web.Event _) => completer.completeError(
      StateError('IndexedDB request failed: ${request.error?.message}'),
    )).toJS;
    return completer.future;
  }

  static Future<void> _complete(web.IDBTransaction tx) {
    final completer = Completer<void>();
    tx.oncomplete = ((web.Event _) => completer.complete()).toJS;
    void fail(web.Event _) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('IndexedDB write failed: ${tx.error?.message}'));
      }
    }

    tx.onerror = fail.toJS;
    tx.onabort = fail.toJS;
    return completer.future;
  }
}

IdbStorage? _idb;

/// Opens IndexedDB, moving data over from localStorage on first use.
/// Falls back to localStorage if IndexedDB is unavailable.
Future<PlannerStorage> openDefaultStorage() async {
  final prefs = await SharedPreferences.getInstance();
  try {
    final idb = await IdbStorage.open();
    if (await idb.read() == null) {
      final legacy = prefs.getString(PrefsStorage.key);
      if (legacy != null) {
        await idb.write(legacy);
        // Only drop the old copy once the new one is verified.
        if (await idb.read() == legacy) await prefs.remove(PrefsStorage.key);
      }
    }
    _idb = idb;
    return idb;
  } catch (e) {
    debugPrint('Planner: IndexedDB unavailable ($e), using localStorage.');
    return PrefsStorage(prefs);
  }
}

// ------------------------------------------------------------------ files

bool get supportsFiles => true;

Future<void> downloadTextFile(String fileName, String content) async {
  final blob = web.Blob(<JSAny>[content.toJS].toJS, web.BlobPropertyBag(type: 'application/json'));
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = fileName;
  web.document.body?.appendChild(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
}

/// Opens the browser's file picker and returns the chosen file's text,
/// or null if the user cancels.
Future<String?> pickTextFile() {
  final completer = Completer<String?>();
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = '.json,application/json';

  Future<void> read() async {
    final file = input.files?.item(0);
    if (file == null) {
      completer.complete(null);
      return;
    }
    final text = await file.text().toDart;
    completer.complete(text.toDart);
  }

  input.addEventListener(
    'change',
    ((web.Event _) {
      read();
    }).toJS,
  );
  input.addEventListener(
    'cancel',
    ((web.Event _) {
      if (!completer.isCompleted) completer.complete(null);
    }).toJS,
  );
  input.click();
  return completer.future;
}

// ------------------------------------------------- storage quota/persistence

Future<StorageEstimate?> storageEstimate() async {
  try {
    final e = await web.window.navigator.storage.estimate().toDart;
    return (usage: e.usage, quota: e.quota);
  } catch (_) {
    return null;
  }
}

Future<bool?> isStoragePersisted() async {
  try {
    return (await web.window.navigator.storage.persisted().toDart).toDart;
  } catch (_) {
    return null;
  }
}

/// Asks the browser not to evict the planner's storage under pressure.
Future<bool> requestPersistentStorage() async {
  try {
    return (await web.window.navigator.storage.persist().toDart).toDart;
  } catch (_) {
    return false;
  }
}

// ---------------------------------------------------------- notifications

NotificationAccess notificationAccess() {
  if (!globalContext.has('Notification')) return NotificationAccess.unsupported;
  return switch (web.Notification.permission) {
    'granted' => NotificationAccess.granted,
    'denied' => NotificationAccess.denied,
    _ => NotificationAccess.notAsked,
  };
}

Future<NotificationAccess> requestNotificationAccess() async {
  if (notificationAccess() == NotificationAccess.unsupported) {
    return NotificationAccess.unsupported;
  }
  try {
    await web.Notification.requestPermission().toDart;
  } catch (_) {}
  return notificationAccess();
}

bool showSystemNotification(String title, String body) {
  if (notificationAccess() != NotificationAccess.granted) return false;
  try {
    web.Notification(title, web.NotificationOptions(body: body, icon: 'icons/Icon-192.png'));
    return true;
  } catch (_) {
    // e.g. Android Chrome only allows notifications from a service worker.
    return false;
  }
}

// -------------------------------------------- sync file (File System Access)

@JS('showSaveFilePicker')
external JSPromise<JSObject> _showSaveFilePicker(JSAny options);

@JS('showOpenFilePicker')
external JSPromise<JSArray<JSObject>> _showOpenFilePicker(JSAny options);

/// The parts of FileSystemFileHandle that package:web doesn't declare.
extension type _PermissionHandle(JSObject _) implements JSObject {
  external JSPromise<JSString> queryPermission(JSAny descriptor);
  external JSPromise<JSString> requestPermission(JSAny descriptor);
}

const _syncHandleKey = 'syncHandle';

JSAny get _readWrite => {'mode': 'readwrite'}.jsify()!;

JSAny get _pickerOptions => {
  'suggestedName': 'planner-sync.json',
  'types': [
    {
      'description': 'Planner data',
      'accept': {
        'application/json': ['.json'],
      },
    },
  ],
}.jsify()!;

class WebSyncFile implements SyncFile {
  WebSyncFile(JSObject handle) : _handle = handle as web.FileSystemFileHandle;

  final web.FileSystemFileHandle _handle;

  @override
  String get name => _handle.name;

  @override
  Future<SyncPermission> permission() async {
    if (!_handle.has('queryPermission')) return SyncPermission.granted;
    final state = (await _PermissionHandle(_handle).queryPermission(_readWrite).toDart).toDart;
    return _parse(state);
  }

  @override
  Future<bool> requestPermission() async {
    if (!_handle.has('requestPermission')) return true;
    final state = (await _PermissionHandle(_handle).requestPermission(_readWrite).toDart).toDart;
    return _parse(state) == SyncPermission.granted;
  }

  @override
  Future<({String text, int lastModified})> read() async {
    final file = await _handle.getFile().toDart;
    final text = (await file.text().toDart).toDart;
    return (text: text, lastModified: file.lastModified);
  }

  @override
  Future<void> write(String text) async {
    final stream = await _handle.createWritable().toDart;
    await stream.write(text.toJS).toDart;
    await stream.close().toDart;
  }

  static SyncPermission _parse(String state) => switch (state) {
    'granted' => SyncPermission.granted,
    'denied' => SyncPermission.denied,
    _ => SyncPermission.prompt,
  };
}

bool get supportsSyncFile => globalContext.has('showSaveFilePicker');

bool _isAbort(Object e) => e.toString().contains('AbortError');

/// Lets the user choose where to create a new sync file.
Future<SyncFile?> createSyncFile() async {
  try {
    final handle = await _showSaveFilePicker(_pickerOptions).toDart;
    await _idb?.putValue(_syncHandleKey, handle);
    return WebSyncFile(handle);
  } catch (e) {
    if (_isAbort(e)) return null;
    rethrow;
  }
}

/// Lets the user pick an existing sync file (e.g. made on another computer).
Future<SyncFile?> openSyncFile() async {
  try {
    final handles = (await _showOpenFilePicker(_pickerOptions).toDart).toDart;
    if (handles.isEmpty) return null;
    await _idb?.putValue(_syncHandleKey, handles.first);
    return WebSyncFile(handles.first);
  } catch (e) {
    if (_isAbort(e)) return null;
    rethrow;
  }
}

/// The sync file chosen in an earlier session, if any.
Future<SyncFile?> restoreSyncFile() async {
  final idb = _idb;
  if (idb == null || !supportsSyncFile) return null;
  try {
    final value = await idb.getValue(_syncHandleKey);
    if (value == null || value.isUndefinedOrNull) return null;
    return WebSyncFile(value as JSObject);
  } catch (e) {
    debugPrint('Planner: could not restore sync file ($e)');
    return null;
  }
}

Future<void> forgetSyncFile() async {
  await _idb?.deleteValue(_syncHandleKey);
}
