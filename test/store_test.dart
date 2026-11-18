import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:planner/data/models.dart';
import 'package:planner/data/planner_store.dart';
import 'package:planner/data/storage.dart';
import 'package:planner/platform/platform_types.dart';
import 'package:shared_preferences/shared_preferences.dart';

TimeBlock block(String date, int start, int end, {String title = 'b', String? goalId}) => TimeBlock(
  id: newId(),
  date: date,
  start: start,
  end: end,
  title: title,
  color: 0,
  goalId: goalId,
);

Routine routine({
  String title = 'Run',
  List<int> weekdays = const [1, 2, 3, 4, 5],
  String startDate = '2026-11-16', // Monday
  String? goalId,
}) => Routine(
  id: newId(),
  title: title,
  start: 420,
  end: 450,
  color: 0,
  startDate: startDate,
  weekdays: weekdays,
  goalId: goalId,
);

/// In-memory stand-in for a file on disk.
class FakeSyncFile implements SyncFile {
  String text = '';
  int writes = 0;

  @override
  String get name => 'fake.json';

  @override
  Future<SyncPermission> permission() async => SyncPermission.granted;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<({String text, int lastModified})> read() async => (text: text, lastModified: 0);

  @override
  Future<void> write(String text) async {
    this.text = text;
    writes++;
  }
}

