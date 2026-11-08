import '../widgets/agri_app_bar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../widgets/app_scaffold_messenger.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/conversation_prefs_service.dart';
import '../services/firebase_refs.dart';
import '../services/presence_service.dart';
import '../widgets/agri_dialog.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/report_user_dialog.dart';
import 'add_product_screen.dart';
import 'conversation_tools_screens.dart';
import 'buyer_public_profile_screen.dart';
import 'farmer_storefront_screen.dart';
import 'product_detail_screen.dart';
import '../theme/app_colors.dart';
import '../l10n/app_language.dart';
import '../theme/app_theme.dart';

/// Conversation Info, a full-screen page opened from the (i) in a chat's
/// header — same for Farmer and Buyer. Shows who the other person is
/// (photo, display name/nickname, role, whether they're active, and only
/// their general area — never an exact location), then:
///  - tools: Nickname, Search conversation, View all photos
///  - the linked product, if any
///  - Pin / Mute / Archive
///  - Report / Block (only here — not in the chat header)
///  - location privacy
///
/// Pops with a message id when the user picks a search result, so the chat
/// can jump to that message.
class ConversationInfoScreen extends StatefulWidget {
  final String conversationId;
  final String otherUserId;
  final String otherUserName;
  final String? otherUserPhotoUrl;
  final String? productId;
  final String? productName;

  const ConversationInfoScreen({
    super.key,
    required this.conversationId,
    required this.otherUserId,
    required this.otherUserName,
    this.otherUserPhotoUrl,
    this.productId,
    this.productName,
  });

  @override
  State<ConversationInfoScreen> createState() => _ConversationInfoScreenState();
}

class _ConversationInfoScreenState extends State<ConversationInfoScreen> {
  final ConversationPrefs _prefs = ConversationPrefs.instance;
  final String? _myUid = FirebaseRefs.auth.currentUser?.uid;

  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _profile =
      FirebaseRefs.firestore
          .collection('publicProfiles')
          .doc(widget.otherUserId)
          .snapshots();
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _presence =
      FirebaseRefs.firestore
          .collection('presence')
          .doc(widget.otherUserId)
          .snapshots();
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _conversation =
      FirebaseRefs.firestore
          .collection('conversations')
          .doc(widget.conversationId)
          .snapshots();

