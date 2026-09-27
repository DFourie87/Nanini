# Nanini Boerdery — Workspace

This folder contains the software for **Nanini Boerdery**, a farming operation (Farm Limpopodraai, Farm Haaskraal, Farm Doornbult in Limpopo, South Africa).

| Folder | What it is |
|---|---|
| [`nanini_app/`](nanini_app/) | The Flutter app. It builds two Android apps: **Nanini Boerdery** (the hub, for the owner and managers) and **Nanini Capture** (offline, step-by-step capturing for workers' phones -- entries wait for approval in the hub). |
| [`scripts/`](scripts/) | Office-PC scripts: sales-report PDF importer and the daily diesel price forecast fetch. |

The original web app (`Nanini App/`) was retired when the database was locked down; it remains in the git history.

Both apps use one **Supabase project** (Postgres + realtime).

- Supabase project URL: `https://nwyizwccmyanbdjmmdds.supabase.co`
- The publishable (anon) key built into the apps opens nothing by itself: every table requires a logged-in, active Nanini user (Supabase Auth, username + 6-digit PIN), and Nanini Capture phones only get a few locked-down functions once an admin approves them. See `nanini_app/docs/sql/lockdown_1_accounts.sql` and `lockdown_2_policies.sql`.

## The 7 modules

| Module | Emoji | Purpose |
|---|---|---|
| Diesel | ⛽ | Tank levels, fuel purchases/usage logging, SARS diesel-refund (VAT) reporting |
| Tuck Shop | 🛒 | On-site shop stock (FIFO costing), employee purchases on account, monthly profit reports |
| Employees (Hours) | 🕒 | Clock hours / kg-picked logging, PAYE & UIF payroll calc, payslip PDFs |
| Packaging (Delivery) | 📦 | Truck loading (pallets/boxes/bags), delivery notes (PDF), market-agent pallet balances |
| Sales | 📊 | Market-agent settlement reports (potatoes/peppers/tobacco/butternut), revenue summaries |
| Employee List | 🧑‍🌾 | Master employee & group register (source of truth other modules read from) |
| Truck | 🚚 | Shared single-truck booking calendar with map pin + live GPS tracking link |

See [`nanini_app/docs/MODULES.md`](nanini_app/docs/MODULES.md) for the full functional spec of each module (data fields, calculations, Supabase tables) used to build the Flutter app, and [`nanini_app/docs/ARCHITECTURE.md`](nanini_app/docs/ARCHITECTURE.md) for how the Flutter app is put together.

## Brand identity (shared by both apps)

- Colors: ink `#000000`, paper `#FFFFFF`, rust/red `#EC1F24` (accent) / `#C41A1E` (dark accent), line `#E4D6C3`, muted text `#4A4A4A`.
- Fonts: **Oswald** (headings/labels), **Inter** (body).
- Logo: `nanini_app/assets/images/hub-logo.jpg`.
