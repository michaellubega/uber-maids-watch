import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/formatters.dart';
import '../core/permissions.dart';
import '../state/app_state.dart';
import 'widgets.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key, required this.onNavigate});

  final ValueChanged<String> onNavigate;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final user = app.user;
    if (user == null) return const SizedBox.shrink();

    final isFamily = user.role == 'FAMILY';
    final isMaid = user.role == 'MAID';
    final padding = pagePadding(context);
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 17
            ? 'Good afternoon'
            : 'Good evening';

    final kpis = <Widget>[];
    if (isFamily) {
      final bookings = app.rows('booking');
      final placements = app.rows('placement');
      final payments = app.rows('payment');
      kpis.addAll([
        KpiCard(
          title: 'Open requests',
          value:
              '${bookings.where((row) => !const {'CANCELLED', 'CLOSED', 'CONVERTED'}.contains(row['status'])).length}',
          subtitle: 'Bookings in progress',
          icon: Icons.event_note_outlined,
          onTap: () => onNavigate('bookings'),
        ),
        KpiCard(
          title: 'Active placements',
          value: '${placements.where((row) => row['status'] == 'ACTIVE').length}',
          subtitle: 'Workers currently with you',
          icon: Icons.handshake_outlined,
          tone: PillTone.success,
          onTap: () => onNavigate('placements'),
        ),
        KpiCard(
          title: 'Payments due',
          value:
              '${payments.where((row) => const {'PENDING', 'PARTIAL'}.contains(row['status'])).length}',
          subtitle: 'Awaiting settlement',
          icon: Icons.payments_outlined,
          tone: PillTone.warning,
          onTap: () => onNavigate('payments'),
        ),
        KpiCard(
          title: 'Open replacements',
          value:
              '${app.rows('replacement_case').where((row) => const {'OPEN', 'REVIEWING'}.contains(row['status'])).length}',
          subtitle: 'Support requests',
          icon: Icons.swap_horiz_outlined,
          tone: PillTone.danger,
          onTap: () => onNavigate('replacements'),
        ),
      ]);
    } else if (isMaid) {
      final worker = app.myWorker;
      final placements = app.rows('placement');
      final followUps = app.rows('follow_up');
      kpis.addAll([
        KpiCard(
          title: 'My status',
          value: Fmt.labelize(worker?['status'], fallback: 'Unknown'),
          subtitle: 'Current availability',
          icon: Icons.badge_outlined,
          tone: PillTone.info,
          onTap: () => onNavigate('workers'),
        ),
        KpiCard(
          title: 'Verification',
          value: Fmt.labelize(worker?['verification_status'], fallback: 'Pending'),
          subtitle: 'Profile checks',
          icon: Icons.verified_user_outlined,
          tone: worker?['verification_status'] == 'VERIFIED'
              ? PillTone.success
              : PillTone.warning,
          onTap: () => onNavigate('workers'),
        ),
        KpiCard(
          title: 'Active placements',
          value: '${placements.where((row) => row['status'] == 'ACTIVE').length}',
          subtitle: 'Current assignments',
          icon: Icons.handshake_outlined,
          tone: PillTone.success,
          onTap: () => onNavigate('placements'),
        ),
        KpiCard(
          title: 'Follow-ups open',
          value: '${followUps.where(Fmt.isOpenFollowUp).length}',
          subtitle: 'Scheduled check-ins',
          icon: Icons.support_agent_outlined,
          tone: PillTone.warning,
          onTap: () => onNavigate('followups'),
        ),
      ]);
    } else {
      final workers = app.rows('worker');
      final followUps = app.rows('follow_up');
      final payments = app.rows('payment');
      kpis.addAll([
        KpiCard(
          title: 'Workers',
          value: '${workers.length}',
          subtitle: '${workers.where((row) => row['status'] == 'AVAILABLE').length} available',
          icon: Icons.badge_outlined,
          onTap: () => onNavigate('workers'),
        ),
        KpiCard(
          title: 'Awaiting verification',
          value:
              '${workers.where((row) => const {'PENDING', 'IN_PROGRESS'}.contains(row['verification_status'])).length}',
          subtitle: 'Needs attention',
          icon: Icons.verified_user_outlined,
          tone: PillTone.warning,
          onTap: () => onNavigate('workers'),
        ),
        KpiCard(
          title: 'Active placements',
          value:
              '${app.rows('placement').where((row) => row['status'] == 'ACTIVE').length}',
          subtitle: 'Workers with families',
          icon: Icons.handshake_outlined,
          tone: PillTone.success,
          onTap: () => onNavigate('placements'),
        ),
        KpiCard(
          title: 'New bookings',
          value:
              '${app.rows('booking').where((row) => row['status'] == 'NEW').length}',
          subtitle: 'Requests to review',
          icon: Icons.event_note_outlined,
          tone: PillTone.info,
          onTap: () => onNavigate('bookings'),
        ),
        KpiCard(
          title: 'Follow-ups due',
          value:
              '${followUps.where((row) => Fmt.isDueToday(row) || Fmt.isOverdue(row)).length}',
          subtitle: '${followUps.where(Fmt.isOverdue).length} overdue',
          icon: Icons.support_agent_outlined,
          tone: followUps.any(Fmt.isOverdue) ? PillTone.danger : PillTone.warning,
          onTap: () => onNavigate('followups'),
        ),
        KpiCard(
          title: 'Open replacements',
          value:
              '${app.rows('replacement_case').where((row) => const {'OPEN', 'REVIEWING'}.contains(row['status'])).length}',
          subtitle: 'Guarantee cases',
          icon: Icons.swap_horiz_outlined,
          tone: PillTone.danger,
          onTap: () => onNavigate('replacements'),
        ),
        KpiCard(
          title: 'Payments outstanding',
          value:
              '${payments.where((row) => const {'PENDING', 'PARTIAL'}.contains(row['status'])).length}',
          subtitle: 'Pending settlement',
          icon: Icons.payments_outlined,
          tone: PillTone.neutral,
          onTap: () => onNavigate('payments'),
        ),
      ]);
    }

    return ListView(
      padding: EdgeInsets.all(padding),
      children: [
        _GreetingCard(app: app, greeting: greeting),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 1150
                ? 4
                : constraints.maxWidth >= 700
                    ? 2
                    : 1;
            final width =
                (constraints.maxWidth - (columns - 1) * 12) / columns;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final kpi in kpis) SizedBox(width: width, child: kpi),
              ],
            );
          },
        ),
        const SizedBox(height: 22),
        const SectionHeader(
          title: 'Quick actions',
          subtitle: 'Available to your role. Administrator actions need a connection.',
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            if (app.canWrite('bookings') && !isMaid)
              _QuickAction(
                icon: Icons.add_circle_outline,
                label: isFamily ? 'Request a worker' : 'New booking',
                onTap: () => onNavigate('bookings'),
              ),
            if (app.canWrite('replacements') && !isMaid)
              _QuickAction(
                icon: Icons.swap_horiz,
                label: isFamily ? 'Request replacement' : 'Open replacement',
                onTap: () => onNavigate('replacements'),
              ),
            if (app.canWrite('workers'))
              _QuickAction(
                icon: Icons.person_add_alt,
                label: 'Register worker',
                onTap: () => onNavigate('workers'),
              ),
            if (app.canWrite('clients'))
              _QuickAction(
                icon: Icons.home_work_outlined,
                label: 'Add client',
                onTap: () => onNavigate('clients'),
              ),
            if (app.canWrite('followups'))
              _QuickAction(
                icon: Icons.support_agent_outlined,
                label: 'Schedule follow-up',
                onTap: () => onNavigate('followups'),
              ),
            if (app.canWrite('payments'))
              _QuickAction(
                icon: Icons.receipt_long_outlined,
                label: 'Record payment',
                onTap: () => onNavigate('payments'),
              ),
            _QuickAction(
              icon: Icons.sync,
              label: 'Offline & sync',
              onTap: () => onNavigate('sync'),
            ),
          ],
        ),
        const SizedBox(height: 24),
        _AttentionList(app: app, onNavigate: onNavigate),
        const SizedBox(height: 22),
        _PolicyNotice(app: app),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _GreetingCard extends StatelessWidget {
  const _GreetingCard({required this.app, required this.greeting});

  final AppState app;
  final String greeting;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF053F45), Color(0xFF075B63), Color(0xFF079DA5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$greeting, ${app.user?.displayName ?? ''}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '${Permissions.roleLabel(app.user?.role ?? '')} · '
                  '${app.myClient != null ? '${textOf(app.myClient, 'client_number')} · ' : ''}'
                  '${app.myWorker != null ? '${textOf(app.myWorker, 'worker_number')} · ' : ''}'
                  '${app.offlineMode ? 'working offline' : 'connected'}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.78),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Icon(Icons.shield_moon_outlined, color: scheme.primaryContainer, size: 30),
              const SizedBox(height: 8),
              Text(
                app.lastSyncAt == null
                    ? 'Not synced yet'
                    : 'Synced ${Fmt.relative(app.lastSyncAt)}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.65),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String textOf(Map<String, dynamic>? row, String key) =>
    row?[key]?.toString() ?? '';

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }
}

