import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/auth_service.dart';
import '../services/product_share_service.dart';
import '../services/notification_permission_prompt.dart';
import '../services/push_notification_service.dart';
import '../widgets/agri_dialog.dart';
import '../widgets/coach_mark.dart';
import '../widgets/swipeable_tabs.dart';
import '../widgets/unread_messages_dot.dart';
import '../widgets/unseen_orders_dot.dart';
import '../widgets/docked_nav_bar.dart';
import '../widgets/page_header.dart';
import 'farmer_settings_screen.dart';
import 'add_product_screen.dart';
import 'market_tab.dart';
import 'chat_list_screen.dart';
import 'farmer_orders_tab.dart';
import 'farmer_profile_tab.dart';
import 'notifications_screen.dart';
import 'role_selection_screen.dart';
import '../l10n/tr.dart';
import '../theme/app_colors.dart';
import '../widgets/password_change_prompt.dart';
import '../widgets/profile_photo_prompt.dart';
import '../l10n/app_language.dart';

// A one-shot "command channel", not persisted UI state: setting this while
// a FarmerHomeScreen is already mounted (e.g. from a notification tap, see
// NotificationNavigationService) switches its active tab in place instead
// of pushing a second, stacked Home screen. A fresh FarmerHomeScreen always
// takes its starting tab from its own `initialIndex` constructor argument,
// never from whatever this notifier was last set to.
final ValueNotifier<int> globalFarmerTabIndex = ValueNotifier<int>(0);

class FarmerHomeScreen extends StatefulWidget {
  final int initialIndex;

  const FarmerHomeScreen({super.key, this.initialIndex = 0});

  @override
  State<FarmerHomeScreen> createState() => _FarmerHomeScreenState();
}

class _FarmerHomeScreenState extends State<FarmerHomeScreen> {
  // 0 = Market, 1 = Messages, 2 = Orders, 3 = Profile
  late int _selectedIndex = widget.initialIndex;

  final _addProductKey = GlobalKey();
  final _ordersTabKey = GlobalKey();

  // Which status tab Orders should open (Market's Orders Today: Confirmed).
  final _ordersStatus = ValueNotifier<String?>(null);

  void _openOrders(String status) {
    // Set afresh, so asking for the same tab again still moves to it.
    _ordersStatus.value = null;
    _ordersStatus.value = status;
    setState(() => _selectedIndex = 2);
  }

  @override
  void initState() {
    super.initState();
    // If the app was launched (cold start) by tapping a push notification,
    // this replays that navigation now that routing has actually finished.
    PushNotificationService.consumePendingNavigation();
    // Likewise for a shared product link that opened the app.
    ProductLinkService.homeReady();
    globalFarmerTabIndex.addListener(_onGlobalTabIndexChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onEnteredApp());
  }

  // Runs once this home screen is actually on screen — i.e. after login,
  // email verification and admin approval are all behind the user. The
  // notification question (and the phone's own Allow) comes first, then
  // the first-time tour, so the two never appear on top of each other (the
  // user's order, 2026-11-07).
  Future<void> _onEnteredApp() async {
    await PasswordChangePrompt.onEnteredApp(context);
    if (!mounted) return;
    await ProfilePhotoPrompt.onEnteredApp(context);
    if (!mounted) return;
    await NotificationPermissionPrompt.instance.onEnteredApp(context);
    await _showWalkthrough();
  }

  void _onGlobalTabIndexChanged() {
    if (!mounted) return;
    setState(() => _selectedIndex = globalFarmerTabIndex.value);
  }

  @override
  void dispose() {
    globalFarmerTabIndex.removeListener(_onGlobalTabIndexChanged);
    _ordersStatus.dispose();
    super.dispose();
  }

  // A one-time, subtle tour pointing at the two things a brand-new farmer
  // most needs to find: posting their first listing, and where incoming
  // orders will show up.
  Future<void> _showWalkthrough() async {
    if (!mounted) return;
    await showCoachMarksOnce(
      context: context,
      prefsKey: 'walkthrough_seen_farmer',
      steps: [
        CoachMarkStep(
          targetKey: _addProductKey,
          title: tl('List your first product'),
          message: tl(
            'Tap here anytime to post crops or livestock for buyers to see.',
          ),
        ),
        CoachMarkStep(
          targetKey: _ordersTabKey,
          title: tl('Track incoming orders'),
          message: tl(
            'Orders from buyers show up here — you can accept, message, and update their status.',
          ),
        ),
      ],
    );
  }

