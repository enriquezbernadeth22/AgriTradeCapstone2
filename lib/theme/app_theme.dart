import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../widgets/app_back_button.dart';
import 'app_colors.dart';

class AppTheme {
  // ---------- COLOURS ----------
  // The colour of the AgriTradeText wordmark (see brandText), so every
  // button in the app reads as the same dark green as the logo text.
  static const Color dark = Color.fromARGB(255, 14, 50, 16); // main dark green
  static const Color mid = Color(0xFF2E7D32); // brand green
  static const Color accent = Color(0xFFDCEDC8); // pale green
  static const Color bgLight = Colors.white; // splash / app background
  static const Color fieldFill = Color(0xFFF2F2F2); // textfield grey

  /// The one off-white page background for inner screens that sit their
  /// content on cards (Inventory, Order Details, Notifications…). Main
  /// tabs and forms are white.
  static const Color surface = Color(0xFFF7F8F6);

  /// The one pale green for soft highlight boxes, banners and selected
  /// rows. ([accent] is the stronger pale green, for chips and badges.)
  static const Color tint = Color(0xFFF1F7EC);

  // ==========================================================
  // THE GLOBAL THEME
  // ----------------------------------------------------------
  // Pass this into MaterialApp in main.dart:
  //
  //     theme: AppTheme.themeData(),
  //
  // That one line makes Montserrat the default everywhere.
  // ==========================================================
  static ThemeData themeData() {
    // Takes Flutter's standard set of text sizes (headings, body,
    // captions...) and rebuilds all of them in Montserrat.
    final dark = AppColors.isDark;
    final brightness = dark ? Brightness.dark : Brightness.light;
    // (On the default text colours for light or dark.)
    final montserratText = GoogleFonts.montserratTextTheme(
      ThemeData(brightness: brightness).textTheme,
    );

    return ThemeData(
      useMaterial3: true,
      // Light or dark, from Settings → Appearance (AppColors).
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppTheme.mid,
        brightness: brightness,
        primary: AppColors.brand,
        surface: AppColors.surface,
        onSurface: AppColors.text,
      ),
      scaffoldBackgroundColor: AppColors.page,

      // <-- THIS is the line that changes the whole app's font.
      textTheme: montserratText,
      primaryTextTheme: montserratText,

      // Inner screens use AgriAppBar (widgets/agri_app_bar.dart); this is
      // the same light look as a fallback for any plain AppBar.
      // Any plain AppBar: the same white as the app's headers.
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.brand,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        titleTextStyle: GoogleFonts.montserrat(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: AppColors.brand,
        ),
      ),

      actionIconTheme: backButtonTheme,

