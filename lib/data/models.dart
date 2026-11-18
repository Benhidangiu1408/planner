import 'dart:math';

import '../util/dates.dart';
import '../util/palette.dart';

final _rng = Random();

String newId() =>
    DateTime.now().microsecondsSinceEpoch.toRadixString(36) +
    _rng.nextInt(1 << 30).toRadixString(36);

int _int(Object? v, int fallback) => v is num ? v.toInt() : fallback;
String _str(Object? v, [String fallback = '']) => v is String ? v : fallback;
String? _strOrNull(Object? v) => v is String && v.isNotEmpty ? v : null;
bool _bool(Object? v) => v == true;
List<Map<String, dynamic>> _maps(Object? v) =>
    v is List ? v.whereType<Map<String, dynamic>>().toList() : const [];
List<int> _weekdays(Object? v) => [
  for (final w in (v is List ? v : const []))
    if (w is num && w >= 1 && w <= 7) w.toInt(),
];
List<String> _stringList(Object? v) => [
  for (final s in (v is List ? v : const []))
    if (s is String) s,
];

/// Human-readable weekday selection, e.g. "Every day", "Weekdays", "Mon, Wed".
String describeWeekdays(List<int> weekdays) {
  if (weekdays.isEmpty || weekdays.length == 7) return 'Every day';
  final set = weekdays.toSet();
  if (set.length == 5 && !set.contains(6) && !set.contains(7)) return 'Weekdays';
  if (set.length == 2 && set.contains(6) && set.contains(7)) return 'Weekends';
  const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return (weekdays.toList()..sort()).map((d) => names[d - 1]).join(', ');
}

/// A slot on the day timeline (short-range planning).
class TimeBlock {
  const TimeBlock({
    required this.id,
    required this.date,
    required this.start,
    required this.end,
    required this.title,
    required this.color,
    this.notes = '',
    this.done = false,
    this.goalId,
    this.routineId,
  });

  final String id;

  /// Day key, see [dateKey].
  final String date;

  /// Minutes after midnight, 0..1440. [end] is exclusive.
  final int start;
  final int end;
  final String title;
  final String notes;
  final int color;
  final bool done;
  final String? goalId;

  /// Set when this block is (or was generated from) a [Routine].
  final String? routineId;

  int get duration => end - start;

  /// True for a routine occurrence that hasn't been changed yet and so only
  /// exists virtually (computed from its routine).
  bool get isVirtual => Routine.isVirtualId(id);

  TimeBlock copyWith({
    String? id,
    String? date,
    int? start,
    int? end,
    String? title,
    String? notes,
    int? color,
    bool? done,
    String? Function()? goalId,
    String? Function()? routineId,
  }) => TimeBlock(
    id: id ?? this.id,
    date: date ?? this.date,
    start: start ?? this.start,
    end: end ?? this.end,
    title: title ?? this.title,
    notes: notes ?? this.notes,
    color: color ?? this.color,
    done: done ?? this.done,
    goalId: goalId != null ? goalId() : this.goalId,
    routineId: routineId != null ? routineId() : this.routineId,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'date': date,
    'start': start,
    'end': end,
    'title': title,
    if (notes.isNotEmpty) 'notes': notes,
    'color': color,
    if (done) 'done': true,
    if (goalId != null) 'goalId': goalId,
    if (routineId != null) 'routineId': routineId,
  };

  factory TimeBlock.fromJson(Map<String, dynamic> j) {
    final start = _int(j['start'], 540).clamp(0, 1425);
    return TimeBlock(
      id: _str(j['id'], newId()),
      date: _str(j['date']),
      start: start,
      end: _int(j['end'], start + 60).clamp(start + 5, 1440),
      title: _str(j['title']),
      notes: _str(j['notes']),
      color: _int(j['color'], 0xFF4F6BED),
      done: _bool(j['done']),
      goalId: _strOrNull(j['goalId']),
      routineId: _strOrNull(j['routineId']),
    );
  }
}

