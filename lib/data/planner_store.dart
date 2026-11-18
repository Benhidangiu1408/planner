import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../platform/platform.dart';
import '../util/dates.dart';
import '../util/palette.dart';
import 'models.dart';
import 'storage.dart';

enum SyncState { off, connected, needsPermission, error }

/// Single source of truth for the app. All data is kept in memory and saved
/// as one JSON document after every change: to IndexedDB on the web, and
/// optionally mirrored to a sync file outside the browser.
class PlannerStore extends ChangeNotifier {
  PlannerStore._(this._storage, this._clock);

  /// 3: pink & blue became the default accent.
  static const schemaVersion = 3;

  final PlannerStorage _storage;
  final DateTime Function() _clock;

  final List<TimeBlock> _blocks = [];
  final List<Routine> _routines = [];
  final List<Task> _tasks = [];
  final List<Goal> _goals = [];
  final List<Habit> _habits = [];
  final List<FocusSession> _sessions = [];
  final Map<String, WeekPlan> _weekPlans = {};
  final Map<String, String> _notes = {};
  PlannerSettings _settings = const PlannerSettings();
  ActiveFocus? _focus;
  int _savedAt = 0;
  DateTime _selectedDate = today();

  /// Concrete blocks grouped by day; rebuilt lazily after changes.
  Map<String, List<TimeBlock>>? _index;

  static Future<PlannerStore> load({PlannerStorage? storage, DateTime Function()? clock}) async {
    final store = PlannerStore._(storage ?? await openDefaultStorage(), clock ?? DateTime.now);
    final raw = await store._storage.read();
    if (raw == null) {
      store._seedFirstRun();
      store._persist();
    } else {
      try {
        store._apply(jsonDecode(raw) as Map<String, dynamic>);
        store._storedBytes = raw.length;
      } catch (e) {
        // Never silently destroy data we can't read: keep a copy aside.
        debugPrint('Planner: saved data could not be read ($e); kept a copy.');
        await store._storage.keepAside(raw);
      }
    }
    await store._restoreSync();
    return store;
  }

  // ---------------------------------------------------------------- general

  DateTime get now => _clock();
  String get todayKey => dateKey(_clock());
  PlannerSettings get settings => _settings;
  DateTime get selectedDate => _selectedDate;
  List<TimeBlock> get blocks => List.unmodifiable(_blocks);
  List<Routine> get routines => List.unmodifiable(_routines);
  List<Task> get tasks => List.unmodifiable(_tasks);
  List<Goal> get goals => List.unmodifiable(_goals);
  List<Habit> get habits => List.unmodifiable(_habits);
  List<FocusSession> get sessions => List.unmodifiable(_sessions);

  void selectDate(DateTime date) {
    _selectedDate = dateOnly(date);
    notifyListeners();
  }

  void updateSettings(PlannerSettings settings) {
    _settings = settings;
    _commit();
  }

  // ----------------------------------------------------------------- blocks

  Map<String, List<TimeBlock>> get _byDate => _index ??= () {
    final map = <String, List<TimeBlock>>{};
    for (final b in _blocks) {
      map.putIfAbsent(b.date, () => []).add(b);
    }
    return map;
  }();

  /// Everything on the timeline for [date]: stored blocks plus routine
  /// occurrences that haven't been overridden or skipped.
  List<TimeBlock> blocksOn(String date) {
    final concrete = _byDate[date] ?? const <TimeBlock>[];
    final result = [...concrete];
    if (_routines.isNotEmpty) {
      final day = parseDateKey(date);
      for (final r in _routines) {
        if (!r.occursOn(day, date)) continue;
        if (concrete.any((b) => b.routineId == r.id)) continue;
        result.add(r.instanceOn(date));
      }
    }
    return result
      ..sort((a, b) => a.start != b.start ? a.start.compareTo(b.start) : a.end.compareTo(b.end));
  }

