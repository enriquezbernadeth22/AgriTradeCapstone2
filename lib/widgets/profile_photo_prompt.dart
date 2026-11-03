import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'app_scaffold_messenger.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/cloudinary_service.dart';
import 'agri_dialog.dart';
import '../l10n/app_language.dart';

/// What the person chose in [ProfilePhotoDialog].
enum ProfilePhotoChoice { google, upload }

/// Asks someone who registered with Google for a profile photo, once, when
/// they first come into the app. The registration form itself no longer asks,
/// so it stays short.
class ProfilePhotoPrompt {
  const ProfilePhotoPrompt._();

  /// Saved per account, so "Not now" is not asked again on this phone.
  @visibleForTesting
  static String askedKey(String uid) => 'profile_photo_asked_$uid';

  /// Only a Google account that has no photo yet, and only once.
  @visibleForTesting
  static bool shouldAsk({
    required Iterable<String> providers,
    required String? savedPhoto,
    required bool alreadyAsked,
  }) =>
      !alreadyAsked &&
      providers.contains('google.com') &&
      (savedPhoto ?? '').trim().isEmpty;

  /// Asks, if it should, and saves the answer. Never stops the person getting
  /// into the app: on a failure they can still add a photo in Edit Profile.
  static Future<void> onEnteredApp(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = askedKey(user.uid);
      final profile = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid);
      final saved = (await profile.get()).data()?['photoUrl']?.toString();
      final ask = shouldAsk(
        providers: user.providerData.map((info) => info.providerId),
        savedPhoto: saved,
        alreadyAsked: prefs.getBool(key) ?? false,
      );
      if (!ask || !context.mounted) return;

      await prefs.setBool(key, true);
      if (!context.mounted) return;
      final choice = await showAgriDialog<ProfilePhotoChoice>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ProfilePhotoDialog(googlePhotoUrl: user.photoURL),
      );
      if (choice == null) return;

      final url = choice == ProfilePhotoChoice.google
          ? user.photoURL
          : await _uploadPhoto();
      if (url == null || url.isEmpty) return;
      await user.updatePhotoURL(url);
      await profile.update({'photoUrl': url});
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        appSnackBar(
          tl('Could not save your photo. You can add it in Edit Profile.'),
          kind: MessageKind.error,
        ),
      );
    }
  }

  static Future<String?> _uploadPhoto() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1000,
      imageQuality: 75,
    );
    if (picked == null) return null;
    final url = await CloudinaryService().uploadImage(
      picked,
      folder: 'agritrade/profiles',
    );
    if (url == null) throw Exception('Could not upload profile photo.');
    return url;
  }
}

/// "Add a profile photo": the Google photo, when the account has one, or one
/// of the person's own, or not now.
class ProfilePhotoDialog extends StatelessWidget {
  final String? googlePhotoUrl;

  const ProfilePhotoDialog({super.key, this.googlePhotoUrl});

  @override
  Widget build(BuildContext context) {
    final googlePhoto = googlePhotoUrl ?? '';
    final hasGooglePhoto = googlePhoto.isNotEmpty;
    return AgriDialog(
      icon: hasGooglePhoto ? null : Icons.person_outline,
      stackedActions: true,
      title: Text(tl('Add a profile photo'), textAlign: TextAlign.center),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasGooglePhoto) ...[
            CircleAvatar(
              radius: 42,
              backgroundImage: NetworkImage(googlePhoto),
            ),
            const SizedBox(height: 12),
          ],
          Text(
            hasGooglePhoto
                ? tl(
                    'Use your Google photo, or upload a different one. You can change it anytime in Edit Profile.',
                  )
                : tl(
                    'A photo helps people recognize you. You can change it anytime in Edit Profile.',
                  ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
      actions: [
        if (hasGooglePhoto)
          AgriDialogButton(
            label: tl('Use Google photo'),
            kind: AgriButtonKind.primary,
            onPressed: () => Navigator.pop(context, ProfilePhotoChoice.google),
          ),
        AgriDialogButton(
          label: hasGooglePhoto ? tl('Upload my own') : tl('Upload a photo'),
          kind: hasGooglePhoto
              ? AgriButtonKind.secondary
              : AgriButtonKind.primary,
          onPressed: () => Navigator.pop(context, ProfilePhotoChoice.upload),
        ),
        AgriDialogButton(
          label: tl('Not now'),
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }
}
