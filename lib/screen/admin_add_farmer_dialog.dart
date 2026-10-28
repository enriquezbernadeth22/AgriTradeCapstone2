import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/laurel_barangays.dart';
import '../data/legal_policies.dart';
import '../services/admin_device_location.dart';
import '../services/person_name.dart';
import '../services/ph_mobile.dart';
import '../services/rsba_number.dart';
import '../widgets/password_requirements.dart';
import 'admin_dashboard_screen.dart' show AdminPalette;
import 'admin_field.dart';
import 'admin_filter_controls.dart'
    show AdminGreyMenu, AdminInputGlow, adminFieldDecoration;
import 'policy_document_screen.dart';

/// User Accounts → Farmers → Add Farmer: the agricultural office adds a
/// farmer it has verified in person, with everything registration asks
/// for. The adminCreateFarmer function (functions/admin_create_farmer.js)
/// checks the same details again and emails the farmer to confirm it is
/// them; the dialog waits, and the account is created — already approved —
/// only when the farmer taps "Yes, it's me" in that email. The Admin sets
/// the first password — by the app's password rules, or generated — and
/// gives it to the farmer; it is shown here and is never emailed. Once
/// confirmed, the farmer is emailed that the account is ready (with a link
/// to change the password) and verifies their email when they first log in
/// to the app.
///
/// Returns true when the account was added while the dialog was open.
Future<bool> showAddFarmerDialog(
  BuildContext context, {
  AddFarmerBackend? backend,
}) async {
  final added = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _AddFarmerDialog(backend: backend ?? AddFarmerBackend()),
  );
  return added == true;
}

/// What Add Farmer talks to: the functions and the invite they keep in
/// farmerInvites/{inviteId} — or stand-ins, in tests.
class AddFarmerBackend {
  /// Asks the farmer to confirm; the invite's id.
  final Future<String> Function(Map<String, Object?> details) sendInvite;

  /// The invite's status as it changes: "pending", then "confirmed",
  /// "declined", "cancelled" or "expired".
  final Stream<String> Function(String inviteId) watchInvite;

  final Future<void> Function(String inviteId) cancelInvite;

  AddFarmerBackend({
    Future<String> Function(Map<String, Object?> details)? sendInvite,
    Stream<String> Function(String inviteId)? watchInvite,
    Future<void> Function(String inviteId)? cancelInvite,
  }) : sendInvite = sendInvite ?? _sendInvite,
       watchInvite = watchInvite ?? _watchInvite,
       cancelInvite = cancelInvite ?? _cancelInvite;

  static HttpsCallable _callable(String name) => FirebaseFunctions.instanceFor(
    region: 'asia-southeast1',
  ).httpsCallable(name);

  static Future<String> _sendInvite(Map<String, Object?> details) async {
    final result = await _callable(
      'adminCreateFarmer',
    ).call<Map<String, dynamic>>(details);
    return result.data['inviteId'] as String;
  }

  static Stream<String> _watchInvite(String inviteId) => FirebaseFirestore
      .instance
      .collection('farmerInvites')
      .doc(inviteId)
      .snapshots()
      .map((snap) => (snap.data()?['status'] as String?) ?? 'pending');

  static Future<void> _cancelInvite(String inviteId) =>
      _callable('adminCancelFarmerInvite').call({'inviteId': inviteId});
}

/// The length of a generated password: the app's minimum.
const int kGeneratedPasswordLength = 12;

/// A password the farmer can remember, from their name only: the first and
/// last name ("AnaGo") — or, when that is too long, the first initial and
/// the last name ("JDelaCruz") — then "@" and random digits, exactly
/// [kGeneratedPasswordLength] characters: "AnaGo@482917", "JDelaCruz@47".
/// It meets the app's password rules (an uppercase and a lowercase letter,
/// a number, a symbol); the random digits keep it from being guessed from
/// the name alone. Null until both names are filled in.
String? memorableFarmerPassword({
  required String firstName,
  required String lastName,
  Random? random,
}) {
  // "dela cruz" → "DelaCruz"; letters only.
  String part(String text) => [
    for (final word in text.split(RegExp(r'[^A-Za-z]+')))
      if (word.isNotEmpty)
        '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}',
  ].join();
  final first = part(firstName);
  final last = part(lastName);
  if (first.isEmpty || last.isEmpty) return null;

  // Room for the name: the length, less "@" and at least two digits.
  const room = kGeneratedPasswordLength - 3;
  var name = '$first$last';
  if (name.length > room) name = '${first[0]}$last';
  if (name.length > room) name = name.substring(0, room);

  final rng = random ?? Random.secure();
  final digits = List.generate(
    kGeneratedPasswordLength - 1 - name.length,
    (_) => rng.nextInt(10),
  ).join();
  final password = '$name@$digits';
  if (PasswordRules.meetsAll(password)) return password;
  // A name of one letter case only ("NG"): one lowercase letter in.
  return '${name.substring(0, name.length - 1)}x@$digits';
}