  Map<String, List<TimeBlock>> blocksBetween(DateTime from, DateTime to) => {
    for (var d = dateOnly(from); !d.isAfter(to); d = addDays(d, 1))
      dateKey(d): blocksOn(dateKey(d)),
  };

  int plannedMinutesOn(String date) => blocksOn(date).fold(0, (sum, b) => sum + b.duration);

  TimeBlock? blockById(String id) {
    final parsed = Routine.parseVirtualId(id);
    if (parsed != null) return routineById(parsed.$1)?.instanceOn(parsed.$2);
    for (final b in _blocks) {
      if (b.id == id) return b;
    }
    return null;
  }

  /// Saves a block. A virtual routine occurrence becomes a stored override.
  /// Returns the block as stored (its id may have changed).
  TimeBlock saveBlock(TimeBlock block) {
    var saved = block;
    String? originalDate;
    final virtual = Routine.parseVirtualId(block.id);
    if (virtual != null) {
      originalDate = virtual.$2;
      saved = block.copyWith(id: newId());
    } else if (block.routineId != null) {
      for (final b in _blocks) {
        if (b.id == block.id) originalDate = b.date;
      }
    }
    // Moving a routine occurrence to another day must not leave the
    // original occurrence behind.
    if (saved.routineId != null && originalDate != null && originalDate != saved.date) {
      _skipOccurrence(saved.routineId!, originalDate);
    }
    _upsert(_blocks, saved, (b) => b.id);
    _commit();
    return saved;
  }

  /// Removes a block (or a single routine occurrence) and returns it, so the
  /// caller can offer undo via [restoreBlock].
  TimeBlock? deleteBlock(String id) {
    final virtual = Routine.parseVirtualId(id);
    if (virtual != null) {
      final routine = routineById(virtual.$1);
      if (routine == null) return null;
      _skipOccurrence(routine.id, virtual.$2);
      _commit();
      return routine.instanceOn(virtual.$2);
    }
    final i = _blocks.indexWhere((b) => b.id == id);
    if (i < 0) return null;
    final removed = _blocks.removeAt(i);
    if (removed.routineId != null) _skipOccurrence(removed.routineId!, removed.date);
    _commit();
    return removed;
  }

  void restoreBlock(TimeBlock block) {
    final virtual = Routine.parseVirtualId(block.id);
    if (virtual == null) {
      saveBlock(block);
      return;
    }
    final i = _routines.indexWhere((r) => r.id == virtual.$1);
    if (i < 0) return;
    _routines[i] = _routines[i].copyWith(
      skipDates: {..._routines[i].skipDates}..remove(virtual.$2),
    );
    _commit();
  }

  void toggleBlock(String id) {
    final block = blockById(id);
    if (block != null) saveBlock(block.copyWith(done: !block.done));
  }

  /// Copies one-off blocks from one day to another (routines already repeat).
  /// Returns how many were copied.
  int copyBlocks({required String from, required String to}) {
    final source = blocksOn(from).where((b) => b.routineId == null).toList();
    for (final b in source) {
      _blocks.add(b.copyWith(id: newId(), date: to, done: false));
    }
    if (source.isNotEmpty) _commit();
    return source.length;
  }

  void clearBlocks(String date) {
    final day = parseDateKey(date);
    for (final r in List.of(_routines)) {
      if (r.occursOn(day, date)) _skipOccurrence(r.id, date);
    }
    _blocks.removeWhere((b) => b.date == date);
    _commit();
  }

  /// First start time at or after [from] where a block of [duration]
  /// minutes fits without overlapping existing blocks.
  int suggestStart(String date, {required int from, int duration = 60}) {
    var candidate = from;
    for (final b in blocksOn(date)) {
      if (b.end <= candidate) continue;
      if (b.start >= candidate + duration) break;
      candidate = max(candidate, b.end);
    }
    return min(candidate, 1440 - duration);
  }

  // --------------------------------------------------------------- routines

  Routine? routineById(String? id) {
    if (id == null) return null;
    for (final r in _routines) {
      if (r.id == id) return r;
    }
    return null;
  }