  void _openAddProduct() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddProductScreen()),
    );
  }

  void _openNotifications() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const NotificationsScreen()),
    );
  }

  // The gear beside the Profile title: Settings, a page of its own (the
  // header no longer has a gear, the user's design of 2026-11-07).
  void _openSettings() => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) =>
          FarmerSettingsScreen(onLogout: () => _handleLogout(context)),
    ),
  );

  Future<void> _handleLogout(BuildContext context) async {
    final confirm = await showAgriConfirm(
      context: context,
      icon: Icons.logout,
      tone: AgriTone.destructive,
      title: tr(context).logOut,
      message: tr(context).logOutConfirm,
      confirmLabel: tr(context).logOut,
    );
    if (!confirm) return;

    await AuthService().logOut();
    if (!context.mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        // On a non-Market tab, the back button returns to Market first.
        if (_selectedIndex != 0) {
          setState(() => _selectedIndex = 0);
          return;
        }
        final shouldExit = await showAgriConfirm(
          context: context,
          icon: Icons.exit_to_app,
          title: tr(context).exitAppTitle,
          message: tr(context).exitAppMessage,
          confirmLabel: tr(context).exit,
        );
        if (shouldExit) {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.page,
        // The page runs on behind the floating bar, with no band around it.
        extendBody: true,
        // ---- Bottom navigation bar (Market · Messages · + · Orders · Profile) ----
        // The floating dark green bar, always on screen.
        bottomNavigationBar: DockedNavBar(
          children: [
            _navItem(
              0,
              Icons.storefront_outlined,
              Icons.storefront,
              tr(context).navMarket,
              // Icons.storefront is still an outline, so the selected tab
              // draws the same shop filled in, like the other tabs.
              activeIconBuilder: (color, size) =>
                  FilledStorefrontIcon(color: color, size: size),
            ),
            _navItem(
              1,
              Icons.mail_outline,
              Icons.mail,
              tr(context).navMessages,
              showUnreadDot: true,
            ),
            _buildAddButton(),
            _navItem(
              2,
              Icons.shopping_bag_outlined,
              Icons.shopping_bag,
              tr(context).navOrders,
              key: _ordersTabKey,
              showUnseenOrdersDot: true,
            ),
            _navItem(
              3,
              Icons.person_outline,
              Icons.person,
              tr(context).navProfile,
            ),
          ],
        ),

        // ---- Each tab lives in its own file now ----
        // Note: no longer `const [...]` — MarketTab now takes a callback
        // closure (onNavigateToTab), which can't be const.
        // No app bar: every tab starts with its own green header — logo and
        // title, see PageHeader — and the status bar strip above it is the
        // same green (PageHeaderSafeArea).
        body: PageHeaderSafeArea(
          // Swipe left or right to move between the tabs, as well as
          // tapping them in the bar below.
          // The header's logo opens Market from any tab, and every tab's
          // header has the notification bell; Settings is on Profile.
          child: HomeLogoAction(
            onTap: () => setState(() => _selectedIndex = 0),
            onNotifications: _openNotifications,
            child: SwipeableTabs(
              index: _selectedIndex,
              onIndexChanged: (i) => setState(() => _selectedIndex = i),
              children: [
                MarketTab(
                  onNavigateToTab: (i) => setState(() => _selectedIndex = i),
                  onOpenOrders: _openOrders,
                  onNotificationsPressed: _openNotifications,
                ),
                const ChatListScreen(),
                OrdersTab(
                  showStatus: _ordersStatus,
                  active: _selectedIndex == 2,
                ),
                ProfileTab(onOpenSettings: _openSettings),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _navItem(
    int index,
    IconData icon,
    IconData activeIcon,
    String label, {
    Key? key,
    bool showUnreadDot = false,
    bool showUnseenOrdersDot = false,
    Widget Function(Color color, double size)? activeIconBuilder,
  }) {
    return NavBarItem(
      key: key,
      icon: icon,
      activeIcon: activeIcon,
      activeIconBuilder: activeIconBuilder,
      label: label,
      selected: _selectedIndex == index,
      onTap: () => setState(() => _selectedIndex = index),
      decorateIcon: showUnreadDot
          ? (icon) => UnreadMessagesDot(child: icon)
          : showUnseenOrdersDot
          ? (icon) => UnseenOrdersDot(child: icon)
          : null,
    );
  }

  Widget _buildAddButton() {
    return Expanded(
      child: Center(
        // Small, rising just above the bar.
        child: Transform.translate(
          offset: const Offset(0, -8),
          child: InkWell(
            onTap: _openAddProduct,
            customBorder: const CircleBorder(),
            child: Container(
              key: _addProductKey,
              width: 40,
              height: 40,
              // Gold, the bar's selected colour: dark green would vanish
              // into the dark green bar.
              decoration: BoxDecoration(
                color: DockedNavBar.selectedColor,
                shape: BoxShape.circle,
                // A soft lift; in dark mode a plain shadow, not a glow.
                boxShadow: [
                  BoxShadow(
                    color: AppColors.isDark
                        ? Colors.black.withValues(alpha: 0.35)
                        : Colors.black.withValues(alpha: 0.22),
                    blurRadius: AppColors.isDark ? 6 : 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: const Icon(Icons.add, color: DockedNavBar.color, size: 24),
            ),
          ),
        ),
      ),
    );
  }
}
