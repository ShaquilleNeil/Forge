import 'package:flutter/material.dart';

/// Forge theme — BLACK AND ORANGE (Forge only; Rank keeps black/blue).
/// Scaffold #0A0A0A, surface #121212, card #1A1A1A, raised #242424,
/// accent orange #FF6B00 — one solid fill per screen, the main action only;
/// secondary is neutral grey so built-in widgets don't turn orange,
/// success green #2FBF71, destructive red #EF4444, warning amber #FFB020.
///
/// Color roles:
///   orange = action, amber = check/warning,
///   red = destructive/error only, green = done/success.
///
/// Type scale (dp): 12, 14, 16, 18, 22, 28 — plus 44 for the splash
/// wordmark only. No other sizes exist in the app.
/// Spacing: 8-pt grid (8/16/24/32). 16 inside cards, 24 between sections.
class ForgeTheme {
  static const Color scaffoldBg = Color(0xFF0A0A0A);
  static const Color surface = Color(0xFF121212);
  static const Color card = Color(0xFF1A1A1A);
  static const Color raised = Color(0xFF242424);
  static const Color text = Color(0xFFF2F5F7);
  static const Color muted = Color(0xFF8A97A3);
  static const Color accent = Color(0xFFFF6B00);
  static const Color accentLight = Color(0xFFFF8C42);
  static const Color accentPressed = Color(0xFFE55F00);
  // accent at 15% opacity — tinted fills (badges, pills, nav indicator).
  static const Color accentTint = Color(0x26FF6B00);
  static const Color warning = Color(0xFFFFB020);
  static const Color green = Color(0xFF2FBF71);
  static const Color red = Color(0xFFEF4444);
  // Per-lift colors — squat orange, bench blue, deadlift green. Used
  // in Progress charts, legends and PR tiles, and the Exercise
  // library category chips.
  static const Color liftSquat = Color(0xFFFF6B00);
  static const Color liftBench = Color(0xFF5B9BD5);
  static const Color liftDeadlift = Color(0xFF2FBF71);

  /// The chart/legend/tile color for a lift id, or [muted] for
  /// anything that is not a main lift.
  static Color liftColorFor(String exerciseId) {
    switch (exerciseId) {
      case 'squat':
        return liftSquat;
      case 'bench':
        return liftBench;
      case 'deadlift':
        return liftDeadlift;
      default:
        return muted;
    }
  }

  /// Sheet motion: 200ms easeOutCubic, per the design audit.
  static const AnimationStyle sheetAnimationStyle = AnimationStyle(
    duration: Duration(milliseconds: 200),
    curve: Curves.easeOutCubic,
    reverseDuration: Duration(milliseconds: 200),
    reverseCurve: Curves.easeOutCubic,
  );
  static const Color divider = Color(0xFF2A2A2A);

  // Radius tokens: sm 4 (bars), chip 8, 12 (cards, inputs, buttons,
  // SetRow, score tiles), sheet 16 (sheets, dialogs).
  static const double radiusSm = 4;
  static const double radiusChip = 8;
  static const double radius = 12;
  static const double radiusSheet = 16;

  // Spacing tokens (8-pt grid).
  static const double space8 = 8;
  static const double space16 = 16;
  static const double space24 = 24;
  static const double space32 = 32;

  /// Tabular numbers — Runner type-in, Progress score tiles.
  static const TextStyle numeric = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.bold,
    color: text,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// Runner current-set weight.
  static const TextStyle hero = TextStyle(
    fontSize: 40,
    fontWeight: FontWeight.bold,
    color: text,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// Section headers (Profile, Settings, Progress). Always uppercase.
  static const TextStyle sectionLabel = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w700,
    color: muted,
    letterSpacing: 1.0,
  );

  /// The standard muted body text — replaces inline
  /// TextStyle(color: ForgeTheme.muted) everywhere.
  static const TextStyle bodyMuted = TextStyle(
    fontSize: 14,
    color: muted,
  );

  /// Muted caption text (12) — chart axis labels, stat labels,
  /// day-of-week letters. Replaces inline muted 11/12 styles.
  static const TextStyle captionMuted = TextStyle(
    fontSize: 12,
    color: muted,
  );