  void saveRoutine(Routine routine) {
    _upsert(_routines, routine, (r) => r.id);
    _commit();
  }

  /// Turns a block into the first occurrence of a new routine.
  Routine makeRoutine(TimeBlock block, List<int> weekdays) {
    final routine = Routine(
      id: newId(),
      title: block.title,
      start: block.start,
      end: block.end,
      color: block.color,
      notes: block.notes,
      goalId: block.goalId,
      weekdays: weekdays,
      startDate: block.date,
    );
    _routines.add(routine);
    // An existing block stays as that day's occurrence (keeping its state).
    final i = _blocks.indexWhere((b) => b.id == block.id);
    if (i >= 0) _blocks[i] = _blocks[i].copyWith(routineId: () => routine.id);
    _commit();
    return routine;
  }

  /// Stops a routine after yesterday; past occurrences stay in history.
  void endRoutine(String id) {
    final r = routineById(id);
    if (r == null) return;
    final yesterday = dateKey(addDays(now, -1));
    if (r.startDate.compareTo(yesterday) > 0) {
      deleteRoutine(id);
      return;
    }
    _blocks.removeWhere((b) => b.routineId == id && b.date.compareTo(yesterday) > 0);
    saveRoutine(r.copyWith(endDate: () => yesterday));
  }

  /// Deletes a routine and every occurrence of it.
  void deleteRoutine(String id) {
    _routines.removeWhere((r) => r.id == id);
    _blocks.removeWhere((b) => b.routineId == id);
    _commit();
  }

  void _skipOccurrence(String routineId, String date) {
    final i = _routines.indexWhere((r) => r.id == routineId);
    if (i < 0) return;
    _routines[i] = _routines[i].copyWith(skipDates: {..._routines[i].skipDates, date});
  }

  // ------------------------------------------------------------------ tasks

  static int _taskOrder(Task a, Task b) {
    if (a.done != b.done) return a.done ? 1 : -1;
    if (a.important != b.important) return a.important ? -1 : 1;
    return a.createdAt.compareTo(b.createdAt);
  }

  List<Task> tasksOn(String date) => _tasks.where((t) => t.date == date).toList()..sort(_taskOrder);

  /// Unfinished tasks from days before [date].
  List<Task> overdueTasks(String date) =>
      _tasks.where((t) => !t.done && t.date.compareTo(date) < 0).toList()..sort(_taskOrder);

  Task addTask(String title, String date, {bool important = false, String? goalId}) {
    final task = Task(
      id: newId(),
      title: title,
      date: date,
      createdAt: now.millisecondsSinceEpoch,
      important: important,
      goalId: goalId,
    );
    _tasks.add(task);
    _commit();
    return task;
  }

  void saveTask(Task task) {
    _upsert(_tasks, task, (t) => t.id);
    _commit();
  }

  Task? deleteTask(String id) => _remove(_tasks, (t) => t.id == id);

  void toggleTask(String id) {
    final i = _tasks.indexWhere((t) => t.id == id);
    if (i < 0) return;
    _tasks[i] = _tasks[i].copyWith(done: !_tasks[i].done);
    _commit();
  }

  void moveTasks(Iterable<String> ids, String date) {
    final set = ids.toSet();
    for (var i = 0; i < _tasks.length; i++) {
      if (set.contains(_tasks[i].id)) _tasks[i] = _tasks[i].copyWith(date: date);
    }
    _commit();
  }

  // ------------------------------------------------------------------ goals

  Goal? goalById(String? id) {
    if (id == null) return null;
    for (final g in _goals) {
      if (g.id == id) return g;
    }
    return null;
  }

  void saveGoal(Goal goal) {
    _upsert(_goals, goal, (g) => g.id);
    _commit();
  }

