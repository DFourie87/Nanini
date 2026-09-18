# Nanini Boerdery — Workspace

This folder contains the software for **Nanini Boerdery**, a farming operation (Farm Limpopodraai, Farm Haaskraal, Farm Doornbult in Limpopo, South Africa). There are two clients sharing one backend:

| Folder | What it is |
|---|---|
| [`Nanini App/`](Nanini%20App/) | The original web app (PWA) — a hub page linking to 7 standalone HTML/JS tools, installable on a phone via "Add to Home Screen". |
| [`nanini_app/`](nanini_app/) | A native Flutter app that replicates the same 7 modules, for a proper installable mobile app experience (offline-friendlier, faster, app-store-deployable). |

Both clients talk to the **same Supabase project** (Postgres + realtime + storage), so data entered in one shows up instantly in the other — e.g. add an employee on the web hub and it appears immediately in the Flutter app's picker lists.

- Supabase project URL: `https://nwyizwccmyanbdjmmdds.supabase.co`
- Publishable (anon) key is embedded client-side in both apps (protected by Postgres Row Level Security, not secrecy).

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
- Logo: `Nanini App/hub-logo.jpg`.
