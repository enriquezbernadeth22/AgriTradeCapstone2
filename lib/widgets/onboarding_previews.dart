import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../l10n/app_language.dart';
import '../l10n/tr.dart';
import '../theme/app_theme.dart';
import 'onboarding_art.dart';
import 'onboarding_reveal.dart';
import 'order_status_pager.dart';
import 'shimmer.dart';

/// The width each preview is laid out at. The onboarding page scales the whole
/// preview to the room it has, like a picture.
const double kOnboardingPreviewWidth = 342;

/// The onboarding's produce pictures, replaced by putting a file of the same
/// name in assets/images/onboarding.
enum OnboardingProduce {
  corn('corn'),
  coconut('coconut'),
  tomato('tomato'),
  vegetables('vegetables');

  final String file;
  const OnboardingProduce(this.file);

  String get asset => 'assets/images/onboarding/$file.png';
}

/// The one green of the onboarding's text and controls: the app's dark green.
const Color kOnboardingGreen = AppTheme.dark;
const Color _ink = Color(0xFF141A15);
const Color _priceInk = kOnboardingGreen;
const Color _muted = Color(0xFF6B716B);
const Color _chip = Color(0xFFF2F3EE);
const Color _surface = Color(0xFFFFFEFB);
const Color _question = Color(0xFFEEF6DC);
const Color _ticks = Color(0xFF3B7DD8);

List<BoxShadow> _softShadow([double opacity = 0.07]) => [
  BoxShadow(
    color: Colors.black.withValues(alpha: opacity),
    blurRadius: 16,
    offset: const Offset(0, 5),
  ),
];

BoxDecoration _panel() => BoxDecoration(
  color: _surface,
  borderRadius: BorderRadius.circular(24),
  boxShadow: _softShadow(0.08),
);

BoxDecoration _innerCard([double radius = 14]) => BoxDecoration(
  color: Colors.white,
  borderRadius: BorderRadius.circular(radius),
  boxShadow: _softShadow(),
);

TextStyle _text(
  double size, {
  FontWeight weight = FontWeight.w500,
  Color color = _ink,
}) => GoogleFonts.montserrat(fontSize: size, fontWeight: weight, color: color);

Widget _panelTitle(String title) => Text(
  title,
  maxLines: 1,
  overflow: TextOverflow.ellipsis,
  style: _text(19, weight: FontWeight.w700),
);

Widget _photo(
  OnboardingProduce produce, {
  required double width,
  required double height,
  double radius = 10,
}) => ClipRRect(
  borderRadius: BorderRadius.circular(radius),
  child: Image.asset(
    produce.asset,
    width: width,
    height: height,
    fit: BoxFit.cover,
    filterQuality: FilterQuality.medium,
  ),
);

Widget _pill(
  String label, {
  double highlight = 0,
  double fontSize = 11.5,
  EdgeInsets padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
}) => Container(
  padding: padding,
  decoration: BoxDecoration(
    color: Color.lerp(_chip, kOnboardingGreen, highlight),
    borderRadius: BorderRadius.circular(30),
  ),
  child: Text(
    label,
    maxLines: 1,
    style: _text(
      fontSize,
      weight: FontWeight.w600,
      color: Color.lerp(_priceInk, Colors.white, highlight)!,
    ),
  ),
);

/// Page two: Explore, tilted a little: the search bar and four products.
class OnboardingExplorePreview extends StatelessWidget {
  /// The card's width, narrower than the other pages': it stands beside the
  /// market stall.
  static const double width = 282;

