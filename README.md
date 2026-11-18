# Planner

**Live: https://benhidangiu1408.github.io/planner/** (each push to `main` is deployed by GitHub Actions to GitHub Pages)

A local-first planning web app built with Flutter. It covers planning at every range, from the next hour to the next few years:

| View | Horizon | What it does |
|---|---|---|
| **Day** | hours | Time-blocked timeline: click a slot to add a block, drag to move it, drag the bottom edge to resize (15-minute snapping), and drop a task on it to schedule it. Also the day's tasks (★ priorities, roll over unfinished ones), habit check-ins, and notes with reflection prompts. |
| **Week** | 7 days | Seven timelines side by side. Drag blocks between days, drag tasks between day trays or onto a timeline. On phones it's a list per day; long-press a task to move it. |
| **Month** | weeks | Calendar grid with blocks, task completion and goal deadlines per day, plus monthly totals. |
| **Goals** | week → years | Goals by horizon (week, month, quarter, year, long term) with deadlines and milestones. Link goals into a hierarchy (a month goal is *part of* a quarter goal); progress rolls up. A board view and a tree view. |
| **Habits** | daily | Habits on chosen weekdays, with streaks, a 30-day rate and a heatmap. |
| **Review** | week | Planned vs focused time by goal and by day, habits, the week's focus goals, reflection, and planning for next week (focus goals, intention, move unfinished tasks). |
| **Settings** | | Theme, accent color (pink with blue by default), clock format, timeline hours, routines, reminders, focus length, storage, sync file and backups. |

Also:

- **Routines**: any block can repeat (every day, weekdays or chosen days). Changing one day only changes that day; "Edit routine" changes all of them.
- **Focus timer**: start it from a block (▶ on the tile or "Focus" in the editor) or from the timeline menu. Pause and resume, then finish to log the time. Blocks and goals show focused time next to planned time.
- **Reminders**: browser notifications a chosen number of minutes before each block starts, plus an in-app message. These only work while the app is open in a tab.

## Storage

Data is saved after every change as one JSON document in the browser's **IndexedDB** (much larger than localStorage's ~5 MB). Data from older versions is moved over from localStorage automatically. Settings → Storage shows usage, and can ask the browser to protect the data from automatic cleanup.

**Sync file** (Chrome or Edge on a computer): Settings → Storage & sync → *Create sync file…* keeps a live JSON copy outside the browser. Put it in a OneDrive, Dropbox or Google Drive folder to use the same planner on several computers. On the other computer, choose *Use existing file…*. When the file has newer changes (saved elsewhere), a banner asks whether to load them or keep the browser's data. After a browser restart, Chrome asks you to *Reconnect* once, which grants file access again.

**Backups**: Settings → Export backup downloads everything as JSON. You can restore it from a file or by pasting the text.

Data belongs to one browser and one origin (host + port). Nothing is sent anywhere.

## Run

```sh
flutter pub get

# Development. Keep the port fixed: a different port is a different origin,
# which means different (empty) storage.
flutter run -d chrome --web-port 5050

# Production build -> build/web (any static host works)
flutter build web --release
```

Tests: `flutter test` (models, store, routines, sub-goals, focus timer, sync conflicts, and every screen at phone, laptop and desktop sizes).

`tool/web_selftest.dart` checks the browser-only storage code (IndexedDB, storing file handles, sync-file writes) in a real browser:
`flutter build web -t tool/web_selftest.dart -o build/selftest`, serve that folder, open it, and read the console.

## Code map

```
lib/
  main.dart, app.dart        startup, theme
  shell.dart                 navigation (rail / bottom bar + "More"), status banner, focus bar, reminders
  data/models.dart           TimeBlock, Routine, Task, Goal/Milestone, Habit, FocusSession, ActiveFocus, WeekPlan, settings
  data/planner_store.dart    all state + logic (routine occurrences, rollups, timer, sync), queued saving
  data/storage.dart          storage interface (+ localStorage fallback)
  platform/                  web: IndexedDB, files, notifications, sync file; stubs elsewhere
  screens/                   day/, week, calendar (month), goals/, habits, review, settings
  widgets/                   block tile, editors, routines, pickers, focus bar, reminders, week focus, task dragging
```
