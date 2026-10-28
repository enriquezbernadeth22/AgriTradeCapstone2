import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/feedback_service.dart';
import 'agri_dialog.dart';
import '../theme/app_colors.dart';

/// The longest comment the team's email takes (functions/app_feedback_logic.js).
const int kFeedbackMaxLength = 1000;

/// "Give us feedback": a 1–5 star rating and an optional comment, emailed
/// to the AgriTrade+ team. [prompted] when the app asked (after a few
/// products posted or orders placed) rather than the person opening Send
/// Feedback themselves. True when it was sent.
///
/// [send] stands in for [FeedbackService.send] in tests.
Future<bool> showFeedbackSheet(
  BuildContext context, {
  FeedbackTrigger trigger = FeedbackTrigger.menu,
  bool prompted = false,
  Future<void> Function({
    required int rating,
    required String message,
    required FeedbackTrigger trigger,
  })?
  send,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final sent = await showAgriSheet<bool>(
    context: context,
    isScrollControlled: true,
    title: prompted ? 'Enjoying AgriTrade+?' : 'Send Feedback',
    builder: (_) => _FeedbackForm(
      trigger: trigger,
      prompted: prompted,
      send: send ?? FeedbackService.instance.send,
    ),
  );
  if (sent == true) {
    messenger?.showSnackBar(
      const SnackBar(content: Text('Thank you for your feedback!')),
    );
  }
  return sent == true;
}

class _FeedbackForm extends StatefulWidget {
  final FeedbackTrigger trigger;
  final bool prompted;
  final Future<void> Function({
    required int rating,
    required String message,
    required FeedbackTrigger trigger,
  })
  send;

  const _FeedbackForm({
    required this.trigger,
    required this.prompted,
    required this.send,
  });

  @override
  State<_FeedbackForm> createState() => _FeedbackFormState();
}

class _FeedbackFormState extends State<_FeedbackForm> {
  final _message = TextEditingController();
  int _rating = 0;
  bool _sending = false;
  String? _error;

  static const _ratingWords = [
    '',
    'Poor',
    'Fair',
    'Good',
    'Very good',
    'Excellent',
  ];

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.send(
        rating: _rating,
        message: _message.text,
        trigger: widget.trigger,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      final message = e.message?.trim() ?? '';
      setState(() {
        _sending = false;
        _error = message.isNotEmpty && message.toLowerCase() != 'internal'
            ? message
            : 'Your feedback could not be sent. Check your connection and '
                  'try again.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error =
            'Your feedback could not be sent. Check your connection and try '
            'again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = GoogleFonts.montserrat(
      fontSize: 12.5,
      height: 1.45,
      color: AppColors.grey(700),
    );
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 2, 18, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.prompted
                ? 'Give us feedback: how is the app working for you? It goes '
                      'straight to the AgriTrade+ team.'
                : 'Tell the AgriTrade+ team what you like or what we can '
                      'improve. It is sent to our email.',
            style: body,
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var star = 1; star <= 5; star++)
                IconButton(
                  tooltip: '$star star${star == 1 ? '' : 's'}',
                  visualDensity: VisualDensity.compact,
                  onPressed: _sending
                      ? null
                      : () => setState(() {
                          _rating = star;
                          _error = null;
                        }),
                  icon: Icon(
                    star <= _rating
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    size: 34,
                    color: star <= _rating
                        ? AppColors.adapt(const Color(0xFFF5A623))
                        : AppColors.grey(400),
                  ),
                ),
            ],
          ),
          SizedBox(
            height: 18,
            child: Text(
              _rating == 0 ? 'Tap a star to rate' : _ratingWords[_rating],
              textAlign: TextAlign.center,
              style: GoogleFonts.montserrat(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _rating == 0 ? AppColors.grey(500) : AppColors.brand,
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _message,
            enabled: !_sending,
            minLines: 3,
            maxLines: 5,
            maxLength: kFeedbackMaxLength,
            textCapitalization: TextCapitalization.sentences,
            style: GoogleFonts.montserrat(fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Your comments or suggestions (optional)',
              hintStyle: GoogleFonts.montserrat(
                fontSize: 12.5,
                color: AppColors.grey(500),
              ),
              filled: true,
              fillColor: AppColors.surface,
              contentPadding: const EdgeInsets.all(12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: AppColors.grey(300)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: AppColors.grey(300)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: AppColors.brand, width: 1.4),
              ),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _error!,
                style: GoogleFonts.montserrat(
                  fontSize: 12,
                  color: AppColors.tone(Colors.red, 700),
                ),
              ),
            ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: AgriDialogButton(
                  label: widget.prompted ? 'Not now' : 'Cancel',
                  onPressed: _sending
                      ? null
                      : () => Navigator.of(context).pop(false),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AgriDialogButton(
                  label: 'Send',
                  kind: AgriButtonKind.primary,
                  loading: _sending,
                  onPressed: _rating == 0 ? null : _send,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
