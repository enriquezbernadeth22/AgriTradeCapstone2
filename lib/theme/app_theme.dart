import 'dart:ui' show lerpDouble;

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
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        side: BorderSide(color: AppColors.textMuted, width: 1.4),
        fillColor: WidgetStateProperty.resolveWith(
          // Near-black when ticked; green in dark mode, where near-black
          // would vanish into the page.
          (states) => states.contains(WidgetState.selected)
              ? (dark ? AppColors.brandFill : const Color(0xFF1C1F23))
              : Colors.transparent,
        ),
        checkColor: const WidgetStatePropertyAll(Colors.white),
      ),
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

      // Default look for every TextField: a pill on one line, rounded
      // corners on a several-line box (see PillInputBorder).
      // Every text field looks like Log In's: white, a thin grey outline, and
      // while typed in no outline but a soft green glow (fieldFocusBorder).
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        isDense: true,
        // Wide enough that the text stays clear of the pill's round ends.
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 14,
        ),
        hintStyle: GoogleFonts.montserrat(
          fontSize: 14,
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
        border: fieldBorder,
        enabledBorder: fieldBorder,
        focusedBorder: fieldFocusBorder,
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
        focusedBorder: fieldFocusBorder,
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

  // Buttons app-wide are pills with 14px semibold text.
  static TextStyle buttonText() =>
      GoogleFonts.montserrat(fontSize: 14, fontWeight: FontWeight.w600);

  // ==========================================================
  // FORMS
  // ----------------------------------------------------------
  // One look for every form screen (Log In, Forgot Password, registration,
  // the Google profile form, Edit Profile, Change Password, and any new
  // one), in this order of emphasis: the page title, its description, the
  // field labels, the fields, the primary button, then links.
  // ==========================================================

  /// A form screen's title: the first thing read on it.
  static TextStyle pageTitle({Color? color}) => GoogleFonts.montserrat(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    color: color ?? AppColors.text,
    height: 1.25,
  );

  /// The line or two under a page title: support only, muted.
  static TextStyle pageDescription() => GoogleFonts.montserrat(
    fontSize: 13.5,
    color: AppColors.textSecondary,
    height: 1.45,
  );

  /// A secondary action in a form ("Forgot Password?", "Create One.",
  /// "Back to Login", "Update"): dark green, quieter than the primary button.
  static TextStyle formLink({double size = 13.5}) => GoogleFonts.montserrat(
    fontSize: size,
    fontWeight: FontWeight.w600,
    color: AppColors.brand,
  );

  /// Size of the text typed into a form field, and of its placeholder.
  static const double formTextSize = 14;

  /// A form field's placeholder: muted.
  static TextStyle formHint() =>
      GoogleFonts.montserrat(fontSize: formTextSize, color: AppColors.grey());

  /// Every form field and dropdown is this tall.
  static const double formFieldHeight = 48;

  /// Every primary and secondary button in a form is this tall.
  static const double formButtonHeight = 50;

  /// The icon at the start of a field: one size, and quieter than the text.
  static const double formIconSize = 20;
  static Color get formIconColor => AppColors.grey(600);

  /// The left and right margin of a form page.
  static const double formPageMargin = 24;

  /// Between a label and its field.
  static const double formLabelGap = 8;

  /// Between one field and the next label.
  static const double formFieldGap = 16;

  /// Between the parts of a form (the title block, the fields, the button).
  static const double formSectionGap = 24;

  // The outline of every field and dropdown at rest, and while typed in.
  static BorderSide get _formOutline =>
      BorderSide(color: AppColors.grey(300), width: 1.2);

  /// Every text field's outline at rest, as on Log In: a thin light grey
  /// pill (rounded corners when several lines tall).
  static PillInputBorder get fieldBorder =>
      PillInputBorder(borderSide: _formOutline);

  /// Every text field while typed in, as on Log In: no outline, a soft
  /// green glow around it (see [GlowInputBorder]).
  static const GlowInputBorder fieldFocusBorder = GlowInputBorder(
    borderSide: _formOutlineHidden,
  );
  static BorderSide get _formOutlineFocused =>
      BorderSide(color: AppColors.mid, width: 1.4);
  // The outline's room kept, nothing drawn: a field on a glow plate, typed in.
  static const BorderSide _formOutlineHidden = BorderSide(
    color: Colors.transparent,
    width: 1.2,
  );
  static const BorderSide _formOutlineError = BorderSide(
    color: Colors.redAccent,
    width: 1.2,
  );

  // The icon at the start of a field, a thin line, and any fixed prefix
  // ("+63 "), always showing: the same as GlowField, so a field built on
  // InputDecoration looks the same. (InputDecoration's own prefixText shows
  // only once the field is focused or filled.) The gap after it matches
  // GlowField's, as the decoration adds a little of its own.
  static Widget _formLeadingIcon(IconData icon, String? prefixText) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const SizedBox(width: 18),
      Icon(icon, color: formIconColor, size: formIconSize),
      const SizedBox(width: 12),
      Container(width: 1, height: 22, color: AppColors.hairline),
      if (prefixText != null) ...[
        const SizedBox(width: 12),
        Text(
          prefixText,
          style: GoogleFonts.montserrat(
            color: AppColors.brand,
            fontWeight: FontWeight.w600,
            fontSize: formTextSize,
          ),
        ),
      ],
      const SizedBox(width: _formLeadingGap),
    ],
  );

  // Between the leading part and the text, on top of the decoration's own.
  static const double _formLeadingGap = 8;

  /// A form field on InputDecoration (a plain TextField, or one with a
  /// helper, a counter or a chip at the end), looking the same as GlowField:
  /// a white pill [formFieldHeight] tall with a light grey outline, the icon,
  /// a thin line, then the text.
  ///
  /// With [onGlowPlate] (inside a FormFieldGlow) it has no outline while
  /// typed in: the plate's glow shows instead, as on GlowField. Without one
  /// the outline turns green. Show an error or a note under such a field
  /// on its own line, not in [errorText] or [helperText], so the glow goes
  /// round the field alone.
  static InputDecoration formFieldDecoration({
    required IconData icon,
    String? hint,
    Widget? suffix,
    String? errorText,
    String? prefixText,
    String? helperText,
    bool onGlowPlate = false,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: formHint(),
      prefixIcon: _formLeadingIcon(icon, prefixText),
      prefixIconConstraints: const BoxConstraints(minHeight: formFieldHeight),
      suffixIcon: suffix,
      filled: true,
      fillColor: AppColors.surface,
      errorText: errorText,
      errorMaxLines: 3,
      helperText: helperText,
      helperStyle: GoogleFonts.montserrat(
        color: AppColors.grey(600),
        fontSize: 11.5,
      ),
      helperMaxLines: 3,
      isDense: true,
      contentPadding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
      border: PillInputBorder(borderSide: _formOutline),
      enabledBorder: PillInputBorder(borderSide: _formOutline),
      disabledBorder: PillInputBorder(borderSide: _formOutline),
      // On a glow plate the plate glows; otherwise the field itself does.
      focusedBorder: onGlowPlate
          ? const PillInputBorder(borderSide: _formOutlineHidden)
          : fieldFocusBorder,
      errorBorder: const PillInputBorder(borderSide: _formOutlineError),
      focusedErrorBorder: const PillInputBorder(
        borderSide: BorderSide(color: Colors.redAccent, width: 1.4),
      ),
    );
  }

  /// A form field with no icon, such as a chat's message box: white with a
  /// thin grey outline, and — inside a FormFieldGlow — no outline while
  /// typed in, the plate's soft green glow instead (as on Log In).
  static InputDecoration plainFieldDecoration({String? hint}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: formHint(),
      isDense: true,
      filled: true,
      fillColor: AppColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      border: PillInputBorder(borderSide: _formOutline),
      enabledBorder: PillInputBorder(borderSide: _formOutline),
      disabledBorder: PillInputBorder(borderSide: _formOutline),
      focusedBorder: const PillInputBorder(borderSide: _formOutlineHidden),
    );
  }

  /// A dropdown in a form: the same as [formFieldDecoration], on a rounded
  /// rectangle rather than a pill, so its list reads as a list.
  static InputDecoration formDropdownDecoration({
    required IconData icon,
    String? hint,
    Widget? suffix,
    String? errorText,
    bool onGlowPlate = false,
  }) {
    OutlineInputBorder outline(BorderSide side) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(dropdownRadius),
      borderSide: side,
    );
    return formFieldDecoration(
      icon: icon,
      hint: hint,
      suffix: suffix,
      errorText: errorText,
    ).copyWith(
      // A dense dropdown's own line is 24 tall: 12 above and below makes
      // [formFieldHeight], the same as a text field.
      contentPadding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
      border: outline(_formOutline),
      enabledBorder: outline(_formOutline),
      disabledBorder: outline(_formOutline),
      focusedBorder: outline(
        onGlowPlate ? _formOutlineHidden : _formOutlineFocused,
      ),
      errorBorder: outline(_formOutlineError),
      focusedErrorBorder: outline(
        const BorderSide(color: Colors.redAccent, width: 1.4),
      ),
    );
  }

  /// The secondary button in a form (Continue with Google, Cancel): white,
  /// outlined in grey, dark text — never as strong as [primaryButton].
  static ButtonStyle secondaryButton() => OutlinedButton.styleFrom(
    foregroundColor: AppColors.text,
    backgroundColor: AppColors.surface,
    minimumSize: const Size(0, formButtonHeight),
    padding: const EdgeInsets.symmetric(horizontal: 20),
    // Dark enough to see the whole button on white, also while it is
    // waiting to be usable (Resend Reset Link's countdown).
    side: BorderSide(color: AppColors.grey(400), width: 1.2),
    shape: const StadiumBorder(),
  );

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

  /// The one main action of a form (Log In, Send Reset Link, Register, Save
  /// Changes): dark green with white text, [formButtonHeight] tall — the
  /// strongest thing on the page after its title.
  static ButtonStyle primaryButton() => ElevatedButton.styleFrom(
    backgroundColor: AppColors.brandFill,
    foregroundColor: Colors.white,
    disabledForegroundColor: Colors.white70,
    // Dark mode: a plain grey when it cannot be pressed, clearly apart from
    // the green one.
    disabledBackgroundColor: AppColors.isDark ? AppColors.grey(300) : null,
    minimumSize: const Size(0, formButtonHeight),
    padding: const EdgeInsets.symmetric(horizontal: 20),
    elevation: 0,
    shape: const StadiumBorder(),
  );

  // ---------- GLOW FIELD ----------
  // GlowField's plate: the form field look (see FORMS above) — a white pill.
  // While typed in it is the Admin login's field: the outline goes and a
  // soft green glow, with a slight lift, shows around it instead. Its
  // outline is [glowFieldOutline], drawn on top (foregroundDecoration) so
  // that it adds nothing to the field's height. FormFieldGlow gives a field
  // built on InputDecoration the same plate.
  static BoxDecoration glowFieldWrapper({
    bool focused = false,
    double radius = pillRadius,
  }) => BoxDecoration(
    color: AppColors.surface,
    borderRadius: BorderRadius.circular(radius),
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
        : null,
  );

  /// GlowField's outline: light grey at rest, none while typed in (the
  /// glow of [glowFieldWrapper] shows instead). For a foregroundDecoration.
  static BoxDecoration glowFieldOutline({
    bool focused = false,
    double radius = pillRadius,
  }) => BoxDecoration(
    border: focused ? null : Border.fromBorderSide(_formOutline),
    borderRadius: BorderRadius.circular(radius),
  );

  /// Outline shared by the registration form's dropdowns.
  static OutlineInputBorder registrationDropdownBorder({
    bool focused = false,
  }) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(dropdownRadius),
    borderSide: focused ? _formOutlineFocused : _formOutline,
  );

  /// A form field with an icon: the same as [formFieldDecoration].
  static InputDecoration inputBox({
    required String hint,
    required IconData icon,
    Widget? suffix,
    String? errorText,
    String? prefixText,
    bool onGlowPlate = false,
  }) => formFieldDecoration(
    icon: icon,
    hint: hint,
    suffix: suffix,
    errorText: errorText,
    prefixText: prefixText,
    onGlowPlate: onGlowPlate,
  );

  /// The corner radius that turns a box of any height into a pill: Flutter
  /// shrinks a radius larger than half the box's height to fit it.
  static const double pillRadius = 999;

  /// How round the Admin Portal's fields, buttons and cards are (see
  /// kAdminFieldRadius): rounded rectangles, not pills.
  static const double adminFieldRadius = 10;

  /// Dropdowns are rounded rectangles, unlike the pill text fields: this is
  /// the radius of a full-size one in a form, [compactDropdownRadius] of a
  /// small one in a toolbar or on a card.
  static const double dropdownRadius = 15;
  static const double compactDropdownRadius = 8;

  /// [base] with its outlines, or the theme's, on a dropdown's corners.
  static InputDecoration dropdownDecoration(
    BuildContext context, [
    InputDecoration base = const InputDecoration(),
  ]) {
    final theme = Theme.of(context).inputDecorationTheme;
    OutlineInputBorder? shaped(InputBorder? border) => border == null
        ? null
        : OutlineInputBorder(
            borderRadius: BorderRadius.circular(dropdownRadius),
            borderSide: border.borderSide,
          );
    return base.copyWith(
      border: shaped(base.border ?? theme.border),
      enabledBorder: shaped(base.enabledBorder ?? theme.enabledBorder),
      focusedBorder: shaped(base.focusedBorder ?? theme.focusedBorder),
      errorBorder: shaped(base.errorBorder ?? theme.errorBorder),
      focusedErrorBorder: shaped(
        base.focusedErrorBorder ?? theme.focusedErrorBorder,
      ),
    );
  }
}

