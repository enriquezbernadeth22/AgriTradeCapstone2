import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// The splash screen's loading scene: a farmer in a salakot on the left
/// walks toward a buyer standing on the right, carrying a crate of produce,
/// along the loading bar itself — it fills dark green behind him as he
/// goes. At the start he sets off (0%), a third of the way he is walking
/// (33%), two thirds of the way he is near the buyer (66%), and as he
/// hands the crate over the bar fills to the buyer's feet (100%) — then
/// the two stand there if the app is still loading. Under the bar,
/// "Loading AgriTrade+…" and how full it is. Drawn in code (no image or
/// package).
///
/// It does not report real progress — it only shows the app is working.
/// With animations turned off on the phone it stands still, near the
/// buyer.
class WalkingFarmerLoader extends StatefulWidget {
  /// Width of the scene and the bar under it.
  final double width;

  const WalkingFarmerLoader({super.key, this.width = 300});

  /// How long the walk and the handoff take.
  static const Duration crossing = Duration(milliseconds: 3000);

  /// Completes once the handoff is done, so the phone's splash can stay up
  /// until then even when the app loads faster than that (see AppRouter).
  /// Right away when it is over, or when the walk never began.
  static Future<void> untilWalkDone() async {
    final started = _walkStartedAt;
    if (started == null) return;
    final left = crossing - DateTime.now().difference(started);
    if (left > Duration.zero) await Future<void>.delayed(left);
  }

  // When the walk began, for the whole app run. Starting up shows the
  // loading screen more than once in a row (app start, then the signed-in
  // check), each a new widget — they all continue this one walk instead of
  // starting another, so it plays only once.
  static DateTime? _walkStartedAt;

  /// Starts the walk afresh (tests only).
  @visibleForTesting
  static void resetWalk() => _walkStartedAt = null;

  @override
  State<WalkingFarmerLoader> createState() => _WalkingFarmerLoaderState();
}

