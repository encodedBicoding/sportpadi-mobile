import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/features/shell/home_shell.dart';
import 'package:sportpadi_mobile/data/events/event_models.dart';
import 'package:sportpadi_mobile/data/events/events_repository.dart';
import 'package:sportpadi_mobile/data/groups/group_models.dart';
import 'package:sportpadi_mobile/data/profile/profile_models.dart';
import 'package:sportpadi_mobile/data/profile/profile_repository.dart';
import 'package:sportpadi_mobile/features/groups/groups_providers.dart';
import 'package:sportpadi_mobile/features/players/aka_card.dart';
import 'package:sportpadi_mobile/features/players/player_profile_screen.dart'
    show playerStatsProvider;
import 'package:sportpadi_mobile/features/players/player_record.dart';
import 'package:sportpadi_mobile/shared/format/parse.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/crest.dart';
import 'package:sportpadi_mobile/shared/widgets/event_tile_square.dart';
import 'package:sportpadi_mobile/shared/widgets/sheet_scroll.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_header.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';
import 'package:sportpadi_mobile/features/progression/progression_widgets.dart';
import 'package:sportpadi_mobile/data/progression/progression_repository.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_sheet.dart';

/// Profile (2026) — dark pitch cover with QR / menu round buttons, identity
/// card with the avatar sitting on its edge (upload, frame, @username copy,
/// Edit profile / Public view), progression, My sports, My record, pinned
/// pill tabs (Groups / Tournaments / Events / Posts). The menu is a bottom
/// sheet: quick tab tiles, then personal pages as icon rows.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}
class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  int _tab = 0; // 0 groups, 1 tournaments, 2 events, 3 posts
  // The sport is a screen-level setting: once chosen, the record and the
  // groups / tournaments tabs all narrow to it. Same rule as the public
  // profile, so what you see here is what a scout sees of you.
  String? _catId;

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(meProvider);
    final p = context.palette;
    void openMenu(Profile profile) {
      showSpSheet<void>(
      context,
      framed: false,
      builder: (ctx) => _ProfileMenuSheet(
          profile: profile,
          onPick: (v) {
            Navigator.pop(ctx);
            // Main destinations are bottom tabs here, so they switch tabs.
            if (v.startsWith('tab:')) {
              ref.read(homeTabIndexProvider.notifier).state =
                  int.parse(v.substring(4));
            } else {
              context.push(v);
            }
          },
        ),
    );
    }

    return Scaffold(
      backgroundColor: p.bg,
      body: AsyncView(
        value: me,
        onRetry: () => ref.invalidate(meProvider),
        data: (profile) {
          if (profile == null) {
            return const Center(child: Text('No profile found.'));
          }
          final userId = profile.userId;
          final stats = userId == null
              ? null
              : ref.watch(playerStatsProvider(userId)).valueOrNull;
          final categories = listOf(stats?['categories']);
          final tournaments = listOf(stats?['tournaments']);
          final selected = _catId ?? defaultCategoryId(categories);
          final cat = categories.isEmpty
              ? null
              : categories.firstWhere(
                  (c) => parseStr(c['categoryId']) == selected,
                  orElse: () => categories.first,
                );
          final catTournaments = cat == null
              ? tournaments
              : [
                  for (final t in tournaments)
                    if (parseStr(t['categoryId']) ==
                        parseStr(cat['categoryId']))
                      t
                ];
          final sportGroupIds = <String>{
            for (final g in listOf(cat?['groups']))
              if (parseStr(g['id']) != null) parseStr(g['id'])!
          };
          final allGroups = ref.watch(myGroupsProvider).valueOrNull ??
              const <GroupSummary>[];
          final groups = sportGroupIds.isEmpty
              ? allGroups
              : [
                  for (final g in allGroups)
                    if (sportGroupIds.contains(g.id)) g
                ];
          final akas = ref.watch(myGroupAkasProvider).valueOrNull ??
              const <String, String>{};

          return RefreshIndicator(
            onRefresh: () async {
              if (userId != null) ref.invalidate(playerStatsProvider(userId));
              ref.invalidate(myGroupAkasProvider);
              return ref.refresh(meProvider.future);
            },
            child: CustomScrollView(slivers: [
              SliverList(
                  delegate: SliverChildListDelegate([
                _Hero(profile: profile, onMenu: () => openMenu(profile)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Gamification: level, streak, "Your game", achievements.
                      ProfileProgressionSection(
                        userId: userId,
                        categoryId: parseStr(cat?['categoryId']),
                        categoryNames: {
                          for (final c in categories)
                            if (parseStr(c['categoryId']) != null)
                              parseStr(c['categoryId'])!:
                                  parseStr(c['name']) ?? 'Sport',
                        },
                      ),
                      const _SportsSection(),
                      const SizedBox(height: 22),
                      const SpSectionTitle('My record'),
                      const SizedBox(height: 10),
                      if (categories.isNotEmpty) ...[
                        CategoryControl(
                          categories: categories,
                          selectedId: parseStr(cat?['categoryId']),
                          onSelect: (id) => setState(() => _catId = id),
                          playerName: profile.displayName,
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (cat == null)
                        const _EmptyNote(
                          icon: Icons.emoji_events_outlined,
                          title: 'No sports set up yet',
                          text:
                              'Add a sport above and your record for it appears here.',
                        )
                      else if (nothingOnRecord(cat))
                        NothingOnRecord(
                            sportName: parseStr(cat['name']) ?? 'this sport')
                      else ...[
                        SportSetup(category: cat),
                        const SizedBox(height: 12),
                        ScopeBlock(
                          title:
                              '${parseStr(cat['emoji']) ?? ''} ${parseStr(cat['name']) ?? 'Sport'} · local group games',
                          tally: mapOf(cat['local']),
                          fields: listOf(cat['fields']),
                          empty: 'No completed local games in this sport yet.',
                        ),
                        const SizedBox(height: 12),
                        ScopeBlock(
                          title:
                              '${parseStr(cat['emoji']) ?? ''} ${parseStr(cat['name']) ?? 'Sport'} · tournaments',
                          tally: mapOf(cat['tournament']),
                          fields: listOf(cat['fields']),
                          accent: true,
                          empty: 'No tournament games in this sport yet.',
                        ),
                      ],
                      const SizedBox(height: 18),
                    ],
                  ),
                ),
              ])),
              // Pill tabs pin while the cover scrolls away.
              SliverPersistentHeader(
                pinned: true,
                delegate: _PinnedProfileTabs(
                  child: Container(
                    color: context.palette.bg,
                    alignment: Alignment.centerLeft,
                    child: _ProfileTabs(
                        tab: _tab,
                        counts: [
                          groups.length,
                          catTournaments.length,
                          0,
                          0,
                        ],
                        onChanged: (i) => setState(() => _tab = i)),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      if (_tab == 0)
                        _MyGroupsList(
                          groups: groups,
                          akas: akas,
                          userId: userId,
                          note: sportGroupIds.isNotEmpty && cat != null
                              ? 'Groups you play ${parseStr(cat['name']) ?? 'this sport'} in.'
                              : null,
                        )
                      else if (_tab == 1)
                        TournamentList(
                          rows: catTournaments,
                          playerId: userId,
                          title: 'My tournaments',
                        )
                      else if (_tab == 2)
                        _AttendedEventsGrid(userId: userId)
                      else
                        const _EmptyNote(
                          icon: Icons.image_outlined,
                          title: 'Posts are coming',
                          text: 'Share photos from events — coming soon.',
                        ),
                    ])),
              ),
            ]),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Hero — gradient, avatar with camera upload, name/@username, edit profile.
// ---------------------------------------------------------------------------

class _Hero extends ConsumerStatefulWidget {
  const _Hero({required this.profile, required this.onMenu});
  final Profile profile;
  final VoidCallback onMenu;

  @override
  ConsumerState<_Hero> createState() => _HeroState();
}

class _HeroState extends ConsumerState<_Hero> {
  bool _uploading = false;

  Future<void> _changeAvatar() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      imageQuality: 85,
    );
    if (picked == null) return;
    setState(() => _uploading = true);
    try {
      final bytes = await picked.readAsBytes();
      final url = await ref.read(eventsRepositoryProvider).uploadImage(
            bytes,
            picked.mimeType ?? 'image/jpeg',
            assetType: 'avatar',
          );
      await ref
          .read(profileRepositoryProvider)
          .updateMe({'avatarUrl': url});
      ref.invalidate(meProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _editProfile() async {
    final saved = await showSpSheet<bool>(
      context,
      framed: false,
      builder: (_) => _EditProfileSheet(profile: widget.profile),
    );
    if (saved == true) ref.invalidate(meProvider);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final profile = widget.profile;
    final userId = profile.userId;
    final top = MediaQuery.of(context).padding.top;
    final coverH = top + 132.0;
    const avatar = 104.0;
    const cardOverlap = 34.0;
    final frame = frameColor(ref
                .watch(identityProvider(userId ?? ''))
                .valueOrNull
                ?.frame ??
            'none') ??
        p.accent;

    return Stack(clipBehavior: Clip.none, children: [
      // Cover — dark pitch, like the other 2026 headers.
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        height: coverH,
        child: ClipRRect(
          borderRadius:
              const BorderRadius.vertical(bottom: Radius.circular(32)),
          child: CustomPaint(
            painter: _ProfileCover(p.hero, p.accentDeep, p.orange),
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, top + 8, 16, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SpRoundButton(
                    icon: Icons.qr_code_2_rounded,
                    tooltip: 'My QR code',
                    onTap: () => context.push('/my-qr'),
                  ),
                  const Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(top: 11),
                      child: Text('Profile',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w800)),
                    ),
                  ),
                  SpRoundButton(
                    icon: Icons.more_horiz_rounded,
                    tooltip: 'Menu',
                    onTap: widget.onMenu,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      // Identity card.
      Padding(
        padding: EdgeInsets.fromLTRB(16, coverH - cardOverlap, 16, 0),
        child: GlassCard(
          padding: const EdgeInsets.fromLTRB(16, avatar / 2 + 12, 16, 16),
          child: Column(children: [
            Text(
              profile.displayName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: p.ink,
                fontSize: 23,
                fontWeight: FontWeight.w800,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 8),
            // Tap to copy — the username is the handle friends use to buy
            // tickets for you.
            Material(
              color: p.surface2,
              shape: const StadiumBorder(),
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: () async {
                  await Clipboard.setData(
                      ClipboardData(text: profile.username));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text(
                            'Username copied — share it so friends can buy tickets for you.')));
                  }
                },
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Flexible(
                      child: Text('@${profile.username}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: p.ink,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 6),
                    Icon(Icons.copy_rounded, size: 13, color: p.muted),
                  ]),
                ),
              ),
            ),
            if (profile.bio != null && profile.bio!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                profile.bio!,
                textAlign: TextAlign.center,
                style: TextStyle(color: p.muted, fontSize: 13.5, height: 1.5),
              ),
            ],
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: SpButton(
                  label: 'Edit profile',
                  icon: Icons.edit_outlined,
                  expand: true,
                  onTap: _editProfile,
                ),
              ),
              if (userId != null) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: _SoftPill(
                    icon: Icons.visibility_outlined,
                    label: 'Public view',
                    onTap: () => context.push('/players/$userId'),
                  ),
                ),
              ],
            ]),
          ]),
        ),
      ),
      // Avatar on the card's edge, with the earned frame and upload button.
      Positioned(
        top: coverH - cardOverlap - avatar / 2,
        left: 0,
        right: 0,
        child: Center(
          child: SizedBox(
            width: avatar,
            height: avatar,
            child: Stack(children: [
              Positioned.fill(
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: p.surface,
                    boxShadow: const [
                      BoxShadow(
                          color: Color(0x2A000000),
                          blurRadius: 18,
                          offset: Offset(0, 6)),
                    ],
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(2.5),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      // Earned avatar frame (gamification) replaces the
                      // default green ring once the player reaches Regular.
                      border: Border.all(color: frame, width: 2.5),
                    ),
                    child: ClipOval(
                      child: Crest(
                          logoUrl: profile.avatarUrl,
                          label: profile.displayName,
                          size: avatar - 16),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 0,
                bottom: 2,
                child: Material(
                  color: p.ink,
                  shape: CircleBorder(
                      side: BorderSide(color: p.surface, width: 3)),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _uploading ? null : _changeAvatar,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: _uploading
                          ? SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: p.bg))
                          : Icon(Icons.photo_camera_rounded,
                              size: 14, color: p.bg),
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    ]);
  }
}

class _ProfileCover extends CustomPainter {
  _ProfileCover(this.base, this.green, this.warm);
  final Color base;
  final Color green;
  final Color warm;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [base, Color.lerp(base, green, 0.7)!],
        ).createShader(rect),
    );
    canvas.drawCircle(
      Offset(size.width * 0.95, size.height * 1.05),
      size.height * 0.9,
      Paint()..color = warm.withAlpha(46),
    );
    final line = Paint()
      ..color = const Color(0x1FFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawLine(Offset(size.width / 2, 0),
        Offset(size.width / 2, size.height), line);
    canvas.drawCircle(Offset(size.width / 2, size.height * 0.62), 44, line);
  }

  @override
  bool shouldRepaint(covariant _ProfileCover old) =>
      old.base != base || old.green != green || old.warm != warm;
}

