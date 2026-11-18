import 'package:material_ui/material_ui.dart';

import 'data/planner_scope.dart';
import 'screens/calendar_screen.dart';
import 'screens/day/day_screen.dart';
import 'screens/goals/goals_screen.dart';
import 'screens/habits_screen.dart';
import 'screens/review_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/week_screen.dart';
import 'widgets/focus_bar.dart';
import 'widgets/reminders.dart';
import 'widgets/status_banner.dart';

typedef _Destination = ({IconData icon, IconData selected, String label});

const _destinations = <_Destination>[
  (icon: Icons.view_day_outlined, selected: Icons.view_day, label: 'Day'),
  (icon: Icons.view_week_outlined, selected: Icons.view_week, label: 'Week'),
  (icon: Icons.calendar_month_outlined, selected: Icons.calendar_month, label: 'Month'),
  (icon: Icons.flag_outlined, selected: Icons.flag, label: 'Goals'),
  (icon: Icons.repeat, selected: Icons.repeat_on, label: 'Habits'),
  (icon: Icons.insights_outlined, selected: Icons.insights, label: 'Review'),
  (icon: Icons.settings_outlined, selected: Icons.settings, label: 'Settings'),
];

/// On phones the first four destinations get tabs; the rest live under "More".
const _phoneTabs = 4;
const _settingsIndex = 6;

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  void _go(int index) => setState(() => _index = index);

  void _openDay(DateTime date) {
    PlannerScope.read(context).selectDate(date);
    _go(0);
  }

  Future<void> _showMore() async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = _phoneTabs; i < _destinations.length; i++)
              ListTile(
                leading: Icon(i == _index ? _destinations[i].selected : _destinations[i].icon),
                title: Text(_destinations[i].label),
                selected: i == _index,
                onTap: () => Navigator.pop(context, i),
              ),
          ],
        ),
      ),
    );
    if (picked != null) _go(picked);
  }

  @override
  Widget build(BuildContext context) {
    final pages = IndexedStack(
      index: _index,
      children: [
        const DayScreen(),
        WeekScreen(onOpenDay: _openDay),
        CalendarScreen(onOpenDay: _openDay),
        const GoalsScreen(),
        const HabitsScreen(),
        const ReviewScreen(),
        const SettingsScreen(),
      ],
    );
    final content = Column(
      children: [
        StatusBanner(onOpenSettings: () => _go(_settingsIndex)),
        Expanded(child: pages),
        const FocusBar(),
      ],
    );

    return ReminderWatcher(
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 840) {
            final extended = constraints.maxWidth >= 1360;
            return Scaffold(
              body: SafeArea(
                child: Row(
                  children: [
                    SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: constraints.maxHeight),
                        child: IntrinsicHeight(
                          child: NavigationRail(
                            extended: extended,
                            minExtendedWidth: 200,
                            labelType: extended
                                ? NavigationRailLabelType.none
                                : NavigationRailLabelType.all,
                            selectedIndex: _index,
                            onDestinationSelected: _go,
                            leading: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: _Logo(showName: extended),
                            ),
                            destinations: [
                              for (final d in _destinations)
                                NavigationRailDestination(
                                  icon: Icon(d.icon),
                                  selectedIcon: Icon(d.selected),
                                  label: Text(d.label),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: content),
                  ],
                ),
              ),
            );
          }
          return Scaffold(
            body: SafeArea(bottom: false, child: content),
            bottomNavigationBar: NavigationBar(
              selectedIndex: _index < _phoneTabs ? _index : _phoneTabs,
              onDestinationSelected: (i) => i == _phoneTabs ? _showMore() : _go(i),
              labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
              destinations: [
                for (final d in _destinations.take(_phoneTabs))
                  NavigationDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selected),
                    label: d.label,
                  ),
                NavigationDestination(
                  icon: const Icon(Icons.more_horiz),
                  label: _index < _phoneTabs ? 'More' : _destinations[_index].label,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo({required this.showName});

  final bool showName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [scheme.primary, scheme.secondary],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.event_note, color: scheme.onPrimary),
        ),
        if (showName) ...[
          const SizedBox(width: 12),
          Text('Planner', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        ],
      ],
    );
  }
}
