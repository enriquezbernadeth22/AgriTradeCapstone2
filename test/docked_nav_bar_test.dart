// The Farmer and Buyer bottom navigation: a solid floating pill with no band
// behind it, the page running on underneath, and the end of a list still
// reachable above the pill.
import 'package:agritrade/theme/app_colors.dart';
import 'package:agritrade/widgets/docked_nav_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const items = [
    NavBarItem(
      icon: Icons.mail_outline,
      activeIcon: Icons.mail,
      label: 'Messages',
      selected: true,
      onTap: _noTap,
    ),
  ];

  Widget home({required Widget body}) => MaterialApp(
    home: Scaffold(
      extendBody: true,
      body: body,
      bottomNavigationBar: const DockedNavBar(children: items),
    ),
  );

  testWidgets('the bar is a solid rounded pill, not a bare row of icons', (
    tester,
  ) async {
    await tester.pumpWidget(home(body: const SizedBox.expand()));

    final plate = tester.widget<DecoratedBox>(
      find.descendant(
        of: find.byType(DockedNavBar),
        matching: find.byType(DecoratedBox),
      ),
    );
    final look = plate.decoration as BoxDecoration;
    expect(look.color, AppColors.surface);
    expect(look.borderRadius, BorderRadius.circular(DockedNavBar.cornerRadius));
    expect(look.boxShadow, isNotEmpty);
    expect(
      tester.getSize(find.byType(DecoratedBox).first).height,
      DockedNavBar.height,
    );
  });

  testWidgets('the Market tab fills its shop in when selected', (tester) async {
    Widget market({required bool selected}) => MaterialApp(
      home: Scaffold(
        body: Row(
          children: [
            NavBarItem(
              icon: Icons.storefront_outlined,
              activeIcon: Icons.storefront,
              label: 'Market',
              selected: selected,
              onTap: _noTap,
              activeIconBuilder: (color, size) =>
                  FilledStorefrontIcon(color: color, size: size),
            ),
          ],
        ),
      ),
    );

    await tester.pumpWidget(market(selected: true));
    expect(find.byType(FilledStorefrontIcon), findsOneWidget);

    await tester.pumpWidget(market(selected: false));
    expect(find.byType(FilledStorefrontIcon), findsNothing);
    expect(find.byIcon(Icons.storefront_outlined), findsOneWidget);
  });

  testWidgets('the page runs on behind the pill, with no band around it', (
    tester,
  ) async {
    const page = Key('page');
    await tester.pumpWidget(home(body: const SizedBox.expand(key: page)));

    final screen = tester.getRect(find.byType(Scaffold));
    expect(tester.getRect(find.byKey(page)).bottom, screen.bottom);
    expect(
      tester.getRect(find.byType(DecoratedBox).first).bottom,
      lessThan(screen.bottom),
    );
  });

  testWidgets('the last row of a list scrolls clear of the pill', (
    tester,
  ) async {
    await tester.pumpWidget(
      home(
        body: Builder(
          builder: (context) => ListView(
            padding: EdgeInsets.only(
              bottom: DockedNavBar.listEndPadding(context),
            ),
            children: [
              for (var i = 0; i < 40; i++)
                SizedBox(height: 60, child: Text('Row $i')),
            ],
          ),
        ),
      ),
    );

    await tester.drag(find.byType(ListView), const Offset(0, -5000));
    await tester.pumpAndSettle();

    expect(
      tester.getRect(find.text('Row 39')).bottom,
      lessThan(tester.getRect(find.byType(DecoratedBox).first).top),
    );
  });
}

void _noTap() {}
