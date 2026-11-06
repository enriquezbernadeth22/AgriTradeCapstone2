import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../widgets/app_scaffold_messenger.dart';

import '../services/message_service.dart';
import '../services/order_format.dart';
import '../services/order_service.dart';
import '../theme/app_theme.dart';
import '../widgets/agri_dialog.dart';
import '../widgets/order_card.dart';
import 'add_review_screen.dart';
import 'chat_screen.dart';
import 'order_details_screen.dart';
import 'order_receipt_screen.dart';
import '../theme/app_colors.dart';
import '../widgets/fitted_menu_width.dart';
import '../l10n/app_language.dart';

/// Everything a user can do to an order from the Orders list, the order
/// details screen or a receipt card in Messages. The business rules stay in
/// [OrderService] / [MessageService]; this only confirms, calls them and
/// reports the outcome, so every entry point behaves the same.
class OrderActions {
  const OrderActions._();

  static final OrderService _orders = OrderService();
  static final MessageService _messages = MessageService();

  static void _snack(
    ScaffoldMessengerState messenger,
    String message, {
    required MessageKind kind,
  }) {
    messenger.showSnackBar(appSnackBar(tl(message), kind: kind));
  }

  // What an action came to: its [error] in red, or [done] in green.
  static void _result(
    ScaffoldMessengerState messenger,
    String? error,
    String done,
  ) {
    _snack(
      messenger,
      error ?? done,
      kind: error == null ? MessageKind.success : MessageKind.error,
    );
  }

  /// The role-specific buttons for [order], most important last. Shared by
  /// the list card and the details screen so they never disagree. Only
  /// transitions the order workflow actually supports are offered: the
  /// farmer moves an order forward, reports a delay or cancels a confirmed
  /// order with a reason; a buyer can cancel until the farmer answers, answers
  /// a proposed new date, and confirms what was sent.
  static List<OrderCardAction> actionsFor(
    BuildContext context,
    OrderInfo order,
    OrderRole role,
  ) {
    if (order.isCompleted) {
      return [
        if (role == OrderRole.buyer && !order.reviewed)
          OrderCardAction('Review', () => review(context, order)),
        OrderCardAction(
          tl('View Receipt'),
          () => viewReceipt(context, order.id),
          kind: OrderActionKind.primary,
        ),
      ];
    }
    if (role == OrderRole.buyer) {
      // Sent or ready for pick-up: the buyer confirms it arrived.
      if (order.status == 'shipped') {
        return [
          OrderCardAction(
            tl('Order Received'),
            () => confirmReceived(context, order),
            kind: OrderActionKind.primary,
          ),
        ];
      }
      // Until the farmer answers, the buyer can change their mind.
      if (order.status == 'pending') {
        return [
          OrderCardAction(
            tl('Cancel Order'),
            () => cancelPending(context, order),
            kind: OrderActionKind.destructive,
          ),
        ];
      }
      // A proposed new date is the other thing a buyer answers: accept it,
      // or cancel. (Message Farmer is on the order details screen.)
      if (!order.isDelayed) return const [];
      return [
        OrderCardAction(
          tl('Cancel Order'),
          () => cancelDelayed(context, order),
          kind: OrderActionKind.destructive,
        ),
        OrderCardAction(
          tl('Accept New Date'),
          () => acceptNewDate(context, order),
          kind: OrderActionKind.primary,
        ),
      ];
    }
    return switch (order.status) {
      'pending' => [
        OrderCardAction(
          tl('Reject'),
          () => reject(context, order),
          kind: OrderActionKind.destructive,
        ),
        OrderCardAction(
          tl('Accept'),
          () => accept(context, order),
          kind: OrderActionKind.primary,
        ),
      ],
      'confirmed' => [
        OrderCardAction(
          tl('Cancel Order'),
          () => cancelConfirmed(context, order),
          kind: OrderActionKind.destructive,
        ),
        // Weather, transport, supply… — propose a new date instead of
        // letting the order silently run late.
        OrderCardAction(
          order.isDelayed ? tl('Update Delay') : tl('Report Delay'),
          () => reportDelay(context, order),
        ),
        OrderCardAction(
          order.isPickup ? tl('Ready for Pick-up') : tl('Mark as Shipped'),
          () => markShipped(context, order),
          kind: OrderActionKind.primary,
        ),
      ],
      'shipped' => [
        // The buyer confirms first; see kBuyerConfirmWindow.
        if (order.farmerCanComplete(DateTime.now()))
          OrderCardAction(
            tl('Mark as Completed'),
            () => markCompleted(context, order),
            kind: OrderActionKind.primary,
          )
        else
          OrderCardAction(
            tl('Waiting for Buyer'),
            () => explainWaiting(context, order),
          ),
      ],
      _ => const [],
    };
  }