/// Quiet secondary pill (surface2) — the partner of the ink [SpButton].
class _SoftPill extends StatelessWidget {
  const _SoftPill(
      {required this.icon,
      required this.label,
      required this.onTap,
      this.compact = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Material(
      color: p.surface2,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
              horizontal: compact ? 12 : 14, vertical: compact ? 7 : 12),
          child: Row(
            mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: compact ? 15 : 17, color: p.ink),
              const SizedBox(width: 6),
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: p.ink,
                        fontSize: compact ? 12.5 : 14,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Sheet handle.
class _Grabber extends StatelessWidget {
  const _Grabber();
  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: context.palette.line,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );
}

/// Icon tile + title + line — the 2026 empty state.
class _EmptyNote extends StatelessWidget {
  const _EmptyNote({required this.icon, required this.text, this.title});
  final IconData icon;
  final String? title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      child: Column(children: [
        SpIconTile(icon, bg: p.surface2, fg: p.muted, size: 52, iconSize: 24),
        if (title != null) ...[
          const SizedBox(height: 12),
          Text(title!,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: p.ink, fontSize: 15, fontWeight: FontWeight.w800)),
        ],
        const SizedBox(height: 6),
        Text(text,
            textAlign: TextAlign.center,
            style: TextStyle(color: p.muted, fontSize: 13, height: 1.4)),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Menu — bottom sheet: who you are, quick tab tiles, then your pages.
// ---------------------------------------------------------------------------

class _ProfileMenuSheet extends StatelessWidget {
  const _ProfileMenuSheet({required this.profile, required this.onPick});
  final Profile profile;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget quick(String value, IconData icon, String label) => Expanded(
          child: Material(
            color: p.surface,
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => onPick(value),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Column(children: [
                  SpIconTile(icon,
                      bg: p.accentTint, fg: p.greenText, size: 40),
                  const SizedBox(height: 8),
                  Text(label,
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
          ),
        );

    Widget row(String value, IconData icon, String label, String sub,
            Color bg, Color fg) =>
        InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => onPick(value),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Row(children: [
              SpIconTile(icon, bg: bg, fg: fg, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: TextStyle(
                            color: p.ink,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700)),
                    Text(sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: p.muted, fontSize: 12)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: p.muted),
            ]),
          ),
        );

    return Container(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
      decoration: BoxDecoration(
        color: p.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: SheetScrollView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _Grabber(),
              const SizedBox(height: 16),
              Row(children: [
                ClipOval(
                  child: Crest(
                      logoUrl: profile.avatarUrl,
                      label: profile.displayName,
                      size: 46),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(profile.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: p.ink,
                              fontSize: 17,
                              fontWeight: FontWeight.w800)),
                      Text('@${profile.username}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: p.muted, fontSize: 12.5)),
                    ],
                  ),
                ),
                SpRoundButton(
                  icon: Icons.close_rounded,
                  tooltip: 'Close',
                  onTap: () => Navigator.of(context).pop(),
                ),
              ]),
              const SizedBox(height: 18),
              Row(children: [
                quick('tab:0', Icons.space_dashboard_outlined, 'Dashboard'),
                const SizedBox(width: 8),
                quick('tab:1', Icons.explore_outlined, 'Discover'),
                const SizedBox(width: 8),
                quick('tab:2', Icons.groups_outlined, 'Groups'),
              ]),
              const SizedBox(height: 18),
              const Padding(
                padding: EdgeInsets.only(left: 4, bottom: 8),
                child: Eyebrow('Check-in & payments'),
              ),
              SpListCard(children: [
                row('/scan', Icons.qr_code_scanner_rounded, 'Scan to check in',
                    'Check in at an event', p.accentTint, p.greenText),
                row('/my-qr', Icons.qr_code_2_rounded, 'My QR code',
                    'Show it at the gate', p.surface2, p.ink),
                row('/tickets', Icons.confirmation_num_outlined,
                    'My purchases', 'Tickets and passes you bought',
                    p.orangeTint, p.orangeInk),
                row('/fines', Icons.receipt_long_outlined, 'My fines',
                    'Fines from your groups', p.liveTint, p.danger),
              ]),
              const SizedBox(height: 16),
              const Padding(
                padding: EdgeInsets.only(left: 4, bottom: 8),
                child: Eyebrow('You'),
              ),
              SpListCard(children: [
                row('/notifications', Icons.notifications_outlined,
                    'Notifications', "What's new for you", p.surface2, p.ink),
                row('/settings', Icons.settings_outlined, 'Settings',
                    'Appearance, account and more', p.surface2, p.ink),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditProfileSheet extends ConsumerStatefulWidget {
  const _EditProfileSheet({required this.profile});
  final Profile profile;

  @override
  ConsumerState<_EditProfileSheet> createState() =>
      _EditProfileSheetState();
}

class _EditProfileSheetState extends ConsumerState<_EditProfileSheet> {
  late final TextEditingController _name =
      TextEditingController(text: widget.profile.displayName);
  late final TextEditingController _username =
      TextEditingController(text: widget.profile.username);
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final username = _username.text.trim().toLowerCase();
    if (name.isEmpty) {
      setState(() => _error = 'Display name is required.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(profileRepositoryProvider).updateMe({
        'displayName': name,
        if (username.isNotEmpty && username != widget.profile.username)
          'username': username,
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: BoxDecoration(
          color: p.bg,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Grabber(),
            const SizedBox(height: 16),
            Text('Edit profile',
                style: TextStyle(
                    color: p.ink,
                    fontSize: 20,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration:
                  const InputDecoration(labelText: 'Display name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _username,
              decoration: const InputDecoration(
                labelText: 'Username',
                prefixText: '@',
                helperText: 'Letters, numbers, underscores',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!,
                  style: TextStyle(color: p.danger, fontSize: 12.5)),
            ],
            const SizedBox(height: 16),
            SpButton(
              label: _busy ? 'Saving…' : 'Save',
              expand: true,
              onTap: _busy ? null : _save,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// My Sports — the web PlayerSportsStats: my sports with answers, add/edit/
// remove, fields driven by each category's statSchema.
// ---------------------------------------------------------------------------

class _SportsSection extends ConsumerWidget {
  const _SportsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final setup = ref.watch(sportsSetupProvider);
    final data = setup.valueOrNull;
    if (data == null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SpSectionTitle('My sports'),
        const SizedBox(height: 10),
        GlassCard(
          child: Text(
            setup.hasError ? 'Could not load your sports.' : 'Loading…',
            style: TextStyle(color: p.muted, fontSize: 13),
          ),
        ),
      ]);
    }
    final byId = {for (final c in data.categories) c.id: c};
    final mine = data.mine.where((m) => byId.containsKey(m.categoryId)).toList();
    final mineIds = mine.map((m) => m.categoryId).toSet();
    final others =
        data.categories.where((c) => !mineIds.contains(c.id)).toList();

    Future<void> addSport() async {
      // Web's "Add a sport" dialog, as a bottom sheet: pick from the sports
      // you haven't added yet.
      await showSpSheet<void>(
      context,
      framed: false,
      builder: (ctx) => Container(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.8),
          decoration: BoxDecoration(
            color: p.bg,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SafeArea(
            top: false,
            child: SheetScrollView(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _Grabber(),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text('Add a sport',
                        style: TextStyle(
                            color: p.ink,
                            fontSize: 20,
                            fontWeight: FontWeight.w800)),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 2, 4, 14),
                    child: Text('Pick one you play — you can set it up next.',
                        style: TextStyle(color: p.muted, fontSize: 13)),
                  ),
                  SpListCard(children: [
                    for (final c in others)
                      InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () async {
                          Navigator.pop(ctx);
                          try {
                            await ref
                                .read(profileRepositoryProvider)
                                .upsertSport(c.id, const {});
                            ref.invalidate(sportsSetupProvider);
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('$e')));
                            }
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 10),
                          child: Row(children: [
                            _EmojiTile(c.emoji),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(c.name,
                                  style: TextStyle(
                                      color: p.ink,
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w700)),
                            ),
                            SpIconTile(Icons.add_rounded,
                                bg: p.accentTint,
                                fg: p.greenText,
                                size: 32,
                                iconSize: 18),
                          ]),
                        ),
                      ),
                  ]),
                ],
              ),
            ),
          ),
        ),
    );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SpSectionTitle(
          'My sports',
          count: mine.isEmpty ? null : mine.length,
          trailing: others.isEmpty
              ? null
              : _SoftPill(
                  icon: Icons.add_rounded,
                  label: 'Add',
                  compact: true,
                  onTap: addSport,
                ),
        ),
        const SizedBox(height: 4),
        Text(
          'The sports you play. Tap one to say how you play — it helps balance teams.',
          style: TextStyle(color: p.muted, fontSize: 12.5, height: 1.4),
        ),
        const SizedBox(height: 10),
        if (mine.isEmpty)
          GlassCard(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
            child: Column(children: [
              SpIconTile(Icons.sports_soccer_rounded,
                  bg: p.accentTint, fg: p.greenText, size: 52, iconSize: 24),
              const SizedBox(height: 12),
              Text("You haven't added any sports yet.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: p.muted, fontSize: 13)),
              const SizedBox(height: 14),
              SpButton(
                label: 'Add a sport',
                icon: Icons.add_rounded,
                onTap: addSport,
              ),
            ]),
          )
        else
          for (final m in mine)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _SportRow(category: byId[m.categoryId]!, mine: m),
            ),
      ],
    );
  }
}

/// A sport's emoji on a quiet rounded tile.
class _EmojiTile extends StatelessWidget {
  const _EmojiTile(this.emoji, {this.size = 40});
  final String? emoji;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: context.palette.surface2,
          borderRadius: BorderRadius.circular(size * 0.34),
        ),
        child: Text(emoji ?? '🏅', style: TextStyle(fontSize: size * 0.48)),
      );
}

