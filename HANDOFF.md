# AgriTrade+ handoff: design and logic rules

This file is for the next coding agent. Read **AGENTS.md** first: it holds
the full rules, and this file only sums up what must stay consistent.
State as of 2026-11-05. The capstone defense is 2026-11-11.

## 1. How to work in this repo

- The user writes in Tagalog/Taglish. Answer in the same language, short and
  plain. They usually send a screenshot with one line of request.
- **Do not commit, push or deploy unless the user asks.** When they ask, ask
  which remote to use.
- Never show fabricated or sample data. An empty state says it is empty.
- Add or update a test with each behaviour change. Tests live in `test/`,
  one file per feature, named after what the user sees.
- Before you finish, check all three:
  - `flutter analyze` says "No issues found!"
  - `flutter test` passes (844 tests now).
  - `cd functions && npm test` passes (128 tests).
- **Formatting:**
  - Only `dart format` the files you edited, and only if that file was
    already formatted in HEAD.
  - Never format a whole folder. Some files under `lib/services/` are
    committed unformatted.
- Environment: Windows + Git Bash, with no python. Use perl, sed or the
  editor's own edit tools.
- **Firestore rules:**
  - Java is missing, so `firestore_tests` cannot run.
  - Check that the rules compile with
    `firebase deploy --only firestore:rules --dry-run --project agritrade-bef87`.
- Comments are full sentences explaining *why*. Use `///` doc comments on
  public widgets and functions.
- **Screen text:**
  - The app is English only.
  - Write screen text as `tl('English text')`, with values as `{0}`.
  - Never translate values saved to Firestore.

## 2. Product shape

- One Flutter codebase, two products:
  - The **mobile app** (Android, portrait only) for farmers and buyers.
    Its entry is `AppRouter`.
  - The **web Admin Portal**. Its entry is `AdminSessionGate`, chosen by
    `kIsWeb` in `app_bootstrap.dart`.
- **Backend:**
  - Firebase project `agritrade-bef87`.
  - Cloud Functions run Node 22 in `asia-southeast1`. Testable pure logic
    goes in `functions/*_logic.js`.
  - Images go to Cloudinary.
- Roles live in `users/{uid}.role`: `farmer`, `buyer` or `admin`.

## 3. Mobile design system (do not invent new sizes or colours)

### Colours (`AppTheme`, `AppColors`)

| Token | Value | Use |
|---|---|---|
| `AppTheme.dark` | rgb(14,50,16) | Main dark green: buttons and the logo text |
| `AppTheme.mid` | `#2E7D32` | Brand green |
| `AppTheme.accent` | `#DCEDC8` | Stronger pale green: chips and badges |
| `AppTheme.tint` | `#F1F7EC` | Soft highlight boxes and selected rows |
| `AppTheme.surface` | `#F7F8F6` | Off-white page behind cards |

Main tabs and forms sit on a white page.

Dark mode uses the `AppColors` tokens:

| Element | Value |
|---|---|
| Page | `#101214` |
| Cards and fields | `#1B1E20` |
| Borders | `#303437` |
| Text | `#F2F3F2` |
| Secondary text | `#A7ADAA` |
| Brand text | `#8CCB96` |
| Brand fill | `#2E7D32` |

Always use the tokens, never fixed colours, so both modes stay right.

### Fonts and forms

- The font is **Montserrat**.
- Forms use the FORMS section of `AppTheme`:

| Part | Style |
|---|---|
| `pageTitle` | 24 |
| `pageDescription` | 13.5, muted |
| `label()` | 14, semibold |
| Field text | 14 |
| Field height | 48 (`formFieldHeight`) |
| `primaryButton()` | Dark green, white 14 semibold, height 50 |
| `secondaryButton()` | White with a grey outline |
| `formLink` | Dark green, quieter |

- Form spacing:

| Gap | Size |
|---|---|
| Page margin | 24 |
| Label gap | 8 |
| Field gap | 16 |
| Section gap | 24 |

