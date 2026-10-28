# AgriTrade+ — guide for coding agents

AgriTrade+ is a capstone project: an agricultural marketplace for **Laurel,
Batangas (Philippines)** that connects **farmers** (sellers) and **buyers**,
overseen by an **Admin**. One Flutter codebase, two products:

- **Mobile app (Android/iOS)** — farmers and buyers. Entry: `AppRouter`.
- **Web = the Admin Portal only.** `lib/screen/app_bootstrap.dart` sends web
  to `AdminSessionGate`, mobile to `AppRouter` (`kIsWeb`).

Backend: **Firebase** project `agritrade-bef87` — Auth, Cloud Firestore,
Cloud Functions (Node 22, `functions/`, region `asia-southeast1`), Hosting
(`build/web`). Images go to Cloudinary (`cloudinary_service.dart`).

## Talking to the user

- The user writes in **Tagalog / Taglish**; answer in the same, short and
  plain. They often send a screenshot plus one line ("dapat pill shaped").
- They are preparing for a capstone **testing/defense with a panel**.
  Prefer safe, verifiable changes; never fake data to "look full".
- **Do not commit, push or deploy unless they ask.** Ask which remote.

## Commands

```
flutter analyze                # must stay "No issues found!"
flutter test                   # ~555 tests, all must pass
cd functions && npm test       # Cloud Functions tests (node --test)
flutter build web --release    # Admin Portal
flutter build apk --release    # Android (signed with the debug key)
firebase deploy --only firestore:rules,functions,hosting --project agritrade-bef87
```

- **Format only the files you edit** (`dart format <file>`), never a whole
  folder: some files (notably under `lib/services/`, e.g.
  `pdf_report_service.dart`, `report_export_service.dart`) are committed
  unformatted and a folder-wide format makes huge unrelated diffs. Check
  first: `dart format -o show <file> | diff <file> -`.
- Windows + Git Bash: `python` is not installed; use `perl` or `sed`.

## Code layout

```
lib/
  main.dart, firebase_options.dart
  data/       commodity_master_list.dart (CommodityRegistry — the Admin-managed
              commodity list everything matches against), Laurel barangays,
              legal policies, FAQs
  l10n/       app_en.arb / app_tl.arb (mobile app is English + Tagalog)
  screen/     every screen; admin_* files are the Admin Portal
  services/   Firestore/data logic (orders, products, analytics, reports…)
  theme/      app_theme.dart, app_colors.dart (mobile; has its own dark mode
              via theme_controller.dart)
  widgets/    shared widgets (splash, sidebar, cards…)
functions/    Cloud Functions (*_logic.js holds testable pure logic)
firestore.rules, firestore.indexes.json
test/         widget + unit tests (one file per feature)
```

## Domain essentials

- **Roles** live on `users/{uid}.role`: `farmer`, `buyer`, `admin`.
  Farmers are verified by the Admin (Verification Queue, `verificationDocs`).
- **Orders** (`orders/{id}`): one order = **one product** (`productId`,
  `productName`, frozen `commodity`, `category`, `quantity`, `unit`,
  `pricePerUnit`, `total`, buyer area fields). Status flow:
  `pending → confirmed → shipped → completed` (plus `rejected`,
  `cancelled`). `completedAt` is stamped on completion; analytics fall back
  to `updatedAt`, then `createdAt` (`DashboardAnalyticsService._completionDate`).
- **All analytics use completed orders only** (`DashboardDataService.orders`
  is already filtered to `status == 'completed'`; `allOrders` has every
  status). Demand = number of completed orders (never kilos — units differ).
- A product counts under its **commodity** (`demandProduct`): "Native
  Chicken" → Chicken. Unknown names count under their own title-cased name.
- Other collections: `products`, `market_prices` (+ `history` subcollection:
  Admin reference prices), `historical_demand` (Admin imports), `reports`,
  `violations`, `audit_logs`, `announcements`, `adminSessions`,
  `notifications`, `market_sales`, `farmerInvites`.
  See `firestore.rules` for the full list and who may read/write what.

## Admin Portal design system (web)

All admin colours, shapes and sizes come from a few shared places — change
those, not individual screens:

- `AdminPalette` (`admin_dashboard_screen.dart`): `light` and `dark`
  (neutral: near-black/greys; green only for accent + success). Read it with
  `AdminThemeScope.of(context).palette`; in dialogs (outside the scope) use
  `AdminPalette.fallback(context)`.
