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

The mobile app is **English only** (decided by the user 2026-11-04 before the
defense): no Language row in Settings and no language picker (removed);
`LanguageController.load()` always starts in English, so a phone that had
chosen Tagalog opens in English. The Tagalog texts (`tagalog_strings.dart`)
and `tl()` are kept for a language choice later. The Admin Portal, emails,
push notifications and legal policies are English.
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

Share AgriTrade+ sends `kAppPageUrl` (`/get/`, the download page; decided by
the user 2026-11-06), whose buttons go to `kAppDownloadUrl` (`/download`),
which a redirect in `firebase.json` points at the hosted APK; to move to the Play Store, change
that redirect's destination. The APK is not in git: after `flutter build web`
(which empties `build/web`) and before deploying hosting, copy it in:

```
mkdir -p build/web/downloads
cp build/app/outputs/flutter-apk/app-release.apk build/web/downloads/agritrade.apk
```

The download page is `web/get/index.html` (served at `/get/`; Firebase sends `/get` there itself. Never add a
redirect from `/get`: Firebase also matches it on `/get/`, and the page
redirects to itself without end, as happened on 2026-11-06): a standalone HTML page like `/reset-password`, not
Flutter, so it loads fast on a phone. Every button goes to `/download`; the
fonts come from the Flutter build (`/assets/assets/fonts/`), the pictures
are small WebP copies in `web/get/img/`. Its facts (Android 7.0+ from
`minSdk` 24, version from `pubspec.yaml`, the commodity band, FAQs from
`mobile_faqs.dart`) are written in by hand: update it when they change.
The phone mock-ups show grey bars in place of names and prices, like the
onboarding previews; never put made-up listings there.
For search: the page has a canonical link and JSON-LD (MobileApplication,
facts only), `web/sitemap.xml` lists it, `web/robots.txt` points to the
sitemap, and the Admin Portal (`web/index.html`) is `noindex`. Google finds
it sooner once the site is added in Google Search Console and the sitemap
submitted there.

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
  cancelled by `expirePendingOrders`. **Stock comes off the listing when the
  farmer confirms** (decided by the user, 2026-11-05): placing an order only
  checks there is enough (`stockOnConfirm: true`), confirming takes it in
  the same transaction (`stockDeductedAt`; refused if not enough left,
  enforced by `farmerStockStepOk` in the rules), and only an order that took
  stock gives it back on cancel (`orderTookStock` /
  `order_stock_logic.js`; orders from before took it when placed, and
  older app versions may still place that way). The buyer confirms a shipped order ("Order Received"); the farmer may
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
- Farmer's Market tab (decided by the user, 2026-11-05): under Sales
  Performance, "AgriTrade+ Insights" is a dropdown ("View AgriTrade+
  insights": Current Market Average, Best-Selling Products, Top Buyer
  Locations) showing only the one chosen (`MarketInsight`); its first-time
  hints are two (Sales Performance, the insights picker). Orders Today
  counts the orders confirmed today and still Confirmed
  (`confirmedTodayCount`) and opens Orders on the Confirmed tab. Orders
  (buyer and farmer) has a period filter under the status tabs (`OrderStatusPager.belowTabs`;
  Today, Last 7 / 30 days, Last 3 / 6 months, This year, All time, Custom
  range; `OrderDateFilter`, by the day placed), whose menu drops down from
  the button itself (`showAgriPopupMenu`), not a bottom sheet. Placing an order ends with an
  "Order Placed!" summary (`showOrderPlacedDialog`).
