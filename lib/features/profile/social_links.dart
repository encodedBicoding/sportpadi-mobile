import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/network/dio_client.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/profile/profile_repository.dart';
import 'package:sportpadi_mobile/shared/format/parse.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_header.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';
import 'package:sportpadi_mobile/core/i18n/l10n.dart';

/// A player's social links (docs/design/scouting-profile.md § Social links).
/// Web twin: components/profile/SocialLinks.tsx. Any platform can be added:
/// the known ones take a handle or a link and the server normalises them to
/// the profile URL; anything else is a labelled https link.

/// Platform → (name, short badge). Must match packages/lib/src/socialLinks.ts.
Map<String, (String, String)> get kSocialPlatforms => <String, (String, String)>{
  'instagram': ('Instagram', 'IG'),
  'tiktok': ('TikTok', 'TT'),
  'x': ('X', 'X'),
  'facebook': ('Facebook', 'f'),
  'threads': ('Threads', '@'),
  'youtube': ('YouTube', 'YT'),
  'snapchat': ('Snapchat', 'SC'),
  'linkedin': ('LinkedIn', 'in'),
  'twitch': ('Twitch', 'TW'),
  'other': (l10n.profile_otherLink, '↗'),
};
const kMaxSocialLinks = 10;

class SocialLink {
  const SocialLink(
      {required this.platform, required this.url, required this.label});
  final String platform;
  final String url;
  final String label;

  String get platformName => kSocialPlatforms[platform]?.$1 ?? l10n.profile_link;

  static List<SocialLink> listFrom(dynamic v) => [
        if (v is List)
          for (final e in v)
            if (e is Map && parseStr(e['url']) != null)
              SocialLink(
                platform: kSocialPlatforms.containsKey(e['platform'])
                    ? e['platform'] as String
                    : 'other',
                url: e['url'] as String,
                label: parseStr(e['label']) ??
                    (kSocialPlatforms[e['platform']]?.$1 ?? l10n.profile_link),
              ),
      ];
}

class PlatformBadge extends StatelessWidget {
  const PlatformBadge(this.platform, {super.key, this.size = 22});
  final String platform;
  final double size;
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
          color: p.ink, borderRadius: BorderRadius.circular(size * 0.32)),
      child: Text(kSocialPlatforms[platform]?.$2 ?? '↗',
          style: TextStyle(
              color: p.bg, fontSize: 10, fontWeight: FontWeight.w800)),
    );
  }
}

/// The chips on a profile. Nothing when there are no links.
class SocialLinksRow extends StatelessWidget {
  const SocialLinksRow(this.links, {super.key});
  final List<SocialLink> links;
  @override
  Widget build(BuildContext context) {
    if (links.isEmpty) return const SizedBox.shrink();
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final l in links)
            Material(
              color: p.surface2,
              shape: const StadiumBorder(),
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: () => launchUrl(Uri.parse(l.url),
                    mode: LaunchMode.externalApplication),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    PlatformBadge(l.platform),
                    const SizedBox(width: 6),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 150),
                      child: Text(l.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: p.ink,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                    ),
                  ]),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Opens the editor; resolves true when links were saved.
Future<bool> showSocialLinksEditor(BuildContext context,
    {required List<SocialLink> links}) async {
  final r = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _SocialLinksSheet(initial: links),
  );
  return r == true;
}

class _Draft {
  _Draft({required this.platform, required this.value, this.label = ''});
  String platform;
  String value;
  String label;
}

class _SocialLinksSheet extends ConsumerStatefulWidget {
  const _SocialLinksSheet({required this.initial});
  final List<SocialLink> initial;
  @override
  ConsumerState<_SocialLinksSheet> createState() => _SocialLinksSheetState();
}

