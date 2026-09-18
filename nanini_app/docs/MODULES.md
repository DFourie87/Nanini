# Module specifications

Distilled from the existing web app source (`Nanini App/<module>/index.html`) so the Flutter rebuild matches real behavior. All modules share one Supabase project (`nwyizwccmyanbdjmmdds`) and its Postgres tables, with realtime subscriptions keeping every connected device in sync.

---
## Diesel (⛽)

**Purpose:** Track diesel inventory across storage tanks — purchases (deliveries) and usage (dispensed to vehicles/equipment) — and produce a SARS diesel-refund (VAT) report.

**Tables:** `diesel_tanks`, `diesel_purchases`, `diesel_usage`, `diesel_vehicles`, `diesel_adjustments`, `diesel_activities`, `diesel_settings` (singleton, `refund_rate`). Reads shared `employees`.

**Key logic:**
- Tank level is event-sourced: replay `initialLevel` + all purchases (+) / usage (−) / adjustments (absolute reset) in chronological order, clamp ≥ 0. Never stored directly.
- Fill % coloring: green ≥35%, amber 15–35%, red <15%.
- VAT period defaults to bi-monthly ending on even months.
- Reports: Total In, Total Out, Eligible % (usage on eligible activities / total usage), Estimated Refund = eligible litres × refund rate (R/L, manager-set).
- Default activities (name / eligible / sort order): Ploughing-planting-cultivating-harvesting-baling (✓,10), Spraying and Fertilizing (✓,20), Livestock care/feeding (✓,30), Irrigation pumps and generators (✓,40), Firebreaks and firefighting (✓,50), Road and fence maintenance (✓,60), On-farm transport of products and inputs (✓,70), Transport of produce to market (✓,80), Personal use (✗,90).
- Purchase/usage entries attach optional photos (delivery slip, invoice — image/PDF).

**Fields:** Usage: tank, date, litres, equipment, employee, hour meter/odometer, activity, notes. Purchase: tank, date, litres, supplier, delivery note no., photo, notes, (+later) cost, invoice no., invoice file.

---
## Tuck Shop (🛒)

**Purpose:** On-site shop where employees buy snacks/drinks on account; manager tracks FIFO-costed stock and monthly profit, scoped per farm.

**Tables:** `tuckshop_items` (name, profit_pct, last_cost_price, farm_id), `tuckshop_batches` (item_id, cost_price, qty, batch_date, paid_by — FIFO batches), `tuckshop_purchases` (employee_id, item_id?, qty?, revenue, cogs, sale_date, note, farm_id), `tuckshop_writeoffs`, `tuckshop_stock_purchases`. Reads shared `employees`, `farms`.

**Key logic:**
- FIFO costing: each restock appends a batch; a sale/write-off consumes oldest batches first (`consumeFifo`).
- Sell price = round(oldest-batch cost × (1 + profit%/100)) to nearest Rand.
- Two farms behave differently: **Limpopodraai** = normal item/qty based logging; **Haaskraal** = no item tracking, manager logs a lump total amount per employee per period ("manual mode").
- Low stock threshold = 5 units. `DEFAULT_PROFIT_PCT = 35`.
- "Paid by" is always one of exactly: `"Nanini Boerdery"` or `"DF Fourie"`.
- Monthly report: total sales, FIFO profit (revenue − cogs), items sold, per-employee totals, stock purchases grouped by payer, write-offs.

---
## Hours (🕒, hub label "Employees")

**Purpose:** Log employee hours (individual/group/piece-work-by-kg), compute pay with SA PAYE/UIF, generate payslip PDFs.

**Tables:** `employees`, `employee_groups` (read-only here), `hours_entries`, `kg_entries`, `hours_settings` (singleton: `dailyThreshold` default 9, `otMultiplier` 1.5). Reads `tuckshop_purchases` (for shop-spend deduction).

**Key logic:**
- Gross pay = hours × rate (no overtime premium applied to gross; OT split is informational only).
- PAYE only applies if employee has an ID/passport number. SARS 2026/27 brackets: 18% to R245,100; 26% to R383,100; 31% to R530,200; 36% to R695,800; 39% to R887,000; 41% to R1,878,600; 45% above. Annual primary rebate R17,820. Annualize monthly gross ×12, apply bracket, subtract rebate, divide by 12.
- UIF = 1% of gross (only if ID present).
- Nett = gross − PAYE − UIF − rent_deduction − tuck-shop spend (this period) − loan_deduction.
- KG picking: rate (R/kg) × kg picked; supports CSV import matched by header regex (`name|employee|worker|picker`, `kg|weight|mass`).
- "Hours worked" summary view is open to everyone (no manager login needed); logging/editing/reports are manager-gated.

---
## Employee List (🧑‍🌾)

**Purpose:** Master employee & group register — the single place employee data is entered; Hours and Tuck Shop read from it.

**Tables:** `employees`, `employee_groups` (name, farm_id), `farms` (read-only in-app, seed-once).

