import 'package:flutter/material.dart';

/// One drawer destination. `figma` and `plan` describe screens that are still
/// placeholders, so whoever picks a screen up knows what to build.
class NavItem {
  const NavItem({
    required this.path,
    required this.label,
    required this.icon,
    this.figma = const [],
    this.plan = const [],
    this.backend = const [],
  });

  final String path;
  final String label;
  final IconData icon;
  final List<String> figma;
  final List<String> plan;
  final List<String> backend;
}

class NavSection {
  const NavSection(this.title, this.items);
  final String title;
  final List<NavItem> items;
}

const browseItem = NavItem(path: '/browse', label: 'Browse Competitions', icon: Icons.grid_view_rounded);

const studentNav = [
  NavSection('Discover', [
    browseItem,
    NavItem(
      path: '/submit',
      label: 'Submit Competition',
      icon: Icons.add_rounded,
      figma: ['15 · Submit Competition', '16 · Submitted · Pending Validation'],
      plan: [
        'Form: name, organizer, category, level, deadline, team size, link, description',
        'Upload poster/guidebook to storage bucket competition-proofs/<competition_id>/',
        'Run AI duplicate check; show "Possible duplicate found" card with reason chips',
        'Submit anyway with a reason; Student Affairs sees the flag',
      ],
      backend: ['insert competitions (draft)', 'fn check-duplicate', 'rpc submit_competition'],
    ),
    NavItem(
      path: '/lobbies',
      label: 'My Lobbies',
      icon: Icons.groups_rounded,
      figma: ['06 · Lobby · Manage Broadcast', '07 · AI Teammate Recommendations', '08 · Find Teammates', '09 · Team Locked'],
      plan: [
        'Team slots, join requests (approve/decline), team balance check',
        'H-3 / H-2 banner: auto-locks H-1 23:59 WIB even if not full',
        '"Lock team now" (no unlock; pending requests get auto-rejected)',
        'AI recommendations with "Why" reasons; fallback "Skill yang dibutuhkan belum diatur"',
        'Direct invite modal (slot reserved 48h)',
      ],
      backend: [
        'rpc create_team / decide_join_request / send_invite / lock_team',
        'fn infer-skills + rpc recommend_candidates',
      ],
    ),
    NavItem(
      path: '/invites',
      label: 'Invites',
      icon: Icons.mail_outline_rounded,
      plan: ['Pending invites with 48h countdown', 'Accept / decline', 'My join requests (cancel)'],
      backend: ['select team_invites / join_requests', 'rpc respond_invite / cancel_join_request'],
    ),
  ]),
  NavSection('My Team', [
    NavItem(
      path: '/team/chat',
      label: 'Team Chat',
      icon: Icons.chat_bubble_outline_rounded,
      figma: ['11 · Team Chat'],
      plan: ['Realtime messages + attachments', 'Pinned meeting', 'Team info side sheet'],
      backend: ['realtime messages', 'storage chat-attachments/<team_id>/', 'team_meetings'],
    ),
    NavItem(
      path: '/team/calendar',
      label: 'Team Calendar',
      icon: Icons.calendar_month_rounded,
      figma: ['10 · Team Calendar · Shared Availability'],
      plan: ['Weekly heatmap of free members', 'Best slots this week', 'Edit my availability'],
      backend: ['rpc team_availability_heatmap', 'availability_slots'],
    ),
    NavItem(
      path: '/team/rate',
      label: 'Rate & Claim SEP',
      icon: Icons.workspace_premium_outlined,
      figma: ['12 · Rate Teammates', '13 · Upload Result · SEP Claim', '14 · SEP Claim Submitted'],
      plan: [
        'Rate each teammate: hard-skill tiers + soft-skill stars (one reputation score)',
        'Unlock checklist, upload certificate, SEP estimate',
      ],
      backend: ['rpc my_rating_progress / submit_rating', 'rpc sep_claim_blockers / submit_sep_claim'],
    ),
    NavItem(
      path: '/reports',
      label: 'Reports & Appeals',
      icon: Icons.flag_outlined,
      figma: ['18 · Report a Member', '19 · Reports & Appeals'],
      plan: ['Fact-based report with evidence', 'Reports about me + 7-day appeal'],
      backend: ['rpc file_report / reports_about_me / submit_appeal', 'storage report-evidence/'],
    ),
  ]),
];

const adminNav = [
  NavSection('Student Affairs', [
    NavItem(
      path: '/admin',
      label: 'Dashboard',
      icon: Icons.space_dashboard_outlined,
      figma: ['17 · Admin · Student Affairs Dashboard'],
      plan: ['KPIs: time-to-team, cross-major %, retention, SEP credited', 'Queues summary'],
      backend: ['rpc admin_dashboard_stats'],
    ),
    NavItem(
      path: '/admin/competitions',
      label: 'Competition Queue',
      icon: Icons.fact_check_outlined,
      figma: ['17 · validation queue'],
      plan: ['Pending submissions with proof files', 'Possible-duplicate flag + override reason', 'Approve / reject'],
      backend: ['select competitions where status = pending', 'rpc admin_review_competition'],
    ),
    NavItem(
      path: '/admin/reports',
      label: 'Reports & Appeals',
      icon: Icons.gavel_rounded,
      figma: ['20 · Admin · Report & Appeal Review'],
      plan: ['Report vs appeal side by side', 'Context: reputation, prior reports', 'Uphold / dismiss / request info'],
      backend: ['select reports + report_evidence', 'rpc admin_decide_report'],
    ),
    NavItem(
      path: '/admin/sep',
      label: 'SEP Claims',
      icon: Icons.verified_outlined,
      plan: ['Verify certificate', 'Confirm points per member'],
      backend: ['select sep_claims + sep_claim_files', 'rpc admin_verify_sep_claim'],
    ),
  ]),
  NavSection('Discover', [browseItem]),
];

const onboardingItem = NavItem(
  path: '/onboarding',
  label: 'Set Up Skill Profile',
  icon: Icons.person_outline_rounded,
  figma: ['03 · Set Up Skill Profile'],
  plan: ['Faculty/program + batch', 'Hard skills with level, soft skills', 'Availability'],
  backend: ['update profiles', 'profile_skills', 'availability_slots'],
);

List<NavItem> get allNavItems => {
      for (final s in [...studentNav, ...adminNav]) ...s.items,
    }.toList();

NavItem? navItemFor(String location) {
  NavItem? best;
  for (final item in allNavItems) {
    if (location == item.path || location.startsWith('${item.path}/')) {
      if (best == null || item.path.length > best.path.length) best = item;
    }
  }
  return best;
}