  const OnboardingExplorePreview({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Transform.rotate(
            angle: 0.03,
            child: OnboardingReveal(
              durationMs: 300,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: _panel(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    OnboardingReveal(
                      delayMs: 120,
                      from: const Offset(0, 10),
                      child: Container(
                        height: 42,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: _chip,
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.search,
                              size: 22,
                              color: kOnboardingGreen,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                tl('Search products...'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: _text(12.5, color: _muted),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Row(
                      children: [
                        _ProductCard(
                          produce: OnboardingProduce.corn,
                          delayMs: 300,
                        ),
                        SizedBox(width: 10),
                        _ProductCard(
                          produce: OnboardingProduce.coconut,
                          delayMs: 400,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Row(
                      children: [
                        _ProductCard(
                          produce: OnboardingProduce.tomato,
                          delayMs: 500,
                        ),
                        SizedBox(width: 10),
                        _ProductCard(
                          produce: OnboardingProduce.vegetables,
                          delayMs: 600,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Positioned(
            top: -24,
            right: -8,
            child: OnboardingReveal(
              delayMs: 760,
              child: OnboardingSparks(size: 34, color: Color(0xFFF6C928)),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  final OnboardingProduce produce;
  final int delayMs;

  const _ProductCard({required this.produce, required this.delayMs});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: OnboardingReveal(
        delayMs: delayMs,
        from: const Offset(0, 14),
        child: Container(
          padding: const EdgeInsets.all(5),
          decoration: _innerCard(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _photo(produce, width: double.infinity, height: 72, radius: 12),
              const Padding(
                padding: EdgeInsets.fromLTRB(5, 8, 3, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(width: 62, height: 11),
                    SizedBox(height: 6),
                    SkeletonBox(width: 86, height: 12),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Page three: a buyer and a farmer talking, then the product, Send Options
/// and the receipt that follows a completed order.
class OnboardingChatPreview extends StatelessWidget {
  const OnboardingChatPreview({super.key});

  Widget _avatar(String file) => Container(
    width: 58,
    height: 58,
    padding: const EdgeInsets.all(2.5),
    decoration: const BoxDecoration(
      color: kOnboardingGreen,
      shape: BoxShape.circle,
    ),
    child: ClipOval(
      child: Image.asset(
        'assets/images/onboarding/$file.png',
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
      ),
    ),
  );

  Widget _bubble(String text, String time, {required Color color}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 7),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(18),
        boxShadow: _softShadow(0.06),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              text,
              style: _text(
                13.5,
                weight: FontWeight.w700,
              ).copyWith(height: 1.25),
            ),
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(time, style: _text(9.5, color: _muted)),
              const SizedBox(width: 3),
              const Icon(Icons.done_all_rounded, size: 13, color: _ticks),
            ],
          ),
        ],
      ),
    );
  }

  Widget _product() {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 18),
      decoration: _innerCard(20),
      child: Row(
        children: [
          _photo(OnboardingProduce.corn, width: 84, height: 50, radius: 12),
          const SizedBox(width: 12),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 70, height: 13),
              SizedBox(height: 8),
              SkeletonBox(width: 110, height: 15),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sendOptions() {
    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: kOnboardingGreen,
        borderRadius: BorderRadius.circular(30),
        boxShadow: _softShadow(0.14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.sell_outlined, size: 19, color: Colors.white),
          const SizedBox(width: 8),
          Text(
            tl('Send Options'),
            style: _text(14, weight: FontWeight.w600, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _receipt() {
    return Transform.rotate(
      angle: 0.02,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6),
          boxShadow: _softShadow(0.1),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.description_outlined,
              size: 26,
              color: kOnboardingGreen,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tl('Transaction Receipt'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _text(12, weight: FontWeight.w700),
                  ),
                  const SizedBox(height: 5),
                  const SkeletonBox(width: 96, height: 11),
                ],
              ),
            ),
            Container(
              width: 26,
              height: 26,
              decoration: const BoxDecoration(
                color: kOnboardingGreen,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check, size: 16, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: kOnboardingPreviewWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OnboardingReveal(
            from: const Offset(0, 10),
            child: Row(
              children: [
                _avatar('avatar_buyer'),
                const SizedBox(width: 12),
                Expanded(
                  child: _bubble(
                    tl('Is the corn still available?'),
                    '10:24 AM',
                    color: _question,
                  ),
                ),
                const SizedBox(width: 74),
              ],
            ),
          ),
          const SizedBox(height: 8),
          OnboardingReveal(
            delayMs: 280,
            from: const Offset(0, 10),
            child: Row(
              children: [
                const SizedBox(width: 26),
                Expanded(
                  child: _bubble(
                    tl('Yes, it\'s available! We can deliver tomorrow. 😋'),
                    '10:28 AM',
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                _avatar('avatar_farmer'),
              ],
            ),
          ),
          const SizedBox(height: 6),
          OnboardingReveal(
            delayMs: 560,
            from: const Offset(0, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.only(left: 2),
                  child: Row(
                    children: [
                      OnboardingSparks(
                        size: 26,
                        color: kOnboardingGreen,
                        toRight: false,
                      ),
                      Spacer(),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 10, right: 38),
                  child: _product(),
                ),
              ],
            ),
          ),
          Transform.translate(
            offset: const Offset(0, -10),
            child: Padding(
              padding: const EdgeInsets.only(left: 8, right: 70),
              child: OnboardingReveal(
                delayMs: 780,
                scaleFrom: 0.88,
                curve: Curves.easeOutBack,
                child: _sendOptions(),
              ),
            ),
          ),
          OnboardingReveal(
            delayMs: 1000,
            from: const Offset(0, 22),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(width: 18),
                const OnboardingDashedArrow(size: Size(38, 44)),
                const SizedBox(width: 10),
                Expanded(child: _receipt()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Page four: Orders, with the status tabs and one pending order.
class OnboardingOrdersPreview extends StatelessWidget {
  const OnboardingOrdersPreview({super.key});

  Widget _order(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: _innerCard(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _photo(OnboardingProduce.corn, width: 58, height: 58),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: SkeletonBox(width: 76, height: 14),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFBEFC4),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'PENDING',
                            style: _text(
                              9,
                              weight: FontWeight.w700,
                              color: const Color(0xFFB8860B),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 9),
                    const SkeletonBox(width: 136, height: 11),
                    const SizedBox(height: 8),
                    const SkeletonBox(width: 104, height: 11),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(height: 1, color: const Color(0xFFEDEEE8)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tl('Total'), style: _text(11.5, color: _muted)),
                    const SizedBox(height: 6),
                    const SkeletonBox(width: 92, height: 16),
                  ],
                ),
              ),
              Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: kOnboardingGreen),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.description_outlined,
                      size: 18,
                      color: kOnboardingGreen,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      tr(context).details,
                      style: _text(
                        12.5,
                        weight: FontWeight.w600,
                        color: _priceInk,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: kOnboardingPreviewWidth,
      padding: const EdgeInsets.fromLTRB(6, 16, 6, 6),
      decoration: _panel(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 14),
            child: _panelTitle(tr(context).navOrders),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                for (final (i, tab) in kOrderStatusTabs.indexed) ...[
                  if (i > 0) const SizedBox(width: 5),
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: OnboardingMotion(
                        delayMs: 160,
                        durationMs: 460,
                        builder: (context, progress) => _pill(
                          tab.labelIn(context),
                          highlight: i == 0 ? progress : 0,
                          fontSize: 11,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 7,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          OnboardingReveal(
            delayMs: 240,
            durationMs: 440,
            from: const Offset(30, 0),
            child: _order(context),
          ),
        ],
      ),
    );
  }
}
