import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../widgets/agri_dialog.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../services/auth_routing_service.dart';
import '../services/auth_service.dart';
import '../services/ph_mobile.dart';
import '../services/cloudinary_service.dart';
import '../theme/app_theme.dart';
import '../widgets/agritrade_text.dart';
import '../widgets/barangay_location_field.dart';
import '../widgets/permission_rationale_dialog.dart';
import '../widgets/public_location_preview.dart';
import '../widgets/role_toggle.dart';
import 'auth_route_handler.dart';
import 'privacy_policy_screen.dart';
import 'supported_products_screen.dart';
import 'terms_and_conditions_screen.dart';
import '../l10n/tr.dart';
import '../services/person_name.dart';
import '../theme/app_colors.dart';

/// Shown right after a brand-new "Continue with Google" sign-in — the
/// Google account is already authenticated with Firebase at this point
/// (see AuthService.signInWithGoogle), but there's no users/{uid} document
/// yet, so this collects the one thing Google can't tell us: which role
/// they're signing up as (and, for farmers, the same barangay +
/// certificate RegisterScreen collects for a password account).
class GoogleCompleteProfileScreen extends StatefulWidget {
  final String uid;
  final String email;
  final String? initialName;
  final String? initialPhotoUrl;
  // Pre-selects the toggle when they tapped Google sign-in on a
  // role-specific door; still changeable, same as RegisterScreen's toggle.
  final String initialRole;

  const GoogleCompleteProfileScreen({
    super.key,
    required this.uid,
    required this.email,
    required this.initialRole,
    this.initialName,
    this.initialPhotoUrl,
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
  late String _selectedRole = widget.initialRole == 'farmer'
      ? 'farmer'
      : 'buyer';

  String? _selectedBarangay;
  XFile? _certFile;
  Uint8List? _certBytes;
  XFile? _profilePhoto;
  Uint8List? _profilePhotoBytes;
  bool _useGooglePhoto = false;
  bool _photoPromptShown = false;

  final _authService = AuthService();
  final _cloudinaryService = CloudinaryService();
  final _imagePicker = ImagePicker();

  bool _loading = false;
  bool _triedSubmit = false;

  bool _agreedToTerms = false;
  bool _supportedProductsAcknowledged = false;

  bool get _isFarmer => _selectedRole == 'farmer';

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _mobileController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _chooseProfilePhoto());
  }

