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
import 'package:sportpadi_mobile/shared/widgets/ui.dart';
import 'package:sportpadi_mobile/features/progression/progression_widgets.dart';
import 'package:sportpadi_mobile/data/progression/progression_repository.dart';

/// Profile — the web profile page's mobile twin: gradient hero with avatar
/// upload, My Sports editor, Events / Posts / Groups tabs, and the menu.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

PopupMenuItem<String> _menuItem(String value, IconData icon, String label) {
  return PopupMenuItem(
    value: value,
    child: Row(children: [
      Icon(icon, size: 18),
      const SizedBox(width: 10),
      Text(label),
    ]),
  );
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
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false, // bottom-nav tab, not a pushed page
        backgroundColor: p.bg,
        surfaceTintColor: p.bg,
        title: const Text('Profile',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        actions: [
          // Same menu as the web profile: main destinations first (those are
          // bottom tabs here, so they switch tabs), then personal pages.
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, size: 22),
            onSelected: (v) {
              if (v.startsWith('tab:')) {
                ref.read(homeTabIndexProvider.notifier).state =
                    int.parse(v.substring(4));
              } else {
                context.push(v);
              }
            },
            itemBuilder: (_) => [
              _menuItem('tab:0', Icons.space_dashboard_outlined, 'Dashboard'),
              _menuItem('tab:1', Icons.explore_outlined, 'Discover'),
              _menuItem('tab:2', Icons.groups_outlined, 'Groups'),
              _menuItem('/scan', Icons.qr_code_scanner_rounded, 'Scan to check in'),
              _menuItem('/fines', Icons.receipt_long_outlined, 'My fines'),
              const PopupMenuDivider(),
              _menuItem('/tickets', Icons.confirmation_num_outlined, 'My purchases'),
              _menuItem('/my-qr', Icons.qr_code_2_rounded, 'My QR code'),
              _menuItem('/notifications', Icons.notifications_outlined, 'Notifications'),
              _menuItem('/settings', Icons.settings_outlined, 'Settings'),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
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
                _Hero(profile: profile),
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
                      const Eyebrow('My sports'),
                      const SizedBox(height: 8),
                      const _SportsSection(),
                      const SizedBox(height: 18),
                      Row(children: [
                        const Eyebrow('My record'),
                        const Spacer(),
                        if (userId != null)
                          InkWell(
                            onTap: () => context.push('/players/$userId'),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Text('View as others see it',
                                  style: TextStyle(
                                      color: p.accent,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700)),
                              Icon(Icons.north_east_rounded,
                                  size: 12, color: p.accent),
                            ]),
                          ),
                      ]),
                      const SizedBox(height: 8),
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
                        GlassCard(
                          padding: const EdgeInsets.all(20),
                          child: Column(children: [
                            Icon(Icons.emoji_events_outlined,
                                size: 30, color: p.muted),
                            const SizedBox(height: 8),
                            Text('No sports set up yet',
                                style: TextStyle(
                                    color: p.ink,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            Text(
                              'Add a sport above and your record for it appears here.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: p.muted, fontSize: 12, height: 1.35),
                            ),
                          ]),
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
              // Events / Posts / Groups pins while the hero scrolls away.
              SliverPersistentHeader(
                pinned: true,
                delegate: _PinnedProfileTabs(
                  child: Container(
                    color: context.palette.bg,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
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
                          title: 'MY TOURNAMENTS',
                        )
                      else if (_tab == 2)
                        _AttendedEventsGrid(userId: userId)
                      else
                        GlassCard(
                          child: Center(
                            child: Text(
                              'Share photos from events — coming soon.',
                              style: TextStyle(
                                  color: context.palette.muted, fontSize: 13),
                            ),
                          ),
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
  const _Hero({required this.profile});
  final Profile profile;

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
    final saved = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _EditProfileSheet(profile: widget.profile),
    );
    if (saved == true) ref.invalidate(meProvider);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final profile = widget.profile;
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.fromRGBO(23, 166, 94, 0.18),
            Color.fromRGBO(235, 240, 237, 1.0),
            Color.fromRGBO(245, 167, 10, 0.12),
          ],
        ),
        border: Border(
          bottom: BorderSide(color: Color.fromRGBO(211, 218, 223, 0.7)),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
      child: Column(
        children: [
          SizedBox(
            width: 112,
            height: 112,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Container(
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Color.fromRGBO(23, 166, 94, 0.35),
                          blurRadius: 22,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 6,
                  top: 6,
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: p.surface,
                      // Earned avatar frame (gamification) replaces the
                      // default green ring once the player reaches Regular.
                      border: Border.all(
                          color: frameColor(ref
                                      .watch(identityProvider(profile.userId ?? ''))
                                      .valueOrNull
                                      ?.frame ??
                                  'none') ??
                              const Color.fromRGBO(23, 166, 94, 0.45),
                          width: 2.5),
                    ),
                    child: ClipOval(
                      child: Crest(
                          logoUrl: profile.avatarUrl,
                          label: profile.displayName,
                          size: 100),
                    ),
                  ),
                ),
                Positioned(
                  right: 2,
                  bottom: 2,
                  child: Material(
                    color: p.accent,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _uploading ? null : _changeAvatar,
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: _uploading
                            ? const SizedBox(
                                width: 15,
                                height: 15,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white))
                            : const Icon(Icons.photo_camera_rounded,
                                size: 15, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  profile.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: p.ink,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              InkWell(
                onTap: _editProfile,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child:
                      Icon(Icons.edit_outlined, size: 16, color: p.muted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          // Tap to copy — the username is the handle friends use to buy
          // tickets for you.
          InkWell(
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: profile.username));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text(
                        'Username copied — share it so friends can buy tickets for you.')));
              }
            },
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('@${profile.username}',
                    style: TextStyle(color: p.muted, fontSize: 13.5)),
                const SizedBox(width: 4),
                Icon(Icons.copy_rounded, size: 13, color: p.muted),
              ]),
            ),
          ),
          if (profile.bio != null && profile.bio!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              profile.bio!,
              textAlign: TextAlign.center,
              style:
                  TextStyle(color: p.muted, fontSize: 13.5, height: 1.5),
            ),
          ],
        ],
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
              const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Edit profile',
                style: TextStyle(
                    color: p.ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
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
      return GlassCard(
        child: Text(
          setup.hasError ? 'Could not load your sports.' : 'Loading…',
          style: TextStyle(color: p.muted, fontSize: 13),
        ),
      );
    }
    final byId = {for (final c in data.categories) c.id: c};
    final mine = data.mine.where((m) => byId.containsKey(m.categoryId)).toList();
    final mineIds = mine.map((m) => m.categoryId).toSet();
    final others =
        data.categories.where((c) => !mineIds.contains(c.id)).toList();

    Future<void> addSport() async {
      // Web's "Add a sport" dialog, as a bottom sheet: pick from the sports
      // you haven't added yet.
      await showModalBottomSheet<void>(
        context: context,
        builder: (ctx) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                child: Text('Add a sport',
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w800)),
              ),
              for (final c in others)
                ListTile(
                  leading: Text(c.emoji ?? '🏅',
                      style: const TextStyle(fontSize: 20)),
                  title: Text(c.name),
                  trailing: Icon(Icons.add_rounded, color: p.accent),
                  onTap: () async {
                    Navigator.pop(ctx);
                    try {
                      await ref
                          .read(profileRepositoryProvider)
                          .upsertSport(c.id, const {});
                      ref.invalidate(sportsSetupProvider);
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text('$e')));
                      }
                    }
                  },
                ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Web-style header: hint + "+ Add" button.
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Text(
              'The sports you play. Tap a card to say how you play — it helps balance teams.',
              style: TextStyle(color: p.muted, fontSize: 12),
            ),
          ),
          if (others.isNotEmpty) ...[
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: addSport,
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('Add'),
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
            ),
          ],
        ]),
        const SizedBox(height: 8),
        if (mine.isEmpty)
          GlassCard(
            padding: const EdgeInsets.all(20),
            child: Column(children: [
              Text("You haven't added any sports yet.",
                  style: TextStyle(color: p.muted, fontSize: 13)),
              const SizedBox(height: 10),
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
              padding: const EdgeInsets.only(bottom: 8),
              child: _SportRow(category: byId[m.categoryId]!, mine: m),
            ),
      ],
    );
  }
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(category.emoji ?? '🏅',
                style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(category.name,
                  style: TextStyle(
                      color: p.ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w700)),
            ),
            Icon(Icons.edit_outlined, size: 15, color: p.muted),
          ]),
          if (category.fields.isNotEmpty) ...[
            const SizedBox(height: 6),
            for (final f in category.fields)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(children: [
                  Text('${f.label}: ',
                      style:
                          TextStyle(color: p.muted, fontSize: 12)),
                  Expanded(
                    child: Text(_summary(f),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: p.ink,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ),
                ]),
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
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
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
      child: ListView(
        shrinkWrap: true,
        children: [
          Row(children: [
            Text(c.emoji ?? '🏅', style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(c.name,
                  style: TextStyle(
                      color: p.ink,
                      fontSize: 17,
                      fontWeight: FontWeight.w700)),
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
          const SizedBox(height: 12),
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
                    color: _selected(f, o) ? p.accent : p.surface,
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
                                  ? p.accent
                                  : p.line),
                        ),
                        child: Text(o,
                            style: TextStyle(
                              color: _selected(f, o)
                                  ? Colors.white
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
    Widget btn(int i, IconData icon, String label) {
      final active = tab == i;
      final count = i < counts.length ? counts[i] : 0;
      return Expanded(
        child: InkWell(
          onTap: () => onChanged(i),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: active ? p.accent : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 15, color: active ? p.accent : p.muted),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: active ? p.accent : p.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      )),
                ),
                if (count > 0) ...[
                  const SizedBox(width: 3),
                  Text('$count',
                      style: TextStyle(
                          color: active
                              ? p.accent.withAlpha(180)
                              : p.muted.withAlpha(180),
                          fontSize: 11)),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.line)),
      ),
      child: Row(children: [
        btn(0, Icons.groups_outlined, 'Groups'),
        btn(1, Icons.emoji_events_outlined, 'Tournaments'),
        btn(2, Icons.calendar_month_outlined, 'Events'),
        btn(3, Icons.image_outlined, 'Posts'),
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
      return GlassCard(
        child: Center(
          child: Text('No events attended yet.',
              style: TextStyle(color: p.muted, fontSize: 13)),
        ),
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
      return GlassCard(
        child: Center(
          child: Text("You're not in any groups yet.",
              style: TextStyle(color: p.muted, fontSize: 13)),
        ),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (note != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 6, left: 2),
          child: Text(note!, style: TextStyle(color: p.muted, fontSize: 11)),
        ),
      for (final g in groups)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: p.line),
            ),
            child: Row(children: [
              Expanded(
                child: InkWell(
                  onTap: userId == null
                      ? null
                      : () => context.push('/players/$userId/groups/${g.id}'),
                  child: Row(children: [
                    ClipOval(
                      child:
                          Crest(logoUrl: g.logoUrl, label: g.name, size: 32),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(children: [
                              Flexible(
                                child: Text(g.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: p.ink,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600)),
                              ),
                              if (g.role == 'admin')
                                Padding(
                                  padding: const EdgeInsets.only(left: 4),
                                  child: Icon(Icons.verified_user_outlined,
                                      size: 13, color: p.accent),
                                ),
                            ]),
                            Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.bar_chart_rounded,
                                  size: 12, color: p.muted),
                              const SizedBox(width: 3),
                              Flexible(
                                child: Text(
                                    akas[g.id] != null
                                        ? 'Known here as ${akas[g.id]}'
                                        : 'See your record here',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: p.muted, fontSize: 11)),
                              ),
                            ]),
                          ]),
                    ),
                    Icon(Icons.chevron_right_rounded, size: 18, color: p.muted),
                  ]),
                ),
              ),
              const SizedBox(width: 6),
              InkWell(
                onTap: () => context.push('/groups/${g.id}'),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: p.line),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('Group',
                        style: TextStyle(
                            color: p.muted,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700)),
                    Icon(Icons.north_east_rounded, size: 11, color: p.muted),
                  ]),
                ),
              ),
            ]),
          ),
        ),
    ]);
  }
}

/// Pins the profile tab row to the top of the scroll view.
class _PinnedProfileTabs extends SliverPersistentHeaderDelegate {
  const _PinnedProfileTabs({required this.child});
  final Widget child;

  static const double _height = 42;

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
