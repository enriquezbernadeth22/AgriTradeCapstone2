import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../data/commodity_master_list.dart';
import '../services/harvest_info.dart';
import '../services/image_helper.dart';
import '../services/market_price_helpers.dart';
import 'save_product_button.dart';
import '../theme/app_colors.dart';
import '../l10n/app_language.dart';
import '../services/buyer_area_watcher.dart';
import '../services/buyer_type_watcher.dart';
import '../services/delivery_coverage.dart';
import '../theme/app_theme.dart';
import 'docked_nav_bar.dart';

/// One product in the Buyer Explore grid (the user's design, 2026-11-08):
/// a wide photo with its category on a pale gold badge and the heart, then
/// the name (dark green) with the rating at the right, the price,
/// "Wholesale | Min …" in one pale green chip, and the stock.
///
/// Every card in the grid is the same height — [extentFor] — whatever its
/// name length or whether it has a rating or a wholesale badge. That height
/// is worked out from the column width and the device's text size instead
/// of a fixed aspect ratio, so the text block always has the room its lines
/// need: nothing overflows on a narrow phone or with a larger system font.
class ExploreProductCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback? onTap;

  /// Whether the buyer has liked this listing, and what the heart
  /// on the image does. The heart is only drawn when [onToggleSave] is
  /// given.
  final bool saved;
  final VoidCallback? onToggleSave;

  /// The farmer line (photo and name) at the bottom. Off by default: the
  /// buyer's grids (Explore, Search, Liked) show the product alone, as the
  /// user decided on 2026-11-05; the farmer is on Product Details.
  final bool showFarmer;

  /// Whether a card with no wholesale keeps the empty room of the
  /// "Wholesale | Min" strip, so it lines up with a card that has one. A
  /// grid whose row has no wholesale at all leaves it out (Search, the
  /// user's picture of 2026-11-08), and the row is shorter.
  final bool reserveWholesaleRow;

  const ExploreProductCard({
    super.key,
    required this.data,
    this.onTap,
    this.saved = false,
    this.onToggleSave,
    this.showFarmer = false,
    this.reserveWholesaleRow = true,
  });

  // Width : height of the product image, the same on every card.
  // (Sizes as measured from the user's picture, 2026-11-08.)
  static const double _imageAspectRatio = 1.76;

  /// The card's corners.
  static const double radius = 14;

  // Line heights (font size x height) of the text block at normal text
  // size; they grow with the system font scale.
  static const double _nameLine = 13 * 1.25;
  static const double _priceLine = 14 * 1.3;
  static const double _chipLine = 9.5 * 1.2;
  static const double _stockLine = 9.5 * 1.3;
  static const double _farmerLine = 11 * 1.3;
  static const double _scaledHeight =
      _nameLine + _priceLine + _chipLine + _stockLine + _farmerLine;

  // Everything that does not scale: padding (6 + 9), the gaps between
  // lines (2 + 2 + 4), the strip's own padding (5), the farmer line's gap,
  // divider and gap (6 + 1 + 5) — plus a little slack for font rounding.
  static const double _fixedHeight = 15 + 8 + 5 + 12 + 3;

  /// Height of a card that is [width] wide.
  static double extentFor(
    double width,
    TextScaler textScaler, {
    bool showFarmer = false,
    bool withWholesaleRow = true,
  }) {
    final scale = textScaler.scale(100) / 100;
    var full = width / _imageAspectRatio + _fixedHeight + _scaledHeight * scale;
    // Without the "Wholesale | Min" strip: its line, padding and gap.
    if (!withWholesaleRow) full -= _chipLine * scale + 5 + 2;
    // Without the farmer line: no gap, divider, gap, or the line itself.
    return showFarmer ? full : full - (6 + 1 + 5) - _farmerLine * scale;
  }

  // The card's price is the wholesale one for a buyer who orders in bulk,
  // unless the stock is below the minimum, when it cannot be ordered at it.
  bool _showsWholesale(bool enabled, double? wholesalePrice) =>
      BuyerTypeWatcher.instance.wholesaleFirst &&
      enabled &&
      wholesalePrice != null &&
      wholesalePrice > 0 &&
      ((data['quantity'] as num?) ?? 0) >=
          ((data['wholesaleMinimumQuantity'] as num?) ?? 1);

  @override
  Widget build(BuildContext context) {
    final name = (data['name'] ?? tl('Unnamed Product')).toString();
    final savedCategory = listingCategory(data);
    final category = savedCategory.isEmpty ? 'General' : savedCategory;
    final farmer = (data['farmerName'] ?? tl('Local Farmer')).toString();
    final price = (data['retailPrice'] as num?) ?? (data['price'] as num?) ?? 0;
    final wholesalePrice = (data['wholesalePrice'] as num?)?.toDouble();
    final wholesaleEnabled =
        data['wholesaleEnabled'] == true ||
        (data['wholesaleEnabled'] == null &&
            wholesalePrice != null &&
            wholesalePrice > 0);
    final wholesaleMinimum = (data['wholesaleMinimumQuantity'] as num?) ?? 1;
    final quantity = (data['quantity'] as num?) ?? 0;
    final unit = (data['unit'] as String?) ?? unitForProductName(name);
    final rating = (data['rating'] as num?)?.toDouble();
    final reviewCount = data['reviewCount'];
    final harvested = harvestDateOf(data);
    final rated = rating != null && (reviewCount is! num || reviewCount > 0);

    // White on a soft, wide shadow (the user's design, 2026-11-08).
    final card = Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
      ),
      color: AppColors.surface,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: _imageAspectRatio,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _ProductImage(data: data),
                  if (onToggleSave != null)
                    Positioned(
                      top: 6.5,
                      right: 6.5,
                      child: LikeHeart(
                        liked: saved,
                        onTap: onToggleSave,
                        size: 28,
                      ),
                    ),
                  // The category, on a pale gold badge.
                  Positioned(
                    left: 9,
                    bottom: 4.5,
                    right: 9,
                    child: Align(
                      alignment: Alignment.bottomLeft,
                      child: _CategoryBadge(category: category),
                    ),
                  ),
                  // Why it is near the top of the buyer's feed: the
                  // farmer's delivery reaches the buyer's area.
                  Positioned(
                    left: 7,
                    top: 7,
                    child: ListenableBuilder(
                      listenable: BuyerAreaWatcher.instance,
                      builder: (context, _) =>
                          deliversTo(data, BuyerAreaWatcher.instance.area)
                          ? const _DeliversHereTag()
                          : const SizedBox.shrink(),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(11.5, 6, 11.5, 9),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // The name, with the rating (only once there are
                    // reviews) at the right; the rating never takes more
                    // than half the line, so the name always shows.
                    LayoutBuilder(
                      builder: (context, line) => Row(
                        children: [
                          Expanded(
                            child: Text(
                              withSellingOption(name, data),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                // The bundled family, with its real bold.
                                fontFamily: 'Montserrat',
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: AppColors.brand,
                                height: 1.25,
                              ),
                            ),
                          ),
                          if (rated) ...[
                            const SizedBox(width: 4),
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: line.maxWidth / 2,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.star_rounded,
                                    size: 12.5,
                                    color: DockedNavBar.selectedColor,
                                  ),
                                  const SizedBox(width: 1),
                                  Flexible(
                                    child: Text(
                                      reviewCount == null
                                          ? rating.toStringAsFixed(1)
                                          : '${rating.toStringAsFixed(1)} ($reviewCount)',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 10,
                                        height: 1.3,
                                        fontWeight: FontWeight.w500,
                                        color: AppColors.grey(800),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 2),
                    // Only scales down when the price is genuinely wider
                    // than the card (e.g. ₱12,500.00/kg liveweight).
                    // A buyer who orders in bulk sees the wholesale price
                    // first (see BuyerTypeWatcher).
                    ListenableBuilder(
                      listenable: BuyerTypeWatcher.instance,
                      builder: (context, _) => FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          formatPriceWithUnit(
                            _showsWholesale(wholesaleEnabled, wholesalePrice)
                                ? wholesalePrice!
                                : price,
                            unit,
                          ),
                          maxLines: 1,
                          style: TextStyle(
                            fontFamily: 'Montserrat',
                            color: AppColors.brand,
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ),
                    // "Wholesale" and its minimum. The line is kept even
                    // without wholesale, so the cards line up (unless the
                    // grid leaves it out: [reserveWholesaleRow]).
                    if (wholesaleEnabled || reserveWholesaleRow) ...[
                      const SizedBox(height: 2),
                      Visibility(
                        visible: wholesaleEnabled,
                        maintainSize: true,
                        maintainAnimation: true,
                        maintainState: true,
                        child: _WholesaleChip(
                          minimum: tl('Min {0}', [
                            formatStock(wholesaleMinimum, unit),
                          ]),
                        ),
                      ),
                    ],
                    const Spacer(),
                    Row(
                      children: [
                        Icon(
                          Icons.inventory_2_outlined,
                          size: 12.5,
                          color: AppColors.grey(800),
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            [
                              tl('{0} left', [formatStock(quantity, unit)]),
                              if (harvested != null) harvestLabel(harvested),
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.grey(800),
                              fontSize: 9.5,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (showFarmer) ...[
                      const SizedBox(height: 6),
                      Divider(
                        height: 1,
                        thickness: 0.5,
                        color: AppColors.grey(200),
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 7,
                            backgroundColor: AppColors.accent,
                            child: Icon(
                              Icons.person,
                              size: 9,
                              color: AppColors.brand,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              farmer,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppColors.grey(600),
                                fontSize: 11,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: AppColors.isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
      ),
      child: card,
    );
  }
}

class _ProductImage extends StatelessWidget {
  final Map<String, dynamic> data;

  const _ProductImage({required this.data});

  Widget _placeholder(IconData icon) => Container(
    color: AppColors.accent,
    child: Icon(icon, size: 48, color: AppColors.brand),
  );

  @override
  Widget build(BuildContext context) {
    final base64 = data['imageBase64']?.toString();
    final imageUrl = (data['imageUrl']?.toString().isNotEmpty == true)
        ? data['imageUrl']?.toString()
        : (data['imageUrls'] is List && (data['imageUrls'] as List).isNotEmpty)
        ? (data['imageUrls'] as List).first?.toString()
        : null;

    if (base64 != null && base64.isNotEmpty) {
      return Base64Image(
        base64Data: base64,
        fit: BoxFit.cover,
        fallback: _placeholder(Icons.eco_rounded),
      );
    }
    if (imageUrl != null && imageUrl.isNotEmpty) {
      // From the disk cache once seen (no spinner on the way back to a
      // grid), decoded at about the card's size, fading in when new
      // (2026-11-08).
      return LayoutBuilder(
        builder: (context, box) => CachedNetworkImage(
          imageUrl: imageUrl,
          fit: BoxFit.cover,
          memCacheWidth: box.maxWidth.isFinite
              ? (box.maxWidth * MediaQuery.devicePixelRatioOf(context)).round()
              : null,
          fadeInDuration: const Duration(milliseconds: 150),
          fadeOutDuration: Duration.zero,
          placeholder: (context, _) => Container(color: AppColors.accent),
          errorWidget: (context, _, _) => _placeholder(Icons.broken_image),
        ),
      );
    }
    return _placeholder(Icons.eco_rounded);
  }
}

/// A product's category over its photo: a pale gold pill with a gold
/// outline and its name in dark capitals (no icon, the user's choice,
/// 2026-11-08).
class _CategoryBadge extends StatelessWidget {
  final String category;

  const _CategoryBadge({required this.category});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 18.5,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF1CD),
        borderRadius: BorderRadius.circular(AppTheme.pillRadius),
        border: Border.all(color: const Color(0xFFF5C84A), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              tl(category).toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: 'Montserrat',
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
                color: Color(0xFF1F2A22),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Wholesale | Min 20 kg" under the price: one pale green strip across
/// the card, a box and a cart icon, a thin bar between the two.
class _WholesaleChip extends StatelessWidget {
  final String minimum;

  const _WholesaleChip({required this.minimum});

  @override
  Widget build(BuildContext context) {
    final ink = AppColors.grey(900);
    final style = TextStyle(
      fontSize: 9.5,
      height: 1.2,
      fontWeight: FontWeight.w500,
      color: ink,
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
      decoration: BoxDecoration(
        color: AppColors.isDark ? AppColors.tint : const Color(0xFFEAF2DD),
        borderRadius: BorderRadius.circular(AppTheme.pillRadius),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined, size: 11.5, color: ink),
            const SizedBox(width: 4),
            Text(tl('Wholesale'), maxLines: 1, style: style),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 7),
              child: Container(width: 1, height: 9, color: AppColors.grey(600)),
            ),
            Icon(Icons.shopping_cart_outlined, size: 11.5, color: ink),
            const SizedBox(width: 4),
            Text(minimum, maxLines: 1, style: style),
          ],
        ),
      ),
    );
  }
}

/// "Delivers to you" over a product's photo: the farmer's delivery
/// coverage reaches the signed-in buyer's area.
class _DeliversHereTag extends StatelessWidget {
  const _DeliversHereTag();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(AppTheme.pillRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.local_shipping_outlined, size: 12, color: AppColors.brand),
          const SizedBox(width: 4),
          Text(
            tl('Delivers to you'),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.brand,
            ),
          ),
        ],
      ),
    );
  }
}