- **Fields** use `GlowField`, `AgriFormField` or `formFieldDecoration`.
  - At rest a field has a thin grey outline.
  - Typed in, the outline goes and a soft green glow shows
    (`glowFieldWrapper`, `FormFieldGlow`).
  - Never use a green focused outline.
  - Errors go on their own line under the field.
- Text fields are pills. Anything that opens a dropdown list is a rounded
  rectangle (`AppTheme.dropdownRadius`).

### Screen parts

- **Headers:**
  - The tabs use `PageHeader`.
  - Inner screens use `AgriAppBar`.
  - Account screens use `AgriAppBar(titleWidget: AgriTradeHeaderBrand())`.
- **System messages:**
  - Always use `showAppMessage(context, text, kind: …)` or `appSnackBar`.
    Never use a plain `SnackBar`.
  - Kinds: error is red, success is dark green, warning is amber, info is
    blue-grey.
- **Popups:** `AgriDialog` and `showAgriConfirm`. The icon is black on a
  grey circle, and the tone shows on the buttons.
- **Empty pages:** `AgriEmptyState` (an icon, with no picture).
- **Pull to refresh:** `AgriRefreshIndicator`. When offline it says there
  is no internet instead of loading.
- **Splash:** `BrandedLoadingScreen` with `SproutLoadingBar`.
  - It shows the logo and the name.
  - The bar is pale green and fills dark green, with a sprout at the end
    of the fill.
  - It reads "Loading AgriTrade+…", with no percentage, and lasts 3
    seconds.
  - `web/index.html` has a pixel-matched HTML copy. Change both together.

## 4. Admin Portal design system (web)

- Change the shared places below, never single screens:
  - `AdminPalette`, read with `AdminThemeScope.of(context).palette`, or
    `AdminPalette.fallback(context)` in dialogs.
  - `adminThemeData`.
  - `AdminRadii`.
  - `admin_filter_controls.dart`.
- **Look:**
  - Neutral black, white and grey.
  - Dark green **only** for buttons, the active item and selected items.
  - Pale green only in the Overview icon boxes.
- **Font:** **Inter** (`kAdminFontFamily`, `adminFont()`).
- **Text colours:**
  - Titles, headings and field labels use `palette.heading` (bold dark
    green).
  - Small spaced capitals use `palette.eyebrow` (medium green).
  - Body text is near-black.
- **Radius:**
  - Cards, tables, buttons, inputs, search, dropdowns and date pickers are
    all 10 (`kAdminFieldRadius`).
  - Only chips and badges are pills.
  - Checkboxes are square, with a 4px radius.
- **Controls:**
  - Height is 40 (`kAdminControlHeight`). Every control in a toolbar is the
    same height.
  - Inputs sit on `AdminInputGlow` with `adminFieldDecoration` (16px inset,
    16px icon).
  - Use the shared controls: `AdminPillDropdown`, `AdminPillSearch`,
    `AdminMonthPill`, `AdminYearPill`, `AdminPillToggle` and
    `AdminGreyMenu`.
- **Buttons:**
  - Primary is filled dark green (`adminActionColor`).
  - Secondary is outlined white with a grey border.
  - Tertiary is text only, near-black.
  - Destructive is red.
- **Sidebar** (`admin_sidebar.dart`):
  - A white top with no green band.
  - Groups MAIN and MODERATION, in dark green, with a line between groups.
  - The open page is a dark green block with 8px corners.
- **Notices:**
  - `AdminAlertToasts` pop up at the top right for 6 s.
  - They stay while hovered, show at most 3, and a click opens the page.
- **Loading:** `AdminLoadingBar`. It never fills, and it never delays real
  data.
- **Info icons** stand alone, with no box.

## 5. Business logic that must not change

### Orders (`orders/{id}`)

- One order is **one product**. Its commodity, price and unit are frozen
  when it is placed.
- The status flow is `pending → confirmed → shipped → completed`, plus
  `rejected` and `cancelled`.