class _WalkingFarmerLoaderState extends State<WalkingFarmerLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _walk = AnimationController(
    vsync: this,
    duration: WalkingFarmerLoader.crossing,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _walk
        ..stop()
        ..value = 0.66;
    } else if (!_walk.isAnimating && !_walk.isCompleted) {
      // Pick up where the walk already is (or stand at the end when it is
      // over) — once per app run, no starting over.
      final started = WalkingFarmerLoader._walkStartedAt ??= DateTime.now();
      final done =
          DateTime.now().difference(started).inMilliseconds /
          WalkingFarmerLoader.crossing.inMilliseconds;
      _walk.value = done.clamp(0.0, 1.0);
      if (!_walk.isCompleted) _walk.forward();
    }
  }

  @override
  void dispose() {
    _walk.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading AgriTrade+',
      child: SizedBox(
        width: widget.width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Its own layer, so each frame of the walk redraws only this.
            RepaintBoundary(
              child: AnimatedBuilder(
                animation: _walk,
                builder: (context, _) {
                  final filled = _ScenePainter.filledAt(
                    _walk.value,
                    widget.width,
                  );
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: widget.width,
                        height: _ScenePainter.height,
                        child: CustomPaint(
                          painter: _ScenePainter(progress: _walk.value),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // What the bar shows, in words and as a number.
                      ExcludeSemantics(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // On a very narrow screen the words give way,
                            // never the number.
                            Flexible(
                              child: Text(
                                'Loading AgriTrade+…',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Figures of one width, so it does not jitter
                            // as it counts up.
                            Text(
                              '${(filled * 100).round()}%',
                              style: TextStyle(
                                color: AppColors.brand,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The farmer, the buyer, the crate between them and the loading bar they
/// stand on, at [progress] 0 → 1 through the walk and the handoff.
class _ScenePainter extends CustomPainter {
  final double progress;

  _ScenePainter({required this.progress});

  static const double height = 80;

  // The bar's thickness; it is the ground they stand on.
  static const double _barHeight = 6;

  // Where the bar runs: from where the farmer starts to where the buyer
  // stands, both this far in from the scene's ends.
  static const double _margin = 26;

  // The farmer's place along the bar at [progress], from its start (0)
  // to where he stops before the buyer. A steady pace, so the bar and the
  // percentage climb steadily: a third of the time in, a third full; two
  // thirds in, two thirds full and near the buyer.
  static double _farmerX(double progress, double width) {
    final along = (progress / _walkShare).clamp(0.0, 1.0);
    final meetX = width - _margin - 26 * _scale;
    return _margin + (meetX - _margin) * along;
  }

  static double _reach(double progress) => Curves.easeInOut.transform(
    ((progress - _walkShare) / (1 - _walkShare)).clamp(0.0, 1.0),
  );

  /// How full the bar is at [progress], 0 → 1: up to the farmer's feet
  /// while he walks, then on to the buyer's as he hands the crate over.
  /// The percentage under the bar is this, so the two always agree.
  static double filledAt(double progress, double width) {
    final length = width - _margin * 2;
    if (length <= 0) return progress;
    final walked = (_farmerX(progress, width) - _margin) / length;
    return walked + (1 - walked) * _reach(progress);
  }

  // The figures are drawn a little larger than their sketch size.
  static const double _scale = 1.6;

  // The first part of the time is the walk; the rest, the handoff.
  static const double _walkShare = 0.8;

  // Strides across the walk (one stride is two steps). The steps follow
  // the distance walked, so they slow as he does, and end feet together.
  static const double _strides = 4;

  // Skin, salakot, the farmer's clothes, the buyer's clothes, the crate.
  static Color get _skin => AppColors.adapt(const Color(0xFFC68642));
  static Color get _buyerSkin => AppColors.adapt(const Color(0xFFB57A4E));
  static Color get _hat => AppColors.adapt(const Color(0xFFD9A441));
  static Color get _hatRim => AppColors.adapt(const Color(0xFFB7832B));
  static Color get _trousers => AppColors.adapt(const Color(0xFF3E4A3D));
  static Color get _shoe => AppColors.adapt(const Color(0xFF2B2B2B));
  static Color get _buyerShirt => AppColors.adapt(const Color(0xFF5B6B7A));
  static Color get _buyerTrousers => AppColors.adapt(const Color(0xFF2F3A44));
  static Color get _hair => AppColors.adapt(const Color(0xFF2A211C));
  static Color get _crate => AppColors.adapt(const Color(0xFFA9773F));
  static Color get _crateLine => AppColors.adapt(const Color(0xFF85592B));
  static Color get _track => AppColors.adapt(const Color(0xFFE4EBE1));

  @override
  void paint(Canvas canvas, Size size) {
    // The bar along the bottom; their feet are on its top edge (a foot's
    // stroke reaches a little below the line it is drawn on).
    final barTop = size.height - _barHeight;
    final groundY = barTop + 0.5;
    final buyerX = size.width - _margin;

    final walk = (progress / _walkShare).clamp(0.0, 1.0);
    // How far along he is (see _farmerX): a steady pace.
    final along = walk;
    final farmerX = _farmerX(progress, size.width);
    final reach = _reach(progress);

    // The loading bar, from the farmer's start to the buyer: a soft
    // green-grey track, dark green as far as it is filled.
    final track = RRect.fromLTRBR(
      _margin - _barHeight / 2,
      barTop,
      buyerX + _barHeight / 2,
      size.height,
      const Radius.circular(_barHeight / 2),
    );
    canvas.drawRRect(track, Paint()..color = _track);
    final filledTo =
        _margin + (buyerX - _margin) * filledAt(progress, size.width);
    canvas.save();
    canvas.clipRRect(track);
    canvas.drawRRect(
      RRect.fromLTRBR(
        track.left,
        barTop,
        filledTo,
        size.height,
        const Radius.circular(_barHeight / 2),
      ),
      Paint()..color = AppColors.brand,
    );
    canvas.restore();

    // The walk cycle, standing still once he has arrived.
    final phase = along * _strides * 2 * math.pi;
    final swing = walk < 1 ? math.sin(phase) : 0.0;
    final bob = walk < 1 ? (1 - math.cos(phase * 2)) / 2 * 1.2 : 0.0;

    // The buyer, facing left; the near arm comes up to take the crate.
    final buyerHand = _drawBuyer(canvas, Offset(buyerX, groundY), reach);
    // The farmer, facing right; the near arm holds the crate out further
    // as he hands it over.
    final farmerHand = _drawFarmer(
      canvas,
      Offset(farmerX, groundY - bob),
      swing,
      reach,
    );

    // The crate: in his hand, then passed across to the buyer's.
    final crateAt = Offset.lerp(farmerHand, buyerHand, reach)!;
    _drawCrate(canvas, crateAt + const Offset(0, 2));
  }

  Offset _end(Offset from, double length, double angle) =>
      from + Offset(math.sin(angle) * length, math.cos(angle) * length);

  // Facing right, standing on [feet]. Returns where the near hand is, in
  // the scene's coordinates.
  Offset _drawFarmer(Canvas canvas, Offset feet, double swing, double reach) {
    canvas.save();
    canvas.translate(feet.dx, feet.dy - 3);
    canvas.scale(_scale);
    final limb = Paint()
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    const hip = Offset(0, -12);
    const shoulder = Offset(0.5, -24);
    const legLength = 12.0;
    const armLength = 9.5;
    final legAngle = swing * 0.5; // about ±29°

    // Back leg and back arm first, a shade darker, so the near ones read
    // in front.
    limb
      ..strokeWidth = 3.2
      ..color = Color.lerp(_trousers, AppColors.textStrong, 0.25)!;
    canvas.drawLine(hip, _end(hip, legLength, -legAngle), limb);
    limb
      ..strokeWidth = 2.6
      ..color = Color.lerp(AppColors.mid, AppColors.textStrong, 0.3)!;
    canvas.drawLine(
      shoulder,
      _end(shoulder, armLength, swing * 0.6 * (1 - reach)),
      limb,
    );

    // Body (shirt).
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: const Offset(0.3, -18), width: 7.5, height: 13),
        const Radius.circular(3.5),
      ),
      Paint()..color = AppColors.mid,
    );

    // Near leg, with a foot.
    limb
      ..strokeWidth = 3.2
      ..color = _trousers;
    final foot = _end(hip, legLength, legAngle);
    canvas.drawLine(hip, foot, limb);
    canvas.drawLine(foot, foot + const Offset(2.6, 0), limb..color = _shoe);

    // Near arm: carrying the crate in front, then held out to the buyer.
    final armAngle = 1.0 + 0.5 * reach;
    final hand = _end(shoulder, armLength, armAngle);
    limb
      ..strokeWidth = 2.6
      ..color = AppColors.mid;
    canvas.drawLine(shoulder, hand, limb);
    canvas.drawCircle(hand, 1.5, Paint()..color = _skin);

    // Head and salakot: a wide, shallow cone with a darker rim.
    canvas.drawCircle(const Offset(1.4, -29), 3.8, Paint()..color = _skin);
    canvas.drawPath(
      Path()
        ..moveTo(-9.5, -31)
        ..lineTo(12, -31)
        ..lineTo(1.6, -38.5)
        ..close(),
      Paint()..color = _hat,
    );
    canvas.drawLine(
      const Offset(-9.5, -31),
      const Offset(12, -31),
      Paint()
        ..color = _hatRim
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round,
    );
    canvas.restore();
    return Offset(feet.dx, feet.dy - 3) + hand * _scale;
  }

  // Facing left, standing on [feet]. Returns where the near hand is, in
  // the scene's coordinates.
  Offset _drawBuyer(Canvas canvas, Offset feet, double reach) {
    canvas.save();
    canvas.translate(feet.dx, feet.dy - 3);
    canvas.scale(-_scale, _scale);
    final limb = Paint()
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    const hip = Offset(0, -12);
    const shoulder = Offset(0.5, -24.5);

    // Legs, standing a little apart.
    limb
      ..strokeWidth = 3.2
      ..color = Color.lerp(_buyerTrousers, AppColors.textStrong, 0.2)!;
    canvas.drawLine(hip, _end(hip, 12, -0.12), limb);
    limb.color = _buyerTrousers;
    final foot = _end(hip, 12, 0.12);
    canvas.drawLine(hip, foot, limb);
    canvas.drawLine(foot, foot + const Offset(2.6, 0), limb..color = _shoe);
    canvas.drawLine(
      _end(hip, 12, -0.12),
      _end(hip, 12, -0.12) + const Offset(2.6, 0),
      limb,
    );

    // Back arm, at the side.
    limb
      ..strokeWidth = 2.6
      ..color = Color.lerp(_buyerShirt, AppColors.textStrong, 0.25)!;
    canvas.drawLine(shoulder, _end(shoulder, 9.5, -0.15), limb);

    // Body (shirt), a little longer than the farmer's.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: const Offset(0.3, -18.5), width: 8, height: 14),
        const Radius.circular(3.5),
      ),
      Paint()..color = _buyerShirt,
    );

    // Near arm: at the side, then raised to take the crate.
    final hand = _end(shoulder, 9.5, 0.15 + 1.3 * reach);
    limb.color = _buyerShirt;
    canvas.drawLine(shoulder, hand, limb);
    canvas.drawCircle(hand, 1.5, Paint()..color = _buyerSkin);

    // Head, with short hair.
    const head = Offset(1.2, -30);
    canvas.drawCircle(head, 3.9, Paint()..color = _buyerSkin);
    canvas.drawArc(
      Rect.fromCircle(center: head, radius: 4.1),
      math.pi * 1.05,
      math.pi * 1.0,
      false,
      Paint()
        ..color = _hair
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2,
    );
    canvas.restore();
    // Mirrored: x runs the other way.
    return Offset(feet.dx - hand.dx * _scale, feet.dy - 3 + hand.dy * _scale);
  }

  // A small wooden crate with greens in it, centred on [at].
  void _drawCrate(Canvas canvas, Offset at) {
    final box = Rect.fromCenter(
      center: at + const Offset(0, 2),
      width: 11,
      height: 7,
    );
    // The greens showing over the top.
    final leaf = Paint()..color = AppColors.mid;
    canvas.drawCircle(box.topLeft + const Offset(3, 0), 2.4, leaf);
    canvas.drawCircle(box.topCenter + const Offset(0, -0.8), 2.7, leaf);
    canvas.drawCircle(box.topRight + const Offset(-3, 0), 2.4, leaf);
    canvas.drawRRect(
      RRect.fromRectAndRadius(box, const Radius.circular(1.5)),
      Paint()..color = _crate,
    );
    canvas.drawLine(
      box.centerLeft + const Offset(1, 0),
      box.centerRight - const Offset(1, 0),
      Paint()
        ..color = _crateLine
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_ScenePainter oldDelegate) =>
      oldDelegate.progress != progress;
}
