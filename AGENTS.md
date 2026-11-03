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

## Language

The mobile app is English or Tagalog, chosen in Settings → Language;
the Admin Portal, emails, push notifications and legal policies are English.
Screen text is written in English inside `tl('...')` (values as `{0}`, passed
as `tl('Order #{0}', [id])`), with its Tagalog in `tagalog_strings.dart`; a text
with no entry shows in English. Never translate values saved to Firestore.

## Commands

```
flutter analyze                # must stay "No issues found!"
flutter test                   # ~555 tests, all must pass
cd functions && npm test       # Cloud Functions tests (node --test)
cd firestore_tests && npm i && npm test   # firestore.rules on the local emulator (needs Java)
flutter build web --release    # Admin Portal
flutter build apk --release    # Android (signed with the debug key)
firebase deploy --only firestore:rules,functions,hosting --project agritrade-bef87
```

Share AgriTrade+ sends `kAppDownloadUrl` (`/download`), which a redirect in
`firebase.json` points at the hosted APK; to move to the Play Store, change
that redirect's destination. The APK is not in git: after `flutter build web`
(which empties `build/web`) and before deploying hosting, copy it in:

```
mkdir -p build/web/downloads
cp build/app/outputs/flutter-apk/app-release.apk build/web/downloads/agritrade.apk
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
  l10n/       app_en.arb / app_tl.arb, plus app_language.dart (the language
              choice and tl()) and tagalog_strings.dart (English → Tagalog)
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
- **"What best describes you"** (`lib/data/account_types.dart`): required at
  registration and in Add Farmer, saved as `users/{uid}.buyerType` or
  `farmerType`; registration starts on `ChooseRoleScreen` (Buyer or Farmer;
  each card shows its own person cut from the one picture
  `assets/images/farmer&buyer.png`, by `buyerCrop` / `farmerCrop` in its
  pixels: re-check those if the picture is replaced), and the form
  has no role toggle. A new "Continue with Google" account goes the same way:
  `ChooseRoleScreen(google: …)` → `GoogleCompleteProfileScreen` (name
  prefilled, email read-only, no password); leaving before finishing signs
  the Google account out. Existing Google accounts go straight in;
  older accounts show "Not specified" and can answer in Edit
  Profile. Bulk buyers see the wholesale price first (`BuyerTypeWatcher`), Add
  Product suggests the farmer's kind of product first, and the Export Report
  has Buyers by Type.
- **Orders** (`orders/{id}`): one order = **one product** (`productId`,
  `productName`, frozen `commodity`, `category`, `quantity`, `unit`,
  `pricePerUnit`, `total`, buyer area fields). Status flow:
  `pending → confirmed → shipped → completed` (plus `rejected`,
  `cancelled`). A buyer can cancel while pending; a farmer can cancel a
  confirmed order with a reason; a pending order unanswered for 3 days is
  cancelled by `expirePendingOrders`; `handleOrderReschedule` returns the
  stock. The buyer confirms a shipped order ("Order Received"); the farmer may
  complete it only 3 days after shipping (`kBuyerConfirmWindow`, also in the
  rules and `order_reminder_logic.js`). `firestore.rules` checks the
  order's price against the listing (keep it in step with
  `PricingTierService`). `completedAt` is stamped on completion; analytics fall back
  to `updatedAt`, then `createdAt` (`DashboardAnalyticsService._completionDate`).
- **All analytics use completed orders only** (`DashboardDataService.orders`
  is already filtered to `status == 'completed'`; `allOrders` has every
  status). Demand = number of completed orders (never kilos — units differ).
  The one exception is **Top-Selling Products** (Admin) and **Best-Selling
  Products** (Farmer's Market tab): they rank product/unit groups by quantity
  sold ("Eggplant (kg)", "Cattle (head)"; units never added together).
  Decided by the user, 2026-11-01. The Buyer's demand badge stays order-based
  (`MarketDemandService.demandLeaders`, top 10).
- Market tab cards (`market_demand_cards.dart`): Best-Selling Products lists
  the top 5 (`bestSellerLimit`); each card has its **own month** (picking one
  on a card never moves the other). Tapping a Top Buyer Locations row shows
  what buyers there ordered that month, by completed orders
  (`productsBoughtIn`).
- The mobile app is **portrait only** (`kAppOrientations` in `main.dart`, plus
  `MainActivity` in the Android manifest and the iPhone list in
  `Info.plist`); decided by the user, 2026-11-03. Screens need not handle
  landscape. In a chat, the photo and name in the header open Conversation
  Info, like the (i).
- Conversation Info: the photo and name open the other person's page — a
  farmer's storefront, or a buyer's `BuyerPublicProfileScreen` (photo, name,
  buyer type, area, member since from publicProfiles, plus only this
  farmer's orders with that buyer). publicProfiles fields come from
  `functions/public_profile_logic.js` (used by syncPublicProfile and
  backfill_public_profiles.js); never email, phone or exact location.
- Chat reactions: hold a message (about 1 s) for Heart, Like, Wow, Sad or
  Angry (`message_reactions.dart`). Saved as `likes.{uid}` = the key
  (`heart`, `like`, `wow`, `sad`, `angry`; `true` from before = Like); the
  same one again takes it off (`MessageService.setReaction`).
  `firestore.rules` allows exactly these keys.
- Chat videos: Record Video / Choose Video in the + menu, at most 20 MB
  (`kChatVideoMaxBytes`; recording stops at 1 minute), uploaded to
  Cloudinary as a video and sent as `type: 'video'`, `videoUrl`. The bubble
  shows Cloudinary's first frame (`CloudinaryService.videoThumbnail`) and
  plays in `ChatVideoPlayerScreen` (`video_player`). The message box uses
  `AppTheme.plainFieldDecoration` in a `FormFieldGlow`, like Log In.
- Chat photos (in the chat and in Conversation Info → Shared Photos) open in
  `ChatPhotoViewer`: pinch to zoom; Save (`SaveToGalleryButton`, also on
  the video player) copies the photo or video (`gallery_saver.dart`) to the
  phone's gallery in an "AgriTrade+" album (`gal`; Android ≤ 10 needs the
  WRITE_EXTERNAL_STORAGE line in the manifest, iPhone
  NSPhotoLibraryAddUsageDescription).
- Chat + menu: Take Photo, Choose Photo, Record Video, Choose Video, then
  Share Location under a line (`AgriMenuItem.dividerBefore`; no group
  titles, the user's choice). Under a buyer's health-certificate request
  the farmer sees `CertificateRequestRow` (white, grey border, outlined
  Attach), whose Attach offers Take Photo / Choose Photo only.
  A photo or video upload shows its real progress over the message box
  (`ChatUploadProgress`) and, on Android, as a quiet progress notification
  removed when it ends (`UploadProgressNotification`, channel
  `agritrade_uploads`). Message text: at most 1,000 characters after
  trimming (`MessageService.maxTextLength`), a count from 900, Send off
  over it; attachments are not counted.
- Popup icons (`AgriDialog`) are black on a grey circle for every tone, like
  the Notifications screen's; the tone shows on the buttons instead.
- A little life in the mobile app (2026-11-04, the user's go-ahead): Explore
  opens with `ExploreBanner` (farmland photo, "Fresh from Laurel farms",
  only when no filter is on); `AgriEmptyState(art: kEmptyProduceArt)` shows
  a produce crate on empty Explore, Liked Products and Orders; Buyer Profile
  counts sit on pale green tiles. Words only, never made-up figures.
- **The buyer's area is the feed's priority** (decided by the user,
  2026-11-04): in Explore and Search, listings whose delivery coverage
  reaches the buyer's saved area (`BuyerAreaWatcher`, users/{uid}
  barangay/municipality/province) come first via `deliveringFirst`, each
  group keeping the feed's own ranking; nothing is hidden. Their card shows
  "Delivers to you". No location saved → order unchanged.
- **Livestock is sold live only** (decided by the user, 2026-11-04): no
  Selling Option in Add Product, no slaughtered price in Price Management;
  a livestock listing saves `sellingOption: 'live'` and shows no suffix.
  Records saved as `slaughtered` before then still read so
  (`isSlaughtered`, "… (Slaughtered)") and stay out of live prices and
  price suggestions.
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

Mobile forms (Log In, Forgot Password, Choose Role, registration, the Google
profile form, Edit Profile, Change Password, and any new form) share one
system in `AppTheme`'s FORMS section; use it, not new sizes:
`pageTitle` 24 → `pageDescription` 13.5 muted → `label()` 14 semibold →
fields 14 (`formTextSize`, `formHint`) → `primaryButton()` (dark green,
white 14 semibold, `formButtonHeight` 50) → `secondaryButton()` (white,
grey outline) → `formLink` (dark green, quieter). Fields are 48 tall
(`formFieldHeight`): `GlowField` / `AgriFormField`, or
`formFieldDecoration` for a TextField that needs InputDecoration (same look:
icon, thin line, text, grey outline), `formDropdownDecoration` for dropdowns.
Typed in, a field looks like the Admin login's: the outline goes and a soft
green glow shows (`glowFieldWrapper`); an InputDecoration field gets it by
sitting in `FormFieldGlow` with `onGlowPlate: true` (errors and notes go on
their own line under it, not in `errorText`). Every other text field gets
the same look from the theme: white, `AppTheme.fieldBorder` at rest and
`AppTheme.fieldFocusBorder` (a `GlowInputBorder`: no outline, the glow drawn
around the field) typed in. Use those two, never a green focused outline.
Spacing: `formPageMargin` 24, `formLabelGap` 8, `formFieldGap` 16,
`formSectionGap` 24. Account screens have the compact header
(`AgriAppBar(titleWidget: AgriTradeHeaderBrand())`, no big logo in the body);
registration shows `RegisteringAsBadge` instead of a role toggle.
`test/form_design_test.dart` checks the heights and alignment.

Mobile dark mode (Settings → Dark Mode) comes from `AppColors`' dark values
(2026-11-04 polish): page charcoal `#101214`, cards/panels/fields
`#1B1E20`, borders `#303437`, text `#F2F3F2`, secondary `#A7ADAA`; the
brand stays green (`brand` soft green `#8CCB96` for text/icons, `brandFill`
`#2E7D32` for buttons); highlights (`tint`) only a hint of green;
`adapt()` turns a pale background into charcoal one step above the cards.
Messages use muted red/amber/green in dark. Use the tokens, never fixed
colours, so both modes stay right.