/// A time block that repeats on chosen weekdays, e.g. "every weekday 7:00 run".
///
/// Occurrences are computed, not stored. Changing a single occurrence stores
/// a concrete [TimeBlock] with [TimeBlock.routineId] that overrides it for
/// that day; deleting one adds the day to [skipDates].
class Routine {
  const Routine({
    required this.id,
    required this.title,
    required this.start,
    required this.end,
    required this.color,
    required this.startDate,
    this.endDate,
    this.weekdays = const [],
    this.notes = '',
    this.goalId,
    this.skipDates = const {},
  });

  final String id;
  final String title;
  final int start;
  final int end;
  final int color;
  final String notes;
  final String? goalId;

  /// ISO weekdays (1 = Monday … 7 = Sunday). Empty means every day.
  final List<int> weekdays;

  /// First and (optional) last day key on which the routine occurs.
  final String startDate;
  final String? endDate;

  /// Days on which a single occurrence was removed.
  final Set<String> skipDates;

  int get duration => end - start;

  static const _prefix = 'r~';

  static String virtualId(String routineId, String date) => '$_prefix$routineId~$date';
  static bool isVirtualId(String id) => id.startsWith(_prefix);

  /// Splits a virtual block id into its routine id and date.
  static (String routineId, String date)? parseVirtualId(String id) {
    if (!isVirtualId(id)) return null;
    final rest = id.substring(_prefix.length);
    final i = rest.lastIndexOf('~');
    if (i <= 0) return null;
    return (rest.substring(0, i), rest.substring(i + 1));
  }

  bool occursOn(DateTime day, [String? key]) {
    final k = key ?? dateKey(day);
    if (k.compareTo(startDate) < 0) return false;
    if (endDate != null && k.compareTo(endDate!) > 0) return false;
    if (weekdays.isNotEmpty && !weekdays.contains(day.weekday)) return false;
    return !skipDates.contains(k);
  }

  TimeBlock instanceOn(String date) => TimeBlock(
    id: virtualId(id, date),
    date: date,
    start: start,
    end: end,
    title: title,
    color: color,
    notes: notes,
    goalId: goalId,
    routineId: id,
  );

  Routine copyWith({
    String? title,
    int? start,
    int? end,
    int? color,
    String? notes,
    String? Function()? goalId,
    List<int>? weekdays,
    String? startDate,
    String? Function()? endDate,
    Set<String>? skipDates,
  }) => Routine(
    id: id,
    title: title ?? this.title,
    start: start ?? this.start,
    end: end ?? this.end,
    color: color ?? this.color,
    notes: notes ?? this.notes,
    goalId: goalId != null ? goalId() : this.goalId,
    weekdays: weekdays ?? this.weekdays,
    startDate: startDate ?? this.startDate,
    endDate: endDate != null ? endDate() : this.endDate,
    skipDates: skipDates ?? this.skipDates,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'start': start,
    'end': end,
    'color': color,
    if (notes.isNotEmpty) 'notes': notes,
    if (goalId != null) 'goalId': goalId,
    if (weekdays.isNotEmpty) 'weekdays': weekdays,
    'startDate': startDate,
    if (endDate != null) 'endDate': endDate,
    if (skipDates.isNotEmpty) 'skipDates': (skipDates.toList()..sort()),
  };

  factory Routine.fromJson(Map<String, dynamic> j) {
    final start = _int(j['start'], 420).clamp(0, 1425);
    return Routine(
      id: _str(j['id'], newId()),
      title: _str(j['title']),
      start: start,
      end: _int(j['end'], start + 30).clamp(start + 5, 1440),
      color: _int(j['color'], 0xFF2BA36B),
      notes: _str(j['notes']),
      goalId: _strOrNull(j['goalId']),
      weekdays: _weekdays(j['weekdays']),
      startDate: _str(j['startDate'], dateKey(today())),
      endDate: _strOrNull(j['endDate']),
      skipDates: _stringList(j['skipDates']).toSet(),
    );
  }
}

/// A to-do for a specific day.
class Task {
  const Task({
    required this.id,
    required this.title,
    required this.date,
    required this.createdAt,
    this.done = false,
    this.important = false,
    this.goalId,
  });

  final String id;
  final String title;
  final String date;
  final bool done;
  final bool important;
  final String? goalId;

  /// Milliseconds since epoch, used for stable ordering.
  final int createdAt;

