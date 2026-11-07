# AgriTrade+ â guide for coding agents

AgriTrade+ is a capstone project: an agricultural marketplace for **Laurel,
Batangas (Philippines)** that connects **farmers** (sellers) and **buyers**,
overseen by an **Admin**. One Flutter codebase, two products:

- **Mobile app (Android/iOS)** â farmers and buyers. Entry: `AppRouter`.
- **Web = the Admin Portal only.** `lib/screen/app_bootstrap.dart` sends web
  to `AdminSessionGate`, mobile to `AppRouter` (`kIsWeb`).

Backend: **Firebase** project `agritrade-bef87` â Auth, Cloud Firestore,
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
  data/       commodity_master_list.dart (CommodityRegistry â the Admin-managed
              commodity list everything matches against), Laurel barangays,
              legal policies, FAQs
  l10n/       app_en.arb / app_tl.arb, plus app_language.dart (the language
              choice and tl()) and tagalog_strings.dart (English â Tagalog)
  screen/     every screen; admin_* files are the Admin Portal
  services/   Firestore/data logic (orders, products, analytics, reportsâ¦)
  theme/      app_theme.dart, app_colors.dart (mobile; has its own dark mode
              via theme_controller.dart)
  widgets/    shared widgets (splash, sidebar, cardsâ¦)
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
  `ChooseRoleScreen(google: â¦)` â `GoogleCompleteProfileScreen` (name
  prefilled, email read-only, no password); leaving before finishing signs
  the Google account out. Existing Google accounts go straight in;
  older accounts show "Not specified" and can answer in Edit
  Profile. Bulk buyers see the wholesale price first (`BuyerTypeWatcher`), Add
  Product suggests the farmer's kind of product first, and the Export Report
  has Buyers by Type.
- **Orders** (`orders/{id}`): one order = **one product** (`productId`,
  `productName`, frozen `commodity`, `category`, `quantity`, `unit`,
  `pricePerUnit`, `total`, buyer area fields). Status flow:
  `pending â confirmed â shipped â completed` (plus `rejected`,
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
  status). Demand = number of completed orders (never kilos â units differ).
  The one exception is **Top-Selling Products** (Admin) and **Best-Selling
  Products** (Farmer's Market tab): they rank product/unit groups by quantity
  sold ("Eggplant (kg)", "Cattle (head)"; units never added together).
  Decided by the user, 2026-11-01. The Buyer's product cards have no
  "High / Moderate demand" badge (removed by the user, 2026-11-07); the
  Market tab's Buyer Areas still show each area's demand. AgriTrade+
  Insights collapses to its heading (`CollapsibleSection`).
- Farmer's Market tab (decided by the user, 2026-11-05): under Sales
  Performance, "AgriTrade+ Insights" is a segmented picker
  (`MarketInsightPicker`: Best Sellers | Market Average | Buyer Areas, the
  market average in the middle, for Best-Selling Products, Current Market
  Average, Top Buyer Locations; the chosen one dark green, all three one
  font size; the user's design 2026-11-07, in place of a dropdown; the
  month sits at the top beside the title, as on Sales Performance, and
  Best Sellers and Buyer Areas each keep their own; Best
  Sellers rows show rank, product and quantity, no trend icon, removed by
  the user) showing only the one chosen (`MarketInsight`); its first-time
  hints are two (Sales Performance, the insights picker). Orders Today
  counts the orders confirmed today and still Confirmed
  (`confirmedTodayCount`) and opens Orders on the Confirmed tab. Orders
  (buyer and farmer) has a period filter: the Buyer's opposite the Orders
  title, the Farmer's under the status tabs on the right (`OrderStatusPager.belowTabs`;
  his title row has Inventory); only All time, Today, Last 7 days and Last 30 days, the
  user's choice 2026-11-07; `OrderDateFilter`, by the day placed), whose menu drops down from
  the button itself (`showAgriPopupMenu`), not a bottom sheet. The button is dark
  green whatever the period, with no × beside it (the user's choice,
  2026-11-07): All time is picked from the menu. Placing an order ends with an
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
- Conversation Info: the photo and name open the other person's page â a
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
  above it and a menu under it â Reply, Copy (text), Pin / Unpin, Unsend
  (your own: content cleared, `unsent: true`, "You unsent a message") and
  Report (theirs: a `reports` doc, `targetType: 'message'`). One pinned
  message per conversation (`pinnedMessage`), shown as a banner with an Ã.
  Messages slide under the finger to reply (`SwipeToReply`): received
  ones to the right, your own to the left.