/// A text field's outline: a pill while the field is one line tall, and
/// rounded corners once it grows to several lines, where a pill's round
/// ends would cut into the lines of text. The shape is worked out from the
/// field's height each time it is painted, so a field that grows as the
/// user types (chat, a review reply) turns from one into the other.
class PillInputBorder extends OutlineInputBorder {
  const PillInputBorder({super.borderSide, super.gapPadding});

  // Up to this tall, a field is one line and is drawn as a pill.
  static const double _singleLineMaxHeight = 64;

  // The corners of a field several lines tall.
  static const double _multilineRadius = 16;

  // The plain outline this border draws for a field of [rect]'s size.
  OutlineInputBorder _sizedTo(Rect rect) => OutlineInputBorder(
    borderSide: borderSide,
    gapPadding: gapPadding,
    borderRadius: BorderRadius.circular(
      rect.height <= _singleLineMaxHeight ? rect.height / 2 : _multilineRadius,
    ),
  );

  // The field fills its state colours in through copyWith and animates
  // between them through lerp and scale; each keeps this adaptive shape,
  // where OutlineInputBorder's own would drop back to a fixed radius.
  @override
  PillInputBorder copyWith({
    BorderSide? borderSide,
    BorderRadius? borderRadius,
    double? gapPadding,
  }) => PillInputBorder(
    borderSide: borderSide ?? this.borderSide,
    gapPadding: gapPadding ?? this.gapPadding,
  );