  Task copyWith({
    String? title,
    String? date,
    bool? done,
    bool? important,
    String? Function()? goalId,
  }) => Task(
    id: id,
    title: title ?? this.title,
    date: date ?? this.date,
    createdAt: createdAt,
    done: done ?? this.done,
    important: important ?? this.important,
    goalId: goalId != null ? goalId() : this.goalId,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'date': date,
    'createdAt': createdAt,
    if (done) 'done': true,
    if (important) 'important': true,
    if (goalId != null) 'goalId': goalId,
  };

  factory Task.fromJson(Map<String, dynamic> j) => Task(
    id: _str(j['id'], newId()),
    title: _str(j['title']),
    date: _str(j['date']),
    createdAt: _int(j['createdAt'], 0),
    done: _bool(j['done']),
    important: _bool(j['important']),
    goalId: _strOrNull(j['goalId']),
  );
}

/// How far ahead a goal looks (long-range planning). Ordered short → long.
enum Horizon {
  week('This week', 'What would make this week a success?'),
  month('This month', 'One or two outcomes that matter this month.'),
  quarter('This quarter', 'A meaningful project for the next three months.'),
  year('This year', 'Where do you want to be by the end of the year?'),
  longTerm('Long term', 'Bigger dreams and directions, no rush.');

  const Horizon(this.label, this.prompt);
  final String label;
  final String prompt;

  /// Sensible default deadline for a goal created today in this horizon.
  DateTime? defaultDue(DateTime from) => switch (this) {
    Horizon.week => endOfWeek(from),
    Horizon.month => endOfMonth(from),
    Horizon.quarter => endOfQuarter(from),
    Horizon.year => endOfYear(from),
    Horizon.longTerm => null,
  };

  /// The next shorter horizon (used when adding a sub-goal).
  Horizon get shorter => index == 0 ? this : Horizon.values[index - 1];

  static Horizon parse(Object? name) =>
      Horizon.values.firstWhere((h) => h.name == name, orElse: () => Horizon.month);
}

class Milestone {
  const Milestone({required this.id, required this.title, this.done = false});

  final String id;
  final String title;
  final bool done;

  Milestone copyWith({String? title, bool? done}) =>
      Milestone(id: id, title: title ?? this.title, done: done ?? this.done);

  Map<String, dynamic> toJson() => {'id': id, 'title': title, if (done) 'done': true};

  factory Milestone.fromJson(Map<String, dynamic> j) =>
      Milestone(id: _str(j['id'], newId()), title: _str(j['title']), done: _bool(j['done']));
}

class Goal {
  const Goal({
    required this.id,
    required this.title,
    required this.horizon,
    required this.color,
    required this.createdAt,
    this.description = '',
    this.dueDate,
    this.milestones = const [],
    this.completed = false,
    this.parentId,
  });

  final String id;
  final String title;
  final String description;
  final Horizon horizon;
  final String? dueDate;
  final int color;
  final List<Milestone> milestones;
  final bool completed;
  final int createdAt;

  /// The longer-horizon goal this one contributes to.
  final String? parentId;

  /// Progress from this goal's own milestones. See
  /// `PlannerStore.progressOf` for progress that includes sub-goals.
  double get progress {
    if (completed) return 1;
    if (milestones.isEmpty) return 0;
    return milestones.where((m) => m.done).length / milestones.length;
  }

  Milestone? get nextMilestone {
    for (final m in milestones) {
      if (!m.done) return m;
    }
    return null;
  }

  Goal copyWith({
    String? title,
    String? description,
    Horizon? horizon,
    String? Function()? dueDate,
    int? color,
    List<Milestone>? milestones,
    bool? completed,
    String? Function()? parentId,
  }) => Goal(
    id: id,
    title: title ?? this.title,
    description: description ?? this.description,
    horizon: horizon ?? this.horizon,
    dueDate: dueDate != null ? dueDate() : this.dueDate,
    color: color ?? this.color,
    milestones: milestones ?? this.milestones,
    completed: completed ?? this.completed,
    createdAt: createdAt,
    parentId: parentId != null ? parentId() : this.parentId,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    if (description.isNotEmpty) 'description': description,
    'horizon': horizon.name,
    if (dueDate != null) 'dueDate': dueDate,
    'color': color,
    'milestones': [for (final m in milestones) m.toJson()],
    if (completed) 'completed': true,
    'createdAt': createdAt,
    if (parentId != null) 'parentId': parentId,
  };

