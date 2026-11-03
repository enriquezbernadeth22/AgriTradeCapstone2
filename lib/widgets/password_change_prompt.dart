import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/push_notification_service.dart';
import 'agri_dialog.dart';
import 'change_password_dialog.dart';
import '../l10n/app_language.dart';

/// Asks an Admin-added farmer to replace the default password from the
/// office: every time they come into the app, until they do. "Skip for now"
/// lets them in, and [PushNotificationService.startPasswordReminder] then
/// reminds them every 10 minutes.
class PasswordChangePrompt {
  const PasswordChangePrompt._();

  /// Asks, if this account still has to change its password. Never stops the
  /// person getting into the app.
  static Future<void> onEnteredApp(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      if (!await _required(user.uid)) {
        await PushNotificationService.stopPasswordReminder();
        return;
      }
      if (!context.mounted) return;
      final changeNow = await showAgriDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const PasswordChangePromptDialog(),
      );
      var changed = false;
      if (changeNow == true && context.mounted) {
        changed = await showChangePasswordDialog(context);
      }
      if (!changed) await PushNotificationService().startPasswordReminder();
    } catch (_) {
      // Asked again the next time they come in.
    }
  }

  static Future<bool> _required(String uid) async {
    final profile = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    if (profile.data()?['mustChangePassword'] != true) return false;
    try {
      // The server can tell if it was changed through the emailed link.
      final result = await FirebaseFunctions.instanceFor(
        region: 'asia-southeast1',
      ).httpsCallable('checkPasswordChangeRequired').call<dynamic>();
      return (result.data as Map)['required'] == true;
    } catch (_) {
      return true;
    }
  }
}

/// "Change your password", with "Skip for now". Resolves to true for
/// "Change Password".
class PasswordChangePromptDialog extends StatelessWidget {
  const PasswordChangePromptDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AgriDialog(
      icon: Icons.lock_reset_rounded,
      stackedActions: true,
      title: Text(tl('Change your password'), textAlign: TextAlign.center),
      content: Text(
        tl(
          'Your account uses the default password from the agricultural office. Change it to one only you know. If you skip for now, we will remind you every 10 minutes until you do.',
        ),
        textAlign: TextAlign.center,
      ),
      actions: [
        AgriDialogButton(
          label: tl('Change Password'),
          kind: AgriButtonKind.primary,
          onPressed: () => Navigator.pop(context, true),
        ),
        AgriDialogButton(
          label: tl('Skip for now'),
          onPressed: () => Navigator.pop(context, false),
        ),
      ],
    );
  }
}
