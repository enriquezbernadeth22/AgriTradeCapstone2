import 'package:flutter/material.dart';
import '../widgets/app_scaffold_messenger.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import '../services/location_permission_prompt.dart';
import '../services/message_service.dart';
import '../widgets/agri_dialog.dart';
import '../widgets/glow_field.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../l10n/app_language.dart';

// The chat composer and its attachment menu, shared by the Farmer and Buyer
// chat screen (ChatScreen).
//
// Permissions are asked only when an attachment is actually used — never
// at startup or onboarding:
//  - Camera / photos: the system asks the first time (iOS); Android's
//    camera hand-off and photo picker need no runtime permission at all.
//    Once granted it's never asked again. If access is denied, the user
//    gets an explanation with Try Again / Open Settings.
//  - Location: separate, requested only after the user confirms Share
//    Location, and never sent automatically.

enum ChatAttachment { camera, gallery, recordVideo, chooseVideo, location }

/// The largest video a chat can send: 100 MB, the most Cloudinary takes in
/// one upload. (20 MB was too little: a phone recording in 1080p passes it
/// in about 10 seconds, so longer clips were turned away.)
const int kChatVideoMaxBytes = 100 * 1024 * 1024;

/// The longest video the camera records for a chat: 30 seconds, about
/// 60 MB at 1080p — within [kChatVideoMaxBytes], and quick enough to send
/// and to play on mobile data.
const Duration kChatVideoMaxDuration = Duration(seconds: 30);

/// [bytes] in megabytes for people: "58 MB", "4.2 MB".
String formatMegabytes(int bytes) {
  final mb = bytes / (1024 * 1024);
  return mb >= 10 ? '${mb.round()} MB' : '${mb.toStringAsFixed(1)} MB';
}

/// The + menu: Take Photo, Choose Photo, Record Video, Choose Video, then —
/// under a line — Share Location — a small floating menu
/// that opens upward from the + button ([plusButtonContext]).
Future<ChatAttachment?> showChatAttachmentMenu(BuildContext plusButtonContext) {
  return showAgriPopupMenu<ChatAttachment>(
    anchorContext: plusButtonContext,
    upward: true,
    width: 236,
    items: [
      AgriMenuItem(
        value: ChatAttachment.camera,
        icon: Icons.camera_alt_outlined,
        label: tl('Take Photo'),
      ),
      AgriMenuItem(
        value: ChatAttachment.gallery,
        icon: Icons.photo_library_outlined,
        label: tl('Choose Photo'),
      ),
      AgriMenuItem(
        value: ChatAttachment.recordVideo,
        icon: Icons.videocam_outlined,
        // The limits are on the menu, so nobody records a clip too long.
        label: tl('Record Video ({0} sec max)', [
          kChatVideoMaxDuration.inSeconds,
        ]),
      ),
      AgriMenuItem(
        value: ChatAttachment.chooseVideo,
        icon: Icons.video_library_outlined,
        label: tl('Choose Video ({0} MB max)', [
          kChatVideoMaxBytes ~/ (1024 * 1024),
        ]),
      ),
      AgriMenuItem(
        value: ChatAttachment.location,
        icon: Icons.location_on_outlined,
        label: tl('Share Location'),
        dividerBefore: true,
      ),
    ],
  );
}

/// Takes or picks one photo for a chat message. Null if the user cancelled
/// or access was denied (after explaining how to allow it).
Future<XFile?> pickChatPhoto(BuildContext context, ImageSource source) async {
  final camera = source == ImageSource.camera;
  while (true) {
    try {
      return await ImagePicker().pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 70,
      );
    } on PlatformException catch (e) {
      if (!context.mounted) return null;
      final denied =
          e.code.contains('access_denied') ||
          e.code.contains('access_restricted');
      if (!denied) {
        ScaffoldMessenger.of(context).showSnackBar(
          appSnackBar(
            camera
                ? tl('The camera isn\'t available right now.')
                : tl('Your photos couldn\'t be opened right now.'),
            kind: MessageKind.error,
          ),
        );
        return null;
      }
      final retry = await _explainMediaDenied(context, camera: camera);
      if (!retry || !context.mounted) return null;
    }
  }
}