class _SocialLinksSheetState extends ConsumerState<_SocialLinksSheet> {
  late final List<_Draft> _rows = [
    for (final l in widget.initial)
      _Draft(
          platform: l.platform,
          value: l.platform == 'other'
              ? l.url
              : (l.label.startsWith('@') ? l.label : l.url),
          label: l.platform == 'other' ? l.label : ''),
  ];
  String _platform = 'instagram';
  final _value = TextEditingController();
  final _label = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _value.dispose();
    _label.dispose();
    super.dispose();
  }

  void _add() {
    final v = _value.text.trim();
    if (v.isEmpty) return;
    if (_rows.length >= kMaxSocialLinks) {
      setState(() => _error = context.l10n.profile_upToLinks2(kMaxSocialLinks));
      return;
    }
    setState(() {
      _rows.add(_Draft(platform: _platform, value: v, label: _label.text.trim()));
      _value.clear();
      _label.clear();
      _error = null;
    });
  }

  Future<void> _save() async {
    // Whatever is still in the add box goes too, so Save never loses it.
    if (_value.text.trim().isNotEmpty) _add();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(dioProvider).post('/api/mobile/me', data: {
        'action': 'set-links',
        'links': [
          for (final d in _rows)
            {
              'platform': d.platform,
              'value': d.value,
              if (d.label.isNotEmpty) 'label': d.label,
            }
        ],
      });
      ref.invalidate(meProvider);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = apiError(e, fallback: l10n.profile_couldNotSave).message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final isOther = _platform == 'other';
    final host = switch (_platform) {
      'instagram' => 'instagram.com',
      'tiktok' => 'tiktok.com',
      'x' => 'x.com',
      'facebook' => 'facebook.com',
      'threads' => 'threads.net',
      'youtube' => 'youtube.com',
      'snapchat' => 'snapchat.com',
      'linkedin' => 'linkedin.com',
      'twitch' => 'twitch.tv',
      _ => '',
    };
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: BoxDecoration(
          color: p.bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: p.line, borderRadius: BorderRadius.circular(2))),
              ),
              const SizedBox(height: 16),
              Text(context.l10n.profile_socialLinks,
                  style: TextStyle(
                      color: p.ink, fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                  context.l10n.profile_shownOnYourPublicProfile2,
                  style: TextStyle(color: p.muted, fontSize: 12.5)),
              const SizedBox(height: 14),
              if (_rows.isNotEmpty)
                GlassCard(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  child: Column(children: [
                    for (var i = 0; i < _rows.length; i++) ...[
                      if (i > 0) Divider(height: 1, color: p.line),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(children: [
                          PlatformBadge(_rows[i].platform, size: 26),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                    _rows[i].platform == 'other'
                                        ? (_rows[i].label.isNotEmpty
                                            ? _rows[i].label
                                            : _rows[i].value)
                                        : _rows[i].value,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: p.ink,
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w600)),
                                Text(
                                    _rows[i].platform == 'other'
                                        ? _rows[i].value
                                        : kSocialPlatforms[_rows[i].platform]!.$1,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: p.muted, fontSize: 11.5)),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: context.l10n.profile_remove,
                            icon: Icon(Icons.delete_outline_rounded,
                                size: 20, color: p.muted),
                            onPressed: () => setState(() => _rows.removeAt(i)),
                          ),
                        ]),
                      ),
                    ],
                  ]),
                ),
              if (_rows.length < kMaxSocialLinks) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _platform,
                  decoration: InputDecoration(labelText: context.l10n.profile_platform),
                  items: [
                    for (final e in kSocialPlatforms.entries)
                      DropdownMenuItem(value: e.key, child: Text(e.value.$1)),
                  ],
                  onChanged: (v) => setState(() => _platform = v ?? 'instagram'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _value,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  textCapitalization: TextCapitalization.none,
                  decoration: InputDecoration(
                    labelText: isOther ? context.l10n.profile_link : context.l10n.profile_handleOrLink2,
                    hintText: isOther ? 'https://…' : context.l10n.profile_handleOrLink3(host),
                  ),
                  onSubmitted: (_) => _add(),
                ),
                if (isOther) ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: _label,
                    maxLength: 40,
                    decoration: InputDecoration(
                        labelText: context.l10n.profile_label, hintText: context.l10n.profile_hudlLinktreeMySite, counterText: ''),
                  ),
                ],
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _add,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: Text(context.l10n.profile_add),
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 4),
                Text(_error!, style: TextStyle(color: p.danger, fontSize: 12.5)),
              ],
              const SizedBox(height: 12),
              SpButton(
                label: _busy ? context.l10n.profile_saving : context.l10n.profile_saveLinks,
                expand: true,
                onTap: _busy ? null : _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// /profile/links — the editor as its own page (web /profile/links twin).
class SocialLinksScreen extends ConsumerWidget {
  const SocialLinksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final me = ref.watch(meProvider).valueOrNull;
    final links = SocialLink.listFrom(me?.links);
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: SpHeader(title: context.l10n.profile_socialLinks),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
              children: [
                Text(
                    context.l10n.profile_wherePeopleCanFindYou,
                    style: TextStyle(color: p.muted, fontSize: 13.5, height: 1.45)),
                const SizedBox(height: 16),
                if (links.isEmpty)
                  GlassCard(
                    child: Column(children: [
                      Icon(Icons.link_rounded, size: 28, color: p.muted),
                      const SizedBox(height: 8),
                      Text(context.l10n.profile_noLinksYet,
                          style: TextStyle(
                              color: p.ink, fontSize: 15, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(context.l10n.profile_instagramTikTokXFacebookThreads2,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: p.muted, fontSize: 12.5)),
                    ]),
                  )
                else
                  GlassCard(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    child: Column(children: [
                      for (var i = 0; i < links.length; i++) ...[
                        if (i > 0) Divider(height: 1, color: p.line),
                        InkWell(
                          onTap: () => launchUrl(Uri.parse(links[i].url),
                              mode: LaunchMode.externalApplication),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Row(children: [
                              PlatformBadge(links[i].platform, size: 28),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(links[i].label,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            color: p.ink,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700)),
                                    Text(links[i].platformName,
                                        style: TextStyle(color: p.muted, fontSize: 12)),
                                  ],
                                ),
                              ),
                              Icon(Icons.open_in_new_rounded, size: 16, color: p.muted),
                            ]),
                          ),
                        ),
                      ],
                    ]),
                  ),
                const SizedBox(height: 14),
                SpButton(
                  label: links.isEmpty ? context.l10n.profile_addLinks : context.l10n.profile_editLinks,
                  icon: Icons.edit_outlined,
                  expand: true,
                  onTap: () => showSocialLinksEditor(context, links: links),
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}
