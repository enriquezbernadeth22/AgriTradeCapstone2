import '../widgets/agri_app_bar.dart';
import '../theme/app_theme.dart';
import 'package:flutter/material.dart';
import '../widgets/app_scaffold_messenger.dart';
import 'package:flutter/services.dart';
import '../widgets/agri_dialog.dart';
import 'package:image_picker/image_picker.dart';

import '../services/cloudinary_service.dart';
import '../services/review_service.dart';
import '../theme/app_colors.dart';
import '../l10n/app_language.dart';

class AddReviewScreen extends StatefulWidget {
  final String orderId;
  final String productId;
  final String productName;
  final String sellerId;
  final String? productImage;

  const AddReviewScreen({
    super.key,
    required this.orderId,
    required this.productId,
    required this.productName,
    required this.sellerId,
    this.productImage,
  });

  @override
  State<AddReviewScreen> createState() => _AddReviewScreenState();
}

class _AddReviewScreenState extends State<AddReviewScreen> {
  final _reviewService = ReviewService();
  final _cloudinary = CloudinaryService();
  final _picker = ImagePicker();
  final _commentController = TextEditingController();

  double _rating = 0;
  bool _submitting = false;
  // The chosen photos, each with its bytes read once for its preview.
  final List<({XFile file, Uint8List bytes})> _photos = [];

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final room = ReviewService.maxPhotos - _photos.length;
    if (room <= 0) return;
    final source = await showAgriSheet<ImageSource>(
      context: context,
      title: tl('Add photos'),
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AgriSheetAction(
            icon: Icons.camera_alt_outlined,
            label: tl('Take a photo'),
            onTap: () => Navigator.pop(context, ImageSource.camera),
          ),
          AgriSheetAction(
            icon: Icons.photo_library_outlined,
            label: tl('Choose from gallery'),
            onTap: () => Navigator.pop(context, ImageSource.gallery),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );

    if (source == null) return;

    // The gallery takes several at once, up to the room left.
    final List<XFile> picked;
    if (source == ImageSource.gallery && room > 1) {
      picked = await _picker.pickMultiImage(
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 75,
        limit: room,
      );
    } else {
      final one = await _picker.pickImage(
        source: source,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 75,
      );
      picked = [?one];
    }

    if (!mounted || picked.isEmpty) return;
    final added = <({XFile file, Uint8List bytes})>[];
    for (final file in picked.take(room)) {
      added.add((file: file, bytes: await file.readAsBytes()));
    }
    if (!mounted) return;
    setState(() => _photos.addAll(added));
  }

  void _removeImage(int index) => setState(() => _photos.removeAt(index));

