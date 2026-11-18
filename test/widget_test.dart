import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:planner/app.dart';
import 'package:planner/data/models.dart';
import 'package:planner/data/planner_store.dart';
import 'package:planner/util/dates.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<PlannerStore> pumpApp(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = (await tester.runAsync(PlannerStore.load))!;
    // Some content so the screens have something to lay out.
    final key = dateKey(today());
    final goal = store.goals.first;
    store.saveRoutine(
      Routine(
        id: 'r',
        title: 'Morning run',
        start: 420,
        end: 450,
        color: 0xFF2BA36B,
        startDate: dateKey(addDays(today(), -7)),
      ),
    );
    store.saveBlock(
      TimeBlock(
        id: 'b',
        date: key,
        start: 600,
        end: 690,
        title: 'Deep work',
        color: 0xFF4F6BED,
        goalId: goal.id,
      ),
    );
    store.addTask('Call the bank', key);
    store.saveHabit(Habit(id: 'h', name: 'Read', color: 0xFF4F6BED, createdOn: key));
    store.saveWeekPlan(WeekPlan(weekStart: dateKey(startOfWeek(today())), focusGoalIds: [goal.id]));
    await tester.pumpWidget(PlannerApp(store: store));
    await tester.pumpAndSettle();
    return store;
  }

  test('pink & blue theme: pink primary, blue secondary, in both modes', () {
    for (final b in Brightness.values) {
      final scheme = AppTheme.schemeFor(b, 0xFFD9488F);
      final primaryHue = HSLColor.fromColor(scheme.primary).hue;
      final secondaryHue = HSLColor.fromColor(scheme.secondary).hue;
      expect(primaryHue, inInclusiveRange(310, 350), reason: '$b primary is pink');
      expect(secondaryHue, inInclusiveRange(200, 240), reason: '$b secondary is blue');
    }
  });

  const wideTabs = ['Week', 'Month', 'Goals', 'Habits', 'Review', 'Settings', 'Day'];

  testWidgets('desktop: add a task from the day view', (tester) async {
    final store = await pumpApp(tester, const Size(1440, 900));

    expect(find.text('Schedule'), findsOneWidget);
    expect(find.text('Morning run'), findsWidgets);

    await tester.enterText(find.widgetWithText(TextField, 'Add a task…'), 'Write report');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(store.tasksOn(dateKey(today())).map((t) => t.title), contains('Write report'));
  });

  testWidgets('desktop: new repeating block becomes a routine', (tester) async {
    final store = await pumpApp(tester, const Size(1440, 900));

    await tester.tap(find.text('Block'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'What will you do?'), 'Standup');
    await tester.tap(find.text('Weekdays').first);
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(store.routines.map((r) => r.title), contains('Standup'));
  });

  testWidgets('focus bar appears and logs time', (tester) async {
    final store = await pumpApp(tester, const Size(1440, 900));
    store.startFocus(block: store.blocksOn(dateKey(today())).last);
    await tester.pump();
    expect(find.byTooltip('Finish and log time'), findsOneWidget);

    await tester.tap(find.byTooltip('Discard'));
    await tester.pump();
    expect(store.activeFocus, isNull);
    expect(find.byTooltip('Finish and log time'), findsNothing);
  });

  testWidgets('every page renders on a wide screen', (tester) async {
    await pumpApp(tester, const Size(1600, 1000));
    for (final label in wideTabs) {
      await tester.tap(find.text(label).first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'while showing $label');
    }
  });

  testWidgets('every page renders on a laptop screen', (tester) async {
    await pumpApp(tester, const Size(1000, 700));
    for (final label in wideTabs) {
      await tester.tap(find.text(label).first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'while showing $label');
    }
  });

  testWidgets('every page renders on a phone, including the More sheet', (tester) async {
    await pumpApp(tester, const Size(390, 844));
    for (final label in ['Week', 'Month', 'Goals', 'Day']) {
      await tester.tap(find.byIcon(_navIcon(label)).last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'while showing $label');
    }
    for (final label in ['Habits', 'Review', 'Settings']) {
      await tester.tap(find.byIcon(Icons.more_horiz));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, label));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'while showing $label');
    }
  });

  testWidgets('goals tree view shows sub-goals', (tester) async {
    final store = await pumpApp(tester, const Size(1440, 900));
    final parent = store.goals.first;
    store.saveGoal(
      Goal(
        id: 'sub',
        title: 'Sub goal',
        horizon: Horizon.week,
        color: 0,
        createdAt: 1,
        parentId: parent.id,
      ),
    );
    await tester.tap(find.text('Goals').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.account_tree_outlined).first);
    await tester.pumpAndSettle();
    expect(find.text('Sub goal'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

IconData _navIcon(String label) => switch (label) {
  'Day' => Icons.view_day_outlined,
  'Week' => Icons.view_week_outlined,
  'Month' => Icons.calendar_month_outlined,
  _ => Icons.flag_outlined,
};
