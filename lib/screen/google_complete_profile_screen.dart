import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../widgets/app_scaffold_messenger.dart';

import '../services/auth_routing_service.dart';
import '../services/auth_service.dart';
import '../services/ph_mobile.dart';
import '../services/rsba_number.dart';
import '../theme/app_theme.dart';
import '../widgets/agritrade_text.dart';
import '../widgets/barangay_location_field.dart';
import '../widgets/public_location_preview.dart';
import '../widgets/registration_role_details.dart';
import '../widgets/step_content_entrance.dart';
import '../widgets/agri_app_bar.dart';
import '../widgets/agri_dialog.dart';
import '../widgets/glow_field.dart';
import 'auth_route_handler.dart';
import 'privacy_policy_screen.dart';
import 'supported_products_screen.dart';
import 'terms_and_conditions_screen.dart';
import '../l10n/tr.dart';
import '../services/person_name.dart';
import '../theme/app_colors.dart';
import '../l10n/app_language.dart';

/// The short sign-up form after a brand-new "Continue with Google" sign-in,
/// opened from [ChooseRoleScreen] once a role is picked. The Google account
/// is already authenticated with Firebase at this point (see
/// AuthService.signInWithGoogle), but there's no users/{uid} document yet.
/// Google already gives the name (prefilled, editable) and the email (shown,
/// not editable), and there is no password, so this asks only for what
/// AgriTrade+ still needs: "What best describes you", the mobile number and,
/// for farmers, the same RSBSA No. and barangay RegisterScreen asks for.
///
/// The role is fixed here: Back returns to [ChooseRoleScreen] to change it,
/// and so does Cancel; leaving that screen signs the Google account out.
class GoogleCompleteProfileScreen extends StatefulWidget {
  final String uid;
  final String email;
  final String? initialName;
  final String role;

  const GoogleCompleteProfileScreen({
    super.key,
    required this.uid,
    required this.email,
    required this.role,
    this.initialName,
  });

  @override
  State<GoogleCompleteProfileScreen> createState() =>
      _GoogleCompleteProfileScreenState();
}

