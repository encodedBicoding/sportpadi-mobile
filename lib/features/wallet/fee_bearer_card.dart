import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/payments/payment_models.dart' show formatMoney;
import 'package:sportpadi_mobile/data/wallet/wallet_models.dart';
import 'package:sportpadi_mobile/data/wallet/wallet_repository.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_sheet.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// "Who pays the fees?" — a one-time group choice covering tickets, fines and
/// tournament entry fees (web twin: components/groups/FeeBearerCard.tsx).
/// Buyers pay by default; once chosen it locks and only support can reset it.
class FeeBearerCard extends ConsumerStatefulWidget {
  const FeeBearerCard({super.key, required this.groupId, this.disabled = false});
  final String groupId;
  final bool disabled;

  @override
  ConsumerState<FeeBearerCard> createState() => _FeeBearerCardState();
}

class _FeeBearerCardState extends ConsumerState<FeeBearerCard> {
  String? _pick;
  bool _saving = false;

  static const _titles = {
    'buyer': 'Buyers pay the fees',
    'group': 'The group pays the fees',
  };
  static const _blurbs = {
    'buyer': 'Fees are added on top of your price at checkout. You receive the full price.',
    'group': 'Buyers see and pay exactly your price. Fees come out of what you receive.',
  };

  Future<void> _confirm(FeeSetting s, String bearer) async {
    final p = context.palette;
    final ok = await showSpSheet<bool>(
      context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SpSheetHeader(
            icon: bearer == 'group' ? Icons.groups_rounded : Icons.person_rounded,
            title: '${_titles[bearer]}?',
            subtitle: 'A one-time choice',
          ),
          Text(_blurbs[bearer]!, style: TextStyle(color: p.muted, fontSize: 13, height: 1.45)),
          const SizedBox(height: 8),
          Text(
            'This applies to every new ticket, fine and tournament payment. Payments already made keep the setting they were made under.',
            style: TextStyle(color: p.muted, fontSize: 13, height: 1.45),
          ),
          const SizedBox(height: 8),
          Text(
            "You can only choose once. To change it later you'll need to contact ${s.supportEmail}.",
            style: TextStyle(color: p.ink, fontSize: 13, height: 1.45, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          SpButton(
            label: 'Confirm',
            icon: Icons.check_rounded,
            expand: true,
            onTap: () => Navigator.of(ctx).pop(true),
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(walletRepositoryProvider).setFeeBearer(widget.groupId, bearer);
      messenger.showSnackBar(const SnackBar(
          content: Text('Saved — this now applies to tickets, fines and tournament fees.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) {
        ref.invalidate(feeSettingProvider(widget.groupId));
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final async = ref.watch(feeSettingProvider(widget.groupId));
    final s = async.valueOrNull;
    if (s == null) {
      if (async.isLoading) {
        return GlassCard(
          child: Row(children: [
            const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 10),
            Text('Loading fee setting…', style: TextStyle(color: p.muted, fontSize: 13)),
          ]),
        );
      }
      return const SizedBox.shrink();
    }

    final locked = s.chosen;
    final selected = locked ? s.bearer : (_pick ?? s.bearer);
    String money(int m) => formatMoney(m, s.currency, s.currencyExponent);

    Widget option(String key) {
      final on = selected == key;
      final canTap = !locked && !widget.disabled && !_saving;
      final pays = key == 'buyer' ? s.buyerPaysIfBuyer : s.buyerPaysIfGroup;
      final gets = key == 'buyer' ? s.groupGetsIfBuyer : s.groupGetsIfGroup;
      return Opacity(
        opacity: locked && !on ? 0.5 : 1,
        child: Material(
          color: on ? p.accentTint : p.surface,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: canTap ? () => setState(() => _pick = key) : null,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: on ? p.accent : p.line, width: on ? 2 : 1),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(key == 'group' ? Icons.groups_rounded : Icons.person_rounded,
                      size: 18, color: p.ink),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_titles[key]!,
                        style: TextStyle(
                            color: p.ink, fontSize: 13.5, fontWeight: FontWeight.w800)),
                  ),
                  Icon(on ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                      size: 20, color: on ? p.accent : p.muted),
                ]),
                const SizedBox(height: 4),
                Text(_blurbs[key]!,
                    style: TextStyle(color: p.muted, fontSize: 12, height: 1.35)),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                      color: p.surface2, borderRadius: BorderRadius.circular(12)),
                  child: Text.rich(
                    TextSpan(
                      style: TextStyle(color: p.ink, fontSize: 11.5, height: 1.35),
                      children: [
                        const TextSpan(text: 'A '),
                        TextSpan(
                            text: money(s.examplePrice),
                            style: const TextStyle(fontWeight: FontWeight.w800)),
                        const TextSpan(text: ' ticket: buyer pays '),
                        TextSpan(
                            text: money(pays),
                            style: const TextStyle(fontWeight: FontWeight.w800)),
                        const TextSpan(text: ' · you receive '),
                        TextSpan(
                            text: money(gets),
                            style: const TextStyle(fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
      );
    }

    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Who pays the fees?',
                  style: TextStyle(color: p.ink, fontSize: 15, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(
                "Applies to tickets, fines and tournament entry fees. SportPadi's fee is the same either way — this only decides who covers it.",
                style: TextStyle(color: p.muted, fontSize: 12.5, height: 1.35),
              ),
            ]),
          ),
          const SizedBox(width: 10),
          locked
              ? SpBadge('Locked', icon: Icons.lock_rounded, tone: p.muted)
              : SpBadge('One-time', tone: p.orange),
        ]),
        const SizedBox(height: 14),
        option('buyer'),
        const SizedBox(height: 10),
        option('group'),
        const SizedBox(height: 12),
        if (locked)
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.mail_outline_rounded, size: 15, color: p.muted),
            const SizedBox(width: 6),
            Expanded(
              child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(
                  '${s.setAt != null ? 'Set on ${_date(s.setAt!)}. ' : ''}To change it, contact ',
                  style: TextStyle(color: p.muted, fontSize: 12),
                ),
                GestureDetector(
                  onTap: () => launchUrl(Uri.parse('mailto:${s.supportEmail}')),
                  child: Text(s.supportEmail,
                      style: TextStyle(
                          color: p.greenText, fontSize: 12, fontWeight: FontWeight.w700)),
                ),
              ]),
            ),
          ])
        else ...[
          Text('Until you choose, buyers pay the fees. You can only set this once.',
              style: TextStyle(color: p.muted, fontSize: 12)),
          const SizedBox(height: 10),
          SpButton(
            label: _saving ? 'Saving…' : 'Save choice',
            expand: true,
            onTap: widget.disabled || _saving ? null : () => _confirm(s, selected),
          ),
        ],
      ]),
    );
  }

  static String _date(DateTime d) {
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final l = d.toLocal();
    return '${l.day} ${m[l.month - 1]} ${l.year}';
  }
}
