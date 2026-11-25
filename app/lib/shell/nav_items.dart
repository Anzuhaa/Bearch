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
      path: '/invites',
      label: 'Invites',
      icon: Icons.mail_outline_rounded,
      plan: ['Pending invites with 48h countdown', 'Accept / decline', 'My join requests (cancel)'],
      backend: ['select team_invites / join_requests', 'rpc respond_invite / cancel_join_request'],
    ),
  ]),
  NavSection('My Team', [
    NavItem(
      path: '/teams',
      label: 'My Teams',
      icon: Icons.groups_rounded,
      figma: ['06 Lobby', '09 Team Locked', '10 Team Calendar', '11 Team Chat', '12 Rate', '13 SEP'],
      plan: ['Pick a team, then open its hub: lobby & members, chat, calendar, rate & SEP, report'],
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