- `adminThemeData(context, palette)`: the portal's Material theme (buttons,
  inputs, checkboxes, dialogs, menus, grey hover/focus).
- `AdminRadii`: `card` 16 (cards, tables, modals), `control` 10 (buttons,
  form inputs), `pill` (dropdowns, search, date/year pickers, chips, badges).
- `admin_filter_controls.dart`: `kAdminControlHeight` = 40,
  `AdminInputGlow` (the white **pill** plate behind every search/dropdown/
  date picker), `adminFieldDecoration` (16px inset, 16px icon),
  `AdminPillDropdown`, `AdminPillSearch`, `AdminMonthPill`, `AdminYearPill`,
  `AdminPillToggle`, `adminPillControlStyle` (a date button styled as a
  pill), `AdminGreyMenu`, `AdminLoadingBar`.
- `adminActionColor(c)` = dark green (primary buttons, active nav, selected
  controls). `adminControlColor(c)` = near-black (field icons, chosen menu
  items). Buttons: primary filled dark green; secondary outlined white with
  grey border; tertiary text-only near-black; destructive red.
- Dark Mode: `adminDarkMode` (ValueNotifier, saved per browser) and the
  moon/sun `AdminThemeToggle` beside Announce. Default is light. Not every
  page has been checked in dark mode.
- Sidebar: `lib/widgets/admin_sidebar.dart` (`AdminSidebarColors.of(context)`).

User preferences for the admin UI (keep them): neutral black/white/grey,
**dark green only for buttons/active/selected**, no pale-green surfaces,
pill-shaped dropdowns/search/date pickers, square checkboxes (4px radius),
standalone info icons (no box), every control in a toolbar the same height.

## Analytics Dashboard specifics

- **Market Demand** (`AdminMarketDemandCard`, `admin_price_trend_chart.dart`):
  grouped monthly bars, earlier year `#A5D6A7`, later `#2E7D32`; Admin
  searches a product and picks two years (`AdminYearCompare`). Shows
  "No data to display" states, error + Retry (`DashboardDataService.ordersError`).
- **Years start at the first completed order** (no fixed 2025): used by
  Market Demand and Price Trend (`PriceTrendService.yearsOnRecord`). One year
  on record → one bar/line per month; comparison appears with two years.
- **Market Change Analysis** (`admin_market_trends_card.dart`): Price Trend
  (listings, completed sales, Admin reference prices, imports) + Last 30 Days
  (demand, local supply, market price, possible factors). The **Import
  Historical Data button is hidden** (`_importEnabled = false`); imports older
  than the first completed order are ignored.
- **Export Report** (`export_options_dialog.dart` → `ReportExportService` →
  `PdfReportService`/Excel): paper size A4 / Short / Long
  (`ReportPaper`), never scrolls (scales down on short windows). It does not
  yet include Market Demand or Market Change Analysis sections.

## Loading & splash

- Splash (web, mobile, admin): `BrandedLoadingScreen` + `WalkingFarmerLoader`
  — logo, name, tagline "Smart Agricultural Trading, Made Simple.", a farmer
  walking along the loading bar to a buyer and handing over a crate, with
  "Loading AgriTrade+… N%". 3 seconds; the app waits for it
  (`WalkingFarmerLoader.untilWalkDone`).
- Data loading in the portal: `AdminLoadingBar` (fills ~50% at 1s, ~85% at
  3s, creeps to 92%, never full; real data is never delayed for it).

## Conventions

- Comments are full sentences in plain English, explaining *why*; match the
  surrounding density. Doc comments (`///`) on public widgets/functions.
- Never show fabricated or sample data in the product; empty states say so.
- Add or update a test with each behaviour change (see `test/` for style:
  named after what the user sees).
- For visual checks, a throwaway golden test with real fonts works:
  load `assets/fonts/Montserrat-*.ttf` with `FontLoader`, set
  `GoogleFonts.config.allowRuntimeFetching = false`, render with
  `matchesGoldenFile`, then delete the test and the image.

## Known open items (as of 2026-10-29)

- Backend not redeployed recently: run the deploy command above (rules,
  functions, hosting) before testing on the live site, then hard-refresh.
- Dark mode not verified on every admin page (tables, Moderation, Audit Log).
- Web shows a blank page for a moment before Flutter loads (no HTML splash
  in `web/index.html`).
- Export Report could include Market Demand / Market Change Analysis.
- Long subtitles on Market Demand / Sales by Category are cut short at
  ~1440px wide screens (controls stay top-right by design).
