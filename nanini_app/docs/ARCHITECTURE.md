# Flutter app architecture

## Stack

- **Flutter** (stable channel), Dart, Material 3.
- **Backend:** `supabase_flutter` — connects to the same Supabase project as the web app (`https://nwyizwccmyanbdjmmdds.supabase.co`), using its publishable (anon) key. Row Level Security on the Postgres side is what actually protects the data, not the key's secrecy.
- **State management:** deliberately no external state-management package. Each screen owns a `Stream` from Supabase's realtime `.stream()` API (or a manual fetch + `postgres_changes` subscription) and rebuilds via `StreamBuilder`/`setState`. Kept simple because the app is a set of largely-independent CRUD modules, not one big shared state tree.
- **Local persistence:** `shared_preferences` only, for the single app-wide manager-mode password hash and small UI prefs (last-selected farm/tank/tab). All business data lives in Supabase — there is no offline-first/local-database layer in this version (see "Not implemented / deviations" below).
- **Fonts:** `google_fonts` package loading Oswald (headings) + Inter (body) to match the web app exactly.
- **PDF generation** (delivery notes, payslips): `pdf` + `printing` packages.
- **CSV:** `csv` package for import (Hours kg-picking) and export.
- **Charts:** `fl_chart` for the Delivery "Fields" pie chart.
- **Maps:** `flutter_map` (OpenStreetMap tiles, no API key needed) + `latlong2` for the Truck booking pin picker — a drop-in equivalent of the web app's Leaflet map.
- **Images:** `image_picker` for diesel delivery-slip/invoice photos.

## Project layout

```
lib/
  main.dart                     — app entry, Supabase.initialize(), runApp
  app.dart                      — MaterialApp, theme, routes
  theme/
    nanini_theme.dart           — colors, text styles, ThemeData matching the web app's CSS variables
  core/
    supabase_client.dart        — the shared SupabaseClient instance + small query helpers
    formatters.dart             — fmtR() (Rand currency), fmtL() (litres), date formatting
    manager_mode.dart           — app-wide manager-mode state (ChangeNotifier) + shared_preferences hash check
    widgets/
      nanini_scaffold.dart      — shared page chrome (header w/ logo, bottom nav)
      tile_button.dart          — the hub's grid tiles
      confirm_dialog.dart, input_dialog.dart, toast.dart
  features/
    hub/            — home screen with the 7 module tiles
    diesel/
    tuckshop/
    hours/
    employees/
    delivery/
    sales/
    truck/
      <module>_models.dart      — typed row classes (fromJson/toJson) for that module's tables
      <module>_repository.dart  — Supabase queries + realtime stream for that module
      <module>_screen.dart (+ subscreens as needed)
```

Each feature folder is self-contained: models + repository + screens. `core/` holds only truly cross-cutting code.

## Navigation

A simple `Navigator` with named routes, one per module's entry screen, pushed from the hub grid — mirroring the original app's hub-and-spoke structure (no bottom-tab-bar-for-everything; each module keeps its own internal bottom nav for its own views, same as the web version).

## Login gateway (bigger deviation from the web app)

The web app has no login at all — it's open to anyone with the URL/APK, with a single shared "Manager" password (per module) gating edit actions. The Flutter app replaces that entirely with **individual accounts**: every person gets their own username + PIN, created by an admin, and the whole app is gated behind sign-in (see `features/auth/login_screen.dart`).

- **Backend**: a new `app_users` table in the same Supabase project, plus a handful of Postgres `SECURITY DEFINER` functions (`login`, `create_app_user`, `list_app_users`, `set_app_user_active`, `change_own_pin`) that do PIN hashing/verification server-side using `pgcrypto` (bcrypt). The table itself has RLS enabled with **no policies**, so the app's publishable key can never read PIN hashes directly — every operation goes through those functions. One-time setup SQL: `docs/sql/app_users_auth.sql` (run once in the Supabase SQL editor; seeds a starting `admin`/`1234` account — change that PIN immediately after first login).
- **Client**: `core/auth/session.dart` (`Session`, a `ChangeNotifier`) holds the logged-in `AppUser` and persists *who's* logged in across restarts via `shared_preferences` — but never the PIN itself. `core/auth/admin_gate.dart`'s `requireAdmin(context)` is the direct replacement for the old `requireManager(context)`: a `staff` account is simply denied (there's no password that promotes them — an admin has to change their role), while an `admin` is asked to confirm their PIN once per app run and it's cached in memory afterwards (matches the old manager-mode UX of "unlock once per session").
- **Roles**: `admin` (everything a "manager" could do before — add/edit/delete master data, reports, settings, plus managing other users) and `staff` (browse + log entries, same as a non-manager before).
- Every module's old `ManagerMode`/`requireManager` call sites were mechanically swapped to `Session`/`requireAdmin` — the gating *points* in each module (which buttons/tabs are admin-only) didn't change, only who's allowed through them.

## Not implemented / intentional deviations in v1

A few features from the web app were simplified or deferred — noted here so they're not mistaken for oversights:

1. **Sales PDF auto-parsing.** The web app extracts line items from uploaded market-agent PDF invoices using `pdf.js` with custom heuristics. The Flutter app's Sales module uses **manual entry** of the same fields instead (still saves to the same `sales_reports`/`sales_line_items` tables, so data is compatible either way). Auto-parsing could be added later using `syncfusion_flutter_pdf` or a server-side function.
2. **Excel export** (Sales/Hours "Download Excel"). v1 offers **CSV export** via the system share sheet instead (same data, no extra dependency). The `excel` package can be added later if a real `.xlsx` is required.
3. **Hours payslip PDFs.** The web app generates a full per-employee payslip PDF (company letterhead, deductions table). v1's Reports tab shows the same numbers (gross, PAYE, UIF, rent, loan, nett) in an expandable list and CSV export; the `pdf`/`printing` packages are already wired up for Diesel/Delivery so a payslip layout can reuse that pattern later.
4. **Hours tuck-shop deduction & CSV kg-import.** `HoursRepository.fetchShopSpend()` exists but isn't wired into the Reports screen yet (nett pay currently subtracts rent + loan, not shop spend). CSV import for kg-picking (matching a spreadsheet's name/kg columns) isn't implemented — kg is entered per employee in-app instead.
5. **Delivery active-truck persistence.** The web app keeps the in-progress truck in `localStorage` so it survives a refresh. v1 keeps it in memory only (lost if you navigate away/kill the app before "Finish Truck") — a `shared_preferences`-backed draft can be added the same way `ManagerMode` persists its password hash.
6. **Manager mode is app-wide**, not per-module — see above.

Everything else — realtime sync across every module, FIFO tuck shop costing, PAYE/UIF payroll math, diesel event-sourced tank levels, delivery-note PDFs, the truck booking map, SARS VAT period reporting — is implemented and backed by the live Supabase schema (verified against the real database, not guessed from source reading).