class _SportRow extends ConsumerWidget {
  const _SportRow({required this.category, required this.mine});
  final SportCategory category;
  final MySport mine;

  String _summary(StatField f) {
    final v = mine.answers[f.key];
    if (f.type == 'multi') {
      final arr = v is List ? v : const [];
      return arr.isEmpty ? '—' : arr.join(', ');
    }
    return v is String && v.isNotEmpty ? v : '—';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    return GlassCard(
      onTap: () => _edit(context, ref),
      padding: const EdgeInsets.all(14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _EmojiTile(category.emoji, size: 44),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(category.name,
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800)),
              ),
              const SizedBox(height: 6),
              if (category.fields.isEmpty)
                Text('Nothing to set up for this sport.',
                    style: TextStyle(color: p.muted, fontSize: 12))
              else
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final f in category.fields)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: p.surface2,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text.rich(
                        TextSpan(children: [
                          TextSpan(
                              text: '${f.label} · ',
                              style: TextStyle(color: p.muted)),
                          TextSpan(
                              text: _summary(f),
                              style: TextStyle(
                                  color: p.ink, fontWeight: FontWeight.w700)),
                        ]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11.5),
                      ),
                    ),
                ]),
            ],
          ),
        ),
        const SizedBox(width: 8),
        SpIconTile(Icons.edit_outlined,
            bg: p.surface2, fg: p.muted, size: 32, iconSize: 15),
      ]),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final saved = await showSpSheet<bool>(
      context,
      framed: false,
      builder: (_) => _SportEditSheet(category: category, mine: mine),
    );
    if (saved == true) ref.invalidate(sportsSetupProvider);
  }
}

