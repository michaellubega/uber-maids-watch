import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/formatters.dart';
import '../core/models.dart';
import '../state/app_state.dart';
import 'widgets.dart';

class SyncScreen extends StatelessWidget {
  const SyncScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final padding = pagePadding(context);
    final db = app.database;
    final pending = db?.pendingMutations ?? const <OutboxMutation>[];
    final conflicts = app.conflicts;
    final rejected = app.rejectedMutations;

    return ListView(
      padding: EdgeInsets.all(padding),
      children: [
        SectionHeader(
          title: 'Offline & sync',
          subtitle: app.offlineMode || !app.online
              ? 'Working from the cache on this device. Writes queue until a '
                  'connection returns.'
              : 'Connected to ${app.baseUrl}',
          action: FilledButton.icon(
            onPressed: app.syncing ? null : () => _sync(context, app),
            icon: app.syncing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.sync, size: 18),
            label: Text(app.syncing ? 'Syncing…' : 'Sync now'),
          ),
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _StatusRow(
                  icon: app.offlineMode || !app.online
                      ? Icons.cloud_off_outlined
                      : Icons.cloud_done_outlined,
                  label: 'Connection',
                  value: app.offlineMode || !app.online
                      ? 'Offline — cache in use'
                      : 'Online',
                  tone: app.offlineMode || !app.online
                      ? PillTone.warning
                      : PillTone.success,
                ),
                const Divider(height: 18),
                _StatusRow(
                  icon: Icons.schedule,
                  label: 'Last successful sync',
                  value: app.lastSyncAt == null
                      ? 'Never on this device'
                      : '${Fmt.dateTime(app.lastSyncAt)} '
                          '(${Fmt.relative(app.lastSyncAt)})',
                  tone: PillTone.neutral,
                ),
                const Divider(height: 18),
                _StatusRow(
                  icon: Icons.upload_outlined,
                  label: 'Writes waiting to upload',
                  value: '${app.pendingCount}',
                  tone: app.pendingCount > 0 ? PillTone.warning : PillTone.success,
                ),
                const Divider(height: 18),
                _StatusRow(
                  icon: Icons.sync_problem,
                  label: 'Conflicts to review',
                  value: '${app.conflictCount}',
                  tone: app.conflictCount > 0 ? PillTone.danger : PillTone.success,
                ),
                if (app.lastSyncError != null) ...[
                  const Divider(height: 18),
                  _StatusRow(
                    icon: Icons.error_outline,
                    label: 'Last sync message',
                    value: app.lastSyncError!,
                    tone: PillTone.danger,
                  ),
                ],
              ],
            ),
          ),
        ),
        if (conflicts.isNotEmpty) ...[
          const SizedBox(height: 20),
          const SectionHeader(
            title: 'Conflicts',
            subtitle: 'These records changed on another device. Choose which '
                'version to keep.',
          ),
          const SizedBox(height: 10),
          for (final mutation in conflicts)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _ConflictCard(app: app, mutation: mutation),
            ),
        ],
        if (pending.isNotEmpty) ...[
          const SizedBox(height: 20),
          SectionHeader(
            title: 'Waiting to upload',
            subtitle: '${pending.length} change'
                '${pending.length == 1 ? '' : 's'} saved on this device.',
          ),
          const SizedBox(height: 10),
          for (final mutation in pending.take(20))
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _MutationRow(
                mutation: mutation,
                trailing: Text(
                  Fmt.relative(mutation.createdAt),
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Colors.black.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ),
        ],
        if (rejected.isNotEmpty) ...[
          const SizedBox(height: 20),
          const SectionHeader(
            title: 'Rejected by the server',
            subtitle: 'Fix the record and retry, or discard the local change.',
          ),
          const SizedBox(height: 10),
          for (final mutation in rejected)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _MutationRow(
                        mutation: mutation,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextButton(
                              onPressed: () => app.retryMutation(mutation.mutationId),
                              child: const Text('Retry'),
                            ),
                            TextButton(
                              onPressed: () => app.discardMutation(mutation.mutationId),
                              child: const Text('Discard'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        mutation.error ?? 'The server rejected this change.',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: Colors.black.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
        const SizedBox(height: 20),
        const SectionHeader(
          title: 'What is stored on this device',
          subtitle: 'Only records your role may see are cached. Signing out '
              'never deletes them.',
        ),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 22,
              runSpacing: 12,
              children: [
                for (final entry in const {
                  'worker': 'Workers',
                  'client': 'Clients',
                  'service': 'Services',
                  'booking': 'Bookings',
                  'placement': 'Placements',
                  'follow_up': 'Follow-ups',
                  'replacement_case': 'Replacements',
                  'payment': 'Payments',
                }.entries)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${app.count(entry.key)}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        entry.value,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Colors.black.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        const SectionHeader(
          title: 'Device controls',
          subtitle: 'Use these when a device is shared, lost or handed over.',
        ),
        const SizedBox(height: 10),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.dns_outlined),
                title: const Text('Server address'),
                subtitle: Text(app.baseUrl),
                trailing: const Icon(Icons.lock_outline, size: 18),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.cleaning_services_outlined),
                title: const Text('Clear cached records'),
                subtitle: const Text(
                  'Removes the offline copy. Pending writes are discarded and '
                  'the cache is rebuilt from the server.',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _clearCache(context, app),
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(
                  Icons.phonelink_erase_outlined,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(
                  'Forget this device',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                subtitle: const Text(
                  'Clears the cache and signs out. The offline copy cannot be '
                  'recovered without signing in online again.',
                ),
                onTap: () => _forgetDevice(context, app),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Card(
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
                        'Actions that need a connection',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Verification, booking confirmation, follow-up completion, '
                        'placement and replacement decisions are checked by the '
                        'server. User administration and the audit trail also live '
                        'only on the server. These are never queued offline because '
                        'the outcome depends on current server state. Recording a '
                        'payment, by contrast, is saved on the device and uploaded '
                        'by the outbox.',
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
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  Future<void> _sync(BuildContext context, AppState app) async {
    final outcome = await app.syncNow();
    if (!context.mounted || outcome == null) return;
    showAppMessage(
      context,
      outcome.summary,
      error: !outcome.succeeded,
    );
  }

  Future<void> _clearCache(BuildContext context, AppState app) async {
    final confirmed = await confirmAction(
      context,
      title: 'Clear cached records?',
      message: 'Any writes that have not reached the server will be discarded. '
          'The cache is rebuilt on the next sync.',
      confirmLabel: 'Clear cache',
      destructive: true,
    );
    if (!confirmed) return;
    await app.clearCachedData();
    if (context.mounted) showAppMessage(context, 'Cache cleared.');
  }

  Future<void> _forgetDevice(BuildContext context, AppState app) async {
    final confirmed = await confirmAction(
      context,
      title: 'Forget this device?',
      message: 'The offline copy will be deleted and you will be signed out. '
          'You can sign in again later.',
      confirmLabel: 'Forget device',
      destructive: true,
    );
    if (!confirmed) return;
    await app.forgetDevice();
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.tone,
  });

  final IconData icon;
  final String label;
  final String value;
  final PillTone tone;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Colors.black.withValues(alpha: 0.5)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.black.withValues(alpha: 0.5),
                ),
              ),
              const SizedBox(height: 2),
              Text(value, style: const TextStyle(fontSize: 13.5, height: 1.35)),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: switch (tone) {
              PillTone.success => const Color(0xFF17663A),
              PillTone.warning => const Color(0xFF9A6200),
              PillTone.danger => const Color(0xFF9B1C1C),
              PillTone.info => const Color(0xFF075B63),
              PillTone.neutral => const Color(0xFFBDB8C9),
            },
            shape: BoxShape.circle,
          ),
        ),
      ],
    );
  }
}