  void _onPrefsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _prefs.addListener(_onPrefsChanged);
    _prefs.load(_myUid);
  }

  @override
  void dispose() {
    _prefs.removeListener(_onPrefsChanged);
    super.dispose();
  }

  int _lastMessageMs(Map<String, dynamic>? data) {
    final t = data?['lastMessageTime'];
    return t is Timestamp ? t.millisecondsSinceEpoch : 0;
  }

  bool _isArchived(Map<String, dynamic>? data) {
    final lastSender = data?['lastSenderId']?.toString() ?? '';
    return _prefs.isArchived(
      widget.conversationId,
      lastMessageMs: _lastMessageMs(data),
      lastFromOther: lastSender.isNotEmpty && lastSender != _myUid,
    );
  }

  Future<void> _block(String name) async {
    final confirmed = await showAgriConfirm(
      context: context,
      icon: Icons.block,
      tone: AgriTone.destructive,
      title: tl('Block {0}?', [name]),
      message: tl(
        'Your conversations with {0} will be hidden from Messages. You can unblock them anytime from Blocked Users.',
        [name],
      ),
      confirmLabel: tl('Block'),
    );
    if (!confirmed || !mounted) return;
    _prefs.block(widget.otherUserId);
    // Close only this screen. The chat sees the block when it regains
    // focus and closes itself (the conversation is now hidden).
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // The cream page with white grouped cards (the user's design,
      // 2026-11-08): no gold anywhere on this screen.
      backgroundColor: AppColors.page,
      appBar: AgriAppBar(title: tl('Conversation Info')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _profile,
        builder: (context, profileSnap) {
          final profile = profileSnap.data?.data();
          final liveName = profile?['name']?.toString().trim() ?? '';
          final realName = liveName.isNotEmpty
              ? liveName
              : widget.otherUserName;
          // In this conversation only, a nickname replaces the real name
          // (which is then not shown here at all).
          final name = _prefs.displayName(widget.conversationId, realName);
          final role = profile?['role']?.toString();
          final area = [
            profile?['barangay'],
            profile?['municipality'],
            profile?['province'],
          ].whereType<String>().where((s) => s.trim().isNotEmpty).join(', ');

          final nickname = _prefs.nicknameFor(widget.conversationId);
          final hasProduct =
              widget.productId != null && widget.productId!.isNotEmpty;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
            children: [
              _header(profile, profileSnap.hasData, name, role, area),
              const SizedBox(height: 20),

              _sectionTitle(tl('Conversation tools')),
              _section(
                children: [
                  _actionRow(
                    icon: Icons.badge_outlined,
                    label: tl('Nickname'),
                    subtitle:
                        nickname ?? tl('Only you see it, only in this chat'),
                    onTap: () => _editNickname(nickname),
                  ),
                  _actionRow(
                    icon: Icons.search_rounded,
                    label: tl('Search conversation'),
                    onTap: () => _openSearch(name),
                  ),
                  _actionRow(
                    icon: Icons.photo_library_outlined,
                    label: tl('View all photos'),
                    onTap: () => _openPhotos(name),
                  ),
                ],
              ),

              if (hasProduct) ...[
                const SizedBox(height: 16),
                _sectionTitle(tl('Product context')),
                _section(
                  children: [
                    _actionRow(
                      icon: Icons.shopping_basket_outlined,
                      label: (widget.productName ?? '').isNotEmpty
                          ? widget.productName!
                          : tl('View product'),
                      onTap: _openProduct,
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 16),
              _sectionTitle(tl('Conversation')),
              StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: _conversation,
                builder: (context, convSnap) =>
                    _management(convSnap.data?.data()),
              ),

              const SizedBox(height: 16),
              _sectionTitle(tl('Safety')),
              _section(
                children: [
                  _actionRow(
                    icon: Icons.report_problem_outlined,
                    label: tl('Report {0}', [name]),
                    destructive: true,
                    // The report itself records the real name, for the
                    // admin; the nickname is only the label here.
                    onTap: () => showReportUserDialog(
                      context,
                      otherUserId: widget.otherUserId,
                      otherUserName: realName,
                      displayName: name,
                      conversationId: widget.conversationId,
                    ),
                  ),
                  _actionRow(
                    icon: Icons.block,
                    label: tl('Block {0}', [name]),
                    destructive: true,
                    onTap: () => _block(name),
                  ),
                ],
              ),

              const SizedBox(height: 16),
              _sectionTitle(tl('Location privacy')),
              _section(
                children: [
                  _infoRow(
                    Icons.lock_outline,
                    tl('Only a general area is public'),
                    tl(
                      'Profiles show only a general location (barangay, municipality/city, province).',
                    ),
                  ),
                  _infoRow(
                    Icons.location_on_outlined,
                    tl('Exact location only when you choose'),
                    tl(
                      'An exact location is shared only when someone intentionally uses Share Location in this chat.',
                    ),
                  ),
                  _infoRow(
                    Icons.local_shipping_outlined,
                    tl('For delivery or pick-up'),
                    tl(
                      'A shared exact location may be used to coordinate delivery or pick-up.',
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _header(
    Map<String, dynamic>? profile,
    bool loaded,
    String name,
    String? role,
    String area,
  ) {
    final livePhotoUrl = profile?['photoUrl']?.toString();
    // The photo and name open the person's own page: a buyer's profile,
    // or a farmer's storefront.
    final openProfile = switch (role) {
      'buyer' => () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => BuyerPublicProfileScreen(
            buyerId: widget.otherUserId,
            fallbackName: widget.otherUserName,
          ),
        ),
      ),
      'farmer' => () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => FarmerStorefrontScreen(farmerId: widget.otherUserId),
        ),
      ),
      _ => null,
    };
    return Column(
      children: [
        Semantics(
          button: openProfile != null,
          hint: role == 'buyer' ? tl('View profile') : null,
          child: InkWell(
            key: const Key('conversationInfoPerson'),
            onTap: openProfile,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Column(
                children: [
                  ProfileAvatar(
                    photoUrl: loaded ? livePhotoUrl : widget.otherUserPhotoUrl,
                    name: name,
                    // Clean: no ring, badge or icon over the photo.
                    radius: 34,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    name,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.montserrat(
                      fontSize: 17.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.brand,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 2),
        StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _presence,
          builder: (context, snap) {
            final online = PresenceService.isOnline(snap.data?.data());
            final roleLabel = role == 'farmer'
                ? 'Farmer'
                : role == 'buyer'
                ? 'Buyer'
                : null;
            final parts = [?roleLabel, if (online) tl('Active now')];
            if (parts.isEmpty) return const SizedBox.shrink();
            return Text(
              parts.join(' · '),
              style: GoogleFonts.montserrat(
                fontSize: 12,
                color: online
                    ? AppColors.adapt(const Color(0xFF16A34A))
                    : _muted,
                fontWeight: FontWeight.w500,
              ),
            );
          },
        ),
        if (area.isNotEmpty) ...[
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.location_on_outlined,
                size: 14,
                color: AppColors.brand,
              ),
              const SizedBox(width: 3),
              Flexible(
                child: Text(
                  area,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.montserrat(fontSize: 11.5, color: _muted),
                ),
              ),
            ],
          ),
        ],
        if (openProfile != null) ...[
          const SizedBox(height: 12),
          // White, a thin dark green outline, 40 high.
          OutlinedButton.icon(
            key: const Key('conversationInfoViewProfile'),
            onPressed: openProfile,
            icon: Icon(
              role == 'farmer'
                  ? Icons.storefront_outlined
                  : Icons.person_outline_rounded,
              size: 16,
            ),
            label: Text(
              role == 'farmer' ? tl('View Storefront') : tl('View Profile'),
              style: GoogleFonts.montserrat(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.brand,
              backgroundColor: AppColors.surface,
              side: BorderSide(color: AppColors.brand),
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 18),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: AppTheme.buttonShape,
            ),
          ),
        ],
      ],
    );
  }

  // Pin / Mute / Archive — the same saved state the Messages list uses.
  Widget _management(Map<String, dynamic>? conversation) {
    final id = widget.conversationId;
    final pinned = _prefs.isPinned(id);
    final muted = _prefs.isMuted(id);
    final archived = _isArchived(conversation);
    return _section(
      children: [
        _actionRow(
          icon: pinned ? Icons.push_pin : Icons.push_pin_outlined,
          label: pinned ? tl('Unpin conversation') : tl('Pin conversation'),
          chevron: false,
          onTap: () => _prefs.togglePinned(id),
        ),
        _actionRow(
          icon: muted
              ? Icons.notifications_active_outlined
              : Icons.notifications_off_outlined,
          label: muted ? tl('Unmute notifications') : tl('Mute notifications'),
          chevron: false,
          onTap: () => _prefs.toggleMuted(id),
        ),
        _actionRow(
          icon: archived ? Icons.unarchive_outlined : Icons.archive_outlined,
          label: archived
              ? tl('Unarchive conversation')
              : tl('Archive conversation'),
          chevron: false,
          onTap: () => archived
              ? _prefs.unarchive(id)
              : _prefs.archive(id, lastMessageMs: _lastMessageMs(conversation)),
        ),
      ],
    );
  }

  Color get _muted =>
      AppColors.isDark ? AppColors.textSecondary : const Color(0xFF757575);
  Color get _line =>
      AppColors.isDark ? AppColors.hairline : const Color(0xFFE8E9E3);

  // A dark green heading over each group.
  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 7),
    child: Text(
      text,
      style: GoogleFonts.montserrat(
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
        color: AppColors.brand,
      ),
    ),
  );

  // Search returns the message to jump to; this screen then closes with it
  // so the chat can scroll there.
  Future<void> _openSearch(String name) async {
    final messageId = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => ConversationSearchScreen(
          conversationId: widget.conversationId,
          otherDisplayName: name,
        ),
      ),
    );
    if (messageId != null && mounted) Navigator.pop(context, messageId);
  }

  void _openPhotos(String name) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ConversationPhotosScreen(
          conversationId: widget.conversationId,
          otherDisplayName: name,
        ),
      ),
    );
  }

  // The listing this chat is about: the farmer who owns it gets their own
  // listing editor, anyone else the product page.
  Future<void> _openProduct() async {
    final productId = widget.productId;
    if (productId == null || productId.isEmpty) return;
    try {
      final snap = await FirebaseRefs.firestore
          .collection('products')
          .doc(productId)
          .get();
      final data = snap.data();
      if (!mounted) return;
      if (data == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          appSnackBar(
            tl('This listing is no longer available.'),
            kind: MessageKind.warning,
          ),
        );
        return;
      }
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => data['farmerId'] == _myUid
              ? AddProductScreen(productId: productId, existingData: data)
              : ProductDetailScreen(productId: productId, data: data),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        appSnackBar(
          tl(
            'Could not open the listing. Check your connection and try again.',
          ),
          kind: MessageKind.error,
        ),
      );
    }
  }

  // One white rounded card, a thin line between its rows.
  Widget _section({required List<Widget> children}) {
    return Container(
      decoration: AppTheme.card(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                indent: 46,
                endIndent: 14,
                color: _line,
              ),
            children[i],
          ],
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19, color: AppColors.brand),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.montserrat(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: GoogleFonts.montserrat(
                    fontSize: 11.5,
                    color: _muted,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // A compact row: a dark green outline icon (red for Report and Block),
  // the label, an optional line under it, and a chevron on rows that open
  // something.
  Widget _actionRow({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    String? subtitle,
    bool destructive = false,
    bool chevron = true,
  }) {
    final color = destructive
        ? AppColors.tone(Colors.red, 700)
        : AppColors.brand;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          child: Row(
            children: [
              Icon(icon, size: 19, color: color),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.montserrat(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: destructive ? color : AppColors.text,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.montserrat(
                          fontSize: 11,
                          color: _muted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (chevron && !destructive)
                Icon(Icons.chevron_right_rounded, size: 18, color: _muted),
            ],
          ),
        ),
      ),
    );
  }

  // Set, change or remove this conversation's nickname. Saving an empty
  // name, or Remove, brings back the real account name.
  Future<void> _editNickname(String? current) async {
    final result = await showAgriDialog<String>(
      context: context,
      builder: (_) => _NicknameDialog(current: current),
    );
    if (result == null || !mounted) return;
    // The chat listens to ConversationPrefs, so its header and placeholder
    // update by themselves — nothing to hand back through Navigator.pop.
    _prefs.setNickname(widget.conversationId, result);
  }
}