  /// Deletes a goal; linked tasks, blocks, routines and sub-goals are kept
  /// but no longer point at it.
  void deleteGoal(String id) {
    _goals.removeWhere((g) => g.id == id);
    for (var i = 0; i < _goals.length; i++) {
      if (_goals[i].parentId == id) _goals[i] = _goals[i].copyWith(parentId: () => null);
    }
    for (var i = 0; i < _blocks.length; i++) {
      if (_blocks[i].goalId == id) _blocks[i] = _blocks[i].copyWith(goalId: () => null);
    }
    for (var i = 0; i < _routines.length; i++) {
      if (_routines[i].goalId == id) _routines[i] = _routines[i].copyWith(goalId: () => null);
    }
    for (var i = 0; i < _tasks.length; i++) {
      if (_tasks[i].goalId == id) _tasks[i] = _tasks[i].copyWith(goalId: () => null);
    }
    _commit();
  }

  void toggleMilestone(String goalId, String milestoneId) {
    final goal = goalById(goalId);
    if (goal == null) return;
    saveGoal(
      goal.copyWith(
        milestones: [
          for (final m in goal.milestones) m.id == milestoneId ? m.copyWith(done: !m.done) : m,
        ],
      ),
    );
  }

  List<Goal> childrenOf(String goalId) => _goals.where((g) => g.parentId == goalId).toList();

  Set<String> descendantsOf(String goalId) {
    final result = <String>{};
    final queue = [goalId];
    while (queue.isNotEmpty) {
      final id = queue.removeLast();
      for (final child in childrenOf(id)) {
        if (result.add(child.id)) queue.add(child.id);
      }
    }
    return result;
  }

  /// Goals that [goal] (with [horizon]) may belong to: longer horizon,
  /// not itself or one of its own sub-goals.
  List<Goal> parentCandidates(Goal? goal, Horizon horizon) {
    final excluded = goal == null ? <String>{} : {goal.id, ...descendantsOf(goal.id)};
    return _goals
        .where(
          (g) =>
              g.horizon.index > horizon.index &&
              !excluded.contains(g.id) &&
              (!g.completed || g.id == goal?.parentId),
        )
        .toList();
  }

  /// Progress including sub-goals: each milestone and each sub-goal counts
  /// as one equal part.
  double progressOf(Goal goal, [Set<String>? seen]) {
    if (goal.completed) return 1;
    seen ??= <String>{};
    if (!seen.add(goal.id)) return goal.progress;
    final parts = <double>[
      for (final m in goal.milestones) m.done ? 1 : 0,
      for (final child in childrenOf(goal.id)) progressOf(child, seen),
    ];
    return parts.isEmpty ? 0 : parts.reduce((a, b) => a + b) / parts.length;
  }

  /// Minutes of time blocks linked to a goal, including routine occurrences
  /// up to the goal's deadline (or today if it has none).
  int plannedMinutesFor(String goalId) {
    var total = _blocks.where((b) => b.goalId == goalId).fold(0, (sum, b) => sum + b.duration);
    final until = goalById(goalId)?.dueDate ?? todayKey;
    for (final r in _routines) {
      if (r.goalId == goalId) total += _routineMinutesUntil(r, until);
    }
    return total;
  }

  int _routineMinutesUntil(Routine r, String until) {
    final endKey = r.endDate != null && r.endDate!.compareTo(until) < 0 ? r.endDate! : until;
    final overridden = {
      for (final b in _blocks)
        if (b.routineId == r.id) b.date,
    };
    final last = parseDateKey(endKey);
    var total = 0;
    var guard = 0;
    for (var d = parseDateKey(r.startDate); !d.isAfter(last) && guard < 4000; d = addDays(d, 1)) {
      guard++;
      final k = dateKey(d);
      if (r.occursOn(d, k) && !overridden.contains(k)) total += r.duration;
    }
    return total;
  }

  ({int done, int total}) taskStatsFor(String goalId) {
    final linked = _tasks.where((t) => t.goalId == goalId);
    return (done: linked.where((t) => t.done).length, total: linked.length);
  }

  // ----------------------------------------------------------------- habits