  static Future<void> accept(BuildContext context, OrderInfo order) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showAgriConfirm(
      context: context,
      icon: Icons.assignment_turned_in_outlined,
      title: tl('Accept this order?'),
      message: tl('{0} of {1} for {2}.', [
        order.quantityLabel,
        order.productName,
        order.buyerName,
      ]),
      confirmLabel: tl('Accept'),
    );
    if (!ok) return;
    final err = await _orders.updateStatus(order.id, 'confirmed');
    _result(messenger, err, tl('Order confirmed.'));
  }

  static Future<void> reject(BuildContext context, OrderInfo order) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showAgriConfirm(
      context: context,
      icon: Icons.cancel_outlined,
      tone: AgriTone.destructive,
      title: tl('Reject this order?'),
      message: tl('The item quantity will be returned to your inventory.'),
      confirmLabel: tl('Reject'),
    );
    if (!ok) return;
    final err = await _orders.rejectOrder(order.id);
    _result(messenger, err, tl('Order rejected.'));
  }

  // ---- Delay / reschedule ----

  /// Farmer: "Report Delay / Reschedule" on a confirmed order — pick a
  /// reason, propose a new date and optionally add a short note. The buyer
  /// is notified and decides; the order itself (id, stock, prices) is left
  /// exactly as it is.
  static Future<void> reportDelay(BuildContext context, OrderInfo order) async {
    final messenger = ScaffoldMessenger.of(context);
    // The sheet owns its text fields (and disposes them once it has fully
    // closed), so nothing is used after it is gone.
    final report = await showAgriSheet<DelayReport>(
      context: context,
      isScrollControlled: true,
      title: tl('Report Delay / Reschedule'),
      builder: (_) => ReportDelaySheet(order: order),
    );
    if (report == null) return;

    final err = await _orders.reportDelay(
      id: order.id,
      reason: report.reason,
      otherReason: report.otherReason,
      proposedDate: report.proposedDate,
      note: report.note,
    );
    _result(
      messenger,
      err,
      tl('Delay reported. Waiting for {0} to respond.', [order.buyerName]),
    );
  }

  /// Buyer: "Order Received" — they have the order, so it is completed
  /// (receipt issued, review unlocked, the farmer told).
  static Future<void> confirmReceived(
    BuildContext context,
    OrderInfo order,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showAgriConfirm(
      context: context,
      icon: Icons.inventory_2_outlined,
      title: tl('Received your order?'),
      message: tl(
        'Confirm that you have received {0} of {1}. This completes the order and issues its receipt.',
        [order.quantityLabel, order.productName],
      ),
      confirmLabel: tl('Received'),
    );
    if (!ok) return;
    final err = await _orders.confirmReceived(order.id);
    _result(
      messenger,
      err,
      tl('Order completed. Your receipt is now available.'),
    );
  }

  /// Buyer: accept the farmer's proposed date.
  static Future<void> acceptNewDate(
    BuildContext context,
    OrderInfo order,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final date = order.delayProposedDate;
    final ok = await showAgriConfirm(
      context: context,
      icon: Icons.event_available_outlined,
      title: tl('Accept the new date?'),
      message: tl(
        '{0} proposed {1} for your {2} order. Your order stays as it is — only the date changes.',
        [
          order.sellerName,
          date == null
              ? 'a new date'
              : MaterialLocalizations.of(context).formatMediumDate(date),
          order.productName,
        ],
      ),
      // Short labels, so the two buttons stay one line each.
      confirmLabel: tl('Accept'),
    );
    if (!ok) return;
    final err = await _orders.acceptProposedDate(order.id);
    _result(messenger, err, tl('New date accepted.'));
  }

  /// Buyer: cancel an order instead of accepting its new date.
  // Why the farmer cannot complete it yet, and from when they can.
  static void explainWaiting(BuildContext context, OrderInfo order) {
    final from = order.farmerCanCompleteAt;
    _snack(
      ScaffoldMessenger.of(context),
      tl(
        'Waiting for {0} to tap Order Received. If they do not, you can complete it from {1}.',
        [
          order.buyerName,
          from == null
              ? ''
              : MaterialLocalizations.of(context).formatMediumDate(from),
        ],
      ),
      kind: MessageKind.info,
    );
  }

  static Future<void> cancelConfirmed(
    BuildContext context,
    OrderInfo order,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final reason = await showAgriSheet<String>(
      context: context,
      isScrollControlled: true,
      title: tl('Cancel this order?'),
      builder: (_) => const CancelOrderSheet(),
    );
    if (reason == null) return;
    final err = await _orders.cancelConfirmedOrder(order.id, reason);
    _result(messenger, err, tl('Order cancelled.'));
  }

  static Future<void> cancelPending(
    BuildContext context,
    OrderInfo order,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showAgriConfirm(
      context: context,
      icon: Icons.cancel_outlined,
      tone: AgriTone.destructive,
      title: tl('Cancel this order?'),
      message: tl('Your {0} order will be cancelled. This cannot be undone.', [
        order.productName,
      ]),
      cancelLabel: tl('Keep Order'),
      confirmLabel: tl('Cancel Order'),
    );
    if (!ok) return;
    final err = await _orders.cancelPendingOrder(order.id);
    _result(messenger, err, tl('Order cancelled.'));
  }

  static Future<void> cancelDelayed(
    BuildContext context,
    OrderInfo order,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showAgriConfirm(
      context: context,
      icon: Icons.cancel_outlined,
      tone: AgriTone.destructive,
      title: tl('Cancel this order?'),
      message: tl('Your {0} order will be cancelled. This cannot be undone.', [
        order.productName,
      ]),
      cancelLabel: tl('Keep Order'),
      confirmLabel: tl('Cancel Order'),
    );
    if (!ok) return;
    final err = await _orders.cancelDelayedOrder(order.id);
    _result(messenger, err, tl('Order cancelled.'));
  }

  static Future<void> markShipped(BuildContext context, OrderInfo order) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showAgriConfirm(
      context: context,
      icon: order.isPickup
          ? Icons.inventory_2_outlined
          : Icons.local_shipping_outlined,
      title: order.isPickup ? tl('Ready for pick-up?') : tl('Mark as shipped?'),
      message: order.isPickup
          ? tl('{0} is ready for {1} to pick up.', [
              order.productName,
              order.buyerName,
            ])
          : tl('{0} is on its way to {1}.', [
              order.productName,
              order.buyerName,
            ]),
      confirmLabel: tl('Confirm'),
    );
    if (!ok) return;
    final err = await _orders.updateStatus(order.id, 'shipped');
    _result(
      messenger,
      err,
      (order.isPickup
          ? tl('Order marked ready for pick-up.')
          : tl('Order marked shipped.')),
    );
  }

  static Future<void> markCompleted(
    BuildContext context,
    OrderInfo order,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showAgriConfirm(
      context: context,
      icon: Icons.task_alt_rounded,
      title: tl('Mark as completed?'),
      message: tl(
        '{0} has received {1}. This finalizes the transaction and issues its receipt, and cannot be undone.',
        [order.buyerName, order.productName],
      ),
      confirmLabel: tl('Complete'),
    );
    if (!ok) return;
    final err = await _orders.updateStatus(order.id, 'completed');
    _result(
      messenger,
      err,
      tl('Order completed. The receipt is now available.'),
    );
    // Tied to the status change itself, not to anyone opening a screen.
    if (err == null) unawaited(_deliverReceipt(order));
  }

  /// Puts the receipt card of a just-completed order into the farmer–buyer
  /// conversation. The issueOrderReceipt Cloud Function does the same from
  /// the status change; whichever gets there first wins and the other finds
  /// the message already there (its id is derived from the order id, and
  /// Firestore rules refuse to overwrite it) — so it is sent exactly once.
  static Future<String?> _deliverReceipt(OrderInfo order) async {
    try {
      final conversationId = await _messages.ensureOrderConversation(
        sellerId: order.sellerId,
        sellerName: order.sellerName,
        buyerId: order.buyerId,
        buyerName: order.buyerName,
        productId: order.productId,
        productName: order.productName,
        productImageUrl: order.imageUrl,
      );
      try {
        await _messages.sendReceiptMessage(
          conversationId: conversationId,
          buyerId: order.buyerId,
          orderId: order.id,
          orderDisplayId: order.displayId,
          receiptNumber: receiptNumberFor(order.id, order.createdAt),
          productId: order.productId,
          productName: order.productName,
          subtotal: order.subtotal,
          total: order.grandTotal,
        );
      } catch (_) {
        // Already sent by the system in the meantime — it's in the chat.
      }
      return conversationId;
    } catch (_) {
      return null; // Offline etc. — the Cloud Function still delivers it.
    }
  }

  static void openDetails(
    BuildContext context,
    OrderInfo order,
    OrderRole role,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            OrderDetailsScreen(orderId: order.id, role: role, initial: order),
      ),
    );
  }

  static void viewReceipt(BuildContext context, String orderId) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => OrderReceiptScreen(orderId: orderId)),
    );
  }

  /// Opens the farmer–buyer conversation for [order] (the existing one if
  /// they have already chatted).
  static Future<void> message(
    BuildContext context,
    OrderInfo order,
    OrderRole role, {
    bool withReceipt = false,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final String conversationId;
    try {
      conversationId = await _messages.ensureOrderConversation(
        sellerId: order.sellerId,
        sellerName: order.sellerName,
        buyerId: order.buyerId,
        buyerName: order.buyerName,
        productId: order.productId,
        productName: order.productName,
        productImageUrl: order.imageUrl,
      );
    } catch (e) {
      _snack(
        messenger,
        e is StateError ? e.message : tl('Could not open the conversation.'),
        kind: MessageKind.error,
      );
      return;
    }

    if (withReceipt && role == OrderRole.farmer && order.isCompleted) {
      await _deliverReceipt(order);
    }

    navigator.push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          conversationId: conversationId,
          otherUserId: order.otherPartyId(role),
          otherUserName: order.otherPartyName(role),
          isFarmer: role == OrderRole.farmer,
          productId: order.productId,
          productName: order.productName,
          productImageUrl: order.imageUrl,
        ),
      ),
    );
  }

  /// Opens the review form for a completed order — only for the buyer of
  /// that exact order. (ReviewService and Firestore rules enforce the same.)
  /// Returns true if a review was submitted.
  static Future<bool> review(BuildContext context, OrderInfo order) async {
    final messenger = ScaffoldMessenger.of(context);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid != order.buyerId) {
      _snack(
        messenger,
        tl('Only the buyer of this order can review it.'),
        kind: MessageKind.error,
      );
      return false;
    }
    if (!order.isCompleted) {
      _snack(
        messenger,
        tl('You can review this product once the order is completed.'),
        kind: MessageKind.info,
      );
      return false;
    }
    if (order.productId.isEmpty || order.sellerId.isEmpty) {
      _snack(
        messenger,
        tl('Missing product info for review.'),
        kind: MessageKind.error,
      );
      return false;
    }
    final done = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AddReviewScreen(
          orderId: order.id,
          productId: order.productId,
          productName: order.productName,
          sellerId: order.sellerId,
          productImage: order.imageUrl,
        ),
      ),
    );
    return done == true;
  }
}

