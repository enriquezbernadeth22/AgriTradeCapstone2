import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../l10n/app_language.dart';
import '../services/order_format.dart';
import '../theme/app_colors.dart';
import '../widgets/agri_app_bar.dart';
import '../widgets/chat_photo_viewer.dart';
import '../widgets/profile_avatar.dart';
import 'order_details_screen.dart';

/// A buyer's profile as a farmer sees it, opened from the buyer's photo in
/// Conversation Info. Only what the marketplace already shares
/// (publicProfiles: photo, name, kind of buyer, general area, member since)
/// and the orders this buyer placed with this farmer — never their email,
/// phone number or orders with anyone else.
class BuyerPublicProfileScreen extends StatefulWidget {
  final String buyerId;

  /// The name the chat already knows, shown until the profile loads.
  final String fallbackName;

  /// publicProfiles/{buyerId}, without Firestore.
  @visibleForTesting
  final Stream<Map<String, dynamic>?>? profileStream;

  /// This farmer's orders from the buyer, without Firestore.
  @visibleForTesting
  final Stream<List<OrderInfo>>? ordersStream;

  const BuyerPublicProfileScreen({
    super.key,
    required this.buyerId,
    this.fallbackName = '',
    this.profileStream,
    this.ordersStream,
  });

  /// How many of the latest orders are listed.
  static const int recentOrders = 5;

  @override
  State<BuyerPublicProfileScreen> createState() =>
      _BuyerPublicProfileScreenState();
}

class _BuyerPublicProfileScreenState extends State<BuyerPublicProfileScreen> {
  late final Stream<Map<String, dynamic>?> _profile =
      widget.profileStream ??
      FirebaseFirestore.instance
          .collection('publicProfiles')
          .doc(widget.buyerId)
          .snapshots()
          .map((doc) => doc.data());

  // The farmer may list only their own orders (firestore.rules), so the
  // query is theirs, narrowed to this buyer.
  late final Stream<List<OrderInfo>> _orderStream =
      widget.ordersStream ??
      FirebaseFirestore.instance
          .collection('orders')
          .where(
            'sellerId',
            isEqualTo: FirebaseAuth.instance.currentUser?.uid ?? '',
          )
          .where('buyerId', isEqualTo: widget.buyerId)
          .snapshots()
          .map((snap) => [for (final doc in snap.docs) OrderInfo.fromDoc(doc)]);

  // The orders as they last came in, shared by this page and its "View all
  // orders" list: one live query for both, so they always agree.
  final _orders = ValueNotifier<AsyncSnapshot<List<OrderInfo>>>(
    const AsyncSnapshot.waiting(),
  );
  StreamSubscription<List<OrderInfo>>? _ordersSub;

  @override
  void initState() {
    super.initState();
    _ordersSub = _orderStream.listen(
      (orders) => _orders.value = AsyncSnapshot.withData(
        ConnectionState.active,
        orders,
      ),
      onError: (Object error) => _orders.value = AsyncSnapshot.withError(
        ConnectionState.active,
        error,
      ),
    );
  }

  @override
  void dispose() {
    _ordersSub?.cancel();
    _orders.dispose();
    super.dispose();
  }

