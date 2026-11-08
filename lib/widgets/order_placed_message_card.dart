import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../screen/order_actions.dart';
import '../services/firebase_refs.dart';
import '../services/market_price_helpers.dart';
import '../services/order_format.dart';
import 'order_card.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../l10n/app_language.dart';

/// An order the buyer placed from a chat (a message of type 'orderPlaced';
/// the user's request, 2026-11-08): what the buyer chose — the product,
/// Retail or Wholesale, the quantity, how it is to be fulfilled and the
/// total — with its status. While it is pending, the farmer confirms or
/// rejects it right here, through the same [OrderActions] as in Orders
/// (the same checks, the same stock step). Everyone can open its details.
///
/// What it shows comes from the order itself, read live; the message only
/// says which order it is (its saved summary shows if the order cannot be
/// read).
class OrderPlacedMessageCard extends StatefulWidget {
  final Map<String, dynamic> data;
  final bool isMe;

  const OrderPlacedMessageCard({
    super.key,
    required this.data,
    required this.isMe,
  });

  @override
  State<OrderPlacedMessageCard> createState() => _OrderPlacedMessageCardState();
}

class _OrderPlacedMessageCardState extends State<OrderPlacedMessageCard> {
  late final String _orderId = (widget.data['orderId'] ?? '').toString();
  late final Stream<DocumentSnapshot<Map<String, dynamic>>>? _order =
      _orderId.isEmpty
      ? null
      : FirebaseRefs.firestore.collection('orders').doc(_orderId).snapshots();

  bool _busy = false;

  Color get _green =>
      AppColors.isDark ? AppColors.brandFill : const Color(0xFF0B4225);
  Color get _muted =>
      AppColors.isDark ? AppColors.textSecondary : const Color(0xFF757575);

  // Confirm or Reject, one at a time; the order's own stream then shows
  // the new status.
  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: widget.isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        key: ValueKey('orderPlacedCard_$_orderId'),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.isDark
                ? AppColors.hairline
                : const Color(0xFFE8E9E3),
          ),
        ),
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _order,
          builder: (context, snapshot) {
            final order = snapshot.data?.exists == true
                ? OrderInfo.fromDoc(snapshot.data!)
                : null;
            final gone =
                _order == null ||
                snapshot.hasError ||
                (snapshot.hasData && snapshot.data?.exists != true);
            return _content(order, gone: gone);
          },
        ),
      ),
    );
  }

  Widget _content(OrderInfo? order, {required bool gone}) {
    final data = widget.data;
    final uid = FirebaseRefs.auth.currentUser?.uid;
    final isSeller = order != null && uid != null && order.sellerId == uid;
    final productName = order?.productName.isNotEmpty == true
        ? order!.productName
        : (data['productName'] ?? tl('Product')).toString();
    final quantity = data['quantity'] as num?;
    final unit = (data['unit'] ?? '').toString();
    final wholesale = order?.isWholesale ?? data['pricingType'] == 'wholesale';
    final total = order != null ? order.grandTotal : data['total'] as num?;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.shopping_bag_outlined, size: 15, color: AppColors.brand),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                widget.isMe ? tl('You placed an order') : tl('Order placed'),
                style: GoogleFonts.montserrat(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.brand,
                ),
              ),
            ),
            if (order != null)
              OrderStatusTag(order.isDelayed ? 'delayed' : order.status),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          productName,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.montserrat(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.text,
          ),
        ),
        const SizedBox(height: 4),
        // What the buyer chose: the quantity and Retail or Wholesale.
        Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              order?.quantityLabel ??
                  (quantity == null ? '' : formatStock(quantity, unit)),
              style: GoogleFonts.montserrat(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: AppColors.text,
              ),
            ),
            if (order != null)
              OrderPricingTag(order)
            else
              Text(
                wholesale ? 'WHOLESALE' : 'RETAIL',
                style: GoogleFonts.montserrat(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppColors.brand,
                ),
              ),
          ],
        ),
        if (order != null && order.unitPriceLabel.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            order.unitPriceLabel,
            style: GoogleFonts.montserrat(fontSize: 10.5, color: _muted),
          ),
        ],
        if (order != null && order.fulfillmentLabel.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            order.fulfillmentLabel,
            style: GoogleFonts.montserrat(fontSize: 10.5, color: _muted),
          ),
        ],
        const SizedBox(height: 6),
        Text(
          total != null
              ? tl('Total: {0}', [formatPeso(total)])
              : tl('Total: {0} + delivery fee', [
                  formatPeso(order?.subtotal ?? 0),
                ]),
          style: GoogleFonts.montserrat(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: AppColors.brand,
          ),
        ),
        if (gone) ...[
          const SizedBox(height: 6),
          Text(
            tl('This order is no longer available.'),
            style: GoogleFonts.montserrat(fontSize: 10.5, color: _muted),
          ),
        ] else if (order != null) ...[
          const SizedBox(height: 10),
          ..._actions(order, isSeller: isSeller),
        ],
      ],
    );
  }

  List<Widget> _actions(OrderInfo order, {required bool isSeller}) {
    final pending = order.status == 'pending';
    final role = isSeller ? OrderRole.farmer : OrderRole.buyer;
    final details = _button(
      key: const Key('orderPlacedDetails'),
      label: tl('View Details'),
      onPressed: () => OrderActions.openDetails(context, order, role),
    );

    // The farmer answers the order right here.
    if (isSeller && pending) {
      return [
        Row(
          children: [
            Expanded(
              child: _button(
                key: const Key('orderPlacedReject'),
                label: tl('Reject'),
                destructive: true,
                onPressed: _busy
                    ? null
                    : () => _run(() => OrderActions.reject(context, order)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _button(
                key: const Key('orderPlacedConfirm'),
                label: tl('Confirm Order'),
                filled: true,
                onPressed: _busy
                    ? null
                    : () => _run(() => OrderActions.accept(context, order)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        SizedBox(width: double.infinity, child: details),
      ];
    }
    return [
      if (!isSeller && pending) ...[
        Text(
          tl('Waiting for the farmer to confirm.'),
          style: GoogleFonts.montserrat(fontSize: 10.5, color: _muted),
        ),
        const SizedBox(height: 6),
      ],
      SizedBox(width: double.infinity, child: details),
    ];
  }

  // A compact button (AppTheme's compact actions: 38 high, 12 labels):
  // filled dark green, outlined red, or outlined dark green.
  Widget _button({
    required Key key,
    required String label,
    required VoidCallback? onPressed,
    bool filled = false,
    bool destructive = false,
  }) {
    final red = AppColors.tone(Colors.red, 700);
    const size = Size.fromHeight(AppTheme.compactActionHeight);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
    );
    final text = Text(
      label,
      maxLines: 1,
      style: GoogleFonts.montserrat(
        fontSize: AppTheme.compactActionLabelSize,
        fontWeight: FontWeight.w600,
      ),
    );
    if (filled) {
      return ElevatedButton(
        key: key,
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: _green,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: size,
          fixedSize: size,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: shape,
        ),
        child: FittedBox(fit: BoxFit.scaleDown, child: text),
      );
    }
    return OutlinedButton(
      key: key,
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: destructive ? red : AppColors.brand,
        backgroundColor: AppColors.surface,
        side: BorderSide(
          color: destructive ? AppColors.tone(Colors.red, 200) : _green,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: size,
        fixedSize: size,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: shape,
      ),
      child: FittedBox(fit: BoxFit.scaleDown, child: text),
    );
  }
}