class _GoogleCompleteProfileScreenState
    extends State<GoogleCompleteProfileScreen> {
  // First name and Last name, filled in from the Google account's name
  // (its last word as the last name) for the user to correct.
  late final _initialName = splitName(widget.initialName ?? '');
  late final _firstNameController = TextEditingController(
    text: _initialName.first,
  );
  late final _lastNameController = TextEditingController(
    text: _initialName.last,
  );
  // Holds only the 10 local digits — see RegisterScreen._mobileController's
  // doc for the full rationale (fixed "+63 " prefix, required for both
  // roles).
  final _mobileController = TextEditingController();
  // Shown only; the email is the Google account's own.
  late final _emailController = TextEditingController(text: widget.email);
  late final String _selectedRole = widget.role == 'farmer'
      ? 'farmer'
      : 'buyer';
  // The answer to "What best describes you".
  String? _accountType;

  String? _selectedBarangay;
  // Farmer-only, as in email registration (see rsba_number.dart).
  final _rsbaController = TextEditingController();
  bool _rsbaTouched = false;

  // Made on first use (on Register), so the form opens without Firebase.
  late final _authService = AuthService();

  bool _loading = false;
  bool _triedSubmit = false;

  bool _agreedToTerms = false;
  bool _supportedProductsAcknowledged = false;

  final _scrollController = ScrollController();

  static const double _registerButtonHeight = AppTheme.formButtonHeight;
  static const double _registerFloatGap = 6;
  static const double _formEndTextHeight = 62;
  static const double _formBottomPadding = 8;
  double _drawnRegisterBottom = _registerFloatGap;

  bool get _isFarmer => _selectedRole == 'farmer';

  @override
  void dispose() {
    _firstNameController.dispose();
    _emailController.dispose();
    _rsbaController.dispose();
    _lastNameController.dispose();
    _mobileController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  bool _mobileNumberValid(String digits) => isValidPhMobile(digits);

  bool get _isFormValid {
    final mobile = _mobileController.text.trim();
    if (!isValidNamePart(_firstNameController.text)) return false;
    if (!isValidNamePart(_lastNameController.text)) return false;
    // Required for both roles — order/delivery/pick-up coordination.
    if (!_mobileNumberValid(mobile)) return false;
    if (_accountType == null) return false;
    if (_isFarmer) {
      if (_selectedBarangay == null) return false;
      if (!isValidRsba(_rsbaController.text)) return false;
      if (!_supportedProductsAcknowledged) return false;
    }
    if (!_agreedToTerms) return false;
    return true;
  }

  String? get _rsbaError => rsbaError(
    _rsbaController.text,
    touched: _rsbaTouched,
    submitted: _triedSubmit,
  );

  // Shown only after a submit attempt, matching the other field errors
  // on this screen.
  // Shared rules for both name fields (person_name.dart).
  String? get _firstNameError => !_triedSubmit
      ? null
      : nameFieldError(
          _firstNameController.text,
          label: tl('First name'),
          submitted: true,
        );

  String? get _lastNameError => !_triedSubmit
      ? null
      : nameFieldError(
          _lastNameController.text,
          label: tl('Last name'),
          submitted: true,
        );

  String get _fullName =>
      joinName(_firstNameController.text, _lastNameController.text);

  // Required for both roles (order/delivery/pick-up coordination).
  // "Must start with 9" shows live; "required"/"incomplete"
  // only after a submit attempt — same rationale as RegisterScreen.
  String? get _mobileError {
    // Shared rules for every mobile field in the app — see ph_mobile.dart.
    return phMobileError(
      _mobileController.text.trim(),
      required: true,
      submitted: _triedSubmit,
    );
  }

  // Every message here is a problem to fix before continuing.
  void _showMessage(String message) {
    showAppMessage(context, tl(message), kind: MessageKind.error);
  }

  // Cancel: back to choosing Buyer or Farmer, still signed in with Google
  // (not out to Log In — decided by the user, 2026-11-05). Leaving the
  // role choice itself is what signs the Google account out.
  // Through maybePop, so a filled-in form asks first (see [_confirmLeave]).
  void _cancel() => Navigator.of(context).maybePop();

  // Anything typed or chosen beyond what came from the Google account,
  // which Back or Cancel would throw away.
  bool get _hasInput =>
      _firstNameController.text.trim() != _initialName.first.trim() ||
      _lastNameController.text.trim() != _initialName.last.trim() ||
      _mobileController.text.trim().isNotEmpty ||
      _rsbaController.text.trim().isNotEmpty ||
      _accountType != null ||
      _selectedBarangay != null ||
      _agreedToTerms ||
      _supportedProductsAcknowledged;

  // Set once the person has agreed to leave, so the pop goes through.
  bool _leaving = false;

  // As on RegisterScreen: Back (the arrow, the phone's Back, or Cancel)
  // with something filled in asks first, since none of it is saved yet.
  Future<void> _confirmLeave(Object? result) async {
    final leave = await showAgriConfirm(
      context: context,
      icon: Icons.edit_note_rounded,
      title: tl('Leave registration?'),
      message: tl('What you have filled in will be lost.'),
      confirmLabel: tl('Leave'),
      cancelLabel: tl('Keep Editing'),
      tone: AgriTone.destructive,
    );
    if (!leave || !mounted) return;
    setState(() => _leaving = true);
    Navigator.pop(context, result);
  }

  Future<void> _finish() async {
    setState(() => _triedSubmit = true);
    if (!_isFormValid) {
      _showMessage(tl('Please fix the errors below before continuing.'));
      return;
    }

    setState(() => _loading = true);

    // One role per account: this Google account only reaches this screen
    // at all when it has no users/{uid} doc yet (see AuthService
    // .signInWithGoogle's needsProfile outcome), so the role picked on
    // ChooseRoleScreen is this account's first and only role — already
    // enforced, nothing further to check.
    final mobileDigits = _mobileController.text.trim();
    final profileError = await _authService.completeGoogleProfile(
      uid: widget.uid,
      fullName: _fullName,
      firstName: formatPersonName(_firstNameController.text),
      lastName: formatPersonName(_lastNameController.text),
      email: widget.email,
      role: _selectedRole,
      mobileNumber: mobileDigits.isEmpty ? null : phMobileE164(mobileDigits),
      accountType: _accountType,
      barangay: _isFarmer ? _selectedBarangay : null,
      rsbaNumber: _isFarmer ? normalizeRsba(_rsbaController.text) : null,
      supportedProductsAcknowledged:
          _isFarmer && _supportedProductsAcknowledged,
    );
    if (!mounted) return;
    if (profileError != null) {
      setState(() => _loading = false);
      _showMessage(profileError);
      return;
    }

    // Buyers no longer set a location here — they set it later, per
    // order, when placing one (see place_order_screen.dart).

    if (!mounted) return;
    final result = await AuthRoutingService.decide(widget.uid);
    if (!mounted) return;
    setState(() => _loading = false);
    await applyAuthRouteResult(context, result, announceSignIn: true);
  }

  // ==========================================================
  // Farmer supported-product awareness — see register_screen.dart's
  // identical section for the full rationale; kept in sync wording-wise
  // since both screens are "Farmer setup," just reached via different
  // sign-up methods (password vs Google).
  // ==========================================================
  Widget _supportedProductsSection() {
    final showError = _triedSubmit && !_supportedProductsAcknowledged;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.20),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: showError ? Colors.red : AppColors.mid,
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.eco_outlined, color: AppColors.brand, size: 18),
              const SizedBox(width: 6),
              Text(
                tl('Supported Products in AgriTrade+'),
                style: AppTheme.body(
                  color: AppColors.brand,
                  size: 13.5,
                ).copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            tl(
              'AgriTrade+ currently supports selected agricultural commodities based on the products identified with the agricultural office. Only supported products can be posted in the marketplace.',
            ),
            style: AppTheme.body(
              color: AppColors.text,
              size: 12.5,
            ).copyWith(height: 1.4),
          ),
          const SizedBox(height: 6),
          Text(
            tl('Please review the supported products before continuing.'),
            style: AppTheme.body(
              color: AppColors.text,
              size: 12.5,
            ).copyWith(fontWeight: FontWeight.w600),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const SupportedProductsScreen(),
                ),
              ),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.brand,
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                tl('View Supported Products'),
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
              ),
            ),
          ),
          const SizedBox(height: 4),
          InkWell(
            onTap: () => setState(
              () => _supportedProductsAcknowledged =
                  !_supportedProductsAcknowledged,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: _supportedProductsAcknowledged,
                  onChanged: (v) => setState(
                    () => _supportedProductsAcknowledged = v ?? false,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      tl(
                        'I understand that AgriTrade+ currently supports only selected agricultural commodities and that I can only post products included in the Supported Products list.',
                      ),
                      style: AppTheme.body(
                        color: AppColors.text,
                        size: 12,
                      ).copyWith(height: 1.4),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (showError)
            Padding(
              padding: EdgeInsets.only(left: 12),
              child: Text(
                tl(
                  'Please confirm you understand the supported products scope.',
                ),
                style: TextStyle(color: Colors.red, fontSize: 11.5),
              ),
            ),
        ],
      ),
    );
  }

  Widget _publicLocationPreview() {
    if (_selectedBarangay == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16, top: 14),
      child: PublicLocationPreview(barangay: _selectedBarangay!),
    );
  }

  Widget _consentCheckbox() {
    final showError = _triedSubmit && !_agreedToTerms;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: InkWell(
        onTap: () => setState(() => _agreedToTerms = !_agreedToTerms),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: _agreedToTerms,
              onChanged: (v) => setState(() => _agreedToTerms = v ?? false),
              visualDensity: VisualDensity.compact,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RichText(
                      text: TextSpan(
                        style: AppTheme.body(
                          color: AppColors.text,
                          size: 12.5,
                        ).copyWith(height: 1.4),
                        children: [
                          TextSpan(text: tl('I agree to the ')),
                          TextSpan(
                            text: tl('Terms & Conditions'),
                            style:
                                AppTheme.body(
                                  color: AppColors.brand,
                                  size: 12.5,
                                ).copyWith(
                                  fontWeight: FontWeight.bold,
                                  decoration: TextDecoration.underline,
                                ),
                            recognizer: TapGestureRecognizer()
                              ..onTap = () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const TermsAndConditionsScreen(),
                                ),
                              ),
                          ),
                          TextSpan(text: tl(' and ')),
                          TextSpan(
                            text: tl('Privacy Policy'),
                            style:
                                AppTheme.body(
                                  color: AppColors.brand,
                                  size: 12.5,
                                ).copyWith(
                                  fontWeight: FontWeight.bold,
                                  decoration: TextDecoration.underline,
                                ),
                            recognizer: TapGestureRecognizer()
                              ..onTap = () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const PrivacyPolicyScreen(),
                                ),
                              ),
                          ),
                          const TextSpan(text: '.'),
                        ],
                      ),
                    ),
                    if (showError)
                      Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text(
                          tl(
                            'Please accept the Terms & Conditions and Privacy Policy to continue.',
                          ),
                          style: TextStyle(color: Colors.red, fontSize: 11.5),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // A name field: its label, the field, and its error on its own line
  // below (outside the input, as every error on this form is).
  Widget _nameField({
    required String label,
    required TextEditingController controller,
    required String hint,
    required String? error,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTheme.label()),
        const SizedBox(height: AppTheme.formLabelGap),
        FormFieldGlow(
          child: TextField(
            controller: controller,
            style: const TextStyle(fontSize: 14),
            textCapitalization: TextCapitalization.words,
            inputFormatters: kNameInputFormatters,
            onChanged: (_) => setState(() {}),
            decoration: AppTheme.inputBox(
              hint: hint,
              icon: Icons.person_outline,
              onGlowPlate: true,
            ),
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.error_outline,
                size: 14,
                color: AppColors.tone(Colors.red, 700),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  tl(error),
                  style: TextStyle(
                    color: AppColors.tone(Colors.red, 700),
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  // An error on its own line under a field, as on RegisterScreen.
  Widget _fieldError(String text) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.error_outline,
          size: 14,
          color: AppColors.tone(Colors.red, 700),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: AppColors.tone(Colors.red, 700),
              fontSize: 11,
            ),
          ),
        ),
      ],
    ),
  );

  double _registerButtonBottom(bool keyboardOpen) {
    if (!_scrollController.hasClients) return _registerFloatGap;
    final position = _scrollController.position;
    if (!position.hasContentDimensions) return _registerFloatGap;
    final leftToScroll = position.maxScrollExtent - position.pixels;
    final inPlace = _formEndTextHeight + _formBottomPadding - leftToScroll;
    return keyboardOpen ? inPlace : math.max(_registerFloatGap, inPlace);
  }

  Widget _registerButton() => SizedBox(
    height: _registerButtonHeight,
    child: ElevatedButton(
      onPressed: _loading ? null : _finish,
      style: AppTheme.primaryButton().copyWith(
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
      ),
      child: _loading
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Text(tr(context).registerButton, style: AppTheme.buttonText()),
    ),
  );

  Widget _formEnd() => Column(
    children: [
      const SizedBox(height: 16),
      const SizedBox(height: _registerButtonHeight, width: double.infinity),
      SizedBox(
        height: _formEndTextHeight,
        width: double.infinity,
        child: Column(
          children: [
            const SizedBox(height: 8),
            if (!_isFormValid && !_loading) ...[
              Text(
                tl('Please complete all fields first.'),
                style: AppTheme.body(color: AppColors.textMuted, size: 12),
              ),
              const SizedBox(height: 4),
            ],
            TextButton(
              onPressed: _loading ? null : _cancel,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                tl('Cancel'),
                style: AppTheme.formLink().copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final bottom = _registerButtonBottom(keyboardOpen);
      if ((bottom - _drawnRegisterBottom).abs() > 0.5) {
        setState(() => _drawnRegisterBottom = bottom);
      }
    });

    return PopScope(
      canPop: _leaving || _loading || !_hasInput,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _confirmLeave(result);
      },
      child: Scaffold(
        backgroundColor: AppColors.authPage,
        // The compact header, as on RegisterScreen: Back (to ChooseRoleScreen,
        // to pick the other role), and the small logo and name.
        appBar: const AgriAppBar(titleWidget: AgriTradeHeaderBrand()),
        // The content comes in from the right, under the still header.
        body: StepContentEntrance(
          child: SafeArea(
            top: false,
            child: Stack(
              children: [
                SingleChildScrollView(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(
                    AppTheme.formPageMargin,
                    AppTheme.formSectionGap,
                    AppTheme.formPageMargin,
                    _formBottomPadding,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Center(
                        child: Text(
                          tl('Complete Your Profile'),
                          textAlign: TextAlign.center,
                          style: AppTheme.pageTitle(),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Center(child: RegisteringAsBadge(isFarmer: _isFarmer)),
                      const SizedBox(height: AppTheme.formSectionGap),

                      RegistrationRoleDetails(
                        isFarmer: _isFarmer,
                        value: _accountType,
                        showRequired: _triedSubmit,
                        onChanged: (value) =>
                            setState(() => _accountType = value),
                      ),
                      const SizedBox(height: AppTheme.formFieldGap),

                      _nameField(
                        label: tr(context).firstName,
                        controller: _firstNameController,
                        hint: 'Juan',
                        error: _firstNameError,
                      ),
                      const SizedBox(height: AppTheme.formFieldGap),
                      _nameField(
                        label: tr(context).lastName,
                        controller: _lastNameController,
                        hint: 'Santos',
                        error: _lastNameError,
                      ),
                      const SizedBox(height: AppTheme.formFieldGap),

                      // ---- RSBSA No. (farmers only) ----
                      // In the same place as on RegisterScreen.
                      if (_isFarmer) ...[
                        Text(kRsbaLabel, style: AppTheme.label()),
                        const SizedBox(height: AppTheme.formLabelGap),
                        Focus(
                          canRequestFocus: false,
                          skipTraversal: true,
                          onFocusChange: (hasFocus) {
                            if (!hasFocus &&
                                _rsbaController.text.isNotEmpty &&
                                !_rsbaTouched) {
                              setState(() => _rsbaTouched = true);
                            }
                          },
                          child: FormFieldGlow(
                            child: TextField(
                              controller: _rsbaController,
                              style: const TextStyle(fontSize: 14),
                              // Plain keyboard with letters and numbers, no
                              // autocorrect.
                              keyboardType: TextInputType.visiblePassword,
                              inputFormatters: kRsbaInputFormatters,
                              onChanged: (_) => setState(() {}),
                              decoration: AppTheme.inputBox(
                                hint: kRsbaHint,
                                icon: Icons.badge_outlined,
                                onGlowPlate: true,
                              ),
                            ),
                          ),
                        ),
                        // Under the field, so the glow goes round the field alone.
                        if (_rsbaError != null) _fieldError(tl(_rsbaError!)),
                        const SizedBox(height: AppTheme.formFieldGap),
                      ],

                      // ---- Email ----
                      // The Google account's own address: shown so they know
                      // which account this is, but not editable.
                      Text(tr(context).emailAddress, style: AppTheme.label()),
                      const SizedBox(height: AppTheme.formLabelGap),
                      TextField(
                        controller: _emailController,
                        readOnly: true,
                        // Nothing to type in: it never takes focus.
                        canRequestFocus: false,
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textSecondary,
                        ),
                        decoration: AppTheme.inputBox(
                          hint: '',
                          icon: Icons.email_outlined,
                          suffix: Icon(
                            Icons.lock_outline,
                            size: 18,
                            color: AppColors.grey(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        tl('From your Google account.'),
                        style: TextStyle(
                          color: AppColors.grey(600),
                          fontSize: 11.5,
                        ),
                      ),
                      const SizedBox(height: AppTheme.formFieldGap),

                      // ---- Mobile Number ----
                      // Required for both roles (order/delivery/pick-up
                      // coordination). Fixed +63 prefix — no country
                      // dropdown, PH-only scope.
                      Text('Mobile Number', style: AppTheme.label()),
                      const SizedBox(height: AppTheme.formLabelGap),
                      FormFieldGlow(
                        child: TextField(
                          controller: _mobileController,
                          style: const TextStyle(fontSize: 14),
                          keyboardType: TextInputType.phone,
                          inputFormatters: kPhMobileInputFormatters,
                          decoration: AppTheme.inputBox(
                            hint: kPhMobileHint,
                            icon: Icons.phone_outlined,
                            prefixText: kPhMobilePrefix,
                            onGlowPlate: true,
                          ),
                        ),
                      ),
                      if (_mobileError != null) ...[
                        const SizedBox(height: 6),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.error_outline,
                              size: 14,
                              color: AppColors.tone(Colors.red, 700),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                _mobileError!,
                                style: TextStyle(
                                  color: AppColors.tone(Colors.red, 700),
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ] else if (_isFarmer) ...[
                        const SizedBox(height: 6),
                        Text(
                          tl(
                            'For order, delivery, and pick-up coordination only.',
                          ),
                          style: TextStyle(
                            color: AppColors.grey(600),
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                      const SizedBox(height: AppTheme.formFieldGap),

                      if (_isFarmer) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(
                              color: AppColors.tone(Colors.amber, 300),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.warning_amber_rounded,
                                color: AppColors.tone(Colors.amber, 800),
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  tl(
                                    'Only verified farmers from Laurel, Batangas will be approved.',
                                  ),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.tone(Colors.amber, 900),
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppTheme.formFieldGap),
                      ],
                      if (_isFarmer) _supportedProductsSection(),
                      if (_isFarmer)
                        BarangayLocationField(
                          value: _selectedBarangay,
                          errorText: _triedSubmit && _selectedBarangay == null
                              ? tl('Please select a barangay in Laurel.')
                              : null,
                          onChanged: (value) =>
                              setState(() => _selectedBarangay = value),
                        ),
                      if (_isFarmer) _publicLocationPreview(),
                      _consentCheckbox(),
                      _formEnd(),
                    ],
                  ),
                ),
                ListenableBuilder(
                  listenable: _scrollController,
                  builder: (context, child) {
                    _drawnRegisterBottom = _registerButtonBottom(keyboardOpen);
                    return Positioned(
                      left: AppTheme.formPageMargin,
                      right: AppTheme.formPageMargin,
                      bottom: _drawnRegisterBottom,
                      child: child!,
                    );
                  },
                  child: _registerButton(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