void main() {
  // Wednesday, Nov 18 2026, 9:00.
  var now = DateTime(2026, 11, 18, 9);
  late SharedPreferences prefs;

  Future<PlannerStore> load() => PlannerStore.load(storage: PrefsStorage(prefs), clock: () => now);

  setUp(() async {
    now = DateTime(2026, 11, 18, 9);
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  group('accent migration', () {
    Future<int> accentAfterLoading(int version, int seed) async {
      SharedPreferences.setMockInitialValues({
        PrefsStorage.key: jsonEncode({
          'version': version,
          'settings': {'seedColor': seed},
        }),
      });
      prefs = await SharedPreferences.getInstance();
      return (await load()).settings.seedColor;
    }

    test('the old default accent becomes pink & blue', () async {
      expect(await accentAfterLoading(2, 0xFF4F6BED), 0xFFD9488F);
    });

    test('a deliberately chosen accent is kept', () async {
      expect(await accentAfterLoading(2, 0xFF2BA36B), 0xFF2BA36B);
      expect(await accentAfterLoading(3, 0xFF4F6BED), 0xFF4F6BED);
    });

    test('new installs start pink & blue', () async {
      expect((await load()).settings.seedColor, 0xFFD9488F);
    });
  });

  group('persistence', () {
    test('first run seeds a getting-started goal and saves it', () async {
      final store = await load();
      await store.flush();
      expect(store.goals, hasLength(1));
      expect(prefs.getString(PrefsStorage.key), isNotNull);
    });

    test('everything survives a reload', () async {
      final store = await load();
      store.saveBlock(block('2026-11-18', 540, 600, title: 'Deep work'));
      store.addTask('Email Sam', '2026-11-18', important: true);
      store.setNote('2026-11-18', 'Good day');
      store.saveRoutine(routine());
      store.saveWeekPlan(const WeekPlan(weekStart: '2026-11-16', intention: 'Ship it'));
      store.startFocus();
      await store.flush();

      final reloaded = await load();
      expect(reloaded.blocksOn('2026-11-18').map((b) => b.title), ['Run', 'Deep work']);
      expect(reloaded.tasksOn('2026-11-18').single.important, isTrue);
      expect(reloaded.noteFor('2026-11-18'), 'Good day');
      expect(reloaded.weekPlan('2026-11-16').intention, 'Ship it');
      expect(reloaded.activeFocus, isNotNull);
    });

    test('rapid changes are all saved, the last one winning', () async {
      final store = await load();
      for (var i = 0; i < 20; i++) {
        store.setNote('2026-11-18', 'draft $i');
      }
      await store.flush();
      expect((await load()).noteFor('2026-11-18'), 'draft 19');
    });

    test('unreadable saved data is kept aside, not overwritten', () async {
      SharedPreferences.setMockInitialValues({PrefsStorage.key: '{broken'});
      prefs = await SharedPreferences.getInstance();
      await load();
      expect(prefs.getString('${PrefsStorage.key}.unreadable'), '{broken');
    });

    test('export/import round-trip, and junk is rejected', () async {
      final store = await load();
      store.saveBlock(block('2026-11-18', 60, 120, title: 'Gym'));
      store.saveRoutine(routine());
      final backup = store.exportJson();
      store.clearAll();
      expect(store.blocks, isEmpty);
      expect(store.routines, isEmpty);

      store.importJson(backup);
      expect(store.blocks.single.title, 'Gym');
      expect(store.routines, hasLength(1));

      expect(() => store.importJson('not json'), throwsFormatException);
      expect(() => store.importJson(jsonEncode({'hello': 1})), throwsFormatException);
      expect(store.blocks.single.title, 'Gym');
    });
  });

  group('tasks & blocks', () {
    test('tasks sort undone first, then priority', () async {
      final store = await load();
      final a = store.addTask('a', '2026-11-18');
      store.addTask('b', '2026-11-18', important: true);
      store.addTask('c', '2026-11-18');
      store.toggleTask(a.id);
      expect(store.tasksOn('2026-11-18').map((t) => t.title), ['b', 'c', 'a']);
    });

    test('overdue tasks can be rolled over', () async {
      final store = await load();
      store.addTask('old', '2026-11-10');
      final done = store.addTask('old done', '2026-11-11');
      store.toggleTask(done.id);
      final overdue = store.overdueTasks('2026-11-18');
      expect(overdue.map((t) => t.title), ['old']);
      store.moveTasks(overdue.map((t) => t.id), '2026-11-18');
      expect(store.overdueTasks('2026-11-18'), isEmpty);
    });

    test('suggestStart finds the first free gap', () async {
      final store = await load();
      store.saveBlock(block('d', 540, 600));
      store.saveBlock(block('d', 600, 690));
      store.saveBlock(block('d', 720, 780));
      expect(store.suggestStart('d', from: 540), 780);
      expect(store.suggestStart('d', from: 540, duration: 30), 690);
      expect(store.suggestStart('d', from: 480), 480);
    });
  });

  group('routines', () {
    test('occur on their weekdays from the start date on', () async {
      final store = await load();
      store.saveRoutine(routine());
      expect(store.blocksOn('2026-11-18').single.isVirtual, isTrue);
      expect(store.blocksOn('2026-11-21'), isEmpty, reason: 'Saturday');
      expect(store.blocksOn('2026-11-13'), isEmpty, reason: 'before the start date');
    });

    test('changing one occurrence stores an override for that day only', () async {
      final store = await load();
      store.saveRoutine(routine());
      final occurrence = store.blocksOn('2026-11-18').single;
      store.toggleBlock(occurrence.id);

      final today = store.blocksOn('2026-11-18').single;
      expect(today.done, isTrue);
      expect(today.isVirtual, isFalse);
      expect(today.routineId, occurrence.routineId);
      expect(store.blocksOn('2026-11-19').single.done, isFalse);
    });

    test('deleting an occurrence skips that day, and undo brings it back', () async {
      final store = await load();
      store.saveRoutine(routine());
      final removed = store.deleteBlock(store.blocksOn('2026-11-18').single.id)!;
      expect(store.blocksOn('2026-11-18'), isEmpty);
      expect(store.blocksOn('2026-11-19'), hasLength(1));
      store.restoreBlock(removed);
      expect(store.blocksOn('2026-11-18'), hasLength(1));
    });

    test('moving an occurrence to another day leaves no copy behind', () async {
      final store = await load();
      store.saveRoutine(routine());
      final occurrence = store.blocksOn('2026-11-18').single;
      store.saveBlock(occurrence.copyWith(date: '2026-11-21'));
      expect(store.blocksOn('2026-11-18'), isEmpty);
      expect(store.blocksOn('2026-11-21').single.title, 'Run');
    });

    test('ending a routine keeps the past and drops the future', () async {
      final store = await load();
      final r = routine();
      store.saveRoutine(r);
      store.toggleBlock(store.blocksOn('2026-11-20').single.id); // future override
      store.endRoutine(r.id);
      expect(store.blocksOn('2026-11-17'), hasLength(1));
      expect(store.blocksOn('2026-11-18'), isEmpty);
      expect(store.blocksOn('2026-11-20'), isEmpty);
    });

    test('a block can become a routine, keeping its own state', () async {
      final store = await load();
      final b = block('2026-11-18', 600, 630, title: 'Inbox');
      store.saveBlock(b.copyWith(done: true));
      store.makeRoutine(b.copyWith(done: true), const []);
      expect(store.blocksOn('2026-11-18').single.done, isTrue);
      expect(store.blocksOn('2026-11-25').single.title, 'Inbox');
    });

    test('copying a day skips routine occurrences', () async {
      final store = await load();
      store.saveRoutine(routine());
      store.saveBlock(block('2026-11-18', 600, 660, title: 'One-off'));
      expect(store.copyBlocks(from: '2026-11-18', to: '2026-11-19'), 1);
      expect(store.blocksOn('2026-11-19').map((b) => b.title), ['Run', 'One-off']);
    });

    test('count towards goal time up to the deadline', () async {
      final store = await load();
      const goal = Goal(
        id: 'g',
        title: 'Fit',
        horizon: Horizon.week,
        color: 0,
        createdAt: 0,
        dueDate: '2026-11-20',
      );
      store.saveGoal(goal);
      store.saveRoutine(routine(goalId: 'g')); // Mon–Fri, 30 min
      store.saveBlock(block('2026-11-22', 0, 60, goalId: 'g'));
      // Mon 16 – Fri 20 = 5 × 30 min, plus the 60 min block.
      expect(store.plannedMinutesFor('g'), 5 * 30 + 60);
    });
  });

  group('goals', () {
    test('progress rolls up from sub-goals', () async {
      final store = await load();
      const parent = Goal(
        id: 'p',
        title: 'Year',
        horizon: Horizon.year,
        color: 0,
        createdAt: 0,
        milestones: [
          Milestone(id: 'a', title: 'a', done: true),
          Milestone(id: 'b', title: 'b'),
        ],
      );
      const child = Goal(
        id: 'c',
        title: 'Quarter',
        horizon: Horizon.quarter,
        color: 0,
        createdAt: 0,
        parentId: 'p',
        milestones: [Milestone(id: 'x', title: 'x', done: true)],
      );
      store.saveGoal(parent);
      store.saveGoal(child);
      expect(store.progressOf(parent), closeTo(2 / 3, 1e-9));
    });

    test('parent candidates exclude shorter horizons and descendants', () async {
      final store = await load();
      const year = Goal(id: 'y', title: 'Y', horizon: Horizon.year, color: 0, createdAt: 0);
      const quarter = Goal(
        id: 'q',
        title: 'Q',
        horizon: Horizon.quarter,
        color: 0,
        createdAt: 0,
        parentId: 'y',
      );
      const month = Goal(id: 'm', title: 'M', horizon: Horizon.month, color: 0, createdAt: 0);
      store
        ..saveGoal(year)
        ..saveGoal(quarter)
        ..saveGoal(month);
      expect(
        store.parentCandidates(month, Horizon.month).map((g) => g.id),
        containsAll(['y', 'q']),
      );
      expect(store.parentCandidates(year, Horizon.month).map((g) => g.id), isNot(contains('q')));
      expect(store.parentCandidates(quarter, Horizon.quarter).map((g) => g.id), ['y']);
    });

    test('deleting a goal unlinks sub-goals, tasks, blocks and routines', () async {
      final store = await load();
      final goalId = store.goals.first.id;
      store.addTask('t', 'd', goalId: goalId);
      store.saveBlock(block('d', 0, 60, goalId: goalId));
      store.saveRoutine(routine(goalId: goalId));
      store.saveGoal(
        Goal(id: 'c', title: 'c', horizon: Horizon.week, color: 0, createdAt: 0, parentId: goalId),
      );
      store.deleteGoal(goalId);
      expect(store.tasks.single.goalId, isNull);
      expect(store.blocks.single.goalId, isNull);
      expect(store.routines.single.goalId, isNull);
      expect(store.goalById('c')!.parentId, isNull);
    });

    test('week focus resolves to existing goals', () async {
      final store = await load();
      final id = store.goals.first.id;
      store.saveWeekPlan(WeekPlan(weekStart: '2026-11-16', focusGoalIds: [id, 'gone']));
      expect(store.focusGoalsFor(DateTime(2026, 11, 19)).map((g) => g.id), [id]);
      store.saveWeekPlan(const WeekPlan(weekStart: '2026-11-16'));
      expect(store.focusGoalsFor(DateTime(2026, 11, 19)), isEmpty);
    });
  });

  group('focus timer', () {
    test('logs the elapsed minutes, excluding pauses', () async {
      final store = await load();
      final b = block('2026-11-18', 540, 600, goalId: 'g');
      store.saveBlock(b);
      store.startFocus(block: b);
      expect(store.activeFocus!.targetMinutes, 60);

      now = now.add(const Duration(minutes: 20));
      store.pauseFocus();
      now = now.add(const Duration(minutes: 30)); // paused, doesn't count
      store.resumeFocus();
      now = now.add(const Duration(minutes: 5));
      final session = store.stopFocus()!;

      expect(session.minutes, 25);
      expect(store.focusMinutesForBlock(b.id), 25);
      expect(store.focusMinutesForGoal('g'), 25);
      expect(store.activeFocus, isNull);
    });

    test('starting on a routine occurrence stores it first', () async {
      final store = await load();
      store.saveRoutine(routine());
      store.startFocus(block: store.blocksOn('2026-11-18').single);
      final blockId = store.activeFocus!.blockId!;
      expect(blockId.startsWith('r~'), isFalse);
      expect(store.blockById(blockId), isNotNull);
    });

    test('discarding or under a minute logs nothing', () async {
      final store = await load();
      store.startFocus();
      now = now.add(const Duration(seconds: 20));
      expect(store.stopFocus(), isNull);
      store.startFocus();
      now = now.add(const Duration(minutes: 10));
      expect(store.stopFocus(save: false), isNull);
      expect(store.sessions, isEmpty);
    });
  });

  group('sync file', () {
    test('an empty file is filled, then kept up to date', () async {
      final store = await load();
      final file = FakeSyncFile();
      await store.connectSyncFile(file);
      expect(jsonDecode(file.text)['goals'], hasLength(1));

      store.addTask('Synced', '2026-11-18');
      await store.flush();
      expect(file.text, contains('Synced'));
    });

    test('newer data from another device is offered, not overwritten', () async {
      final store = await load();
      final file = FakeSyncFile();
      await store.connectSyncFile(file);

      // Another computer saves a newer version.
      final other = jsonDecode(file.text) as Map<String, dynamic>;
      other['savedAt'] = (other['savedAt'] as int) + 60000;
      other['tasks'] = [
        {'id': 'x', 'title': 'From laptop', 'date': '2026-11-18', 'createdAt': 1},
      ];
      file.text = jsonEncode(other);

      await store.checkSyncFile();
      expect(store.incomingSyncSavedAt, isNotNull);

      // Local edits meanwhile must not clobber the file.
      store.addTask('Local', '2026-11-18');
      await store.flush();
      expect(file.text, contains('From laptop'));

      store.acceptIncomingSync();
      await store.flush();
      expect(store.tasks.map((t) => t.title), ['From laptop']);
      expect(store.incomingSyncSavedAt, isNull);
    });

    test('keeping local data overwrites the file', () async {
      final store = await load();
      final file = FakeSyncFile();
      await store.connectSyncFile(file);
      final other = jsonDecode(file.text) as Map<String, dynamic>;
      other['savedAt'] = (other['savedAt'] as int) + 60000;
      other['goals'] = [];
      file.text = jsonEncode(other);
      await store.checkSyncFile();

      store.rejectIncomingSync();
      await store.flush();
      expect(jsonDecode(file.text)['goals'], hasLength(1));
    });

    test('a file that is not a backup is replaced by local data', () async {
      final store = await load();
      final file = FakeSyncFile()..text = 'hello';
      await store.connectSyncFile(file);
      expect(store.incomingSyncSavedAt, isNull);
      expect(jsonDecode(file.text)['version'], PlannerStore.schemaVersion);
    });
  });
}