  void saveHabit(Habit habit) {
    _upsert(_habits, habit, (h) => h.id);
    _commit();
  }

  Habit? deleteHabit(String id) => _remove(_habits, (h) => h.id == id);

  void toggleHabit(String id, String date) {
    final i = _habits.indexWhere((h) => h.id == id);
    if (i < 0) return;
    final done = {..._habits[i].doneDates};
    if (!done.remove(date)) done.add(date);
    _habits[i] = _habits[i].copyWith(doneDates: done);
    _commit();
  }

  // ------------------------------------------------------------ focus timer

  ActiveFocus? get activeFocus => _focus;

  /// Starts a focus timer, optionally for a block (whose length becomes the
  /// target). Any running timer is stopped and logged first.
  void startFocus({TimeBlock? block}) {
    if (_focus != null) stopFocus();
    var b = block;
    if (b != null && b.isVirtual) b = saveBlock(b);
    _focus = ActiveFocus(
      title: b?.title ?? 'Focus session',
      date: b?.date ?? todayKey,
      startedAt: now.millisecondsSinceEpoch,
      targetMinutes: b != null ? max(5, b.duration) : _settings.focusMinutes,
      blockId: b?.id,
      goalId: b?.goalId,
    );
    _commit();
  }

  void pauseFocus() {
    final f = _focus;
    if (f == null || !f.running) return;
    _focus = f.copyWith(accumulatedMs: f.elapsedMs(now.millisecondsSinceEpoch), running: false);
    _commit();
  }

  void resumeFocus() {
    final f = _focus;
    if (f == null || f.running) return;
    _focus = f.copyWith(startedAt: now.millisecondsSinceEpoch, running: true);
    _commit();
  }

  void markFocusAlerted() {
    final f = _focus;
    if (f == null || f.alerted) return;
    _focus = f.copyWith(alerted: true);
    _commit();
  }

  /// Stops the timer. With [save], logs a session if at least a minute passed.
  FocusSession? stopFocus({bool save = true}) {
    final f = _focus;
    if (f == null) return null;
    _focus = null;
    final nowMs = now.millisecondsSinceEpoch;
    final elapsed = f.elapsedMs(nowMs);
    final minutes = (elapsed / 60000).round();
    FocusSession? session;
    if (save && minutes >= 1) {
      session = FocusSession(
        id: newId(),
        date: f.date,
        startedAt: nowMs - elapsed,
        minutes: minutes,
        title: f.title,
        blockId: f.blockId,
        goalId: f.goalId,
      );
      _sessions.add(session);
    }
    _commit();
    return session;
  }

  int focusMinutesForBlock(String blockId) =>
      _sessions.where((s) => s.blockId == blockId).fold(0, (sum, s) => sum + s.minutes);

  int focusMinutesForGoal(String goalId) =>
      _sessions.where((s) => s.goalId == goalId).fold(0, (sum, s) => sum + s.minutes);

  List<FocusSession> sessionsBetween(String from, String to) =>
      _sessions.where((s) => s.date.compareTo(from) >= 0 && s.date.compareTo(to) <= 0).toList();

  // ------------------------------------------------------------- week plans

  WeekPlan weekPlan(String weekStart) => _weekPlans[weekStart] ?? WeekPlan(weekStart: weekStart);

  void saveWeekPlan(WeekPlan plan) {
    if (plan.isEmpty) {
      _weekPlans.remove(plan.weekStart);
    } else {
      _weekPlans[plan.weekStart] = plan;
    }
    _commit();
  }

  /// Focus goals for the week containing [day] that still exist.
  List<Goal> focusGoalsFor(DateTime day) => [
    for (final id in weekPlan(dateKey(startOfWeek(day))).focusGoalIds) ?goalById(id),
  ];

  // ------------------------------------------------------------------ notes

  String noteFor(String date) => _notes[date] ?? '';
  bool hasNote(String date) => _notes.containsKey(date);

