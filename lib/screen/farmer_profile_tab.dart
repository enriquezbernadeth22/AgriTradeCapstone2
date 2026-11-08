import 'package:flutter/material.dart';
import '../services/firebase_refs.dart';
import '../widgets/app_scaffold_messenger.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/product_service.dart';
import '../services/product_share_service.dart';
import '../services/market_price_helpers.dart';
import '../services/review_stats.dart';
import '../data/commodity_master_list.dart';
import 'add_product_screen.dart';
import 'farmer_edit_profile_screen.dart';
import 'farmer_reviews_screen.dart';
import '../widgets/docked_nav_bar.dart';
import '../widgets/page_header.dart';
import '../widgets/profile_cover_header.dart';
import '../widgets/agri_dialog.dart';
import '../widgets/update_stock_dialog.dart';
import '../widgets/shimmer.dart';
import '../widgets/skeleton_loaders.dart';
import '../widgets/retry_message.dart';
import '../widgets/agri_refresh_indicator.dart';
import '../l10n/tr.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../l10n/app_language.dart';

// Body-only widget — renders inside FarmerHomeScreen's Scaffold.
class ProfileTab extends StatefulWidget {
  /// Opens the Farmer's Settings page, from the gear beside the title.
  final VoidCallback? onOpenSettings;

  const ProfileTab({super.key, this.onOpenSettings});

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  final ProductService _productService = ProductService();
  // The farmer's own products, for the overall rating — created once.
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _myProductsForRating =
      _productService.myProductsStream();
  // The farmer's saved profile, live — its name and location. The name
  // comes from here (as on the Market tab), not the login account, so an
  // edit shows at once: this tab stays alive under the others and is not
  // rebuilt when Edit Profile saves.
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _profile =
      FirebaseRefs.firestore
          .collection('users')
          .doc(FirebaseRefs.auth.currentUser?.uid ?? 'unknown')
          .snapshots();
  // 'active' | 'archived' — which of the farmer's own listings to show.
  String _productFilter = 'active';
  // How My Products is ordered.
  _ProductSort _sort = _ProductSort.newest;
  // The farmer's own listings, created once — re-sorting never reloads.
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _myProducts =
      FirebaseRefs.firestore
          .collection('products')
          .where('farmerId', isEqualTo: FirebaseRefs.auth.currentUser?.uid)
          .snapshots();

  Future<void> _refreshData() async {
    await Future.delayed(const Duration(milliseconds: 700));
  }