/// Records or picks one video for a chat message, at most
/// [kChatVideoMaxBytes] (one over it is turned away with a message). Null
/// if the user cancelled, access was denied, or the video was too large.
Future<XFile?> pickChatVideo(BuildContext context, ImageSource source) async {
  final camera = source == ImageSource.camera;
  while (true) {
    try {
      final video = await ImagePicker().pickVideo(
        source: source,
        maxDuration: kChatVideoMaxDuration,
      );
      if (video == null || !context.mounted) return null;
      final size = await video.length();
      if (!chatVideoFits(size)) {
        if (!context.mounted) return null;
        ScaffoldMessenger.of(context).showSnackBar(
          appSnackBar(
            tl(
              'This video is {0}; the most a chat can send is {1} MB. Choose a shorter one, or record up to {2} seconds.',
              [
                formatMegabytes(size),
                kChatVideoMaxBytes ~/ (1024 * 1024),
                kChatVideoMaxDuration.inSeconds,
              ],
            ),
            kind: MessageKind.warning,
          ),
        );
        return null;
      }
      return video;
    } on PlatformException catch (e) {
      if (!context.mounted) return null;
      final denied =
          e.code.contains('access_denied') ||
          e.code.contains('access_restricted');
      if (!denied) {
        ScaffoldMessenger.of(context).showSnackBar(
          appSnackBar(
            camera
                ? tl('The camera isn\'t available right now.')
                : tl('Your videos couldn\'t be opened right now.'),
            kind: MessageKind.error,
          ),
        );
        return null;
      }
      final retry = await _explainMediaDenied(
        context,
        camera: camera,
        video: true,
      );
      if (!retry || !context.mounted) return null;
    }
  }
}

/// Whether a video of [bytes] may be sent in a chat.
bool chatVideoFits(int bytes) => bytes <= kChatVideoMaxBytes;

/// Access was denied: says why it's needed and how to allow it. True means
/// try again.
Future<bool> _explainMediaDenied(
  BuildContext context, {
  required bool camera,
  bool video = false,
}) async {
  final action = await showAgriDialog<String>(
    context: context,
    builder: (dialogContext) => AgriDialog(
      icon: camera ? Icons.no_photography_outlined : Icons.hide_image_outlined,
      tone: AgriTone.warning,
      title: Text(
        camera
            ? tl('Camera access is off')
            : video
            ? tl('Video access is off')
            : tl('Photo access is off'),
      ),
      content: Text(switch ((camera, video)) {
        (true, false) => tl(
          'AgriTrade+ needs the camera to take a photo to send in this chat. Allow camera access in your device settings, then try again.',
        ),
        (true, true) => tl(
          'AgriTrade+ needs the camera to record a video to send in this chat. Allow camera access in your device settings, then try again.',
        ),
        (false, false) => tl(
          'AgriTrade+ needs access to your photos to send one in this chat. Allow photo access in your device settings, then try again.',
        ),
        (false, true) => tl(
          'AgriTrade+ needs access to your videos to send one in this chat. Allow photo and video access in your device settings, then try again.',
        ),
      }),
      actions: [
        AgriDialogButton(
          label: tl('Try Again'),
          onPressed: () => Navigator.pop(dialogContext, 'retry'),
        ),
        AgriDialogButton(
          label: tl('Open Settings'),
          kind: AgriButtonKind.primary,
          onPressed: () => Navigator.pop(dialogContext, 'settings'),
        ),
      ],
    ),
  );
  if (action == 'settings') {
    await Geolocator.openAppSettings();
    return false;
  }
  return action == 'retry';
}

/// Share Location, step by step: confirm (exact location, this chat only,
/// for delivery/pick-up) → location permission (asked only now) → location
/// services on → current position. Null if the user stopped at any step or
/// it couldn't be read; nothing is ever sent without the confirmation.
Future<Position?> getLocationToShare(
  BuildContext context, {
  required String otherUserName,
}) async {
  final confirmed = await showAgriConfirm(
    context: context,
    icon: Icons.location_on_outlined,
    title: tl('Share your exact location?'),
    message: tl(
      'Your current location will be sent to {0} in this chat only — use it to coordinate delivery or pick-up. Your public profile still shows only your general area.',
      [otherUserName],
    ),
    confirmLabel: tl('Share Location'),
  );
  if (!confirmed || !context.mounted) return null;

  final granted = await maybeRequestLocationPermission(
    context,
    title: tl('Share your location'),
    message: tl(
      'AgriTrade+ needs location access to send your current position in this chat. It\'s only read when you choose Share Location.',
    ),
  );
  if (!granted || !context.mounted) return null;

  if (!await Geolocator.isLocationServiceEnabled()) {
    if (!context.mounted) return null;
    ScaffoldMessenger.of(context).showSnackBar(
      appSnackBar(
        tl('Turn on location services to share your location.'),
        kind: MessageKind.warning,
      ),
    );
    return null;
  }

  return Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
  );
}