  Future<void> _chooseProfilePhoto() async {
    final googlePhoto = widget.initialPhotoUrl;
    if (googlePhoto == null || googlePhoto.isEmpty || !mounted) return;
    final choice = await showAgriDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AgriDialog(
        title: const Text(
          'Choose your profile photo',
          textAlign: TextAlign.center,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 42,
              backgroundImage: NetworkImage(googlePhoto),
            ),
            const SizedBox(height: 12),
            const Text(
              'Use your Google photo, or upload a different one.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          AgriDialogButton(
            label: 'Upload my own',
            onPressed: () => Navigator.pop(context, 'upload'),
          ),
          AgriDialogButton(
            label: 'Use Google photo',
            kind: AgriButtonKind.primary,
            onPressed: () => Navigator.pop(context, 'google'),
          ),
        ],
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'google') {
      setState(() => _useGooglePhoto = true);
      return;
    }
    await _pickProfilePhoto();
  }

  Future<void> _pickProfilePhoto() async {
    final picked = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1000,
      imageQuality: 75,
    );
    if (picked != null) {
      final bytes = await picked.readAsBytes();
      if (mounted) {
        setState(() {
          _profilePhoto = picked;
          _profilePhotoBytes = bytes;
          _useGooglePhoto = false;
        });
      }
    }
  }

  bool _mobileNumberValid(String digits) => isValidPhMobile(digits);

  bool get _isFormValid {
    final mobile = _mobileController.text.trim();
    if (!isValidNamePart(_firstNameController.text)) return false;
    if (!isValidNamePart(_lastNameController.text)) return false;
    // Required for both roles — order/delivery/pick-up coordination.
    if (!_mobileNumberValid(mobile)) return false;
    if (_isFarmer) {
      if (_selectedBarangay == null) return false;
      if (_certFile == null) return false;
      if (!_supportedProductsAcknowledged) return false;
    }
    if (!_agreedToTerms) return false;
    return true;
  }

  // Shown only after a submit attempt, matching the other field errors
  // on this screen.
  // Shared rules for both name fields (person_name.dart).
  String? get _firstNameError => !_triedSubmit
      ? null
      : nameFieldError(
          _firstNameController.text,
          label: 'First name',
          submitted: true,
        );

  String? get _lastNameError => !_triedSubmit
      ? null
      : nameFieldError(
          _lastNameController.text,
          label: 'Last name',
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

  void _selectRole(String role) {
    if (role == _selectedRole) return;
    setState(() {
      _selectedRole = role;
      // Farmer's barangay and buyer's map pin are separate fields — only
      // the certificate is farmer-only.
      if (role != 'farmer') {
        _certFile = null;
        _certBytes = null;
      }
    });
  }

  static const int _maxCertBytes = 5 * 1024 * 1024; // 5MB
  static const List<String> _allowedCertExtensions = ['.png', '.jpg', '.jpeg'];

  Future<void> _pickCertificate() async {
    if (!_photoPromptShown) {
      _photoPromptShown = true;
      final proceed = await showPermissionRationale(
        context,
        icon: Icons.photo_library_outlined,
        title: 'Attach your certificate',
        message:
            'AgriTrade+ needs access to your photos so you can attach '
            'a picture of your agricultural certification.',
      );
      if (!proceed) return;
      if (!mounted) return;
    }

    final XFile? picked = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      imageQuality: 75,
    );
    if (picked == null) return;

    final name = picked.name.toLowerCase();
    if (!_allowedCertExtensions.any(name.endsWith)) {
      _showMessage('Please attach a PNG or JPG image.');
      return;
    }

    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    if (bytes.length > _maxCertBytes) {
      _showMessage('That image is too large. Please attach one under 5MB.');
      return;
    }

    setState(() {
      _certFile = picked;
      _certBytes = bytes;
    });
  }

  void _removeCertificate() {
    setState(() {
      _certFile = null;
      _certBytes = null;
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _cancel() async {
    await _authService.signOut();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _finish() async {
    setState(() => _triedSubmit = true);
    if (!_isFormValid) {
      _showMessage('Please fix the errors below before continuing.');
      return;
    }

    setState(() => _loading = true);

    // One role per account: this Google account only reaches this screen
    // at all when it has no users/{uid} doc yet (see AuthService
    // .signInWithGoogle's needsProfile outcome), so whatever role they
    // pick here is this account's first and only role — already enforced,
    // nothing further to check.
    final mobileDigits = _mobileController.text.trim();
    String? profilePhotoUrl = _useGooglePhoto ? widget.initialPhotoUrl : null;
    if (_profilePhoto != null) {
      profilePhotoUrl = await _cloudinaryService.uploadImage(
        _profilePhoto!,
        folder: 'agritrade/profiles',
      );
      if (profilePhotoUrl == null) {
        setState(() => _loading = false);
        _showMessage('Profile photo upload failed. Please try again.');
        return;
      }
    }
    final profileError = await _authService.completeGoogleProfile(
      uid: widget.uid,
      fullName: _fullName,
      firstName: tidyName(_firstNameController.text),
      lastName: tidyName(_lastNameController.text),
      email: widget.email,
      role: _selectedRole,
      photoUrl: profilePhotoUrl,
      mobileNumber: mobileDigits.isEmpty ? null : phMobileE164(mobileDigits),
      supportedProductsAcknowledged:
          _isFarmer && _supportedProductsAcknowledged,
    );
    if (!mounted) return;
    if (profileError != null) {
      setState(() => _loading = false);
      _showMessage(profileError);
      return;
    }

    if (_isFarmer) {
      final certUrl = await _cloudinaryService.uploadImage(
        _certFile!,
        folder: 'agritrade/certificates',
      );
      if (!mounted) return;
      if (certUrl == null) {
        setState(() => _loading = false);
        _showMessage('Certificate upload failed. Please try again.');
        return;
      }
      final docError = await _authService.saveVerificationDocument(
        uid: widget.uid,
        documentUrl: certUrl,
        barangay: _selectedBarangay!,
        fullName: _fullName,
      );
      if (!mounted) return;
      if (docError != null) {
        setState(() => _loading = false);
        _showMessage(docError);
        return;
      }
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
                'Supported Products in AgriTrade+',
                style: AppTheme.body(
                  color: AppColors.brand,
                  size: 13.5,
                ).copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'AgriTrade+ currently supports selected agricultural commodities based on '
            'the products identified with the agricultural office. Only supported '
            'products can be posted in the marketplace.',
            style: AppTheme.body(
              color: AppColors.text,
              size: 12.5,
            ).copyWith(height: 1.4),
          ),
          const SizedBox(height: 6),
          Text(
            'Please review the supported products before continuing.',
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
              child: const Text(
                'View Supported Products',
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
                  activeColor: AppColors.brandFill,
                  visualDensity: VisualDensity.compact,
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      'I understand that AgriTrade+ currently supports only selected '
                      'agricultural commodities and that I can only post products '
                      'included in the Supported Products list.',
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
            const Padding(
              padding: EdgeInsets.only(left: 12),
              child: Text(
                'Please confirm you understand the supported products scope.',
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
              activeColor: AppColors.brandFill,
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
                          const TextSpan(text: 'I agree to the '),
                          TextSpan(
                            text: 'Terms & Conditions',
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
                          const TextSpan(text: ' and '),
                          TextSpan(
                            text: 'Privacy Policy',
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
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text(
                          'Please accept the Terms & Conditions and Privacy Policy to continue.',
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
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          textCapitalization: TextCapitalization.words,
          onChanged: (_) => setState(() {}),
          decoration: AppTheme.inputBox(hint: hint, icon: Icons.person_outline),
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
                  error,
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

  @override
  Widget build(BuildContext context) {
    final canSubmit = _isFormValid && !_loading;

    return Scaffold(
      backgroundColor: AppColors.page,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 12),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    border: AppColors.cardBorder,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Center(child: AgriTradeText(fontSize: 26)),
                      const SizedBox(height: 6),
                      Center(
                        child: Text(
                          'One last step',
                          style: AppTheme.heading(20),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Center(
                        child: Text(
                          'Logged in as ${widget.email}',
                          style: AppTheme.body(
                            color: AppColors.textSecondary,
                            size: 12.5,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      _nameField(
                        label: tr(context).firstName,
                        controller: _firstNameController,
                        hint: 'Juan',
                        error: _firstNameError,
                      ),
                      const SizedBox(height: 14),
                      _nameField(
                        label: tr(context).lastName,
                        controller: _lastNameController,
                        hint: 'Santos',
                        error: _lastNameError,
                      ),
                      const SizedBox(height: 16),

                      OutlinedButton.icon(
                        onPressed: _loading ? null : _pickProfilePhoto,
                        icon: const Icon(Icons.photo_camera_outlined),
                        label: Text(
                          _profilePhoto != null || _useGooglePhoto
                              ? 'Change profile photo'
                              : 'Add a profile photo',
                        ),
                      ),
                      if (_profilePhoto != null || _useGooglePhoto) ...[
                        const SizedBox(height: 8),
                        Center(
                          child: CircleAvatar(
                            radius: 38,
                            backgroundImage: _profilePhoto != null
                                ? MemoryImage(_profilePhotoBytes!)
                                : NetworkImage(widget.initialPhotoUrl!)
                                      as ImageProvider,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),

                      // ---- Mobile Number ----
                      // Required for both roles (order/delivery/pick-up
                      // coordination). Fixed +63 prefix — no country
                      // dropdown, PH-only scope.
                      Text('Mobile Number', style: AppTheme.label()),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _mobileController,
                        keyboardType: TextInputType.phone,
                        inputFormatters: kPhMobileInputFormatters,
                        decoration: AppTheme.inputBox(
                          hint: kPhMobileHint,
                          icon: Icons.phone_outlined,
                          prefixText: kPhMobilePrefix,
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
                          'For order, delivery, and pick-up coordination only.',
                          style: TextStyle(
                            color: AppColors.grey(600),
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),

                      Text('Choose your role', style: AppTheme.label()),
                      const SizedBox(height: 8),
                      RoleToggle(
                        selected: _selectedRole,
                        onChanged: _selectRole,
                      ),

                      if (_isFarmer) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
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
                                  'Only verified farmers from Laurel, Batangas will be approved.',
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
                      ],
                      const SizedBox(height: 14),
                      if (_isFarmer) _supportedProductsSection(),
                      if (_isFarmer)
                        BarangayLocationField(
                          value: _selectedBarangay,
                          errorText: _triedSubmit && _selectedBarangay == null
                              ? 'Please select a barangay in Laurel.'
                              : null,
                          onChanged: (value) =>
                              setState(() => _selectedBarangay = value),
                        ),
                      if (_isFarmer) _publicLocationPreview(),
                      if (_isFarmer) ...[
                        Text(
                          'Agricultural Certification',
                          style: AppTheme.label(),
                        ),
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap: _loading ? null : _pickCertificate,
                          child: Container(
                            width: double.infinity,
                            height: 160,
                            decoration: BoxDecoration(
                              color: AppColors.accent.withValues(alpha: 0.20),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: _triedSubmit && _certFile == null
                                    ? Colors.red
                                    : AppColors.mid,
                                width: 1.2,
                              ),
                            ),
                            child: _certBytes == null
                                ? Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.upload_file,
                                        size: 38,
                                        color: AppColors.mid,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Attach your certificate',
                                        style: AppTheme.body(size: 13),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'PNG or JPG only, up to 5MB',
                                        style: AppTheme.body(
                                          color: AppColors.textMuted,
                                          size: 11.5,
                                        ),
                                      ),
                                    ],
                                  )
                                : Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(14),
                                        child: Image.memory(
                                          _certBytes!,
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                      Positioned(
                                        top: 8,
                                        right: 8,
                                        child: Material(
                                          color: AppColors.textSecondary,
                                          shape: const CircleBorder(),
                                          child: IconButton(
                                            icon: const Icon(
                                              Icons.close,
                                              color: Colors.white,
                                              size: 20,
                                            ),
                                            onPressed: _loading
                                                ? null
                                                : _removeCertificate,
                                            tooltip: 'Remove',
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                        if (_triedSubmit && _certFile == null) ...[
                          const SizedBox(height: 6),
                          const Text(
                            'Agricultural certification is required.',
                            style: TextStyle(color: Colors.red, fontSize: 11.5),
                          ),
                        ],
                      ],
                      _consentCheckbox(),
                    ],
                  ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
              decoration: BoxDecoration(
                color: AppColors.page,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 12,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: canSubmit
                          ? _finish
                          : (_loading ? null : _finish),
                      style: AppTheme.primaryButton(),
                      child: _loading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              'Finish Sign Up',
                              style: AppTheme.buttonText(),
                            ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: _loading ? null : _cancel,
                    child: Text(
                      'Cancel',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
