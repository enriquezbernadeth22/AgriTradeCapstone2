import 'package:agritrade/screen/conversation_info_screen.dart';
import 'package:agritrade/services/firebase_refs.dart';
import 'package:agritrade/theme/app_colors.dart';
import 'package:agritrade/widgets/profile_avatar.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _gold = Color(0xFFF5BB24);

Future<void> _open(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final db = FakeFirebaseFirestore();
  FirebaseRefs.useForTests(
    firestore: db,
    auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'me')),
  );
  await db.collection('publicProfiles').doc('f1').set({
    'name': 'Daniella Claveria',
    'role': 'farmer',
    'barangay': 'Bugaan East',
    'municipality': 'Laurel',
    'province': 'Batangas',
  });
  tester.view.physicalSize = const Size(390 * 3, 1400 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    const MaterialApp(
      home: ConversationInfoScreen(
        conversationId: 'c1',
        otherUserId: 'f1',
        otherUserName: 'Daniella Claveria',
        productId: 'p1',
        productName: 'Corn',
      ),
    ),
  );
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  tearDown(FirebaseRefs.reset);

  testWidgets('the cream page shows the person with a clean photo', (
    tester,
  ) async {
    await _open(tester);

    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
      AppColors.page,
    );
    final person = find.byKey(const Key('conversationInfoPerson'));
    // Only the photo itself: nothing stacked over it.
    expect(
      find.descendant(of: person, matching: find.byType(ProfileAvatar)),
      findsOneWidget,
    );
    expect(
      find.ancestor(
        of: find.byType(ProfileAvatar),
        matching: find.byType(Stack),
      ),
      findsNothing,
    );
    expect(find.text('Daniella Claveria'), findsOneWidget);
    expect(find.text('Farmer'), findsOneWidget);
    expect(find.text('Bugaan East, Laurel, Batangas'), findsOneWidget);
    expect(
      tester
          .getSize(find.byKey(const Key('conversationInfoViewProfile')))
          .height,
      40,
    );
  });

  testWidgets('every group is kept, with no gold anywhere', (tester) async {
    await _open(tester);

    for (final text in [
      'Conversation tools',
      'Nickname',
      'Search conversation',
      'View all photos',
      'Product context',
      'Corn',
      'Pin conversation',
      'Mute notifications',
      'Archive conversation',
      'Report Daniella Claveria',
      'Block Daniella Claveria',
      'Only a general area is public',
      'Exact location only when you choose',
      'For delivery or pick-up',
    ]) {
      await tester.scrollUntilVisible(find.text(text), 200);
      expect(find.text(text), findsOneWidget, reason: text);
    }
    final icons = tester.widgetList<Icon>(find.byType(Icon));
    expect(icons.where((i) => i.color == _gold), isEmpty);
  });
}
