import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../l10n/app_language.dart';
import '../services/cloudinary_service.dart';
import '../theme/app_colors.dart';
import 'chat_photo_viewer.dart';

/// A video sent in a chat: its first frame with a play button. Tapping it
/// opens [ChatVideoPlayerScreen]; nothing is downloaded until then.
class ChatVideoBubble extends StatelessWidget {
  final String videoUrl;

  const ChatVideoBubble({super.key, required this.videoUrl});

  @override
  Widget build(BuildContext context) {
    final thumbnail = CloudinaryService.videoThumbnail(videoUrl);
    return Semantics(
      button: true,
      label: tl('Video. Tap to play.'),
      child: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatVideoPlayerScreen(videoUrl: videoUrl),
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            width: 220,
            height: 160,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: AppColors.grey(800)),
                if (thumbnail != null)
                  Image.network(
                    thumbnail,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                Center(
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Plays one chat video full screen: tap to pause or play, with a bar
/// showing how far it has played, and Save to put a copy in the gallery.
class ChatVideoPlayerScreen extends StatefulWidget {
  final String videoUrl;

  const ChatVideoPlayerScreen({super.key, required this.videoUrl});

  @override
  State<ChatVideoPlayerScreen> createState() => _ChatVideoPlayerScreenState();
}

class _ChatVideoPlayerScreenState extends State<ChatVideoPlayerScreen> {
  late VideoPlayerController _controller;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _failed = false;
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
    _controller
        .initialize()
        .then((_) {
          if (!mounted) return;
          setState(() {});
          _controller.play();
        })
        .catchError((Object _) {
          if (mounted) setState(() => _failed = true);
        });
    _controller.addListener(_onTick);
  }

  // Redraws the play / pause button as the video plays and stops.
  void _onTick() {
    if (mounted) setState(() {});
  }

  void _retry() {
    _controller
      ..removeListener(_onTick)
      ..dispose();
    setState(_load);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onTick)
      ..dispose();
    super.dispose();
  }

  void _togglePlay() {
    if (!_controller.value.isInitialized) return;
    _controller.value.isPlaying ? _controller.pause() : _controller.play();
  }

  @override
  Widget build(BuildContext context) {
    final value = _controller.value;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [SaveToGalleryButton(url: widget.videoUrl, video: true)],
      ),
      body: SafeArea(
        child: Center(
          child: _failed
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      tl('Could not play this video.'),
                      style: const TextStyle(color: Colors.white),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _retry,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                      ),
                      child: Text(tl('Retry')),
                    ),
                  ],
                )
              : !value.isInitialized
              ? const CircularProgressIndicator(color: Colors.white)
              : GestureDetector(
                  onTap: _togglePlay,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: AspectRatio(
                          aspectRatio: value.aspectRatio,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              VideoPlayer(_controller),
                              if (!value.isPlaying)
                                Container(
                                  width: 64,
                                  height: 64,
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.55),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.play_arrow_rounded,
                                    color: Colors.white,
                                    size: 40,
                                    semanticLabel: tl('Play'),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      VideoProgressIndicator(
                        _controller,
                        allowScrubbing: true,
                        padding: const EdgeInsets.all(12),
                        colors: VideoProgressColors(
                          playedColor: Colors.white,
                          bufferedColor: Colors.white38,
                          backgroundColor: Colors.white12,
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