  factory Goal.fromJson(Map<String, dynamic> j) => Goal(
    id: _str(j['id'], newId()),
    title: _str(j['title']),
    description: _str(j['description']),
    horizon: Horizon.parse(j['horizon']),
    dueDate: _strOrNull(j['dueDate']),
    color: _int(j['color'], 0xFF4F6BED),
    milestones: [for (final m in _maps(j['milestones'])) Milestone.fromJson(m)],
    completed: _bool(j['completed']),
    createdAt: _int(j['createdAt'], 0),
    parentId: _strOrNull(j['parentId']),
  );
}

class Habit {
  const Habit({
    required this.id,
    required this.name,
    required this.color,
    required this.createdOn,
    this.weekdays = const [],
    this.doneDates = const {},
  });

  final String id;
  final String name;
  final int color;

  /// ISO weekdays (1 = Monday … 7 = Sunday). Empty means every day.
  final List<int> weekdays;

  /// Day keys on which the habit was completed.
  final Set<String> doneDates;

  /// Day key of creation; days before it don't count against the habit.
  final String createdOn;

  bool isScheduledOn(DateTime d) => weekdays.isEmpty || weekdays.contains(d.weekday);
  bool isDoneOn(DateTime d) => doneDates.contains(dateKey(d));

  /// First day that matters for statistics.
  DateTime get _firstDay {
    var first = parseDateKey(createdOn);
    for (final k in doneDates) {
      final d = parseDateKey(k);
      if (d.isBefore(first)) first = d;
    }
    return first;
  }

  /// Consecutive completed scheduled days, ending today (or yesterday if
  /// today is still open). Unscheduled days neither break nor extend it,
  /// unless the habit was done anyway.
  int currentStreak(DateTime now) {
    final first = _firstDay;
    var d = dateOnly(now);
    if (!isDoneOn(d)) d = addDays(d, -1);
    var streak = 0;
    while (!d.isBefore(first)) {
      if (isDoneOn(d)) {
        streak++;
      } else if (isScheduledOn(d)) {
        break;
      }
      d = addDays(d, -1);
    }
    return streak;
  }

  int bestStreak(DateTime now) {
    final end = dateOnly(now);
    var best = 0;
    var run = 0;
    for (var d = _firstDay; !d.isAfter(end); d = addDays(d, 1)) {
      if (isDoneOn(d)) {
        run++;
        if (run > best) best = run;
      } else if (isScheduledOn(d) && !isSameDay(d, end)) {
        run = 0;
      }
    }
    return best;
  }

  /// Done vs scheduled days between [from] and [to] (inclusive), ignoring
  /// days before the habit existed and days after [now]. Today only counts
  /// once it's done, so an open day doesn't drag the rate down.
  ({int done, int scheduled}) statsBetween(DateTime from, DateTime to, DateTime now) {
    final created = parseDateKey(createdOn);
    final today = dateOnly(now);
    var start = dateOnly(from);
    if (start.isBefore(created)) start = created;
    var end = dateOnly(to);
    if (end.isAfter(today)) end = today;
    var scheduled = 0;
    var done = 0;
    for (var d = start; !d.isAfter(end); d = addDays(d, 1)) {
      final isDone = isDoneOn(d);
      if (isSameDay(d, today) && !isDone) continue;
      if (isScheduledOn(d) || isDone) {
        scheduled++;
        if (isDone) done++;
      }
    }
    return (done: done, scheduled: scheduled);
  }

  /// Share of scheduled days completed over the last [days] days.
  double completionRate(DateTime now, {int days = 30}) {
    final s = statsBetween(addDays(now, 1 - days), now, now);
    return s.scheduled == 0 ? 0 : s.done / s.scheduled;
  }