  // TextTheme slots as static consts, so screens can use them directly
  // (ForgeTheme.titleMedium) instead of inline TextStyles. The
  // ThemeData textTheme below references these same constants.
  static const TextStyle headlineLarge = TextStyle(
      fontSize: 28, fontWeight: FontWeight.bold, color: text);
  static const TextStyle headlineMedium = TextStyle(
      fontSize: 22, fontWeight: FontWeight.bold, color: text);
  static const TextStyle titleLarge = TextStyle(
      fontSize: 18, fontWeight: FontWeight.w600, color: text);
  static const TextStyle titleMedium = TextStyle(
      fontSize: 16, fontWeight: FontWeight.w600, color: text);
  static const TextStyle bodyLarge = TextStyle(fontSize: 16, color: text);
  static const TextStyle bodyMedium = TextStyle(fontSize: 14, color: text);
  static const TextStyle bodySmall = TextStyle(fontSize: 12, color: muted);
  static const TextStyle labelLarge = TextStyle(
      fontSize: 16, fontWeight: FontWeight.w600, color: text);
  static const TextStyle labelSmall = TextStyle(
      fontSize: 12, fontWeight: FontWeight.w600, color: text);

  // Named variants of the slots above, for the styles that recur
  // verbatim. All const, so they work inside const widgets.
  /// 18/w700 — dialog-style headings ("Show this to your coach").
  static const TextStyle titleLargeBold = TextStyle(
      fontSize: 18, fontWeight: FontWeight.w700, color: text);
  /// 16/w700 — client/coach names.
  static const TextStyle titleMediumBold = TextStyle(
      fontSize: 16, fontWeight: FontWeight.w700, color: text);
  /// 16/w600/tabular — tabular numbers at title size.
  static const TextStyle titleMediumTabular = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: text,
    fontFeatures: [FontFeature.tabularFigures()],
  );
  /// 14/w600 — stat values, tab row counts.
  static const TextStyle bodyMediumSemibold = TextStyle(
      fontSize: 14, fontWeight: FontWeight.w600, color: text);
  /// 14/w700 — stat values (client workout review, trim "Kept").
  static const TextStyle bodyMediumBold = TextStyle(
      fontSize: 14, fontWeight: FontWeight.w700, color: text);
  /// 12/w600/muted — set-row header labels.
  static const TextStyle captionSemibold = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: muted,
  );

  /// 12/accentLight — "in progress" style labels (see Phase 3).
  static const TextStyle captionAccentLight = TextStyle(
      fontSize: 12, color: accentLight);
  /// 12/bold/scaffoldBg — badge labels on an accent fill ("New").
  static const TextStyle captionOnAccent = TextStyle(
      fontSize: 12, fontWeight: FontWeight.bold, color: scaffoldBg);
  /// 14/red — error text.
  static const TextStyle errorText = TextStyle(fontSize: 14, color: red);
  /// 16/w600/red — destructive TextButton labels ("End workout").
  static const TextStyle destructiveLabel = TextStyle(
      fontSize: 16, fontWeight: FontWeight.w600, color: red);
  /// 18/bold/green — rest "Go" heading.
  static const TextStyle titleLargeSuccess = TextStyle(
      fontSize: 18, fontWeight: FontWeight.bold, color: green);
  /// 22/w800/letterSpacing 2 — pairing code display (FORGE-XXXXXX).
  static const TextStyle codeDisplay = TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.w800,
      color: text,
      letterSpacing: 2);
  /// 16/w800/scaffoldBg — avatar initial letters.
  static const TextStyle avatarInitial = TextStyle(
      fontSize: 16, fontWeight: FontWeight.w800, color: scaffoldBg);
  /// 22/w800/scaffoldBg — large avatar initial (client detail).
  static const TextStyle avatarInitialLarge = TextStyle(
      fontSize: 22, fontWeight: FontWeight.w800, color: scaffoldBg);
  /// 16/w700/tabular — rest countdown ("Rest 2:30").
  static const TextStyle titleMediumBoldTabular = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: text,
    fontFeatures: [FontFeature.tabularFigures()],
  );
  /// 16/w700/accent/tabular — rest countdown in the mini workout bar.
  static const TextStyle titleMediumAccentTabular = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: accent,
    fontFeatures: [FontFeature.tabularFigures()],
  );
  /// 14/bold/scaffoldBg — badge labels on an accent fill (superset badge).
  static const TextStyle badgeLabelOnAccent = TextStyle(
      fontSize: 14, fontWeight: FontWeight.bold, color: scaffoldBg);
  /// 14/bold/accent — badge labels on an accentTint fill (superset badge).
  static const TextStyle badgeLabelAccent = TextStyle(
      fontSize: 14, fontWeight: FontWeight.bold, color: accent);
  /// 16/w600/warning — numbers over target (RPE over target).
  static const TextStyle titleMediumWarning = TextStyle(
      fontSize: 16, fontWeight: FontWeight.w600, color: warning);
  /// 14/warning — warning copy (write-back failed).
  static const TextStyle warningText = TextStyle(fontSize: 14, color: warning);
  /// 16/w600/scaffoldBg — values on an accent fill (Total PR tile).
  static const TextStyle labelOnAccent = TextStyle(
      fontSize: 16, fontWeight: FontWeight.w600, color: scaffoldBg);
  /// 12/w700/accent — small accent markers ("ACTIVE").
  static const TextStyle captionAccent = TextStyle(
      fontSize: 12, fontWeight: FontWeight.w700, color: accent);

  /// Section header widget: uppercase label in sectionLabel style.
  static Text sectionHeader(String label) =>
      Text(label.toUpperCase(), style: sectionLabel);

  static ThemeData get dark => ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: scaffoldBg,
        colorScheme: const ColorScheme.dark(
          primary: accent,
          onPrimary: scaffoldBg,
          // Neutral grey on purpose: secondary/secondaryContainer were
          // orange, which made built-in widgets (SegmentedButton,
          // switches) orange by default. Orange stays an explicit choice.
          secondary: muted,
          secondaryContainer: card,
          onSecondaryContainer: text,
          surface: surface,
          error: red,
        ),
        chipTheme: const ChipThemeData(
          selectedColor: accent,
          secondarySelectedColor: accent,
          secondaryLabelStyle: TextStyle(color: scaffoldBg),
          side: BorderSide(color: divider),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: scaffoldBg,
          foregroundColor: text,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          color: card,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
          ),
        ),
        textTheme: const TextTheme(
          headlineLarge: headlineLarge,
          headlineMedium: headlineMedium,
          titleLarge: titleLarge,
          titleMedium: titleMedium,
          bodyLarge: bodyLarge,
          bodyMedium: bodyMedium,
          bodySmall: bodySmall,
          labelLarge: labelLarge,
          labelSmall: labelSmall,
        ),
        // ListTile titles/subtitles get explicit styles (no framework
        // defaults): titles titleMedium, subtitles muted 14.
        listTileTheme: const ListTileThemeData(
          titleTextStyle: titleMedium,
          subtitleTextStyle: bodyMuted,
        ),
        checkboxTheme: CheckboxThemeData(
          fillColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected) ? accent : null),
          checkColor: const WidgetStatePropertyAll(scaffoldBg),
          side: const BorderSide(color: divider, width: 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSm),
          ),
        ),
        // NEVER use an infinite minimum width here. DyadeSpace was bitten
        // twice by Size.fromHeight(52) (infinite width) on FilledButton /
        // OutlinedButton themes: blank sheets and broken top bars.
        // Finite Size(0, 52): full height, zero minimum width.
        // White on orange is 2.86:1 (fails WCAG even for large text);
        // near-black on orange is 6.93:1. Every filled button and the
        // FAB keep their orange fill and read in dark text.
        // Pressed state: the fill deepens to accentPressed.
        filledButtonTheme: FilledButtonThemeData(
          style: ButtonStyle(
            backgroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.pressed)
                  ? accentPressed
                  : accent,
            ),
            foregroundColor:
                const WidgetStatePropertyAll(scaffoldBg),
            minimumSize: const WidgetStatePropertyAll(Size(0, 52)),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(radius),
              ),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: accent,
            side: const BorderSide(color: accent),
            minimumSize: const Size(0, 52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: accent,
            minimumSize: const Size(48, 48),
          ),
        ),
        // Dialogs: raised bg, 16 radius, titleLarge title, bodyMedium
        // content — no more unthemed framework defaults.
        dialogTheme: DialogThemeData(
          backgroundColor: raised,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSheet),
          ),
          titleTextStyle: titleLarge,
          contentTextStyle: bodyMedium,
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: raised,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(radiusSheet),
              topRight: Radius.circular(radiusSheet),
            ),
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: raised,
          contentTextStyle: bodyMedium,
          actionTextColor: accent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
          ),
        ),
        // Segmented buttons: 48 tall. Selected = accentTint fill +
        // accent border + accent label; unselected = transparent +
        // divider border + muted label.
        segmentedButtonTheme: SegmentedButtonThemeData(
          style: ButtonStyle(
            minimumSize: const WidgetStatePropertyAll(Size(0, 48)),
            backgroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? accentTint
                  : Colors.transparent,
            ),
            foregroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? accent
                  : muted,
            ),
            side: WidgetStateProperty.resolveWith(
              (states) => BorderSide(
                color: states.contains(WidgetState.selected)
                    ? accent
                    : divider,
              ),
            ),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(radiusChip),
              ),
            ),
          ),
        ),
        // Switches: on = accent track, off = divider track + muted thumb.
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? scaffoldBg
                : muted,
          ),
          trackColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? accent
                : divider,
          ),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: accent,
          foregroundColor: scaffoldBg,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: surface,
          elevation: 0,
          indicatorColor: accentTint,
          iconTheme: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return IconThemeData(color: selected ? accent : muted);
          }),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
              color: selected ? accent : muted,
            );
          }),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: card,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: divider),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: divider),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: accent),
          ),
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: accent,
        ),
        dividerColor: divider,
      );
}
