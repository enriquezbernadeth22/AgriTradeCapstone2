// One look for every form: each kind of field and dropdown is the same height,
// with its text starting in the same place after the icon and its thin line;
// a fixed "+63" shows before anything is typed; and the primary button is the
// tallest control, dark green with white text.
import 'package:agritrade/theme/app_colors.dart';
import 'package:agritrade/theme/app_theme.dart';
import 'package:agritrade/widgets/barangay_location_field.dart';
import 'package:agritrade/widgets/glow_field.dart';
import 'package:agritrade/widgets/registration_role_details.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  Future<void> pumpForm(WidgetTester tester, List<Widget> children) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.themeData(),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(AppTheme.formPageMargin),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('every kind of field is the same height', (tester) async {
    await pumpForm(tester, [
      GlowField(
        key: const Key('glow'),
        controller: TextEditingController(),
        hint: 'Juan',
        icon: Icons.person_outline,
      ),
      TextField(
        key: const Key('decorated'),
        decoration: AppTheme.formFieldDecoration(
          icon: Icons.person_outline,
          hint: 'Juan',
        ),
      ),
      RegistrationRoleDetails(isFarmer: false, value: null, onChanged: (_) {}),
      BarangayLocationField(value: null, onChanged: (_) {}),
    ]);

    double heightOf(Finder finder) => tester.getSize(finder).height;
    expect(heightOf(find.byKey(const Key('glow'))), AppTheme.formFieldHeight);
    expect(
      heightOf(find.byKey(const Key('decorated'))),
      AppTheme.formFieldHeight,
    );
    expect(
      heightOf(find.byType(DropdownButtonFormField<String>)),
      AppTheme.formFieldHeight,
    );
    expect(
      heightOf(
        find.ancestor(
          of: find.text('Select your barangay'),
          matching: find.byType(SizedBox),
        ),
      ),
      AppTheme.formFieldHeight,
    );
  });

  testWidgets('the text starts in the same place in either kind of field', (
    tester,
  ) async {
    await pumpForm(tester, [
      GlowField(
        controller: TextEditingController(),
        hint: 'In a GlowField',
        icon: Icons.person_outline,
      ),
      TextField(
        decoration: AppTheme.formFieldDecoration(
          icon: Icons.person_outline,
          hint: 'In a decorated field',
        ),
      ),
    ]);
    final glow = tester.getTopLeft(find.text('In a GlowField')).dx;
    final decorated = tester.getTopLeft(find.text('In a decorated field')).dx;
    expect((glow - decorated).abs(), lessThanOrEqualTo(1.5));
  });

  testWidgets('typed in, a field glows soft green with no outline, as the '
      'Admin login does', (tester) async {
    await pumpForm(tester, [
      GlowField(
        controller: TextEditingController(),
        hint: 'In a GlowField',
        icon: Icons.person_outline,
      ),
      FormFieldGlow(
        child: TextField(
          decoration: AppTheme.formFieldDecoration(
            icon: Icons.person_outline,
            hint: 'In a decorated field',
            onGlowPlate: true,
          ),
        ),
      ),
    ]);

    // The plates around the two fields: the shadows of each, and GlowField's
    // outline (drawn on top).
    List<AnimatedContainer> plates() => tester
        .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
        .toList();
    bool glows(AnimatedContainer plate) =>
        (plate.decoration! as BoxDecoration).boxShadow?.any(
          (shadow) => shadow.color.g > shadow.color.r,
        ) ??
        false;
    bool outlined(AnimatedContainer plate) =>
        (plate.foregroundDecoration as BoxDecoration?)?.border != null;

    // At rest: a light grey outline, no glow.
    expect(plates().where(glows), isEmpty);
    expect(outlined(plates().first), isTrue);

    await tester.tap(find.text('In a GlowField'));
    await tester.pumpAndSettle();
    expect(glows(plates().first), isTrue);
    expect(outlined(plates().first), isFalse);
    expect(glows(plates().last), isFalse);

    await tester.tap(find.text('In a decorated field'));
    await tester.pumpAndSettle();
    expect(glows(plates().first), isFalse);
    expect(glows(plates().last), isTrue);
    // And its own outline is not drawn while typed in.
    final decorated = tester.widget<InputDecorator>(
      find.byType(InputDecorator).last,
    );
    expect(
      decorated.decoration.focusedBorder!.borderSide.color,
      Colors.transparent,
    );
  });

  testWidgets('"Registering as" is plain words (no icon, no green plate), and '
      'the "What best describes '
      'you" dropdown has an ID card icon for either role', (tester) async {
    for (final isFarmer in [true, false]) {
      await pumpForm(tester, [
        Align(
          alignment: Alignment.centerLeft,
          child: RegisteringAsBadge(isFarmer: isFarmer),
        ),
        RegistrationRoleDetails(
          isFarmer: isFarmer,
          value: null,
          onChanged: (_) {},
        ),
      ]);
      expect(
        find.descendant(
          of: find.byType(RegisteringAsBadge),
          matching: find.byType(Icon),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(RegisteringAsBadge),
          matching: find.byType(DecoratedBox),
        ),
        findsNothing,
      );
      expect(find.byIcon(Icons.badge_outlined), findsOneWidget);
    }
  });

  testWidgets('a fixed +63 shows before anything is typed', (tester) async {
    await pumpForm(tester, [
      TextField(
        decoration: AppTheme.formFieldDecoration(
          icon: Icons.phone_outlined,
          hint: '9123456789',
          prefixText: '+63 ',
        ),
      ),
    ]);
    expect(find.text('+63 '), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('+63 ')).dx,
      lessThan(tester.getTopLeft(find.text('9123456789')).dx),
    );
  });

  testWidgets('the primary button is dark green, white text, and the tallest', (
    tester,
  ) async {
    await pumpForm(tester, [
      ElevatedButton(
        onPressed: () {},
        style: AppTheme.primaryButton(),
        child: Text('Log In', style: AppTheme.buttonText()),
      ),
      OutlinedButton(
        onPressed: () {},
        style: AppTheme.secondaryButton(),
        child: Text('Continue with Google', style: AppTheme.buttonText()),
      ),
    ]);
    final primary = find.byType(ElevatedButton);
    expect(tester.getSize(primary).height, AppTheme.formButtonHeight);
    expect(
      tester.getSize(find.byType(OutlinedButton)).height,
      AppTheme.formButtonHeight,
    );
    final style = tester.widget<ElevatedButton>(primary).style!;
    expect(style.backgroundColor!.resolve({}), AppColors.brandFill);
    expect(style.foregroundColor!.resolve({}), Colors.white);
    expect(AppTheme.formButtonHeight, greaterThan(AppTheme.formFieldHeight));
  });

  test('a secondary button keeps a clear outline, even while it cannot be '
      'pressed yet', () {
    final side = AppTheme.secondaryButton().side!;
    for (final states in [
      <WidgetState>{},
      {WidgetState.disabled},
    ]) {
      final outline = side.resolve(states)!;
      expect(outline.color, AppColors.grey(400));
      expect(outline.width, greaterThanOrEqualTo(1.2));
    }
  });

  test('the type follows the hierarchy: title, then labels and fields', () {
    final title = AppTheme.pageTitle().fontSize!;
    final description = AppTheme.pageDescription().fontSize!;
    final label = AppTheme.label().fontSize!;
    expect(title, inInclusiveRange(24, 26));
    expect(description, inInclusiveRange(13, 14));
    expect(label, inInclusiveRange(13, 14));
    expect(AppTheme.formTextSize, 14);
    expect(AppTheme.buttonText().fontWeight, FontWeight.w600);
    expect(AppTheme.formLink().color, AppColors.brand);
  });

  testWidgets('any plain text field (e.g. Set nickname) looks like Log In: '
      'a grey outline at rest, a green glow and no outline typed in', (
    tester,
  ) async {
    await pumpForm(tester, [
      const TextField(decoration: InputDecoration(hintText: 'Nickname')),
    ]);
    InputDecoration decoration() =>
        tester.widget<InputDecorator>(find.byType(InputDecorator)).decoration;

    // At rest: white, a thin grey outline.
    expect(decoration().fillColor, AppColors.surface);
    expect(decoration().enabledBorder!.borderSide.color, AppColors.grey(300));

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    final focused = decoration().focusedBorder!;
    expect(focused, isA<GlowInputBorder>());
    expect(focused.borderSide.color, Colors.transparent);
    expect((focused as GlowInputBorder).glow, 1);
  });

  test('the glow fades in and out as focus moves', () {
    final rest = AppTheme.fieldBorder;
    const typed = AppTheme.fieldFocusBorder;
    final halfIn = ShapeBorder.lerp(rest, typed, 0.5)! as GlowInputBorder;
    expect(halfIn.glow, closeTo(0.5, 0.001));
    final halfOut = ShapeBorder.lerp(typed, rest, 0.5)! as GlowInputBorder;
    expect(halfOut.glow, closeTo(0.5, 0.001));
    expect(ShapeBorder.lerp(typed, rest, 1), rest);
  });
}