class _AddFarmerDialog extends StatefulWidget {
  final AddFarmerBackend backend;
  const _AddFarmerDialog({required this.backend});

  @override
  State<_AddFarmerDialog> createState() => _AddFarmerDialogState();
}

class _AddFarmerDialogState extends State<_AddFarmerDialog> {
  // First name and Last name, as registration asks for them.
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _email = TextEditingController();
  final _mobile = TextEditingController();
  final _rsba = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  String? _barangay;
  bool _consent = false;
  bool _showPassword = false;

  bool _submitted = false;
  bool _saving = false;
  String? _serverError;

  // Why Generate could not make a password yet.
  String? _generateNote;

  // The Terms of Service and Privacy Policy links in the agreement line.
  late final _termsLink = TapGestureRecognizer()
    ..onTap = () => showPolicyDocumentDialog(context, kTermsOfService);
  late final _privacyLink = TapGestureRecognizer()
    ..onTap = () => showPolicyDocumentDialog(context, kPrivacyPolicy);
  static const _linkStyle = TextStyle(
    color: Color(0xFF2E7D32),
    fontWeight: FontWeight.w600,
    decoration: TextDecoration.underline,
  );

  /// Set once the farmer has been emailed: the login to hand them, and the
  /// invite being waited on.
  _Sent? _sent;

  /// The invite's status while [_sent]: "pending" until the farmer answers.
  String _status = 'pending';
  StreamSubscription<String>? _watch;
  String? _watchError;
  bool _cancelling = false;