Mobile app: text fields are pills (`PillInputBorder`), but anything that opens
a dropdown list is a **rounded rectangle** (`AppTheme.dropdownRadius`,
`compactDropdownRadius`, `dropdownDecoration`). Headers are rectangular bars
(`PageHeader` on the tabs, `AgriAppBar` on inner screens). Settings is one
bottom sheet for both roles (`showSettingsSheet`), opened from the gear beside
the bell in every tab's header.

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
  (`ReportPaper`), never scrolls (scales down on short windows). Market Demand
  and Market Change Analysis come from `MarketReportSections`.

## Onboarding

`OnboardingScreen`: four pages once on a fresh install (`onboarding_complete`,
see `AppRouter`), laid out from the user's design; Skip and Get Started leave
the same way. The previews (`onboarding_previews.dart`) are copies of the look
of the real screens, not the real widgets, with `SkeletonBox` grey bars in
place of names and prices, so no made-up listing shows. The welcome page's
picture is `assets/images/onboard.png`; the rest of the art is
in `assets/images/onboarding/`: replace a file under the same name for no code
change. The welcome page shows the logo alone, in the middle, since its title
has the name; from the second page the logo and name are at the left, and the
last page has Get Started with no Skip. Each page's parts come in once with
`OnboardingReveal`, and not at all with animations turned off on the phone.
The welcome picture shows the two half body (the hill at their waists,
`_WelcomeArt`). Every picture is listed in `OnboardingScreen.artAssets` and
decoded during the splash (`precacheArt`): add a new one there, or its page's
entrance plays before it appears on a first open.

