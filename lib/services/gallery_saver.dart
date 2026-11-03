import 'dart:io';
import 'dart:typed_data';

import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;

/// How a save to the phone's gallery ended.
enum SaveResult { saved, accessDenied, failed }

/// Saves the photo or video at [url] to the phone's gallery.
typedef SaveToGallery = Future<SaveResult> Function(String url);

/// The album a saved chat photo or video goes into.
const String kGalleryAlbum = 'AgriTrade+';

/// Saves the photo at [url] to the gallery, in the [kGalleryAlbum] album:
/// downloads it, asks for access to add photos the first time (only some
/// phones ask), then adds it.
Future<SaveResult> savePhotoToGallery(String url) =>
    _save(url, timeout: const Duration(seconds: 30), (bytes) async {
      await Gal.putImageBytes(
        bytes,
        album: kGalleryAlbum,
        name: 'agritrade_${DateTime.now().millisecondsSinceEpoch}',
      );
    });

/// Saves the video at [url] to the gallery, in the [kGalleryAlbum] album.
/// A video is added from a file, so it is written to a temporary folder
/// first, which is removed afterwards.
Future<SaveResult> saveVideoToGallery(String url) =>
    _save(url, timeout: const Duration(minutes: 2), (bytes) async {
      final folder = await Directory.systemTemp.createTemp('agritrade_video');
      try {
        final file = File(
          '${folder.path}/agritrade_${DateTime.now().millisecondsSinceEpoch}'
          '${_videoExtension(url)}',
        );
        await file.writeAsBytes(bytes);
        await Gal.putVideo(file.path, album: kGalleryAlbum);
      } finally {
        try {
          await folder.delete(recursive: true);
        } catch (_) {}
      }
    });

// ".mp4", ".mov"… from the link; ".mp4" when it has none.
String _videoExtension(String url) {
  final path = Uri.tryParse(url)?.path ?? '';
  final dot = path.lastIndexOf('.');
  final ext = dot > path.lastIndexOf('/') ? path.substring(dot) : '';
  return RegExp(r'^\.[A-Za-z0-9]{2,4}$').hasMatch(ext) ? ext : '.mp4';
}

Future<SaveResult> _save(
  String url,
  Future<void> Function(Uint8List bytes) add, {
  required Duration timeout,
}) async {
  try {
    final response = await http.get(Uri.parse(url)).timeout(timeout);
    if (response.statusCode != 200) return SaveResult.failed;
    if (!await Gal.hasAccess(toAlbum: true) &&
        !await Gal.requestAccess(toAlbum: true)) {
      return SaveResult.accessDenied;
    }
    await add(response.bodyBytes);
    return SaveResult.saved;
  } on GalException catch (e) {
    return e.type == GalExceptionType.accessDenied
        ? SaveResult.accessDenied
        : SaveResult.failed;
  } catch (_) {
    return SaveResult.failed;
  }
}
