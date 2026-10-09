import 'package:flutter/material.dart';

/// Why someone came to SportPadi — the four doors on the welcome screen.
/// Dart copy of packages/lib/src/intents.ts (keep the two in step): drives
/// the welcome cards, the sign-in hand-off, the start wizard after sign-in
/// and the first card on Home.
class IntentStep {
  const IntentStep(this.title, this.body, this.image);
  final String title;
  final String body;

  /// Visual context for the wizard slide — a bundled feature shot
  /// (assets/onboarding/<intent>-<n>.webp, resized from the web's
  /// public/features set; see packages/lib/src/intents.ts for the source).
  final String image;
}

class UserIntent {
  const UserIntent({
    required this.key,
    required this.title,
    required this.blurb,
    required this.icon,
    required this.headline,
    required this.steps,
    required this.cta,
    required this.destination,
  });

  final String key;
  final String title;
  final String blurb;
  final IconData icon;
  final String headline;
  final List<IntentStep> steps;
  final String cta;

  /// In-app route the wizard lands on — the first relevant page.
  final String destination;
}

const intents = <UserIntent>[
  UserIntent(
    key: 'play',
    title: 'Play & join a community',
    blurb: 'Find pickup games near you, join a group, check in with a scan.',
    icon: Icons.explore_rounded,
    headline: 'Your next game is three taps away',
    steps: [
      IntentStep('Find games near you',
          'Pickup football, padel, basketball and more — filtered by sport and distance, nearest first.',
          'assets/onboarding/play-1.webp'),
      IntentStep('Join the group that runs it',
          'Groups are where the regulars are. Join one and every game they run lands on your Home.',
          'assets/onboarding/play-2.webp'),
      IntentStep('RSVP and show up',
          "Tap going, get the reminder, scan the organiser's QR at the venue — attendance that counts.",
          'assets/onboarding/play-3.webp'),
      IntentStep('Build your record',
          'Streaks, levels, stats and leaderboards fill themselves from the games you actually play.',
          'assets/onboarding/play-4.webp'),
    ],
    cta: 'Find a game near me',
    destination: '/home?tab=browse',
  ),
  UserIntent(
    key: 'coach',
    title: 'Coach & manage my team',
    blurb: 'Roster, squads, line-ups and fixtures — the admin, handled.',
    icon: Icons.assignment_rounded,
    headline: 'Run your team from one place',
    steps: [
      IntentStep('Create your group',
          'Your club or academy on SportPadi: members, announcements, a schedule people actually see.',
          'assets/onboarding/coach-1.webp'),
      IntentStep('Add your team and roster',
          'Positions, captains, coaches. Invite players by link; parents accept for the younger ones.',
          'assets/onboarding/coach-2.webp'),
      IntentStep('Enter tournaments with a squad',
          'Call players up per event, see who accepted, set the line-up and formation.',
          'assets/onboarding/coach-3.webp'),
      IntentStep('Games, stats and awards',
          'Live scoring, timelines and a record for every player — the season writes itself.',
          'assets/onboarding/coach-4.webp'),
    ],
    cta: 'Create my group & team',
    destination: '/home?create=group&then=team',
  ),
  UserIntent(
    key: 'guardian',
    title: 'Onboard my child',
    blurb:
        'Add them as a ward: RSVP and pay for them, scan them in, see their games.',
    icon: Icons.child_care_rounded,
    headline: 'Their games, managed by you',
    steps: [
      IntentStep('Add your child as a ward',
          'A managed account under yours — no email or password needed for them.',
          'assets/onboarding/guardian-1.webp'),
      IntentStep('RSVP and pay on their behalf',
          'Tickets, RSVPs and team invites come to you; you accept and pay in a tap.',
          'assets/onboarding/guardian-2.webp'),
      IntentStep('Scan them in at the venue',
          'Their QR lives in your app. Show it at the gate; their attendance is recorded under their name.',
          'assets/onboarding/guardian-3.webp'),
      IntentStep('Hand the account over at 18',
          "When they're ready, they claim it with their own login and keep every stat.",
          'assets/onboarding/guardian-4.webp'),
    ],
    cta: 'Add my child',
    destination: '/profile/wards?add=1',
  ),
  UserIntent(
    key: 'host',
    title: 'Host games & tournaments',
    blurb:
        'Create a group, run events and friendlies, sell tickets, run a bracket.',
    icon: Icons.campaign_rounded,
    headline: 'From first event to full tournament',
    steps: [
      IntentStep('Create your group',
          'Public or private, with a shareable link. Members, followers and announcements come built in.',
          'assets/onboarding/host-1.webp'),
      IntentStep('Add your first event',
          'Set it to repeat, cap the players, require RSVPs — reminders do the chasing.',
          'assets/onboarding/host-2.webp'),
      IntentStep('Tickets and check-in',
          'Sell tickets or keep it free; scan players in with your QR so teams are built from who turned up.',
          'assets/onboarding/host-3.webp'),
      IntentStep('Friendlies and tournaments',
          'Balanced teams in a tap, live scoring, brackets, fixtures, officials and awards.',
          'assets/onboarding/host-4.webp'),
    ],
    cta: 'Create my group',
    destination: '/home?create=group&then=event',
  ),
];

UserIntent? intentByKey(String? key) {
  for (final i in intents) {
    if (i.key == key) return i;
  }
  return null;
}
