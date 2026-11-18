// Browser self-test for the web storage layer (IndexedDB + sync file).
// Not part of the app. Build with:
//   flutter build web -t tool/web_selftest.dart -o <dir>
// then open it and read the console. The sync file is exercised through an
// origin-private file, which uses the same FileSystemFileHandle API as a
// file picked with showSaveFilePicker (which needs a user gesture).
import 'dart:js_interop';

import 'package:planner/data/planner_store.dart';
import 'package:planner/platform/platform_web.dart';
import 'package:web/web.dart' as web;

Future<void> main() async {
  void log(String message) => web.console.log('SELFTEST $message'.toJS);
  try {
    final storage = await openDefaultStorage();
    log('storage: ${storage.label}');
    await storage.write('{"probe":1}');
    log('idb round-trip: ${await storage.read() == '{"probe":1}'}');

    final dir = await web.window.navigator.storage.getDirectory().toDart;
    final handle = await dir
        .getFileHandle('selftest.json', web.FileSystemGetFileOptions(create: true))
        .toDart;
    await (storage as IdbStorage).putValue('syncHandle', handle);

    final file = await restoreSyncFile();
    log('handle restored from IndexedDB: ${file?.name}');
    log('permission: ${await file!.permission()}');
    await file.write('{"hello":1}');
    final back = await file.read();
    log(
      'file round-trip: ${back.text == '{"hello":1}'}, lastModified set: ${back.lastModified > 0}',
    );

    // Through the store: a non-backup file gets replaced by local data,
    // then every change is mirrored.
    final store = await PlannerStore.load(storage: storage);
    log('store sync state after load: ${store.syncState}');
    store.addTask('from selftest', '2026-11-18');
    await store.flush();
    final after = (await file.read()).text;
    log('file mirrors store: ${after.contains('from selftest')}');

    await forgetSyncFile();
    log('forgotten: ${await restoreSyncFile() == null}');
    log('DONE');
  } catch (e, st) {
    log('FAIL $e\n$st');
  }
}