class _MutationRow extends StatelessWidget {
  const _MutationRow({required this.mutation, required this.trailing});

  final OutboxMutation mutation;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            AvatarCircle(
              name: Fmt.labelize(mutation.entity),
              size: 34,
              color: const Color(0xFF075B63),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${Fmt.labelize(mutation.entity)} · '
                    '${mutation.operation == 'delete' ? 'delete' : 'update'}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    '#${mutation.id.length >= 8 ? mutation.id.substring(0, 8) : mutation.id}'
                    ' · base version ${mutation.baseVersion}',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Colors.black.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
            trailing,
          ],
        ),
      ),
    );
  }
}

class _ConflictCard extends StatelessWidget {
  const _ConflictCard({required this.app, required this.mutation});

  final AppState app;
  final OutboxMutation mutation;

  @override
  Widget build(BuildContext context) {
    final server = mutation.serverRecord;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.sync_problem, size: 18, color: Color(0xFF9B1C1C)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${Fmt.labelize(mutation.entity)} · '
                    '#${mutation.id.length >= 8 ? mutation.id.substring(0, 8) : mutation.id}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                const StatusPill(label: 'CONFLICT', tone: PillTone.danger),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              mutation.error ?? 'This record changed on another device.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: Colors.black.withValues(alpha: 0.6),
              ),
            ),
            if (server != null) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F6F6),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Server version '
                      '${server['server_version'] ?? mutation.baseVersion}',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _summary(server),
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.4,
                        color: Colors.black.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () => app.resolveKeepMine(mutation.mutationId),
                  icon: const Icon(Icons.phone_android, size: 17),
                  label: const Text('Keep this device'),
                ),
                OutlinedButton.icon(
                  onPressed: server == null
                      ? null
                      : () => app.resolveUseServer(mutation.mutationId),
                  icon: const Icon(Icons.cloud_download_outlined, size: 17),
                  label: const Text('Use server copy'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _summary(Map<String, dynamic> record) {
    final parts = <String>[];
    for (final key in const [
      'full_name',
      'name',
      'client_name',
      'worker_name',
      'status',
      'amount_ugx',
      'description',
    ]) {
      final value = record[key];
      if (value == null || '$value'.trim().isEmpty) continue;
      parts.add('${Fmt.labelize(key)}: $value');
      if (parts.length >= 3) break;
    }
    if (record['deleted_at'] != null) parts.add('Deleted on the server');
    return parts.isEmpty ? 'No preview available.' : parts.join(' · ');
  }
}