  @override
  PillInputBorder scale(double t) => PillInputBorder(
    borderSide: borderSide.scale(t),
    gapPadding: gapPadding * t,
  );

  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) {
    // Leaving a typed-in field: its glow fades out as the outline returns.
    if (a is GlowInputBorder && this is! GlowInputBorder) {
      if (t >= 1) return this;
      return GlowInputBorder(
        borderSide: BorderSide.lerp(a.borderSide, borderSide, t),
        gapPadding: gapPadding,
        glow: a.glow * (1 - t),
      );
    }
    if (a is PillInputBorder) {
      return PillInputBorder(
        borderSide: BorderSide.lerp(a.borderSide, borderSide, t),
        gapPadding: a.gapPadding,
      );
    }
    return super.lerpFrom(a, t);
  }

  @override
  ShapeBorder? lerpTo(ShapeBorder? b, double t) {
    if (b is PillInputBorder) {
      return PillInputBorder(
        borderSide: BorderSide.lerp(borderSide, b.borderSide, t),
        gapPadding: b.gapPadding,
      );
    }
    return super.lerpTo(b, t);
  }

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      _sizedTo(rect).getInnerPath(rect, textDirection: textDirection);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      _sizedTo(rect).getOuterPath(rect, textDirection: textDirection);

  @override
  void paintInterior(
    Canvas canvas,
    Rect rect,
    Paint paint, {
    TextDirection? textDirection,
  }) => _sizedTo(
    rect,
  ).paintInterior(canvas, rect, paint, textDirection: textDirection);

  @override
  void paint(
    Canvas canvas,
    Rect rect, {
    double? gapStart,
    double gapExtent = 0.0,
    double gapPercentage = 0.0,
    TextDirection? textDirection,
  }) => _sizedTo(rect).paint(
    canvas,
    rect,
    gapStart: gapStart,
    gapExtent: gapExtent,
    gapPercentage: gapPercentage,
    textDirection: textDirection,
  );
}