- Market tab cards (`market_demand_cards.dart`): Best-Selling Products lists
  the top 5 (`bestSellerLimit`); each card has its **own month** (picking one
  on a card never moves the other). Tapping a Top Buyer Locations row shows
  what buyers there ordered that month, by completed orders
  (`productsBoughtIn`). Each area's percentage is its share of all the
  month's buyer orders (`BuyerLocation.sharePercent`, `wholePercents`: the
  areas always add up to 100%), decided by the user 2026-11-06; the counts
  are real completed orders, never padded.
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
- Held messages (decided by the user, 2026-11-05; `message_actions.dart`):
  the rest of the chat blurs, the message stays sharp with the reactions
  above it and a menu under it — Reply, Copy (text), Pin / Unpin, Unsend
  (your own: content cleared, `unsent: true`, "You unsent a message") and
  Report (theirs: a `reports` doc, `targetType: 'message'`). One pinned
  message per conversation (`pinnedMessage`), shown as a banner with an ×.
  Messages slide under the finger to reply (`SwipeToReply`): received
  ones to the right, your own to the left.
- Tapping outside a text field takes its focus and the keyboard away, in
  every screen (`TapOutsideToUnfocus` in main.dart). On "Continue with
  Google", the profile form's Cancel goes back to choosing Buyer/Farmer
  (still signed in), not out to Log In. A login with an unregistered email
  says "This email is not registered" (and a Google-only one says to use
  Google): `reportLoginFailure` looks the email up — the user accepted that
  this reveals whether an email is registered.
- Chat videos: Record Video / Choose Video in the + menu, at most 100 MB
  (`kChatVideoMaxBytes`, the most Cloudinary takes in one upload; 20 MB
  turned away 1080p clips past ~10 s) and recorded up to 30 seconds
  (`kChatVideoMaxDuration`); both limits are on the menu labels and the
  upload bar shows "12 of 58 MB". Uploaded to
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
- Buyer Profile counts sit on pale green tiles. A banner on Explore and a
  produce picture on empty pages were tried on 2026-11-04 and removed by
  the user: empty pages keep the icon (`AgriEmptyState`).
- **No internet** (decided by the user, 2026-11-05): opened offline, the
  phone stays on the splash with a note and Try Again, and carries on by
  itself once online (`AppBootstrap._waitForInternet`; the Admin website
  keeps its NoInternetScreen). Offline mid-session, what is on screen
  stays, and pull-to-refresh says there is no internet instead of loading
  (`AgriRefreshIndicator.online`). Buyer Search suggests commodities,
  listing and farmer names as they type, with the matching products under
  them (`suggestedSearchTerms`). Product Details' map preview opens Farm
  Location (`BuyerMapView`), which shows the distance from the last known
  position at once and has a refresh; Order Now and Message fill the bar.
- **What a buyer buys comes first** (decided by the user, 2026-11-05):
  Explore puts the products a buyer buys most (from their own orders;
  `boughtFirst` / `boughtCounts`) ahead of the rest, inside the area tiers
  below, and each pull-to-refresh deals a fresh mix (`_feedMix`). Search's
  Recommended Products puts listings of a product they bought first, and
  shows no "based on…" line. A confirmed pick-up order shows the buyer the
  pick-up address, a map of the farm pin and Get Directions
  (`PickupPlaceCard`; the farmer shares them on confirming, in
  orders/{id}/private/farmer, `pickupAddress`/`pickupLat`/`pickupLng`).
  Map points for an area wait at most 3 s for geocoding (`geocodeWait`),
  then use the barangay's reference point and finish in the background.
- **The buyer's area is the feed's priority** (decided by the user,
  2026-11-04): in Explore and Search, listings whose delivery coverage
  reaches the buyer's saved area (`BuyerAreaWatcher`, users/{uid}
  barangay/municipality/province) come first via `deliveringFirst`, each
  group keeping the feed's own ranking; nothing is hidden. Their card shows
  "Delivers to you". No location saved → order unchanged.
- **Photos and listings** (decided by the user, 2026-11-05): a listing has
  up to 5 photos (`AddProductScreen.maxPhotos`: the main photo plus a "More
  photos" row); Product Details swipes through them, and every photo that
  can be tapped (product, storefront, review) opens `openPhotoGallery`
  (`chat_photo_viewer.dart`: swipe, "2 / 5", zoom, Save). The farm map on
  Product Details is a still preview (no gestures; lite mode on Android);
  tapping it or Open map opens the movable map. The storefront shows the
  farmer's reviews (rating, latest two, See all = `ProductReviewsScreen`
  with no productId). The buyer's product grids (Explore, Search, Liked)
  have no farmer line (`ExploreProductCard.showFarmer` is off by default).
  Tapping the "Welcome to AgriTrade+!" notification shows
  `showWelcomeDialog` (greets by first name), then Help & Support.
