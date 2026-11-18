import 'package:intl/intl.dart';

String _two(int n) => n.toString().padLeft(2, '0');

/// Stable storage key for a calendar day: `yyyy-MM-dd`.
/// Keys sort lexicographically in chronological order.
String dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)}';

DateTime parseDateKey(String key) {
  final p = key.split('-');
  return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime today() => dateOnly(DateTime.now());

/// Calendar-day arithmetic that is safe across DST changes.
DateTime addDays(DateTime d, int days) => DateTime(d.year, d.month, d.day + days);

bool isSameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// Weeks start on Monday.
DateTime startOfWeek(DateTime d) => addDays(dateOnly(d), 1 - d.weekday);
DateTime endOfWeek(DateTime d) => addDays(startOfWeek(d), 6);
DateTime endOfMonth(DateTime d) => DateTime(d.year, d.month + 1, 0);
int quarterOf(DateTime d) => (d.month - 1) ~/ 3 + 1;
DateTime startOfQuarter(DateTime d) => DateTime(d.year, (quarterOf(d) - 1) * 3 + 1, 1);
DateTime endOfQuarter(DateTime d) => DateTime(d.year, quarterOf(d) * 3 + 1, 0);
DateTime endOfYear(DateTime d) => DateTime(d.year, 12, 31);

int daysBetween(DateTime from, DateTime to) => DateTime.utc(
  to.year,
  to.month,
  to.day,
).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

/// Formats minutes-after-midnight (0..1440) as a clock time.
String formatClock(int minutes, {required bool use24h}) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (use24h) return '${_two(h)}:${_two(m)}';
  final period = (h < 12 || h == 24) ? 'AM' : 'PM';
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return m == 0 ? '$h12 $period' : '$h12:${_two(m)} $period';
}

String formatDuration(int minutes) {
  if (minutes <= 0) return '0m';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '${m}m';
  if (m == 0) return '${h}h';
  return '${h}h ${m}m';
}

String relativeDayLabel(DateTime d) => switch (daysBetween(today(), d)) {
  0 => 'Today',
  1 => 'Tomorrow',
  -1 => 'Yesterday',
  _ => '',
};

String dueLabel(DateTime due) {
  final diff = daysBetween(today(), due);
  if (diff == 0) return 'Due today';
  if (diff == 1) return 'Due tomorrow';
  if (diff < 0) return 'Overdue by ${-diff} day${diff == -1 ? '' : 's'}';
  if (diff < 14) return '$diff days left';
  if (diff < 60) return '${(diff / 7).round()} weeks left';
  return 'Due ${DateFormat.yMMMd().format(due)}';
}