  // ---- My Products ----
  // Lists the signed-in farmer's own listings. Matched by an 'ownerId'
  // field on each product doc — rename this to whatever field your
  // ProductService.addProduct() actually writes (e.g. 'farmerId', 'uid').
  Widget _myProductsSection(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  tl('MY PRODUCTS'),
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.grey(500),
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              // Sorting and a category filter, for a farmer with many
              // listings (adding one is the + in the bottom bar).
              _sortMenu(),
            ],
          ),
          const SizedBox(height: 6),
          // Active | Archived, with the current one underlined; swiping the
          // list below sideways moves between them too.
          // Two equal halves, like the Orders tabs.
          Row(
            children: [
              Expanded(
                child: _productFilterTab(tr(context).productsActive, 'active'),
              ),
              Expanded(
                child: _productFilterTab(
                  tr(context).productsArchived,
                  'archived',
                ),
              ),
            ],
          ),
          Divider(height: 1, color: AppColors.grey(200)),
          const SizedBox(height: 10),
          Container(
            decoration: AppTheme.card(),
            // The rows' tap ripple shows on the card (a ListTile draws it on
            // the nearest Material, under the card's own colour otherwise).
            child: Material(
              type: MaterialType.transparency,
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _myProducts,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Shimmer(
                      child: Column(
                        children: [
                          ProductRowSkeleton(),
                          Divider(height: 1, indent: 16, endIndent: 16),
                          ProductRowSkeleton(),
                        ],
                      ),
                    );
                  }
                  if (snap.hasError) {
                    return RetryMessage(
                      message: tl(
                        'Could not load your listings. Check your connection and retry.',
                      ),
                      onRetry: () => setState(() {}),
                    );
                  }

                  final showArchived = _productFilter == 'archived';
                  // A listing the AgriTrade+ team took off the marketplace
                  // (its product no longer sold, or moderated) is not
                  // Active: it is with the archived ones, marked so.
                  final inTab = (snap.data?.docs ?? [])
                      .where(
                        (d) =>
                            (d.data()['isArchived'] == true ||
                                d.data()['isSuspended'] == true) ==
                            showArchived,
                      )
                      .toList();
                  final docs = _sorted(inTab);
                  final Widget list = docs.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(
                            showArchived
                                ? tl('You don\'t have any archived products.')
                                : tl(
                                    'You haven\'t posted any active products yet.',
                                  ),
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.grey(600),
                            ),
                          ),
                        )
                      : Column(
                          children: [
                            for (var i = 0; i < docs.length; i++) ...[
                              if (i > 0)
                                const Divider(
                                  height: 1,
                                  indent: 16,
                                  endIndent: 16,
                                ),
                              _productTile(context, docs[i].id, docs[i].data()),
                            ],
                          ],
                        );
                  return _swipeBetweenFilters(list);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  // [docs] in the chosen order.
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _sorted(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final shown = [...docs];
    String name(Map<String, dynamic> d) =>
        (d['name'] ?? '').toString().trim().toLowerCase();
    int posted(Map<String, dynamic> d) {
      final at = d['updatedAt'] ?? d['createdAt'];
      return at is Timestamp ? at.millisecondsSinceEpoch : 0;
    }

    shown.sort((a, b) {
      final x = a.data();
      final y = b.data();
      final byChoice = switch (_sort) {
        _ProductSort.newest => posted(y).compareTo(posted(x)),
        _ProductSort.oldest => posted(x).compareTo(posted(y)),
        _ProductSort.nameAz => name(x).compareTo(name(y)),
        _ProductSort.nameZa => name(y).compareTo(name(x)),
      };
      // Ties in name order, so the list never shuffles.
      return byChoice != 0 ? byChoice : name(x).compareTo(name(y));
    });
    return shown;
  }

  // "Sort" — how the list is ordered. The pill names what is chosen.
  Widget _sortMenu() {
    TextStyle item(bool selected) => TextStyle(
      fontSize: 13,
      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
      color: selected ? AppColors.brand : AppColors.text,
    );
    PopupMenuItem<String> choice(String value, String label, bool selected) =>
        PopupMenuItem<String>(
          value: value,
          height: 38,
          child: Row(
            children: [
              Expanded(child: Text(label, style: item(selected))),
              if (selected)
                Icon(Icons.check_rounded, size: 17, color: AppColors.brand),
            ],
          ),
        );
    PopupMenuItem<String> heading(String label) => PopupMenuItem<String>(
      enabled: false,
      height: 30,
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.grey(500),
          letterSpacing: 0.6,
        ),
      ),
    );

    return PopupMenuButton<String>(
      tooltip: tl('Sort your products'),
      position: PopupMenuPosition.under,
      color: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onSelected: (value) =>
          setState(() => _sort = _ProductSort.values.byName(value)),
      itemBuilder: (context) => [
        heading('SORT BY'),
        for (final sort in _ProductSort.values)
          choice(sort.name, tl(sort.label), sort == _sort),
      ],
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 5, 8, 5),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppTheme.compactDropdownRadius),
          border: Border.all(color: AppColors.grey(300)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sort_rounded, size: 16, color: AppColors.brand),
            const SizedBox(width: 5),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 150),
              child: Text(
                tl(_sort.short),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.brand,
                ),
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.expand_more_rounded, size: 16, color: AppColors.brand),
          ],
        ),
      ),
    );
  }

  // One half of Active | Archived: its label centred, and — for the one
  // showing — dark green with a green bar under the whole half. Tapping
  // it works too.
  Widget _productFilterTab(String label, String value) {
    final selected = _productFilter == value;
    return InkWell(
      onTap: () => _showProductFilter(value),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? AppColors.brand : AppColors.grey(500),
              ),
            ),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            height: 2.5,
            width: double.infinity,
            decoration: BoxDecoration(
              color: selected ? AppColors.brandFill : Colors.transparent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }

  // Which way the list last moved: -1 to Archived (it slides in from the
  // right), 1 back to Active.
  int _filterDirection = -1;

  void _showProductFilter(String value) {
    if (value == _productFilter) return;
    setState(() {
      _filterDirection = value == 'archived' ? -1 : 1;
      _productFilter = value;
    });
  }

  // The list, swiped sideways to move between Active and Archived — left
  // for Archived, right for Active — sliding the new list in from that side.
  Widget _swipeBetweenFilters(Widget list) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity < -250) _showProductFilter('archived');
        if (velocity > 250) _showProductFilter('active');
      },
      child: ClipRect(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.topCenter,
            children: [...previous, ?current],
          ),
          transitionBuilder: (child, animation) {
            final incoming = child.key == ValueKey(_productFilter);
            final from = Offset(incoming ? -_filterDirection * 1.0 : 0, 0);
            final to = Offset(incoming ? 0 : _filterDirection * 1.0, 0);
            final slide = incoming
                ? Tween(begin: from, end: Offset.zero).animate(animation)
                : Tween(begin: to, end: Offset.zero).animate(animation);
            return SlideTransition(position: slide, child: child);
          },
          child: KeyedSubtree(key: ValueKey(_productFilter), child: list),
        ),
      ),
    );
  }

  Widget _productTile(
    BuildContext context,
    String id,
    Map<String, dynamic> data,
  ) {
    final name = data['name']?.toString() ?? 'Unnamed product';
    final price = (data['price'] as num?)?.toDouble();
    final quantity = data['quantity'];
    final unit = (data['unit'] as String?) ?? unitForProductName(name);
    final isArchived = data['isArchived'] == true;
    // Taken off the marketplace by the AgriTrade+ team: its product is no
    // longer sold (archived or removed in Price Management), or moderated.
    final isSuspended = data['isSuspended'] == true;
    final productRemoved = data['moderationStatus'] == 'commodity_archived';
    final saveCount = (data['saveCount'] as num?)?.toInt() ?? 0;
    final isOutOfStock =
        !isArchived &&
        !isSuspended &&
        ((quantity as num?)?.toDouble() ?? 0) <= 0;
    final reason = (data['moderationReason'] ?? '').toString().trim();

    final imageUrls =
        (data['imageUrls'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final imageUrl = imageUrls.isNotEmpty
        ? imageUrls.first
        : data['imageUrl']?.toString();

    final stockText = quantity is num
        ? 'Available Stock: ${formatStock(quantity, unit)}'
        : '';
    final subtitle = isSuspended
        ? [
            productRemoved
                ? tl(
                    'Not on the marketplace: {0} is no longer sold on AgriTrade+.',
                    [name],
                  )
                : tl('Hidden from the marketplace by the AgriTrade+ team.'),
            if (reason.isNotEmpty) tl('Reason: {0}', [reason]),
          ].join(' ')
        : price != null
        ? '${formatPriceWithUnit(price, unit)}${stockText.isEmpty ? '' : ' · $stockText'}'
        : stockText;

    return Column(
      children: [
        ListTile(
          // Less room on the right, so the ⋮ sits near the card's edge,
          // in line with "View Reviews" below it.
          contentPadding: const EdgeInsets.only(left: 16, right: 4),
          horizontalTitleGap: 12,
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: (imageUrl != null && imageUrl.isNotEmpty)
                ? Image.network(
                    imageUrl,
                    width: 46,
                    height: 46,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      width: 46,
                      height: 46,
                      color: AppColors.accent,
                      child: Icon(
                        Icons.eco_outlined,
                        color: AppColors.brand,
                        size: 22,
                      ),
                    ),
                  )
                : Container(
                    width: 46,
                    height: 46,
                    color: AppColors.accent,
                    child: Icon(
                      Icons.eco_outlined,
                      color: AppColors.brand,
                      size: 22,
                    ),
                  ),
          ),
          title: Row(
            children: [
              Flexible(
                child: Text(
                  withSellingOption(name, data),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (isArchived || isSuspended || isOutOfStock) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: isSuspended
                        ? AppColors.tone(Colors.red, 50)
                        : isArchived
                        ? AppColors.grey(300)
                        : AppColors.tone(Colors.orange, 100),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    isSuspended
                        ? (productRemoved ? tl('UNAVAILABLE') : tl('HIDDEN'))
                        : isArchived
                        ? tl('ARCHIVED')
                        : tl('OUT OF STOCK'),
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      color: isSuspended
                          ? AppColors.tone(Colors.red, 700)
                          : isArchived
                          ? AppColors.grey(700)
                          : AppColors.tone(Colors.orange, 800),
                    ),
                  ),
                ),
              ],
            ],
          ),
          subtitle: subtitle.isNotEmpty || saveCount > 0
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppColors.grey(600),
                        ),
                      ),
                    // How many buyers liked this listing — a number
                    // only (kept by the syncProductSaveCount Cloud
                    // Function); who they are is never available here.
                    if (saveCount > 0) ...[
                      const SizedBox(height: 2),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.favorite_rounded,
                            size: 13,
                            color: AppColors.brand,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            saveCount == 1
                                ? tl('1 like')
                                : tl('{0} likes', [saveCount]),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.brand,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                )
              : null,
          // The same compact menu Messages uses (showAgriPopupMenu),
          // dropped from this product's own ⋮ button.
          trailing: Builder(
            builder: (buttonContext) => IconButton(
              tooltip: tl('Product actions'),
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.more_vert, color: AppColors.grey(500)),
              onPressed: () => _openProductMenu(
                buttonContext,
                id: id,
                data: data,
                name: name,
                quantity: quantity,
                unit: unit,
                isArchived: isArchived,
                isSuspended: isSuspended,
              ),
            ),
          ),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  AddProductScreen(productId: id, existingData: data),
            ),
          ),
        ),
        _productRating(id, data),
      ],
    );
  }

  // Unless said otherwise, a message here is a problem (such as a stock
  // amount that is not allowed).
  void _snack(
    BuildContext context,
    String message, {
    MessageKind kind = MessageKind.error,
  }) {
    showAppMessage(context, tl(message), kind: kind);
  }

  // Active listing: Share, Edit, Update Quantity, Archive. An archived
  // one is hidden from buyers and read-only, so it only offers its
  // details and Restore — nothing to share, edit or restock until then.
  Future<void> _openProductMenu(
    BuildContext buttonContext, {
    required String id,
    required Map<String, dynamic> data,
    required String name,
    required dynamic quantity,
    required String unit,
    required bool isArchived,
    bool isSuspended = false,
  }) async {
    final action = await showAgriPopupMenu<String>(
      anchorContext: buttonContext,
      // Taken off by the AgriTrade+ team: the farmer can only look at it.
      items: isSuspended
          ? [
              AgriMenuItem(
                value: 'view',
                icon: Icons.visibility_outlined,
                label: tl('View Details'),
              ),
            ]
          : isArchived
          ? [
              AgriMenuItem(
                value: 'view',
                icon: Icons.visibility_outlined,
                label: tl('View Details'),
              ),
              AgriMenuItem(
                value: 'archive',
                icon: Icons.unarchive_outlined,
                label: tl('Restore Listing'),
              ),
            ]
          : [
              AgriMenuItem(
                value: 'share',
                icon: Icons.share_outlined,
                label: tl('Share Product'),
              ),
              AgriMenuItem(
                value: 'edit',
                icon: Icons.edit_outlined,
                label: tl('Edit Product'),
              ),
              AgriMenuItem(
                value: 'quantity',
                icon: Icons.inventory_2_outlined,
                label: tl('Update Quantity'),
              ),
              AgriMenuItem(
                value: 'archive',
                icon: Icons.archive_outlined,
                label: tl('Archive Listing'),
              ),
            ],
    );
    if (action == null || !buttonContext.mounted) return;
    switch (action) {
      case 'view':
      case 'edit':
        Navigator.push(
          buttonContext,
          MaterialPageRoute(
            builder: (_) => AddProductScreen(productId: id, existingData: data),
          ),
        );
      case 'quantity':
        _showUpdateQuantityDialog(buttonContext, id, name, quantity, unit);
      case 'archive':
        _setArchived(buttonContext, id, !isArchived);
      case 'share':
        ProductShareService.share(buttonContext, id, data);
    }
  }

  Future<void> _setArchived(
    BuildContext context,
    String id,
    bool archive,
  ) async {
    final error = archive
        ? await _productService.archiveProduct(id)
        : await _productService.unarchiveProduct(id);
    if (!context.mounted) return;
    if (archive && error == ProductService.archiveBlockedByOrdersMessage) {
      await showAgriDialog<void>(
        context: context,
        builder: (dialogContext) => AgriDialog(
          icon: Icons.archive_outlined,
          tone: AgriTone.warning,
          title: Text(tl('Cannot archive product')),
          content: Text(
            tl(
              'This product has orders that are not finished yet. Resolve or complete those orders before archiving this product.',
            ),
          ),
          actions: [
            AgriDialogButton(
              label: 'OK',
              kind: AgriButtonKind.primary,
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
          ],
        ),
      );
      return;
    }
    _snack(
      context,
      error ??
          (archive
              ? tl(
                  'Listing archived — hidden from the marketplace until you restore it.',
                )
              : tl('Listing restored — visible in the marketplace again.')),
      kind: error == null ? MessageKind.success : MessageKind.error,
    );
  }

  // Farmers can always manually correct Available Stock (independent of
  // order-driven deduction) — whole numbers only for count-based units
  // (piece/head), decimals allowed for weight-based ones (kg/kg liveweight).
  Future<void> _showUpdateQuantityDialog(
    BuildContext context,
    String id,
    String name,
    dynamic currentQuantity,
    String unit,
  ) async {
    final current = currentQuantity is num
        ? currentQuantity
        : num.tryParse(currentQuantity?.toString() ?? '') ?? 0;
    // The dialog owns its own text controller (see UpdateStockDialog) —
    // it must outlive this call returning, since the dialog is still
    // closing at that point. Null means cancelled: nothing is saved.
    final newQuantity = await showUpdateStockDialog(
      context,
      name: name,
      currentQuantity: current,
      unit: unit,
      onInvalid: _snack,
    );
    if (!context.mounted || newQuantity == null) return;
    final error = await _productService.updateQuantity(id, newQuantity);
    if (!context.mounted) return;
    _snack(
      context,
      error ??
          tl('Available Stock updated to {0}.', [
            formatStock(newQuantity, unit),
          ]),
      kind: error == null ? MessageKind.success : MessageKind.error,
    );
  }

  // A product's rating line: "4.7 ★ · 18 reviews · View Reviews". Reads
  // the totals stored on the product (kept current by the
  // recomputeProductReviewStats Cloud Function) rather than loading every
  // review for every product in the list.
  Widget _productRating(String productId, Map<String, dynamic> product) {
    final summary = productRating(product);
    return Padding(
      padding: const EdgeInsets.fromLTRB(72, 0, 12, 8),
      child: Row(
        children: [
          if (summary.count == 0)
            Text(
              tr(context).noReviewsYet,
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            )
          else ...[
            Text(
              formatRating(summary.average),
              style: GoogleFonts.montserrat(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.text,
              ),
            ),
            const SizedBox(width: 2),
            const Icon(Icons.star_rounded, color: Colors.amber, size: 16),
            const SizedBox(width: 6),
            Text(
              reviewCountLabel(summary.count),
              style: TextStyle(fontSize: 12, color: AppColors.grey(600)),
            ),
            const Spacer(),
            TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => FarmerReviewsScreen(
                    productId: productId,
                    productName: product['name']?.toString(),
                  ),
                ),
              ),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.brand,
                minimumSize: const Size(0, 30),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: GoogleFonts.montserrat(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: Text(tr(context).viewReviews),
            ),
          ],
        ],
      ),
    );
  }

  // The farmer's overall rating across all their products, weighted by
  // each product's number of reviews (see combineProductRatings).
  Widget _farmerRatingSummary() {
    final uid = FirebaseRefs.auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _myProductsForRating,
      builder: (context, snapshot) {
        final summary = combineProductRatings(
          (snapshot.data?.docs ?? const []).map((doc) => doc.data()),
        );
        // Nothing to show until the first valid review arrives — a new
        // farmer (no products, or products with no reviews) sees no empty
        // rating card. It appears on its own once a review exists.
        if (summary.count == 0) return const SizedBox.shrink();
        return Container(
          margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: AppTheme.card(),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tl('Overall Product Rating'),
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.grey(600),
                      ),
                    ),
                    const SizedBox(height: 4),
                    ...[
                      Row(
                        children: [
                          Text(
                            formatRating(summary.average),
                            style: GoogleFonts.montserrat(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: AppColors.brand,
                            ),
                          ),
                          const SizedBox(width: 8),
                          RatingStars(summary.average, size: 17),
                        ],
                      ),
                      Text(
                        tl('Based on {0}', [reviewCountLabel(summary.count)]),
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.grey(600),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const FarmerReviewsScreen(),
                  ),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.brand,
                  textStyle: GoogleFonts.montserrat(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: Text(tr(context).viewAllReviews),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseRefs.auth.currentUser;

    // The header stays put; pull-to-refresh starts under it.
    return Column(
      children: [
        // The band stays put; the title (with the account menu opposite
        // it) scrolls with the page below.
        PageHeader(title: tr(context).navProfile, includeTitle: false),
        Expanded(
          child: AgriRefreshIndicator(
            color: AppColors.brand,
            onRefresh: _refreshData,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.only(
                bottom: DockedNavBar.listEndPadding(context),
              ),
              child: Column(
                children: [
                  // ---- Title, cover, photo and name: the same header as
                  // the Buyer Profile (the user, 2026-11-08); Settings is
                  // a small gear opposite the title. ----
                  StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: _profile,
                    builder: (context, snap) {
                      final data = snap.data?.data();
                      final name =
                          [data?['name'], data?['fullName'], user?.displayName]
                              .map((v) => v?.toString().trim() ?? '')
                              .firstWhere(
                                (v) => v.isNotEmpty,
                                orElse: () => tl('Farmer'),
                              );
                      final photoUrl =
                          data?['photoUrl']?.toString() ?? user?.photoURL;
                      return Column(
                        children: [
                          ProfileCoverHeader(
                            title: tr(context).navProfile,
                            name: name,
                            photoUrl: photoUrl,
                            onEdit: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const EditProfileScreen(),
                              ),
                            ),
                            trailing: widget.onOpenSettings == null
                                ? null
                                : IconButton(
                                    key: const Key('profileSettings'),
                                    tooltip: tl('Settings'),
                                    onPressed: widget.onOpenSettings,
                                    icon: Icon(
                                      Icons.settings_outlined,
                                      size: AppTheme.barIconSize + 2,
                                      color: AppColors.heading,
                                    ),
                                  ),
                          ),
                          const SizedBox(height: 8),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Text(
                              name,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.montserrat(
                                fontSize: 19,
                                fontWeight: FontWeight.bold,
                                color: AppColors.heading,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 3),

                  // ---- Location ----
                  StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: _profile,
                    builder: (context, snap) {
                      final data = snap.data?.data();
                      final barangay = data?['barangay']?.toString();
                      final muni =
                          data?['municipality']?.toString() ?? 'Laurel';
                      final prov = data?['province']?.toString() ?? 'Batangas';
                      final location = (barangay != null && barangay.isNotEmpty)
                          ? '$barangay, $muni, $prov'
                          : '$muni, $prov';
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.location_on_outlined,
                            size: 14,
                            color: AppColors.grey(600),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            location,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: AppColors.grey(600),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  _farmerRatingSummary(),
                  const SizedBox(height: 24),

                  // ---- My Products ----
                  _myProductsSection(context),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// How My Products is ordered.
enum _ProductSort {
  newest('Newest first', 'Newest'),
  oldest('Oldest first', 'Oldest'),
  nameAz('Name: A–Z', 'A–Z'),
  nameZa('Name: Z–A', 'Z–A');

  /// In the menu.
  final String label;

  /// On the pill.
  final String short;

  const _ProductSort(this.label, this.short);
}