- **Livestock is sold live only** (decided by the user, 2026-11-04): no
  Selling Option in Add Product, no slaughtered price in Price Management;
  a livestock listing saves `sellingOption: 'live'` and shows no suffix.
  Records saved as `slaughtered` before then still read so
  (`isSlaughtered`, "… (Slaughtered)") and stay out of live prices and
  price suggestions.
$1- **Categories** (restored by the user 2026-11-06): Grains, Root Crops,
  Vegetables, Spices, Fruits, Livestock (`kBuiltInCategories`, listed in
  that order, then any the Admin adds). Root Crops and Spices were part of
  Vegetables from 2026-10-28 to 11-06; a listing or order saved as
  Vegetables then counts under its commodity's category again
  (`listingCategory`), and so do the built-in root crops and spices
  that Price Management saved as Vegetables then (`applyAdminRecords`).
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
  `AdminPalette.fallback(context)`. Titles, headings and field labels use
  `palette.heading` (bold dark green, like the Admin login's "Welcome" and
  "Email Address"); small spaced capitals ("ADMIN DASHBOARD", sidebar
  groups) use `palette.eyebrow` (medium green, like "ADMIN PORTAL"); body
  text and figures stay near-black. Decided by the user, 2026-11-04.
- `adminThemeData(context, palette)`: the portal's Material theme (buttons,
  inputs, checkboxes, dialogs, menus, grey hover/focus).
- Font: **Inter** (`kAdminFontFamily`, bundled in `assets/fonts`; `adminFont()`
  for a style of its own). The mobile app keeps Montserrat. The Admin login and
  Forgot Password forms are in Inter too (`AdminAuthShell._forms`): outside
  the portal theme the web default is Google Fonts Montserrat in its regular
  file only, where bold cannot be drawn.
- `AdminRadii`: `card` 10 (cards, tables; `kAdminTableRadius` 10), `control`
  10 (buttons, form inputs, search, dropdowns, date/year pickers: all
  `kAdminFieldRadius`), `pill` (chips, badges only). The Admin login and
  Forgot Password fields and buttons are the same rounded rectangles
  (`GlowField(radius: AppTheme.adminFieldRadius)`). Header buttons (Announce, Dark Mode, bell): white
  rounded squares with a grey border (`adminHeaderButtonDecoration`).
