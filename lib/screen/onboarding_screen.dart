import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../l10n/app_language.dart';
import '../l10n/tr.dart';
import '../widgets/agritrade_text.dart';
import '../widgets/onboarding_art.dart';
import '../widgets/onboarding_previews.dart';
import '../widgets/onboarding_reveal.dart';
import '../theme/app_theme.dart';

/// First-run intro carousel — shown once on a fresh install, before the app
/// routes to role selection or login. Each page shows what the app does, on a
/// preview of it. Both "Skip" and "Get Started" leave onboarding the same way
/// — permissions are never requested here; each feature that actually needs
/// one (location, chat notifications, ...) asks for it the first time the
/// user reaches that feature. [onGetStarted] is awaited (and the button
/// disabled meanwhile) because it's the hook the caller uses to persist the
/// "already onboarded" flag before moving on.
class OnboardingScreen extends StatefulWidget {
  final Future<void> Function() onGetStarted;

  const OnboardingScreen({super.key, required this.onGetStarted});

  /// Every picture the four pages show.
  static List<String> get artAssets => [
    'assets/images/onboard.png',
    'assets/images/onboarding/market_scene.png',
    'assets/images/onboarding/avatar_buyer.png',
    'assets/images/onboarding/avatar_farmer.png',
    for (final produce in OnboardingProduce.values) produce.asset,
  ];

  /// Decodes the pages' pictures ahead of time. A picture still decoding when
  /// its page opens appears only after the page's entrance has played, so on
  /// a first open the entrance seemed not to happen at all. Never fails.
  // Awaited inside so that what comes back really is a Future<void>: the
  // Future<List<void>> of Future.wait turned down a caller's `onTimeout: () {}`
  // at run time, and the splash stopped at 100%.
  static Future<void> precacheArt(BuildContext context) async {
    await Future.wait([
      for (final asset in artAssets)
        precacheImage(AssetImage(asset), context, onError: (_, _) {}),
    ]);
  }

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

enum _PageArt { welcome, market, plain, card }

class _OnboardingPage {
  /// Two lines, split by a line break: black, then green.
  final String title;
  final String description;
  final _PageArt art;

  /// The page's preview; the welcome page has its picture instead.
  final Widget? preview;

  const _OnboardingPage(this.title, this.description, this.art, [this.preview]);

  /// The chat page's title is short enough to keep its two parts on one line.
  bool get titleOnOneLine => art == _PageArt.plain;
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const int _pageCount = 4;

  // The cream bar the dots stand on, with Skip and Next under them.
  static const double _barHeight = 106;

  // Next's width; Get Started takes the whole line.
  static const double _buttonWidth = 108;

  // The green hill showing above the bar, in front of the page.
  static const double _hillHeight = 46;

  // How long Get Started shows its loading.
  static const Duration _loadingTime = Duration(milliseconds: 800);

  final PageController _controller = PageController();
  int _index = 0;
  bool _submitting = false;
  bool _loading = false;

  bool get _isLastPage => _index == _pageCount - 1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // AppRouter has these decoded during the splash already; this covers any
    // other way here, and the later pages before they are reached.
    OnboardingScreen.precacheArt(context);
  }

  List<_OnboardingPage> _pages() => [
    _OnboardingPage(
      tl('Welcome to\nAgriTrade+'),
      tl(
        'A direct farm-to-buyer platform that connects farmers and buyers for fresh, local, and fair trade.',
      ),
      _PageArt.welcome,
    ),
    _OnboardingPage(
      tl('Explore\nLocal Products'),
      tl(
        'Browse agricultural products, check prices and details, and discover products from local farmers.',
      ),
      _PageArt.market,
      const OnboardingExplorePreview(),
    ),
    _OnboardingPage(
      tl('Chat &\nOrder'),
      tl(
        'Message farmers directly, ask about their products, and arrange your order with ease.',
      ),
      _PageArt.plain,
      const OnboardingChatPreview(),
    ),
    _OnboardingPage(
      tl('Track Your\nOrders'),
      tl(
        'View your orders, monitor their status, and keep track of your transactions in one place.',
      ),
      _PageArt.card,
      const OnboardingOrdersPreview(),
    ),
  ];

