import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../l10n/app_language.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/agri_app_bar.dart';
import '../widgets/agritrade_text.dart';
import 'google_complete_profile_screen.dart';
import 'page_transitions.dart';
import 'register_screen.dart';

/// The first step of creating an account: buyer or farmer. Choosing marks the
/// card and opens the form for that role, which has no way to switch: going
/// back here does.
///
/// With [google], the person has just signed in with a Google account that
/// has no AgriTrade+ profile yet: the cards open the shorter Google profile
/// form instead, and leaving this screen signs that Google account back out,
/// so no half-made account stays signed in.
class ChooseRoleScreen extends StatefulWidget {
  final GoogleSignInResult? google;

  /// Stands in for AuthService.signOut in tests.
  @visibleForTesting
  final Future<void> Function()? signOut;

  const ChooseRoleScreen({super.key, this.google, this.signOut});

  /// One picture of a buyer and a farmer side by side; each card shows its
  /// own person from it (head to waist), cut from the picture's pixels.
  static const picture = 'assets/images/farmer&buyer.png';
  static const pictureSize = Size(1448, 1086);
  static const buyerCrop = Rect.fromLTWH(0, 60, 680, 680);
  static const farmerCrop = Rect.fromLTWH(724, 30, 724, 724);

  @override
  State<ChooseRoleScreen> createState() => _ChooseRoleScreenState();
}

class _ChooseRoleScreenState extends State<ChooseRoleScreen>
    with SingleTickerProviderStateMixin {
  // How long the chosen card shows as chosen before the form slides in.
  late final AnimationController _hold;

  String? _chosen;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _hold = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
  }

  Future<void> _choose(String role) async {
    if (_leaving) return;
    setState(() {
      _chosen = role;
      _leaving = true;
    });
    if (!MediaQuery.disableAnimationsOf(context)) {
      await _hold.forward(from: 0);
    }
    if (!mounted) return;
    final google = widget.google;
    final toLogIn = await Navigator.push(
      context,
      slideRoute(
        google == null
            ? RegisterScreen(initialRole: role)
            : GoogleCompleteProfileScreen(
                uid: google.uid!,
                email: google.email ?? '',
                initialName: google.displayName,
                role: role,
              ),
      ),
    );
    if (!mounted) return;
    setState(() => _leaving = false);
    // The form's "Log in" link (or the Google form's Cancel) goes past this
    // screen as well.
    if (toLogIn == true) Navigator.pop(context);
  }

  // Only a pop reaches here: entering the app removes this screen without
  // popping it, so a finished Google sign-up stays signed in.
  void _leftScreen(bool didPop, Object? result) {
    if (!didPop || widget.google == null) return;
    final signOut =
        widget.signOut ??
        () => AuthService().signOut(
          reason: 'Google sign-up left before completing the profile',
        );
    signOut();
  }

  @override
  void dispose() {
    _hold.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(onPopInvokedWithResult: _leftScreen, child: _page(context));
  }

  Widget _page(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.page,
      appBar: const AgriAppBar(titleWidget: AgriTradeHeaderBrand()),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            20,
            AppTheme.formSectionGap,
            20,
            AppTheme.formSectionGap,
          ),
          child: Column(
            children: [
              Text(
                tl('How will you use AgriTrade+?'),
                textAlign: TextAlign.center,
                style: AppTheme.pageTitle(color: AppColors.brand),
              ),
              const SizedBox(height: 8),
              Text(
                tl('Choose the option that best fits you.'),
                textAlign: TextAlign.center,
                style: AppTheme.pageDescription(),
              ),
              if (widget.google?.email case final email?) ...[
                const SizedBox(height: 6),
                Text(
                  tl('Logged in as {0}', [email]),
                  textAlign: TextAlign.center,
                  style: AppTheme.pageDescription().copyWith(fontSize: 12.5),
                ),
              ],
              const SizedBox(height: 28),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _RoleCard(
                        picture: ChooseRoleScreen.buyerCrop,
                        title: tl('I\'m a Buyer'),
                        description: tl('I want to buy agricultural products.'),
                        selected: _chosen == 'buyer',
                        onTap: () => _choose('buyer'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _RoleCard(
                        picture: ChooseRoleScreen.farmerCrop,
                        title: tl('I\'m a Farmer'),
                        description: tl(
                          'I want to sell my agricultural products.',
                        ),
                        selected: _chosen == 'farmer',
                        onTap: () => _choose('farmer'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  /// The part of [ChooseRoleScreen.picture] this card shows.
  final Rect picture;
  final String title;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  const _RoleCard({
    required this.picture,
    required this.title,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(20);
    return Semantics(
      selected: selected,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: selected ? AppColors.softTint : AppColors.surface,
          borderRadius: shape,
          border: Border.all(
            color: selected ? AppColors.brandFill : AppColors.grey(200),
            width: selected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: shape,
            // Being chosen is the feedback: the usual grey press would hide
            // the card's green.
            highlightColor: Colors.transparent,
            splashFactory: NoSplash.splashFactory,
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ExcludeSemantics(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: AspectRatio(
                            aspectRatio: picture.width / picture.height,
                            child: _CroppedPicture(crop: picture),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 10, 4, 8),
                        child: Column(
                          children: [
                            Text(
                              title,
                              textAlign: TextAlign.center,
                              style: GoogleFonts.montserrat(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AppColors.brand,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              description,
                              textAlign: TextAlign.center,
                              style: GoogleFonts.montserrat(
                                fontSize: 12.5,
                                color: AppColors.grey(700),
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (selected)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: AppColors.brandFill,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Icon(
                        Icons.check,
                        size: 15,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shows only [crop] of [ChooseRoleScreen.picture], filling the space given
/// (an AspectRatio of the crop's shape).
class _CroppedPicture extends StatelessWidget {
  final Rect crop;

  const _CroppedPicture({required this.crop});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final scale = box.maxWidth / crop.width;
        const full = ChooseRoleScreen.pictureSize;
        return ClipRect(
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: 0,
            maxWidth: double.infinity,
            minHeight: 0,
            maxHeight: double.infinity,
            child: Transform.translate(
              offset: Offset(-crop.left * scale, -crop.top * scale),
              child: Image.asset(
                ChooseRoleScreen.picture,
                width: full.width * scale,
                height: full.height * scale,
                fit: BoxFit.fill,
                filterQuality: FilterQuality.medium,
              ),
            ),
          ),
        );
      },
    );
  }
}