  // Newest first.
  static List<OrderInfo> _newestFirst(List<OrderInfo> orders) => [...orders]
    ..sort(
      (a, b) =>
          (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)),
    );

  void _openAllOrders(String name) => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => Scaffold(
        backgroundColor: AppColors.surfaceAlt,
        appBar: AgriAppBar(title: tl('Orders from {0}', [name])),
        body: ValueListenableBuilder<AsyncSnapshot<List<OrderInfo>>>(
          valueListenable: _orders,
          builder: (context, snap, _) {
            final orders = _newestFirst(snap.data ?? const []);
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                _privacyNote(),
                const SizedBox(height: 10),
                _card(
                  child: Column(
                    children: [
                      for (var i = 0; i < orders.length; i++) ...[
                        if (i > 0)
                          Divider(height: 1, color: AppColors.grey(200)),
                        _orderRow(orders[i]),
                      ],
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );

  // Said where the orders are, so it is seen however long the list is.
  Widget _privacyNote() => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(Icons.lock_outline_rounded, size: 15, color: AppColors.grey(600)),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
          tl(
            'Only you see your orders with this buyer. Their email and phone number are not shown here.',
          ),
          style: _muted(size: 11.5),
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceAlt,
      appBar: AgriAppBar(title: tl('Buyer Profile')),
      body: StreamBuilder<Map<String, dynamic>?>(
        stream: _profile,
        builder: (context, profileSnap) {
          final profile = profileSnap.data ?? const <String, dynamic>{};
          final liveName = (profile['name'] ?? '').toString().trim();
          final name = liveName.isNotEmpty ? liveName : widget.fallbackName;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
            children: [
              _header(profile, name),
              const SizedBox(height: 18),
              // No loading bar: the section opens in smoothly once the
              // orders are here (usually at once, from the phone's copy),
              // and stays live — a new order or status shows by itself.
              ValueListenableBuilder<AsyncSnapshot<List<OrderInfo>>>(
                valueListenable: _orders,
                builder: (context, ordersSnap, _) {
                  final Widget section;
                  if (ordersSnap.hasError) {
                    section = _ordersSection(
                      _card(
                        child: Text(
                          tl('Could not load your orders with this buyer.'),
                          style: _muted(),
                        ),
                      ),
                    );
                  } else if (ordersSnap.hasData) {
                    section = _ordersSection(
                      _ordersCard(ordersSnap.data!, name),
                    );
                  } else {
                    section = const SizedBox(width: double.infinity);
                  }
                  return AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    alignment: Alignment.topCenter,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: section,
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _header(Map<String, dynamic> profile, String name) {
    final photoUrl = (profile['photoUrl'] ?? '').toString();
    final buyerType = (profile['buyerType'] ?? '').toString().trim();
    final area = [
      profile['barangay'],
      profile['municipality'],
      profile['province'],
    ].whereType<String>().where((s) => s.trim().isNotEmpty).join(', ');
    final memberSince = profile['memberSince'];
    return Column(
      children: [
        // The photo opens full screen, as in the chat.
        GestureDetector(
          onTap: photoUrl.isEmpty
              ? null
              : () => openChatPhoto(context, photoUrl, caption: name),
          child: ProfileAvatar(photoUrl: photoUrl, name: name, radius: 44),
        ),
        const SizedBox(height: 12),
        Text(
          name,
          textAlign: TextAlign.center,
          style: GoogleFonts.montserrat(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.text,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          buyerType.isEmpty ? tl('Buyer') : '${tl('Buyer')} · ${tl(buyerType)}',
          textAlign: TextAlign.center,
          style: GoogleFonts.montserrat(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: AppColors.grey(700),
          ),
        ),
        if (area.isNotEmpty) ...[
          const SizedBox(height: 6),
          _iconLine(Icons.place_outlined, area),
        ],
        if (memberSince is Timestamp) ...[
          const SizedBox(height: 4),
          _iconLine(
            Icons.event_outlined,
            tl('Member since {0}', [
              DateFormat('MMMM y').format(memberSince.toDate()),
            ]),
          ),
        ],
      ],
    );
  }

  Widget _iconLine(IconData icon, String text) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Icon(icon, size: 15, color: AppColors.grey(600)),
      const SizedBox(width: 4),
      Flexible(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: GoogleFonts.montserrat(
            fontSize: 12.5,
            color: AppColors.grey(700),
          ),
        ),
      ),
    ],
  );

  // "Orders with you", who sees them, then the card.
  Widget _ordersSection(Widget card) => Column(
    key: const ValueKey('ordersSection'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _sectionTitle(tl('Orders with you')),
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
        child: _privacyNote(),
      ),
      card,
    ],
  );

  Widget _ordersCard(List<OrderInfo> orders, String name) {
    if (orders.isEmpty) {
      return _card(
        child: Text(
          tl('{0} has not ordered from you yet.', [name]),
          style: _muted(),
        ),
      );
    }
    final completed = orders.where((o) => o.status == 'completed').length;
    final ended = orders
        .where((o) => o.status == 'cancelled' || o.status == 'rejected')
        .length;
    final active = orders.length - completed - ended;
    final recent = _newestFirst(orders);
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _stat(tl('Completed'), completed),
              const SizedBox(width: 8),
              _stat(tl('Active'), active),
              const SizedBox(width: 8),
              _stat(tl('Cancelled'), ended),
            ],
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: AppColors.grey(200)),
          const SizedBox(height: 4),
          for (final order in recent.take(
            BuyerPublicProfileScreen.recentOrders,
          ))
            _orderRow(order),
          // The rest are one tap away, not under the note.
          if (orders.length > BuyerPublicProfileScreen.recentOrders)
            Align(
              child: TextButton.icon(
                key: const Key('viewAllOrders'),
                onPressed: () => _openAllOrders(name),
                iconAlignment: IconAlignment.end,
                icon: const Icon(Icons.chevron_right_rounded, size: 18),
                label: Text(
                  tl('View all orders ({0})', [orders.length]),
                  style: GoogleFonts.montserrat(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.brand,
                  minimumSize: const Size(0, 34),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // One count on a pale green tile, so the numbers stand out.
  Widget _stat(String label, int count) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.tint,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            '$count',
            style: GoogleFonts.montserrat(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.brand,
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: _muted(size: 11.5)),
        ],
      ),
    ),
  );

  // One order: product, its number and date, and status; opens the order.
  Widget _orderRow(OrderInfo order) {
    final date = order.createdAt;
    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => OrderDetailsScreen(
            orderId: order.id,
            role: OrderRole.farmer,
            initial: order,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    order.productName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.montserrat(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      tl('Order #{0}', [order.displayId]),
                      if (date != null) DateFormat('MMM d, y').format(date),
                    ].join(' · '),
                    style: _muted(size: 11.5),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _statusChip(order.status),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: AppColors.grey(500),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusChip(String status) {
    final label = switch (status) {
      'pending' => tl('Pending'),
      'confirmed' => tl('Confirmed'),
      'shipped' => tl('Shipped'),
      'completed' => tl('Completed'),
      'rejected' => tl('Rejected'),
      'cancelled' => tl('Cancelled'),
      _ => status,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.grey(100),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.grey(300)),
      ),
      child: Text(
        label,
        style: GoogleFonts.montserrat(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: AppColors.text,
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 8),
    child: Text(
      text,
      style: GoogleFonts.montserrat(
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
        color: AppColors.grey(700),
      ),
    ),
  );

  Widget _card({required Widget child}) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      border: AppColors.cardBorder,
    ),
    child: child,
  );

  TextStyle _muted({double size = 12.5}) =>
      GoogleFonts.montserrat(fontSize: size, color: AppColors.grey(600));
}
