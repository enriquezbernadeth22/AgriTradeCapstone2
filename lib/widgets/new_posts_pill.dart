import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// The small dark-green pill over the top of Explore, "↑ 2 new posts",
/// telling a buyer that farmers have posted since the feed was loaded.
/// The feed itself never reshuffles on its own; tapping the pill brings
/// the new posts in at the top. Nothing is shown while [count] is 0, and
/// it slides in and out as posts arrive or are brought in.
class NewPostsPill extends StatefulWidget {
  final int count;
  final VoidCallback onTap;

  const NewPostsPill({super.key, required this.count, required this.onTap});

  /// "1 new post", "3 new posts".
  static String label(int count) =>
      count == 1 ? '1 new post' : '$count new posts';

  @override
  State<NewPostsPill> createState() => _NewPostsPillState();
}

class _NewPostsPillState extends State<NewPostsPill> {
  // The last count above 0, still shown while the pill slides away, so it
  // never flashes "0 new posts" on its way out.
  int _shownCount = 1;

  @override
  Widget build(BuildContext context) {
    final visible = widget.count > 0;
    if (visible) _shownCount = widget.count;
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        offset: visible ? Offset.zero : const Offset(0, -1.4),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 220),
          opacity: visible ? 1 : 0,
          child: Material(
            color: AppColors.brandFill,
            shape: const StadiumBorder(),
            elevation: 4,
            shadowColor: Colors.black38,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: widget.onTap,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 7, 16, 7),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.arrow_upward_rounded,
                      size: 16,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      NewPostsPill.label(_shownCount),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