  @override
  void dispose() {
    _watch?.cancel();
    _termsLink.dispose();
    _privacyLink.dispose();
    for (final controller in [
      _firstName,
      _lastName,
      _email,
      _mobile,
      _rsba,
      _password,
      _confirm,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  // The 10 digits after +63 (the field keeps only those).
  String get _mobileDigits => phMobileLocalDigits(_mobile.text);

  String? get _firstNameError =>
      nameFieldError(_firstName.text, label: 'First name', submitted: true);

  String? get _lastNameError =>
      nameFieldError(_lastName.text, label: 'Last name', submitted: true);

  String? get _emailError =>
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(_email.text.trim())
      ? null
      : 'Enter a valid email address.';

  String? get _mobileError => RegExp(r'^9\d{9}$').hasMatch(_mobileDigits)
      ? null
      : 'Enter a valid mobile number (9XX XXX XXXX).';

  String? get _barangayError =>
      _barangay == null ? "Choose the farmer's barangay." : null;

  String? get _rsbaError => isValidRsba(_rsba.text)
      ? null
      : 'Enter the RSBSA number ($kRsbaMinLength–$kRsbaMaxLength letters or '
            'digits).';

  String? get _passwordError => PasswordRules.meetsAll(_password.text)
      ? null
      : 'The password needs ${PasswordRules.minLength}+ characters, with an '
            'uppercase letter, a lowercase letter, a number and a symbol.';

  String? get _confirmError =>
      _confirm.text == _password.text ? null : 'The passwords do not match.';

  String? get _consentError => _consent
      ? null
      : 'Confirm that the farmer agreed to the Terms of Service and Privacy '
            'Policy.';

  bool get _valid => [
    _firstNameError,
    _lastNameError,
    _emailError,
    _mobileError,
    _barangayError,
    _rsbaError,
    _passwordError,
    _confirmError,
    _consentError,
  ].every((e) => e == null);

  // From the farmer's first and last name (memorableFarmerPassword).
  void _generate() {
    final password = memorableFarmerPassword(
      firstName: _firstName.text,
      lastName: _lastName.text,
    );
    setState(() {
      _serverError = null;
      if (password == null) {
        _generateNote =
            'Fill in the First name and Last name first: the password is '
            'made from them.';
        return;
      }
      _generateNote = null;
      _password.text = password;
      _confirm.text = password;
      // Shown, so it can be written down or copied for the farmer.
      _showPassword = true;
    });
  }

  Future<void> _save() async {
    setState(() {
      _submitted = true;
      _serverError = null;
    });
    if (!_valid || _saving) return;
    setState(() => _saving = true);
    final firstName = tidyName(_firstName.text);
    final lastName = tidyName(_lastName.text);
    final email = _email.text.trim().toLowerCase();
    final password = _password.text;
    try {
      final inviteId = await widget.backend.sendInvite({
        'firstName': firstName,
        'lastName': lastName,
        'email': email,
        'mobileNumber': '+63$_mobileDigits',
        'barangay': _barangay,
        'rsbaNumber': normalizeRsba(_rsba.text),
        'password': password,
        'termsAccepted': _consent,
        'termsVersion': kTermsOfService.version,
        'privacyVersion': kPrivacyPolicy.version,
        'location': ?await AdminDeviceLocation.current(),
      });
      if (!mounted) return;
      setState(() {
        _saving = false;
        _sent = (
          inviteId: inviteId,
          name: joinName(firstName, lastName),
          email: email,
          password: password,
        );
      });
      _watchInvite(inviteId);
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        // The function's own message where it gave one. A function that
        // is not deployed (or no connection) reaches the browser as a bare
        // "internal" error, and the two cannot be told apart.
        final message = e.message?.trim() ?? '';
        final ownMessage =
            message.isNotEmpty && message.toLowerCase() != 'internal';
        _serverError = switch (e.code) {
          'not-found' || 'unimplemented' =>
            'Adding farmers is not available yet: the adminCreateFarmer '
                'function has not been deployed.',
          _ when ownMessage => message,
          _ =>
            'Could not reach the Add Farmer service. Check your connection. '
                'If this keeps happening, the adminCreateFarmer function may '
                'not be deployed yet.',
        };
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _serverError =
            'Could not add the farmer. Check your connection and try again.';
      });
    }
  }

  // Waits for the farmer's answer to the email.
  void _watchInvite(String inviteId) {
    _watch?.cancel();
    _watch = widget.backend
        .watchInvite(inviteId)
        .listen(
          (status) {
            if (!mounted) return;
            setState(() {
              _status = status;
              _watchError = null;
            });
            // Nothing more to wait for.
            if (status != 'pending') _watch?.cancel();
          },
          onError: (_) {
            if (!mounted) return;
            setState(
              () => _watchError =
                  "Could not check for the farmer's answer here. The account "
                  'is still added once they confirm: look for it in User '
                  'Accounts.',
            );
          },
        );
  }

  // Cancel request: the email's link stops working and nothing is added.
  Future<void> _cancelInvite(String inviteId) async {
    setState(() => _cancelling = true);
    try {
      await widget.backend.cancelInvite(inviteId);
      if (mounted) Navigator.of(context).pop(false);
    } catch (_) {
      if (!mounted) return;
      setState(() => _cancelling = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not cancel the request. Try again.'),
        ),
      );
    }
  }

