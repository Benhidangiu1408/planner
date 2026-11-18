import 'package:flutter_test/flutter_test.dart';
import 'package:planner/data/models.dart';
import 'package:planner/util/dates.dart';

void main() {
  group('dates', () {
    test('dateKey round-trips and sorts chronologically', () {
      final d = DateTime(2026, 3, 9);
      expect(dateKey(d), '2026-03-09');
      expect(parseDateKey('2026-03-09'), d);
      expect('2026-03-09'.compareTo('2026-11-01') < 0, isTrue);
    });

    test('period boundaries', () {
      final d = DateTime(2026, 11, 18); // Wednesday
      expect(startOfWeek(d), DateTime(2026, 11, 16));
      expect(endOfWeek(d), DateTime(2026, 11, 22));
      expect(endOfMonth(DateTime(2028, 2, 3)), DateTime(2028, 2, 29));
      expect(endOfQuarter(d), DateTime(2026, 12, 31));
      expect(startOfQuarter(DateTime(2026, 5, 20)), DateTime(2026, 4, 1));
    });

    test('formatClock in 24h and 12h', () {
      expect(formatClock(0, use24h: true), '00:00');
      expect(formatClock(1440, use24h: true), '24:00');
      expect(formatClock(13 * 60 + 5, use24h: false), '1:05 PM');
      expect(formatClock(0, use24h: false), '12 AM');
      expect(formatClock(12 * 60, use24h: false), '12 PM');
    });

    test('formatDuration', () {
      expect(formatDuration(45), '45m');
      expect(formatDuration(120), '2h');
      expect(formatDuration(95), '1h 35m');
    });
  });

  group('Goal', () {
    test('progress follows milestones', () {
      const g = Goal(
        id: 'g',
        title: 'Ship it',
        horizon: Horizon.quarter,
        color: 0,
        createdAt: 0,
        milestones: [
          Milestone(id: 'a', title: 'a', done: true),
          Milestone(id: 'b', title: 'b'),
        ],
      );
      expect(g.progress, 0.5);
      expect(g.nextMilestone?.id, 'b');
      expect(g.copyWith(completed: true).progress, 1);
    });

    test('JSON round-trip', () {
      const g = Goal(
        id: 'g',
        title: 'Run 10K',
        description: 'Health',
        horizon: Horizon.year,
        dueDate: '2026-12-31',
        color: 123,
        createdAt: 42,
        milestones: [Milestone(id: 'm', title: '5K', done: true)],
      );
      final back = Goal.fromJson(g.toJson());
      expect(back.title, 'Run 10K');
      expect(back.horizon, Horizon.year);
      expect(back.dueDate, '2026-12-31');
      expect(back.milestones.single.done, isTrue);
    });
  });

  group('Habit', () {
    Habit habit(Set<String> done, {List<int> weekdays = const []}) => Habit(
      id: 'h',
      name: 'Read',
      color: 0,
      createdOn: '2026-11-01',
      weekdays: weekdays,
      doneDates: done,
    );

    final now = DateTime(2026, 11, 18); // Wednesday

    test('streak counts back from today, or yesterday if today is open', () {
      expect(habit({'2026-11-16', '2026-11-17', '2026-11-18'}).currentStreak(now), 3);
      expect(habit({'2026-11-16', '2026-11-17'}).currentStreak(now), 2);
      expect(habit({'2026-11-15', '2026-11-17'}).currentStreak(now), 1);
    });

    test('unscheduled days do not break a streak', () {
      // Weekdays only: Fri 13th, Mon 16th, Tue 17th; the weekend is skipped.
      final h = habit({'2026-11-13', '2026-11-16', '2026-11-17'}, weekdays: [1, 2, 3, 4, 5]);
      expect(h.currentStreak(now), 3);
    });

    test('best streak and completion rate', () {
      final h = habit({'2026-11-02', '2026-11-03', '2026-11-04', '2026-11-10'});
      expect(h.bestStreak(now), 3);
      // 17 days since Nov 1 excluding open today, 4 done.
      expect(h.completionRate(now), closeTo(4 / 17, 1e-9));
    });
  });

  test('TimeBlock JSON clamps bad values', () {
    final b = TimeBlock.fromJson({
      'id': 'x',
      'date': '2026-11-18',
      'start': -20,
      'end': 5000,
      'title': 't',
    });
    expect(b.start, 0);
    expect(b.end, 1440);
  });
}