/// The nickname editor. Pops with the new nickname, '' to remove it, or
/// null when cancelled. Owns (and disposes) its own text controller.
class _NicknameDialog extends StatefulWidget {
  final String? current;

  const _NicknameDialog({required this.current});

  @override
  State<_NicknameDialog> createState() => _NicknameDialogState();
}

class _NicknameDialogState extends State<_NicknameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.current ?? '',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AgriDialog(
      icon: Icons.badge_outlined,
      title: Text(
        widget.current == null ? tl('Set nickname') : tl('Edit nickname'),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            style: const TextStyle(fontSize: 14),
            autofocus: true,
            maxLength: ConversationPrefs.nicknameMaxLength,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(hintText: tl('Nickname')),
            onSubmitted: (value) => Navigator.pop(context, value),
          ),
          const SizedBox(height: 6),
          Text(
            tl('Only you see this nickname, and only in this conversation.'),
            textAlign: TextAlign.center,
            style: GoogleFonts.montserrat(
              fontSize: 11.5,
              color: AppColors.grey(600),
            ),
          ),
        ],
      ),
      actions: [
        if (widget.current != null)
          AgriDialogButton(
            label: tl('Remove'),
            kind: AgriButtonKind.destructive,
            onPressed: () => Navigator.pop(context, ''),
          )
        else
          AgriDialogButton(
            label: tl('Cancel'),
            onPressed: () => Navigator.pop(context),
          ),
        AgriDialogButton(
          label: tl('Save'),
          kind: AgriButtonKind.primary,
          onPressed: () => Navigator.pop(context, _controller.text),
        ),
      ],
    );
  }
}