  void setNote(String date, String text) {
    if (text.trim().isEmpty) {
      _notes.remove(date);
    } else {
      _notes[date] = text;
    }
    _commit();
  }

  // ------------------------------------------------------------ persistence

  Map<String, dynamic> toJson() => {
    'version': schemaVersion,
    'savedAt': _savedAt,
    'settings': _settings.toJson(),
    'blocks': [for (final b in _blocks) b.toJson()],
    'routines': [for (final r in _routines) r.toJson()],
    'tasks': [for (final t in _tasks) t.toJson()],
    'goals': [for (final g in _goals) g.toJson()],
    'habits': [for (final h in _habits) h.toJson()],
    'sessions': [for (final s in _sessions) s.toJson()],
    'weekPlans': [for (final p in _weekPlans.values) p.toJson()],
    'notes': _notes,
    if (_focus != null) 'activeFocus': _focus!.toJson(),
  };

  String exportJson() =>
      const JsonEncoder.withIndent('  ')
          .convert({...toJson(), 'exportedAt': DateTime.now().toIso8601String()});

  static bool _looksLikeBackup(Object? decoded) =>
      decoded is Map<String, dynamic> &&
      const ['blocks', 'tasks', 'goals', 'habits'].any(decoded.containsKey);

  /// Replaces all data with the contents of a backup.
  /// Throws [FormatException] if [source] isn't a planner backup.
  void importJson(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException {
      throw const FormatException('That file is not valid JSON.');
    }
    if (!_looksLikeBackup(decoded)) {
      throw const FormatException("That doesn't look like a Planner backup.");
    }
    _apply(decoded as Map<String, dynamic>);
    _commit();
  }

  /// Removes all planning data. Settings are kept.
  void clearAll() {
    _blocks.clear();
    _routines.clear();
    _tasks.clear();
    _goals.clear();
    _habits.clear();
    _sessions.clear();
    _weekPlans.clear();
    _notes.clear();
    _focus = null;
    _commit();
  }

  String get storageLabel => _storage.label;
  int _storedBytes = 0;

  /// Size of the last saved document, in bytes (approximately).
  int get storedBytes => _storedBytes;

  String? _saveError;

  /// Set when the last save failed (e.g. storage full).
  String? get saveError => _saveError;

  void _apply(Map<String, dynamic> json) {
    List<Map<String, dynamic>> maps(String key) =>
        (json[key] as List? ?? const []).whereType<Map<String, dynamic>>().toList();

    // Parse everything first so a bad record can't leave us half-loaded.
    final blocks = [for (final m in maps('blocks')) TimeBlock.fromJson(m)];
    final routines = [for (final m in maps('routines')) Routine.fromJson(m)];
    final tasks = [for (final m in maps('tasks')) Task.fromJson(m)];
    final goals = [for (final m in maps('goals')) Goal.fromJson(m)];
    final habits = [for (final m in maps('habits')) Habit.fromJson(m)];
    final sessions = [for (final m in maps('sessions')) FocusSession.fromJson(m)];
    final weekPlans = [for (final m in maps('weekPlans')) WeekPlan.fromJson(m)];
    final notes = <String, String>{
      for (final e in (json['notes'] as Map? ?? const {}).entries)
        if (e.key is String && e.value is String) e.key as String: e.value as String,
    };
    var settings = json['settings'] is Map<String, dynamic>
        ? PlannerSettings.fromJson(json['settings'] as Map<String, dynamic>)
        : _settings;
    // Data from before pink & blue: the old default accent moves to the new one.
    final version = json['version'] is num ? (json['version'] as num).toInt() : 1;
    if (version < 3 && settings.seedColor == legacyDefaultAccent) {
      settings = settings.copyWith(seedColor: defaultAccent);
    }
    final focus = json['activeFocus'] is Map<String, dynamic>
        ? ActiveFocus.fromJson(json['activeFocus'] as Map<String, dynamic>)
        : null;

    _blocks
      ..clear()
      ..addAll(blocks.where((b) => b.date.isNotEmpty));
    _routines
      ..clear()
      ..addAll(routines);
    _tasks
      ..clear()
      ..addAll(tasks.where((t) => t.date.isNotEmpty));
    _goals
      ..clear()
      ..addAll(goals);
    _habits
      ..clear()
      ..addAll(habits);
    _sessions
      ..clear()
      ..addAll(sessions.where((s) => s.date.isNotEmpty));
    _weekPlans
      ..clear()
      ..addEntries(
        weekPlans.where((p) => p.weekStart.isNotEmpty).map((p) => MapEntry(p.weekStart, p)),
      );
    _notes
      ..clear()
      ..addAll(notes);
    _settings = settings;
    _focus = focus;
    _savedAt = json['savedAt'] is num ? (json['savedAt'] as num).toInt() : 0;
    _index = null;
  }