  void _next() {
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.jumpToPage(_index + 1);
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _finish({bool showLoading = false}) async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _loading = showLoading;
    });
    // Leaving onboarding is all but instant, so the button's loading would
    // only flash by: it stays up long enough to be seen.
    if (showLoading) await Future<void>.delayed(_loadingTime);
    if (!mounted) return;
    await widget.onGetStarted();
    if (mounted) {
      setState(() {
        _submitting = false;
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = _pages();
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final barHeight = _barHeight + bottomInset;
    return Scaffold(
      backgroundColor: const Color(0xFFFDFCF8),
      body: Stack(
        children: [
          const Positioned.fill(child: OnboardingBackdrop()),
          // The page runs on behind the hill and the bar.
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                // The welcome page's title already says the name, so it has
                // the logo alone, in the middle.
                _Brand(onWelcome: _index == 0),
                Expanded(
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: pages.length,
                    onPageChanged: (i) => setState(() => _index = i),
                    itemBuilder: (context, i) => OnboardingPageScope(
                      active: i == _index,
                      child: _PageContent(pages[i], bottomSpace: barHeight),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: barHeight + _hillHeight,
            child: const IgnorePointer(
              child: OnboardingFrontHill(barTop: _hillHeight),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: bottomInset,
            height: _barHeight,
            child: _bar(pages.length),
          ),
        ],
      ),
    );
  }

  // The dots, and under them Skip and the button. On the last page there is
  // nothing left to skip: Skip goes, and Get Started takes the whole line.
  Widget _bar(int count) {
    final t = tr(context);
    final change = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 280);
    final button = ElevatedButton(
      onPressed: _submitting
          ? null
          : (_isLastPage ? () => _finish(showLoading: true) : _next),
      style: ElevatedButton.styleFrom(
        backgroundColor: kOnboardingGreen,
        foregroundColor: Colors.white,
        disabledBackgroundColor: kOnboardingGreen,
        elevation: 0,
        minimumSize: const Size(0, 46),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        shape: AppTheme.buttonShape,
      ),
      child: _loading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2.4,
              ),
            )
          : FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                _isLastPage ? t.onboardingGetStarted : t.onboardingNext,
                maxLines: 1,
                style: GoogleFonts.montserrat(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        children: [
          _Dots(count: count, index: _index),
          const SizedBox(height: 10),
          Expanded(
            // On top of each other rather than in a row: as Skip goes and the
            // button widens they cross, and a row would run out of room for
            // a moment.
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 18, 0),
              child: LayoutBuilder(
                builder: (context, constraints) => Stack(
                  alignment: Alignment.center,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: AnimatedSwitcher(
                        duration: change,
                        child: _isLastPage
                            ? const SizedBox.shrink()
                            : TextButton(
                                onPressed: _submitting ? null : _finish,
                                style: TextButton.styleFrom(
                                  foregroundColor: kOnboardingGreen,
                                ),
                                child: Text(
                                  t.onboardingSkip,
                                  style: GoogleFonts.montserrat(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: AnimatedContainer(
                        duration: change,
                        curve: Curves.easeOutCubic,
                        width: _isLastPage
                            ? constraints.maxWidth - 6
                            : _buttonWidth,
                        child: button,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The logo alone in the middle on the welcome page; from then on, at the left
/// with the name beside it.
class _Brand extends StatelessWidget {
  static const double welcomeLogoSize = 52;
  static const double logoSize = 30;

  final bool onWelcome;

  const _Brand({required this.onWelcome});

  @override
  Widget build(BuildContext context) {
    final change = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 320);
    final name = onWelcome
        ? const SizedBox(height: 24)
        : const Padding(
            padding: EdgeInsets.only(left: 9),
            child: AgriTradeText(fontSize: 19),
          );
    // Alone on the welcome page it also sits lower, nearer the title.
    return AnimatedPadding(
      duration: change,
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.fromLTRB(20, onWelcome ? 32 : 12, 20, 4),
      child: AnimatedAlign(
        duration: change,
        curve: Curves.easeOutCubic,
        alignment: onWelcome ? Alignment.center : Alignment.centerLeft,
        // Shrinks with the phone's largest text rather than run off the side.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Alone on the welcome page it is larger; beside the name, the
              // size of the name.
              TweenAnimationBuilder<double>(
                tween: Tween(end: onWelcome ? welcomeLogoSize : logoSize),
                duration: change,
                curve: Curves.easeOutCubic,
                builder: (context, size, _) => AgriTradeLogoMark(size: size),
              ),
              // AnimatedSize cannot take a duration of nothing.
              if (change == Duration.zero)
                name
              else
                AnimatedSize(
                  duration: change,
                  curve: Curves.easeOutCubic,
                  child: name,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  final int count;
  final int index;

  const _Dots({required this.count, required this.index});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: tl('Page {0} of {1}', [index + 1, count]),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < count; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: 11,
              height: 11,
              decoration: BoxDecoration(
                color: i == index ? kOnboardingGreen : const Color(0xFFE2E0D4),
                shape: BoxShape.circle,
              ),
            ),
        ],
      ),
    );
  }
}

class _PageContent extends StatelessWidget {
  final _OnboardingPage page;

  /// How much of the page's bottom the bar covers.
  final double bottomSpace;

  const _PageContent(this.page, {required this.bottomSpace});

  Widget _visual() {
    return switch (page.art) {
      _PageArt.welcome => _WelcomeArt(bottomSpace: bottomSpace),
      _PageArt.market => _MarketArt(
        bottomSpace: bottomSpace,
        preview: page.preview!,
      ),
      _PageArt.plain || _PageArt.card => Padding(
        padding: EdgeInsets.fromLTRB(
          page.art == _PageArt.plain ? 18 : 24,
          0,
          page.art == _PageArt.plain ? 18 : 24,
          bottomSpace + 40,
        ),
        child: _ScaledPreview(page.preview!),
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    // The type follows the phone's width, from the design's 390.
    final scale = (MediaQuery.sizeOf(context).width / 390).clamp(0.82, 1.12);
    final lines = page.title.split('\n');
    final titleSize = (page.art == _PageArt.welcome ? 30 : 28) * scale;
    TextStyle titleStyle(Color color) => GoogleFonts.montserrat(
      fontSize: titleSize,
      fontWeight: FontWeight.w800,
      color: color,
      height: 1.12,
    );

    final header = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 26),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: 2 * scale),
          if (page.titleOnOneLine)
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(lines.first, style: titleStyle(const Color(0xFF232624))),
                  SizedBox(width: titleSize * 0.28),
                  Text(lines.last, style: titleStyle(kOnboardingGreen)),
                ],
              ),
            )
          else ...[
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                lines.first,
                style: titleStyle(const Color(0xFF232624)),
              ),
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(lines.last, style: titleStyle(kOnboardingGreen)),
            ),
          ],
          const SizedBox(height: 3),
          OnboardingSwoosh(width: 190 * scale),
          SizedBox(height: 10 * scale),
          Text(
            page.description,
            textAlign: TextAlign.center,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.montserrat(
              fontSize: 13 * scale,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF2E332F),
              height: 1.38,
            ),
          ),
          SizedBox(height: 12 * scale),
        ],
      ),
    );

    if (page.art == _PageArt.welcome) {
      return CustomMultiChildLayout(
        delegate: _WelcomeLayout(bottomSpace: bottomSpace),
        children: [
          LayoutId(id: _WelcomeLayout.header, child: header),
          LayoutId(id: _WelcomeLayout.art, child: _visual()),
        ],
      );
    }
    return Column(
      children: [
        header,
        Expanded(child: _visual()),
      ],
    );
  }
}

/// The welcome page: the picture at the bottom, as tall as it can use, and the
/// title and text right under the logo. On a tall phone the room left over
/// goes between the text and the picture, so the logo and the title stay
/// together.
class _WelcomeLayout extends MultiChildLayoutDelegate {
  static const Object header = 'header';
  static const Object art = 'art';

  final double bottomSpace;

  _WelcomeLayout({required this.bottomSpace});

  @override
  void performLayout(Size size) {
    final headerSize = layoutChild(
      header,
      BoxConstraints(
        minWidth: size.width,
        maxWidth: size.width,
        maxHeight: size.height,
      ),
    );
    final below = math.max(0.0, size.height - headerSize.height);
    final artHeight = math.min(
      _WelcomeArt.tallest(size.width, bottomSpace),
      below,
    );
    positionChild(header, Offset.zero);
    layoutChild(art, BoxConstraints.tight(Size(size.width, artHeight)));
    positionChild(art, Offset(0, size.height - artHeight));
  }

  @override
  bool shouldRelayout(_WelcomeLayout oldDelegate) =>
      oldDelegate.bottomSpace != bottomSpace;
}

/// The farmer and the buyer, half body: the hill in front of them stands at
/// their waists, whatever the phone's height.
class _WelcomeArt extends StatelessWidget {
  // The picture is square with room at its sides. The top of the hat to just
  // under the crate is this much of its height.
  static const double _halfBody = 0.6;

  // How far down the bar's top the hill reaches over the picture.
  static const double _hillCover = 26;
  static const double _minZoom = 1.2;

  // Any closer and the farmer's elbow and the phone would be cut off.
  static const double _maxZoom = 1.6;

  final double bottomSpace;

  const _WelcomeArt({required this.bottomSpace});

  /// The most room the two can use: the picture at its closest, down to their
  /// waists, plus what the hill and the bar cover.
  static double tallest(double width, double bottomSpace) =>
      width * _maxZoom * _halfBody + _hillCover + bottomSpace;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        // Down to the hill's top.
        final room = constraints.maxHeight - bottomSpace - _hillCover;
        final side = (room / _halfBody).clamp(
          width * _minZoom,
          width * _maxZoom,
        );
        // On a tall phone the room left over goes above the two, so the
        // hill still meets them at the waist.
        final top = math.max(0.0, room - side * _halfBody);
        final picture = Image.asset(
          'assets/images/onboard.png',
          width: side,
          height: side,
          filterQuality: FilterQuality.medium,
        );
        return ExcludeSemantics(
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned(
                top: top,
                left: (width - side) / 2,
                width: side,
                height: side,
                child: OnboardingReveal(
                  durationMs: 560,
                  scaleFrom: 0.96,
                  child: SizedBox.square(
                    dimension: side,
                    child: Stack(
                      children: [
                        picture,
                        // The crate is part of the picture: a copy of just that
                        // part rises onto it, and at rest cannot be told apart.
                        OnboardingMotion(
                          delayMs: 200,
                          durationMs: 640,
                          builder: (context, progress) => Transform.translate(
                            offset: Offset(0, side * 0.022 * (1 - progress)),
                            child: ClipPath(
                              clipper: const _CrateClipper(),
                              child: picture,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// The crate and its produce in the welcome picture, leaving out the hands
// holding it.
class _CrateClipper extends CustomClipper<Path> {
  const _CrateClipper();

  static const double _pictureSize = 1254;
  static const List<Offset> _outline = [
    Offset(345, 425),
    Offset(395, 395),
    Offset(430, 385),
    Offset(530, 380),
    Offset(640, 372),
    Offset(750, 418),
    Offset(748, 545),
    Offset(700, 572),
    Offset(660, 605),
    Offset(510, 605),
    Offset(510, 560),
    Offset(455, 535),
    Offset(390, 540),
    Offset(358, 540),
  ];

  @override
  Path getClip(Size size) {
    final scale = size.width / _pictureSize;
    return Path()
      ..addPolygon([for (final point in _outline) point * scale], true);
  }

  @override
  bool shouldReclip(_CrateClipper oldClipper) => false;
}

/// The market stall and crates along the left and bottom, with the preview
/// standing in front of them.
class _MarketArt extends StatelessWidget {
  final double bottomSpace;
  final Widget preview;

  const _MarketArt({required this.bottomSpace, required this.preview});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              bottom: bottomSpace - 6,
              child: ExcludeSemantics(
                child: Image.asset(
                  'assets/images/onboarding/market_scene.png',
                  width: width,
                  fit: BoxFit.fitWidth,
                  filterQuality: FilterQuality.medium,
                ),
              ),
            ),
            Positioned(
              left: width * 0.18,
              right: width * 0.05,
              top: 14,
              bottom: bottomSpace + 34,
              // It stands on the crates, however tall the phone is.
              child: _ScaledPreview(preview, alignment: Alignment.bottomCenter),
            ),
          ],
        );
      },
    );
  }
}

/// A preview as a picture: scaled to the room there is, whatever the phone's
/// size or text setting, and not tappable or read out as real content.
class _ScaledPreview extends StatelessWidget {
  // A preview grows with a wide phone, up to this.
  static const double _maxWidth = 372;

  final Alignment alignment;
  final Widget child;

  const _ScaledPreview(this.child, {this.alignment = Alignment.topCenter});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => Align(
        alignment: alignment,
        child: SizedBox(
          width: math.min(constraints.maxWidth, _maxWidth),
          height: constraints.maxHeight,
          child: FittedBox(
            alignment: alignment,
            child: MediaQuery.withNoTextScaling(
              child: IgnorePointer(child: ExcludeSemantics(child: child)),
            ),
          ),
        ),
      ),
    );
  }
}