/// Thin bar at the top of the messages area while a conversation's first
/// batch of messages loads. The rest of the chat stays on screen.
class ChatMessagesLoadingBar extends StatelessWidget {
  const ChatMessagesLoadingBar({super.key});

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(48, 8, 48, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: LinearProgressIndicator(
          minHeight: 2.5,
          color: AppColors.brand.withValues(alpha: 0.55),
          backgroundColor: AppColors.brandFill.withValues(alpha: 0.08),
        ),
      ),
    ),
  );
}

/// Take Photo or Choose Photo — no video or location — opening from
/// [anchorContext]: the farmer's Attach on a buyer's health-certificate
/// request ([CertificateRequestRow]). Null if dismissed.
Future<ImageSource?> showChatPhotoMenu(BuildContext anchorContext) {
  return showAgriPopupMenu<ImageSource>(
    anchorContext: anchorContext,
    width: 196,
    items: [
      AgriMenuItem(
        value: ImageSource.camera,
        icon: Icons.camera_alt_outlined,
        label: tl('Take Photo'),
      ),
      AgriMenuItem(
        value: ImageSource.gallery,
        icon: Icons.photo_library_outlined,
        label: tl('Choose Photo'),
      ),
    ],
  );
}

/// Under a buyer's health-certificate request, on the farmer's side: a
/// compact row — a document icon, "Health certificate requested", and an
/// outlined Attach — set apart from the messages (white, thin grey border,
/// no bubble). Attach opens Take Photo / Choose Photo ([showChatPhotoMenu]).
class CertificateRequestRow extends StatelessWidget {
  /// Gets the Attach button's context, to anchor the menu. Null shows it
  /// off (e.g. while something is sending).
  final ValueChanged<BuildContext>? onAttach;

  const CertificateRequestRow({super.key, required this.onAttach});