      // Default look for every ElevatedButton in the app: a slim pill
      // (about 40 high), in proportion with the small bottom bar.
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.brandFill,
          foregroundColor: Colors.white,
          padding: buttonPadding,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
          textStyle: buttonText(),
        ),
      ),

      // Every button in the app is pill-shaped, for consistency.
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.brand,
          shape: const StadiumBorder(),
          textStyle: GoogleFonts.montserrat(fontSize: 13.5),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.brand,
          shape: const StadiumBorder(),
          padding: buttonPadding,
          textStyle: buttonText(),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.brandFill,
          shape: const StadiumBorder(),
          padding: buttonPadding,
          textStyle: buttonText(),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(shape: const StadiumBorder()),
      ),

      // Default look for every TextField: curved edges — a pill on one
      // line, rounded corners on a several-line box.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.field,
        hintStyle: GoogleFonts.montserrat(
          fontSize: 13.5,
          color: AppColors.grey(),
        ),
        errorStyle: GoogleFonts.montserrat(fontSize: 11.5),
        // The "12/40" under a field with a length limit, the same on every
        // field (nickname, review, …).
        counterStyle: GoogleFonts.montserrat(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: AppColors.grey(600),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: AppColors.outlineSide,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: AppColors.outlineSide,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide(color: AppColors.mid, width: 1.4),
        ),
      ),

      // Fallback popup look for any dialog/sheet not built with
      // widgets/agri_dialog.dart (e.g. date pickers): same rounded white
      // card, Montserrat, dark-green title and the same dimmed barrier.
      // New popups should use agri_dialog.dart for the full frosted style.
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        barrierColor: const Color(0x61000000),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: AppColors.outlineSide,
        ),
        titleTextStyle: GoogleFonts.montserrat(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: AppColors.brand,
        ),
        contentTextStyle: GoogleFonts.montserrat(
          fontSize: 13,
          color: AppColors.text,
          height: 1.45,
        ),
      ),
      // The calendar (Report Delay, harvest date, needed-by date…) in the
      // same look as every other popup: a white card with rounded corners,
      // a dark-green Montserrat heading, the chosen day filled dark green,
      // and pill Cancel / OK buttons like AgriDialogButton.
      datePickerTheme: _datePickerTheme(),
      timePickerTheme: TimePickerThemeData(
        backgroundColor: AppColors.surface,
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        helpTextStyle: GoogleFonts.montserrat(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.grey(600),
        ),
        dialHandColor: AppColors.brandFill,
        dialBackgroundColor: AppColors.tint,
        hourMinuteColor: WidgetStateColor.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.accent
              : AppColors.tint,
        ),
        hourMinuteTextColor: AppColors.brand,
        hourMinuteShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        dayPeriodShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        dayPeriodColor: AppColors.accent,
        dayPeriodTextColor: AppColors.brand,
        entryModeIconColor: AppColors.brand,
        cancelButtonStyle: _pickerCancelButton,
        confirmButtonStyle: _pickerConfirmButton,
      ),

      // Every dropdown list and popup menu opens as the same white panel
      // with rounded corners (it used to take the app's greenish surface
      // colour), with the current choice shown in pale green.
      canvasColor: AppColors.surface,
      focusColor: AppColors.accent.withValues(alpha: 0.7),
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shadowColor: Colors.black.withValues(alpha: 0.25),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: AppColors.outlineSide,
        ),
        textStyle: GoogleFonts.montserrat(
          fontSize: 13.5,
          color: AppColors.text,
        ),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(AppColors.surface),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(16)),
            ),
          ),
        ),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        modalBarrierColor: const Color(0x61000000),
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          side: AppColors.outlineSide,
        ),
      ),

      // Every system message (SnackBar): white text on the brand's dark
      // green, floating with rounded corners. The text colour has to be set
      // here — without one it fell back to the dark body text and could
      // not be read on the dark bar.
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.brandFill,
        contentTextStyle: GoogleFonts.montserrat(
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
          color: Colors.white,
        ),
        actionTextColor: AppColors.accent,
        closeIconColor: Colors.white,
        behavior: SnackBarBehavior.floating,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // Picker buttons, shaped like AgriDialogButton: Cancel outlined, the
  // confirm button filled dark green.
  static ButtonStyle get _pickerCancelButton => TextButton.styleFrom(
    foregroundColor: AppColors.brand,
    backgroundColor: AppColors.surface,
    side: BorderSide(color: AppColors.brand, width: 1.2),
    shape: const StadiumBorder(),
    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
    textStyle: GoogleFonts.montserrat(
      fontSize: 13.5,
      fontWeight: FontWeight.w600,
    ),
  );
  static ButtonStyle get _pickerConfirmButton => TextButton.styleFrom(
    foregroundColor: Colors.white,
    backgroundColor: AppColors.brandFill,
    shape: const StadiumBorder(),
    padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 10),
    textStyle: GoogleFonts.montserrat(
      fontSize: 13.5,
      fontWeight: FontWeight.w600,
    ),
  );

  static DatePickerThemeData _datePickerTheme() {
    OutlineInputBorder pill(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: BorderSide(color: color, width: width),
        );
    return DatePickerThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: 0.25),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      headerBackgroundColor: AppColors.surface,
      headerForegroundColor: AppColors.brand,
      headerHelpStyle: GoogleFonts.montserrat(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: AppColors.grey(600),
      ),
      headerHeadlineStyle: GoogleFonts.montserrat(
        fontSize: 26,
        fontWeight: FontWeight.w700,
        color: AppColors.brand,
      ),
      dividerColor: AppColors.grey(200),
      subHeaderForegroundColor: AppColors.brand,
      toggleButtonTextStyle: GoogleFonts.montserrat(
        fontSize: 13.5,
        fontWeight: FontWeight.w700,
        color: AppColors.brand,
      ),
      weekdayStyle: GoogleFonts.montserrat(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: AppColors.grey(600),
      ),
      dayStyle: GoogleFonts.montserrat(
        fontSize: 13.5,
        fontWeight: FontWeight.w500,
      ),
      dayForegroundColor: WidgetStateColor.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return Colors.white;
        if (states.contains(WidgetState.disabled)) {
          return AppColors.grey(400);
        }
        return AppColors.text;
      }),
      dayBackgroundColor: WidgetStateColor.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? AppColors.brandFill
            : Colors.transparent,
      ),
      dayOverlayColor: WidgetStatePropertyAll(
        AppColors.accent.withValues(alpha: 0.6),
      ),
      todayForegroundColor: WidgetStateColor.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return Colors.white;
        if (states.contains(WidgetState.disabled)) {
          return AppColors.grey(400);
        }
        return AppColors.brand;
      }),
      todayBackgroundColor: WidgetStateColor.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? AppColors.brandFill
            : Colors.transparent,
      ),
      todayBorder: BorderSide(color: AppColors.mid, width: 1.4),
      yearStyle: GoogleFonts.montserrat(
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      yearForegroundColor: WidgetStateColor.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? Colors.white
            : AppColors.brand,
      ),
      yearBackgroundColor: WidgetStateColor.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? AppColors.brandFill
            : Colors.transparent,
      ),
      // Typing the date instead (the pencil): the same pill field as the
      // rest of the app.
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 14,
        ),
        border: pill(AppColors.grey(300)),
        enabledBorder: pill(AppColors.grey(300)),
        focusedBorder: pill(AppColors.mid, 1.4),
        errorBorder: pill(Colors.redAccent, 1.2),
        focusedErrorBorder: pill(Colors.redAccent, 1.4),
      ),
      cancelButtonStyle: _pickerCancelButton,
      confirmButtonStyle: _pickerConfirmButton,
    );
  }

  // Every app bar's Back button, on every screen: the shared white circle
  // with a dark green arrow instead of Flutter's plain arrow. Only the
  // icon changes — what the button does when tapped is untouched.
  static final ActionIconThemeData backButtonTheme = ActionIconThemeData(
    backButtonIconBuilder: (context) => const AppBackIcon(),
  );

  // ==========================================================
  // HELPER STYLES
  // ----------------------------------------------------------
  // You mostly won't need these now that the global theme handles
  // fonts — a plain Text('Hello') already renders in Montserrat. Keep
  // them for when you want a specific size or weight quickly.
  // ==========================================================

  static TextStyle heading(double size) => GoogleFonts.montserrat(
    fontSize: size,
    fontWeight: FontWeight.bold,
    color: AppColors.text,
  );

  static TextStyle label() => GoogleFonts.montserrat(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: AppColors.text,
  );

  static TextStyle body({Color? color, double size = 13.5}) =>
      GoogleFonts.montserrat(
        fontSize: size,
        color: color ?? AppColors.grey(700),
      );

  // The "AgriTrade+" wordmark: the whole word in one colour — the brand's
  // dark green, or white where it sits on a dark background. Rendered by
  // AgriTradeText; anything else that draws the brand name uses this too.
  // Montserrat Bold — the bundled Montserrat (pubspec.yaml), the same as
  // the password reset page's wordmark, so it is the same everywhere.
  static TextStyle brandText({double fontSize = 28, bool light = false}) =>
      TextStyle(
        fontFamily: 'Montserrat',
        fontWeight: FontWeight.w700,
        letterSpacing: fontSize * 0.01,
        fontSize: fontSize,
        color: light ? Colors.white : AppColors.brand,
      );

  // Lilita One, bundled in assets/fonts (see pubspec.yaml), for the few
  // display headings that use it ("Verify Your Email").
  static const String brandFontFamily = 'LilitaOne';

  // Buttons app-wide are slim pills, in proportion with the small bottom
  // bar: 14px bold text, about 40 high.
  static TextStyle buttonText() =>
      GoogleFonts.montserrat(fontSize: 14, fontWeight: FontWeight.bold);

  static const EdgeInsets buttonPadding = EdgeInsets.symmetric(
    vertical: 11,
    horizontal: 20,
  );

  // ---------- REUSABLE PIECES ----------

  static BoxDecoration authCard() => BoxDecoration(
    color: AppColors.surface.withValues(alpha: 0.90),
    borderRadius: BorderRadius.circular(24),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.15),
        blurRadius: 20,
        offset: const Offset(0, 8),
      ),
    ],
  );

  static ButtonStyle primaryButton() => ElevatedButton.styleFrom(
    backgroundColor: AppColors.brandFill,
    foregroundColor: Colors.white,
    padding: buttonPadding,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
  );

  // ---------- LOGIN-STYLE "GLOW" FIELD ----------
  // Pill-shaped, borderless field on its own white plate. At rest it only
  // has a faint lift shadow; the brand-green glow (in place of the usual
  // blue-glow neumorphic look) switches on around it while it's focused —
  // see the field wrapping this in LoginFormFields for the FocusNode that
  // drives [focused]. Used by the login form.
  static BoxDecoration glowFieldWrapper({bool focused = false}) =>
      BoxDecoration(
        color: AppColors.surface,
        border: AppColors.cardBorder,
        borderRadius: BorderRadius.circular(30),
        boxShadow: focused
            ? [
                BoxShadow(
                  color: AppColors.mid.withValues(alpha: 0.18),
                  blurRadius: 12,
                  spreadRadius: 0.5,
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
      );

  static InputDecoration inputBox({
    required String hint,
    required IconData icon,
    Widget? suffix,
    String? errorText,
    String? prefixText,
  }) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, color: AppColors.grey()),
      prefixText: prefixText,
      prefixStyle: TextStyle(
        color: AppColors.brand,
        fontWeight: FontWeight.w600,
        fontSize: 15,
      ),
      suffixIcon: suffix,
      filled: true,
      fillColor: AppColors.field,
      errorText: errorText,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(30),
        borderSide: AppColors.outlineSide,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(30),
        borderSide: AppColors.outlineSide,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(30),
        borderSide: BorderSide(color: AppColors.mid, width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(30),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(30),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.4),
      ),
    );
  }
}