**Employee fields:** first_name, last_name (required), id_or_passport (optional — required for PAYE/UIF to apply), rate_per_hour, current_group_id, rent_deduction, loan_deduction, payment_method (`bank`|`atm`|`cash`, default cash) driving conditional fields: bank → bank_name + bank_account_no; atm → phone_number + atm_access_code; cash → neither.

**Default farms (seed once if empty):** "Farm Limpopodraai - Stockpoort", "Farm Haaskraal - Swartwater", "Farm Doornbult - Polokwane". Limpopodraai always sorts first.

**Key logic:** deleting a group nulls out its members' `current_group_id` first, then deletes; deleting an employee just removes the row (history in other modules is kept, referencing a now-missing id — handle gracefully / show "Unknown").

---
## Delivery (📦, hub label "Packaging")

**Purpose:** Log truck-loading of produce (potato/pepper/butternut) from field to market, generate a numbered Delivery Note PDF, track pallet inventory (bought vs. delivered) per market agent.

**Tables:** `delivery_notes`, `delivery_pallet_purchases`, `delivery_market_agents`. `note_number` is server-assigned.

**Key logic — potato sizes** (key / label / grade), each with bags-per-pallet:
```
baby10        Baby 1st Grade 10kg          g1  110
small10       Small 1st Grade 10kg         g1  110
smallmed7     Small/Medium 1st Grade 7kg   g1  144
med7          Medium 1st Grade 7kg         g1  144
largemed10    Large/Medium 1st Grade 10kg  g1  110
large10       Large 1st Grade 10kg         g1  110
med10g2       Medium 2nd Grade 10kg        g2  110
largemed10g2  Large/Medium 2nd Grade 10kg  g2  110
large10g2     Large 2nd Grade 10kg         g2  110
```
- Pepper boxes: 5kg/4kg × Red/Yellow/Green (6 counters). Butternut bags: 10kg/7kg (2 counters).
- Mixed pallets: one pallet containing several sizes' worth of bags — each mixed pallet still counts as 1 pallet.
- An in-progress "active truck" persists locally (not synced) until "Finish Truck" (requires truck registration) saves it as a delivery note.
- Default target pallets = 30; triggers a "full load" prompt once crossed.
- Pallet report: balance = bought − delivered, per market agent.
- Fields tab: per-field bag breakdown + "delivered by date" summary.
- Default market agents to seed: {"Grow Botha Roodt", attn "David Nel", "Johannesburg Fresh Produce Market"}, {"Dapper Market Agents", attn "Monty", "Johannesburg Fresh Produce Market"}.
- Delivery note PDF letterhead: "NANINI 121 CC T/A NANINI BOERDERY", "Farm Limpopodraai 751 LQ", "Lephalale", "Limpopo Province", "0555", "fourie05@gmail.com", "082 790 7808", "082 442 4329", "REG: 2000/026925/23", "VAT: 4840191854".

---
## Sales (📊)

**Purpose:** Record produce sale settlement reports from market agents (potatoes/peppers/tobacco/butternut) and summarize revenue. The original app auto-parses uploaded PDF settlement invoices; the Flutter version uses manual entry instead (see `ARCHITECTURE.md` deviations).

**Tables:** `sales_reports` (category, agent, report_number [dedupe key], report_date, gross_total, commission_before_vat, vat, vat_on_sales [tobacco only], nett_amount), `sales_line_items` (report_id, category, subcategory, class [potatoes only], description, gross_amount).

**Categories & subcategories:**
```
potatoes  → Baby, Small, Small/Medium, Medium, Large/Medium, Large   (+ Class 1 / Class 2)
peppers   → Red, Yellow, Green
tobacco   → F1, F2, F3, F4, F5, F6, S1, S2, S3, S4
butternut → 10kg, 7kg
```
- Tobacco has extra fields: VAT on sales, and "Deductions — packaging (before VAT)" (label differs from other categories' "Commission/Deductions").
- Summary view: totals per category/subcategory over a date range. Reports view: browsable list with expandable line items, inline agent-name edit.

---
## Truck (🚚)

**Purpose:** A shared booking calendar for the farm's **one** truck (not a fleet) — who has it booked, where, and a live GPS tracking link.

**Tables:** `truck_bookings` (start_at, end_at, location_text, lat, lng, booked_by, notes), `truck_settings` (singleton, `tracking_url`).

**Key logic:**
- Month calendar with a dot on days that have a booking; tapping a day filters the list to that day (tap again to clear → shows "upcoming" = bookings ending in the future).
- Booking form: start/end datetime (end must be after start), location text, optional map pin (lat/lng), booked-by, notes.
- Overlap check on save is a **soft warning** (confirm dialog), not a hard block.
- Default map center: Limpopo, South Africa (-23.9, 29.45), zoom 9.
- No fleet/driver fields exist at all — this is single-truck only.

---
## Manager mode (all modules)

The original web app gives each module its own separate manager password (stored hashed in that module's own browser `localStorage`). **The Flutter app simplifies this to one app-wide "Manager Mode" toggle** with a single password (SHA-256 hashed, stored locally via `shared_preferences`), gating the same category of actions (add/edit/delete master data, reports, settings) across every module. See `ARCHITECTURE.md`.
