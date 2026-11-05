import '../widgets/agri_app_bar.dart';
import '../widgets/app_scaffold_messenger.dart';
import '../widgets/recovery_email_code_dialog.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import '../widgets/agri_dialog.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../services/auth_service.dart';
import '../services/cloudinary_service.dart';
import '../services/geocoding_service.dart';
import '../services/ph_mobile.dart';
import '../widgets/buyer_location_picker.dart';
import 'set_farm_location_screen.dart';
import '../l10n/tr.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../l10n/app_language.dart';
import '../data/account_types.dart';
import '../widgets/registration_role_details.dart';
import '../widgets/glow_field.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _recoveryEmailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _locationController = TextEditingController();

  final ImagePicker _imagePicker = ImagePicker();
  final CloudinaryService _cloudinaryService = CloudinaryService();

  XFile? _pickedPhoto;
  String? _photoUrl;
  String? _role;
  // "What best describes you" (see account_types.dart).
  String? _accountType;
  double? _latitude;
  double? _longitude;
  // A buyer's saved region/province/city/barangay, for reopening the
  // location popup where they left off.
  BuyerLocationResult? _buyerLocation;

  bool _loading = false;

  // What the save is doing now, shown on the card over the page.
  String _savingStep = '';
  bool _savingLocation = false;
  bool _initialLoading = true;
  bool _recoveryEmailVerified = false;
  // The recovery email as saved on the account (what Verified is about).
  String _savedRecoveryEmail = '';
  bool _verifyingRecovery = false;

  User? get _user => FirebaseAuth.instance.currentUser;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final user = _user;
    _nameController.text = user?.displayName ?? '';
    _emailController.text = user?.email ?? '';

    if (user != null) {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final data = doc.data();
      // Exact coordinates live under users/{uid}/private/geo, not on the
      // main doc just read above — only this account (the owner) or an
      // admin can read it (see firestore.rules).
      final geoDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('private')
          .doc('geo')
          .get();
      final geo = geoDoc.data();
      _latitude = (geo?['latitude'] as num?)?.toDouble();
      _longitude = (geo?['longitude'] as num?)?.toDouble();
      if (data != null) {
        // Registration saves 'mobileNumber'; this screen used to save
        // 'phone'. Either is read, in whatever format it was stored, and
        // shown as the 10 digits after +63.
        _phoneController.text = phMobileLocalDigits(
          (data['mobileNumber'] ?? data['phone'])?.toString(),
        );
        // A recovery email is a second address: empty until the user adds
        // one (never pre-filled with the login email), and Verified only
        // once its code has been entered.
        final storedRecovery = (data['recoveryEmail'] ?? '').toString().trim();
        _recoveryEmailController.text = _sameAsLogin(storedRecovery)
            ? ''
            : storedRecovery;
        _savedRecoveryEmail = _recoveryEmailController.text;
        _recoveryEmailVerified =
            _savedRecoveryEmail.isNotEmpty &&
            data['recoveryEmailVerified'] == true;
        _recoveryEmailController.addListener(() => setState(() {}));
        _photoUrl = data['photoUrl']?.toString();
        _role = data['role']?.toString();
        _accountType = accountTypeOf(data);
        // Combine barangay/municipality/province into one display string,
        // matching how ProfileTab shows location. Adjust field names here
        // if your schema differs.
        final barangay = data['barangay']?.toString();
        final muni = data['municipality']?.toString() ?? '';
        final prov = data['province']?.toString() ?? '';
        _locationController.text = (barangay != null && barangay.isNotEmpty)
            ? '$barangay, $muni, $prov'
            : [muni, prov].where((s) => s.isNotEmpty).join(', ');
        final region = data['region']?.toString() ?? '';
        if (barangay != null &&
            barangay.isNotEmpty &&
            muni.isNotEmpty &&
            prov.isNotEmpty) {
          _buyerLocation = BuyerLocationResult(
            region: region.isNotEmpty ? region : prov,
            province: prov,
            city: muni,
            barangay: barangay,
          );
        }
      }
    }

    if (!mounted) return;
    setState(() => _initialLoading = false);
    _lookUpPinPlace();
  }

  // The place the farm pin is actually in (barangay, town, province),
  // looked up from its coordinates. Until it is known — or if the lookup
  // fails — the registered location stands in.
  String? _pinPlace;

  Future<void> _lookUpPinPlace() async {
    final lat = _latitude, lng = _longitude;
    // Only farmers have the Farm Location box.
    if (lat == null || lng == null || _role != 'farmer') return;
    final address = await GeocodingService.reverseGeocode(lat, lng);
    if (!mounted || lat != _latitude || lng != _longitude) return;
    final place = address?.readable.trim() ?? '';
    setState(() => _pinPlace = place.isEmpty ? null : place);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _recoveryEmailController.dispose();
    _phoneController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final phoneDigits = _phoneController.text.trim();
    // Always stored as +639XXXXXXXXX.
    final phone = phMobileE164(phoneDigits);
    final location = _locationController.text.trim();
    final recoveryEmail = _recoveryEmailController.text.trim();

    // Required, like at registration — it is what Place Order starts from.
    if (phoneDigits.isEmpty) {
      _showMessage(tl('Mobile number is required.'));
      return;
    }
    if (!isValidPhMobile(phoneDigits)) {
      _showMessage(kPhMobileInvalidMessage);
      return;
    }
    if (name.isEmpty) {
      _showMessage(tl('Please enter your full name.'));
      return;
    }
    if (recoveryEmail.isNotEmpty &&
        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(recoveryEmail)) {
      _showMessage(tl('Please enter a valid recovery email.'));
      return;
    }
    if (_sameAsLogin(recoveryEmail)) {
      _showMessage(_sameAsLoginMessage);
      return;
    }

    setState(() {
      _loading = true;
      _savingStep = _pickedPhoto != null
          ? tl('Uploading your photo…')
          : tl('Saving your changes…');
    });
    try {
      final user = _user;
      if (user != null) {
        final Map<String, dynamic> updateData = {
          'name': name,
          'fullName': name,
          // Both names, so every reader sees the same number: 'mobileNumber'
          // (Registration, Place Order) and 'phone' (the admin views).
          'phone': phone,
          'mobileNumber': phone,
          if (_role != null && _accountType != null)
            accountTypeField(_role!): _accountType,
          'location': location, // simple combined string; split into
          // barangay/municipality/province fields instead if your
          // schema needs them separately.
          // An emptied recovery email field removes the saved one.
          if (_recoveryRemoved) ...{
            'recoveryEmail': FieldValue.delete(),
            'recoveryEmailVerified': FieldValue.delete(),
            'recoveryEmailVerifiedAt': FieldValue.delete(),
          },
        };

        if (_pickedPhoto != null) {
          final uploadedUrl = await _cloudinaryService.uploadImage(
            _pickedPhoto!,
          );
          if (uploadedUrl == null || uploadedUrl.isEmpty) {
            throw Exception('Could not upload profile photo.');
          }
          updateData['photoUrl'] = uploadedUrl;
          _photoUrl = uploadedUrl;
          await user.updatePhotoURL(uploadedUrl);
        }

        if (mounted) setState(() => _savingStep = tl('Saving your changes…'));
        if (user.displayName != name) {
          await user.updateDisplayName(name);
        }

        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .set(updateData, SetOptions(merge: true));
      }
      if (!mounted) return;
      // A new recovery email is saved — and verified — by entering the code
      // emailed to it (never by changing the sign-in email).
      if (_recoveryChanged) {
        setState(() => _loading = false);
        await _verifyRecovery();
        if (!mounted) return;
      } else {
        if (_recoveryRemoved) {
          _savedRecoveryEmail = '';
          _recoveryEmailVerified = false;
        }
        _showMessage(tl('Profile updated!'), kind: MessageKind.success);
      }
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      _showMessage(tl('Could not save changes. Please try again.'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // A saved recovery email whose field was emptied.
  bool get _recoveryRemoved =>
      _savedRecoveryEmail.isNotEmpty &&
      _recoveryEmailController.text.trim().isEmpty;

  bool get _recoveryChanged {
    final typed = _recoveryEmailController.text.trim();
    return typed.isNotEmpty &&
        typed.toLowerCase() != _savedRecoveryEmail.toLowerCase();
  }

  // A recovery email of its own is in the field (not empty, not the
  // login email) — only then is there a status to show.
  bool get _hasOwnRecoveryEmail {
    final typed = _recoveryEmailController.text.trim();
    return typed.isNotEmpty && !_sameAsLogin(typed);
  }

  static const String _sameAsLoginMessage =
      'Use a different email from the one you log in with.';

  // The login email cannot be its own recovery email.
  bool _sameAsLogin(String email) {
    final login = (_user?.email ?? '').trim().toLowerCase();
    return email.isNotEmpty && email.trim().toLowerCase() == login;
  }

  // Emails a code to the recovery email in the field and asks for it.
  Future<void> _verifyRecovery() async {
    final email = _recoveryEmailController.text.trim();
    if (email.isEmpty || _verifyingRecovery) return;
    setState(() => _verifyingRecovery = true);
    final verified = await verifyRecoveryEmail(context, email);
    if (!mounted) return;
    setState(() {
      _verifyingRecovery = false;
      // Requesting the code saved the address, verified or not.
      _savedRecoveryEmail = email;
      _recoveryEmailVerified = verified;
    });
  }

  // Unless said otherwise, a message here is a problem with the form.
  void _showMessage(String message, {MessageKind kind = MessageKind.error}) {
    showAppMessage(context, tl(message), kind: kind);
  }

  Future<ImageSource?> _showImageSourceSheet() async {
    return showAgriSheet<ImageSource>(
      context: context,
      title: tl('Choose Photo'),
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AgriSheetAction(
            icon: Icons.photo_camera_outlined,
            label: tl('Take Photo'),
            onTap: () => Navigator.pop(context, ImageSource.camera),
          ),
          AgriSheetAction(
            icon: Icons.photo_library_outlined,
            label: tl('Choose from Gallery'),
            onTap: () => Navigator.pop(context, ImageSource.gallery),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Future<void> _pickProfilePhoto() async {
    final source = await _showImageSourceSheet();
    if (source == null) return;

    final picked = await _imagePicker.pickImage(
      source: source,
      maxWidth: 1000,
      imageQuality: 70,
    );
    if (picked == null || !mounted) return;

    setState(() => _pickedPhoto = picked);
  }

  void showComingSoon(String feature) =>
      _showMessage(tl('{0} — coming soon.', [feature]), kind: MessageKind.info);

  // The buyer's location: the same popup as Place Order and Delivery &
  // Pickup, saved the same way — the readable area on the profile, the
  // coordinates (when there are any) only under private/geo.
  Future<void> _editBuyerLocation([BuildContext? fieldContext]) async {
    final user = _user;
    if (user == null || _savingLocation) return;
    FocusManager.instance.primaryFocus?.unfocus();
    // The choices open right under the Location field.
    final picked = await showBuyerLocationOptions(
      context,
      initial: _buyerLocation,
      anchorContext: fieldContext,
    );
    if (picked == null || !mounted) return;

    setState(() => _savingLocation = true);
    final error = await AuthService().saveBuyerLocation(
      uid: user.uid,
      latitude: picked.latitude,
      longitude: picked.longitude,
      region: picked.region,
      province: picked.province,
      city: picked.city,
      barangay: picked.barangay,
    );
    if (!mounted) return;
    setState(() {
      _savingLocation = false;
      if (error == null) {
        _buyerLocation = picked;
        _locationController.text = picked.readable;
      }
    });
    _showMessage(
      error ?? tl('Location updated.'),
      kind: error == null ? MessageKind.success : MessageKind.error,
    );
  }

  Future<void> _openLocationPicker() async {
    final picked = await Navigator.push<LatLng>(
      context,
      MaterialPageRoute(
        builder: (_) => SetFarmLocationScreen(
          initialLat: _latitude,
          initialLng: _longitude,
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _latitude = picked.latitude;
      _longitude = picked.longitude;
      _pinPlace = null;
    });
    _lookUpPinPlace();
    _showMessage(tl('Farm location saved!'), kind: MessageKind.success);
  }

  Widget _farmLocationSection() {
    final hasLocation = _latitude != null && _longitude != null;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.softTint,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.softTintBorder, width: 1.2),
      ),
      child: Row(
        children: [
          Icon(
            hasLocation ? Icons.location_on : Icons.location_off_outlined,
            color: AppColors.brand,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tl('Farm Location'),
                  style: GoogleFonts.montserrat(
                    fontWeight: FontWeight.bold,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 2),
                // The place the pin is in (barangay, town, province), not
                // its coordinates; the registered location until known.
                Text(
                  hasLocation
                      ? (_pinPlace ??
                            (_locationController.text.trim().isNotEmpty
                                ? _locationController.text.trim()
                                : tl('Set on the map')))
                      : tl(
                          'Not pinned yet — buyers and admin can\'t see your farm on the map.',
                        ),
                  style: GoogleFonts.montserrat(
                    fontSize: 11.5,
                    color: AppColors.grey(600),
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _openLocationPicker,
            child: Text(
              hasLocation ? tl('Update') : tl('Set on Map'),
              style: GoogleFonts.montserrat(
                fontWeight: FontWeight.bold,
                fontSize: 12.5,
                color: AppColors.brand,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // The app's form field and label (AppTheme's FORMS section).
  // Each field sits on a FormFieldGlow: the soft green glow while typed
  // in, as on GlowField and the Admin login.
  InputDecoration _fieldDecoration(IconData icon) =>
      AppTheme.formFieldDecoration(icon: icon, onGlowPlate: true);

  // A note or an error on its own line under a field, outside its glow.
  Widget _fieldNote(String text, {bool error = false}) => Padding(
    padding: const EdgeInsets.only(top: 6, left: 4),
    child: Text(
      text,
      style: GoogleFonts.montserrat(
        fontSize: error ? 11 : 11.5,
        color: error ? AppColors.tone(Colors.red, 700) : AppColors.grey(600),
      ),
    ),
  );

  Widget _fieldLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.formLabelGap),
      child: Text(text, style: AppTheme.label()),
    );
  }

  Widget _avatarWithEditBadge() {
    final ImageProvider? imageProvider;
    if (_pickedPhoto != null) {
      imageProvider = FileImage(File(_pickedPhoto!.path));
    } else if (_photoUrl != null && _photoUrl!.isNotEmpty) {
      imageProvider = NetworkImage(_photoUrl!);
    } else {
      imageProvider = null;
    }

    return Column(
      children: [
        GestureDetector(
          onTap: _pickProfilePhoto,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(
                radius: 46,
                backgroundColor: AppColors.accent,
                backgroundImage: imageProvider,
                child: imageProvider == null
                    ? Icon(Icons.person, color: AppColors.brand, size: 52)
                    : null,
              ),
              Positioned(
                bottom: -2,
                right: -2,
                child: GestureDetector(
                  onTap: _pickProfilePhoto,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppColors.brandFill,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(
                      Icons.camera_alt,
                      color: Colors.white,
                      size: 14,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _pickProfilePhoto,
          child: Text(
            tl('Change Photo'),
            style: GoogleFonts.montserrat(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppColors.brand,
            ),
          ),
        ),
      ],
    );
  }

  // While saving: the page dimmed, and a card in the middle with a spinner
  // and what is happening now (uploading the photo, then saving). It also
  // keeps the form from being changed half-way.
  Widget _savingOverlay() => Positioned.fill(
    child: ColoredBox(
      color: Colors.black.withValues(alpha: 0.28),
      child: Center(
        child: Container(
          key: const Key('profileSavingCard'),
          width: 240,
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: AppColors.cardBorder,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 34,
                height: 34,
                child: CircularProgressIndicator(
                  color: AppColors.brand,
                  strokeWidth: 3,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _savingStep,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                tl('Please wait a moment.'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // No leaving half-way through a save.
      canPop: !_loading,
      child: Scaffold(
        backgroundColor: AppColors.page,
        appBar: AgriAppBar(title: tr(context).editProfile),
        body: Stack(children: [_form(), if (_loading) _savingOverlay()]),
      ),
    );
  }

  Widget _form() {
    return _initialLoading
        ? Center(child: CircularProgressIndicator(color: AppColors.brand))
        : SingleChildScrollView(
            // Room between the header and the photo.
            padding: const EdgeInsets.fromLTRB(
              AppTheme.formPageMargin,
              AppTheme.formSectionGap,
              AppTheme.formPageMargin,
              AppTheme.formSectionGap,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _avatarWithEditBadge(),
                const SizedBox(height: 24),

                _fieldLabel(tl('Full Name')),
                FormFieldGlow(
                  child: TextField(
                    controller: _nameController,
                    style: GoogleFonts.montserrat(fontSize: 14),
                    decoration: _fieldDecoration(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: AppTheme.formFieldGap),

                _fieldLabel(tr(context).emailAddress),
                TextField(
                  controller: _emailController,
                  enabled:
                      false, // email changes need re-auth; edit elsewhere if needed
                  style: GoogleFonts.montserrat(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                  decoration: _fieldDecoration(Icons.mail_outline),
                ),
                const SizedBox(height: AppTheme.formFieldGap),

                _fieldLabel(tl('Recovery Email')),
                FormFieldGlow(
                  child: TextField(
                    controller: _recoveryEmailController,
                    keyboardType: TextInputType.emailAddress,
                    style: GoogleFonts.montserrat(fontSize: 14),
                    decoration: _fieldDecoration(Icons.security_outlined)
                        .copyWith(
                          hintText: tl('Add a backup email'),
                          // Verified / Not verified only for a second
                          // address (not the login email): Verified once
                          // its code was entered, a newly typed one not yet.
                          suffixIcon: !_hasOwnRecoveryEmail
                              ? null
                              : Padding(
                                  padding: const EdgeInsets.only(right: 10),
                                  child: RecoveryEmailStatusChip(
                                    verified:
                                        _recoveryEmailVerified &&
                                        !_recoveryChanged,
                                  ),
                                ),
                          suffixIconConstraints: const BoxConstraints(),
                        ),
                  ),
                ),
                if (_sameAsLogin(_recoveryEmailController.text))
                  _fieldNote(tl(_sameAsLoginMessage), error: true)
                else if (_hasOwnRecoveryEmail &&
                    !(_recoveryEmailVerified && !_recoveryChanged))
                  _fieldNote(
                    tl('We will email it a 6-digit code to verify it.'),
                  ),
                // A saved but unverified address can be verified now.
                if (!_recoveryEmailVerified &&
                    !_recoveryChanged &&
                    _hasOwnRecoveryEmail)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _verifyingRecovery ? null : _verifyRecovery,
                      icon: _verifyingRecovery
                          ? SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.brand,
                              ),
                            )
                          : const Icon(
                              Icons.mark_email_read_outlined,
                              size: 16,
                            ),
                      label: Text(tl('Verify now')),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.brand,
                        textStyle: GoogleFonts.montserrat(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: AppTheme.formFieldGap),

                _fieldLabel(tl('Phone Number')),
                FormFieldGlow(
                  child: TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    inputFormatters: kPhMobileInputFormatters,
                    style: GoogleFonts.montserrat(fontSize: 14),
                    // The +63 is fixed, not editable: only the 10 digits
                    // after it are.
                    decoration: AppTheme.formFieldDecoration(
                      icon: Icons.call_outlined,
                      prefixText: kPhMobilePrefix,
                      hint: kPhMobileHint,
                      onGlowPlate: true,
                    ),
                  ),
                ),
                const SizedBox(height: AppTheme.formFieldGap),

                if (_role != null) ...[
                  RegistrationRoleDetails(
                    isFarmer: _role == 'farmer',
                    value: _accountType,
                    onChanged: (value) => setState(() => _accountType = value),
                  ),
                  const SizedBox(height: AppTheme.formFieldGap),
                ],

                _fieldLabel(tl('Location')),
                if (_role == 'buyer')
                  Builder(
                    builder: (fieldContext) => FormFieldGlow(
                      radius: AppTheme.dropdownRadius,
                      child: TextField(
                        controller: _locationController,
                        readOnly: true,
                        onTap: () => _editBuyerLocation(fieldContext),
                        style: GoogleFonts.montserrat(fontSize: 14),
                        decoration:
                            AppTheme.formDropdownDecoration(
                              icon: Icons.location_on_outlined,
                              hint: tl('Tap to set your location'),
                              onGlowPlate: true,
                            ).copyWith(
                              suffixIcon: _savingLocation
                                  ? Padding(
                                      padding: EdgeInsets.all(14),
                                      child: SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: AppColors.brand,
                                        ),
                                      ),
                                    )
                                  : Icon(
                                      Icons.expand_more_rounded,
                                      color: AppTheme.formIconColor,
                                      size: AppTheme.formIconSize,
                                    ),
                            ),
                      ),
                    ),
                  )
                else
                  FormFieldGlow(
                    child: TextField(
                      controller: _locationController,
                      style: GoogleFonts.montserrat(fontSize: 14),
                      decoration: _fieldDecoration(Icons.location_on_outlined),
                    ),
                  ),

                if (_role == 'farmer') ...[
                  const SizedBox(height: AppTheme.formFieldGap),
                  _farmLocationSection(),
                ],
                const SizedBox(height: AppTheme.formSectionGap),

                ElevatedButton(
                  onPressed: _loading ? null : _save,
                  // Stays dark green while saving, so "Saving…" can be read.
                  style: AppTheme.primaryButton().copyWith(
                    backgroundColor: WidgetStatePropertyAll(
                      _loading
                          ? AppColors.brandFill.withValues(alpha: 0.8)
                          : AppColors.brandFill,
                    ),
                  ),
                  child: _loading
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              tl('Saving…'),
                              style: AppTheme.buttonText().copyWith(
                                color: Colors.white,
                              ),
                            ),
                          ],
                        )
                      : Text(
                          tr(context).saveChanges,
                          style: AppTheme.buttonText(),
                        ),
                ),
              ],
            ),
          );
  }
}
