import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../services/order_format.dart';
import 'orders_view.dart';

// The Farmer's Orders tab. Body-only — it renders inside the
// FarmerHomeScreen Scaffold (which already provides the AgriTrade+ app bar
// and bottom nav). The screen itself is shared with the Buyer side; see
// OrdersView.
class OrdersTab extends StatelessWidget {
  /// A status tab to open on request (Market's Orders Today opens
  /// Confirmed).
  final ValueListenable<String?>? showStatus;

  const OrdersTab({super.key, this.showStatus});

  @override
  Widget build(BuildContext context) =>
      OrdersView(role: OrderRole.farmer, showStatus: showStatus);
}
