import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/filters_on_scroll.dart';
import '../services/auth_service.dart';
import '../services/product_share_service.dart';
import '../services/notification_permission_prompt.dart';
import '../services/push_notification_service.dart';
import 'role_selection_screen.dart';
import '../widgets/agri_dialog.dart';
import '../widgets/coach_mark.dart';
import '../widgets/swipeable_tabs.dart';
import '../widgets/unread_messages_dot.dart';
import '../widgets/docked_nav_bar.dart';
import '../widgets/page_header.dart';
import 'buyer_explore_screen.dart';
import 'chat_list_screen.dart';
import 'buyer_orders_screen.dart';
import 'buyer_profile_screen.dart';
import 'notifications_screen.dart';
import '../l10n/tr.dart';
import '../theme/app_colors.dart';
import '../widgets/profile_photo_prompt.dart';
import '../l10n/app_language.dart';

// A one-shot "command channel", not persisted UI state — see the matching
// comment on globalFarmerTabIndex in farmer_home_screen.dart.
final ValueNotifier<int> globalMarketplaceIndex = ValueNotifier<int>(0);

class BuyerMarketplaceScreen extends StatefulWidget {
  final int initialIndex;

  const BuyerMarketplaceScreen({super.key, this.initialIndex = 0});

  @override
  State<BuyerMarketplaceScreen> createState() => _BuyerMarketplaceScreenState();
}

class _BuyerMarketplaceScreenState extends State<BuyerMarketplaceScreen> {
  late int _navIndex;

  // Explore, for Back: a scrolled-down Explore goes back to its top first.
  final _exploreKey = GlobalKey<BuyerExploreScreenState>();

  // Which status tab Orders should open (the Profile's Completed Orders).
  final _ordersStatus = ValueNotifier<String?>(null);

  void _openOrders(String status) {
    setState(() => _navIndex = 2);
    // Set again even if unchanged, so Orders follows it every time.
    _ordersStatus.value = null;
    _ordersStatus.value = status;
  }