/// What the farmer filled in on the Report Delay sheet.
class DelayReport {
  final String reason;
  final String otherReason;
  final DateTime proposedDate;
  final String note;

  const DelayReport({
    required this.reason,
    required this.otherReason,
    required this.proposedDate,
    required this.note,
  });
}

/// Report Delay / Reschedule: the reason from a dropdown — "Other" opens a
/// box for the farmer's own words, at most 100 characters — the proposed
/// new date and an optional note. Send to Buyer is available once a date
/// is chosen (and, for Other, the reason written); it closes the sheet with
/// a [DelayReport].
class ReportDelaySheet extends StatefulWidget {
  final OrderInfo order;
  const ReportDelaySheet({super.key, required this.order});

  @override
  State<ReportDelaySheet> createState() => _ReportDelaySheetState();
}

/// The farmer's reason for cancelling a confirmed order. Resolves to the
/// reason, or null if they keep the order.
class CancelOrderSheet extends StatefulWidget {
  const CancelOrderSheet({super.key});

  @override
  State<CancelOrderSheet> createState() => _CancelOrderSheetState();
}

class _CancelOrderSheetState extends State<CancelOrderSheet> {
  static const int maxLength = 200;

  late final _reason = TextEditingController()
    ..addListener(() => setState(() {}));

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        18,
        4,
        18,
        18 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            tl(
              'The buyer is told your reason, and the stock goes back to your listing. This cannot be undone.',
            ),
            style: TextStyle(fontSize: 12.5, color: AppColors.grey(700)),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _reason,
            style: const TextStyle(fontSize: 14),
            maxLength: maxLength,
            maxLines: 3,
            minLines: 2,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: tl('Why are you cancelling this order?'),
            ),
          ),
          const SizedBox(height: 10),
          ElevatedButton(
            onPressed: _reason.text.trim().isEmpty
                ? null
                : () => Navigator.pop(context, _reason.text.trim()),
            style: AppTheme.primaryButton().copyWith(
              shape: const WidgetStatePropertyAll(StadiumBorder()),
            ),
            child: Text(tl('Cancel Order'), style: AppTheme.buttonText()),
          ),
        ],
      ),
    );
  }
}

