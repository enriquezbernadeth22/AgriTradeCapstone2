import 'package:flutter/material.dart';

import '../screen/login_screen.dart';
import '../screen/page_transitions.dart';
import '../screen/choose_role_screen.dart';
import '../services/registration_guard.dart';
import 'agri_dialog.dart';
import '../l10n/app_language.dart';

/// What the person chose in [showExistingAccountDialog].
enum ExistingAccountChoice { cancel, login, differentEmail }

/// The title and message for an account that already exists.
({String title, String message, bool cancellable}) existingAccountCopy(
  ExistingAccount account,
) => switch (account) {
  ExistingAccount.farmerPending => (
    title: tl('Application already submitted'),
    message: tl(
      'Your Farmer application is already under review. Please log in to check your application status.',
    ),
    cancellable: true,
  ),
  ExistingAccount.farmerApproved => (
    title: tl('Account already registered'),
    message: tl(
      'This email is already registered as an approved Farmer. Please log in to continue.',
    ),
    cancellable: false,
  ),
  // There is no resubmission in the app: the application's status, and
  // the office's reason, are shown after signing in.
  ExistingAccount.farmerRejected => (
    title: tl('Application not approved'),
    message: tl(
      'Your previous Farmer application was not approved. Please sign in to see your application status and the reason given.',
    ),
    cancellable: true,
  ),
  ExistingAccount.registered || ExistingAccount.none => (
    title: tl('Account already registered'),
    message: tl(
      'This email already has an AgriTrade+ account. Please log in to continue.',
    ),
    cancellable: true,
  ),
};

/// Tells someone the account they are about to register already exists.
///
/// [offerDifferentEmail] adds a way through for someone else using the
/// same phone: the check before the form opens is against the email last
/// used on this phone, which may not be theirs.
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
      // One layout whichever of the buttons below it has: Back to Login on
      // top, then the others, all the same slim size.
      stackedActions: true,
      actions: [
        if (copy.cancellable)
          AgriDialogButton(
            label: tl('Cancel'),
            onPressed: () =>
                Navigator.of(dialogContext).pop(ExistingAccountChoice.cancel),
          ),
        if (offerDifferentEmail)
          AgriDialogButton(
            label: tl('Register a different email'),
            kind: AgriButtonKind.secondary,
            onPressed: () => Navigator.of(
              dialogContext,
            ).pop(ExistingAccountChoice.differentEmail),
          ),
        AgriDialogButton(
          label: tl('Back to Login'),
          kind: AgriButtonKind.primary,
          onPressed: () =>
              Navigator.of(dialogContext).pop(ExistingAccountChoice.login),
        ),
      ],
    ),
  );
  return choice ?? ExistingAccountChoice.cancel;
}

/// "Create one": opens the choice of role and then the registration form,
/// unless the account last used on this phone already exists — then says so
/// first.
///
/// [onLoginPage] is true when this is called from the login page itself,
/// where "Back to Login" simply closes the dialog.
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