  // A field's error once the form has been submitted.
  String? _shown(String? error) => _submitted ? error : null;

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 6, top: 12),
    child: Text(
      text,
      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
    ),
  );

  Widget _error(String? text) => text == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(left: 6, top: 4),
          child: Text(
            text,
            style: TextStyle(color: Colors.red.shade700, fontSize: 12),
          ),
        );

  Widget _eye() => IconButton(
    tooltip: _showPassword ? 'Hide password' : 'Show password',
    icon: Icon(
      _showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
      size: 19,
    ),
    onPressed: () => setState(() => _showPassword = !_showPassword),
  );

  @override
  Widget build(BuildContext context) {
    final sent = _sent;
    if (sent != null) return _sentView(context, sent);

    void changed(_) {
      if (_submitted || _serverError != null) {
        setState(() => _serverError = null);
      }
    }

    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return AlertDialog(
      title: const Text('Add Farmer'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'For a farmer the office has verified in person. The farmer '
                'is first emailed to confirm it is them ("Yes, it\'s me"); '
                'the account is added, already approved, once they do. Give '
                'the farmer the password you set.',
                style: TextStyle(fontSize: 12.5, color: muted, height: 1.4),
              ),
              // First name and Last name side by side.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _label('First name'),
                        AdminField(
                          controller: _firstName,
                          icon: Icons.person_outline,
                          autofocus: true,
                          decoration: const InputDecoration(
                            hintText: 'e.g. Juan',
                          ),
                          onChanged: changed,
                        ),
                        _error(_shown(_firstNameError)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _label('Last name'),
                        AdminField(
                          controller: _lastName,
                          decoration: const InputDecoration(
                            hintText: 'e.g. Dela Cruz',
                          ),
                          onChanged: changed,
                        ),
                        _error(_shown(_lastNameError)),
                      ],
                    ),
                  ),
                ],
              ),
              _label('Email address'),
              AdminField(
                controller: _email,
                icon: Icons.mail_outline,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  hintText: 'The farmer logs in with this',
                ),
                onChanged: changed,
              ),
              _error(_shown(_emailError)),
              _label('Mobile number'),
              AdminField(
                controller: _mobile,
                icon: Icons.phone_outlined,
                keyboardType: TextInputType.phone,
                // At most the 10 digits after +63, as in registration; a
                // number pasted as 09… or +639… is reduced to them.
                inputFormatters: kPhMobileInputFormatters,
                decoration: const InputDecoration(
                  prefixText: kPhMobilePrefix,
                  hintText: kPhMobileHint,
                ),
                onChanged: changed,
              ),
              _error(_shown(_mobileError)),
              _label('Barangay (Laurel, Batangas)'),
              // On the same plate as the fields around it (the Admin
              // login's look).
              AdminInputGlow(
                child: AdminGreyMenu(
                  child: DropdownButtonFormField<String>(
                    initialValue: _barangay,
                    isExpanded: true,
                    hint: const Text('Choose a barangay'),
                    borderRadius: BorderRadius.circular(16),
                    decoration: adminFieldDecoration(
                      AdminPalette.fallback(context),
                      icon: Icons.location_on_outlined,
                    ),
                    items: [
                      for (final name in kLaurelBarangays)
                        DropdownMenuItem(value: name, child: Text(name)),
                    ],
                    onChanged: (value) => setState(() {
                      _barangay = value;
                      _serverError = null;
                    }),
                  ),
                ),
              ),
              _error(_shown(_barangayError)),
              _label('RSBSA number'),
              AdminField(
                controller: _rsba,
                icon: Icons.badge_outlined,
                maxLength: kRsbaMaxLength,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                ],
                decoration: const InputDecoration(
                  hintText: 'Registry System for Basic Sectors in Agriculture',
                ),
                onChanged: changed,
              ),
              _error(_shown(_rsbaError)),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(child: _label('Password')),
                  Tooltip(
                    message:
                        'From the farmer\'s name, 12 characters, e.g. '
                        'JDelaCruz@47 or AnaGo@482917',
                    child: TextButton.icon(
                      onPressed: _generate,
                      icon: const Icon(Icons.auto_fix_high_outlined, size: 16),
                      label: const Text('Generate'),
                    ),
                  ),
                ],
              ),
              if (_generateNote != null)
                Padding(
                  padding: const EdgeInsets.only(left: 6, bottom: 6),
                  child: Text(
                    _generateNote!,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.orange.shade800,
                    ),
                  ),
                ),
              AdminField(
                controller: _password,
                icon: Icons.lock_outline,
                obscureText: !_showPassword,
                decoration: InputDecoration(
                  hintText: 'At least ${PasswordRules.minLength} characters',
                  suffixIcon: _eye(),
                ),
                onChanged: (v) => setState(() => _serverError = null),
              ),
              const SizedBox(height: 8),
              PasswordRequirementsChecklist(
                password: _password.text,
                bottomSpacing: 0,
              ),
              _error(_shown(_passwordError)),
              _label('Confirm password'),
              AdminField(
                controller: _confirm,
                icon: Icons.lock_outline,
                obscureText: !_showPassword,
                decoration: InputDecoration(
                  hintText: 'Type the password again',
                  suffixIcon: _eye(),
                ),
                onChanged: changed,
              ),
              _error(_shown(_confirmError)),
              const SizedBox(height: 10),
              CheckboxListTile(
                value: _consent,
                onChanged: (value) => setState(() {
                  _consent = value ?? false;
                  _serverError = null;
                }),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
                // The two policies open, to read, from their names — the
                // same text as on the mobile app's registration.
                title: Text.rich(
                  TextSpan(
                    style: const TextStyle(fontSize: 12.5),
                    children: [
                      const TextSpan(
                        text: 'The farmer has agreed to the AgriTrade+ ',
                      ),
                      TextSpan(
                        text: 'Terms of Service',
                        style: _linkStyle,
                        recognizer: _termsLink,
                      ),
                      const TextSpan(text: ' and '),
                      TextSpan(
                        text: 'Privacy Policy',
                        style: _linkStyle,
                        recognizer: _privacyLink,
                      ),
                      const TextSpan(text: '.'),
                    ],
                  ),
                ),
              ),
              _error(_shown(_consentError)),
              if (_serverError != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.red.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    _serverError!,
                    style: TextStyle(
                      color: Colors.red.shade800,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Send confirmation'),
        ),
      ],
    );
  }

  Widget _loginRow(BuildContext context, String label, String value) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label, style: TextStyle(fontSize: 12.5, color: muted)),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _copyLogin(BuildContext context, _Sent sent) => TextButton.icon(
    onPressed: () {
      Clipboard.setData(
        ClipboardData(text: 'Email: ${sent.email}\nPassword: ${sent.password}'),
      );
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Login copied.')));
    },
    icon: const Icon(Icons.copy_rounded, size: 16),
    label: const Text('Copy login'),
  );

  // Emailed: waiting for the farmer's "Yes, it's me" — then the login to
  // hand them, or why nothing was added.
  Widget _sentView(BuildContext context, _Sent sent) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final note = TextStyle(fontSize: 12.5, color: muted, height: 1.4);
    final login = [
      _loginRow(context, 'Email', sent.email),
      _loginRow(context, 'Password', sent.password),
    ];

    switch (_status) {
      case 'confirmed':
        return AlertDialog(
          title: const Text('Farmer account added'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.verified_rounded,
                      color: Color(0xFF2E7D32),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${sent.name} confirmed by email. The account is '
                        'added, already approved.',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Give the farmer this login. The password is not emailed '
                  'or kept anywhere.',
                  style: note,
                ),
                const SizedBox(height: 14),
                ...login,
                const SizedBox(height: 4),
                Text(
                  'An email telling the farmer the account is ready was sent '
                  'to ${sent.email}, with a link to change the password.',
                  style: TextStyle(fontSize: 12, color: muted, height: 1.4),
                ),
              ],
            ),
          ),
          actions: [
            _copyLogin(context, sent),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Done'),
            ),
          ],
        );
      case 'declined' || 'cancelled' || 'expired':
        final message = switch (_status) {
          'declined' =>
            '${sent.name} answered "No, it\'s not me" in the email, so no '
                'account was added. Check the email address with the farmer.',
          'cancelled' => 'The request was cancelled, so no account was added.',
          _ =>
            'The farmer did not confirm within 24 hours, so no account was '
                'added. Add them again to send a new email.',
        };
        return AlertDialog(
          title: const Text('Farmer not added'),
          content: SizedBox(width: 440, child: Text(message, style: note)),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Close'),
            ),
          ],
        );
    }

    // Still waiting.
    return AlertDialog(
      title: const Text('Waiting for the farmer'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Waiting for ${sent.name} to confirm…',
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              'A confirmation email was sent to ${sent.email}. The account '
              'is added only when the farmer opens it and taps "Yes, it\'s '
              'me". The link works for 24 hours.',
              style: note,
            ),
            const SizedBox(height: 14),
            Text(
              'The login to give the farmer once they confirm:',
              style: note,
            ),
            const SizedBox(height: 8),
            ...login,
            if (_watchError != null) ...[
              const SizedBox(height: 6),
              Text(
                _watchError!,
                style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
              ),
            ],
            const SizedBox(height: 4),
            Text(
              'You can close this: the account is still added when the '
              'farmer confirms.',
              style: TextStyle(fontSize: 12, color: muted, height: 1.4),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _cancelling ? null : () => _cancelInvite(sent.inviteId),
          style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
          child: const Text('Cancel request'),
        ),
        _copyLogin(context, sent),
        OutlinedButton(
          onPressed: _cancelling
              ? null
              : () => Navigator.of(context).pop(false),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

/// The farmer emailed to confirm, and the login to hand them.
typedef _Sent = ({String inviteId, String name, String email, String password});