- Tapping outside a text field takes its focus and the keyboard away, in
  every screen (`TapOutsideToUnfocus` in main.dart). On "Continue with
  Google", the profile form's Cancel goes back to choosing Buyer/Farmer
  (still signed in), not out to Log In. A login with an unregistered email
  says "This email is not registered" (and a Google-only one says to use
  Google): `reportLoginFailure` looks the email up â the user accepted that
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
- Chat photos (in the chat and in Conversation Info â Shared Photos) open in
  `ChatPhotoViewer`: pinch to zoom; Save (`SaveToGalleryButton`, also on
  the video player) copies the photo or video (`gallery_saver.dart`) to the
  phone's gallery in an "AgriTrade+" album (`gal`; Android â¤ 10 needs the
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
- Buyer Profile counts sit on pale green tiles. A produce picture on empty
  pages was tried on 2026-11-04 and removed by the user: empty pages keep
  the icon (`AgriEmptyState`). Explore (the user's design, 2026-11-08,
  copied from their picture): a cream page (`exploreBackground`); under
  the dark green band, `ExploreHero` (a big title — its leaf removed by the user
  2026-11-08 — one line, a gold underline, a drawn farm scene, `FarmScenePainter`; it tucks
  away with the filters on a scroll down); a white search pill on a soft
  shadow holding the search field (its own thin pill) and a pale green
  round filter button that shows or hides the filters; category pills with
  no icons (selected dark green, others white with a grey outline); a pale
  green location pill with a green outline and a filled pin. Product cards
  (`ExploreProductCard`, white on a soft shadow): a wide photo with the
  category on a pale gold badge (no icon, the user's choice) and
  "Delivers to you" at its top left, the name in dark green (one line) with
  a gold star rating at the right, the price, "Wholesale | Min …" in one
  pale green pill, and the stock with a box icon. Bold text there names
  `fontFamily: 'Montserrat'` (the bundled family with its real weights):
  the theme's Google Fonts family alone drew "Explore" without its bold. Every size there (fonts, heights,
  paddings, the farm scene running on behind the search bar) was measured
  from the user's picture for a 390-wide screen (2026-11-08): the user asked
  for it to match exactly, so change them only from a new picture.
  Search (`BuyerSearchScreen`, the user's picture of 2026-11-08): no header;
  a cream page starting with a plain dark green Back and the search field
  (`ExploreSearchPill` with a controller: Explore's very own bar as the
  field, the same 41 high, outline and text; the user, 2026-11-08);
  section titles 17 in dark green with a small icon (gold flame Trending,
  clock Recent, gold star Recommended); Trending terms on pale green pills,
  Recent ones on white pills with a clock; the products in rows of two, a
  row with no wholesale at all leaving out the "Wholesale | Min" strip
  (`ExploreProductCard.reserveWholesaleRow`, `extentFor(withWholesaleRow:)`).
  Category badges have no icon anywhere (the user, 2026-11-08).
  A farmer's public profile (`FarmerStorefrontScreen`, what a buyer sees;
  the user's design, 2026-11-08): no app bar — Back over a drawn landscape
  (`ProfileLandscapePainter`: faint gold sun, hills, curved rows, leaves),
  the photo 92 in a white ring with a gold arc and, only when verified, a
  dark green shield; the name 19.5, the place 12.5, the Verified Farmer
  pill, a white card of Rating | Reviews | Products (real numbers, "–" with
  no rating; the reviews and products are each read once for the card and
  the lists), then Reviews (an outlined See all pill; the latest two on
  white cards) and Products (Explore's cards). Reviews everywhere show the
  reviewer's photo from publicProfiles (`ReviewerAvatar`, once per buyer;
  initials without one), the user's choice 2026-11-08.
  Place Order (the user's design, 2026-11-08; UI only): the cream page
  under a plain Back + title; the product card (photo 60, name 14, price
  16); section titles 15.5 with a small dark green icon (Buyer Details,
  Contact Information, Order, Fulfillment, Order Summary); labels 12.5,
  notes 10.5; the form's own fields (`GlowField`, the app's 48); the check
  dark green; the price note a pale green banner with a tag; the chosen
  fulfillment pale green with a dark green outline; the summary rows
  11.5/12, the total 14 and 17; Submit Order dark green, 46 high, a gold
  send icon, fixed on the cream.
  Search opens without jumping: until Trending, Recent and the last
  "Clear" (on the phone) have all answered — with data, nothing or an
  error — Trending and Recent show placeholder pills in their places and
  Recommended Products waits (`_historyReady`); what was last seen is kept
  for the next visit (static `_lastTrending` / `_lastRecentRaw`, per
  account). `test/search_screen_loading_test.dart` checks the order.
  Messages (`ChatListScreen` inbox, both roles; the user's design,
  2026-11-08): on Explore's cream, under the dark green band, "Messages" as
  big as Explore's title (no icon) with the menu opposite; Explore's own
  search bar and pills (shared: `ExploreSearchPill`, `FilterPill` in
  explore_search_pill.dart); flat rows with a hairline (#E9EAE5): avatar 46,
  the name in dark green, a pin and the place, the last message, the time at
  the top right and a pale green unread count (#DCEFCB) under it. The list
  keeps the last conversations it received (`_lastConversations`, the
  StreamBuilder's initialData): built anew on a stream already listened to,
  it would otherwise spin until a new message.
  Orders (`OrdersView`, both roles; the user's design, 2026-11-08): on the
  cream, under the band, "Orders" as big as Explore's title with the period
  (buyer; a pale green pill, calendar and chevron, 12) or Inventory (farmer)
  opposite; status tabs 12 (dark green over a thin line, the rest grey);
  white cards (`OrderCard`): photo 56, the name 14 in dark green, a pale
  green RETAIL/WHOLESALE badge, details 11, PENDING pale gold with golden
  brown text, the total 15, Details 36 high with a thin dark green outline.
  Search's section titles are 14 and its term pills 11 (about Explore's
  size), its field Explore's bar with the text in the middle.
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
  shows no "based onâ¦" line. A confirmed pick-up order shows the buyer the
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
  "Delivers to you". No location saved â order unchanged.
- **Photos and listings** (decided by the user, 2026-11-05): a listing has
  up to 5 photos (`AddProductScreen.maxPhotos`: the main photo plus a "More
  photos" row); Product Details swipes through them, and every photo that
  can be tapped (product, storefront, review) opens `openPhotoGallery`
  (`chat_photo_viewer.dart`: swipe, "2 / 5", zoom, Save). The farm map on
  Product Details is a still preview (no gestures; lite mode on Android);
  tapping it or Open map opens the movable map. On both maps the farmer and the
  buyer are round photos (initials without one; `FarmBuyerMap`,
  `MapAvatarMarker`: farmer ringed green, buyer blue) in place of pins, and
  a dashed line along the roads draws itself from the buyer to the farm
  area (`RoadRouteService`: OSRM's public server on OpenStreetMap, no key,
  since the app's Google key is limited to the web and Directions refuses
  it; no route = a straight line), with a note at the top of the map that it ends at
  the farmer's general area (without a line, that the photo marks the
  general area): said only there, not again in the card under it.
  Farm Location has its own + and − (`_ZoomButtons`): + zooms one step in
  with the farmer in the middle. The photo rings are thin (2, then a 1.5
  white gap). Decided by the user 2026-11-07. The distance
  then reads "by road". Farm Location starts from the phone's position,
  else the buyer's saved one (users/{uid}/private/geo), and says which. Under Farm Location, Recommended
  Products: other listings of the same product name with stock (not this
  one, not archived or suspended), in a sideways row of cards. Decided by the user 2026-11-07 (the tabs:
  see below).
  Product Details look (the user's picture, 2026-11-08; UI only): a cream
  page; the photo with round white Back, heart and share; the white panel
  it curves into (rounded below, on a soft shadow) holds a pale green
  category pill (11), the name 20 and price 23 (dark green, bold) with the
  rating on the left and the facts (dark green icons) on the right (stacked
  under 330 wide), a pale green wholesale banner with a faint sprout
  (`SproutFieldPainter`), and the farmer with a pale green Verified badge;
  then the row of tabs (`SectionTabs`, 11.5: the chosen one a dark green
  pill with a short gold line). It scrolls with the page: no bar at the top,
  and a tap never moves the page; it only chooses what shows under it
  (Overview every section, the others their one; the user's choice,
  2026-11-08, replacing the scroll-to-section bar of 11-07). Description,
  Buyer Reviews (one review full width on cream, more slide
  sideways), Farm Location (the map's own note says it is the general area,
  no caption under it) and Recommended Products each a white rounded card
  (`_SectionCard`; headings 15.5, body 12.5); Order Now (outlined 1.2) and
  Message (filled #0B4225), 46 high, radius 13, 13 labels, 18 icons in gold
  (#F5BB24; grey while off), fixed on the cream with no band. From an
  Explore card, Product Details grows out of that card and shrinks back into
  it on Back (`openFromCard` / `CardZoomRoute`, card_zoom_route.dart: 360 ms,
  easeInOutCubic, the page scaled to the growing box from its top so its
  photo stands where the card's was; the same widgets throughout, so the
  page keeps its state). Other lists still slide. The storefront shows the
  farmer's reviews (rating, latest two, See all = `ProductReviewsScreen`
  with no productId). Review cards (storefront, Product Details, all
  reviews) have a thumbs-up at the right (`ReviewLikeButton`): another
  buyer likes the review (`likes.{uid}` = true, again to take it back;
  firestore.rules allows only their own key, never on their own review);
  the reviewer, farmers and the Admin see the count only. Decided by the
  user 2026-11-07. The buyer's product grids (Explore, Search, Liked)
  have no farmer line (`ExploreProductCard.showFarmer` is off by default).
  Tapping the "Welcome to AgriTrade+!" notification shows
  `showWelcomeDialog` (greets by first name), then Help & Support.
- **Livestock is sold live only** (decided by the user, 2026-11-04): no
  Selling Option in Add Product, no slaughtered price in Price Management;
  a livestock listing saves `sellingOption: 'live'` and shows no suffix.
  Records saved as `slaughtered` before then still read so
  (`isSlaughtered`, "â¦ (Slaughtered)") and stay out of live prices and
  price suggestions.
$1- **Categories** (restored by the user 2026-11-06): Grains, Root Crops,
  Vegetables, Spices, Fruits, Livestock (`kBuiltInCategories`, listed in
  that order, then any the Admin adds). Root Crops and Spices were part of
  Vegetables from 2026-10-28 to 11-06; a listing or order saved as
  Vegetables then counts under its commodity's category again
  (`listingCategory`), and so do the built-in root crops and spices
  that Price Management saved as Vegetables then (`applyAdminRecords`).
- **A commodity the Admin takes off** (decided by the user, 2026-11-07):
  archiving it (onCommodityArchiveChanged) or removing it in Price
  Management (deleting its market_prices record, onCommodityRemoved) hides
  its listings (`isSuspended`, `moderationStatus: commodity_archived`;
  found by `commodity` or, for older listings, by `name`) and notifies only
  the farmers who sell it (`commodityNotice`); restoring it, or adding it
  back (onCommodityAdded), brings them back. On the Farmer's Profile such a
  listing is with the archived ones, marked UNAVAILABLE (HIDDEN if
  moderated), with View Details only. Listings of commodities removed
  before this: `node functions/backfill_removed_commodities.js` (lists;
  `--apply` hides them and leaves each farmer the in-app notice).
- Other collections: `products`, `market_prices` (+ `history` subcollection:
  Admin reference prices), `historical_demand` (Admin imports), `reports`,
  `violations`, `audit_logs`, `announcements`, `adminSessions`,
  `notifications`, `market_sales`, `farmerInvites`.
  See `firestore.rules` for the full list and who may read/write what.

## Admin Portal design system (web)

All admin colours, shapes and sizes come from a few shared places â change
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
- `AdminRadii`: `card` 16 (cards and tables, `kAdminTableRadius`; white
  with a soft shadow, `adminCard()`; tables keep their outline for the
  tabs), `control` 10 (buttons, dropdowns, date/year pickers, toggles:
  `kAdminFieldRadius`), `pill` (chips, badges). Text fields and searches
  are pills (`kAdminInputRadius`; 16 when several lines tall; a dropdown in
  a form uses `adminDropdownBorder`). The Admin login and Forgot Password
  fields are pills too (`GlowField(radius: AppTheme.pillRadius)`), their
  buttons rounded rectangles. Header buttons (Announce, Dark Mode, bell): white
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
`pageTitle` 24 â `pageDescription` 13.5 muted â `label()` 14 semibold â
fields 14 (`formTextSize`, `formHint`) â `primaryButton()` (dark green,
white 14 semibold, `formButtonHeight` 50) â `secondaryButton()` (white,
grey outline) â `formLink` (dark green, quieter). Fields are 48 tall
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
Registration is three steps (Choose Role â Your Information â Account
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

**One design for the whole mobile app, buyer and farmer (the user, 2026-11-08):**
the page is Explore's cream (`AppColors.page`, #FEF7EE, through the
theme's scaffold colour); cards, fields, sheets and dialogs stay white
(`AppColors.surface`). The sign-in screens and the splash keep their white
(`AppColors.authPage`: Log In, registration, Choose Role, Forgot Password,
the Google profile form, email verification, waiting for approval, role
selection, the loading and no-internet screens). `AgriAppBar` takes the
colour of its Scaffold, so inner screens' bars are cream and the sign-in
ones white. Tab titles (`PageTitle` and the tabs' own) are 23.5 extra
bold dark green; secondary titles stay `AgriAppBar's`. Shared look: search
bars and filter pills from explore_search_pill.dart (also Notifications'
filters and Messages search), `AgriEmptyState` (24 icon on a pale green
circle, 13.5 title, 11.5 line), `showAgriPopupMenu` (14 corners, 18 icons,
12.5 labels), stars gold (#F5BB24, `ReviewStars`), `LogOutButton` 13 with
an 18 icon. Notifications: compact white cards 8 apart under Today /
Yesterday / the date (12.5), the icon dark green on a pale green circle
(34), title 13.5, text 11.5, time 10.5, a 16 chevron only when it opens
something, unread a 6 gold dot and a stronger title; Mark All as Read a
small icon and 11.5 text. Buyer Reviews: a summary
card and a white card per review. Order Details (every status, one set of
sections): cream page, section titles dark green 11, lines 11.5/12, photo
56. Buyer Profile: the options in three white cards (`ProfileMenuGroup`).
Photos: `ProfileAvatar` and the product cards use `cached_network_image`
(disk cache, decoded at the size shown, a plain pale circle or block while
loading, initials only with no photo); a widget test that shows a photo
URL needs path_provider mocked.

Mobile dark mode (Settings â Dark Mode) comes from `AppColors`' dark values
(2026-11-04 polish): page charcoal `#101214`, cards/panels/fields
`#1B1E20`, borders `#303437`, text `#F2F3F2`, secondary `#A7ADAA`; the
brand stays green (`brand` soft green `#8CCB96` for text/icons, `brandFill`
`#2E7D32` for buttons); highlights (`tint`) only a hint of green;
`adapt()` turns a pale background into charcoal one step above the cards.
Messages use muted red/amber/green in dark. Use the tokens, never fixed
colours, so both modes stay right.

**Buttons and cards (the user's design, 2026-11-07, for the app, the Admin
Portal and the download page):** buttons are rounded rectangles, never
pills (`AppTheme.buttonShape`, 12; `compactButtonShape`, 8, for 36 high or
less; the Admin's 40-high buttons 10; the page's `--btn-radius` 12); the
secondary button is white with a grey outline (`grey(600)`). Cards are
white, 16, a soft shadow and no outline (`AppTheme.card()`, `adminCard()`,
the page's `--radius`; a thin border in dark mode). Text fields, search
bars, chips, badges, filters and toggles stay pills. Two exceptions: "Continue with
Google" on Log In (the user's choice, 2026-11-07) and the small See all on
a farmer's public profile (2026-11-08) are pills.

Mobile app: text fields are pills (`PillInputBorder`), but anything that opens
a dropdown list is a **rounded rectangle** (`AppTheme.dropdownRadius`,
`compactDropdownRadius`, `dropdownDecoration`). An open dropdown list is
only as wide as its longest option, not the whole field (decided by the
user 2026-11-06): use `FittedDropdownField` for a form dropdown, or
`menuWidth: fittedMenuWidth(...)` on a `DropdownButton`
(`fitted_menu_width.dart`; `DropdownButtonFormField` cannot set it). Headers are rectangular bars
(`PageHeader` on the tabs, `AgriAppBar` on inner screens). The tabs' band
is the bottom bar's dark green for both roles (the user's design,
2026-11-08), its lower edge wavy (down near the left, up at a third, down at three
quarters, up at the right) over a gold stripe under the right-hand wave
(`HeaderWavePainter`, points measured from the user's picture; the row 40,
the bell keeping its 48 tap area, the wave 18 more; green #043C1E): the
logo straight on the green, "AgriTrade" white with a gold "+"
(`AgriTradeText(plusColor:)`), white icons, the status bar strip the same
green with light icons, and the bell's unread mark a gold dot with no count
(`NotificationBellButton`). The inner screens' `AgriAppBar` stays white. (A
green gradient was tried on 2026-11-07 and reverted.) Settings: the
**farmer** opens a full page (`FarmerSettingsScreen`, 2026-11-07) from a
small gear beside the Profile title; no tab header has a gear any more.
Its groups: ACCOUNT & SECURITY (Manage Account = `ManageAccountScreen(part:
account)`, Privacy & Security = `part: security`), PREFERENCES (Notification
Settings, Dark Mode switch), SUPPORT & INFORMATION (Send Feedback, Help &
Support, About AgriTrade+ = `AboutScreen`: purpose, installed version, the
AgriTrade+ team and support email, download page, policies), Share
AgriTrade+, then `LogOutButton` (white with a grey outline, not red, the
user's choice 2026-11-08; the confirmation's Log Out stays red); a chevron
only on rows that open a screen.
The bottom bar is a floating dark green pill (`DockedNavBar.color`, fully
round ends, a plain dark shadow; floating again after a day as a full-width
bar, 2026-11-08) with a thin lighter green rim (`rimColor`); the selected
tab sits on a gold pill in dark green (no gold glow under it), the others
white (the user's picture)
(`selectedColor`, also the farmer's +); the user's design, 2026-11-08. It is 54 high, 21 in from the sides, as in the user's picture of
2026-11-08 (it had been 48; the farmer's + 40), the gold pill about 79 x 41,
icons 19, labels 9.5. The buyer's slides away on a scroll down
and back on a scroll up (`FiltersOnScroll(showAfterUp: 24)`); the
farmer's always stays. The **buyer** has no gear (2026-11-04) â the same options are rows on
the Buyer Profile: My Activity (My Reviews, Liked Products, Purchase History
= Orders â Completed), Preferences & Account (Delivery & Pick-up, Manage
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
pill text fields and searches (icon, thin line, text; back to pills on
2026-11-07, from the user's design), rounded-rectangle dropdowns, date
pickers and buttons (10px, `kAdminFieldRadius`), square checkboxes (4px radius),
standalone info icons (no box), every control in a toolbar the same height.

## Analytics Dashboard specifics

- **Market Demand** (`AdminMarketDemandCard`, `admin_price_trend_chart.dart`):
  grouped monthly bars, earlier year `#A5D6A7`, later `#2E7D32`; Admin
  searches a product and picks two years (`AdminYearCompare`). Shows
  "No data to display" states, error + Retry (`DashboardDataService.ordersError`).
- **Years start at the first completed order** (no fixed 2025): used by
  Market Demand and Price Trend (`PriceTrendService.yearsOnRecord`). One year
  on record â one bar/line per month; comparison appears with two years.
- **Market Change Analysis** (`admin_market_trends_card.dart`): Price Trend
  (listings, completed sales, Admin reference prices, imports) + Last 30 Days
  (demand, local supply, market price, possible factors). The **Import
  Historical Data button is hidden** (`_importEnabled = false`); imports older
  than the first completed order are ignored.
- **Export Report** (`export_options_dialog.dart` â `ReportExportService` â
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

**First-time tips** (decided by the user, 2026-11-07; `coach_mark.dart`):
on entering the app the notification question (and the phone's Allow)
comes first, then the home tour. Each screen has its own short tour the
first time it opens, only for what a newcomer would not find alone (no
bell, profile, search or Order Now): buyer home = area filter + Orders
tab; farmer home = + and Orders tab; Orders (`OrdersView.active`, both
roles) = Inventory (farmer) + period filter; Product Details = farm map
(if in view) + Message (not on the farmer's own listing); Chat = + and
hold/slide on a message. Market keeps its scroll hints, Orders its swipe
tutorial. `showCoachMarksOnce` shows one tour at a time, only the steps
whose button is wholly on screen (none: tried again next time), and
waits while a popup is in front. Every hint card has **Skip**, which turns
all tips off (`TutorialTips.skipAll`, `tips_off`); Help & Support â Tips â
"Show tips again" (`TutorialTips.showAgain`) brings them all back. A tour
remembers it was seen as `tour_seen_<screen>` (home: `walkthrough_seen_`,
which logging in to an existing account sets, so only new accounts get it).

## Loading & splash

- Splash (web, mobile, admin): `BrandedLoadingScreen` + `SproutLoadingBar`
  â logo, name, a pale green bar filling dark green with a small sprout at
  the end of the fill, and "Loading AgriTrade+â¦" (no percentage). 3 seconds;
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
  they say: `showAppMessage(context, text, kind: â¦)` or
  `appSnackBar(text, kind: â¦)` (`app_scaffold_messenger.dart`), never a plain
  `SnackBar`. `MessageKind.error` red (failed, refused, a field to fix),
  `success` dark green (done, saved, sent), `warning` amber (out of stock, no
  longer available, turn on location), `info` blue-grey (a heads-up). An
  `err ?? 'Done.'` result picks its kind from `err`.
- Add or update a test with each behaviour change (see `test/` for style:
  named after what the user sees). Screens that read Firestore or Auth can be
  tested whole: services reach Firebase through `FirebaseRefs`
  (`lib/services/firebase_refs.dart`), and a test puts in
  `FakeFirebaseFirestore` and `MockFirebaseAuth` with
  `FirebaseRefs.useForTests` (see `orders_view_test.dart`,
  `login_form_test.dart`). Use `FirebaseRefs.firestore` / `.auth` in new
  service code, not `FirebaseFirestore.instance`.
- `test/design_consistency_test.dart` reads the whole mobile source: no
  pill buttons (only "Continue with Google"), no text under 9.5 (body text
  11 and up; badges 10–10.5; the bottom bar's labels 10.5), white cards
  at `AppTheme.cardRadius`. Change it together with a rule.
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
