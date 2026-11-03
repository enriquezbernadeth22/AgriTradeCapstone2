import 'package:flutter/material.dart';

import 'agri_dialog.dart';

/// Shown when this browser was signed out from Active Sessions elsewhere.
Future<void> showAdminSessionEndedDialog(BuildContext context) {
  return showAgriDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AgriDialog(
      icon: Icons.logout_rounded,
      tone: AgriTone.warning,
      title: const Text('Session ended'),
      content: const Text(
        'This device was signed out of your Admin account from Active '
        'Sessions on another device. Log in again to continue.',
      ),
      actions: [
        AgriDialogButton(
          label: 'Back to Login',
          kind: AgriButtonKind.primary,
          onPressed: () => Navigator.of(dialogContext).pop(),
        ),
      ],
    ),
  );
}
