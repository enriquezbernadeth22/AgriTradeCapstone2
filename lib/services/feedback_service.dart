import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/feedback_sheet.dart';

/// Why the feedback sheet was opened — named in the team's email.
enum FeedbackTrigger {
  /// Profile → Send Feedback.
  menu('menu'),

  /// Asked after the farmer posted products.
  productPosted('product_posted'),

  /// Asked after the buyer placed orders.
  orderPlaced('order_placed');

  /// As the sendAppFeedback function knows it.
  final String wireName;
  const FeedbackTrigger(this.wireName);
}

/// After how many products posted or orders placed the app first asks
/// for feedback.
const int kFeedbackFirstAsk = 3;

/// After "Not now", how many more before it asks again.
const int kFeedbackAskAgainAfter = 10;

/// Whether to ask now, after [actions] products posted or orders placed:
/// at [nextAsk] (first [kFeedbackFirstAsk]) and never again once feedback
/// has been [sent] — Send Feedback in the menu is always there.
bool feedbackPromptDue({
  required int actions,
  required int? nextAsk,
  required bool sent,
}) => !sent && actions >= (nextAsk ?? kFeedbackFirstAsk);

/// Sends feedback — emailed to the AgriTrade+ team by the sendAppFeedback
/// function (functions/app_feedback.js); nothing is kept in the app — and
/// asks for it now and then, after a few products posted (farmers) or
/// orders placed (buyers).
class FeedbackService {
  FeedbackService._();
  static final FeedbackService instance = FeedbackService._();

  GlobalKey<NavigatorState>? _navigatorKey;
  bool _asking = false;

  /// Called once from main(): the prompt opens over whatever screen is
  /// showing once the one that recorded the action has closed.
  void start(GlobalKey<NavigatorState> navigatorKey) {
    _navigatorKey = navigatorKey;
  }

  /// Emails the feedback to the team. Throws if it could not be sent.
  Future<void> send({
    required int rating,
    required String message,
    required FeedbackTrigger trigger,
  }) async {
    String version = '';
    try {
      version = (await PackageInfo.fromPlatform()).version;
    } catch (_) {}
    await FirebaseFunctions.instanceFor(
      region: 'asia-southeast1',
    ).httpsCallable('sendAppFeedback').call({
      'rating': rating,
      'message': message.trim(),
      'trigger': trigger.wireName,
      'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
      'appVersion': version,
    });
    await _remember(sent: true);
  }

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;
  String _key(String name, String uid) => 'feedback_${name}_$uid';

  Future<void> _remember({bool sent = false}) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (sent) await prefs.setBool(_key('sent', uid), true);
    } catch (_) {}
  }

  /// A product was posted or an order placed ([trigger]). On the third,
  /// and after "Not now" every tenth after that, the feedback sheet opens.
  Future<void> recordAction(FeedbackTrigger trigger) async {
    final uid = _uid;
    if (uid == null) return;
    int actions;
    int? nextAsk;
    bool sent;
    SharedPreferences prefs;
    try {
      prefs = await SharedPreferences.getInstance();
      actions = (prefs.getInt(_key('actions', uid)) ?? 0) + 1;
      await prefs.setInt(_key('actions', uid), actions);
      nextAsk = prefs.getInt(_key('next_ask', uid));
      sent = prefs.getBool(_key('sent', uid)) ?? false;
    } catch (_) {
      return;
    }
    if (_asking ||
        !feedbackPromptDue(actions: actions, nextAsk: nextAsk, sent: sent)) {
      return;
    }

    // Once the screen that posted or ordered has closed and its message
    // has shown.
    _asking = true;
    await Future<void>.delayed(const Duration(milliseconds: 900));
    try {
      final context = _navigatorKey?.currentState?.overlay?.context;
      if (context == null || !context.mounted) return;
      final wasSent = await showFeedbackSheet(
        context,
        trigger: trigger,
        prompted: true,
      );
      if (!wasSent) {
        await prefs.setInt(
          _key('next_ask', uid),
          actions + kFeedbackAskAgainAfter,
        );
      }
    } catch (_) {
    } finally {
      _asking = false;
    }
  }
}