  Habit copyWith({String? name, int? color, List<int>? weekdays, Set<String>? doneDates}) => Habit(
    id: id,
    name: name ?? this.name,
    color: color ?? this.color,
    createdOn: createdOn,
    weekdays: weekdays ?? this.weekdays,
    doneDates: doneDates ?? this.doneDates,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'color': color,
    'createdOn': createdOn,
    if (weekdays.isNotEmpty) 'weekdays': weekdays,
    'doneDates': (doneDates.toList()..sort()),
  };

  factory Habit.fromJson(Map<String, dynamic> j) => Habit(
    id: _str(j['id'], newId()),
    name: _str(j['name']),
    color: _int(j['color'], 0xFF2BA36B),
    createdOn: _str(j['createdOn'], dateKey(today())),
    weekdays: _weekdays(j['weekdays']),
    doneDates: _stringList(j['doneDates']).toSet(),
  );
}

/// A finished stretch of focused work, logged by the focus timer.
class FocusSession {
  const FocusSession({
    required this.id,
    required this.date,
    required this.startedAt,
    required this.minutes,
    required this.title,
    this.blockId,
    this.goalId,
  });

  final String id;
  final String date;
  final int startedAt;
  final int minutes;
  final String title;
  final String? blockId;
  final String? goalId;

  Map<String, dynamic> toJson() => {
    'id': id,
    'date': date,
    'startedAt': startedAt,
    'minutes': minutes,
    'title': title,
    if (blockId != null) 'blockId': blockId,
    if (goalId != null) 'goalId': goalId,
  };

  factory FocusSession.fromJson(Map<String, dynamic> j) => FocusSession(
    id: _str(j['id'], newId()),
    date: _str(j['date']),
    startedAt: _int(j['startedAt'], 0),
    minutes: _int(j['minutes'], 0),
    title: _str(j['title']),
    blockId: _strOrNull(j['blockId']),
    goalId: _strOrNull(j['goalId']),
  );
}

/// The focus timer that is currently running or paused.
class ActiveFocus {
  const ActiveFocus({
    required this.title,
    required this.date,
    required this.startedAt,
    required this.targetMinutes,
    this.accumulatedMs = 0,
    this.running = true,
    this.blockId,
    this.goalId,
    this.alerted = false,
  });

  final String title;
  final String date;

  /// When the current run started (ms since epoch). Ignored while paused.
  final int startedAt;

  /// Time from earlier runs before the last pause.
  final int accumulatedMs;
  final bool running;
  final int targetMinutes;
  final String? blockId;
  final String? goalId;

  /// Whether the "time's up" alert has already been shown.
  final bool alerted;

  int elapsedMs(int nowMs) => accumulatedMs + (running ? max(0, nowMs - startedAt) : 0);

  ActiveFocus copyWith({int? startedAt, int? accumulatedMs, bool? running, bool? alerted}) =>
      ActiveFocus(
        title: title,
        date: date,
        startedAt: startedAt ?? this.startedAt,
        targetMinutes: targetMinutes,
        accumulatedMs: accumulatedMs ?? this.accumulatedMs,
        running: running ?? this.running,
        blockId: blockId,
        goalId: goalId,
        alerted: alerted ?? this.alerted,
      );

  Map<String, dynamic> toJson() => {
    'title': title,
    'date': date,
    'startedAt': startedAt,
    'accumulatedMs': accumulatedMs,
    'running': running,
    'targetMinutes': targetMinutes,
    if (blockId != null) 'blockId': blockId,
    if (goalId != null) 'goalId': goalId,
    if (alerted) 'alerted': true,
  };

  factory ActiveFocus.fromJson(Map<String, dynamic> j) => ActiveFocus(
    title: _str(j['title'], 'Focus'),
    date: _str(j['date'], dateKey(today())),
    startedAt: _int(j['startedAt'], 0),
    accumulatedMs: _int(j['accumulatedMs'], 0),
    running: _bool(j['running']),
    targetMinutes: _int(j['targetMinutes'], 25).clamp(1, 600),
    blockId: _strOrNull(j['blockId']),
    goalId: _strOrNull(j['goalId']),
    alerted: _bool(j['alerted']),
  );
}

/// Intentions and reflection for one week (keyed by its Monday).
class WeekPlan {
  const WeekPlan({
    required this.weekStart,
    this.focusGoalIds = const [],
    this.intention = '',
    this.wentWell = '',
    this.improve = '',
  });