  final _notificationsKey = GlobalKey();
  final _ordersTabKey = GlobalKey();
  final _locationKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _navIndex = widget
        .initialIndex; // Properly initializes to index 1 (Messages) when passed from chat
    // If the app was launched (cold start) by tapping a push notification,
    // this replays that navigation now that routing has actually finished.
    PushNotificationService.consumePendingNavigation();
    // Likewise for a shared product link that opened the app.
    ProductLinkService.homeReady();
    globalMarketplaceIndex.addListener(_onGlobalIndexChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onEnteredApp());
  }

  // Runs once this home screen is actually on screen — i.e. after login
  // and email verification are behind the user. The notification question
  // (and the phone's own Allow) comes first, then the first-time tour, so
  // the two never appear on top of each other (the user's order,
  // 2026-11-07).
  Future<void> _onEnteredApp() async {
    await ProfilePhotoPrompt.onEnteredApp(context);
    if (!mounted) return;
    await NotificationPermissionPrompt.instance.onEnteredApp(context);
    await _showWalkthrough();
  }

  void _onGlobalIndexChanged() {
    if (!mounted) return;
    setState(() => _navIndex = globalMarketplaceIndex.value);
  }

  @override
  void dispose() {
    globalMarketplaceIndex.removeListener(_onGlobalIndexChanged);
    _ordersStatus.dispose();
    super.dispose();
  }

  // A one-time tour of what a brand-new buyer would not find by themselves:
  // shopping by area, and where their orders are followed. (The bell needs
  // no explaining.)
  Future<void> _showWalkthrough() async {
    if (!mounted) return;
    await showCoachMarksOnce(
      context: context,
      prefsKey: 'walkthrough_seen_buyer',
      steps: [
        CoachMarkStep(
          targetKey: _locationKey,
          title: tl('Shop by area'),
          message: tl(
            'Pick a barangay to see only what is sold there. Listings that deliver to you come first.',
          ),
        ),
        CoachMarkStep(
          targetKey: _ordersTabKey,
          title: tl('Track your orders'),
          message: tl(
            'Everything you order shows up here, from pending to delivered.',
          ),
        ),
      ],
    );
  }

  Future<void> _logout(BuildContext context) async {
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
    // A new tab starts with the bottom bar showing.
    if (_navShownFor != _navIndex) {
      _navShownFor = _navIndex;
      _navHidden = false;
      _navOnScroll.reset();
    }
    final pages = <Widget>[
      BuyerExploreScreen(
        key: _exploreKey,
        bellKey: _notificationsKey,
        locationKey: _locationKey,
        onNotificationsPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const NotificationsScreen()),
        ),
      ),
      const ChatListScreen(),
      BuyerOrdersScreen(
        onBrowseMarketplace: () => setState(() => _navIndex = 0),
        showStatus: _ordersStatus,
        active: _navIndex == 2,
      ),
      BuyerProfileScreen(
        onOpenCompletedOrders: () => _openOrders('completed'),
        onLogout: () => _logout(context),
      ),
    ];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        // Like the farmer's: Back returns to Explore first, then offers to
        // close the app — it never logs out (that is in the Settings sheet).
        if (_navIndex != 0) {
          setState(() => _navIndex = 0);
          return;
        }
        // Scrolled down on Explore: Back returns to the top, with a fresh
        // mix of products, before it offers to close the app.
        if (_exploreKey.currentState?.backToTop() ?? false) return;
        final shouldExit = await showAgriConfirm(
          context: context,
          icon: Icons.exit_to_app,
          title: tr(context).exitAppTitle,
          message: tr(context).exitAppMessage,
          confirmLabel: tr(context).exit,
        );
        if (shouldExit) SystemNavigator.pop();
      },
      child: Scaffold(
        backgroundColor: AppColors.page,
        // The page runs on behind the floating bar, with no band around it.
        extendBody: true,
        // No app bar: every tab starts with its own header row — logo and
        // title, see PageHeader.
        // The status bar strip is the header's green (PageHeaderSafeArea).
        body: PageHeaderSafeArea(
          // Swipe left or right to move between the tabs, as well as
          // tapping them in the bar below.
          // The header's logo opens Explore from any tab; on Explore it
          // goes back to the top.
          child: HomeLogoAction(
            onTap: _goHome,
            // Every tab's header has the notification bell. A buyer has no
            // Settings gear: those options are in the Profile tab.
            onNotifications: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NotificationsScreen()),
            ),
            // The pages' scrolling hides and shows the bottom bar.
            child: NotificationListener<ScrollMetricsNotification>(
              onNotification: _onPageMetrics,
              child: NotificationListener<ScrollUpdateNotification>(
                onNotification: _onPageScroll,
                child: SwipeableTabs(
                  index: _navIndex,
                  onIndexChanged: (i) => setState(() => _navIndex = i),
                  children: pages,
                ),
              ),
            ),
          ),
        ),
        bottomNavigationBar: AnimatedSlide(
          offset: _navHidden ? const Offset(0, 1.6) : Offset.zero,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          child: _buildBottomNavBar(),
        ),
      ),
    );
  }

  // The bottom bar hides while the buyer scrolls down a page and comes back
  // on a scroll up or at the top (the user's choice, 2026-11-07; the
  // farmer's too since 2026-11-08). Another tab always shows it.
  bool _navHidden = false;
  int _navShownFor = -1;
  final FiltersOnScroll _navOnScroll = FiltersOnScroll(showAfterUp: 24);

  bool _onPageScroll(ScrollUpdateNotification notification) {
    // Up and down only: not the tabs' own sideways swipe.
    if (notification.metrics.axis != Axis.vertical) return false;
    final hide = _navOnScroll.update(
      delta: notification.scrollDelta ?? 0,
      pixels: notification.metrics.pixels,
      dragging: notification.dragDetails != null,
    );
    if (hide != null && hide != _navHidden) {
      setState(() => _navHidden = hide);
    }
    return false;
  }

  // A page whose content changed size (Market's insights picker: Buyer
  // Areas is shorter than the others) may now fit on the screen. It can
  // then not be scrolled up to bring the bar back, so it shows again.
  bool _onPageMetrics(ScrollMetricsNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;
    if (_navHidden &&
        _navOnScroll.metricsChanged(notification.metrics) == false) {
      setState(() => _navHidden = false);
    }
    return false;
  }

  void _goHome() {
    if (_navIndex != 0) {
      setState(() => _navIndex = 0);
      return;
    }
    _exploreKey.currentState?.backToTop();
  }

  Widget _buildBottomNavBar() {
    final t = tr(context);
    // The floating dark green bar; it slides away while a page is scrolled down.
    return DockedNavBar(
      children: [
        _navItem(0, Icons.explore_outlined, Icons.explore, t.navExplore),
        _navItem(
          1,
          Icons.mail_outline,
          Icons.mail,
          t.navMessages,
          showUnreadDot: true,
        ),
        _navItem(
          2,
          Icons.shopping_bag_outlined,
          Icons.shopping_bag,
          t.navOrders,
          key: _ordersTabKey,
        ),
        _navItem(3, Icons.person_outline, Icons.person, t.navProfile),
      ],
    );
  }

  Widget _navItem(
    int index,
    IconData icon,
    IconData activeIcon,
    String label, {
    Key? key,
    bool showUnreadDot = false,
  }) {
    return NavBarItem(
      key: key,
      icon: icon,
      activeIcon: activeIcon,
      label: label,
      selected: _navIndex == index,
      onTap: () => setState(() => _navIndex = index),
      decorateIcon: showUnreadDot
          ? (icon) => UnreadMessagesDot(child: icon)
          : null,
    );
  }
}
