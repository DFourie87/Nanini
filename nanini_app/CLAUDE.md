# Nanini app -- styling rule

Every screen in this app must use the shared look defined in
`lib/theme/nanini_theme.dart` (`NaniniTheme.light`, `NaniniColors`) --
never hardcode colors, fonts, or one-off button/card styles that diverge
from it. This applies to every module (Diesel, Tuck Shop, Hours, Packaging,
Sales, Employee List, Truck, Game Breeding, and any new app added later).

In practice:
- Screens: `Scaffold` with `NaniniAppBar` (from `core/widgets/nanini_app_bar.dart`).
- Multi-tab apps: `BottomNavigationBar` (picks up rust-dark selected color
  from `bottomNavigationBarTheme` automatically -- no per-screen color
  overrides needed), or a `SegmentedButton` with
  `selectedBackgroundColor: NaniniColors.rust, selectedForegroundColor: Colors.white`
  when the picker sits at the top of a tab instead of in the nav bar.
  Both patterns are used across the app -- match whichever the existing
  screen already uses; don't invent a third.
- Buttons: `FilledButton`/`ElevatedButton` (already themed rust via
  `colorScheme.primary` / `elevatedButtonTheme`), `OutlinedButton` for
  secondary actions.
- Text: use `Theme.of(context).textTheme.*` for headings (Oswald) and let
  body text inherit the default (Inter) -- don't set a custom
  `fontFamily`.
- Colors: only `NaniniColors.*` (rust, rustDark, muted, line, green, amber,
  red, disabledBg, ink, paper) -- never raw `Colors.grey`/`Colors.black`/etc.
  for anything that should track the brand palette.
- Cards/inputs: rely on the global `cardTheme`/`inputDecorationTheme`
  rather than custom decorations.

When building a new app or screen, check how an existing one (e.g.
`lib/features/delivery/`, `lib/features/sales/`) solves the same kind of
layout before inventing a new pattern.