  /// Records a change: notifies listeners and saves.
  void _commit() {
    _index = null;
    _savedAt = max(_savedAt + 1, now.millisecondsSinceEpoch);
    notifyListeners();
    _persist();
  }

  // Writes are queued so that at most one is in flight and the latest
  // state always wins, without timers.
  bool _dirty = false;
  Future<void>? _writer;

  void _persist() {
    _dirty = true;
    _ensureWriter();
  }

  void _ensureWriter() {
    _writer ??= _drainWrites().whenComplete(() {
      _writer = null;
      if (_dirty) _ensureWriter();
    });
  }

  Future<void> _drainWrites() async {
    while (_dirty) {
      _dirty = false;
      final json = jsonEncode(toJson());
      try {
        await _storage.write(json);
        _storedBytes = json.length;
        if (_saveError != null) {
          _saveError = null;
          notifyListeners();
        }
      } catch (e) {
        _saveError = '$e';
        notifyListeners();
      }
      await _writeSyncFile(json);
    }
  }

  /// Completes once every pending change has been written.
  Future<void> flush() async {
    while (_writer != null) {
      await _writer;
    }
  }

  // ------------------------------------------------------------ sync file

  SyncFile? _syncFile;
  SyncState _syncState = SyncState.off;
  String? _syncError;
  ({String text, int savedAt})? _incoming;

  SyncState get syncState => _syncState;
  String? get syncFileName => _syncFile?.name;
  String? get syncError => _syncError;

  /// When the sync file holds newer data than this browser (e.g. it was
  /// edited on another computer), this is when that data was saved.
  int? get incomingSyncSavedAt => _incoming?.savedAt;

  Future<void> _restoreSync() async {
    final file = await restoreSyncFile();
    if (file == null) return;
    _syncFile = file;
    try {
      if (await file.permission() == SyncPermission.granted) {
        _syncState = SyncState.connected;
        await _checkSyncFile();
      } else {
        _syncState = SyncState.needsPermission;
      }
    } catch (e) {
      _setSyncError(e);
    }
  }

  Future<void> _writeSyncFile(String json) async {
    final file = _syncFile;
    // Don't overwrite newer data from another device before the user decides.
    if (file == null || _syncState != SyncState.connected || _incoming != null) return;
    try {
      await file.write(json);
    } catch (e) {
      _setSyncError(e);
      notifyListeners();
    }
  }

  /// Compares the sync file with local data: newer data there is offered via
  /// [incomingSyncSavedAt]; otherwise the file is brought up to date.
  Future<void> _checkSyncFile() async {
    final file = _syncFile;
    if (file == null || _syncState != SyncState.connected) return;
    try {
      final text = (await file.read()).text;
      Object? decoded;
      try {
        decoded = text.trim().isEmpty ? null : jsonDecode(text);
      } on FormatException {
        decoded = null;
      }
      final theirs = _looksLikeBackup(decoded)
          ? ((decoded as Map<String, dynamic>)['savedAt'] as num?)?.toInt() ?? 0
          : -1;
      if (theirs > _savedAt) {
        _incoming = (text: text, savedAt: theirs);
      } else if (theirs < _savedAt) {
        _incoming = null;
        await file.write(jsonEncode(toJson()));
      }
      _syncError = null;
    } catch (e) {
      _setSyncError(e);
    }
    notifyListeners();
  }