/// A field's border while it is typed in, as on Log In: no outline (its
/// [borderSide] is see-through), a soft green glow and a slight shadow
/// around the field instead — the same as GlowField's plate
/// ([AppTheme.glowFieldWrapper]), but on any TextField, through its
/// InputDecoration. [glow] (0 to 1) fades it in and out as focus moves.
class GlowInputBorder extends PillInputBorder {
  const GlowInputBorder({super.borderSide, super.gapPadding, this.glow = 1});

  final double glow;

  @override
  GlowInputBorder copyWith({
    BorderSide? borderSide,
    BorderRadius? borderRadius,
    double? gapPadding,
  }) => GlowInputBorder(
    borderSide: borderSide ?? this.borderSide,
    gapPadding: gapPadding ?? this.gapPadding,
    glow: glow,
  );

  @override
  GlowInputBorder scale(double t) => GlowInputBorder(
    borderSide: borderSide.scale(t),
    gapPadding: gapPadding * t,
    glow: glow,
  );

  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) {
    if (a is PillInputBorder) {
      return GlowInputBorder(
        borderSide: BorderSide.lerp(a.borderSide, borderSide, t),
        gapPadding: gapPadding,
        glow: lerpDouble(a is GlowInputBorder ? a.glow : 0, glow, t)!,
      );
    }
    return super.lerpFrom(a, t);
  }

  @override
  ShapeBorder? lerpTo(ShapeBorder? b, double t) {
    if (b is PillInputBorder) {
      return GlowInputBorder(
        borderSide: BorderSide.lerp(borderSide, b.borderSide, t),
        gapPadding: b.gapPadding,
        glow: lerpDouble(glow, b is GlowInputBorder ? b.glow : 0, t)!,
      );
    }
    return super.lerpTo(b, t);
  }

  @override
  void paint(
    Canvas canvas,
    Rect rect, {
    double? gapStart,
    double gapExtent = 0.0,
    double gapPercentage = 0.0,
    TextDirection? textDirection,
  }) {
    if (glow > 0) {
      final shape = getOuterPath(rect, textDirection: textDirection);
      // Only outside the field, so the glow never tints what is typed.
      canvas.save();
      canvas.clipPath(
        Path.combine(
          PathOperation.difference,
          Path()..addRect(rect.inflate(24)),
          shape,
        ),
      );
      // The same two shadows as GlowField's plate (glowFieldWrapper).
      canvas.drawPath(
        shape,
        Paint()
          ..color = AppColors.mid.withValues(alpha: 0.18 * glow)
          ..maskFilter = MaskFilter.blur(
            BlurStyle.normal,
            Shadow.convertRadiusToSigma(12),
          ),
      );
      canvas.drawPath(
        shape.shift(const Offset(0, 3)),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.06 * glow)
          ..maskFilter = MaskFilter.blur(
            BlurStyle.normal,
            Shadow.convertRadiusToSigma(8),
          ),
      );
      canvas.restore();
    }
    super.paint(
      canvas,
      rect,
      gapStart: gapStart,
      gapExtent: gapExtent,
      gapPercentage: gapPercentage,
      textDirection: textDirection,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GlowInputBorder &&
      other.borderSide == borderSide &&
      other.gapPadding == gapPadding &&
      other.glow == glow;

  @override
  int get hashCode => Object.hash(borderSide, gapPadding, glow);
}