- **Stock comes off when the farmer confirms**, not when the buyer places
  the order:
  - Placing an order only checks there is enough (`stockOnConfirm: true`).
  - Confirming takes the stock in the same transaction (`stockDeductedAt`).
    The rules enforce it in `farmerStockStepOk`.
  - On cancel, stock goes back only if the order took it (`orderTookStock`,
    `order_stock_logic.js`).
- **Cancelling:**
  - A buyer can cancel while the order is pending.
  - A farmer can cancel a confirmed order, with a reason.
  - A pending order with no answer for 3 days is auto-cancelled.
- **Finishing:**
  - The buyer confirms "Order Received".
  - The farmer can complete the order only 3 days after shipping
    (`kBuyerConfirmWindow`).
- **Pick-up:** for a pick-up order, the farmer shares the address and pin
  on confirming (`orders/{id}/private/farmer`). The buyer then sees
  `PickupPlaceCard`.
- `firestore.rules` checks the order price against the listing. Keep it in
  step with `PricingTierService`.

### Analytics

- **Analytics count completed orders only.**
- Demand is the number of completed orders, never kilos.
- **Exception:** Top-Selling (Admin) and Best-Selling (Farmer) rank by
  quantity sold per product and unit, for example "Eggplant (kg)". Units
  are never added together.
- Years start at the first completed order. No year is fixed.
- A product counts under its commodity (`demandProduct`), so "Native
  Chicken" counts as Chicken.

### Buyer feed

- Listings that deliver to the buyer's saved area come first
  (`deliveringFirst`). Nothing is hidden.
- Inside that order, the products the buyer buys most come first
  (`boughtFirst`). Every refresh shuffles them (`_feedMix`).

### Listings

- A listing has up to 5 photos.
- Livestock is sold **live only**. `sellingOption` is `'live'`.

### Chat

- **Reactions:** `likes.{uid}` holds one of `heart`, `like`, `wow`, `sad`
  or `angry`. The rules allow exactly these.
- **Swipe to reply:** a message slides under the finger to reply. Received
  messages slide right and your own slide left (`SwipeToReply`).
- **Holding a message:**
  - The chat behind it blurs.
  - Reactions show above the message.
  - The menu under it has Reply, Copy (text only), Pin or Unpin, Unsend
    (your own only) and Report (theirs only). See `message_actions.dart`.
- **Unsend:**
  - Clears the content and sets `unsent: true`.
  - Your side shows "You unsent a message".
- **Pin:**
  - A conversation has one pinned message (`pinnedMessage`).
  - It shows as a banner with an ×.
- **Report:** creates a `reports` doc with `targetType: 'message'`.
- **Limits:**
  - Text is at most 1,000 characters.
  - Video is at most 100 MB and up to 30 seconds when recorded.

### Login

- An unregistered email gets "This email is not registered".
- A Google-only account is told to use Continue with Google.
- Both come from `reportLoginFailure` in `functions/login_throttle.js`.
  The user accepted that this reveals whether an email is registered.
- After 5 wrong passwords, password login for that email pauses for 5
  minutes.
- **Continue with Google:** Cancel on the profile form goes back to Choose
  Role and stays signed in.

### App behaviour

- **Offline:**
  - Opened offline, the app stays on the splash with Try Again, and carries
    on by itself once online.
  - Offline mid-session, what is on screen stays.
- Tapping outside a text field closes the keyboard (`TapOutsideToUnfocus`
  in `main.dart`).

## 6. Not done yet / watch out

- **Nothing from this round is committed or deployed.**
- **Pin, Unsend, Report message and pick-up sharing** need the new rules:
  - They need `firestore.rules` deployed together with a new APK.
  - Stock-on-confirm also needs the new functions.
  - Run: `firebase deploy --only firestore:rules,functions,hosting --project agritrade-bef87`
- **"Not registered" login** needs the new function deployed. Until then
  it shows "Incorrect email or password".
- **Before deploying hosting,** copy the APK in
  (see "Commands" in AGENTS.md).
- **Not yet checked on a real phone:** chat (swipe, hold menu, pin,
  unsend), login messages, the map distance and video upload.
- **Dark mode** has not been checked on every Admin page.