class _AttentionList extends StatelessWidget {
  const _AttentionList({required this.app, required this.onNavigate});

  final AppState app;
  final ValueChanged<String> onNavigate;

  @override
  Widget build(BuildContext context) {
    final overdue = app
        .rows('follow_up')
        .where(Fmt.isOverdue)
        .toList()
      ..sort((a, b) => '${a['due_date']}'.compareTo('${b['due_date']}'));
    final replacements = app
        .rows('replacement_case')
        .where((row) => const {'OPEN', 'REVIEWING'}.contains(row['status']))
        .toList();

    if (overdue.isEmpty && replacements.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            title: 'Needs attention',
            subtitle: 'Nothing overdue in the cached records.',
          ),
          const SizedBox(height: 10),
          EmptyState(
            icon: Icons.task_alt,
            title: 'All caught up',
            message: app.offlineMode
                ? 'This is based on the data cached on this device.'
                : 'There are no overdue follow-ups or open replacement cases.',
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(
          title: 'Needs attention',
          subtitle: 'Overdue check-ins and open guarantee cases.',
        ),
        const SizedBox(height: 10),
        for (final followUp in overdue.take(4))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: RecordCard(
              title: 'Follow-up overdue · ${Fmt.date(followUp['due_date'])}',
              subtitle: '${textOf(followUp, 'client_name')} · '
                  '${textOf(followUp, 'placement_number')}',
              leading: const AvatarCircle(
                name: 'FU',
                size: 38,
                color: Color(0xFF9B1C1C),
              ),
              trailing: const StatusPill(label: 'OVERDUE', tone: PillTone.danger),
              onTap: () => onNavigate('followups'),
            ),
          ),
        for (final replacement in replacements.take(4))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: RecordCard(
              title: '${textOf(replacement, 'case_number')} · '
                  '${Fmt.labelize(replacement['problem_category'])}',
              subtitle: '${textOf(replacement, 'client_name')} · '
                  '${textOf(replacement, 'placement_number')}',
              leading: const AvatarCircle(
                name: 'RC',
                size: 38,
                color: Color(0xFF075B63),
              ),
              trailing: StatusPill(label: '${replacement['status']}'),
              onTap: () => onNavigate('replacements'),
            ),
          ),
      ],
    );
  }
}

class _PolicyNotice extends StatelessWidget {
  const _PolicyNotice({required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFFFFFBF0),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.gavel_outlined, size: 19, color: Color(0xFF8A5A00)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Policies awaiting owner confirmation',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    AppState.pendingBusinessRules.join(' · '),
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.45,
                      color: Colors.black.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