  @override
  Widget build(BuildContext context) {
    final enabled = onAttach != null;
    return Container(
      constraints: const BoxConstraints(maxWidth: 300),
      padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.grey(300)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.description_outlined, size: 17, color: AppColors.brand),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              tl('Health certificate requested'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: AppColors.text),
            ),
          ),
          const SizedBox(width: 8),
          Builder(
            builder: (buttonContext) => OutlinedButton(
              key: const Key('certificateAttach'),
              onPressed: enabled ? () => onAttach!(buttonContext) : null,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.brand,
                side: BorderSide(
                  color: enabled ? AppColors.brand : AppColors.grey(300),
                ),
                minimumSize: const Size(0, 30),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: AppTheme.compactButtonShape,
              ),
              child: Text(
                tl('Attach'),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A one-tap message or action in a chat, as a small pill: the buyer's
/// "Can I see the animal's health certificate?" over the message box.
class ChatSuggestionChip extends StatelessWidget {
  final IconData icon;
  final String label;

  /// Null shows the chip disabled (e.g. while a message is sending).
  /// Gets the chip's own context, to anchor a menu.
  final ValueChanged<BuildContext>? onTap;

  const ChatSuggestionChip({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Material(
      color: AppColors.tint,
      shape: StadiumBorder(side: BorderSide(color: AppColors.accent)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: enabled ? () => onTap!(context) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: enabled ? AppColors.brand : AppColors.grey(500),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: enabled ? AppColors.brand : AppColors.grey(500),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// From how many characters the message box shows its count ("900/1000").
const int kChatCounterFrom = 900;

/// The message box: one + button for attachments, a wide text field that
/// grows as the user types more lines, and Send.
///
/// The text may be up to [MessageService.maxTextLength] characters, its
/// leading and trailing spaces not counted. Near the limit a count shows
/// under the box; over it the count turns red and Send is off.
class ChatComposerBar extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final bool sending;
  final VoidCallback onSend;

  /// Called with the + button's context, to anchor the attachment menu.
  final ValueChanged<BuildContext> onAttach;

  /// The + button and the message box, for the first-time tour.
  final GlobalKey? plusKey;
  final GlobalKey? fieldKey;

  const ChatComposerBar({
    super.key,
    required this.controller,
    required this.hintText,
    required this.sending,
    required this.onSend,
    required this.onAttach,
    this.plusKey,
    this.fieldKey,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final length = value.text.trim().length;
        const max = MessageService.maxTextLength;
        final tooLong = length > max;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _bar(
              canSend: !sending && !tooLong,
              // While a message is being typed the + steps aside, giving
              // the box its room; it comes back once the box is empty.
              showAttach: length == 0,
            ),
            if (length >= kChatCounterFrom)
              Padding(
                padding: const EdgeInsets.only(top: 4, right: 52),
                child: Text(
                  '$length/$max',
                  key: const Key('chatCharacterCount'),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: tooLong ? FontWeight.w700 : FontWeight.w500,
                    color: tooLong
                        ? AppColors.tone(Colors.red, 700)
                        : AppColors.grey(600),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _bar({required bool canSend, required bool showAttach}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Always in the row (only its content changes), so the text field
        // keeps its place — and the keyboard — as the + comes and goes.
        AnimatedSize(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            child: showAttach
                ? Row(
                    key: const ValueKey('attach'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Builder(
                        builder: (buttonContext) => IconButton(
                          key: plusKey,
                          tooltip: tl('Attach'),
                          onPressed: sending
                              ? null
                              : () => onAttach(buttonContext),
                          constraints: const BoxConstraints(
                            minWidth: 40,
                            minHeight: 42,
                          ),
                          padding: EdgeInsets.zero,
                          icon: Icon(
                            Icons.add_circle_outline_rounded,
                            color: AppColors.brand,
                            size: 26,
                          ),
                        ),
                      ),
                      const SizedBox(width: 2),
                    ],
                  )
                : const SizedBox(key: ValueKey('noAttach'), height: 42),
          ),
        ),
        // The forms' field (as on Log In): a thin grey outline at rest, and
        // while typing no outline but the soft green glow.
        Expanded(
          child: FormFieldGlow(
            key: fieldKey,
            child: TextField(
              controller: controller,
              style: const TextStyle(fontSize: 14),
              minLines: 1,
              maxLines: 6,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              decoration: AppTheme.plainFieldDecoration(hint: hintText),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Semantics(
          button: true,
          enabled: canSend,
          label: tl('Send'),
          child: Material(
            color: canSend ? AppColors.brandFill : AppColors.grey(400),
            shape: const CircleBorder(),
            child: InkWell(
              key: const Key('chatSend'),
              onTap: canSend ? onSend : null,
              customBorder: const CircleBorder(),
              child: const SizedBox(
                width: 42,
                height: 42,
                child: Icon(Icons.send_rounded, color: Colors.white, size: 20),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Over the message box while a photo or video goes up: what is being sent
/// and how far along, from the real upload (so it moves with the signal).
/// At 100% it says "Finishing…" while the message itself is saved.
class ChatUploadProgress extends StatelessWidget {
  final bool video;

  /// 0 to 1.
  final double progress;

  /// The file's size, when known: shown as "12 of 58 MB", so a big video's
  /// wait is understood.
  final int? totalBytes;

  const ChatUploadProgress({
    super.key,
    required this.video,
    required this.progress,
    this.totalBytes,
  });

  @override
  Widget build(BuildContext context) {
    final percent = (progress * 100).clamp(0, 100).floor();
    final finishing = percent >= 100;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.grey(200)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                video ? Icons.videocam_outlined : Icons.image_outlined,
                size: 18,
                color: AppColors.textStrong,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  finishing
                      ? tl('Finishing…')
                      : video
                      ? tl('Sending video… {0}%', [percent])
                      : tl('Sending photo… {0}%', [percent]),
                  style: TextStyle(fontSize: 12.5, color: AppColors.text),
                ),
              ),
              if (totalBytes case final total? when !finishing)
                Text(
                  tl('{0} of {1}', [
                    formatMegabytes(
                      (total * progress).round(),
                    ).replaceAll(' MB', ''),
                    formatMegabytes(total),
                  ]),
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textSecondary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              minHeight: 4,
              value: finishing ? null : progress,
              color: AppColors.brandFill,
              backgroundColor: AppColors.grey(200),
            ),
          ),
        ],
      ),
    );
  }
}
