import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/firebase_refs.dart';
import '../widgets/docked_nav_bar.dart';
import '../widgets/page_header.dart';
import '../widgets/profile_cover_header.dart';
import '../widgets/profile_menu.dart';
import 'farmer_edit_profile_screen.dart';
import 'buyer_my_reviews_screen.dart';
import 'buyer_saved_products_screen.dart';
import 'buyer_fulfillment_preferences_screen.dart';
import 'appearance_screen.dart';
import 'help_support_screen.dart';
import 'manage_account_screen.dart';
import 'notification_preferences_screen.dart';
import '../widgets/feedback_sheet.dart';
import '../widgets/settings_sheet.dart';
import '../widgets/agri_refresh_indicator.dart';
import '../l10n/tr.dart';
import '../theme/app_colors.dart';
import '../l10n/app_language.dart';

/// The buyer's Profile tab. Same look as the farmer's (header, the
/// avatar with its edit badge, name, then role-specific content), with
/// buyer content: everything for the buyer
/// in groups — My Activity, Preferences & Account, Support & More — and
/// Log Out. A buyer has no Settings gear: the rows of the farmer's
/// Settings sheet are here instead, opening the same screens.
///
/// Shows only what is fine for the profile itself — photo, name and the
/// general saved location. The email address and other account details
/// live in Account Settings; the exact delivery details in
/// Delivery & Pickup.
class BuyerProfileScreen extends StatefulWidget {
  /// Opens Orders on its Completed tab (Purchase History).
  final VoidCallback? onOpenCompletedOrders;

  /// Log Out, with its confirmation (the buyer shell's own).
  final VoidCallback? onLogout;

  const BuyerProfileScreen({
    super.key,
    this.onOpenCompletedOrders,
    this.onLogout,
  });

  @override
  State<BuyerProfileScreen> createState() => _BuyerProfileScreenState();
}

class _BuyerProfileScreenState extends State<BuyerProfileScreen> {
  final String? _uid = FirebaseRefs.auth.currentUser?.uid;

  // Created once, not in build(), so a rebuild doesn't resubscribe.
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _profile =
      FirebaseRefs.firestore
          .collection('users')
          .doc(_uid ?? 'unknown')
          .snapshots();
  Future<void> _refreshData() async {
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    setState(() {});
  }

  void _open(Widget screen) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

  Color get _muted =>
      AppColors.isDark ? AppColors.textSecondary : const Color(0xFF757575);

  @override
  Widget build(BuildContext context) {
    final t = tr(context);
    final user = FirebaseRefs.auth.currentUser;

    // The header stays put; pull-to-refresh starts under it. On the cream
    // of Explore (2026-11-08).
    return ColoredBox(
      color: AppColors.page,
      child: Column(
        children: [
          // The band stays put; the title scrolls with the page below.
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
                    // ---- Title, cover, photo, name, general location ----
                    StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      stream: _profile,
                      builder: (context, snapshot) {
                        final data = snapshot.data?.data();
                        final name =
                            [
                                  data?['name'],
                                  data?['fullName'],
                                  user?.displayName,
                                ]
                                .map((v) => (v ?? '').toString().trim())
                                .firstWhere(
                                  (v) => v.isNotEmpty,
                                  orElse: () => tl('Buyer'),
                                );
                        final photoUrl =
                            data?['photoUrl']?.toString() ?? user?.photoURL;
                        // General area only — barangay and city, never a street
                        // address or a pin.
                        final location =
                            [data?['barangay'], data?['municipality']]
                                .map((v) => (v ?? '').toString().trim())
                                .where((v) => v.isNotEmpty)
                                .join(', ');

                        return Column(
                          children: [
                            ProfileCoverHeader(
                              title: tr(context).navProfile,
                              name: name,
                              photoUrl: photoUrl,
                              onEdit: () => _open(const EditProfileScreen()),
                            ),
                            const SizedBox(height: 8),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                              ),
                              child: Text(
                                name,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: 'Montserrat',
                                  fontSize: 19,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.heading,
                                ),
                              ),
                            ),
                            if (location.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.location_on_outlined,
                                      size: 14,
                                      color: _muted,
                                    ),
                                    const SizedBox(width: 3),
                                    Flexible(
                                      child: Text(
                                        location,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          color: _muted,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        );
                      },
                    ),

                    const SizedBox(height: 4),

                    // ---- The buyer's own options, each group on one white
                    // card (the user's design, 2026-11-08). ----
                    // The buyer has no Settings gear: what the farmer finds
                    // in the Settings sheet is here, in these groups.
                    ProfileMenuGroup(
                      title: tl('My Activity'),
                      children: [
                        ProfileLinkTile(
                          icon: Icons.rate_review_outlined,
                          label: t.myReviews,
                          onTap: () => _open(const BuyerMyReviewsScreen()),
                        ),
                        ProfileLinkTile(
                          icon: Icons.favorite_border_rounded,
                          label: t.likedProducts,
                          onTap: () => _open(const BuyerSavedProductsScreen()),
                        ),
                        // The completed orders, each with its receipt.
                        if (widget.onOpenCompletedOrders != null)
                          ProfileLinkTile(
                            icon: Icons.receipt_long_outlined,
                            label: tl('Purchase History'),
                            onTap: widget.onOpenCompletedOrders!,
                          ),
                      ],
                    ),
                    ProfileMenuGroup(
                      title: tl('Preferences & Account'),
                      children: [
                        ProfileLinkTile(
                          icon: Icons.local_shipping_outlined,
                          label: t.deliveryPickupPreferences,
                          onTap: () =>
                              _open(const BuyerFulfillmentPreferencesScreen()),
                        ),
                        ProfileLinkTile(
                          icon: Icons.manage_accounts_outlined,
                          label: t.manageAccount,
                          onTap: () => _open(const ManageAccountScreen()),
                        ),
                        ProfileLinkTile(
                          icon: Icons.notifications_none_rounded,
                          label: t.notificationSettings,
                          onTap: () =>
                              _open(const NotificationPreferencesScreen()),
                        ),
                        ProfileLinkTile(
                          icon: Icons.dark_mode_outlined,
                          label: tl('Appearance'),
                          onTap: () => _open(const AppearanceScreen()),
                        ),
                      ],
                    ),
                    ProfileMenuGroup(
                      title: tl('Support & More'),
                      children: [
                        ProfileLinkTile(
                          icon: Icons.share_outlined,
                          label: tl('Share AgriTrade+'),
                          onTap: () => shareAgriTrade(context),
                        ),
                        ProfileLinkTile(
                          icon: Icons.rate_review_outlined,
                          label: t.sendFeedback,
                          onTap: () => showFeedbackSheet(context),
                        ),
                        ProfileLinkTile(
                          icon: Icons.help_outline,
                          label: t.helpSupport,
                          onTap: () =>
                              _open(const HelpSupportScreen(farmer: false)),
                        ),
                      ],
                    ),
                    if (widget.onLogout != null) ...[
                      const SizedBox(height: 14),
                      // White with a thin dark green outline, icon and text.
                      LogOutButton(
                        label: t.logOut,
                        onTap: widget.onLogout!,
                        brandOutline: true,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
