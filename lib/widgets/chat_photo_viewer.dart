import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../l10n/app_language.dart';
import '../services/gallery_saver.dart';
import 'app_scaffold_messenger.dart';

/// Opens a chat photo full screen ([ChatPhotoViewer]).
void openChatPhoto(BuildContext context, String url, {String? caption}) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => ChatPhotoViewer(url: url, caption: caption),
    ),
  );
}

/// The Save button in the bar of a full-screen chat photo or video: saves
/// it to the phone's gallery (a spinner in its place meanwhile), then says
/// how it went — saved, not allowed yet, or failed.
class SaveToGalleryButton extends StatefulWidget {
  final String url;
  final bool video;

  /// Stands in for [savePhotoToGallery] / [saveVideoToGallery] in tests.
  @visibleForTesting
  final SaveToGallery? save;

  const SaveToGalleryButton({
    super.key,
    required this.url,
    this.video = false,
    this.save,
  });

  @override
  State<SaveToGalleryButton> createState() => _SaveToGalleryButtonState();
}

class _SaveToGalleryButtonState extends State<SaveToGalleryButton> {
  bool _saving = false;

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final save =
        widget.save ?? (widget.video ? saveVideoToGallery : savePhotoToGallery);
    final result = await save(widget.url);
    if (!mounted) return;
    setState(() => _saving = false);
    final video = widget.video;
    ScaffoldMessenger.of(context).showSnackBar(switch (result) {
      SaveResult.saved => appSnackBar(
        video
            ? tl('Video saved to your gallery.')
            : tl('Photo saved to your gallery.'),
        kind: MessageKind.success,
      ),
      SaveResult.accessDenied => appSnackBar(
        video
            ? tl(
                'AgriTrade+ cannot save videos yet. Allow it in your phone settings, then try again.',
              )
            : tl(
                'AgriTrade+ cannot save photos yet. Allow it in your phone settings, then try again.',
              ),
        kind: MessageKind.warning,
      ),
      SaveResult.failed => appSnackBar(
        video
            ? tl(
                'Could not save the video. Check your connection and try again.',
              )
            : tl(
                'Could not save the photo. Check your connection and try again.',
              ),
        kind: MessageKind.error,
      ),
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_saving) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
        ),
      );
    }
    return IconButton(
      key: const Key('saveToGallery'),
      tooltip: tl('Save to Gallery'),
      onPressed: _save,
      icon: const Icon(Icons.download_rounded),
    );
  }
}

/// A photo from a chat, full screen on black: pinch to zoom, and Save puts
/// a copy in the phone's gallery.
class ChatPhotoViewer extends StatelessWidget {
  final String url;

  /// Who sent it and when, in the bar at the top; optional.
  final String? caption;

  /// Stands in for [savePhotoToGallery] in tests.
  @visibleForTesting
  final SaveToGallery? save;

  const ChatPhotoViewer({
    super.key,
    required this.url,
    this.caption,
    this.save,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: caption == null
            ? null
            : Text(
                caption!,
                style: GoogleFonts.montserrat(
                  fontSize: 13,
                  color: Colors.white70,
                ),
              ),
        actions: [SaveToGalleryButton(url: url, save: save)],
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 1,
          maxScale: 5,
          child: Hero(
            tag: url,
            child: Image.network(
              url,
              fit: BoxFit.contain,
              loadingBuilder: (context, child, progress) => progress == null
                  ? child
                  : const CircularProgressIndicator(color: Colors.white),
              errorBuilder: (_, _, _) => const Icon(
                Icons.broken_image_outlined,
                color: Colors.white54,
                size: 48,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