class _SportEditSheet extends ConsumerStatefulWidget {
  const _SportEditSheet({required this.category, required this.mine});
  final SportCategory category;
  final MySport mine;

  @override
  ConsumerState<_SportEditSheet> createState() => _SportEditSheetState();
}

class _SportEditSheetState extends ConsumerState<_SportEditSheet> {
  late final Map<String, dynamic> _draft =
      Map<String, dynamic>.from(widget.mine.answers);
  bool _busy = false;

  void _toggle(StatField f, String option) {
    setState(() {
      if (f.type == 'multi') {
        final list = _draft[f.key] is List
            ? List<String>.from(
                (_draft[f.key] as List).map((x) => '$x'))
            : <String>[];
        if (list.contains(option)) {
          list.remove(option);
        } else {
          if (f.max != null && list.length >= f.max!) return;
          list.add(option);
        }
        _draft[f.key] = list;
      } else {
        _draft[f.key] = _draft[f.key] == option ? '' : option;
      }
    });
  }

  bool _selected(StatField f, String option) {
    final v = _draft[f.key];
    return f.type == 'multi'
        ? v is List && v.contains(option)
        : v == option;
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await ref
          .read(profileRepositoryProvider)
          .upsertSport(widget.category.id, _draft);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _remove() async {
    setState(() => _busy = true);
    try {
      await ref
          .read(profileRepositoryProvider)
          .removeSport(widget.category.id);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final c = widget.category;
    return Container(
      constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8),
      decoration: BoxDecoration(
        color: p.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
      child: ListView(
        shrinkWrap: true,
        children: [
          const _Grabber(),
          const SizedBox(height: 16),
          Row(children: [
            _EmojiTile(c.emoji, size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Text(c.name,
                  style: TextStyle(
                      color: p.ink,
                      fontSize: 19,
                      fontWeight: FontWeight.w800)),
            ),
            InkWell(
              onTap: _busy ? null : _remove,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Text('Remove',
                    style: TextStyle(
                        color: p.danger,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600)),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          if (c.fields.isEmpty)
            Text('Nothing to set up for this sport.',
                style: TextStyle(color: p.muted, fontSize: 13))
          else
            for (final f in c.fields) ...[
              Text(
                f.type == 'multi' && f.max != null
                    ? '${f.label} (up to ${f.max})'
                    : f.label,
                style: TextStyle(
                    color: p.muted,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final o in f.options)
                  Material(
                    color: _selected(f, o) ? p.ink : p.surface,
                    borderRadius: BorderRadius.circular(999),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () => _toggle(f, o),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                              color: _selected(f, o)
                                  ? p.ink
                                  : p.line),
                        ),
                        child: Text(o,
                            style: TextStyle(
                              color: _selected(f, o)
                                  ? p.bg
                                  : p.ink,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            )),
                      ),
                    ),
                  ),
              ]),
              const SizedBox(height: 14),
            ],
          SpButton(
            label: _busy ? 'Saving…' : 'Save',
            expand: true,
            onTap: _busy ? null : _save,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tabs — Events / Posts / Groups (web profile tabs replica).
// ---------------------------------------------------------------------------

class _ProfileTabs extends StatelessWidget {
  const _ProfileTabs({
    required this.tab,
    required this.onChanged,
    this.counts = const [0, 0, 0, 0],
  });
  final int tab;
  final ValueChanged<int> onChanged;
  final List<int> counts;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget pill(int i, IconData icon, String label) {
      final active = tab == i;
      final count = i < counts.length ? counts[i] : 0;
      final fg = active ? p.bg : p.ink;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Material(
          color: active ? p.ink : p.surface,
          shape: StadiumBorder(
              side: active ? BorderSide.none : BorderSide(color: p.line)),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: () => onChanged(i),
            child: Padding(
              padding: EdgeInsets.fromLTRB(12, 8, count > 0 ? 8 : 14, 8),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 16, color: active ? p.bg : p.muted),
                const SizedBox(width: 6),
                Text(label,
                    style: TextStyle(
                        color: fg, fontSize: 13, fontWeight: FontWeight.w700)),
                if (count > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    constraints: const BoxConstraints(minWidth: 22),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: active ? const Color(0x33FFFFFF) : p.surface2,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text('$count',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: active ? p.bg : p.muted,
                            fontSize: 11,
                            fontWeight: FontWeight.w800)),
                  ),
                ],
              ]),
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        pill(0, Icons.groups_outlined, 'Groups'),
        pill(1, Icons.emoji_events_outlined, 'Tournaments'),
        pill(2, Icons.calendar_month_outlined, 'Events'),
        pill(3, Icons.image_outlined, 'Posts'),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Attended events grid — square tiles like the web EventTile.
// ---------------------------------------------------------------------------

class _AttendedEventsGrid extends ConsumerWidget {
  const _AttendedEventsGrid({this.userId});

  /// Whose record an event opens. Without it, tiles open the event itself.
  final String? userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final events = ref.watch(attendedEventsProvider);
    final list = events.valueOrNull ?? const <EventSummary>[];
    if (events.isLoading) {
      return GlassCard(
          child: Text('Loading…',
              style: TextStyle(color: p.muted, fontSize: 13)));
    }
    if (list.isEmpty) {
      return const _EmptyNote(
        icon: Icons.calendar_month_outlined,
        text: 'No events attended yet.',
      );
    }
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      children: [
        // Your record in that event — not the event's scoresheet. The event
        // itself is one deliberate tap further, inside.
        for (final e in list)
          EventTileSquare(
            event: e,
            onTap: userId == null
                ? null
                : () => context.push(e.isTournament
                    ? '/players/$userId/tournaments/${e.id}'
                    : '/players/$userId/events/${e.id}'),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// My groups grid — crest, name, member count, role badge.
// ---------------------------------------------------------------------------

/// Your groups, each opening YOUR record in that group — where you also set
/// the name that group knows you by. The group itself stays one tap away, as
/// the chip on the right.
class _MyGroupsList extends StatelessWidget {
  const _MyGroupsList({
    required this.groups,
    required this.akas,
    required this.userId,
    this.note,
  });

  final List<GroupSummary> groups;
  final Map<String, String> akas;
  final String? userId;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    if (groups.isEmpty) {
      return const _EmptyNote(
        icon: Icons.groups_outlined,
        text: "You're not in any groups yet.",
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (note != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 4),
          child: Text(note!, style: TextStyle(color: p.muted, fontSize: 12)),
        ),
      SpListCard(children: [
        for (final g in groups)
          InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: userId == null
                ? null
                : () => context.push('/players/$userId/groups/${g.id}'),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              child: Row(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Crest(logoUrl: g.logoUrl, label: g.name, size: 44),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Flexible(
                          child: Text(g.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: p.ink,
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w700)),
                        ),
                        if (g.role == 'admin') ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: p.accentTint,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text('Admin',
                                style: TextStyle(
                                    color: p.greenText,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ]),
                      const SizedBox(height: 2),
                      Text(
                          akas[g.id] != null
                              ? 'Known here as ${akas[g.id]}'
                              : 'See your record here',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: p.muted, fontSize: 12)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // The group itself, one tap away.
                Material(
                  color: p.surface2,
                  shape: const StadiumBorder(),
                  child: InkWell(
                    customBorder: const StadiumBorder(),
                    onTap: () => context.push('/groups/${g.id}'),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text('Group',
                            style: TextStyle(
                                color: p.ink,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(width: 2),
                        Icon(Icons.north_east_rounded,
                            size: 12, color: p.ink),
                      ]),
                    ),
                  ),
                ),
              ]),
            ),
          ),
      ]),
    ]);
  }
}

/// Pins the profile tab row to the top of the scroll view.
class _PinnedProfileTabs extends SliverPersistentHeaderDelegate {
  const _PinnedProfileTabs({required this.child});
  final Widget child;

  static const double _height = 56;

  @override
  double get minExtent => _height;
  @override
  double get maxExtent => _height;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return SizedBox(height: _height, child: child);
  }

  @override
  bool shouldRebuild(covariant _PinnedProfileTabs oldDelegate) =>
      oldDelegate.child != child;
}