  void _setSyncError(Object e) {
    _syncState = SyncState.error;
    _syncError = '$e';
  }

  /// Call when the app regains focus to pick up changes from other devices.
  Future<void> checkSyncFile() => _checkSyncFile();

  /// Lets the user create a new sync file and fills it with local data.
  Future<void> createAndConnectSyncFile() async {
    final file = await createSyncFile();
    if (file != null) await connectSyncFile(file, overwrite: true);
  }

  /// Lets the user pick an existing sync file (e.g. from another computer).
  Future<void> openAndConnectSyncFile() async {
    final file = await openSyncFile();
    if (file != null) await connectSyncFile(file);
  }

  /// Starts mirroring to [file]. Unless [overwrite] is set, newer data in
  /// the file is offered first (see [incomingSyncSavedAt]).
  Future<void> connectSyncFile(SyncFile file, {bool overwrite = false}) async {
    _syncFile = file;
    _syncState = SyncState.connected;
    _syncError = null;
    _incoming = null;
    if (overwrite) {
      try {
        await file.write(jsonEncode(toJson()));
      } catch (e) {
        _setSyncError(e);
      }
      notifyListeners();
    } else {
      await _checkSyncFile();
    }
  }

  /// Re-grants access after a reload. Must be called from a user gesture.
  Future<void> reconnectSyncFile() async {
    final file = _syncFile;
    if (file == null) return;
    try {
      final ok = await file.requestPermission();
      _syncState = ok ? SyncState.connected : SyncState.needsPermission;
      _syncError = null;
      if (ok) await _checkSyncFile();
    } catch (e) {
      _setSyncError(e);
    }
    notifyListeners();
  }

  Future<void> disconnectSyncFile() async {
    await forgetSyncFile();
    _syncFile = null;
    _syncState = SyncState.off;
    _syncError = null;
    _incoming = null;
    notifyListeners();
  }

  /// Replaces local data with the newer data from the sync file.
  void acceptIncomingSync() {
    final incoming = _incoming;
    if (incoming == null) return;
    _incoming = null;
    _apply(jsonDecode(incoming.text) as Map<String, dynamic>);
    notifyListeners();
    _persist();
  }

  /// Keeps local data and overwrites the sync file with it.
  void rejectIncomingSync() {
    if (_incoming == null) return;
    _incoming = null;
    _commit();
  }

  // ---------------------------------------------------------------- helpers

  T? _remove<T>(List<T> list, bool Function(T) test) {
    final i = list.indexWhere(test);
    if (i < 0) return null;
    final removed = list.removeAt(i);
    _commit();
    return removed;
  }

  static void _upsert<T>(List<T> list, T item, String Function(T) idOf) {
    final i = list.indexWhere((e) => idOf(e) == idOf(item));
    if (i >= 0) {
      list[i] = item;
    } else {
      list.add(item);
    }
  }

  void _seedFirstRun() {
    final day = today();
    _goals.add(
      Goal(
        id: newId(),
        title: 'Get started with Planner',
        description: 'A short tour. Tick these off as you go, then delete this goal.',
        horizon: Horizon.week,
        dueDate: dateKey(endOfWeek(day)),
        color: plannerColors.first,
        createdAt: now.millisecondsSinceEpoch,
        milestones: [
          for (final t in const [
            'Click an empty slot in the Day timeline to add a time block',
            'Make a block repeat, e.g. a morning routine',
            'Start a focus timer on a block',
            'Drag a task onto a day in the Week view',
            'Create a quarter goal and give it a monthly sub-goal',
            'Do a weekly review and pick next week\'s focus',
            'Export a backup or set up a sync file in Settings',
          ])
            Milestone(id: newId(), title: t),
        ],
      ),
    );
  }
}