class _ReportDelaySheetState extends State<ReportDelaySheet> {
  static const int otherMaxLength = 100;

  late String _reason = kOrderDelayReasons.containsKey(widget.order.delayReason)
      ? widget.order.delayReason
      : 'weather';
  late final _other = TextEditingController(text: widget.order.delayOtherReason)
    ..addListener(() => setState(() {}));
  late final _note = TextEditingController(text: widget.order.delayNote);
  late DateTime? _date = _initialDate();

  DateTime get _today => DateUtils.dateOnly(DateTime.now());

  DateTime? _initialDate() {
    final proposed = widget.order.delayProposedDate;
    return proposed == null || proposed.isBefore(_today) ? null : proposed;
  }

  @override
  void dispose() {
    _other.dispose();
    _note.dispose();
    super.dispose();
  }

  bool get _isOther => _reason == 'other';
  bool get _canSend =>
      _date != null && (!_isOther || _other.text.trim().isNotEmpty);

  // Every field is a white pill with a light border (the sheet itself is
  // light grey); the several-line note gets rounded corners instead (see
  // PillInputBorder).
  InputDecoration _field({String? hint, Widget? prefix}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(fontSize: 14, color: AppColors.grey(500)),
      prefixIcon: prefix,
      filled: true,
      fillColor: AppColors.surface,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      counterStyle: TextStyle(fontSize: 11, color: AppColors.grey(500)),
      border: AppTheme.fieldBorder,
      enabledBorder: AppTheme.fieldBorder,
      focusedBorder: AppTheme.fieldFocusBorder,
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 7),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: AppColors.brand,
      ),
    ),
  );

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? _today,
      firstDate: _today,
      lastDate: _today.add(const Duration(days: 730)),
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  // The reason list, in the field and in its open list.
  TextStyle get _reasonStyle => TextStyle(
    fontFamily: 'Montserrat',
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: AppColors.brand,
  );

  @override
  Widget build(BuildContext context) {
    final dateText = _date == null
        ? 'Choose a date'
        : MaterialLocalizations.of(context).formatMediumDate(_date!);
    // The sheet pads only its title: the same 18 px either side here, so
    // the text, the fields and the button all line up under it.
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 2, 18, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            tl(
              'Tell {0} why this order is delayed and propose a new date. They can accept it, cancel, or message you.',
              [widget.order.buyerName],
            ),
            style: TextStyle(
              fontSize: 12.5,
              color: AppColors.grey(700),
              height: 1.45,
            ),
          ),
          const SizedBox(height: 18),

          _label(tl('Reason')),
          // The list opens as the same white panel as every dropdown, as
          // wide as its longest reason (FittedDropdownField).
          FittedDropdownField<String>(
            value: _reason,
            labels: [for (final label in kOrderDelayReasons.values) tl(label)],
            dropdownColor: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            icon: Icon(
              Icons.keyboard_arrow_down_rounded,
              color: AppColors.brand,
              size: 20,
            ),
            decoration: AppTheme.dropdownDecoration(context, _field()),
            style: _reasonStyle,
            items: [
              for (final entry in kOrderDelayReasons.entries)
                DropdownMenuItem(
                  value: entry.key,
                  child: Text(tl(entry.value)),
                ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _reason = value);
            },
          ),
          // "Other": what it is, in the farmer's own words.
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: !_isOther
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: TextField(
                      controller: _other,
                      style: const TextStyle(fontSize: 14),
                      maxLength: otherMaxLength,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: _field(hint: tl('Specify the reason')),
                    ),
                  ),
          ),
          SizedBox(height: _isOther ? 6 : 16),

          _label(tl('Proposed new date')),
          InkWell(
            onTap: _pickDate,
            borderRadius: BorderRadius.circular(AppTheme.pillRadius),
            child: InputDecorator(
              decoration:
                  _field(
                    prefix: Padding(
                      padding: EdgeInsets.only(left: 16, right: 8),
                      child: Icon(
                        Icons.calendar_today_outlined,
                        size: 18,
                        color: AppColors.brand,
                      ),
                    ),
                  ).copyWith(
                    prefixIconConstraints: const BoxConstraints(minWidth: 0),
                    suffixIcon: Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.brand,
                    ),
                  ),
              child: Text(
                dateText,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: _date == null ? FontWeight.w500 : FontWeight.w600,
                  color: _date == null ? AppColors.grey(500) : AppColors.brand,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          _label(tl('Note to the buyer (optional)')),
          TextField(
            controller: _note,
            style: const TextStyle(fontSize: 14),
            maxLength: 200,
            maxLines: 3,
            minLines: 2,
            textCapitalization: TextCapitalization.sentences,
            decoration: _field(hint: tl('Anything else the buyer should know')),
          ),
          const SizedBox(height: 10),
          ElevatedButton(
            onPressed: _canSend
                ? () => Navigator.pop(
                    context,
                    DelayReport(
                      reason: _reason,
                      otherReason: _isOther ? _other.text.trim() : '',
                      proposedDate: _date!,
                      note: _note.text,
                    ),
                  )
                : null,
            style: AppTheme.primaryButton().copyWith(
              shape: const WidgetStatePropertyAll(StadiumBorder()),
            ),
            child: Text(tl('Send to Buyer'), style: AppTheme.buttonText()),
          ),
        ],
      ),
    );
  }
}