  final String weekStart;

  /// Up to three goals to concentrate on this week.
  final List<String> focusGoalIds;
  final String intention;
  final String wentWell;
  final String improve;

  bool get isEmpty =>
      focusGoalIds.isEmpty && intention.isEmpty && wentWell.isEmpty && improve.isEmpty;

  WeekPlan copyWith({
    List<String>? focusGoalIds,
    String? intention,
    String? wentWell,
    String? improve,
  }) => WeekPlan(
    weekStart: weekStart,
    focusGoalIds: focusGoalIds ?? this.focusGoalIds,
    intention: intention ?? this.intention,
    wentWell: wentWell ?? this.wentWell,
    improve: improve ?? this.improve,
  );

  Map<String, dynamic> toJson() => {
    'weekStart': weekStart,
    if (focusGoalIds.isNotEmpty) 'focusGoalIds': focusGoalIds,
    if (intention.isNotEmpty) 'intention': intention,
    if (wentWell.isNotEmpty) 'wentWell': wentWell,
    if (improve.isNotEmpty) 'improve': improve,
  };

  factory WeekPlan.fromJson(Map<String, dynamic> j) => WeekPlan(
    weekStart: _str(j['weekStart']),
    focusGoalIds: _stringList(j['focusGoalIds']),
    intention: _str(j['intention']),
    wentWell: _str(j['wentWell']),
    improve: _str(j['improve']),
  );
}

enum ThemePreference { system, light, dark }

class PlannerSettings {
  const PlannerSettings({
    this.theme = ThemePreference.system,
    this.seedColor = defaultAccent,
    this.dayStartHour = 6,
    this.dayEndHour = 23,
    this.use24h = true,
    this.remindersEnabled = false,
    this.reminderLeadMinutes = 5,
    this.focusMinutes = 25,
  });

  final ThemePreference theme;
  final int seedColor;
  final int dayStartHour;
  final int dayEndHour;
  final bool use24h;

  /// Notify before time blocks start.
  final bool remindersEnabled;
  final int reminderLeadMinutes;

  /// Default length of a focus session that isn't tied to a block.
  final int focusMinutes;

  PlannerSettings copyWith({
    ThemePreference? theme,
    int? seedColor,
    int? dayStartHour,
    int? dayEndHour,
    bool? use24h,
    bool? remindersEnabled,
    int? reminderLeadMinutes,
    int? focusMinutes,
  }) => PlannerSettings(
    theme: theme ?? this.theme,
    seedColor: seedColor ?? this.seedColor,
    dayStartHour: dayStartHour ?? this.dayStartHour,
    dayEndHour: dayEndHour ?? this.dayEndHour,
    use24h: use24h ?? this.use24h,
    remindersEnabled: remindersEnabled ?? this.remindersEnabled,
    reminderLeadMinutes: reminderLeadMinutes ?? this.reminderLeadMinutes,
    focusMinutes: focusMinutes ?? this.focusMinutes,
  );

  Map<String, dynamic> toJson() => {
    'theme': theme.name,
    'seedColor': seedColor,
    'dayStartHour': dayStartHour,
    'dayEndHour': dayEndHour,
    'use24h': use24h,
    'remindersEnabled': remindersEnabled,
    'reminderLeadMinutes': reminderLeadMinutes,
    'focusMinutes': focusMinutes,
  };

  factory PlannerSettings.fromJson(Map<String, dynamic> j) {
    final start = _int(j['dayStartHour'], 6).clamp(0, 12);
    return PlannerSettings(
      theme: ThemePreference.values.firstWhere(
        (t) => t.name == j['theme'],
        orElse: () => ThemePreference.system,
      ),
      seedColor: _int(j['seedColor'], defaultAccent),
      dayStartHour: start,
      dayEndHour: _int(j['dayEndHour'], 23).clamp(start + 1, 24),
      use24h: j['use24h'] is bool ? j['use24h'] as bool : true,
      remindersEnabled: _bool(j['remindersEnabled']),
      reminderLeadMinutes: _int(j['reminderLeadMinutes'], 5).clamp(0, 120),
      focusMinutes: _int(j['focusMinutes'], 25).clamp(5, 240),
    );
  }
}
