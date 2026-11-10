import 'package:flutter/material.dart';

import '../screen/login_screen.dart';
import '../screen/page_transitions.dart';
import '../screen/choose_role_screen.dart';
import '../services/registration_guard.dart';
import 'agri_dialog.dart';
import '../l10n/app_language.dart';

/// What the person chose in [showExistingAccountDialog].
enum ExistingAccountChoice { cancel, login, differentEmail }

/// The title and message for an account that already exists. Every kind
/// has the one title, "Account Already Exists" (the panel's wording, system
/// testing 2026-11-09); a Farmer application says where it stands.
({String title, String message}) existingAccountCopy(
  ExistingAccount account,
) => (
  title: tl('Account Already Exists'),
  message: switch (account) {
    ExistingAccount.farmerPending => tl(
      'An account with this email address is already registered with AgriTrade+. Its Farmer application is under review: please log in to check its status.',
    ),
    // There is no resubmission in the app: the application's status, and
    // the office's reason, are shown after signing in.
    ExistingAccount.farmerRejected => tl(
      'An account with this email address is already registered with AgriTrade+. Its Farmer application was not approved: please log in to see the reason given.',
    ),
    ExistingAccount.farmerApproved ||
    ExistingAccount.registered ||
    ExistingAccount.none => tl(
      'An account with this email address is already registered with AgriTrade+. Please log in to continue.',
    ),
  },
);

/// Tells someone the account they are about to register already exists:
/// Cancel (stay on the form) or Log In.
///
/// [offerDifferentEmail] is for "Create one", before any form: the check
/// there is against the email last used on this phone, which may not be
/// theirs, so Register a different email takes the place of Cancel.
Future<ExistingAccountChoice> showExistingAccountDialog(
  BuildContext context,
  ExistingAccount account, {
  bool offerDifferentEmail = false,
}) async {
  final copy = existingAccountCopy(account);
  final choice = await showAgriDialog<ExistingAccountChoice>(
    context: context,
    builder: (dialogContext) => AgriDialog(
      icon: Icons.info_outline_rounded,
      title: Text(copy.title),
      content: Text(copy.message),
      // Cancel and Log In side by side, as the panel drew it; the longer
      // Register a different email goes under Log In instead.
      stackedActions: offerDifferentEmail,
      actions: [
        if (offerDifferentEmail)
          AgriDialogButton(
            label: tl('Register a different email'),
            kind: AgriButtonKind.secondary,
            onPressed: () => Navigator.of(
              dialogContext,
            ).pop(ExistingAccountChoice.differentEmail),
          )
        else
          AgriDialogButton(
            label: tl('Cancel'),
            onPressed: () =>
                Navigator.of(dialogContext).pop(ExistingAccountChoice.cancel),
          ),
        AgriDialogButton(
          label: tl('Log In'),
          kind: AgriButtonKind.primary,
          onPressed: () =>
              Navigator.of(dialogContext).pop(ExistingAccountChoice.login),
        ),
      ],
    ),
  );
  // Tapping outside is the same as Cancel.
  return choice ?? ExistingAccountChoice.cancel;
}

/// Log In from the registration screens: back to the first screen (role
/// selection), with the Log In page over it, [email] already typed in.
/// Every registration screen in between is closed, so Back never returns to
/// a half-filled form and nothing is left blank under the login.
void goToLoginAfterExistingAccount(
  BuildContext context, {
  String? role,
  String? email,
}) {
  Navigator.of(context).pushAndRemoveUntil(
    slideRoute(LoginScreen(role: role, initialEmail: email)),
    (route) => route.isFirst,
  );
}

/// "Create one": opens the choice of role and then the registration form,
/// unless the account last used on this phone already exists — then says so
/// first.
///
/// [onLoginPage] is true when this is called from the login page itself,
/// where Log In simply closes the dialog.
Future<void> openRegistration(
  BuildContext context, {
  String? role,
  required bool onLoginPage,
}) async {
  final email = await RegistrationGuard.remembered();
  if (!context.mounted) return;
  if (email != null) {
    final account = await RegistrationGuard.check(email);
    if (!context.mounted) return;
    if (account != ExistingAccount.none) {
      final choice = await showExistingAccountDialog(
        context,
        account,
        offerDifferentEmail: true,
      );
      if (!context.mounted) return;
      switch (choice) {
        case ExistingAccountChoice.cancel:
          return;
        case ExistingAccountChoice.login:
          if (!onLoginPage) {
            Navigator.push(
              context,
              slideRoute(
                LoginScreen(
                  role: account == ExistingAccount.registered ? role : 'farmer',
                  initialEmail: email,
                ),
              ),
            );
          }
          return;
        case ExistingAccountChoice.differentEmail:
          break;
      }
    }
  }
  Navigator.push(context, slideRoute(const ChooseRoleScreen()));
}
