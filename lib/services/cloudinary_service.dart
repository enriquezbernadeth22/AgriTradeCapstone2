import 'package:cloudinary_public/cloudinary_public.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

class CloudinaryService {
  final _cloudinary =
      CloudinaryPublic('gxir71bo', 'agritrade_unsigned', cache: false);

  /// [onProgress] is told how much has gone up, 0 to 1, as it uploads.
  Future<String?> uploadImage(
    XFile file, {
    String folder = 'agritrade/listings',
    void Function(double sent)? onProgress,
  }) async {
    try {
      final res = await _cloudinary.uploadFile(
        CloudinaryFile.fromFile(
          file.path,
          resourceType: CloudinaryResourceType.Image,
          folder: folder,
        ),
        onProgress: uploadProgress(onProgress),
      );
      return res.secureUrl;
    } catch (e) {
      return null;
    }
  }

  /// Uploads a chat video; its https link, or null if it could not be sent.
  /// [onProgress] is told how much has gone up, 0 to 1, as it uploads.
  Future<String?> uploadVideo(
    XFile file, {
    String folder = 'agritrade/chat',
    void Function(double sent)? onProgress,
  }) async {
    try {
      final res = await _cloudinary.uploadFile(
        CloudinaryFile.fromFile(
          file.path,
          resourceType: CloudinaryResourceType.Video,
          folder: folder,
        ),
        onProgress: uploadProgress(onProgress),
      );
      return res.secureUrl;
    } catch (e) {
      return null;
    }
  }

  /// The bytes sent so far as a share of the whole file (0 to 1), passed
  /// to [onProgress]. Null when nobody is listening.
  @visibleForTesting
  static void Function(int sent, int total)? uploadProgress(
    void Function(double sent)? onProgress,
  ) {
    if (onProgress == null) return null;
    return (sent, total) {
      if (total > 0) onProgress((sent / total).clamp(0.0, 1.0));
    };
  }

  /// The still picture Cloudinary makes from a video's first frame
  /// (`so_0`, as a .jpg), shown in the chat before the video is played.
  /// Null for a link that is not a Cloudinary video.
  static String? videoThumbnail(String videoUrl) {
    const marker = '/video/upload/';
    final at = videoUrl.indexOf(marker);
    if (at < 0) return null;
    final head = videoUrl.substring(0, at + marker.length);
    final tail = videoUrl.substring(at + marker.length);
    final dot = tail.lastIndexOf('.');
    final slash = tail.lastIndexOf('/');
    final stem = dot > slash ? tail.substring(0, dot) : tail;
    return '${head}so_0/$stem.jpg';
  }

  /// [uploadImage] from the picture's bytes — for the web (the Admin
  /// Portal), where a picked file has no path to read it from.
  Future<String?> uploadImageBytes(
    List<int> bytes, {
    required String name,
    String folder = 'agritrade/profiles',
  }) async {
    try {
      final res = await _cloudinary.uploadFile(
        CloudinaryFile.fromBytesData(
          bytes,
          identifier: name,
          resourceType: CloudinaryResourceType.Image,
          folder: folder,
        ),
      );
      return res.secureUrl;
    } catch (e) {
      return null;
    }
  }
}