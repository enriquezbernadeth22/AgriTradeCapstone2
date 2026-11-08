import 'package:agritrade/screen/chat_list_screen.dart';
import 'package:agritrade/services/conversation_prefs_service.dart';
import 'package:agritrade/services/firebase_refs.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _open(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final db = FakeFirebaseFirestore();
  FirebaseRefs.useForTests(
    firestore: db,
    auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'me')),
  );
  await db.collection('conversations').doc('c1').set({
    'participants': ['me', 'f1'],
    'participantNames': {'me': 'Me', 'f1': 'Sander Calda'},
    'lastMessage': 'Hello po',
    'lastSenderId': 'f1',
    'lastMessageTime': Timestamp.fromDate(DateTime(2026, 11, 8, 9)),
  });
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    const MaterialApp(home: Scaffold(body: ChatListScreen())),
  );
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  tearDown(() {
    final prefs = ConversationPrefs.instance;
    if (prefs.isMuted('c1')) prefs.toggleMuted('c1');
    FirebaseRefs.reset();
  });

  testWidgets('a grey bell-off sits beside a muted chat name, and goes '
      'when it is unmuted', (tester) async {
    await _open(tester);
    final bell = find.byKey(const ValueKey('muted_c1'));
    expect(find.text('Sander Calda'), findsOneWidget);
    expect(bell, findsNothing);

    ConversationPrefs.instance.toggleMuted('c1');
    await tester.pump();
    expect(bell, findsOneWidget);
    final icon = tester.widget<Icon>(bell);
    expect(icon.icon, Icons.notifications_off_outlined);
    expect(icon.color, const Color(0xFF757575));
    // Right after the name, on its line.
    final name = tester.getRect(find.text('Sander Calda'));
    final mark = tester.getRect(bell);
    expect(mark.left - name.right, moreOrLessEquals(5, epsilon: 0.5));
    expect(mark.center.dy, moreOrLessEquals(name.center.dy, epsilon: 2));

    ConversationPrefs.instance.toggleMuted('c1');
    await tester.pump();
    expect(bell, findsNothing);
  });

  testWidgets('the menu lists Archived, Muted, Reported and Blocked Users, '
      'compact with lines between', (tester) async {
    await _open(tester);
    await tester.tap(find.byTooltip('Manage messages'));
    await tester.pumpAndSettle();

    const labels = ['Archived', 'Muted', 'Reported', 'Blocked Users'];
    for (var i = 1; i < labels.length; i++) {
      expect(
        tester.getTopLeft(find.text(labels[i - 1])).dy,
        lessThan(tester.getTopLeft(find.text(labels[i])).dy),
      );
    }
    final menu = find.ancestor(
      of: find.text('Archived'),
      matching: find.byType(Column),
    );
    expect(
      find.descendant(of: menu.first, matching: find.byType(Divider)),
      findsNWidgets(3),
    );
    for (final icon in [
      Icons.archive_outlined,
      Icons.notifications_off_outlined,
      Icons.flag_outlined,
      Icons.block,
    ]) {
      final widget = tester.widget<Icon>(find.byIcon(icon).last);
      expect(widget.size, 16);
      expect(widget.color, const Color(0xFF0B4225));
    }
    final text = tester.widget<Text>(find.text('Muted'));
    expect(text.style!.fontSize, 12);
    final gap =
        tester.getTopLeft(find.text('Muted')).dy -
        tester.getTopLeft(find.text('Archived')).dy;
    expect(gap, inInclusiveRange(36, 41));
  });
}