  // The photo part (system objectives, 2026-11-09: "optional review
  // photos"): up to [ReviewService.maxPhotos] in one row of equal squares,
  // each with an × at its corner, a dashed "Add" square while there is
  // room, and the count above.
  Widget _photoSection() {
    final max = ReviewService.maxPhotos;
    final canAdd = _photos.length < max;
    Widget square(Widget child) =>
        Expanded(child: AspectRatio(aspectRatio: 1, child: child));

    Widget photoTile(int index) => ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.memory(
            _photos[index].bytes,
            fit: BoxFit.cover,
            gaplessPlayback: true,
          ),
          Positioned(
            top: 6,
            right: 6,
            child: Material(
              color: AppTheme.dark,
              shape: const CircleBorder(),
              child: InkWell(
                key: Key('reviewRemovePhoto_$index'),
                customBorder: const CircleBorder(),
                onTap: _submitting ? null : () => _removeImage(index),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(
                    Icons.close_rounded,
                    size: 15,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    final addTile = Material(
      color: AppColors.tint,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        key: const Key('reviewAddPhoto'),
        borderRadius: BorderRadius.circular(12),
        onTap: _submitting ? null : _pickImage,
        child: CustomPaint(
          painter: _DashedOutlinePainter(
            color: AppColors.brand.withValues(alpha: 0.45),
            radius: 12,
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.add_a_photo_outlined,
                  color: AppColors.brand,
                  size: 22,
                ),
                const SizedBox(height: 6),
                Text(
                  tl('Add Photo'),
                  style: TextStyle(
                    color: AppColors.brand,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(tl('Photos'), style: AppTheme.label()),
            const SizedBox(width: 6),
            Text(
              tl('(optional, up to {0})', [max]),
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const Spacer(),
            Text(
              '${_photos.length} / $max',
              key: const Key('reviewPhotoCount'),
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (var i = 0; i < max; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              square(
                i < _photos.length
                    ? photoTile(i)
                    : i == _photos.length && canAdd
                    ? addTile
                    : const SizedBox.shrink(),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (_rating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        appSnackBar(
          tl('Please choose a star rating.'),
          kind: MessageKind.error,
        ),
      );
      return;
    }
    final comment = _commentController.text.trim();
    if (comment.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        appSnackBar(
          tl('Please add a review description.'),
          kind: MessageKind.error,
        ),
      );
      return;
    }

    setState(() => _submitting = true);

    // Every photo uploaded, in order; one that fails stops the review, so
    // nothing is saved with a photo missing.
    final imageUrls = <String>[];
    for (final photo in _photos) {
      final url = await _cloudinary.uploadImage(
        photo.file,
        folder: 'agritrade/reviews',
      );
      if (url == null) {
        if (!mounted) return;
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          appSnackBar(
            tl('Could not upload review image.'),
            kind: MessageKind.error,
          ),
        );
        return;
      }
      imageUrls.add(url);
    }

    final err = await _reviewService.submitReview(
      orderId: widget.orderId,
      productId: widget.productId,
      productName: widget.productName,
      sellerId: widget.sellerId,
      rating: _rating,
      comment: comment,
      imageUrls: imageUrls,
    );

    if (!mounted) return;
    setState(() => _submitting = false);

    if (err != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(appSnackBar(err, kind: MessageKind.error));
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      appSnackBar(
        tl('Review submitted. Thank you!'),
        kind: MessageKind.success,
      ),
    );
    Navigator.pop(context, true);
  }

  Widget _star(int index) {
    final fill = (_rating - (index - 1)).clamp(0.0, 1.0);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (details) {
        final half = details.localPosition.dx < 18;
        setState(() => _rating = index - (half ? 0.5 : 0));
      },
      child: SizedBox(
        width: 36,
        height: 44,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(Icons.star_border_rounded, color: AppColors.grey(), size: 32),
            if (fill > 0)
              ClipRect(
                clipper: _StarFillClipper(fill),
                child: const Icon(
                  Icons.star_rounded,
                  color: Colors.amber,
                  size: 32,
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AgriAppBar(title: tl('Add Review')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: AppTheme.card(),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: 56,
                      height: 56,
                      child: (widget.productImage ?? '').isNotEmpty
                          ? Image.network(
                              widget.productImage!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Container(
                                color: AppColors.accent,
                                child: Icon(
                                  Icons.shopping_basket,
                                  color: AppColors.brand,
                                ),
                              ),
                            )
                          : Container(
                              color: AppColors.accent,
                              child: Icon(
                                Icons.shopping_basket,
                                color: AppColors.brand,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.productName,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              tl('Your Rating (required)'),
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (i) => _star(i + 1)),
            ),
            Center(
              child: Text(
                _rating == 0
                    ? tl('Choose 0.5 to 5 stars')
                    : tl('{0} out of 5', [_rating.toStringAsFixed(1)]),
                style: TextStyle(color: AppColors.grey(600), fontSize: 12),
              ),
            ),
            const SizedBox(height: 16),
            Text(tl('Description'), style: AppTheme.label()),
            const SizedBox(height: 8),
            // The app's standard field (AppTheme), like every other, with
            // the "n/50" count under its right edge; typing stops at the
            // limit.
            TextField(
              controller: _commentController,
              style: const TextStyle(fontSize: 14),
              minLines: 3,
              maxLines: 4,
              maxLength: ReviewService.maxCommentLength,
              maxLengthEnforcement: MaxLengthEnforcement.enforced,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: tl('Share your experience with this product…'),
              ),
            ),
            const SizedBox(height: 12),
            _photoSection(),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brandFill,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: Text(
                  _submitting ? tl('Submitting...') : tl('Submit Review'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StarFillClipper extends CustomClipper<Rect> {
  final double fill;
  const _StarFillClipper(this.fill);

  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, size.width * fill, size.height);

  @override
  bool shouldReclip(covariant _StarFillClipper oldClipper) =>
      oldClipper.fill != fill;
}

/// A dashed rounded outline, for the "Add a photo" tile.
class _DashedOutlinePainter extends CustomPainter {
  final Color color;
  final double radius;
  const _DashedOutlinePainter({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          Radius.circular(radius),
        ).deflate(0.7),
      );
    const dash = 6.0;
    const gap = 4.0;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, distance + dash), paint);
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedOutlinePainter old) =>
      old.color != color || old.radius != radius;
}