- `admin_filter_controls.dart`: `kAdminControlHeight` = 40,
  `AdminInputGlow` (the white rounded plate behind every search/dropdown/
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
- Sidebar: `lib/widgets/admin_sidebar.dart` (`AdminSidebarColors.of(context)`):
  white top (logo, "AgriTrade+" bold dark green, "Admin Panel"; no green
  band, removed by the user 2026-11-05), dark green group names,
  pages in groups MAIN / MODERATION (`AdminSidebarEntry.section`, a line
  between groups), the open page a dark green block with 8px corners
  (`kAdminSidebarRowRadius`), sub-pages with a small dot. Dashboard look
  (2026-11-04, from the user's mock-up; the bar beside the welcome text, the
  leaf before "Overview" and the icons before card titles were removed by
  the user on 2026-11-05): Overview cards with a pale green (amber for
  attention) icon box and a soft wave in the corner. Pop-up notices
  (`AdminAlertToasts`, admin_notifications.dart): what happens while the
  portal is open (orders, applications, approvals, reports; not the
  Admin's own announcements or sign-ins) pops up at the top right for 6 s
  (held while hovered, at most 3, click opens its page).

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
Registration is three steps (Choose Role → Your Information → Account
Setup): under the header, `RegistrationStepIndicator` (numbered circles
joined by lines, each step's name under it at 11, the active one bold
green; done steps a tick; not tappable), then the page title, a one-line
description and the badge. Above Register is only a reminder to review
what was entered, not a copy of the details (the user's choice, 2026-11-06).
Choose Role has "Already have an account? Log in" under the cards (not on
the forms after it; none for a new Google account), and the chosen card
stays marked on coming back (2026-11-07). Moving between steps, the header
and the steps never move: only the content under them slides in, from the
right going on and from the left going back (the user's choice,
2026-11-07). Between screens that is `registrationStepRoute` (no movement)
plus `StepContentEntrance` on the content; inside RegisterScreen,
`_playStepIn`. Keep the step indicator outside those animations.
`test/registration_transition_test.dart` checks it.
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
`compactDropdownRadius`, `dropdownDecoration`). An open dropdown list is
only as wide as its longest option, not the whole field (decided by the
user 2026-11-06): use `FittedDropdownField` for a form dropdown, or
`menuWidth: fittedMenuWidth(...)` on a `DropdownButton`
(`fitted_menu_width.dart`; `DropdownButtonFormField` cannot set it). Headers are rectangular bars
(`PageHeader` on the tabs, `AgriAppBar` on inner screens). Settings: the
**farmer** has the bottom sheet (`showSettingsSheet`) from the gear beside the
bell; the **buyer** has no gear (2026-11-04) — the same options are rows on
the Buyer Profile: My Activity (My Reviews, Liked Products, Purchase History
= Orders → Completed), Preferences & Account (Delivery & Pick-up, Manage
Account, Notification Settings, Appearance = Dark Mode), Support & More
(Share, Feedback, Help), then `LogOutButton`. Both reuse the same screens
(`shareAgriTrade`, `showFeedbackSheet`, `AppearanceScreen`). Registration
asks before Back throws away a filled-in form ("Leave registration?":
`RegisterScreen`, and the Google profile form, whose Cancel asks too). Explore
fixes its list only once the server has answered and lets new posts in at
once at the top of the feed (`exploreFeed`). Its category pills and location
dropdown hide while scrolling down and come back after a deliberate scroll
up (`FiltersOnScroll`, 140px) or at the top. Legal policies are version
1.0, effective and last updated November 5, 2026 (`kPolicyEffectiveDate`),
set with the user on 2026-11-05.

User preferences for the admin UI (keep them): neutral black/white/grey,
**dark green only for buttons/active/selected** (plus the pale green icon boxes of the 2026-11-04 mock-up), no other pale-green
surfaces,
rounded-rectangle text fields, search, dropdowns and date pickers (10px,
`kAdminFieldRadius`, like the Admin login's fields: icon, thin line, text;
changed from pills by the user on 2026-11-04), square checkboxes (4px radius),
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
  (`ReportPaper`). Choices on the left (sections in two columns; a short
  window scrolls them, nothing is shrunk), and from 900px wide a live
  preview on the right of the very report they make: the PDF's pages
  (`ReportExportService.build` + `Printing.raster`) or the Excel sheets'
  first rows. The data is read once when the dialog opens
  (`ReportExportService.loadData`) and reused by the preview and Export. Market Demand
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
  the app waits for it (`SproutLoadingBar.untilFilled`). On the web,
  `web/index.html` shows an HTML/CSS copy of it while Flutter downloads
  (same sizes, colours and sprout, matched to the pixel). That bar never
  fills (70% in 2.1 s, then creeps to 90%: `pageBarProgress`), and
  Flutter's bar finishes from where it got to (`window.agriTradeSplashStart`,
  read once by `takePageSplashStart`, so a hot restart fills afresh);
  change both together.
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

- Rules, functions and hosting were last deployed on 2026-11-06 (with the
  download page). Redeploy after backend changes, then hard-refresh.
- Dark mode not verified on every admin page (tables, Moderation, Audit Log).
- Long subtitles on Market Demand / Sales by Category are cut short at
  ~1440px wide screens (controls stay top-right by design).
