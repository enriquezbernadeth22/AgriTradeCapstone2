import 'package:flutter/material.dart';
import 'app_scaffold_messenger.dart';

import '../services/saved_products_service.dart';
import '../theme/app_colors.dart';
import '../l10n/app_language.dart';

/// The Liked Products heart: an outline in dark green when the product is
/// not liked, a filled red heart when it is, with a small bounce on tap.
///
/// Purely visual — [liked] and [onTap] come from the caller. Sits on a
/// white circle so it stays readable on top of any product photo.
class LikeHeart extends StatefulWidget {
  final bool liked;
  final VoidCallback? onTap;

  /// Diameter of the white circle; the heart is a little over half of it.
  final double size;

  /// The heart's own size, when not a little over half of [size].
  final double? iconSize;

  /// A tap area larger than the circle (it stays [size] to the eye), e.g.
  /// 44 around a 36 circle.
  final double? tapTarget;

  /// The circle's fill and shadow, when not the plain white on a soft
  /// shadow of the product cards.
  final Color? background;
  final double elevation;

  const LikeHeart({
    super.key,
    required this.liked,
    required this.onTap,
    this.size = 34,
    this.iconSize,
    this.tapTarget,
    this.background,
    this.elevation = 1.5,
  });

  /// The colour of a liked heart.
  static const Color likedColor = Color(0xFFE53935);

  @override
  State<LikeHeart> createState() => _LikeHeartState();
}

class _LikeHeartState extends State<LikeHeart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bounce = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  );
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 1, end: 1.3), weight: 45),
    TweenSequenceItem(tween: Tween(begin: 1.3, end: 1), weight: 55),
  ]).animate(CurvedAnimation(parent: _bounce, curve: Curves.easeOut));

  @override
  void dispose() {
    _bounce.dispose();
    super.dispose();
  }

  void _tap() {
    _bounce.forward(from: 0);
    widget.onTap!();
  }

  @override
  Widget build(BuildContext context) {
    final circle = Material(
      color: widget.background ?? AppColors.surface,
      shape: const CircleBorder(),
      elevation: widget.elevation,
      shadowColor: Colors.black.withValues(alpha: 0.35),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onTap == null ? null : _tap,
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: Center(
            child: ScaleTransition(
              scale: _scale,
              child: Icon(
                widget.liked
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                size: widget.iconSize ?? widget.size * 0.58,
                color: widget.liked ? LikeHeart.likedColor : AppColors.brand,
              ),
            ),
          ),
        ),
      ),
    );
    final target = widget.tapTarget;
    return Tooltip(
      message: widget.liked
          ? tl('Remove from Liked Products')
          : tl('Like product'),
      child: target == null || target <= widget.size
          ? circle
          // The whole square answers a tap; only the circle shows.
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onTap == null ? null : _tap,
              child: SizedBox.square(
                dimension: target,
                child: Center(child: circle),
              ),
            ),
    );
  }
}

/// Likes or unlikes [productId] for the signed-in buyer and confirms it
/// with the usual snackbar. Used by every heart in the app, so they all
/// behave — and read — the same.
Future<void> toggleLikedProduct(BuildContext context, String productId) async {
  final messenger = ScaffoldMessenger.of(context);
  final result = await LikedProducts.instance.toggle(productId);
  messenger
    ..clearSnackBars()
    ..showSnackBar(
      appSnackBar(
        result.error ??
            (result.liked
                ? tl('Added to Liked Products')
                : tl('Removed from Liked Products')),
        kind: result.error == null ? MessageKind.success : MessageKind.error,
        duration: const Duration(seconds: 2),
      ),
    );
}

/// The heart on Product Details, wired to the buyer's real liked state
/// ([LikedProducts]). Draws nothing for anyone who isn't a buyer.
///
/// Drawn like the photo's other round buttons (the user's sizes,
/// 2026-11-08): a 36 circle, white at 95%, a very soft shadow, an 18
/// heart, and a 44 tap area.
class SaveProductButton extends StatefulWidget {
  final String productId;

  const SaveProductButton({super.key, required this.productId});

  static const double size = 36;
  static const double iconSize = 18;
  static const double tapTarget = 44;

  @override
  State<SaveProductButton> createState() => _SaveProductButtonState();
}

class _SaveProductButtonState extends State<SaveProductButton> {
  @override
  void initState() {
    super.initState();
    LikedProducts.instance.start();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: LikedProducts.instance,
      builder: (context, _) {
        final likes = LikedProducts.instance;
        if (!likes.canLike) return const SizedBox.shrink();
        return LikeHeart(
          key: const Key('productFavorite'),
          liked: likes.contains(widget.productId),
          size: SaveProductButton.size,
          iconSize: SaveProductButton.iconSize,
          tapTarget: SaveProductButton.tapTarget,
          background: AppColors.surface.withValues(alpha: 0.95),
          elevation: 1,
          onTap: () => toggleLikedProduct(context, widget.productId),
        );
      },
    );
  }
}
