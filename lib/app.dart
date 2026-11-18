import 'package:material_ui/material_ui.dart';

import 'data/models.dart';
import 'data/planner_scope.dart';
import 'data/planner_store.dart';
import 'shell.dart';
import 'util/palette.dart';

class PlannerApp extends StatelessWidget {
  const PlannerApp({super.key, required this.store});

  final PlannerStore store;

  @override
  Widget build(BuildContext context) {
    return PlannerScope(
      store: store,
      child: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final s = store.settings;
          return MaterialApp(
            title: 'Planner',
            debugShowCheckedModeBanner: false,
            themeMode: switch (s.theme) {
              ThemePreference.system => ThemeMode.system,
              ThemePreference.light => ThemeMode.light,
              ThemePreference.dark => ThemeMode.dark,
            },
            theme: AppTheme.of(Brightness.light, s.seedColor),
            darkTheme: AppTheme.of(Brightness.dark, s.seedColor),
            home: const HomeShell(),
          );
        },
      ),
    );
  }
}

abstract final class AppTheme {
  static final _cache = <(Brightness, int), ThemeData>{};

  static ThemeData of(Brightness brightness, int seed) =>
      _cache.putIfAbsent((brightness, seed), () => _build(brightness, schemeFor(brightness, seed)));

  /// One hue for most accents; for a paired accent (pink & blue) the
  /// partner hue supplies the secondary and tertiary colors.
  static ColorScheme schemeFor(Brightness brightness, int seed) {
    final partner = accentPartners[seed];
    if (partner == null) {
      return ColorScheme.fromSeed(seedColor: Color(seed), brightness: brightness);
    }
    final main = ColorScheme.fromSeed(
      seedColor: Color(seed),
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.vibrant,
    );
    final other = ColorScheme.fromSeed(
      seedColor: Color(partner),
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.vibrant,
    );
    return main.copyWith(
      secondary: other.primary,
      onSecondary: other.onPrimary,
      secondaryContainer: other.primaryContainer,
      onSecondaryContainer: other.onPrimaryContainer,
      tertiary: other.secondary,
      onTertiary: other.onSecondary,
      tertiaryContainer: other.secondaryContainer,
      onTertiaryContainer: other.onSecondaryContainer,
    );
  }

  static ThemeData _build(Brightness brightness, ColorScheme scheme) {
    final light = brightness == Brightness.light;
    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: light ? scheme.surfaceContainerLow : scheme.surface,
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: light ? scheme.surface : scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
        ),
      ),
      inputDecorationTheme: const InputDecorationThemeData(
        border: OutlineInputBorder(),
        isDense: true,
      ),
      dialogTheme: const DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(20))),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: light ? scheme.surfaceContainerLow : scheme.surface,
      ),
      tooltipTheme: const TooltipThemeData(waitDuration: Duration(milliseconds: 500)),
    );
  }
}
