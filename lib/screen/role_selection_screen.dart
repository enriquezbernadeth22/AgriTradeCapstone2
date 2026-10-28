import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../widgets/existing_account_dialog.dart';
import '../widgets/login_form_fields.dart';
import '../widgets/login_hero.dart';
import '../widgets/login_sheet_body.dart';
import '../l10n/tr.dart';
import '../theme/app_colors.dart';

/// The app's front door: "Log In" or "Don't have an account? Create One."
/// No role is picked here — login itself is role-agnostic (see
/// LoginScreen), and farmer vs. buyer is a toggle right on the registration
/// form (see RegisterScreen). Remembering credentials between sessions is
/// left entirely to the OS's own password manager (see LoginFormFields).
class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    // Less on a short phone, so the form fits (LoginHero.heightFor).
    final heroHeight = LoginHero.heightFor(
      screenHeight,
      keyboardOpen: keyboardOpen,
      bottomInset: MediaQuery.viewPaddingOf(context).bottom,
      max: 320,
    );

    return Scaffold(
      backgroundColor: AppColors.page,
      body: Stack(
        children: [
          // ---- Hero: same branded header as LoginScreen — this is the ----
          // ---- app's actual front door, so it gets the same treatment. ----
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            top: 0,
            left: 0,
            right: 0,
            height: heroHeight,
            child: LoginHero(showBranding: !keyboardOpen),
          ),

          // ---- White sheet, overlapping the hero ----
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            top: heroHeight - LoginHero.sheetOverlap,
            left: 0,
            right: 0,
            bottom: 0,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: AppColors.cardBorder,
                borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 24,
                    offset: Offset(0, -8),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: LoginSheetBody(
                  keyboardOpen: keyboardOpen,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        tr(context).loginButton,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 28,
                          color: AppColors.brand,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        tr(context).loginSubtitle,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.grey(600),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 26),
                      const LoginFormFields(),

                      const SizedBox(height: 18),

                      // ----- Create account -----
                      // Only "Create One." is tappable — the question
                      // before it is plain text.
                      Center(
                        child: Wrap(
                          alignment: WrapAlignment.center,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            RichText(
                              text: TextSpan(
                                text: tr(context).noAccountSignUp,
                                style: GoogleFonts.montserrat(
                                  fontSize: 14,
                                  color: AppColors.text,
                                ),
                              ),
                            ),
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () =>
                                  openRegistration(context, onLoginPage: true),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                child: RichText(
                                  text: TextSpan(
                                    text: tr(context).createOne,
                                    style: GoogleFonts.montserrat(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.brand,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // No language switch here: the language is chosen inside the
          // app, in the farmer's and the buyer's Settings.
        ],
      ),
    );
  }
}
