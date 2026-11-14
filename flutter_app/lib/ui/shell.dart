import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/formatters.dart';
import '../core/permissions.dart';
import '../state/app_state.dart';
import 'administration_screen.dart';
import 'bookings_screen.dart';
import 'clients_screen.dart';
import 'dashboard_screen.dart';
import 'followups_screen.dart';
import 'payments_screen.dart';
import 'placements_screen.dart';
import 'replacements_screen.dart';
import 'services_screen.dart';
import 'sync_screen.dart';
import 'widgets.dart';
import 'workers_screen.dart';

class ShellScreen extends StatefulWidget {
  const ShellScreen({super.key});

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  String _section = 'dashboard';

  void _open(String section) {
    setState(() => _section = section);
    if (_scaffoldKey.currentState?.isDrawerOpen == true) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final sections = Permissions.sectionsFor(app.user);
    final selected = sections.contains(_section)
        ? _section
        : (sections.isEmpty ? 'dashboard' : sections.first);
    final wide = MediaQuery.sizeOf(context).width >= 980;

    final content = _sectionFor(selected, app);

    return Scaffold(
      key: _scaffoldKey,
      drawer: wide ? null : Drawer(child: _NavigationList(
        sections: sections,
        selected: selected,
        onSelected: _open,
        header: _DrawerHeader(app: app),
      )),
      appBar: AppBar(
        leading: wide
            ? null
            : IconButton(
                icon: const Icon(Icons.menu),
                tooltip: 'Menu',
                onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(Permissions.sectionLabel(selected)),
            Text(
              app.user == null
                  ? ''
                  : '${app.user!.displayName} · ${Permissions.roleLabel(app.user!.role)}',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                color: Colors.black.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
        actions: [
          _SyncActionChip(onPressed: () => _open('sync')),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Sync now',
            onPressed: app.syncing ? null : () => app.syncNow(),
            icon: app.syncing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
          PopupMenuButton<String>(
            tooltip: 'Account',
            icon: const Icon(Icons.account_circle_outlined),
            onSelected: (value) {
              if (value == 'sync') _open('sync');
              if (value == 'signout') app.signOut();
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'profile',
                enabled: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      app.user?.displayName ?? '',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      '${Permissions.roleLabel(app.user?.role ?? '')}'
                      '${app.offlineMode ? ' · offline' : ''}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'sync',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.sync),
                  title: Text('Offline & sync'),
                ),
              ),
              const PopupMenuItem(
                value: 'signout',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.logout),
                  title: Text('Sign out'),
                ),
              ),
            ],
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Column(
        children: [
          OfflineBanner(onOpenSync: () => _open('sync')),
          if (app.notice != null) _NoticeBar(app: app),
          Expanded(
            child: wide
                ? Row(
                    children: [
                      NavigationRail(
                        extended: MediaQuery.sizeOf(context).width >= 1280,
                        selectedIndex: sections.indexOf(selected),
                        onDestinationSelected: (index) => _open(sections[index]),
                        labelType: MediaQuery.sizeOf(context).width >= 1280
                            ? NavigationRailLabelType.none
                            : NavigationRailLabelType.all,
                        destinations: [
                          for (final section in sections)
                            NavigationRailDestination(
                              icon: Icon(_iconFor(section)),
                              label: Text(Permissions.sectionLabel(section)),
                            ),
                        ],
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(child: content),
                    ],
                  )
                : content,
          ),
        ],
      ),
    );
  }

  Widget _sectionFor(String section, AppState app) {
    switch (section) {
      case 'workers':
        return const WorkersScreen();
      case 'clients':
        return const ClientsScreen();
      case 'bookings':
        return const BookingsScreen();
      case 'placements':
        return const PlacementsScreen();
      case 'followups':
        return const FollowUpsScreen();
      case 'replacements':
        return const ReplacementsScreen();
      case 'payments':
        return const PaymentsScreen();
      case 'services':
        return const ServicesScreen();
      case 'sync':
        return const SyncScreen();
      case 'administration':
        return const AdministrationScreen();
      case 'dashboard':
      default:
        return DashboardScreen(onNavigate: _open);
    }
  }
}

IconData _iconFor(String section) {
  switch (section) {
    case 'workers':
      return Icons.badge_outlined;
    case 'clients':
      return Icons.home_work_outlined;
    case 'bookings':
      return Icons.event_note_outlined;
    case 'placements':
      return Icons.handshake_outlined;
    case 'followups':
      return Icons.support_agent_outlined;
    case 'replacements':
      return Icons.swap_horiz_outlined;
    case 'payments':
      return Icons.payments_outlined;
    case 'services':
      return Icons.cleaning_services_outlined;
    case 'sync':
      return Icons.sync_outlined;
    case 'administration':
      return Icons.admin_panel_settings_outlined;
    case 'dashboard':
    default:
      return Icons.space_dashboard_outlined;
  }
}

class _NavigationList extends StatelessWidget {
  const _NavigationList({
    required this.sections,
    required this.selected,
    required this.onSelected,
    required this.header,
  });

  final List<String> sections;
  final String selected;
  final ValueChanged<String> onSelected;
  final Widget header;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          header,
          const Divider(height: 8),
          for (final section in sections)
            ListTile(
              selected: section == selected,
              leading: Icon(_iconFor(section)),
              title: Text(Permissions.sectionLabel(section)),
              onTap: () => onSelected(section),
            ),
        ],
      ),
    );
  }
}

class _DrawerHeader extends StatelessWidget {
  const _DrawerHeader({required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 16),
      child: Row(
        children: [
          AvatarCircle(name: app.user?.displayName ?? '?', size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  app.user?.displayName ?? '',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  Permissions.roleLabel(app.user?.role ?? ''),
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SyncActionChip extends StatelessWidget {
  const _SyncActionChip({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final conflicts = app.conflictCount;
    final pending = app.pendingCount;
    final offline = app.offlineMode || !app.online;

    final icon = conflicts > 0
        ? Icons.sync_problem
        : offline
            ? Icons.cloud_off
            : app.syncing
                ? Icons.sync
                : Icons.cloud_done;
    final label = conflicts > 0
        ? '$conflicts conflict${conflicts == 1 ? '' : 's'}'
        : pending > 0
            ? '$pending queued'
            : offline
                ? 'Offline'
                : Fmt.relative(app.lastSyncAt);

    return Tooltip(
      message: 'Offline & sync',
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: conflicts > 0
                ? const Color(0xFFFFF2D8)
                : const Color(0xFFE8F6F5),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 16,
                color: conflicts > 0
                    ? const Color(0xFF8A5A00)
                    : const Color(0xFF075B63),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: conflicts > 0
                      ? const Color(0xFF8A5A00)
                      : const Color(0xFF075B63),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoticeBar extends StatelessWidget {
  const _NoticeBar({required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFEFF3FB),
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 17, color: Color(0xFF2C3E66)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              app.notice!,
              style: const TextStyle(fontSize: 12.5, color: Color(0xFF2C3E66)),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close, size: 18),
            onPressed: app.dismissNotice,
          ),
        ],
      ),
    );
  }
}