## Loading & splash

- Splash (web, mobile, admin): `BrandedLoadingScreen` + `SproutLoadingBar`
  — logo, name, a pale green bar filling dark green with a small sprout at
  the end of the fill, and "Loading AgriTrade+…" (no percentage). 3 seconds;
  the app waits for it (`SproutLoadingBar.untilFilled`).
- Data loading in the portal: `AdminLoadingBar` (fills ~50% at 1s, ~85% at
  3s, creeps to 92%, never full; real data is never delayed for it).

## Conventions

- Comments are full sentences in plain English, explaining *why*; match the
  surrounding density. Doc comments (`///`) on public widgets/functions.
- Never show fabricated or sample data in the product; empty states say so.
- System messages (SnackBars, mobile and Admin Portal) are coloured by what
  they say: `showAppMessage(context, text, kind: …)` or
  `appSnackBar(text, kind: …)` (`app_scaffold_messenger.dart`), never a plain
  `SnackBar`. `MessageKind.error` red (failed, refused, a field to fix),
  `success` dark green (done, saved, sent), `warning` amber (out of stock, no
  longer available, turn on location), `info` blue-grey (a heads-up). An
  `err ?? 'Done.'` result picks its kind from `err`.
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
- Long subtitles on Market Demand / Sales by Category are cut short at
  ~1440px wide screens (controls stay top-right by design).
